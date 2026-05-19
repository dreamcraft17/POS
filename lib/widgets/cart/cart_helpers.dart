import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/menu_filter_providers.dart';
import '../../providers/receipt_settings_provider.dart';
import '../../models/menu.dart';
import '../../repositories/menus_repo.dart';
import '../bill_receipt.dart';

/// Store title for receipts / queue tickets (Settings → Receipt template).
String receiptStoreTitle(WidgetRef ref) =>
    ref.read(receiptSettingsProvider).title;

/// Local daily queue number (format `YYYYMMDD-XXX`).
Future<String> nextLocalQueueNo() async {
  final sp = await SharedPreferences.getInstance();
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');

  final dayKey = 'kitchen.queue.seq.$y$m$d';
  final last = sp.getInt(dayKey) ?? 0;
  final next = last + 1;
  await sp.setInt(dayKey, next);

  return '$y$m$d-${next.toString().padLeft(3, '0')}';
}

Map<String, String>? _menuTypeMemCache;
DateTime _menuTypeMemCacheAt = DateTime.fromMillisecondsSinceEpoch(0);
const Duration _menuTypeMemCacheTtl = Duration(minutes: 10);

Map<String, dynamic> itemToPayload(dynamic it) {
  if (it.sku.startsWith('menu:')) {
    return {
      'menu_code': it.sku.substring(5),
      'name': it.name,
      'qty': it.qty,
      'price_cents': it.priceCents,
    };
  }
  return {
    'sku': it.sku,
    'name': it.name,
    'qty': it.qty,
    'price_cents': it.priceCents,
  };
}

Map<String, String> _mapFromMenuModels(List<MenuItemModel> menus) {
  return {
    for (final m in menus)
      if (m.code.isNotEmpty) m.code: (m.type ?? '').trim().toLowerCase(),
  };
}

/// Menu code → type. Prioritas: Riverpod → SQLite cache (tanpa hit API).
Future<Map<String, String>> buildMenuTypeMap({WidgetRef? ref}) async {
  if (ref != null) {
    final fromRiverpod = ref.read(menuTypeMapProvider);
    if (fromRiverpod.isNotEmpty) return fromRiverpod;
  }

  final now = DateTime.now();
  if (_menuTypeMemCache != null &&
      now.difference(_menuTypeMemCacheAt) < _menuTypeMemCacheTtl) {
    return _menuTypeMemCache!;
  }

  try {
    final cached = await MenusRepo().readCache();
    if (cached.isNotEmpty) {
      final m = _mapFromMenuModels(cached);
      _menuTypeMemCache = m;
      _menuTypeMemCacheAt = now;
      return m;
    }
  } catch (_) {}

  return _menuTypeMemCache ?? const {};
}

List<QueueItem> queueItemsFor(
  List<dynamic> cart,
  Map<String, String> typeMap,
  bool Function(String? t) predicate,
) {
  final out = <QueueItem>[];
  for (final e in cart) {
    final dyn = e as dynamic;
    final sku = (dyn.sku?.toString() ?? '');
    if (!sku.startsWith('menu:')) continue;
    final code = sku.substring(5);
    final t = typeMap[code];
    if (predicate(t)) {
      final name = (dyn.name?.toString() ?? code);
      final qty =
          (dyn.qty is int ? dyn.qty as int : int.tryParse('${dyn.qty}') ?? 1);
      out.add(QueueItem(name: name, qty: qty));
    }
  }
  return out;
}

List<QueueItem> queueItemsAll(List<dynamic> cart) {
  final out = <QueueItem>[];
  for (final e in cart) {
    final dyn = e as dynamic;
    final name = (dyn.name?.toString() ?? '-');
    final qty =
        (dyn.qty is int ? dyn.qty as int : int.tryParse('${dyn.qty}') ?? 1);
    out.add(QueueItem(name: name, qty: qty));
  }
  return out;
}

List<Map<String, dynamic>> diffAddedItems(
  List<Map> base,
  List<Map<String, dynamic>> now,
) {
  String keyOf(Map m) => '${m['sku']}|${m['price_cents']}';

  final baseQty = <String, int>{};
  for (final m in base) {
    final k = keyOf(m);
    baseQty[k] = (baseQty[k] ?? 0) + ((m['qty'] ?? 1) as int);
  }
  final add = <Map<String, dynamic>>[];
  for (final m in now) {
    final k = keyOf(m);
    final qtyNow = (m['qty'] ?? 1) as int;
    final qtyBase = baseQty[k] ?? 0;
    final extra = qtyNow - qtyBase;
    if (extra > 0) {
      add.add({
        'sku': m['sku'],
        'name': m['name'],
        'qty': extra,
        'price_cents': m['price_cents'],
      });
    }
  }
  return add;
}

Future<String?> askBillingName(BuildContext context, {String? initial}) async {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Billing Name'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Nomor meja / Nama customer',
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
          child: const Text('Simpan'),
        ),
      ],
    ),
  );
}
