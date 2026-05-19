// lib/pages/menus_page.dart

import 'package:dio/dio.dart';
import 'package:ee_pos/models/menu.dart'; // MenuItemModel & MenuComponent
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';
import '../ui/pos_theme.dart';
import '../utils/formatting.dart';

// Use the global provider also used by POSHome/MenuGrid
import '../providers/menus_provider.dart';

// ⬇️ Tambahkan ini (fallback audit: info user yang login)
import '../repositories/auth_repo.dart';

/// ====== Lightweight UI models (self-contained in this page) ======
class _MenuComponent {
  String productSku;
  int qty;
  _MenuComponent({required this.productSku, required this.qty});

  factory _MenuComponent.fromJson(Map<String, dynamic> j) =>
      _MenuComponent(productSku: '${j['product_sku']}', qty: (j['qty'] as num).toInt());

  Map<String, dynamic> toJson() => {'product_sku': productSku, 'qty': qty};
}

class _MenuItem {
  String code;
  String name;
  int priceCents;
  bool enabled;
  int sort;
  List<_MenuComponent> components;
  // optional local type (untuk edit dialog)
  String? type;

  _MenuItem({
    required this.code,
    required this.name,
    required this.priceCents,
    required this.enabled,
    required this.sort,
    required this.components,
    this.type,
  });

  factory _MenuItem.fromJson(Map<String, dynamic> j) => _MenuItem(
        code: '${j['code']}',
        name: '${j['name']}',
        priceCents: (j['price_cents'] as num).toInt(),
        enabled: j['enabled'] == true || j['enabled'] == 1,
        sort: (j['sort'] is int) ? j['sort'] as int : int.tryParse('${j['sort'] ?? 999}') ?? 999,
        components: (j['components'] as List? ?? const [])
            .map((e) => _MenuComponent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        type: j['type']?.toString(),
      );
}

// Local products provider (for the picker)
final _productsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ApiService.shared();
  final list = await api.products();
  return list
      .map<Map<String, dynamic>>((e) {
        final m = Map<String, dynamic>.from(e as Map);
        m['sku'] = '${m['sku']}';
        m['name'] = '${m['name']}';
        return m;
      })
      .toList()
    ..sort((a, b) => '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()));
});

/// ====== PAGE ======
class MenusPage extends ConsumerStatefulWidget {
  const MenusPage({super.key});
  @override
  ConsumerState<MenusPage> createState() => _MenusPageState();
}

class _MenusPageState extends ConsumerState<MenusPage> {
  final _api = ApiService.shared();

  // 🔎 NEW: Search + Sort state
  final TextEditingController _search = TextEditingController();
  String _query = '';
  String _sortBy = 'display'; // display | name | price | items | enabled
  bool _ascending = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    ref.invalidate(menusProvider);
    try {
      await ref.read(menusProvider.future);
    } catch (_) {
      // Keep refresh flow resilient; UI already handles provider error state.
    }
  }

  Future<void> _createOrEdit({_MenuItem? edit}) async {
    final products =
        await ref.read(_productsProvider.future).catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;

    // Prepare initial (MenuItemModel) tanpa variants (sudah dihapus)
    MenuItemModel? initial;
    if (edit != null) {
      // fallback minimal
      initial = MenuItemModel(
        code: edit.code,
        name: edit.name,
        priceCents: edit.priceCents,
        enabled: edit.enabled,
        sort: edit.sort,
        components: edit.components
            .map((e) => MenuComponent(productSku: e.productSku, qty: e.qty))
            .toList(),
        type: edit.type,
        variants: const [],
      );
      // coba ambil dari API (untuk sync kolom type terbaru)
      try {
        final all = await _api.menus();
        final raw = all.cast<Map>().firstWhere(
              (e) => (e['code'] ?? '') == edit.code,
              orElse: () => const <String, dynamic>{},
            ) as Map<String, dynamic>;
        if (raw.isNotEmpty) {
          initial = MenuItemModel(
            code: '${raw['code']}',
            name: '${raw['name']}',
            priceCents: (raw['price_cents'] as num).toInt(),
            enabled: raw['enabled'] == true || raw['enabled'] == 1,
            sort: (raw['sort'] is int)
                ? raw['sort'] as int
                : int.tryParse('${raw['sort'] ?? 999}') ?? 999,
            components: (raw['components'] as List? ?? const [])
                .map<MenuComponent>((c) {
                  final m = Map<String, dynamic>.from(c as Map);
                  return MenuComponent(productSku: '${m['product_sku']}', qty: (m['qty'] as num).toInt());
                })
                .toList(),
            type: raw['type']?.toString(),
            variants: const [],
          );
        }
      } catch (_) {}
    }

    // Dialog returns Map<String, dynamic> body for the API
    if (!mounted) return;
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditMenuDialog(
        products: products,
        initial: initial,
      ),
    );
    if (body == null) return;

    // ⬇️ Fallback audit: sisipkan user yang login (cache)
    try {
      final u = await AuthRepo().me(refreshFromServer: false);
      if (u != null) {
        body['created_by'] = u.username;  // backend boleh abaikan jika tak dipakai
        body['created_by_id'] = u.id;     // idem
      }
    } catch (_) {}

    try {
      if (edit == null) {
        await _api.createMenu(body);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Menu created')));
        }
      } else {
        await _api.updateMenu(edit.code, body);
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Menu updated')));
        }
      }

      await _reload();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    }
  }

  Future<void> _delete(String code) async {
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete menu?'),
        content: Text('Code: $code'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(dialogCtx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _api.deleteMenu(code);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Menu deleted')));
      }
      await _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final menusAsync = ref.watch(menusProvider);

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header (with Search & Sort)
          Row(
            children: [
              const Text('Menus', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(width: 12),

              // 🔎 Search
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  decoration: const InputDecoration(
                    hintText: 'Search by name / code / SKU…',
                    prefixIcon: Icon(Icons.search),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // ⬇️ Sort dropdown
              DropdownButton<String>(
                value: _sortBy,
                onChanged: (v) => setState(() => _sortBy = v ?? 'display'),
                items: const [
                  DropdownMenuItem(value: 'display', child: Text('Sort: Display Order')),
                  DropdownMenuItem(value: 'name',    child: Text('Sort: Name')),
                  DropdownMenuItem(value: 'price',   child: Text('Sort: Price')),
                  DropdownMenuItem(value: 'items',   child: Text('Sort: #Items')),
                  DropdownMenuItem(value: 'enabled', child: Text('Sort: Active')),
                ],
              ),

              // ASC/DESC toggle
              IconButton(
                tooltip: _ascending ? 'Ascending' : 'Descending',
                onPressed: () => setState(() => _ascending = !_ascending),
                icon: Icon(_ascending ? Icons.arrow_upward : Icons.arrow_downward),
              ),

              const Spacer(),
              FilledButton.icon(
                onPressed: () => _createOrEdit(),
                icon: const Icon(Icons.add),
                label: const Text('New Menu'),
              ),
            ],
          ),

          const SizedBox(height: 12),
          Expanded(
            child: menusAsync.when(
              data: (menus) {
                // ✅ Build local list
                final items = menus
                    .map((m) => _MenuItem.fromJson({
                          'code': m.code,
                          'name': m.name,
                          'price_cents': m.priceCents,
                          'enabled': m.enabled,
                          'sort': m.sort,
                          'type': m.type,
                          'components': m.components
                              .map((c) => {
                                    'product_sku': c.productSku,
                                    'qty': c.qty,
                                  })
                              .toList(),
                        }))
                    .toList();

                // 🔎 SEARCH
                final q = _query;
                var filtered = (q.isEmpty)
                    ? items
                    : items.where((e) {
                        final name = e.name.toLowerCase();
                        final code = e.code.toLowerCase();
                        final inSku = e.components.any(
                          (c) => c.productSku.toLowerCase().contains(q),
                        );
                        return name.contains(q) || code.contains(q) || inSku;
                      }).toList();

                // ↕️ SORT
                int cmp<T extends Comparable>(T a, T b) => a.compareTo(b);
                filtered.sort((a, b) {
                  int r;
                  switch (_sortBy) {
                    case 'name':
                      r = cmp(a.name.toLowerCase(), b.name.toLowerCase());
                      break;
                    case 'price':
                      r = cmp(a.priceCents, b.priceCents);
                      break;
                    case 'items':
                      r = cmp(a.components.length, b.components.length);
                      break;
                    case 'enabled':
                      r = cmp(a.enabled ? 1 : 0, b.enabled ? 1 : 0);
                      break;
                    case 'display':
                    default:
                      r = cmp(a.sort, b.sort);
                      if (r == 0) {
                        r = cmp(a.name.toLowerCase(), b.name.toLowerCase());
                      }
                  }
                  return _ascending ? r : -r;
                });

                // UI kosong
                if (filtered.isEmpty) {
                  return RefreshIndicator.adaptive(
                    onRefresh: _reload,
                    child: ListView(
                      children: const [
                        SizedBox(height: 240),
                        Center(child: Text('No menus match your search')),
                      ],
                    ),
                  );
                }

                // GRID
                return RefreshIndicator.adaptive(
                  onRefresh: _reload,
                  child: GridView.builder(
                    padding: const EdgeInsets.only(bottom: 10),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 280,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 3 / 4,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final it = filtered[i];
                      return _MenuCard(
                        m: it,
                        onEdit: () => _createOrEdit(edit: it),
                        onDelete: () => _delete(it.code),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator.adaptive()),
              error: (e, _) => Center(
                child: Text('Failed to load: $e', style: const TextStyle(color: PosTheme.muted)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ====== CARD ======
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.m, required this.onEdit, required this.onDelete});
  final _MenuItem m;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: PosTheme.border),
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        boxShadow: const [BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onEdit,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: PosTheme.panel,
                        border: Border.all(color: PosTheme.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Icon(Icons.fastfood_rounded, size: 36, color: Colors.black54),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.2,
                      color: PosTheme.black,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Items: ${m.components.length}',
                    style: const TextStyle(fontSize: 12, color: PosTheme.muted),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: const ShapeDecoration(
                            color: Colors.white,
                            shape: StadiumBorder(side: BorderSide(color: PosTheme.border)),
                          ),
                          child: Text(rp(m.priceCents)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(onPressed: onEdit, icon: const Icon(Icons.edit)),
                      IconButton(onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ====== EDIT/CREATE DIALOG (tanpa variants, pakai Type/Category) ======
class _EditMenuDialog extends StatefulWidget {
  const _EditMenuDialog({required this.products, this.initial});
  final List<Map<String, dynamic>> products;
  final MenuItemModel? initial;

  @override
  State<_EditMenuDialog> createState() => _EditMenuDialogState();
}

class _EditMenuDialogState extends State<_EditMenuDialog> {
  final _form = GlobalKey<FormState>();
  late TextEditingController _code, _name, _sort;
  late TextEditingController _basePrice; // shown in Rp
  late TextEditingController _customCategory;
  bool _enabled = true;

  // components
  late List<MenuComponent> _components;

  // Type / Category
  final List<String> _preset = const ['drink', 'food', 'desert', 'cake', 'bread'];
  String _selectedType = 'drink';
  bool _useCustom = false;

  @override
  void initState() {
    super.initState();
    final it = widget.initial;
    _code = TextEditingController(text: it?.code ?? '');
    _name = TextEditingController(text: it?.name ?? '');
    _sort = TextEditingController(text: (it?.sort ?? 999).toString());
    _basePrice = TextEditingController(text: (it?.priceCents ?? 0).toString());
    _enabled = it?.enabled ?? true;
    _customCategory = TextEditingController();

    _components = (it?.components ?? const [])
        .map((e) => MenuComponent(productSku: e.productSku, qty: e.qty))
        .toList();

    final initialType = (it?.type ?? '').toLowerCase();
    if (initialType.isNotEmpty) {
      if (_preset.contains(initialType)) {
        _selectedType = initialType;
        _useCustom = false;
      } else {
        _selectedType = initialType;
        _useCustom = true;
        _customCategory.text = initialType;
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _sort.dispose();
    _basePrice.dispose();
    _customCategory.dispose();
    super.dispose();
  }

  String _effectiveType() {
    if (_useCustom) {
      final s = _customCategory.text.trim().toLowerCase();
      return s.isEmpty ? _selectedType : s;
    }
    return _selectedType;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initial != null;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Form(
            key: _form,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(isEdit ? Icons.edit : Icons.add),
                      const SizedBox(width: 8),
                      Text(isEdit ? 'Edit Menu' : 'New Menu',
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      const Spacer(),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Name + Base Price + Display Order + Active
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _name,
                          decoration: const InputDecoration(labelText: 'Name'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 180,
                        child: TextFormField(
                          controller: _basePrice,
                          decoration: const InputDecoration(labelText: 'Base Price (Rp, optional)'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 140,
                        child: TextFormField(
                          controller: _sort,
                          decoration: const InputDecoration(labelText: 'Display Order'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Checkbox(value: _enabled, onChanged: (v) => setState(() => _enabled = v ?? true)),
                      const Text('Active'),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Code (no upload)
                  Row(
                    children: [
                      if (!isEdit)
                        SizedBox(
                          width: 240,
                          child: TextFormField(
                            controller: _code,
                            decoration: const InputDecoration(labelText: 'Code (lowercase, unique)'),
                            validator: (v) {
                              if (isEdit) return null;
                              final s = (v ?? '').trim();
                              if (s.isEmpty) return 'Required';
                              final ok = RegExp(r'^[a-z0-9_-]+$').hasMatch(s);
                              return ok ? null : 'Use a-z, 0-9, _ or -';
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // ===== Type / Category (chips + custom) =====
                  Row(children: const [
                    Text('Type / Category:', style: TextStyle(fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final opt in _preset)
                        ChoiceChip(
                          label: Text(opt[0].toUpperCase() + opt.substring(1)),
                          selected: !_useCustom && _selectedType == opt,
                          onSelected: (_) => setState(() {
                            _useCustom = false;
                            _selectedType = opt;
                          }),
                        ),
                      ChoiceChip(
                        label: const Text('Custom'),
                        selected: _useCustom,
                        onSelected: (_) => setState(() => _useCustom = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_useCustom)
                    TextFormField(
                      controller: _customCategory,
                      decoration: const InputDecoration(
                        labelText: 'Custom category (e.g. “tea”, “sandwich”, …)',
                      ),
                      textInputAction: TextInputAction.done,
                    ),

                  const SizedBox(height: 14),

                  // Components editor
                  _ComponentsEditor(
                    products: widget.products,
                    components: _components
                        .map((e) => _MenuComponent(productSku: e.productSku, qty: e.qty))
                        .toList(),
                    onAddRow: () {
                      setState(() {
                        final sku = widget.products.isNotEmpty ? '${widget.products.first['sku']}' : '';
                        _components.add(MenuComponent(productSku: sku, qty: 1));
                      });
                    },
                    onRemoveRow: (i){
                      setState((){
                        _components.removeAt(i);
                      });
                    },
                    onChanged: () => setState(() {}),
                  ),

                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton(
                          onPressed: () {
                            if (!_form.currentState!.validate()) return;

                            final type = _effectiveType(); // <== final type/category yang disimpan
                            if (type.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Category is required')),
                              );
                              return;
                            }

                            final body = {
                              'code': _code.text.trim(),
                              'name': _name.text.trim(),
                              'price_cents': int.tryParse(_basePrice.text.trim()) ?? 0,
                              'enabled': _enabled,
                              'sort': int.tryParse(_sort.text.trim()) ?? 999,
                              'type': type, // <== simpan ke kolom type
                              'components': _components.map((c) => {
                                    'product_sku': c.productSku,
                                    'qty': c.qty,
                                  }).toList(),
                              // tidak kirim 'variants' lagi
                            };

                            Navigator.pop(context, body); // return Map<String,dynamic>
                          },
                          child: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ====== COMPONENTS EDITOR (tetap sama) ======
class _ComponentsEditor extends StatelessWidget {
  const _ComponentsEditor({
    required this.products,
    required this.components,
    required this.onAddRow,
    required this.onRemoveRow,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> products;
  final List<_MenuComponent> components;
  final VoidCallback onAddRow;
  final void Function(int index) onRemoveRow;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: PosTheme.border),
            borderRadius: BorderRadius.circular(10),
            color: Colors.white,
          ),
          child: Column(
            children: [
              for (var i = 0; i < components.length; i++) ...[
                if (i > 0) const Divider(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: components[i].productSku.isNotEmpty
                            ? components[i].productSku
                            : (products.isNotEmpty ? products.first['sku'] as String : null),
                        isExpanded: true,
                        items: [
                          for (final p in products)
                            DropdownMenuItem(
                              value: p['sku'] as String,
                              child: Text('${p['name']} (${p['sku']})', overflow: TextOverflow.ellipsis),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) return;
                          components[i].productSku = v;
                          onChanged();
                        },
                        decoration: const InputDecoration(
                          labelText: 'Product',
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 120,
                      child: TextFormField(
                        initialValue: components[i].qty.toString(),
                        onChanged: (v) {
                          final n = int.tryParse(v) ?? 1;
                          components[i].qty = n < 1 ? 1 : n;
                        },
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(onPressed: () => onRemoveRow(i), icon: const Icon(Icons.delete_outline)),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: onAddRow,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Component'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
