// lib/shift/shift_printer.dart
import 'package:flutter/material.dart';
import 'formatters.dart';
import 'shift_service.dart';
import '../services/receipt_printer.dart';

class ShiftPrinter {
  /// Cetak shift report mirip Moka, sekarang bisa pakai logo dari assets.
  ///
  /// [logoAsset] contoh: 'assets/receipt/logo_bill.png'.
  /// Jika [logoAsset] null, akan pakai [companyHeader] (teks) seperti sebelumnya.
  static Future<void> print(
    BuildContext context, {
    // Header teks (dipakai jika logoAsset == null)
    required List<String> companyHeader,
    required String outletName,
    required String cashierName,
    required int openingCashCents,
    required ShiftSummary sum,
    int? actualEndingCashCents,
    Map<String, String>? methodAliases,
    String profilePrefix = 'printer',
    String paper = '58', // '58' => 32 kolom, '80' => 48 kolom
    String? logoAsset,   // jika ada, header pakai logo
  }) async {
    // Lebar berdasarkan ukuran kertas
    final int width = (paper == '80') ? 48 : 32;

    String line() => '-' * width;

    String center(String s) {
      if (s.length >= width) return s;
      final left = ((width - s.length) / 2).floor();
      final right = width - s.length - left;
      return ' ' * left + s + ' ' * right;
    }

    String col2(String left, String right) {
      left = left.trimRight();
      right = right.trimLeft();
      final space = width - left.length - right.length;
      return (space >= 1) ? '$left${' ' * space}$right' : '$left $right';
    }

    String money(int cents) => rp(cents);

    /// Satu baris item: "qty name .... total"
    String formatItemLine({
      required String name,
      required int qty,
      required int totalCents,
    }) {
      final left = '$qty $name';
      final right = money(totalCents);
      final maxLeft = width - right.length - 1;
      final clipped = left.length > maxLeft ? left.substring(0, maxLeft) : left;
      final pad = maxLeft - clipped.length;
      return '${clipped}${' ' * (pad < 0 ? 0 : pad)} $right';
    }

    /// Tambah judul section dengan jarak 1 baris kosong sebelumnya.
    void addSection(List<String> out, String title, {bool addDivider = true}) {
      if (out.isNotEmpty && out.last.isNotEmpty) out.add(''); // spasi antar section
      out.add(title);
      if (addDivider) out.add(line());
    }

    // ====== Kelompokkan pembayaran ======
    final alias = methodAliases ?? const {};
    int cashTotal = 0, edcTotal = 0, digitalTotal = 0;
    final edcBreakdown = <String, int>{};
    final digitalBreakdown = <String, int>{};

    sum.byPayment.forEach((method, amount) {
      final m = (alias[method] ?? method).toUpperCase();
      if (m.contains('CASH')) {
        cashTotal += amount;
      } else if (m.contains('EDC') ||
          m.contains('CARD') ||
          m.contains('DEBIT') ||
          m.contains('CREDIT')) {
        edcTotal += amount;
        final key = m.replaceAll('EDC ', '').trim();
        final normalized = key.isEmpty ? 'EDC' : key;
        edcBreakdown[normalized] = (edcBreakdown[normalized] ?? 0) + amount;
      } else {
        digitalTotal += amount;
        digitalBreakdown[m] = (digitalBreakdown[m] ?? 0) + amount;
      }
    });

    // ====== Cash Management ======
    final cashSales = cashTotal;
    final cashFromInvoice = 0;
    final cashRefunds = 0;
    final expectedEndingCash =
        openingCashCents + cashSales + cashFromInvoice - cashRefunds;
    final endingCashActual = actualEndingCashCents ?? expectedEndingCash;
    final cashDiff = endingCashActual - expectedEndingCash;

    // ====== Susun teks ======
    final lines = <String>[];

    // Header: pakai logo jika tersedia, kalau tidak fallback ke teks header
    if (logoAsset != null && logoAsset.isNotEmpty) {
      lines.add('IMG:$logoAsset'); // NOTE: jangan pakai bracket []
    } else {
      for (final h in companyHeader) {
        lines.add(h);
      }
    }

    lines.add(line());
    lines.add(center('SHIFT PRINT'));
    lines.add(line());
    lines.add(col2('Name', outletName));
    lines.add(col2('Start Date', sum.startAt.toString()));
    lines.add(col2('End Date', sum.endAt.toString()));
    lines.add(col2('Sold Items', '${sum.soldItems}'));
    lines.add(col2('Refunded Items', '0'));

    // ========= Cash Management =========
    addSection(lines, 'CASH MANAGEMENT');
    lines.add(col2('Starting Cash Drawer', money(openingCashCents)));
    lines.add(col2('Cash Payment', money(cashSales)));
    lines.add(col2('Cash from Invoice', money(cashFromInvoice)));
    lines.add(col2('Cash Refunds', money(cashRefunds)));
    lines.add(col2('Expected Ending Cash', money(expectedEndingCash)));
    lines.add(col2('Actual Ending Cash', money(endingCashActual)));
    lines.add(col2('Cash Difference', money(cashDiff)));

    // ========= Order Details / Sold Items =========
    addSection(lines, 'ORDER DETAILS');
    lines.add('SOLD ITEMS');
    lines.add(line());
    for (final it in sum.items) {
      lines.add(formatItemLine(
        name: it.name,
        qty: it.qty,
        totalCents: it.totalCents,
      ));
      lines.add(''); // ⬅️ Jarak antar item supaya tidak rapat
    }
    if (lines.isEmpty || lines.last.isNotEmpty) lines.add('');
    lines.add(line());

    // Ringkasan total/discount/rounding
    addSection(lines, 'SUMMARY', addDivider: false);
    lines.add(col2('ROUNDING', money(0))); // set jika ada pembulatan
    lines.add(col2('TOTAL AMOUNT', money(sum.netCents)));
    lines.add(line());
    lines.add('DISCOUNTS');
    lines.add(col2('All Discount', money(sum.discountCents)));
    lines.add(col2('TOTAL AMOUNT', money(sum.netCents - sum.discountCents)));

    // ========= Payment Detail =========
    addSection(lines, 'PAYMENT DETAIL');

    // Cash
    lines.add('CASH PAYMENT');
    lines.add(line());
    lines.add(col2('Cash Sales', money(cashSales)));
    lines.add(col2('Cash from Invoice', money(cashFromInvoice)));
    lines.add(col2('Cash Refunds', money(cashRefunds)));
    lines.add(col2('TOTAL AMOUNT', money(cashSales + cashFromInvoice - cashRefunds)));

    // EDC
    addSection(lines, 'EDC PAYMENT');
    if (edcBreakdown.isEmpty) {
      lines.add(col2('—', money(0)));
    } else {
      edcBreakdown.forEach((k, v) => lines.add(col2(k, money(v))));
    }
    lines.add(col2('TOTAL AMOUNT', money(edcTotal)));

    // Digital
    addSection(lines, 'DIGITAL PAYMENT');
    if (digitalBreakdown.isEmpty) {
      lines.add(col2('—', money(0)));
    } else {
      digitalBreakdown.forEach((k, v) => lines.add(col2(k, money(v))));
    }
    lines.add(col2('TOTAL AMOUNT', money(digitalTotal)));

    // ========= Total Transaction =========
    addSection(lines, 'TOTAL TRANSACTION', addDivider: false);
    lines.add(col2(
      'TOTAL TRANSACTION',
      money(cashTotal + edcTotal + digitalTotal),
    ));

    lines.add('');
    lines.add(center('Printed by $cashierName'));
    lines.add('');

    // Kirim ke printer sesuai setting
    await ReceiptPrinter.printWithSavedPrefs(
      context,
      lines,
      profilePrefix: profilePrefix,
    );
  }
}
 