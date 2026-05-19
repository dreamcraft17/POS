import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../repositories/auth_repo.dart';
import '../services/api_service.dart';

// ⬇️ SESUAIKAN path ini dengan lokasi BillData/BillLine/ReceiptPrinter di project kamu.
import '../widgets/bill_receipt.dart'
    show BillData, BillLine, ReceiptPrinter;

class OrderDetailPage extends ConsumerWidget {
  final int orderId;
  const OrderDetailPage({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return FutureBuilder<_OrderDetailData>(
      future: _load(ref, orderId),
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || !snap.hasData) {
          return Scaffold(
            appBar: AppBar(title: Text('Order #$orderId')),
            body: Center(child: Text('Failed to load: ${snap.error ?? "unknown"}')),
          );
        }

        final d = snap.data!;
        final fDate = DateFormat('EEE, d MMM yyyy HH:mm');

        return Scaffold(
          appBar: AppBar(
            elevation: 0,
            toolbarHeight: 72,
            centerTitle: true,
            title: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Order #${d.order.id}', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(
                  fDate.format(d.order.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: .7)),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Print receipt',
                icon: const Icon(Icons.print_rounded),
                onPressed: () => _printReceipt(context, d),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              // ===== SUMMARY =====
              _SectionCard(
                title: 'Ringkasan',
                icon: Icons.receipt_long_rounded,
                child: Column(
                  children: [
                    _KV('Subtotal', _rp(d.order.subtotalCents)),
                    _KV('Diskon', _rp(d.order.discountCents)),
                    _KV('Pajak', _rp(d.order.taxCents)),
                    const SizedBox(height: 8),
                    const Divider(),
                    Row(
                      children: [
                        Text('Grand Total', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const Spacer(),
                        Text(
                          _rp(d.order.totalCents),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // ===== ITEMS =====
              _SectionCard(
                title: 'Item',
                icon: Icons.shopping_bag_rounded,
                child: Column(
                  children: [
                    for (final it in d.items) ...[
                      _ItemRow(name: it.name, qty: it.qty, priceEach: it.priceCentsEach),
                      const Divider(height: 16),
                    ],
                  ],
                ),
              ),

              if (d.payments.isNotEmpty) ...[
                const SizedBox(height: 12),

                // ===== PAYMENTS =====
                _SectionCard(
                  title: 'Pembayaran',
                  icon: Icons.payments_rounded,
                  child: Column(
                    children: [
                      for (final p in d.payments) _PaymentTile(p: p),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.print_rounded),
                onPressed: () => _printReceipt(context, d),
                label: const Text('Print Receipt'),
              ),
            ],
          ),
        );
      },
    );
  }

  // ================== PRINT ==================

  Future<void> _printReceipt(BuildContext context, _OrderDetailData d) async {
    try {
      final bill = _buildBillFromDetail(d);
      // ⬇️ Ini otomatis pakai profil "Printer" (customer) yang disimpan di Settings
      await ReceiptPrinter.printWithSavedPrefs(context, bill);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Print failed: $e')),
        );
      }
    }
  }

  BillData _buildBillFromDetail(_OrderDetailData d) {
    // Items → BillLine
    final lines = d.items
        .map((it) => BillLine(name: it.name, qty: it.qty, priceCentsEach: it.priceCentsEach))
        .toList();

    // Payment summary & detail lines
    String? paymentSummary;
    List<String>? paymentLines;
    if (d.payments.isNotEmpty) {
      final methods = d.payments.map((p) => _capitalize(p.method)).toList();
      paymentSummary = methods.join(' + ');
      paymentLines = d.payments.map((p) => '${_capitalize(p.method)} ${_rp(p.amountCents)}').toList();
    }

    // Opsional: cetak "Table: {customerName}" di header jika ada
    final String? tableName = (d.customerName?.isNotEmpty ?? false) ? d.customerName : null;
    final String? orderTypeName = (d.orderTypeName?.isNotEmpty ?? false) ? d.orderTypeName : null;

    return BillData(
      title: '', // biarkan kosong agar fallback ke prefs title/logo
      date: d.order.createdAt,
      items: lines,
      subtotal: d.order.subtotalCents,
      discount: d.order.discountCents,
      tax: d.order.taxCents,
      total: d.order.totalCents,
      footer: '',
      orderId: d.order.id.toString(),
      orderTypeName: orderTypeName,
      paymentSummary: paymentSummary,
      paymentLines: paymentLines,
      tableName: tableName,
    );
  }

  // ================== DATA LOAD ==================

  Future<_OrderDetailData> _load(WidgetRef ref, int id) async {
    final me = await AuthRepo().me(refreshFromServer: false);
    if (me == null) throw Exception('No user in client');
    final api = ApiService.shared();
    final json = await api.orderDetail(id: id, createdBy: me.id);

    final order = _Order.fromJson(Map<String, dynamic>.from(json['order'] as Map));
    final items = (json['items'] as List)
        .map((e) => _OrderItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    final payments = (json['payments'] as List? ?? const [])
        .map((e) => _Payment.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final orderMap = Map<String, dynamic>.from(json['order'] as Map);
    final customerName = _asString(orderMap['customer_name'], '');
    final orderTypeName = _asString(orderMap['order_type_name'], '');

    return _OrderDetailData(
      order: order,
      items: items,
      payments: payments,
      customerName: customerName.isEmpty ? null : customerName,
      orderTypeName: orderTypeName.isEmpty ? null : orderTypeName,
    );
  }
}

/// ===== UI HELPERS =====

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final border = BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: .4));
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.fromBorderSide(border),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            spreadRadius: 0,
            offset: const Offset(0, 4),
            color: Colors.black.withValues(alpha: .04),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const Spacer(),
          ]),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}

class _KV extends StatelessWidget {
  final String k, v;
  const _KV(this.k, this.v);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(k, style: theme.textTheme.bodyMedium),
          const Spacer(),
          Text(v, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final String name;
  final int qty;
  final int priceEach;
  const _ItemRow({required this.name, required this.qty, required this.priceEach});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
        ),
        const SizedBox(width: 12),
        Text('x$qty • ${_rp(priceEach)}', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: .7))),
        const SizedBox(width: 12),
        Text(
          _rp(qty * priceEach),
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _PaymentTile extends StatelessWidget {
  final _Payment p;
  const _PaymentTile({required this.p});

  IconData _icon(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return Icons.attach_money_rounded;
      case 'card':
        return Icons.credit_card_rounded;
      case 'qris':
        return Icons.qr_code_2_rounded;
      case 'transfer':
        return Icons.account_balance_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = DateFormat('d MMM yyyy HH:mm');
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        radius: 16,
        child: Icon(_icon(p.method), size: 18),
      ),
      title: Text(p.method[0].toUpperCase() + p.method.substring(1)),
      subtitle: Text(f.format(p.at)),
      trailing: Text(_rp(p.amountCents), style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w800)),
    );
  }
}

/// ===== UTIL =====

String _rp(int cents) {
  final s = NumberFormat.decimalPattern('id_ID').format(cents);
  return 'Rp$s';
}

String _capitalize(String s) {
  if (s.isEmpty) return s;
  return s[0].toUpperCase() + s.substring(1).toLowerCase();
}

/// ===== MODELS =====

class _Order {
  final int id;
  final DateTime createdAt;
  final int subtotalCents;
  final int discountCents;
  final int taxCents;
  final int totalCents;

  _Order({
    required this.id,
    required this.createdAt,
    required this.subtotalCents,
    required this.discountCents,
    required this.taxCents,
    required this.totalCents,
  });

  factory _Order.fromJson(Map<String, dynamic> m) => _Order(
        id: _asInt(m['id']),
        createdAt: _asDate(m['created_at']),
        subtotalCents: _asInt(m['subtotal_cents']),
        discountCents: _asInt(m['discount_cents']),
        taxCents: _asInt(m['tax_cents']),
        totalCents: _asInt(m['total_cents']),
      );
}

class _OrderItem {
  final String name;
  final int qty;
  final int priceCentsEach;

  _OrderItem({required this.name, required this.qty, required this.priceCentsEach});

  factory _OrderItem.fromJson(Map<String, dynamic> m) => _OrderItem(
        name: _asString(m['name'], '(no name)'),
        qty: _asInt(m['qty'], 1),
        priceCentsEach: _asInt(m['price_cents_each']),
      );
}

class _Payment {
  final String method;
  final int amountCents;
  final DateTime at;

  _Payment({required this.method, required this.amountCents, required this.at});

  factory _Payment.fromJson(Map<String, dynamic> m) => _Payment(
        method: _asString(m['method'], '-'),
        amountCents: _asInt(m['amount_cents']),
        at: _asDate(m['at']),
      );
}

class _OrderDetailData {
  final _Order order;
  final List<_OrderItem> items;
  final List<_Payment> payments;
  // Opsional (untuk "Table: ...")
  final String? customerName;
  final String? orderTypeName;

  _OrderDetailData({
    required this.order,
    required this.items,
    required this.payments,
    this.customerName,
    this.orderTypeName,
  });
}

int _asInt(dynamic v, [int def = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? def;
  return def;
}

String _asString(dynamic v, [String def = '']) => v?.toString() ?? def;

DateTime _asDate(dynamic v) {
  final s = v?.toString();
  if (s == null || s.isEmpty) return DateTime.now();
  try {
    return DateTime.parse(s);
  } catch (_) {
    return DateTime.now();
  }
}
