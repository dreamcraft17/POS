// lib/repositories/products_repo.dart
import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';
import '../models/product.dart';
import '../services/api_service.dart';

class ProductsRepo {
  final _api = ApiService.shared();

  Future<List<Product>> fetchAndCache() async {
    final list = (await _api.products()).map((e) => Product.fromJson(e)).toList();
    final db = await LocalDB.instance;
    final batch = db.batch();
    for (final p in list) {
      batch.insert('products', p.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    return list;
  }

  Future<List<Product>> readCache() async {
    final db = await LocalDB.instance;
    final rows = await db.query('products');
    return rows
        .map((e) =>
            Product(e['sku'] as String, e['name'] as String, e['price_cents'] as int, e['stock'] as int))
        .toList();
  }
}
