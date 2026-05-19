class CartItem {
  final String sku;
  final String name;
  final int priceCents;
  final int qty;

  CartItem(this.sku, this.name, this.priceCents, this.qty);

  CartItem copyWith({int? qty}) => CartItem(sku, name, priceCents, qty ?? this.qty);
}
