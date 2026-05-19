import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../repositories/products_repo.dart';

final productsProvider = FutureProvider<List<Product>>((ref) async {
  final repo = ProductsRepo();
  try {
    return await repo.fetchAndCache();
  } catch (_) {
    return repo.readCache();
  }
});
