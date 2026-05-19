import 'package:flutter/material.dart';
import 'formatters.dart';
import 'shift_history_repo.dart';
import 'shift_printer.dart';
import 'shift_service.dart';

class ShiftHistoryDetailPage extends StatelessWidget {
  final ShiftHistoryEntry entry;
  final String outletName;
  final String cashierNameForReprint;
  final String paper; // '58' or '80'
  final Map<String, String>? methodAliases;
  final String? logoAsset;

  const ShiftHistoryDetailPage({
    super.key,
    required this.entry,
    required this.outletName,
    required this.cashierNameForReprint,
    this.paper = '58',
    this.methodAliases,
    this.logoAsset,
  });

  Map<String, dynamic> _groupPayments(ShiftSummary sum) {
    final alias = methodAliases ?? const {};
    int cashTotal = 0, edcTotal = 0, digitalTotal = 0;
    final edcBreakdown = <String, int>{};
    final digitalBreakdown = <String, int>{};

    sum.byPayment.forEach((method, amount) {
      final m = (alias[method] ?? method).toUpperCase();
      if (m.contains('CASH')) {
        cashTotal += amount;
      } else if (m.contains('EDC') || m.contains('CARD') || m.contains('DEBIT') || m.contains('CREDIT')) {
        edcTotal += amount;
        final key = m.replaceAll('EDC ', '').trim();
        edcBreakdown[key.isEmpty ? 'EDC' : key] =
            (edcBreakdown[key.isEmpty ? 'EDC' : key] ?? 0) + amount;
      } else {
        digitalTotal += amount;
        digitalBreakdown[m] = (digitalBreakdown[m] ?? 0) + amount;
      }
    });

    return {
      'cashTotal': cashTotal,
      'edcTotal': edcTotal,
      'digitalTotal': digitalTotal,
      'edcBreakdown': edcBreakdown,
      'digitalBreakdown': digitalBreakdown,
    };
  }

  @override
  Widget build(BuildContext context) {
    final sum = entry.summary;
    final gp = _groupPayments(sum);

    final opening = entry.openingCashCents;
    final expectedEndingCash = opening + (gp['cashTotal'] as int);
    final items = sum.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Shift History Detail"),
        actions: [
          IconButton(
            tooltip: 'Cetak ulang',
            icon: const Icon(Icons.print),
            onPressed: () async {
              await ShiftPrinter.print(
                context,
                companyHeader: const [],
                outletName: outletName,
                cashierName: cashierNameForReprint,
                openingCashCents: entry.openingCashCents,
                sum: sum,
                paper: paper,
                methodAliases: methodAliases,
                logoAsset: logoAsset,
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Shift report dicetak')),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionCard("PERIOD", [
            _kv("Start", sum.startAt.toLocal().toString()),
            _kv("End", sum.endAt.toLocal().toString()),
            _kv("Orders", '${sum.ordersCount}'),
            _kv("Sold Items", '${sum.soldItems}'),
          ]),
          _sectionCard("TOTALS", [
            _kv("Gross", rp(sum.grossCents)),
            _kv("Discount", rp(sum.discountCents)),
            _kv("Tax", rp(sum.taxCents)),
            _kv("Net", rp(sum.netCents)),
          ]),
          _sectionCard("CASH MANAGEMENT", [
            _kv("Opening Cash", rp(opening)),
            _kv("Cash Sales", rp(gp['cashTotal'] as int)),
            _kv("Expected Ending Cash", rp(expectedEndingCash)),
          ]),
          _sectionCard("PAYMENTS", [
            _kv("Cash", rp(gp['cashTotal'] as int)),
            const Divider(),
            const Text("EDC", style: TextStyle(fontWeight: FontWeight.bold)),
            ...((gp['edcBreakdown'] as Map<String, int>)
                .entries
                .map((e) => _kv(e.key, rp(e.value)))),
            _kv("EDC Total", rp(gp['edcTotal'] as int)),
            const Divider(),
            const Text("Digital", style: TextStyle(fontWeight: FontWeight.bold)),
            ...((gp['digitalBreakdown'] as Map<String, int>)
                .entries
                .map((e) => _kv(e.key, rp(e.value)))),
            _kv("Digital Total", rp(gp['digitalTotal'] as int)),
          ]),
          _sectionCard("SOLD ITEMS", [
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text("— No items —"),
              )
            else
              Column(
                children: items
                    .map((it) => ListTile(
                          dense: true,
                          title: Text("${it.qty}  ${it.name}"),
                          trailing: Text(rp(it.totalCents),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                        ))
                    .toList(),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
                flex: 2,
                child: Text(k,
                    style: const TextStyle(color: Colors.black54, fontSize: 14))),
            Expanded(
                flex: 3,
                child: Text(v,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14))),
          ],
        ),
      );
}
