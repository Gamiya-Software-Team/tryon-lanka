//  TRYON LANKA - Try-On tab: explains live fitting and lists eligible products.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:nylo_framework/nylo_framework.dart';
import 'package:woosignal/models/response/product.dart';

import '/app/tryon/garment_calibration.dart';
import '/bootstrap/helpers.dart';
import '/resources/pages/product_detail_page.dart';
import '/resources/pages/tryon_page.dart';

class TryOnHubPage extends StatefulWidget {
  const TryOnHubPage({super.key, this.storeConnected = true});

  /// False when the app opened without store settings (offline Try-On mode).
  final bool storeConnected;

  @override
  State<TryOnHubPage> createState() => _TryOnHubPageState();
}

class _TryOnHubPageState extends State<TryOnHubPage> {
  List<Product> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!widget.storeConnected) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final all = await appWooSignal((api) => api.getProducts(
              perPage: 50, status: "publish", stockStatus: "instock"))
          .timeout(const Duration(seconds: 15));
      _products = (all as List<Product>)
          .where((p) => GarmentCalibration.fromMetaList(p.metaData).enabled)
          .toList();
    } catch (_) {
      _products = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    const black = Color(0xFF111111);
    const gold = Color(0xFFC8A878);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5F0),
      appBar: AppBar(
        automaticallyImplyLeading: widget.storeConnected,
        backgroundColor: const Color(0xFFF7F5F0),
        title: Text(trans('Live Try-On'),
            style: const TextStyle(letterSpacing: 1.5)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (!widget.storeConnected)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFFFF4E0),
                  border: Border.all(color: gold),
                  borderRadius: BorderRadius.circular(10)),
              child: Row(children: [
                const Icon(Icons.storefront_outlined, color: black),
                const SizedBox(width: 10),
                Expanded(child: Text(trans('tryon_store_not_connected'))),
              ]),
            ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
                color: black, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('TRYON LANKA',
                    style: TextStyle(
                        color: gold,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text(trans('Wear it before you buy it.'),
                    style: const TextStyle(color: Colors.white, fontSize: 22)),
                const SizedBox(height: 12),
                _step('1', trans('tryon_how_1')),
                _step('2', trans('tryon_how_2')),
                _step('3', trans('tryon_how_3')),
                const SizedBox(height: 16),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                      backgroundColor: gold, foregroundColor: black),
                  icon: const Icon(Icons.photo_camera_front_outlined),
                  label: Text(trans('Try demo garments')),
                  onPressed: () => openTryOn(context, TryOnItem.demoItems()),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(trans('Try-On ready products'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (!widget.storeConnected)
            const SizedBox.shrink()
          else if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_products.isEmpty)
            Text(trans('tryon_no_products'))
          else
            ..._products.map((p) => Card(
                  child: ListTile(
                    leading: p.images.isNotEmpty
                        ? SizedBox(
                            width: 48,
                            child: CachedNetworkImage(
                                imageUrl: p.images.first.src ?? '',
                                fit: BoxFit.cover))
                        : const Icon(Icons.checkroom),
                    title: Text(p.name ?? ''),
                    trailing: const Icon(Icons.photo_camera_front_outlined),
                    onTap: () => routeTo(ProductDetailPage.path, data: p),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _step(String n, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$n.  ',
              style: const TextStyle(color: Color(0xFFC8A878))),
          Expanded(
              child: Text(text, style: const TextStyle(color: Colors.white70))),
        ]),
      );
}
