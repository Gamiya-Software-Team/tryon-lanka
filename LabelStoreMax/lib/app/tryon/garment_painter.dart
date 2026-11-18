//  TRYON LANKA - paints the garment over the camera preview.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'garment_calibration.dart';
import 'pose_fit.dart';

class GarmentPainter extends CustomPainter {
  GarmentPainter({
    required this.placement,
    required this.image,
    required this.type,
    required this.color,
  });

  final GarmentPlacement? placement;
  final ui.Image? image;
  final GarmentType type;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = placement;
    if (p == null) return;
    canvas.save();
    canvas.translate(p.anchor.dx, p.anchor.dy);
    canvas.rotate(p.angle);
    final rect = Rect.fromLTWH(-p.width / 2, 0, p.width, p.height);
    if (image != null) {
      paintImage(
        canvas: canvas,
        rect: rect,
        image: image!,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.medium,
      );
    } else {
      _paintSilhouette(canvas, rect);
    }
    canvas.restore();
  }

  /// Built-in garment drawn as a vector, used when the product has no
  /// transparent cutout yet (demo mode). Coordinates are in a 0..1 box.
  void _paintSilhouette(Canvas canvas, Rect r) {
    Offset pt(double x, double y) =>
        Offset(r.left + x * r.width, r.top + y * r.height);
    final longSleeve = type == GarmentType.shirt || type == GarmentType.hoodie;
    final sleeveEndY = longSleeve ? 0.80 : 0.38;
    final sleeveOutX = longSleeve ? 0.04 : 0.0;

    final path = Path()
      ..moveTo(pt(0.38, 0.0).dx, pt(0.38, 0.0).dy)
      ..quadraticBezierTo(pt(0.5, 0.10).dx, pt(0.5, 0.10).dy, pt(0.62, 0.0).dx,
          pt(0.62, 0.0).dy)
      ..lineTo(pt(0.80, 0.04).dx, pt(0.80, 0.04).dy)
      ..lineTo(pt(1.0 - sleeveOutX, sleeveEndY).dx,
          pt(1.0 - sleeveOutX, sleeveEndY).dy)
      ..lineTo(pt(longSleeve ? 0.86 : 0.84, sleeveEndY + 0.06).dx,
          pt(longSleeve ? 0.86 : 0.84, sleeveEndY + 0.06).dy)
      ..lineTo(pt(0.76, 0.30).dx, pt(0.76, 0.30).dy)
      ..lineTo(pt(0.77, 1.0).dx, pt(0.77, 1.0).dy)
      ..lineTo(pt(0.23, 1.0).dx, pt(0.23, 1.0).dy)
      ..lineTo(pt(0.24, 0.30).dx, pt(0.24, 0.30).dy)
      ..lineTo(pt(longSleeve ? 0.14 : 0.16, sleeveEndY + 0.06).dx,
          pt(longSleeve ? 0.14 : 0.16, sleeveEndY + 0.06).dy)
      ..lineTo(pt(sleeveOutX, sleeveEndY).dx, pt(sleeveOutX, sleeveEndY).dy)
      ..lineTo(pt(0.20, 0.04).dx, pt(0.20, 0.04).dy)
      ..close();

    canvas.drawPath(path, Paint()..color = color.withValues(alpha: 0.88));
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.black.withValues(alpha: 0.25));

    if (type == GarmentType.shirt) {
      final line = Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 1.5;
      canvas.drawLine(pt(0.5, 0.08), pt(0.5, 1.0), line);
      for (var i = 0; i < 6; i++) {
        canvas.drawCircle(pt(0.53, 0.14 + i * 0.14), r.width * 0.008, line);
      }
    }
  }

  @override
  bool shouldRepaint(covariant GarmentPainter old) =>
      old.placement != placement ||
      old.image != image ||
      old.color != color ||
      old.type != type;
}
