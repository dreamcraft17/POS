import 'package:ee_pos/shift/shift_history_detail_page.dart';
import 'package:flutter/material.dart';
import 'formatters.dart';
import 'shift_printer.dart';
import 'shift_history_repo.dart';

class ShiftHistoryPage extends StatefulWidget {
  final String outletName;
  final String cashierNameForReprint;
  final String paper;
  final Map<String, String>? methodAliases;
  final String? logoAsset;

  const ShiftHistoryPage({
    super.key,
    required this.outletName,
    required this.cashierNameForReprint,
    this.paper = '58',
    this.methodAliases,
    this.logoAsset,
  });

  @override
  State<ShiftHistoryPage> createState() => _ShiftHistoryPageState();
}

class _ShiftHistoryPageState extends State<ShiftHistoryPage> {
  final _repo = ShiftHistoryRepo();
  List<ShiftHistoryEntry> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _repo.list();
    if (!mounted) return;
    setState(() {
      _rows = data;
      _loading = false;
    });
  }

  Future<void> _print(ShiftHistoryEntry e) async {
    await ShiftPrinter.print(
      context,
      companyHeader: const [],
      outletName: widget.outletName,
      cashierName: widget.cashierNameForReprint,
      openingCashCents: e.openingCashCents,
      sum: e.summary,
      methodAliases: widget.methodAliases,
      paper: widget.paper,
      logoAsset: widget.logoAsset,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shift report dicetak')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shift History'), centerTitle: true),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _load,
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _rows.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (ctx, i) {
                final e = _rows[i];
                final period =
                    '${e.startAt.toLocal()}  →  ${e.endAt.toLocal()}';
                return ListTile(
  title: Text(period, style: const TextStyle(fontWeight: FontWeight.w600)),
  subtitle: Text(
    'Items: ${e.summary.soldItems} · Orders: ${e.summary.ordersCount}\n'
    'Net: ${rp(e.summary.netCents)} · Discount: ${rp(e.summary.discountCents)}',
  ),
  isThreeLine: true,
  trailing: IconButton(
    icon: const Icon(Icons.print),
    tooltip: 'Cetak ulang',
    onPressed: () => _print(e),
  ),
  onTap: () {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ShiftHistoryDetailPage(
          entry: e,
          outletName: widget.outletName,
          cashierNameForReprint: widget.cashierNameForReprint,
          paper: widget.paper,
          methodAliases: widget.methodAliases,
          logoAsset: widget.logoAsset,
        ),
      ),
    );
  },
);
              },
            ),
          ),
          if (_loading)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x0A000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}
