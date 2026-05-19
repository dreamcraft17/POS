// class Product {
//   final String sku;
//   final String name;
//   final int priceCents;
//   final int stock;

//   Product(this.sku, this.name, this.priceCents, this.stock);

//   factory Product.fromJson(Map<String, dynamic> j) =>
//       Product(j['sku'] ?? '', j['name'], j['price_cents'], j['stock'] ?? 0);

//   Map<String, dynamic> toDb() => {
//     'sku': sku, 'name': name, 'price_cents': priceCents, 'stock': stock,
//   };
// }


class Product {
  final String sku;
  final String name;
  final int priceCents;
  final int stock;

  // tambahan
  final String? note;
  final String? variant;

  Product(
    this.sku,
    this.name,
    this.priceCents,
    this.stock, {
    this.note,
    this.variant,
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        j['sku'] ?? '',
        j['name'],
        j['price_cents'],
        j['stock'] ?? 0,
        note: j['note'],
        variant: j['variant'],
      );

  Map<String, dynamic> toDb() => {
        'sku': sku,
        'name': name,
        'price_cents': priceCents,
        'stock': stock,
        if (note != null && note!.isNotEmpty) 'note': note,
        if (variant != null && variant!.isNotEmpty) 'variant': variant,
      };
}
