import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ui/pos_theme.dart';
import '../models/product.dart';
import '../services/api_service.dart';
import '../providers/products_provider.dart';

Future<void> showEditProductDialog(
  BuildContext context,
  WidgetRef ref,
  Product p,
) async {
  final nameCtrl = TextEditingController(text: p.name);
  final priceCtrl = TextEditingController(text: '${p.priceCents}');
  final deltaCtrl = TextEditingController(text: '0');
  final api = ApiService.shared();

  await showDialog(
    context: context,
    builder: (_) {
      return AlertDialog(
        backgroundColor: PosTheme.white,
        surfaceTintColor: PosTheme.white,
        title: Text('Edit ${p.sku}', style: const TextStyle(color: PosTheme.black)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            TextField(
              controller: priceCtrl,
              decoration: const InputDecoration(labelText: 'Price'),
              keyboardType: TextInputType.number,
            ),
            const Divider(color: PosTheme.border),
            TextField(
              controller: deltaCtrl,
              decoration: const InputDecoration(labelText: 'Adjust Stock (delta, +/-)'),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: PosTheme.black,
              foregroundColor: PosTheme.white,
            ),
            onPressed: () async {
              try {
                final patch = <String, dynamic>{};
                if (nameCtrl.text.trim() != p.name) {
                  patch['name'] = nameCtrl.text.trim();
                }
                final newPrice = int.tryParse(priceCtrl.text.trim());
                if (newPrice != null && newPrice != p.priceCents) {
                  patch['price_cents'] = newPrice;
                }
                if (patch.isNotEmpty) await api.updateProduct(p.sku, patch);

                final delta = int.tryParse(deltaCtrl.text.trim()) ?? 0;
                if (delta != 0) {
                  await api.adjustStock(p.sku, delta, reason: 'manual');
                }

                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('Saved')));
                }
                ref.invalidate(productsProvider);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Failed: $e')));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
