import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../db/local_db.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    final d = await LocalDB.instance;
    final rows = await d.query('cart');
    state = rows
        .map((e) => CartItem(
              e['sku'] as String,
              e['name'] as String,
              e['price_cents'] as int,
              e['qty'] as int,
            ))
        .toList();
  }

  Future<void> add(Product p) async {
    final i = state.indexWhere((e) => e.sku == p.sku);
    final next = [...state];
    if (i == -1) {
      next.add(CartItem(p.sku, p.name, p.priceCents, 1));
    } else {
      next[i] = next[i].copyWith(qty: next[i].qty + 1);
    }
    state = next;
    unawaited(_persistLine(p.sku, next));
  }

  Future<void> dec(String sku) async {
    final i = state.indexWhere((e) => e.sku == sku);
    if (i < 0) return;
    final it = state[i];
    if (it.qty <= 1) {
      final next = [...state]..removeAt(i);
      state = next;
      unawaited(_deleteLine(sku));
    } else {
      final next = [...state]..[i] = it.copyWith(qty: it.qty - 1);
      state = next;
      unawaited(_updateQty(sku, it.qty - 1));
    }
  }

  Future<void> clear() async {
    state = [];
    unawaited(_clearDb());
  }

  Future<void> _persistLine(String sku, List<CartItem> next) async {
    final row = next.firstWhere((e) => e.sku == sku);
    final d = await LocalDB.instance;
    await d.insert(
      'cart',
      {
        'sku': row.sku,
        'name': row.name,
        'price_cents': row.priceCents,
        'qty': row.qty,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _updateQty(String sku, int qty) async {
    final d = await LocalDB.instance;
    await d.update('cart', {'qty': qty}, where: 'sku=?', whereArgs: [sku]);
  }

  Future<void> _deleteLine(String sku) async {
    final d = await LocalDB.instance;
    await d.delete('cart', where: 'sku=?', whereArgs: [sku]);
  }

  Future<void> _clearDb() async {
    final d = await LocalDB.instance;
    await d.delete('cart');
  }
}
