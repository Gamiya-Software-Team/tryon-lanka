//  TRYON LANKA - live on-device virtual try-on.
//
//  Privacy: camera frames are processed only on this phone by Google ML Kit
//  Pose Detection (bundled model). Nothing is recorded or uploaded. A preview
//  photo is created only when the user taps capture, and leaves the phone only
//  if the user taps share.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '/app/tryon/garment_calibration.dart';
import '/app/tryon/garment_painter.dart';
import '/app/tryon/pose_fit.dart';

/// One garment the user can switch to inside the try-on screen.
class TryOnItem {
  const TryOnItem({
    required this.title,
    required this.calibration,
    this.thumbnailUrl,
    this.demoColor = const Color(0xFF2F4A6D),
  });
  final String title;
  final GarmentCalibration calibration;
  final String? thumbnailUrl;
  final Color demoColor;

  static List<TryOnItem> demoItems() => const [
        TryOnItem(
            title: 'Classic Black Tee',
            demoColor: Color(0xFF111111),
            calibration: GarmentCalibration(enabled: true)),
        TryOnItem(
            title: 'Cream Tee',
            demoColor: Color(0xFFF7F5F0),
            calibration: GarmentCalibration(enabled: true)),
        TryOnItem(
            title: 'Gold Tee',
            demoColor: Color(0xFFC8A878),
            calibration: GarmentCalibration(enabled: true)),
        TryOnItem(
            title: 'Blue Oxford Shirt',
            demoColor: Color(0xFF8FA9C8),
            calibration: GarmentCalibration(
                enabled: true,
                type: GarmentType.shirt,
                widthRatio: 2.0,
                heightRatio: 1.55)),
      ];
}

/// Shows the privacy notice, then opens the live try-on.
Future<void> openTryOn(BuildContext context, List<TryOnItem> items,
    {int initialIndex = 0}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.privacy_tip_outlined, size: 36),
            const SizedBox(height: 12),
            Text(trans('Camera privacy'),
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(trans('tryon_privacy_body')),
            const SizedBox(height: 8),
            Text(trans('tryon_disclaimer'),
                style: Theme.of(ctx)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.grey[600])),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF111111),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(trans('Continue to camera')),
              ),
            ),
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(trans('Cancel'))),
          ],
        ),
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => TryOnPage(items: items, initialIndex: initialIndex)));
}

class TryOnPage extends StatefulWidget {
  const TryOnPage({super.key, required this.items, this.initialIndex = 0});
  final List<TryOnItem> items;
  final int initialIndex;

  @override
  State<TryOnPage> createState() => _TryOnPageState();
}

class _TryOnPageState extends State<TryOnPage> with WidgetsBindingObserver {
  static const _orientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  final _boundaryKey = GlobalKey();
  final _smoother = PlacementSmoother();
  late final PoseDetector _detector = PoseDetector(
      options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream, model: PoseDetectionModel.base));

  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _busy = false;
  bool _starting = false;
  int _frame = 0;
  int _skip = 1; // process every (_skip + 1)th frame, adapts to device speed
  String? _error;

  Size? _imageSize;
  InputImageRotation _rotation = InputImageRotation.rotation0deg;
  Pose? _lastPose;
  GarmentPlacement? _placement;
  bool _bodyVisible = false;

  late int _itemIndex = widget.initialIndex.clamp(0, widget.items.length - 1);
  ui.Image? _garmentImage;
  String? _garmentImageUrl;

  TryOnItem get _item => widget.items[_itemIndex];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadGarment();
    _initCameras();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopCamera();
    _detector.close();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _stopCamera();
    } else if (state == AppLifecycleState.resumed && _controller == null) {
      _startCamera();
    }
  }

  Future<void> _initCameras() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        setState(() => _error = trans('No camera found on this device'));
        return;
      }
      final front = _cameras
          .indexWhere((c) => c.lensDirection == CameraLensDirection.front);
      _cameraIndex = front >= 0 ? front : 0;
      await _startCamera();
    } catch (e) {
      setState(() => _error = trans('Camera could not be opened'));
    }
  }

  Future<void> _startCamera() async {
    if (_starting || _cameras.isEmpty || !mounted) return;
    _starting = true;
    final controller = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.medium, // adaptive: medium keeps inference fast
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      _controller = controller;
      _smoother.reset();
      await controller.startImageStream(_onFrame);
      setState(() => _error = null);
    } on CameraException catch (e) {
      await controller.dispose();
      setState(() => _error = e.code == 'CameraAccessDenied'
          ? trans('Camera permission was denied')
          : trans('Camera could not be opened'));
    } finally {
      _starting = false;
    }
  }

  Future<void> _stopCamera() async {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    try {
      if (c.value.isStreamingImages) await c.stopImageStream();
    } catch (_) {}
    await c.dispose();
    if (mounted) setState(() {});
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2) return;
    await _stopCamera();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _startCamera();
  }

  void _onFrame(CameraImage image) {
    _frame++;
    if (_busy || _frame % (_skip + 1) != 0) return; // no concurrent inference
    final input = _toInputImage(image);
    if (input == null) return;
    _busy = true;
    final sw = Stopwatch()..start();
    _detector.processImage(input).then((poses) {
      sw.stop();
      // Adaptive frame skipping for slower phones.
      if (sw.elapsedMilliseconds > 90 && _skip < 3) _skip++;
      if (sw.elapsedMilliseconds < 40 && _skip > 0) _skip--;
      if (!mounted) return;
      setState(() {
        _imageSize = Size(image.width.toDouble(), image.height.toDouble());
        _rotation = input.metadata!.rotation;
        _lastPose = poses.isEmpty ? null : poses.first;
      });
    }).catchError((Object e) {
      if (kDebugMode) debugPrint('pose error: $e');
    }).whenComplete(() => _busy = false);
  }

  InputImage? _toInputImage(CameraImage image) {
    final controller = _controller;
    if (controller == null) return null;
    final camera = _cameras[_cameraIndex];
    final sensor = camera.sensorOrientation;
    InputImageRotation? rotation;
    if (Platform.isIOS) {
      rotation = InputImageRotationValue.fromRawValue(sensor);
    } else {
      var comp = _orientations[controller.value.deviceOrientation];
      if (comp == null) return null;
      comp = camera.lensDirection == CameraLensDirection.front
          ? (sensor + comp) % 360
          : (sensor - comp + 360) % 360;
      rotation = InputImageRotationValue.fromRawValue(comp);
    }
    if (rotation == null) return null;
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  // Map an ML Kit landmark to the preview canvas (same maths as the ML Kit
  // Flutter example, so mirroring matches the front-camera preview).
  Offset _map(double x, double y, Size canvas) {
    final img = _imageSize!;
    final front =
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
    double tx, ty;
    switch (_rotation) {
      case InputImageRotation.rotation90deg:
        tx = x * canvas.width / (Platform.isIOS ? img.width : img.height);
        ty = y * canvas.height / (Platform.isIOS ? img.height : img.width);
        break;
      case InputImageRotation.rotation270deg:
        tx = canvas.width -
            x * canvas.width / (Platform.isIOS ? img.width : img.height);
        ty = y * canvas.height / (Platform.isIOS ? img.height : img.width);
        break;
      default:
        tx = x * canvas.width / img.width;
        if (front) tx = canvas.width - tx;
        ty = y * canvas.height / img.height;
    }
    return Offset(tx, ty);
  }

  GarmentPlacement? _computePlacement(Size canvas) {
    final pose = _lastPose;
    if (pose == null || _imageSize == null) return _smoother.update(null);
    BodyPoint? p(PoseLandmarkType t) {
      final l = pose.landmarks[t];
      if (l == null) return null;
      final o = _map(l.x, l.y, canvas);
      return BodyPoint(o.dx, o.dy, l.likelihood);
    }

    final raw = PoseFit.compute(
      leftShoulder: p(PoseLandmarkType.leftShoulder),
      rightShoulder: p(PoseLandmarkType.rightShoulder),
      leftHip: p(PoseLandmarkType.leftHip),
      rightHip: p(PoseLandmarkType.rightHip),
      calibration: _item.calibration,
      garmentAspect: _garmentImage == null
          ? null
          : _garmentImage!.height / _garmentImage!.width,
    );
    return _smoother.update(raw);
  }

  Future<void> _loadGarment() async {
    final cal = _item.calibration;
    if (!cal.hasGarmentAsset) {
      setState(() {
        _garmentImage = null;
        _garmentImageUrl = null;
      });
      return;
    }
    final url = cal.garmentUrl!;
    if (url == _garmentImageUrl && _garmentImage != null) return;
    _garmentImageUrl = url;
    // CachedNetworkImageProvider keeps the cutout on disk, so try-on keeps
    // working offline once the garment has been downloaded.
    final provider = CachedNetworkImageProvider(url);
    final stream = provider.resolve(const ImageConfiguration());
    final completer = Completer<ui.Image?>();
    late ImageStreamListener listener;
    listener = ImageStreamListener((info, _) {
      completer.complete(info.image);
      stream.removeListener(listener);
    }, onError: (e, _) {
      completer.complete(null);
      stream.removeListener(listener);
    });
    stream.addListener(listener);
    final img = await completer.future;
    if (!mounted || _garmentImageUrl != url) return;
    setState(() => _garmentImage = img);
    if (img == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(trans('Garment image unavailable, showing preview'))));
    }
  }

  Future<void> _capture() async {
    try {
      final boundary = _boundaryKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null || !mounted) return;
      final bytes = data.buffer.asUint8List();
      await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => TryOnCapturePreviewPage(pngBytes: bytes)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(trans('Could not capture preview'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: _error != null
                  ? _ErrorView(message: _error!, onRetry: _initCameras)
                  : controller == null || !controller.value.isInitialized
                      ? const Center(
                          child: CircularProgressIndicator(color: Colors.white))
                      : Center(
                          child: RepaintBoundary(
                            key: _boundaryKey,
                            child: AspectRatio(
                              aspectRatio: 1 / controller.value.aspectRatio,
                              child: LayoutBuilder(builder: (context, box) {
                                final size = box.biggest;
                                _placement = _computePlacement(size);
                                _bodyVisible = _placement != null;
                                return Stack(fit: StackFit.expand, children: [
                                  CameraPreview(controller),
                                  CustomPaint(
                                    painter: GarmentPainter(
                                      placement: _placement,
                                      image: _garmentImage,
                                      type: _item.calibration.type,
                                      color: _item.demoColor,
                                    ),
                                  ),
                                ]);
                              }),
                            ),
                          ),
                        ),
            ),
            // Top bar
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: Row(
                children: [
                  _RoundButton(
                    icon: Icons.close,
                    tooltip: trans('Stop camera'),
                    onTap: () async {
                      await _stopCamera();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20)),
                    child: Row(children: [
                      const Icon(Icons.lock_outline,
                          color: Color(0xFFC8A878), size: 16),
                      const SizedBox(width: 6),
                      Text(trans('Processed on this phone'),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ]),
                  ),
                  const Spacer(),
                  if (_cameras.length > 1)
                    _RoundButton(
                        icon: Icons.cameraswitch_outlined,
                        tooltip: trans('Switch camera'),
                        onTap: _switchCamera),
                ],
              ),
            ),
            if (_error == null && controller != null && !_bodyVisible)
              Positioned(
                top: 70,
                left: 24,
                right: 24,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12)),
                  child: Text(trans('tryon_step_back'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white)),
                ),
              ),
            // Bottom garment picker + capture
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Column(
                children: [
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.items.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final it = widget.items[i];
                        final selected = i == _itemIndex;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _itemIndex = i;
                              _smoother.reset();
                            });
                            _loadGarment();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 68,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                  color: selected
                                      ? const Color(0xFFC8A878)
                                      : Colors.transparent,
                                  width: 3),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: it.thumbnailUrl != null
                                ? CachedNetworkImage(
                                    imageUrl: it.thumbnailUrl!,
                                    fit: BoxFit.cover,
                                    errorWidget: (_, __, ___) =>
                                        Icon(Icons.checkroom, color: it.demoColor))
                                : Icon(Icons.checkroom,
                                    color: it.demoColor, size: 40),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: controller == null ? null : _capture,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: const DecoratedBox(
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFFC8A878))),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton(
      {required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black54,
        shape: const CircleBorder(),
        child: IconButton(
            tooltip: tooltip,
            icon: Icon(icon, color: Colors.white),
            onPressed: onTap),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.videocam_off_outlined,
                color: Colors.white, size: 48),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 16),
            OutlinedButton(
                onPressed: onRetry,
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: Text(trans('Try again'))),
          ]),
        ),
      );
}

/// Shows the captured preview. Saving and sharing happen only on user action.
class TryOnCapturePreviewPage extends StatelessWidget {
  const TryOnCapturePreviewPage({super.key, required this.pngBytes});
  final Uint8List pngBytes;

  Future<File> _writeFile({required bool permanent}) async {
    final dir = permanent
        ? await getApplicationDocumentsDirectory()
        : await getTemporaryDirectory();
    final folder = Directory('${dir.path}/tryon_previews');
    if (!folder.existsSync()) folder.createSync(recursive: true);
    final file = File(
        '${folder.path}/tryon_${DateTime.now().millisecondsSinceEpoch}.png');
    await file.writeAsBytes(pngBytes);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(trans('Try-On preview')),
      ),
      body: Column(children: [
        Expanded(child: Center(child: Image.memory(pngBytes))),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(Icons.download_outlined),
                label: Text(trans('Save')),
                onPressed: () async {
                  await _writeFile(permanent: true);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(trans('Saved on this phone'))));
                  }
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFC8A878),
                    foregroundColor: const Color(0xFF111111),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                icon: const Icon(Icons.share_outlined),
                label: Text(trans('Share')),
                onPressed: () async {
                  final f = await _writeFile(permanent: false);
                  await SharePlus.instance.share(ShareParams(
                      files: [XFile(f.path)], text: 'TRYON LANKA'));
                },
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}
