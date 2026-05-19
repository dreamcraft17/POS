import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/open_bills_repo.dart';
import '../providers/cart_provider.dart';
import '../models/product.dart';
import '../utils/formatting.dart';

/// Utility: pretty age like "2 h 36 min", "24 h 54 min", "0 min"
String timeAgoShort(DateTime from) {
  final dur = DateTime.now().difference(from);
  final h = dur.inHours;
  final m = dur.inMinutes.remainder(60);
  if (h <= 0) return '$m min';
  return '$h h ${m} min';
}

class OpenBillsPage extends ConsumerStatefulWidget {
  const OpenBillsPage({super.key});
  @override
  ConsumerState<OpenBillsPage> createState() => _OpenBillsPageState();
}

class _OpenBillsPageState extends ConsumerState<OpenBillsPage>
    with SingleTickerProviderStateMixin {
  final repo = OpenBillsRepo();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _openDrafts = [];
  List<Map<String, dynamic>> _cancelled = [];
  List<Map<String, dynamic>> _done = [];
  bool _loading = true;

  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 4, vsync: this);
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tab.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final open = await repo.listDrafts();
    final cancelled = await repo.listCancelled();
    final done = await repo.listDone();

    open.sort((a, b) {
      final ad = DateTime.tryParse('${a['created_at'] ?? ''}') ?? DateTime(2000);
      final bd = DateTime.tryParse('${b['created_at'] ?? ''}') ?? DateTime(2000);
      return bd.compareTo(ad);
    });
    cancelled.sort((a, b) {
      final ad = DateTime.tryParse('${a['cancelled_at'] ?? a['created_at'] ?? ''}') ?? DateTime(2000);
      final bd = DateTime.tryParse('${b['cancelled_at'] ?? b['created_at'] ?? ''}') ?? DateTime(2000);
      return bd.compareTo(ad);
    });
    done.sort((a, b) {
      final ad = DateTime.tryParse('${a['done_at'] ?? a['created_at'] ?? ''}') ?? DateTime(2000);
      final bd = DateTime.tryParse('${b['done_at'] ?? b['created_at'] ?? ''}') ?? DateTime(2000);
      return bd.compareTo(ad);
    });
    setState(() {
      _openDrafts = open;
      _cancelled = cancelled;
      _loading = false;
      _done = done;
    });
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> src) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return src;
    return src.where((m) {
      final name = (m['customer_name'] ?? '').toString().toLowerCase();
      final tableGroup = (m['table_group'] ?? '').toString().toLowerCase();
      final id = (m['id'] ?? '').toString().toLowerCase();
      final reason = (m['cancel_reason'] ?? '').toString().toLowerCase();
      return name.contains(q) || tableGroup.contains(q) || id.contains(q) || reason.contains(q);
    }).toList();
  }

  // ===== business actions
  Future<void> _restore(Map<String, dynamic> draft) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString('pos.active.draft.id', '${draft['id']}');
  await sp.setString('pos.active.draft.payload', jsonEncode(draft));
  await sp.setString('pos.active.draft.base_items', jsonEncode(draft['items'] ?? const []));
  await sp.setString('pos.active.draft.mode', 'continue');

  final cart = ref.read(cartProvider.notifier);
  await cart.clear();

  // Ambil list mentah
  final itemsRaw = (draft['items'] as List?) ?? const [];
  final editsRaw = (draft['edits'] as List?) ?? const [];

  // Konversi aman ke List<Map<String, dynamic>>
  List<Map<String, dynamic>> _toMapList(List? src) => (src ?? const [])
      .whereType<Map>() // filter yang benar-benar Map
      .map((m) => Map<String, dynamic>.from(m)) // cast key/value
      .toList();

  final allItems = <Map<String, dynamic>>[];
  allItems.addAll(_toMapList(itemsRaw));

  for (final e in editsRaw.whereType<Map>()) {
    allItems.addAll(_toMapList(e['items'] as List?));
  }

  for (final it0 in allItems) {
    final it = Map<String, dynamic>.from(it0);
    final sku = it['sku'] ?? (it['menu_code'] != null ? 'menu:${it['menu_code']}' : 'unknown');
    final name = (it['name'] ?? '').toString();
    final price = (it['price_cents'] as num?)?.toInt()
        ?? (it['unit_price_cents'] as num?)?.toInt()
        ?? 0;
    final qty = (it['qty'] as num?)?.toInt() ?? 1;
    for (var i = 0; i < qty; i++) {
      await cart.add(Product(sku, name.isEmpty ? sku.toString() : name, price, 0));
    }
  }

  if (mounted) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Continue bill: ${draft['customer_name'] ?? '-'}')),
    );
  }
}

  Future<String?> _askCancelReason(BuildContext context) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Reason'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'e.g. Customer left'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _cancelBill(Map<String, dynamic> draft) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel this bill?'),
        content: const Text('The draft will be moved to Cancelled Bills.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(_, true), child: const Text('Yes, cancel')),
        ],
      ),
    );
    if (ok != true) return;

    final reason = await _askCancelReason(context) ?? '';
    // move to cancelled
    await repo.addCancelled({
      ...draft,
      'cancelled_at': DateTime.now().toIso8601String(),
      'cancel_reason': reason,
    });
    // remove from open
    await repo.removeDraft(draft['id']);
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bill moved to Cancelled')),
      );
    }
  }

  // ======== UI ========
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Billing Management'),
        centerTitle: true,
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context), // optional: new bill
              child: const Text('New Bill'),
            ),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'Open Bills'),
            Tab(text: 'Cancelled Bills'),
            Tab(text: 'Done Bills'),
            Tab(text: 'Item Void'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tab,
              children: [
                _buildOpenBills(cs),
                _buildCancelled(cs),
                _buildDone(cs),
                _buildPlaceholder('No item voids'),
              ],
            ),
    );
  }

  Widget _buildPlaceholder(String text) => Center(child: Text(text));

  Widget _buildDone(ColorScheme cs) {
    final data = _filtered(_done);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search Done Bill',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                _ColHeader('BILLING NAME', flex: 3),
                _ColHeader('ORDER ID', flex: 2),
                _ColHeader('METHOD', flex: 2),
                _ColHeader('PAID AT', flex: 3),
              ],
            ),
          ),
          const SizedBox(height: 6),
          if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('No done bills', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            ...data.map((m) => InkWell(
                  onTap: () => _showDoneDetail(context, m),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 3, child: Text('${m['customer_name'] ?? '-'}')),
                        Expanded(flex: 2, child: Text('${m['order_id'] ?? '-'}')),
                        Expanded(flex: 2, child: Text('${m['payment_method'] ?? '-'}')),
                        Expanded(flex: 3, child: Text('${m['paid_at'] ?? '-'}')),
                      ],
                    ),
                  ),
                )),
        ],
      ),
    );
  }

  Future<void> _showDoneDetail(BuildContext context, Map<String, dynamic> d) async {
    final itemsRaw = (d['items'] as List?) ?? const [];
    final items = itemsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    int lineTotal(Map<String, dynamic> it) {
      final price = (it['price_cents'] as num?)?.toInt()
          ?? (it['unit_price_cents'] as num?)?.toInt()
          ?? 0;
      final qty = (it['qty'] as num?)?.toInt() ?? 1;
      return price * qty;
    }
    final subtotal = items.fold<int>(0, (s, it) => s + lineTotal(it));

    await showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.of(ctx).size.height * 0.8,
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  (d['customer_name'] ?? 'Done Bill').toString(),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
              ]),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Order ID: ${d['order_id'] ?? '-'}\nMethod: ${d['payment_method'] ?? '-'}\nPaid at: ${d['paid_at'] ?? '-'}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(child: SingleChildScrollView(child: _itemsBox(items, subtotal))),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  // ------- Open Bills tab -------
  Widget _buildOpenBills(ColorScheme cs) {
    final data = _filtered(_openDrafts);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search bar + hint
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search Open Bill',
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text('Pull down to complete sync process',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),

          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                _ColHeader('BILLING NAME', flex: 3),
                _ColHeader('TABLE GROUP', flex: 2),
                _ColHeader('SERVER', flex: 2),
                _ColHeader('TIME', flex: 2),
                _ColHeader('SYNC', width: 48),
                SizedBox(width: 8),
              ],
            ),
          ),
          const SizedBox(height: 6),

          if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child:
                    Text('No open bills', style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            ...data.map((m) => _BillRowOpen(
                  data: m,
                  onPreview: () => _showDraftPreview(context, m),
                  onDelete: () async {
                    await repo.removeDraft(m['id']); // delete tanpa pindah
                    await _load();
                  },
                )),
        ],
      ),
    );
  }

  // ------- Cancelled tab -------
  Widget _buildCancelled(ColorScheme cs) {
    final data = _filtered(_cancelled);
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Search
          TextField
          (
            controller: _searchCtrl,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search Cancelled Bill',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
          const SizedBox(height: 12),

          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: cs.surfaceVariant.withValues(alpha: .6),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: const [
                _ColHeader('BILLING NAME', flex: 3),
                _ColHeader('REASON', flex: 4),
                _ColHeader('CANCELLED AT', flex: 3),
              ],
            ),
          ),
          const SizedBox(height: 6),

          if (data.isEmpty)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: Text('No cancelled bills',
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
            )
          else
            ...data.map((m) => _BillRowCancelled(
                  data: m,
                  onTap: () => _showCancelledDetail(context, m),
                )),
        ],
      ),
    );
  }

  Future<void> _showDraftPreview(BuildContext context, Map<String, dynamic> d) async {
    final itemsRaw = (d['items'] as List?) ?? const [];
    final items = itemsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    int lineTotal(Map<String, dynamic> it) {
      final price = (it['price_cents'] as num?)?.toInt()
          ?? (it['unit_price_cents'] as num?)?.toInt()
          ?? 0;
      final qty = (it['qty'] as num?)?.toInt() ?? 1;
      return price * qty;
    }

    final subtotal = items.fold<int>(0, (s, it) => s + lineTotal(it));
    final created = DateTime.tryParse('${d['created_at'] ?? ''}');
    final timeStr = created == null ? '-' : timeAgoShort(created);

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              // ⬇️ batasi tinggi dialog biar bagian bawah tidak ketutupan
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LayoutBuilder(
                builder: (ctx, cons) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Header
                      Row(
                        children: [
                          const Icon(Icons.receipt_long_rounded),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (d['customer_name'] ?? 'Open Bill').toString(),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          Text(timeStr, style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // ⬇️ area scroll untuk item
                      Flexible(
                        child: SingleChildScrollView(
                          child: _itemsBox(items, subtotal),
                        ),
                      ),

                      const SizedBox(height: 14),

                      // Tombol action
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(ctx),
                              child: const Text('Close'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.cancel_outlined),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                              onPressed: () async {
                                Navigator.pop(ctx); // tutup preview
                                await _cancelBill(d);
                              },
                              label: const Text('Cancel Bill'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                Navigator.pop(ctx); // close preview first
                                _restore(d);        // then continue
                              },
                              child: const Text('Continue'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showCancelledDetail(BuildContext context, Map<String, dynamic> d) async {
    final itemsRaw = (d['items'] as List?) ?? const [];
    final items = itemsRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    int lineTotal(Map<String, dynamic> it) {
      final price = (it['price_cents'] as num?)?.toInt()
          ?? (it['unit_price_cents'] as num?)?.toInt()
          ?? 0;
      final qty = (it['qty'] as num?)?.toInt() ?? 1;
      return price * qty;
    }
    final subtotal = items.fold<int>(0, (s, it) => s + lineTotal(it));

    final created = DateTime.tryParse('${d['created_at'] ?? ''}');
    final cancelledAt = DateTime.tryParse('${d['cancelled_at'] ?? ''}');
    final reason = (d['cancel_reason'] ?? '').toString();

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(ctx).size.height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.cancel, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          (d['customer_name'] ?? 'Cancelled Bill').toString(),
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Reason: ${reason.isEmpty ? '-' : reason}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Created: ${created?.toLocal() ?? '-'}\nCancelled: ${cancelledAt?.toLocal() ?? '-'}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Flexible(child: SingleChildScrollView(child: _itemsBox(items, subtotal))),

                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _itemsBox(List<Map<String, dynamic>> items, int subtotal) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black12.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(
            children: const [
              Expanded(child: Text('Item', style: TextStyle(fontWeight: FontWeight.w600))),
              SizedBox(width: 8),
              SizedBox(width: 56, child: Text('Qty', textAlign: TextAlign.right)),
              SizedBox(width: 12),
              SizedBox(width: 120, child: Text('Total', textAlign: TextAlign.right)),
            ],
          ),
          const Divider(),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text('No items'),
            )
          else
            ...items.map((it) {
              final name = (it['name'] ?? it['menu_code'] ?? it['sku'] ?? '-').toString();
              final qty = (it['qty'] as num?)?.toInt() ?? 1;
              final price = (it['price_cents'] as num?)?.toInt()
                  ?? (it['unit_price_cents'] as num?)?.toInt()
                  ?? 0;
              final total = price * qty;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(name)),
                    const SizedBox(width: 8),
                    SizedBox(width: 56, child: Text('$qty', textAlign: TextAlign.right)),
                    const SizedBox(width: 12),
                    SizedBox(width: 120, child: Text(rp(total), textAlign: TextAlign.right)),
                  ],
                ),
              );
            }),
          const Divider(),
          Row(
            children: [
              const Expanded(child: Text('Subtotal', style: TextStyle(fontWeight: FontWeight.w700))),
              SizedBox(width: 120, child: Text(rp(subtotal), textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700))),
            ],
          ),
        ],
      ),
    );
  }
}

// ====== row widgets ======
class _ColHeader extends StatelessWidget {
  final String text;
  final int? flex;
  final double? width;
  const _ColHeader(this.text, {this.flex, this.width});
  @override
  Widget build(BuildContext context) {
    final label = Text(
      text,
      style: const TextStyle(
        fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: .4),
    );
    if (width != null) return SizedBox(width: width, child: label);
    return Expanded(flex: flex ?? 1, child: label);
  }
}

class _BillRowOpen extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onPreview;
  final VoidCallback onDelete;
  const _BillRowOpen({
    required this.data,
    required this.onPreview,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (data['customer_name'] ?? '').toString();
    final tableGroup = (data['table_group'] ?? '').toString();
    final server = (data['server_name'] ?? '').toString();
    final created =
        DateTime.tryParse('${data['created_at'] ?? ''}') ?? DateTime.now();
    final timeStr = timeAgoShort(created);
    final synced = data['synced'] == true;

    return InkWell(
      onTap: onPreview,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(name.isEmpty ? '-' : name)),
            Expanded(flex: 2, child: Text(tableGroup.isEmpty ? '-' : tableGroup)),
            Expanded(flex: 2, child: Text(server.isEmpty ? '-' : server)),
            Expanded(flex: 2, child: Text(timeStr)),
            SizedBox(
              width: 48,
              child: Icon(
                synced ? Icons.check_circle : Icons.radio_button_unchecked,
                size: 18,
                color: synced ? Colors.green : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline, size: 20),
              color: Colors.red,
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _BillRowCancelled extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onTap;
  const _BillRowCancelled({required this.data, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final name = (data['customer_name'] ?? '').toString();
    final reason = (data['cancel_reason'] ?? '').toString();
    final cancelledAt =
        DateTime.tryParse('${data['cancelled_at'] ?? ''}') ?? DateTime.now();

    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: .5)),
          ),
        ),
        child: Row(
          children: [
            Expanded(flex: 3, child: Text(name.isEmpty ? '-' : name)),
            Expanded(flex: 4, child: Text(reason.isEmpty ? '(no reason)' : reason)),
            Expanded(flex: 3, child: Text(cancelledAt.toLocal().toString())),
          ],
        ),
      ),
    );
  }
}
