import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';
import '../models/discount.dart';

final discountsProvider = FutureProvider<List<Discount>>((ref) async {
  final api = ApiService.shared();
  final list = await api.discounts();
  return list.map((e) => Discount.fromJson(Map<String, dynamic>.from(e))).toList();
});

/// Diskon yang sedang dipilih untuk order berjalan
final selectedDiscountProvider = StateProvider<Discount?>((ref) => null);

/// Hitung nilai diskon (dalam cents) dari subtotal berdasarkan discount terpilih.
int computeDiscountCents(Discount? d, int subtotalCents) {
  if (d == null) return 0;
  if (d.kind == DiscountKind.percent) {
    final v = (subtotalCents * (d.value / 100)).round();
    if (v < 0) return 0;
    if (v > subtotalCents) return subtotalCents;
    return v;
  }
  final v = d.value.round();
  if (v < 0) return 0;
  if (v > subtotalCents) return subtotalCents;
  return v;
}
