import 'package:flutter/material.dart';

import '../../ui/pos_theme.dart';
import '../../utils/formatting.dart';

Widget cartReceiptRow(
  String left,
  String right, {
  bool isBold = false,
  bool big = false,
  bool isAccent = false,
}) {
  final baseStyle = TextStyle(
    color: isAccent ? Colors.green : PosTheme.black,
    fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
    fontSize: big ? 16 : 14,
  );
  final leftStyle = isAccent
      ? baseStyle.copyWith(color: Colors.green)
      : baseStyle.copyWith(color: isBold ? PosTheme.black : PosTheme.muted);

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(child: Text(left, style: leftStyle)),
        const SizedBox(width: 12),
        Text(right, style: baseStyle),
      ],
    ),
  );
}

class CartGlassCard extends StatelessWidget {
  const CartGlassCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 1.5),
          boxShadow: [
            BoxShadow(
              blurRadius: 24,
              color: Colors.black.withValues(alpha: 0.10),
              offset: const Offset(0, 12),
            )
          ],
        ),
        child: child,
      ),
    );
  }
}

Widget cartTotalRow(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: PosTheme.muted)),
          const Spacer(),
          Text(rp(value), style: const TextStyle(color: PosTheme.black)),
        ],
      ),
    );

Widget cartTotalRowBold(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: PosTheme.black, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            rp(value),
            style: const TextStyle(
              color: PosTheme.black,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );

Widget cartTotalRowDiscount(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.green)),
          const Spacer(),
          Text(rp(value), style: const TextStyle(color: Colors.green)),
        ],
      ),
    );

Widget cartSumRow(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: PosTheme.muted)),
          const Spacer(),
          Text(rp(value), style: const TextStyle(color: PosTheme.black)),
        ],
      ),
    );

Widget cartSumRowBold(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: PosTheme.black, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            rp(value),
            style: const TextStyle(
              color: PosTheme.black,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
