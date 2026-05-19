import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'formatters.dart';
import 'order_data_source.dart';
import 'shift_repo.dart';
import 'shift_service.dart';
import 'shift_printer.dart';
import 'shift_history_repo.dart';
import '../services/api_service.dart';

/// Shift Page (manual start, UI mengikuti 307d):
/// - Hapus auto-start shift (TIDAK ada auto start).
/// - Start shift via bottom sheet (input opening cash) + aturan startAt menyesuaikan trx pertama - 30 menit.
/// - Tampilan memakai Scaffold + AppBar, RefreshIndicator, section headers, action buttons,
///   dan Paper Size selector seperti 307d.
class ShiftPage extends StatefulWidget {
  final String outletName;
  final String cashierName;
  final int currentUserId;
  final Future<void> Function(String text)? sendToPrinter;

  const ShiftPage({
    super.key,
    required this.outletName,
    required this.cashierName,
    required this.currentUserId,
    this.sendToPrinter,
  });

  @override
  State<ShiftPage> createState() => _ShiftPageState();
}

class _ShiftPageState extends State<ShiftPage> {
  final _repo = ShiftRepo();
  ShiftService? _svc;

  DateTime? _startAt;
  int _openingCashCents = 0;
  ShiftSummary? _sum;
  bool _loading = false;
  bool _initing = true;
  String _paper = '58';

  // Alias tampilan nama metode pembayaran (optional)
  static const Map<String, String> _methodAliases = {
    'cash': 'Cash',
    'qris': 'EDC BCA QRIS',
    'edc': 'Debit / Kredit',
  };

  String _aliasOr(String method) => _methodAliases[method] ?? method;

  @override
  void initState() {
    super.initState();
    _initAll();
  }

  Future<void> _initAll() async {
    setState(() => _initing = true);
    await _loadPaperPref();

    final ds = await OrderDataSource.withMenuPriceIndex(
      api: ApiService.shared(),
      currentUserId: widget.currentUserId,
    );
    _svc = ShiftService(ds);

    await _loadShift();
    if (!mounted) return;
    setState(() => _initing = false);
  }

  Future<void> _loadPaperPref() async {
    final sp = await SharedPreferences.getInstance();
    final v = sp.getString('shift.paper');
    _paper = (v == '58' || v == '80') ? v! : '58';
  }

  Future<void> _savePaperPref(String v) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('shift.paper', v);
  }

  Future<void> _loadShift() async {
    final curr = await _repo.current();
    if (!mounted) return;

    // ❌ TIDAK ada auto-start. Hanya baca state tersimpan.
    setState(() {
      _startAt = curr.startAt;
      _openingCashCents = curr.openingCashCents;
    });
    await _refreshSummary();
  }

  Future<void> _refreshSummary() async {
    if (_svc == null || _startAt == null) {
      setState(() => _sum = null);
      return;
    }
    setState(() => _loading = true);
    final s = await _svc!.compute(startAt: _startAt!);
    if (!mounted) return;
    setState(() {
      _sum = s;
      _loading = false;
    });
  }

  Future<void> _startShiftSheet() async {
    final formKey = GlobalKey<FormState>();
    final ctrl = TextEditingController(text: '0');
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final viewInsets = MediaQuery.of(ctx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: viewInsets.bottom),
          child: Form(
            key: formKey,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Mulai Shift',
                      style: Theme.of(ctx).textTheme.titleLarge!.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(ctx).colorScheme.primary,
                          )),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ctrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Opening Cash (Rp)',
                      prefixText: 'Rp ',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Wajib diisi';
                      final parsed = int.tryParse(
                        v.replaceAll('.', '').replaceAll(',', '').trim(),
                      );
                      if (parsed == null || parsed < 0) return 'Nominal tidak valid';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            if (formKey.currentState?.validate() == true) {
                              Navigator.pop(ctx, true);
                            }
                          },
                          icon: const Icon(Icons.play_arrow_rounded),
                          label: const Text('Mulai'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (ok != true) return;

    // Ambil nominal opening cash
    final opening = int.parse(
      ctrl.text.replaceAll('.', '').replaceAll(',', ''),
    );

    // Tentukan startAt manual (default: sekarang)
    DateTime candidate = DateTime.now();

    // Aturan: kalau startAt (candidate) > trx pertama hari ini,
    // maka startAt = trx pertama - 30 menit
    try {
      if (_svc != null) {
        final now = DateTime.now();
        final startOfToday = DateTime(now.year, now.month, now.day);
        final ordersToday = await _svc!.dataSource.listOrdersSince(startOfToday);
        if (ordersToday.isNotEmpty) {
          ordersToday.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          final first = ordersToday.first.createdAt;
          if (candidate.isAfter(first)) {
            candidate = first.subtract(const Duration(minutes: 30));
          }
        }
      }
    } catch (_) {
      // Jika gagal cek, pakai candidate apa adanya (now)
    }

    setState(() => _loading = true);
    await _repo.startShift(openingCashCents: opening, startAt: candidate);
    await _loadShift();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Shift dimulai')));
  }

  Future<void> _endShift() async {
    if (_startAt == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Akhiri Shift?'),
        content: const Text('Pastikan semua transaksi sudah diproses.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Akhiri'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _loading = true);
    await _refreshSummary();

    try {
      if (_sum != null && _startAt != null) {
        final endNow = DateTime.now();
        final entry = ShiftHistoryEntry(
          startAt: _sum!.startAt,
          endAt: endNow,
          openingCashCents: _openingCashCents,
          summary: _sum!.copyWith(endAt: endNow),
        );
        await ShiftHistoryRepo().add(entry);
      }
    } catch (_) {}

    await _repo.endShift();
    await _loadShift();
    if (!mounted) return;
    setState(() => _loading = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Shift diakhiri & tersimpan ke riwayat')),
    );
  }

  Future<void> _printCurrent() async {
    if (_startAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada shift berjalan')),
      );
      return;
    }
    if (_sum == null) await _refreshSummary();
    if (_sum == null) return;
    setState(() => _loading = true);
    try {
      await ShiftPrinter.print(
        context,
        companyHeader: const [],
        outletName: widget.outletName,
        cashierName: widget.cashierName,
        openingCashCents: _openingCashCents,
        sum: _sum!,
        methodAliases: _methodAliases,
        paper: _paper,
        logoAsset: 'assets/receipt/logo_bill.png',
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  // --- UI build ---
  @override
  Widget build(BuildContext context) {
    final running = _startAt != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Current Shift'), centerTitle: true),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _loadShift,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!running && !_initing) ...[
                  FilledButton.icon(
                    onPressed: _startShiftSheet,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start New Shift'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                if (running)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (running && !_initing) ? _endShift : null,
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: const Text('End Current Shift'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: (running && !_initing) ? _printCurrent : null,
                          style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16)),
                          child: const Text('Print Current Shift'),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 20),

                _sectionHeader('SHIFT DETAILS'),
                _kv('Name', widget.cashierName),
                _kv('Outlet', widget.outletName),
                _kv('Starting Shift',
                    _startAt == null ? '-' : _startAt!.toLocal().toString()),
                _kv('Opening Cash', rp(_openingCashCents)),
                const SizedBox(height: 16),

                _sectionHeader('ORDER DETAILS'),
                _kv('Sold Items', _sum == null ? '-' : '${_sum!.soldItems}'),
                _kv('Refunded Items', '0'),

                const SizedBox(height: 16),
                _sectionHeader('Income Summary from each Payment Method'),
                _paymentBreakdown(),

                const SizedBox(height: 40),
                _paperSelector(),
              ],
            ),
          ),
          if (_loading || _initing)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.05),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: Theme.of(context).textTheme.labelLarge!.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                )),
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 240,
                child: Text(k,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium!
                        .copyWith(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant))),
            const SizedBox(width: 8),
            Expanded(child: Text(v, style: Theme.of(context).textTheme.bodyLarge))
          ],
        ),
      );

  Widget _paymentBreakdown() {
    final sum = _sum;
    if (sum == null || sum.byPayment.isEmpty) {
      return _kv('—', '-');
    }

    // Urutkan by nominal desc
    final entries = sum.byPayment.entries.toList()
      ..sort((a, b) => (b.value).compareTo(a.value));
    final total = entries.fold<int>(0, (acc, e) => acc + (e.value));

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          children: [
            for (final e in entries) _rowPay(_aliasOr(e.key), rp(e.value)),
            const Divider(),
            _rowPay('TOTAL', rp(total), isTotal: true),
          ],
        ),
      ),
    );
  }

  Widget _rowPay(String left, String right, {bool isTotal = false}) {
    final styleLeft = isTotal
        ? Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyLarge!;
    final styleRight = isTotal
        ? Theme.of(context).textTheme.titleMedium!.copyWith(fontWeight: FontWeight.w800)
        : Theme.of(context).textTheme.bodyLarge!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, style: styleLeft)),
          Text(right, style: styleRight),
        ],
      ),
    );
  }

  Widget _paperSelector() {
    final cs = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paper Size',
                style: Theme.of(context).textTheme.titleMedium!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.primary,
                    )),
            const SizedBox(height: 12),
            Wrap(spacing: 10, children: [
              ChoiceChip(
                label: const Text('58 mm'),
                selected: _paper == '58',
                onSelected: (s) async {
                  setState(() => _paper = '58');
                  await _savePaperPref('58');
                },
                selectedColor: cs.primary.withValues(alpha: .2),
              ),
              ChoiceChip(
                label: const Text('80 mm'),
                selected: _paper == '80',
                onSelected: (s) async {
                  setState(() => _paper = '80');
                  await _savePaperPref('80');
                },
                selectedColor: cs.primary.withValues(alpha: .2),
              ),
            ]),
            const SizedBox(height: 8),
            Text(
              _paper == '58' ? 'Lebar karakter ±32 kolom.' : 'Lebar karakter ±48 kolom.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

extension _ShiftSummaryCopy on ShiftSummary {
  ShiftSummary copyWith({
    DateTime? startAt,
    DateTime? endAt,
    int? ordersCount,
    int? soldItems,
    int? grossCents,
    int? discountCents,
    int? taxCents,
    int? netCents,
    Map<String, int>? byPayment,
    List<SoldItem>? items,
  }) {
    return ShiftSummary(
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      ordersCount: ordersCount ?? this.ordersCount,
      soldItems: soldItems ?? this.soldItems,
      grossCents: grossCents ?? this.grossCents,
      discountCents: discountCents ?? this.discountCents,
      taxCents: taxCents ?? this.taxCents,
      netCents: netCents ?? this.netCents,
      byPayment: byPayment ?? this.byPayment,
      items: items ?? this.items,
    );
  }
}
