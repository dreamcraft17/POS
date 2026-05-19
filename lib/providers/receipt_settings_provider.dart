import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class ReceiptSettings {
  final String title;
  final String footer;
  final String dateFormat; // 'dd/MM/yyyy HH:mm' | 'yyyy-MM-dd HH:mm' | 'dd MMM yyyy HH:mm'
  final bool showOrderId;
  final bool showPayment;
  final bool showSubtotal;
  final bool showTax;
  final String taxLabel;
  final String paper; // '58' | '80'
  final bool centerTotal;
  final int cutFeed; // 0..5

  const ReceiptSettings({
    required this.title,
    required this.footer,
    required this.dateFormat,
    required this.showOrderId,
    required this.showPayment,
    required this.showSubtotal,
    required this.showTax,
    required this.taxLabel,
    required this.paper,
    required this.centerTotal,
    required this.cutFeed,
  });

  static const def = ReceiptSettings(
    title: 'e+e Coffee Kitchen',
    footer: 'thank you',
    dateFormat: 'dd/MM/yyyy HH:mm',
    showOrderId: true,
    showPayment: true,
    showSubtotal: true,
    showTax: true,
    taxLabel: 'PPN (10%)',
    paper: '58',
    centerTotal: false,
    cutFeed: 0,
  );

  ReceiptSettings copyWith({
    String? title,
    String? footer,
    String? dateFormat,
    bool? showOrderId,
    bool? showPayment,
    bool? showSubtotal,
    bool? showTax,
    String? taxLabel,
    String? paper,
    bool? centerTotal,
    int? cutFeed,
  }) =>
      ReceiptSettings(
        title: title ?? this.title,
        footer: footer ?? this.footer,
        dateFormat: dateFormat ?? this.dateFormat,
        showOrderId: showOrderId ?? this.showOrderId,
        showPayment: showPayment ?? this.showPayment,
        showSubtotal: showSubtotal ?? this.showSubtotal,
        showTax: showTax ?? this.showTax,
        taxLabel: taxLabel ?? this.taxLabel,
        paper: paper ?? this.paper,
        centerTotal: centerTotal ?? this.centerTotal,
        cutFeed: cutFeed ?? this.cutFeed,
      );
}

class ReceiptSettingsNotifier extends StateNotifier<ReceiptSettings> {
  ReceiptSettingsNotifier() : super(ReceiptSettings.def) {
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = state.copyWith(
      title: p.getString('receipt_title') ?? state.title,
      footer: p.getString('receipt_footer') ?? state.footer,
      dateFormat: p.getString('receipt_date_format') ?? state.dateFormat,
      showOrderId: p.getBool('receipt_show_order') ?? state.showOrderId,
      showPayment: p.getBool('receipt_show_payment') ?? state.showPayment,
      showSubtotal: p.getBool('receipt_show_subtotal') ?? state.showSubtotal,
      showTax: p.getBool('receipt_show_tax') ?? state.showTax,
      taxLabel: p.getString('receipt_tax_label') ?? state.taxLabel,
      paper: p.getString('receipt_paper') ?? state.paper,
      centerTotal: p.getBool('receipt_center_total') ?? state.centerTotal,
      cutFeed: p.getInt('receipt_cut_feed') ?? state.cutFeed,
    );
  }

  Future<void> save(ReceiptSettings next) async {
    state = next;
    final p = await SharedPreferences.getInstance();
    await p.setString('receipt_title', next.title);
    await p.setString('receipt_footer', next.footer);
    await p.setString('receipt_date_format', next.dateFormat);
    await p.setBool('receipt_show_order', next.showOrderId);
    await p.setBool('receipt_show_payment', next.showPayment);
    await p.setBool('receipt_show_subtotal', next.showSubtotal);
    await p.setBool('receipt_show_tax', next.showTax);
    await p.setString('receipt_tax_label', next.taxLabel);
    await p.setString('receipt_paper', next.paper);
    await p.setBool('receipt_center_total', next.centerTotal);
    await p.setInt('receipt_cut_feed', next.cutFeed);
  }
}

final receiptSettingsProvider =
    StateNotifierProvider<ReceiptSettingsNotifier, ReceiptSettings>(
        (_) => ReceiptSettingsNotifier());
