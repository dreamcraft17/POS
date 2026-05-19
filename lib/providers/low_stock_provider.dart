import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import 'products_provider.dart';

// 10 = Low
final lowStockThresholdProvider = Provider<int>((_) => 10);

final lowStockProvider = Provider<({List<Product> low, List<Product> out})>((ref) {
  final productsAsync = ref.watch(productsProvider); // ambil dari repo
  final threshold = ref.watch(lowStockThresholdProvider);
  return productsAsync.maybeWhen(
    data: (list) {
      final low = <Product>[];
      final out = <Product>[];
      for (final p in list) {
        if (p.stock <= 0) {
          out.add(p);
        } else if (p.stock <= threshold) {
          low.add(p);
        }
      }
      return (low: low, out: out);
    },
    orElse: () => (low: const <Product>[], out: const <Product>[]),
  );
});
