class MenuVariant {
  final String kind; // 'drink' | 'food'
  final String? category; // 'hot' | 'ice' | null
  final String? size; // 'S' | 'M' | 'L' | null
  final int priceCents;

  const MenuVariant({
    required this.kind,
    this.category,
    this.size,
    required this.priceCents,
  });

  factory MenuVariant.fromJson(Map<String, dynamic> j) => MenuVariant(
        kind: '${j['kind']}',
        category: j['category'] == null ? null : '${j['category']}',
        size: j['size'] == null ? null : '${j['size']}',
        priceCents: (j['price_cents'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'category': category,
        'size': size,
        'price_cents': priceCents,
      };

  String shortLabel() {
    final hotIce = (category == null) ? '' : (category == 'hot' ? 'H' : 'I');
    final sz = size ?? '';
    if (hotIce.isEmpty && sz.isEmpty) return '';
    if (hotIce.isNotEmpty && sz.isNotEmpty) return '$hotIce,$sz';
    return hotIce.isNotEmpty ? hotIce : sz;
  }
}
