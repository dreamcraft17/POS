// lib/repositories/menus_repo.dart
import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';
import '../services/api_service.dart';
import '../models/menu.dart';
import '../repositories/auth_repo.dart';

class MenusRepo {
  final _api = ApiService.shared();

  // ===== helpers: schema & user =====
  Future<int> _currentUserId() async {
    final u = await AuthRepo().me(refreshFromServer: false);
    return u?.id ?? 0;
  }

  Future<void> _ensureSchema(Database db) async {
    // menus
    await db.execute('''
         CREATE TABLE IF NOT EXISTS menus (
      code TEXT PRIMARY KEY,
      name TEXT,
      price_cents INTEGER,
      image_url TEXT,
      enabled INTEGER,
      sort INTEGER,
      type TEXT,                      
      owner_user_id INTEGER DEFAULT 0
      )
    ''');
    // add column if upgrading from old schema
    // try { await db.execute('ALTER TABLE menus ADD COLUMN owner_user_id INTEGER DEFAULT 0'); } catch (_) {}
      try { await db.execute('ALTER TABLE menus ADD COLUMN owner_user_id INTEGER DEFAULT 0'); } catch (_) {}
  try { await db.execute('ALTER TABLE menus ADD COLUMN type TEXT'); } catch (_) {} // NEW

    // menu_components
    await db.execute('''
      CREATE TABLE IF NOT EXISTS menu_components (
        owner_user_id INTEGER DEFAULT 0,
        menu_code TEXT,
        product_sku TEXT,
        qty INTEGER,
        PRIMARY KEY(owner_user_id, menu_code, product_sku)
      )
    ''');
    try { await db.execute('ALTER TABLE menu_components ADD COLUMN owner_user_id INTEGER DEFAULT 0'); } catch (_) {}

    // menu_variants
    await db.execute('''
      CREATE TABLE IF NOT EXISTS menu_variants (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        owner_user_id INTEGER DEFAULT 0,
        menu_code TEXT NOT NULL,
        kind TEXT NOT NULL,         -- 'drink' | 'food'
        category TEXT NULL,         -- 'hot' | 'ice' | NULL
        size TEXT NULL,             -- 'S' | 'M' | 'L' | NULL
        price_cents INTEGER NOT NULL
      )
    ''');
    try { await db.execute('ALTER TABLE menu_variants ADD COLUMN owner_user_id INTEGER DEFAULT 0'); } catch (_) {}

    // unique index termasuk owner_user_id supaya kode menu yang sama antar user tidak tabrakan
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS ux_menu_variants_owner
      ON menu_variants (owner_user_id, menu_code, IFNULL(category,''), IFNULL(size,''))
    ''');
  }

  // ====== FETCH (server) + CACHE (per user) ======
  Future<List<MenuItemModel>> fetchAndCache() async {
    // Ambil dari API (server SUDAH memfilter berdasarkan user aktif)
    final list = (await _api.menus())
        .map((e) => MenuItemModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();

    final userId = await _currentUserId();
    final db = await LocalDB.instance;
    await _ensureSchema(db);
    final b = db.batch();

    // bersihkan cache HANYA untuk user ini
    b.delete('menu_components', where: 'owner_user_id=?', whereArgs: [userId]);
    b.delete('menu_variants',  where: 'owner_user_id=?', whereArgs: [userId]);
    b.delete('menus',          where: 'owner_user_id=?', whereArgs: [userId]);

    for (final m in list) {
      b.insert(
        'menus',
        {
          'code': m.code,
          'name': m.name,
          'price_cents': m.priceCents,
          'image_url': null,
          'enabled': m.enabled ? 1 : 0,
          'sort': m.sort,
          'type': m.type,
          'owner_user_id': userId,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      for (final c in m.components) {
        b.insert(
          'menu_components',
          {
            'owner_user_id': userId,
            'menu_code': m.code,
            'product_sku': c.productSku,
            'qty': c.qty,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      for (final v in (m.variants as List)) {
        final mv = Map<String, dynamic>.from(v as Map);
        b.insert(
          'menu_variants',
          {
            'owner_user_id': userId,
            'menu_code': m.code,
            'kind': '${mv['kind']}',
            'category': mv['category'],
            'size': mv['size'],
            'price_cents': (mv['price_cents'] as num).toInt(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    await b.commit(noResult: true);
    return list;
  }

  // ====== READ from cache (per user) ======
  Future<List<MenuItemModel>> readCache() async {
    final userId = await _currentUserId();
    final db = await LocalDB.instance;
    await _ensureSchema(db);

    final rows = await db.query(
      'menus',
      where: 'owner_user_id=?',
      whereArgs: [userId],
      orderBy: 'sort,name',
    );

    final compRows = await db.query(
      'menu_components',
      where: 'owner_user_id=?',
      whereArgs: [userId],
    );

    final varRows = await db.query(
      'menu_variants',
      where: 'owner_user_id=?',
      whereArgs: [userId],
    );

    final compsBy = <String, List<MenuComponent>>{};
    for (final r in compRows) {
      final list = compsBy[r['menu_code'] as String] ?? [];
      list.add(
        MenuComponent(
          productSku: r['product_sku'] as String,
          qty: (r['qty'] as num).toInt(),
        ),
      );
      compsBy[r['menu_code'] as String] = list;
    }

    final variantsBy = <String, List<Map<String, dynamic>>>{};
    for (final r in varRows) {
      final list = variantsBy[r['menu_code'] as String] ?? [];
      list.add({
        'kind': r['kind'],
        'category': r['category'],
        'size': r['size'],
        'price_cents': (r['price_cents'] as num).toInt(),
      });
      variantsBy[r['menu_code'] as String] = list;
    }

    return rows
        .map((e) => MenuItemModel(
              code: e['code'] as String,
              name: e['name'] as String,
              priceCents: (e['price_cents'] as num).toInt(),
              enabled: ((e['enabled'] as num).toInt()) == 1,
              sort: (e['sort'] as num).toInt(),
              type: e['type'] as String?,
              components: compsBy[e['code'] as String] ?? const [],
              variants: variantsBy[e['code'] as String] ?? const [],
            ))
        .toList();
  }
}
