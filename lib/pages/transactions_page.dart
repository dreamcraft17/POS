import 'package:ee_pos/pages/order_detail_page.dart';
import 'package:ee_pos/repositories/auth_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:ee_pos/pages/order_detail_page.dart';
import '../providers/auth_providers.dart'; // if you need auth context
import '../services/api_service.dart';     // wherever ApiService is

final _ordersProvider = FutureProvider.autoDispose<List<_Order>>((ref) async {
  final api = ApiService.shared();

  // Pull cached user (no network). Adjust if you keep a user provider already.
  final me = await AuthRepo().me(refreshFromServer: false);
  if (me == null) return <_Order>[]; // not logged in locally => empty list

  final list = await api.orders(createdBy: me.id);
  return list.map(_Order.fromJson).toList();
});

class TransactionsPage extends ConsumerWidget {
  const TransactionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_ordersProvider);

    return Scaffold(
      appBar: MediaQuery.of(context).size.width < 900
          ? AppBar(title: const Text('Transactions'))
          : null,
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Failed to load: $e')),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No transactions yet'));
          }

          // group by yyyy-MM-dd
          final byDate = <String, List<_Order>>{};
          for (final o in orders) {
            final key = DateFormat('yyyy-MM-dd').format(o.createdAt);
            (byDate[key] ??= []).add(o);
          }

          final sortedKeys = byDate.keys.toList()
            ..sort((a, b) => b.compareTo(a)); // newest first

          return RefreshIndicator(
             onRefresh: () async => ref.refresh(_ordersProvider.future),
           child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            itemBuilder: (ctx, idx) {
              final k = sortedKeys[idx];
              final day = DateTime.parse(k);
              final title = DateFormat('EEE, d MMM yyyy').format(day);
              final rows = byDate[k]!;
              final dayTotal = rows.fold<int>(0, (s, o) => s + o.totalCents);

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Text(title, style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Text(_rp(dayTotal),
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const Divider(height: 18),
...rows.map((o) => ListTile(
  dense: true,
  leading: CircleAvatar(radius: 16, child: Text('${o.id}')),
  title: Text('Order #${o.id}'),
  subtitle: Text(
    'Subtotal ${_rp(o.subtotalCents)} • Disc ${_rp(o.discountCents)} • Tax ${_rp(o.taxCents)}',
    style: const TextStyle(color: Colors.black54),
  ),
  trailing: Text(_rp(o.totalCents), style: const TextStyle(fontWeight: FontWeight.w700)),
  onTap: () {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OrderDetailPage(orderId: o.id),
    ));
  },
)),

                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: sortedKeys.length,
           ),
          );//listview
        },
      ),
    );
  }
}

String _rp(int cents) {
  // Treat cents as IDR (no decimals). If you truly use cents, change formatting.
  final v = cents; // cents already integer IDR in your project
  final s = NumberFormat.decimalPattern('id_ID').format(v);
  return 'Rp$s';
}

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
        id: (m['id'] as num).toInt(),
        createdAt: DateTime.parse('${m['created_at']}'),
        subtotalCents: (m['subtotal_cents'] as num).toInt(),
        discountCents: (m['discount_cents'] as num).toInt(),
        taxCents: (m['tax_cents'] as num).toInt(),
        totalCents: (m['total_cents'] as num).toInt(),
      );
}
