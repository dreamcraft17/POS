import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/product.dart';
import '../repositories/products_repo.dart';

/// Produk dari API hanya di-sync setelah gate aktif (tab Products/Stock / refresh stok).
final productsLoadGateProvider = StateProvider<bool>((ref) => false);

void enableProductsNetworkLoad(WidgetRef ref) {
  if (ref.read(productsLoadGateProvider)) return;
  ref.read(productsLoadGateProvider.notifier).state = true;
  final cached = ref.read(productsProvider).valueOrNull;
  if (cached == null || cached.isEmpty) {
    unawaited(ref.read(productsProvider.notifier).reloadFromNetwork());
  }
}

/// Produk: cache dulu; sync API hanya setelah [productsLoadGateProvider] aktif.
class ProductsNotifier extends AsyncNotifier<List<Product>> {
  @override
  Future<List<Product>> build() async {
    ref.keepAlive();
    final gate = ref.watch(productsLoadGateProvider);

    ref.listen(productsLoadGateProvider, (prev, next) {
      if (next == true && state.hasValue) {
        unawaited(_silentRefresh(ProductsRepo()));
      }
    });

    final repo = ProductsRepo();
    final cached = await repo.readCache();
    if (cached.isNotEmpty) {
      if (gate) unawaited(_silentRefresh(repo));
      return cached;
    }
    if (!gate) return cached;

    try {
      return await repo.fetchAndCache();
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> _silentRefresh(ProductsRepo repo) async {
    try {
      final fresh = await repo.fetchAndCache();
      state = AsyncData(fresh);
    } catch (_) {}
  }

  Future<void> reloadFromNetwork() async {
    ref.read(productsLoadGateProvider.notifier).state = true;
    final repo = ProductsRepo();
    final previous = state.valueOrNull;
    try {
      final fresh = await repo.fetchAndCache();
      state = AsyncData(fresh);
    } catch (e, st) {
      if (previous != null) {
        state = AsyncData(previous);
      } else {
        state = AsyncError(e, st);
      }
    }
  }
}

final productsProvider =
    AsyncNotifierProvider<ProductsNotifier, List<Product>>(ProductsNotifier.new);
