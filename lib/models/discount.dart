class Discount {
  final String code;
  final String name;
  final DiscountKind kind; // percent | amount
  final double value; // if percent -> 0..100 ; if amount -> cents

  const Discount({
    required this.code,
    required this.name,
    required this.kind,
    required this.value,
  });

  factory Discount.fromJson(Map<String, dynamic> m) {
    return Discount(
      code: m['code'] as String,
      name: m['name'] as String,
      kind: ((m['kind'] ?? '') as String).toLowerCase() == 'percent'
          ? DiscountKind.percent
          : DiscountKind.amount,
      value: (m['value'] is int) ? (m['value'] as int).toDouble() : (m['value'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'kind': kind.name,
        'value': value,
      };
}

enum DiscountKind { percent, amount }
