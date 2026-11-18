//  TRYON LANKA - "TRY WITH CAMERA" button for the product page.

import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:woosignal/models/response/product.dart';

import '/app/tryon/garment_calibration.dart';
import '/resources/pages/tryon_page.dart';

class TryOnButtonWidget extends StatelessWidget {
  const TryOnButtonWidget({super.key, required this.product});
  final Product? product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    if (p == null) return const SizedBox.shrink();
    final cal = GarmentCalibration.fromMetaList(p.metaData);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor:
                cal.enabled ? const Color(0xFF111111) : Colors.grey[300],
            foregroundColor:
                cal.enabled ? const Color(0xFFC8A878) : Colors.grey[700],
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          icon: const Icon(Icons.photo_camera_front_outlined),
          label: Text(trans('TRY WITH CAMERA'),
              style: const TextStyle(
                  letterSpacing: 1.2, fontWeight: FontWeight.w600)),
          onPressed: () => cal.enabled
              ? _open(context, p, cal)
              : _showUnavailable(context),
        ),
      ),
    );
  }

  void _open(BuildContext context, Product p, GarmentCalibration cal) {
    final thumb = p.images.isNotEmpty ? p.images.first.src : null;
    openTryOn(context, [
      TryOnItem(
          title: p.name ?? 'Product', calibration: cal, thumbnailUrl: thumb),
      ...TryOnItem.demoItems(),
    ]);
  }

  void _showUnavailable(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(trans('Try-On not available')),
        content: Text(trans('tryon_unavailable_body')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: Text(trans('Close'))),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              openTryOn(context, TryOnItem.demoItems());
            },
            child: Text(trans('Try demo garments')),
          ),
        ],
      ),
    );
  }
}
