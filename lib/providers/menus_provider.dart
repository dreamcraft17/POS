import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/menu.dart';
import '../repositories/menus_repo.dart';

final menusProvider = FutureProvider<List<MenuItemModel>>((ref) async {
  final repo = MenusRepo();
  try {
    return await repo.fetchAndCache();
  } catch (_) {
    return repo.readCache();
  }
});
