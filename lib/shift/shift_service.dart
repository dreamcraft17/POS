import 'order_models.dart';
import 'order_data_source.dart';
import 'shift_history_repo.dart';


class SoldItem {
  final String name;
  final int qty;
  final int totalCents;
  SoldItem({required this.name, required this.qty, required this.totalCents});
}

class ShiftSummary {
  final DateTime startAt;
  final DateTime endAt;
  final int ordersCount;
  final int soldItems;
  final int grossCents;
  final int discountCents;
  final int taxCents;
  final int netCents;
  final Map<String, int> byPayment;
  final List<SoldItem> items;

  ShiftSummary({
    required this.startAt,
    required this.endAt,
    required this.ordersCount,
    required this.soldItems,
    required this.grossCents,
    required this.discountCents,
    required this.taxCents,
    required this.netCents,
    required this.byPayment,
    required this.items,
  });
}

class ShiftService {
  final OrderDataSource dataSource;
  ShiftService(this.dataSource);

  Future<ShiftSummary> compute({required DateTime startAt}) async {
    final orders = await dataSource.listOrdersSince(startAt);

    int ordersCount = 0, soldItems = 0, gross = 0, disc = 0, tax = 0, net = 0;
    final byPayment = <String, int>{};
    final itemsAgg = <String, SoldItem>{};

    for (final o in orders) {
      ordersCount++;
      soldItems += o.itemsCount;
      gross += o.subtotalCents;
      disc  += o.discountCents;
      tax   += o.taxCents;
      net   += o.totalCents;

      for (final p in o.payments) {
        byPayment[p.method] = (byPayment[p.method] ?? 0) + p.amountCents;
      }

      for (final it in o.items) {
        final key = it.name;
        final addQty = it.qty;
        final addTotal = it.lineTotalCents; // pakai total override bila ada

        final ex = itemsAgg[key];
        itemsAgg[key] = (ex == null)
            ? SoldItem(name: key, qty: addQty, totalCents: addTotal)
            : SoldItem(
                name: key,
                qty: ex.qty + addQty,
                totalCents: ex.totalCents + addTotal,
              );
      }
    }

    final itemsList = itemsAgg.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return ShiftSummary(
      startAt: startAt,
      endAt: DateTime.now(),
      ordersCount: ordersCount,
      soldItems: soldItems,
      grossCents: gross,
      discountCents: disc,
      taxCents: tax,
      netCents: net,
      byPayment: byPayment,
      items: itemsList,
    );
  }
}

extension _ShiftSummaryCopy on ShiftSummary {
  ShiftSummary copyWith({
    DateTime? startAt,
    DateTime? endAt,
    int? ordersCount,
    int? soldItems,
    int? grossCents,
    int? discountCents,
    int? taxCents,
    int? netCents,
    Map<String, int>? byPayment,
    List<SoldItem>? items,
  }) {
    return ShiftSummary(
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      ordersCount: ordersCount ?? this.ordersCount,
      soldItems: soldItems ?? this.soldItems,
      grossCents: grossCents ?? this.grossCents,
      discountCents: discountCents ?? this.discountCents,
      taxCents: taxCents ?? this.taxCents,
      netCents: netCents ?? this.netCents,
      byPayment: byPayment ?? this.byPayment,
      items: items ?? this.items,
    );
  }
}
