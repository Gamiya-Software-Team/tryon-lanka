//  TRYON LANKA - pure maths that turns body landmarks into a garment placement.
//  No Flutter/camera imports so it can be unit tested.

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'garment_calibration.dart';

class BodyPoint {
  const BodyPoint(this.x, this.y, this.confidence);
  final double x;
  final double y;
  final double confidence;
  Offset get offset => Offset(x, y);
}

/// Where and how big to draw the garment, in screen (canvas) coordinates.
class GarmentPlacement {
  const GarmentPlacement({
    required this.anchor,
    required this.width,
    required this.height,
    required this.angle,
  });

  /// Top-centre (collar) point of the garment.
  final Offset anchor;
  final double width;
  final double height;

  /// Rotation in radians around [anchor].
  final double angle;

  GarmentPlacement lerpTo(GarmentPlacement next, double t) {
    double l(double a, double b) => a + (b - a) * t;
    return GarmentPlacement(
      anchor: Offset(l(anchor.dx, next.anchor.dx), l(anchor.dy, next.anchor.dy)),
      width: l(width, next.width),
      height: l(height, next.height),
      angle: l(angle, next.angle),
    );
  }
}

class PoseFit {
  static const double minConfidence = 0.5;

  /// Returns null when the shoulders are not confidently visible.
  static GarmentPlacement? compute({
    required BodyPoint? leftShoulder,
    required BodyPoint? rightShoulder,
    BodyPoint? leftHip,
    BodyPoint? rightHip,
    required GarmentCalibration calibration,
    double? garmentAspect, // image height / width, if an image is used
  }) {
    if (leftShoulder == null || rightShoulder == null) return null;
    if (leftShoulder.confidence < minConfidence ||
        rightShoulder.confidence < minConfidence) {
      return null;
    }

    // Order by screen x so mirroring does not flip the garment upside down.
    var a = leftShoulder.offset, b = rightShoulder.offset;
    if (a.dx > b.dx) {
      final tmp = a;
      a = b;
      b = tmp;
    }

    final shoulderMid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    final shoulderWidth = (b - a).distance;
    if (shoulderWidth < 8) return null;

    final bodyAngle = math.atan2(b.dy - a.dy, b.dx - a.dx);

    double torso = shoulderWidth * 1.35;
    final hipsOk = leftHip != null &&
        rightHip != null &&
        leftHip.confidence >= minConfidence &&
        rightHip.confidence >= minConfidence;
    if (hipsOk) {
      final hipMid =
          Offset((leftHip.x + rightHip.x) / 2, (leftHip.y + rightHip.y) / 2);
      final measured = (hipMid - shoulderMid).distance;
      // Reject implausible torso lengths (bad detections).
      if (measured > shoulderWidth * 0.6 && measured < shoulderWidth * 3.5) {
        torso = measured;
      }
    }

    final s = calibration.scale;
    final width = shoulderWidth * calibration.widthRatio * s;
    final height = garmentAspect != null
        ? width * garmentAspect
        : torso * calibration.heightRatio * s;

    final angle = bodyAngle + calibration.rotation * math.pi / 180.0;

    // Offsets are expressed in the garment's own rotated frame.
    final ox = calibration.offsetX * width;
    final oy = calibration.offsetY * height;
    final anchor = shoulderMid +
        Offset(ox * math.cos(angle) - oy * math.sin(angle),
            ox * math.sin(angle) + oy * math.cos(angle));

    return GarmentPlacement(
        anchor: anchor, width: width, height: height, angle: angle);
  }
}

/// Exponential smoothing so the garment does not jitter between frames.
class PlacementSmoother {
  PlacementSmoother({this.alpha = 0.45, this.maxMissedFrames = 6});
  final double alpha;
  final int maxMissedFrames;

  GarmentPlacement? _current;
  int _missed = 0;

  GarmentPlacement? get current => _current;

  GarmentPlacement? update(GarmentPlacement? next) {
    if (next == null) {
      _missed++;
      if (_missed > maxMissedFrames) _current = null;
      return _current;
    }
    _missed = 0;
    _current = _current == null ? next : _current!.lerpTo(next, alpha);
    return _current;
  }

  void reset() {
    _current = null;
    _missed = 0;
  }
}
