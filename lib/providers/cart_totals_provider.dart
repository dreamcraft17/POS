import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tax_prefs.dart';
import 'cart_provider.dart';
import 'discount_providers.dart';
import 'tax_settings_provider.dart';

/// Ringkasan angka keranjang — dipakai panel total supaya list cart tidak ikut hitung ulang layout berat.
class CartTotals {
  const CartTotals({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.taxRate,
    required this.taxLabel,
    required this.showDiscount,
    required this.discountLabel,
  });

  final int subtotal;
  final int discount;
  final int tax;
  final int total;
  final double taxRate;
  final String taxLabel;
  final bool showDiscount;
  final String discountLabel;
}

final cartTotalsProvider = Provider<CartTotals>((ref) {
  final cart = ref.watch(cartProvider);
  final selectedDiscount = ref.watch(selectedDiscountProvider);
  final taxSettings = ref.watch(taxSettingsProvider).valueOrNull;
  final taxEnabled = taxSettings?.enabled ?? kDefaultTaxEnabled;
  final taxRatePct = taxSettings?.ratePercent ?? kDefaultTaxRatePct;
  final taxRate = taxEnabled ? (taxRatePct / 100.0) : 0.0;

  final subtotal = cart.fold<int>(0, (s, it) => s + it.priceCents * it.qty);
  final discount = computeDiscountCents(selectedDiscount, subtotal);
  final taxableBase = (subtotal - discount).clamp(0, 1 << 31);
  final tax = (taxableBase * taxRate).round();
  final total = taxableBase + tax;

  final taxPctStr = (taxRate * 100).toStringAsFixed(
    ((taxRate * 100).truncateToDouble() == (taxRate * 100)) ? 0 : 1,
  );
  final taxLabel = 'Tax ($taxPctStr%)';

  final discountLabel = selectedDiscount == null
      ? ''
      : (selectedDiscount.code.isNotEmpty
          ? 'Discount'
          : "Discount (${selectedDiscount.kind.name == 'percent' ? '${selectedDiscount.value.toStringAsFixed(0)}%' : selectedDiscount.name})");

  return CartTotals(
    subtotal: subtotal,
    discount: discount,
    tax: tax,
    total: total,
    taxRate: taxRate,
    taxLabel: taxLabel,
    showDiscount: selectedDiscount != null,
    discountLabel: discountLabel,
  );
});
