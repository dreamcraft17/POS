import '../repositories/menus_repo.dart';

String _k(String code, String? category, String? size) =>
    '${code.trim().toLowerCase()}|${(category ?? '').trim().toLowerCase()}|${(size ?? '').trim().toLowerCase()}';

class MenuPriceIndex {
  MenuPriceIndex._();

  // Lookup by code (base)
  final Map<String, int> _baseByCode = {}; // code -> price_cents

  // Lookup by name (base)
  final Map<String, int> _baseByName = {}; // name -> price_cents

  // Variant lookup: code|category|size -> price_cents
  final Map<String, int> _variantByTriple = {};

  // Variant lookup by name: name|category|size -> price_cents (kalau detail tak punya code)
  final Map<String, int> _variantByNameTriple = {};

  static Future<MenuPriceIndex> buildFromCache(MenusRepo repo) async {
    final idx = MenuPriceIndex._();
    final menus = await repo.readCache(); // cache lokal sudah include variants
    for (final m in menus) {
      final code = m.code.trim().toLowerCase();
      final name = m.name.trim().toLowerCase();
      final base = (m.priceCents as num).toInt();

      idx._baseByCode[code] = base;
      idx._baseByName[name] = base;

      for (final v0 in (m.variants as List)) {
        final v = Map<String, dynamic>.from(v0 as Map);
        final cat = (v['category'] ?? '').toString();
        final size = (v['size'] ?? '').toString();
        final price = (v['price_cents'] as num).toInt();

        idx._variantByTriple[_k(code, cat, size)] = price;
        idx._variantByNameTriple[_k(name, cat, size)] = price;
      }
    }
    return idx;
  }

  /// Cari harga satuan (cents). Urutan:
  /// 1) variant by code|category|size
  /// 2) base by code
  /// 3) variant by name|category|size
  /// 4) base by name
  int priceCentsFor({
    String? code,
    String? name,
    String? category,
    String? size,
  }) {
    final c = (code ?? '').trim().toLowerCase();
    final n = (name ?? '').trim().toLowerCase();
    final cat = (category ?? '').trim().toLowerCase();
    final sz = (size ?? '').trim().toLowerCase();

    if (c.isNotEmpty) {
      final v = _variantByTriple[_k(c, cat, sz)];
      if (v != null && v > 0) return v;
      final b = _baseByCode[c];
      if (b != null && b > 0) return b;
    }
    if (n.isNotEmpty) {
      final v = _variantByNameTriple[_k(n, cat, sz)];
      if (v != null && v > 0) return v;
      final b = _baseByName[n];
      if (b != null && b > 0) return b;
    }
    return 0;
  }
}
