import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/menu.dart';
import '../repositories/menus_repo.dart';

/// Menu: tampilkan cache SQLite dulu, refresh API di background (tanpa spinner).
class MenusNotifier extends AsyncNotifier<List<MenuItemModel>> {
  @override
  Future<List<MenuItemModel>> build() async {
    ref.keepAlive();
    final repo = MenusRepo();
    final cached = await repo.readCache();
    if (cached.isNotEmpty) {
      unawaited(_silentRefresh(repo));
      return cached;
    }
    try {
      return await repo.fetchAndCache();
    } catch (_) {
      if (cached.isNotEmpty) return cached;
      rethrow;
    }
  }

  Future<void> _silentRefresh(MenusRepo repo) async {
    try {
      final fresh = await repo.fetchAndCache();
      state = AsyncData(fresh);
    } catch (_) {}
  }

  /// Pull-to-refresh / manual reload — tidak buang data lama jika gagal.
  Future<void> reloadFromNetwork() async {
    final repo = MenusRepo();
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

final menusProvider =
    AsyncNotifierProvider<MenusNotifier, List<MenuItemModel>>(MenusNotifier.new);
