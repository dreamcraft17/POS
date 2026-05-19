import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';
import '../models/cart_item.dart';
import '../models/product.dart';

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]) { _load(); }

  Future<void> _load() async {
    final d = await LocalDB.instance;
    final rows = await d.query('cart');
    state = rows.map((e) => CartItem(
      e['sku'] as String, e['name'] as String, e['price_cents'] as int, e['qty'] as int
    )).toList();
  }

  Future<void> add(Product p) async {
    final i = state.indexWhere((e) => e.sku == p.sku);
    final next = [...state];
    if (i == -1) next.add(CartItem(p.sku, p.name, p.priceCents, 1));
    else next[i] = next[i].copyWith(qty: next[i].qty + 1);
    state = next;
    final d = await LocalDB.instance;
    final qty = next.firstWhere((e) => e.sku == p.sku).qty;
    await d.insert('cart', {
      'sku': p.sku, 'name': p.name, 'price_cents': p.priceCents, 'qty': qty
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> dec(String sku) async {
    final i = state.indexWhere((e) => e.sku == sku);
    if (i < 0) return;
    final it = state[i];
    final d = await LocalDB.instance;
    if (it.qty <= 1) {
      state = [...state]..removeAt(i);
      await d.delete('cart', where: 'sku=?', whereArgs: [sku]);
    } else {
      state = [...state]..[i] = it.copyWith(qty: it.qty - 1);
      await d.update('cart', {'qty': it.qty - 1}, where: 'sku=?', whereArgs: [sku]);
    }
  }

  Future<void> clear() async {
    state = [];
    final d = await LocalDB.instance;
    await d.delete('cart');
  }
}
