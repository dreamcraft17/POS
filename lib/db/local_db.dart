// lib/db/local_db.dart
import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class LocalDB {
  static Database? _db;

  static const _DB_NAME = 'e+e POS.db';
  static const _DB_VERSION = 3;

  static Future<Database> get instance async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, _DB_NAME);

    _db = await openDatabase(
      path,
      version: _DB_VERSION,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
    return _db!;
  }

  static Future<void> _onCreate(Database db, int version) async {
    // === cart ===
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cart(
        sku TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price_cents INTEGER NOT NULL,
        qty INTEGER NOT NULL
      );
    ''');

    // === products (dipakai ProductsRepo) ===
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products(
        sku TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price_cents INTEGER NOT NULL,
        stock INTEGER NOT NULL
      );
    ''');

    // === antrean offline ===
    await db.execute('''
      CREATE TABLE IF NOT EXISTS offline_queue(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kind TEXT NOT NULL,
        payload TEXT NOT NULL,
        try_count INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        created_at INTEGER NOT NULL
      );
    ''');

    // (Opsional) siapkan outbox jika nanti dipakai OutboxRepo
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL,
        body TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        try_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_error TEXT
      );
    ''');
  }

  static Future<void> _onUpgrade(Database db, int oldV, int newV) async {
    // Pastikan cart selalu ada
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cart(
        sku TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        price_cents INTEGER NOT NULL,
        qty INTEGER NOT NULL
      );
    ''');

    if (oldV < 2) {
      // Tambah antrean offline di v2
      await db.execute('''
        CREATE TABLE IF NOT EXISTS offline_queue(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          kind TEXT NOT NULL,
          payload TEXT NOT NULL,
          try_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          created_at INTEGER NOT NULL
        );
      ''');
    }

    if (oldV < 3) {
      // Pastikan products ada
      await db.execute('''
        CREATE TABLE IF NOT EXISTS products(
          sku TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          price_cents INTEGER NOT NULL,
          stock INTEGER NOT NULL
        );
      ''');

      // MIGRASI dari products_cache jika ada
      final hasCache = await _tableExists(db, 'products_cache');
      if (hasCache) {
        final countProducts = Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM products'),
            ) ??
            0;
        if (countProducts == 0) {
          // rename langsung
          await db.execute('DROP TABLE IF EXISTS products;');
          await db.execute('ALTER TABLE products_cache RENAME TO products;');
        } else {
          // merge lalu hapus cache
          await db.execute('''
            INSERT OR IGNORE INTO products (sku, name, price_cents, stock)
            SELECT sku, name, price_cents, stock FROM products_cache;
          ''');
          await db.execute('DROP TABLE IF EXISTS products_cache;');
        }
      }
    }

    // (Opsional) siapkan outbox kalau belum ada
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbox(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        op TEXT NOT NULL,
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL,
        body TEXT NOT NULL,
        idempotency_key TEXT NOT NULL,
        try_count INTEGER NOT NULL DEFAULT 0,
        created_at INTEGER NOT NULL,
        last_error TEXT
      );
    ''');
  }

  static Future<bool> _tableExists(Database db, String name) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [name],
    );
    return res.isNotEmpty;
  }

  // Debug helper (opsional)
  static Future<List<Map<String, Object?>>> debugTables() async {
    final db = await instance;
    return db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name",
    );
  }
}
