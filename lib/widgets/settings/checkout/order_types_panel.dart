import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

class OrderTypesPanel extends ConsumerStatefulWidget {
  const OrderTypesPanel({super.key});
  @override
  ConsumerState<OrderTypesPanel> createState() => _OrderTypesPanelState();
}

class _OrderTypesPanelState extends ConsumerState<OrderTypesPanel> {
  final _api = ApiService.shared();

  bool _loading = false;
  bool _saving = false; // global saving (add)
  String? _error; // last error message
  List<Map<String, dynamic>> _items = [];

  // form add
  final _codeCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _sortCtrl = TextEditingController(text: '999');
  bool _enabled = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.orderTypes();
      // sort aman ke int
      list.sort((a, b) {
        final ai = (a['sort'] is int)
            ? a['sort'] as int
            : int.tryParse('${a['sort'] ?? 999}') ?? 999;
        final bi = (b['sort'] is int)
            ? b['sort'] as int
            : int.tryParse('${b['sort'] ?? 999}') ?? 999;
        return ai.compareTo(bi);
      });
      setState(() => _items = list);
    } catch (e) {
      setState(() => _error = 'Gagal memuat order types: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final code = _codeCtrl.text.trim().toLowerCase();
    final name = _nameCtrl.text.trim();
    final sort = int.tryParse(_sortCtrl.text.trim()) ?? 999;
    if (code.isEmpty || name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Code & Name wajib diisi')),
      );
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.createOrderType({
        'code': code,
        'name': name,
        'enabled': _enabled,
        'sort': sort,
      });
      _codeCtrl.clear();
      _nameCtrl.clear();
      _enabled = true;
      _sortCtrl.text = '999';

      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Order type created')),
        );
      }
    } catch (e) {
      setState(() => _error = 'Gagal menambah: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_error!)),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _update(
    Map<String, dynamic> it, {
    String? name,
    bool? enabled,
    int? sort,
  }) async {
    final code = (it['code'] ?? '').toString();
    final patch = <String, dynamic>{};
    if (name != null) patch['name'] = name;
    if (enabled != null) patch['enabled'] = enabled;
    if (sort != null) patch['sort'] = sort;
    if (patch.isEmpty) return;

    try {
      await _api.updateOrderType(code, patch);
      await _load();
    } catch (e) {
      setState(() => _error = 'Gagal update "$code": $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_error!)),
      );
    }
  }

  Future<void> _delete(Map<String, dynamic> it) async {
    final code = (it['code'] ?? '').toString();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete order type?'),
        content: Text('Code: $code'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _api.deleteOrderType(code);
        await _load();
      } catch (e) {
        setState(() => _error = 'Gagal delete "$code": $e');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_error!)),
        );
      }
    }
  }

  // helper untuk +/- sort
  void _bumpSort(Map<String, dynamic> it, int delta) {
    final current = (it['sort'] is int)
        ? it['sort'] as int
        : int.tryParse('${it['sort'] ?? 999}') ?? 999;
    final next = current + delta;
    _update(it, sort: next < 0 ? 0 : next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + actions
        Row(
          children: [
            const Text('Order Types',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(
              tooltip: 'Reload',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Kelola “Dine In”, “Take Away”, dsb. Urutan berdasar kolom sort (kecil → besar).'),

        if (_error != null) ...[
          const SizedBox(height: 8),
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(onPressed: () => setState(() => _error = null), child: const Text('Dismiss')),
            ],
          ),
        ],

        const SizedBox(height: 14),

        // FORM TAMBAH
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add New', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _codeCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Code (lowercase, e.g. dinein)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _nameCtrl,
                        enabled: !_saving,
                        decoration: const InputDecoration(
                          labelText: 'Name (e.g. Dine In)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    SizedBox(
                      width: 160,
                      child: TextField(
                        controller: _sortCtrl,
                        enabled: !_saving,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Sort',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Checkbox(
                      value: _enabled,
                      onChanged: _saving ? null : (v) => setState(() => _enabled = v ?? true),
                    ),
                    const Text('Enabled'),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _saving ? null : _create,
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add),
                      label: const Text('Add'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // LIST
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? ListView(children: [SizedBox(height: 250), Center(child: Text('No order types yet'))])
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final it = _items[i];
                          final code = (it['code'] ?? '').toString();
                          final name = (it['name'] ?? '').toString();
                          final enabled = (it['enabled'] == 1 || it['enabled'] == true);
                          final sort = (it['sort'] is int)
                              ? it['sort'] as int
                              : int.tryParse('${it['sort'] ?? 0}') ?? 0;

                          final nameCtrl = TextEditingController(text: name);
                          final sortCtrl = TextEditingController(text: '$sort');

                          return ListTile(
                            title: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(code, style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Name edit
                                    Expanded(
                                      child: TextField(
                                        controller: nameCtrl,
                                        decoration: const InputDecoration(
                                          labelText: 'Name',
                                          border: OutlineInputBorder(),
                                        ),
                                        onSubmitted: (v) => _update(it, name: v.trim()),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Sort with - / +
                                    SizedBox(
                                      width: 210,
                                      child: Row(
                                        children: [
                                          IconButton(
                                            tooltip: 'Kurangi sort',
                                            onPressed: () => _bumpSort(it, -1),
                                            icon: const Icon(Icons.remove_circle_outline),
                                          ),
                                          Expanded(
                                            child: TextField(
                                              controller: sortCtrl,
                                              keyboardType: TextInputType.number,
                                              decoration: const InputDecoration(
                                                labelText: 'Sort',
                                                border: OutlineInputBorder(),
                                              ),
                                              onSubmitted: (v) => _update(
                                                it,
                                                sort: int.tryParse(v.trim()) ?? sort,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            tooltip: 'Tambah sort',
                                            onPressed: () => _bumpSort(it, 1),
                                            icon: const Icon(Icons.add_circle_outline),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // Enabled toggle
                                    Row(
                                      children: [
                                        const Text('Enabled'),
                                        Switch(
                                          value: enabled,
                                          onChanged: (v) => _update(it, enabled: v),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: 'Delete',
                              onPressed: () => _delete(it),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    _nameCtrl.dispose();
    _sortCtrl.dispose();
    super.dispose();
  }
}
