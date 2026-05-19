import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kuota qty "pesanan lama" per `sku|price_cents` dari draft aktif.
final cartDraftBaseQuotaProvider = FutureProvider<Map<String, int>>((ref) async {
  try {
    final sp = await SharedPreferences.getInstance();
    final baseStr = sp.getString('pos.active.draft.base_items');
    final base = baseStr != null ? (jsonDecode(baseStr) as List) : const [];
    final m = <String, int>{};
    for (final raw in base) {
      final it = Map<String, dynamic>.from(raw as Map);
      final sku = (it['sku'] ??
              (it['menu_code'] != null ? 'menu:${it['menu_code']}' : 'unknown'))
          .toString();
      final price = (it['price_cents'] as num?)?.toInt() ??
          (it['unit_price_cents'] as num?)?.toInt() ??
          0;
      final qty = (it['qty'] as num?)?.toInt() ?? 1;
      final key = '$sku|$price';
      m[key] = (m[key] ?? 0) + qty;
    }
    return m;
  } catch (_) {
    return const {};
  }
});
