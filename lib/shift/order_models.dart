class PaymentLine {
  final String method;
  final int amountCents;
  PaymentLine({required this.method, required this.amountCents});
}

class OrderItemLite {
  final String name;
  final int qty;
  final int priceCentsEach;
  final int? lineTotalOverrideCents; // total dari detail kalau ada

  int get lineTotalCents =>
      (lineTotalOverrideCents != null && lineTotalOverrideCents! > 0)
          ? lineTotalOverrideCents!
          : qty * priceCentsEach;

  OrderItemLite({
    required this.name,
    required this.qty,
    required this.priceCentsEach,
    this.lineTotalOverrideCents,
  });
}

class OrderLite {
  final int id;
  final DateTime createdAt;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;
  final int itemsCount;
  final List<PaymentLine> payments;
  final List<OrderItemLite> items;

  OrderLite({
    required this.id,
    required this.createdAt,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
    required this.itemsCount,
    required this.payments,
    required this.items,
  });
}
