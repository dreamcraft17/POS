import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';
import '../../../providers/discount_providers.dart';
import '../../../models/discount.dart';

class DiscountsPanel extends ConsumerWidget {
  const DiscountsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listAsync = ref.watch(discountsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.local_offer_outlined),
            const SizedBox(width: 8),
            const Text('Discounts', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _showEditDialog(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: listAsync.when(
            data: (list) => Card(
              child: ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final d = list[i];
                  return ListTile(
                    leading: Icon(d.kind == DiscountKind.percent ? Icons.percent : Icons.attach_money_rounded),
                    title: Text(d.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(d.kind == DiscountKind.percent
                        ? 'Percent • ${d.value.toStringAsFixed(0)}%'
                        : 'Amount • ${d.value.round()}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => _showEditDialog(context, ref, existing: d),
                          icon: const Icon(Icons.edit),
                        ),
                        IconButton(
                          onPressed: () => _confirmDelete(context, ref, d),
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            loading: () => const Center(child: CircularProgressIndicator.adaptive()),
            error: (e, _) => Center(child: Text('Failed to load: $e')),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Discount d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Discount'),
        content: Text('Delete "${d.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ApiService.shared().deleteDiscount(d.code);
      ref.invalidate(discountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $e')));
      }
    }
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, {Discount? existing}) async {
    final isEdit = existing != null;
    final codeCtrl = TextEditingController(text: existing?.code ?? '');
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    DiscountKind kind = existing?.kind ?? DiscountKind.percent;
    final valCtrl = TextEditingController(text: existing?.value.toStringAsFixed(0) ?? '10');

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isEdit ? 'Edit Discount' : 'New Discount'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isEdit)
              TextField(
                controller: codeCtrl,
                decoration: const InputDecoration(labelText: 'Code (unique)', hintText: 'e.g. weekend10'),
              ),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Weekend 10%'),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<DiscountKind>(
                    initialValue: kind,
                    decoration: const InputDecoration(labelText: 'Kind'),
                    items: const [
                      DropdownMenuItem(value: DiscountKind.percent, child: Text('Percent')),
                      DropdownMenuItem(value: DiscountKind.amount, child: Text('Amount (cents)')),
                    ],
                    onChanged: (v) => kind = v ?? DiscountKind.percent,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: valCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: kind == DiscountKind.percent ? 'Value %' : 'Value (cents)',
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(isEdit ? 'Save' : 'Create')),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final body = {
        'name': nameCtrl.text.trim(),
        'kind': kind.name,
        'value': double.tryParse(valCtrl.text.trim()) ?? 0,
        'enabled': true,
        'sort': 0,
      };
      if (isEdit) {
        await ApiService.shared().updateDiscount(existing.code, body);
      } else {
        final code = codeCtrl.text.trim().toLowerCase();
        await ApiService.shared().createDiscount({'code': code, ...body});
      }
      ref.invalidate(discountsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'Saved' : 'Created')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
      }
    }
  }
}
