import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/api_service.dart';

/// Set ke true kalau nanti backend PATCH sudah siap.
const bool kShowEnableToggle = false;

final paymentMethodsProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final api = ApiService.shared();
  final list = await api.paymentMethods();
  return list.cast<Map<String, dynamic>>();
});

class PaymentsPanel extends ConsumerWidget {
  const PaymentsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final methods = ref.watch(paymentMethodsProvider);
    final api = ApiService.shared();

    Future<void> showAddSheet() async {
      final codeCtrl = TextEditingController();
      final nameCtrl = TextEditingController();
      final sortCtrl = TextEditingController(text: '99');
      bool enabled = true; // default aktif (tetap dikirim di payload)
      final formKey = GlobalKey<FormState>();

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final media = MediaQuery.of(ctx);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: media.viewInsets.bottom + 16,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DragHandle(),
                    Text('Add Payment Method',
                        style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Code (a-z0-9_-)',
                      ),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Code is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: sortCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Sort (number)'),
                    ),
                    const SizedBox(height: 12),
                    if (kShowEnableToggle)
                      StatefulBuilder(
                        builder: (ctx, setState) {
                          return SwitchListTile(
                            title: const Text('Enabled'),
                            value: enabled,
                            onChanged: (v) => setState(() => enabled = v),
                          );
                        },
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              final c = codeCtrl.text.trim().toLowerCase();
                              final n = nameCtrl.text.trim();
                              final s =
                                  int.tryParse(sortCtrl.text.trim()) ?? 99;
                              await api.createPaymentMethod({
                                'code': c,
                                'name': n,
                                'enabled': enabled,
                                'sort': s,
                              });
                              if (context.mounted) Navigator.pop(ctx);
                              ref.invalidate(paymentMethodsProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Payment method added successfully'),
                                ),
                              );
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
          );
        },
      );
    }

    Future<void> showEditSheet(Map<String, dynamic> m) async {
      final nameCtrl = TextEditingController(text: '${m['name']}');
      final sortCtrl = TextEditingController(text: '${m['sort']}');
      // Tetap baca enabled untuk tampilan, tapi tidak bisa diubah saat toggle disembunyikan
      bool enabled = asBool(m['enabled']);
      final formKey = GlobalKey<FormState>();

      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) {
          final media = MediaQuery.of(ctx);
          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: media.viewInsets.bottom + 16,
            ),
            child: Form(
              key: formKey,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _DragHandle(),
                    Text('Edit ${m['code']}',
                        style: Theme.of(ctx).textTheme.titleLarge),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name'),
                      validator: (v) =>
                          v == null || v.isEmpty ? 'Name is required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: sortCtrl,
                      keyboardType: TextInputType.number,
                      decoration:
                          const InputDecoration(labelText: 'Sort (number)'),
                    ),
                    const SizedBox(height: 12),
                    if (kShowEnableToggle)
                      StatefulBuilder(
                        builder: (ctx, setState) {
                          return SwitchListTile(
                            title: const Text('Enabled'),
                            value: enabled,
                            onChanged: (v) => setState(() => enabled = v),
                          );
                        },
                      ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              final patch = <String, dynamic>{};
                              if (nameCtrl.text.trim() != m['name']) {
                                patch['name'] = nameCtrl.text.trim();
                              }
                              final newSort =
                                  int.tryParse(sortCtrl.text.trim());
                              if (newSort != null && newSort != m['sort']) {
                                patch['sort'] = newSort;
                              }
                              // Jangan kirim enabled saat toggle disembunyikan
                              // if (kShowEnableToggle &&
                              //     enabled != asBool(m['enabled'])) {
                              //   patch['enabled'] = enabled;
                              // }

                              if (patch.isNotEmpty) {
                                await ApiService.shared().updatePaymentMethod(
                                  m['code'] as String,
                                  patch,
                                );
                              }
                              if (context.mounted) Navigator.pop(ctx);
                              ref.invalidate(paymentMethodsProvider);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Changes saved successfully'),
                                ),
                              );
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
          );
        },
      );
    }

    Future<void> deleteConfirm(String code) async {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Payment Method'),
          content: Text('Are you sure you want to delete "$code"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await ApiService.shared().deletePaymentMethod(code);
        ref.invalidate(paymentMethodsProvider);
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment method deleted')),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'Payment Methods',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: showAddSheet,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: methods.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) {
              if (list.isEmpty) {
                return const Center(child: Text('No payment methods yet'));
              }
              return ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final m = list[i];
                  final enabled = asBool(m['enabled']);
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      title: Text('${m['name']}'),
                      subtitle:
                          Text('Code: ${m['code']} • Sort: ${m['sort']}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (kShowEnableToggle)
                            Switch.adaptive(
                              value: enabled,
                              onChanged: (v) async {
                                try {
                                  await api.updatePaymentMethod(
                                      m['code'] as String, {'enabled': v});
                                  ref.invalidate(paymentMethodsProvider);
                                } catch (_) {
                                  // optional: toast error
                                }
                              },
                            ),
                          IconButton(
                            tooltip: 'Edit',
                            icon: const Icon(Icons.edit),
                            onPressed: () => showEditSheet(m),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () =>
                                deleteConfirm(m['code'] as String),
                          ),
                        ],
                      ),
                      onTap: () => showEditSheet(m),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 4,
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.grey.shade400,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

bool asBool(dynamic v) {
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) return v == '1' || v.toLowerCase() == 'true';
  return false;
}
