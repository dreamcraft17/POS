import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/product.dart';
import '../providers/products_provider.dart';
import '../services/api_service.dart';

class ProductsPage extends ConsumerStatefulWidget {
  const ProductsPage({super.key});
  @override
  ConsumerState<ProductsPage> createState() => _ProductsPageState();
}

class _ProductsPageState extends ConsumerState<ProductsPage> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) enableProductsNetworkLoad(ref);
    });
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return Container(
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // Search
            Material(
              elevation: 2,
              shadowColor: Colors.black12,
              borderRadius: BorderRadius.circular(28),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search Item',
                  prefixIcon: const Icon(Icons.search, color: Colors.black87),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(28),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                ),
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
            const SizedBox(height: 12),

            // List
            Expanded(
              child: productsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (list) {
                  final filtered = list
                      .where((p) =>
                          p.name.toLowerCase().contains(_query) ||
                          p.sku.toLowerCase().contains(_query))
                      .toList();

                  Future<void> refreshProducts() async {
                    await ref.read(productsProvider.notifier).reloadFromNetwork();
                  }

                  if (filtered.isEmpty) {
                    return RefreshIndicator(
                      onRefresh: refreshProducts,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 120),
                          Icon(Icons.inventory_2_outlined,
                              size: 64, color: Colors.black38),
                          SizedBox(height: 12),
                          Text('no product',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black54)),
                          SizedBox(height: 6),
                          Text('Try add new product or new search filter.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.black45)),
                          SizedBox(height: 400),
                        ],
                      ),
                    );
                  }

                  return Card(
                    clipBehavior: Clip.antiAlias,
                    elevation: 1,
                    color: Colors.white,
                    child: RefreshIndicator(
                      onRefresh: refreshProducts,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Colors.black26),
                        itemBuilder: (_, i) {
                          final p = filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.black12,
                              child: Text(
                                p.name.isNotEmpty
                                    ? p.name.characters.first.toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.black87,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            title: Text(
                              p.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.black),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Wrap(
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 10,
                                runSpacing: 6,
                                children: [
                                  _Meta(
                                      icon: Icons.numbers,
                                      text: p.sku,
                                      color: Colors.black54),
                                  Chip(
                                    label: Text('Stock: ${p.stock}'),
                                    side: const BorderSide(
                                        color: Colors.black26),
                                    backgroundColor: Colors.white,
                                    labelStyle:
                                        const TextStyle(color: Colors.black87),
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ],
                              ),
                            ),
                            trailing: PopupMenuButton<_RowAction>(
                              tooltip: 'Aksi',
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.black87),
                              onSelected: (a) {
                                switch (a) {
                                  case _RowAction.edit:
                                    _showEditSheet(context, p);
                                    break;
                                  case _RowAction.delete:
                                    _confirmDelete(context, p.sku);
                                    break;
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: _RowAction.edit,
                                  child: ListTile(
                                    leading: Icon(Icons.edit,
                                        color: Colors.black87),
                                    title: Text('Edit / adjust stock'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: _RowAction.delete,
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline,
                                        color: Colors.black54),
                                    title: Text('Delete (soft delete)',
                                        style:
                                            TextStyle(color: Colors.black54)),
                                  ),
                                ),
                              ],
                            ),
                            onLongPress: () => _showEditSheet(context, p),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white),
                icon: const Icon(Icons.add),
                label: const Text('Add Product'),
                onPressed: () => _showCreateSheet(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ======= SHEETS =======

  Future<void> _showCreateSheet(BuildContext context) async {
    final skuCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final stockCtrl = TextEditingController(text: '0');
    final api = ApiService.shared();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: media.viewInsets.bottom + 16,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetHandle(),
                const Text('Add Product',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: Colors.black)),
                const SizedBox(height: 12),
                _LabeledField(
                  label: 'SKU',
                  child: TextFormField(
                    controller: skuCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: _input('SKU', icon: Icons.numbers),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'SKU mandatory' : null,
                  ),
                ),
                _LabeledField(
                  label: 'Prod Name',
                  child: TextFormField(
                    controller: nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration:
                        _input('Product Name', icon: Icons.badge_outlined),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Nama wajib diisi' : null,
                  ),
                ),
                _LabeledField(
                  label: 'Initial Stock',
                  child: TextFormField(
                    controller: stockCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _input('0', icon: Icons.inventory_2_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final stock = int.tryParse(stockCtrl.text.trim()) ?? 0;

                      await api.upsertProduct({
                        'sku': skuCtrl.text.trim(),
                        'name': nameCtrl.text.trim(),
                        'price_cents': 0,
                        'stock': stock,
                      });

                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      ref.invalidate(productsProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Produk ditambahkan.')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Must Unique SKU.',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showEditSheet(BuildContext context, Product p) async {
    final nameCtrl = TextEditingController(text: p.name);
    final deltaCtrl = TextEditingController(text: '0');
    final api = ApiService.shared();
    final formKey = GlobalKey<FormState>();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        final media = MediaQuery.of(ctx);
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 12,
            bottom: media.viewInsets.bottom + 16,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetHandle(),
                Text('Edit ${p.sku}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                        color: Colors.black)),
                const SizedBox(height: 12),
                _LabeledField(
                  label: 'Name',
                  child: TextFormField(
                    controller: nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration:
                        _input('Product Name', icon: Icons.badge_outlined),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Prod Name must filled' : null,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: _LabeledField(
                        label: 'Stock Adjustment (Δ)',
                        child: TextFormField(
                          controller: deltaCtrl,
                          keyboardType: TextInputType.number,
                          decoration: _input('±0', icon: Icons.trending_up),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final v in const [-10, -5, -1, 1, 5, 10])
                        ActionChip(
                          label: Text(v > 0 ? '+$v' : '$v'),
                          onPressed: () {
                            final cur =
                                int.tryParse(deltaCtrl.text.trim()) ?? 0;
                            deltaCtrl.text = '${cur + v}';
                            setState(() {});
                          },
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Colors.black12,
                          labelStyle: const TextStyle(color: Colors.black87),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      final patch = <String, dynamic>{};

                      if (nameCtrl.text.trim() != p.name) {
                        patch['name'] = nameCtrl.text.trim();
                      }
                      if (patch.isNotEmpty) {
                        await api.updateProduct(p.sku, patch);
                      }
                      final delta = int.tryParse(deltaCtrl.text.trim()) ?? 0;
                      if (delta != 0) {
                        await api.adjustStock(p.sku, delta, reason: 'manual');
                      }
                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      ref.invalidate(productsProvider);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Change Save.')),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Use Δ Stock for quick Correction.',
                    style: TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, String sku) async {
    final api = ApiService.shared();

    bool acknowledged = false;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog.adaptive(
          backgroundColor: Colors.white,
          title: Row(
            children: const [
              Icon(Icons.warning_amber_rounded, color: Colors.black87),
              SizedBox(width: 8),
              Text(
                'Delete Product',
                style:
                    TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  const Text('Are you sure you want to delete this product?',
                      style: TextStyle(color: Colors.black87)),
                  Chip(
                    label: Text('SKU: $sku'),
                    visualDensity: VisualDensity.compact,
                    side: const BorderSide(color: Colors.black26),
                    backgroundColor: Colors.white,
                    labelStyle: const TextStyle(color: Colors.black87),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'This is a soft delete. The product will no longer be visible.\n'
                'To restore it later, please contact IT support.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 12),
              CheckboxListTile.adaptive(
                value: acknowledged,
                onChanged: (v) => setState(() => acknowledged = v ?? false),
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('I understand and want to proceed.',
                    style: TextStyle(color: Colors.black87)),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.black)),
            ),
            FilledButton.icon(
              onPressed: acknowledged ? () => Navigator.pop(ctx, true) : null,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Delete'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );

    if (ok == true) {
      try {
        await api.deleteProduct(sku);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Product $sku has been deleted.')),
        );
        ref.invalidate(productsProvider);
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  // ======= Helpers =======

  static InputDecoration _input(String label, {IconData? icon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: icon != null ? Icon(icon, color: Colors.black54) : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      filled: true,
      fillColor: Colors.white,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      labelStyle: const TextStyle(color: Colors.black54),
    );
  }
}

enum _RowAction { edit, delete }

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.black54;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: c),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(color: c, fontSize: 12)),
      ],
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, color: Colors.black)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}
