import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter_app/app/tryon/garment_calibration.dart';
import 'package:flutter_app/app/tryon/pose_fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GarmentCalibration', () {
    test('defaults when meta missing', () {
      final c = GarmentCalibration.fromMeta({});
      expect(c.enabled, isFalse);
      expect(c.widthRatio, 1.9);
      expect(c.hasGarmentAsset, isFalse);
    });

    test('parses and clamps meta values', () {
      final c = GarmentCalibration.fromMeta({
        'tryon_enabled': 'yes',
        'tryon_garment_url': 'https://example.lk/tee.png',
        'tryon_garment_type': 'shirt',
        'tryon_width_ratio': '2.2',
        'tryon_scale': '99',
        'tryon_offset_y': 'bad',
      });
      expect(c.enabled, isTrue);
      expect(c.type, GarmentType.shirt);
      expect(c.widthRatio, 2.2);
      expect(c.scale, 3.0);
      expect(c.offsetY, -0.10);
      expect(c.hasGarmentAsset, isTrue);
    });

    test('rejects non-https garment url', () {
      final c = GarmentCalibration.fromMeta(
          {'tryon_garment_url': 'http://insecure.lk/a.png'});
      expect(c.hasGarmentAsset, isFalse);
    });
  });

  group('PoseFit', () {
    const cal = GarmentCalibration(enabled: true, offsetY: 0);

    test('level shoulders give zero angle and scaled width', () {
      final p = PoseFit.compute(
        leftShoulder: const BodyPoint(100, 200, 0.9),
        rightShoulder: const BodyPoint(200, 200, 0.9),
        leftHip: const BodyPoint(110, 340, 0.9),
        rightHip: const BodyPoint(190, 340, 0.9),
        calibration: cal,
      )!;
      expect(p.angle, closeTo(0, 1e-9));
      expect(p.width, closeTo(190, 1e-6)); // 100 * 1.9
      expect(p.height, closeTo(140 * 1.45, 1e-6));
      expect(p.anchor.dx, closeTo(150, 1e-6));
      expect(p.anchor.dy, closeTo(200, 1e-6));
    });

    test('mirrored landmark order gives the same placement', () {
      final a = PoseFit.compute(
          leftShoulder: const BodyPoint(200, 200, 0.9),
          rightShoulder: const BodyPoint(100, 200, 0.9),
          calibration: cal)!;
      expect(a.angle, closeTo(0, 1e-9));
      expect(a.width, closeTo(190, 1e-6));
    });

    test('tilted shoulders rotate the garment', () {
      final p = PoseFit.compute(
          leftShoulder: const BodyPoint(100, 200, 0.9),
          rightShoulder: const BodyPoint(200, 300, 0.9),
          calibration: cal)!;
      expect(p.angle, closeTo(math.pi / 4, 1e-9));
    });

    test('low confidence returns null', () {
      expect(
          PoseFit.compute(
              leftShoulder: const BodyPoint(100, 200, 0.2),
              rightShoulder: const BodyPoint(200, 200, 0.9),
              calibration: cal),
          isNull);
    });

    test('image aspect drives height', () {
      final p = PoseFit.compute(
          leftShoulder: const BodyPoint(100, 200, 0.9),
          rightShoulder: const BodyPoint(200, 200, 0.9),
          calibration: cal,
          garmentAspect: 1.2)!;
      expect(p.height, closeTo(190 * 1.2, 1e-6));
    });
  });

  group('PlacementSmoother', () {
    test('smooths toward new value and drops after misses', () {
      final s = PlacementSmoother(alpha: 0.5, maxMissedFrames: 1);
      const a = GarmentPlacement(
          anchor: Offset(0, 0), width: 100, height: 100, angle: 0);
      const b = GarmentPlacement(
          anchor: Offset(10, 0), width: 200, height: 100, angle: 0);
      s.update(a);
      final r = s.update(b)!;
      expect(r.width, 150);
      expect(r.anchor.dx, 5);
      expect(s.update(null), isNotNull);
      expect(s.update(null), isNull);
    });
  });
}
