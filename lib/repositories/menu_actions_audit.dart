// lib/repositories/menu_actions_audit.dart
import 'dart:async';
import '../models/menu.dart';
import '../repositories/auth_repo.dart';
import '../services/api_service.dart';

extension _MapExt on Map<String, dynamic> {
  void addIf(String key, dynamic val) {
    if (val != null) this[key] = val;
  }
}

class MenuActionsAudit {
  final _api = ApiService.shared();

  /// Create menu dengan auto injeksi audit user (created_by / created_by_id).
  Future<void> createMenuWithUser(MenuItemModel menu) async {
    final body = menu.toCreateBody();
    final u = await AuthRepo().me(refreshFromServer: false).catchError((_) => null);
    if (u != null) {
      body.addIf('created_by_id', u.id);
      body.addIf('created_by', u.username);
    }
    await _api.createMenu(body);
  }

  /// Update menu + injeksi audit (bisa dipakai utk "last updated by" kalau backend dukung).
  Future<void> updateMenuWithUser(String code, Map<String, dynamic> patch) async {
    final body = {...patch};
    final u = await AuthRepo().me(refreshFromServer: false).catchError((_) => null);
    if (u != null) {
      body.addIf('created_by_id', u.id);
      body.addIf('created_by', u.username);
    }
    await _api.updateMenu(code, body);
  }
}
