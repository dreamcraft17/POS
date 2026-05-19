import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/menu.dart';
import 'menus_provider.dart';
import 'ui_state.dart';

/// Kategori menu terpilih di POS (`null` = All).
final posMenuCategoryProvider = StateProvider<String?>((ref) => null);

/// Chip kategori unik dari data menu.
final menuTypeChipsProvider = Provider<List<String>>((ref) {
  final menus = ref.watch(menusProvider).valueOrNull;
  if (menus == null || menus.isEmpty) return const [];
  final set = <String>{};
  for (final m in menus) {
    final t = (m.type ?? '').trim().toLowerCase();
    if (t.isNotEmpty) set.add(t);
  }
  return set.toList()..sort();
});

/// Menu sudah difilter search + kategori.
final filteredMenusProvider = Provider<List<MenuItemModel>>((ref) {
  final menus = ref.watch(menusProvider).valueOrNull ?? const [];
  if (menus.isEmpty) return const [];

  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final selectedType = ref.watch(posMenuCategoryProvider);

  return menus.where((m) {
    final matchesQuery = query.isEmpty ||
        m.name.toLowerCase().contains(query) ||
        m.code.toLowerCase().contains(query) ||
        m.components.any((c) => c.productSku.toLowerCase().contains(query));

    final t = m.type?.trim().toLowerCase();
    final matchesType = selectedType == null || selectedType == t;
    return matchesQuery && matchesType;
  }).toList(growable: false);
});

/// `menu_code` → `type` untuk kitchen/bar split (dari data menu yang sudah di-cache).
final menuTypeMapProvider = Provider<Map<String, String>>((ref) {
  final menus = ref.watch(menusProvider).valueOrNull;
  if (menus == null || menus.isEmpty) return const {};
  return Map.unmodifiable({
    for (final m in menus)
      if (m.code.isNotEmpty) m.code: (m.type ?? '').trim().toLowerCase(),
  });
});
