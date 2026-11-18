//  TRYON LANKA - garment calibration read from WooCommerce product meta.
//
//  The companion WordPress plugin (wordpress-plugin/tryon-lanka-tryon) stores
//  these values as product meta. WooCommerce REST only returns meta keys that
//  do NOT start with "_", so every key here is public.

enum GarmentType { tshirt, shirt, hoodie, dress }

class GarmentCalibration {
  const GarmentCalibration({
    this.enabled = false,
    this.garmentUrl,
    this.type = GarmentType.tshirt,
    this.widthRatio = 1.9,
    this.heightRatio = 1.45,
    this.offsetX = 0.0,
    this.offsetY = -0.10,
    this.rotation = 0.0,
    this.scale = 1.0,
    this.version = 1,
  });

  static const keyEnabled = 'tryon_enabled';
  static const keyGarmentUrl = 'tryon_garment_url';
  static const keyType = 'tryon_garment_type';
  static const keyWidthRatio = 'tryon_width_ratio';
  static const keyHeightRatio = 'tryon_height_ratio';
  static const keyOffsetX = 'tryon_offset_x';
  static const keyOffsetY = 'tryon_offset_y';
  static const keyRotation = 'tryon_rotation';
  static const keyScale = 'tryon_scale';
  static const keyVersion = 'tryon_calibration_version';

  /// Whether the product is marked as try-on enabled on the website.
  final bool enabled;

  /// Transparent, front-facing garment cutout (PNG/WebP). Null means the app
  /// draws its built-in garment silhouette in a demo colour.
  final String? garmentUrl;
  final GarmentType type;

  /// Garment width as a multiple of the detected shoulder width.
  final double widthRatio;

  /// Garment height as a multiple of the shoulder-to-hip torso length.
  final double heightRatio;

  /// Horizontal shift as a fraction of garment width.
  final double offsetX;

  /// Vertical shift of the collar as a fraction of garment height
  /// (negative = up, so the collar sits above the shoulder line).
  final double offsetY;

  /// Extra rotation in degrees.
  final double rotation;
  final double scale;
  final int version;

  bool get hasGarmentAsset =>
      garmentUrl != null && garmentUrl!.trim().startsWith('https://');

  /// Builds calibration from WooCommerce `meta_data` as a key -> value map.
  factory GarmentCalibration.fromMeta(Map<String, dynamic> meta) {
    double d(String k, double fallback) {
      final v = meta[k];
      if (v == null) return fallback;
      final parsed = double.tryParse(v.toString().trim());
      if (parsed == null || parsed.isNaN || parsed.isInfinite) return fallback;
      return parsed;
    }

    bool b(String k) {
      final v = meta[k]?.toString().trim().toLowerCase();
      return v == '1' || v == 'yes' || v == 'true' || v == 'on';
    }

    GarmentType t(String? raw) {
      switch (raw?.trim().toLowerCase()) {
        case 'shirt':
          return GarmentType.shirt;
        case 'hoodie':
          return GarmentType.hoodie;
        case 'dress':
          return GarmentType.dress;
        default:
          return GarmentType.tshirt;
      }
    }

    final url = meta[keyGarmentUrl]?.toString().trim();
    return GarmentCalibration(
      enabled: b(keyEnabled),
      garmentUrl: (url == null || url.isEmpty) ? null : url,
      type: t(meta[keyType]?.toString()),
      widthRatio: d(keyWidthRatio, 1.9).clamp(0.5, 4.0).toDouble(),
      heightRatio: d(keyHeightRatio, 1.45).clamp(0.5, 4.0).toDouble(),
      offsetX: d(keyOffsetX, 0.0).clamp(-1.0, 1.0).toDouble(),
      offsetY: d(keyOffsetY, -0.10).clamp(-1.0, 1.0).toDouble(),
      rotation: d(keyRotation, 0.0).clamp(-45.0, 45.0).toDouble(),
      scale: d(keyScale, 1.0).clamp(0.3, 3.0).toDouble(),
      version: d(keyVersion, 1).round(),
    );
  }

  /// Convenience for WooSignal `Product.metaData` (objects with key/value).
  static GarmentCalibration fromMetaList(Iterable<dynamic> metaData) {
    final map = <String, dynamic>{};
    for (final m in metaData) {
      try {
        final key = (m as dynamic).key?.toString();
        if (key != null && key.startsWith('tryon_')) {
          map[key] = (m as dynamic).value;
        }
      } catch (_) {}
    }
    return GarmentCalibration.fromMeta(map);
  }
}
