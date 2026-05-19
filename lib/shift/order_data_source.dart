import 'order_models.dart';
import '../services/api_service.dart';
import 'menu_price_index.dart';
import '../repositories/menus_repo.dart';

int _toInt(dynamic v, {int def = 0}) {
  if (v == null) return def;
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}
String _toStr(dynamic v, {String def = ''}) => v?.toString() ?? def;
DateTime _toDate(dynamic v) => DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();

class OrderDataSource {
  final ApiService api;
  final int currentUserId;
  final MenuPriceIndex priceIdx;

  OrderDataSource({required this.api, required this.currentUserId, required this.priceIdx});

  static Future<OrderDataSource> withMenuPriceIndex({
    required ApiService api,
    required int currentUserId,
    bool refreshMenusFirst = false,
  }) async {
    final repo = MenusRepo();
    if (refreshMenusFirst) {
      await repo.fetchAndCache(); // isi cache menus + variants ke SQLite. :contentReference[oaicite:2]{index=2}
    }
    final idx = await MenuPriceIndex.buildFromCache(repo); // baca cache lokal. :contentReference[oaicite:3]{index=3}
    return OrderDataSource(api: api, currentUserId: currentUserId, priceIdx: idx);
  }

  Future<List<OrderLite>> listOrdersSince(DateTime since) async {
    final rows = await api.orders(
      createdBy: currentUserId,
      sinceIso: since.toIso8601String(),
    );

    return Future.wait(rows.map<Future<OrderLite>>((raw) async {
      final m = (raw as Map).cast<String, dynamic>();

      final orderId   = _toInt(m['id']);
      final createdAt = _toDate(m['created_at']);
      final subtotal  = _toInt(m['subtotal_cents']);
      final discount  = _toInt(m['discount_cents']);
      final tax       = _toInt(m['tax_cents']);
      final total     = _toInt(m['total_cents']);

      final paymentsHeader = (m['payments'] as List? ?? const [])
          .map((p0) {
            final p = (p0 as Map).cast<String, dynamic>();
            return PaymentLine(
              method: _toStr(p['method'], def: 'UNKNOWN'),
              amountCents: _toInt(p['amount_cents']),
            );
          })
          .toList();

      // Ambil detail + items
      final detail = await api.orderDetail(id: orderId, createdBy: currentUserId);
      final itemsJson = (detail['items'] as List? ?? const []);

      final items = <OrderItemLite>[];
      var itemsCount = 0;

      for (final it0 in itemsJson) {
        final it = (it0 as Map).cast<String, dynamic>();

        final name = _toStr(it['name'], def: '(no name)');
        final qty  = _toInt(it['qty'], def: 0);
        itemsCount += qty;

        // total per-line dari banyak kemungkinan field
        var lineTotal = _toInt(it['total_cents']);
        if (lineTotal == 0) lineTotal = _toInt(it['line_total_cents']);
        if (lineTotal == 0) lineTotal = _toInt(it['amount_cents']);
        if (lineTotal == 0) lineTotal = _toInt(it['price_total_cents']);
        if (lineTotal == 0) lineTotal = _toInt(it['line_total']);
        if (lineTotal == 0) lineTotal = _toInt(it['total']);
        if (lineTotal == 0) lineTotal = _toInt(it['amount']);

        // ambil kode & varian (kalau ada di detail)
        final code = _toStr(it['menu_code']);
        final category = _toStr(it['category'], def: '');
        final size = _toStr(it['size'], def: '');

        // harga satuan prioritas: index (code/name + category/size)
        var priceEach = priceIdx.priceCentsFor(
          code: code.isEmpty ? null : code,
          name: name,
          category: category.isEmpty ? null : category,
          size: size.isEmpty ? null : size,
        );

        // kalau index tidak punya, coba field di detail...
        if (priceEach == 0) {
          priceEach = _toInt(it['price_cents_each']);
          if (priceEach == 0) priceEach = _toInt(it['unit_price_cents']);
          if (priceEach == 0) priceEach = _toInt(it['price_each_cents']);
          if (priceEach == 0) priceEach = _toInt(it['unit_price']);
          if (priceEach == 0) priceEach = _toInt(it['price']);
        }

        // fallback terakhir: hitung dari total / qty
        if (priceEach == 0 && qty > 0 && lineTotal > 0) {
          priceEach = (lineTotal / qty).floor();
        }

        items.add(OrderItemLite(
          name: name,
          qty: qty,
          priceCentsEach: priceEach,
          lineTotalOverrideCents: lineTotal > 0 ? lineTotal : null,
        ));
      }

      final paymentsDetail = (detail['payments'] as List? ?? const [])
          .map((p0) {
            final p = (p0 as Map).cast<String, dynamic>();
            return PaymentLine(
              method: _toStr(p['method'], def: 'UNKNOWN'),
              amountCents: _toInt(p['amount_cents']),
            );
          })
          .toList();

      final payments = paymentsHeader.isNotEmpty ? paymentsHeader : paymentsDetail;

      return OrderLite(
        id: orderId,
        createdAt: createdAt,
        subtotalCents: subtotal,
        discountCents: discount,
        taxCents: tax,
        totalCents: total,
        itemsCount: itemsCount,
        payments: payments,
        items: items,
      );
    }));
  }
}
