import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/discount_providers.dart';
import '../models/discount.dart';
import '../utils/formatting.dart';

Future<void> showDiscountDialog(BuildContext context) async {
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => const _DiscountDialog(),
  );
}

class _DiscountDialog extends ConsumerStatefulWidget {
  const _DiscountDialog();

  @override
  ConsumerState<_DiscountDialog> createState() => _DiscountDialogState();
}

enum _FilterKind { all, percent, fixed }
enum _Density { comfy, compact }

class _DiscountDialogState extends ConsumerState<_DiscountDialog> {
  final _searchCtrl = TextEditingController();
  _FilterKind _filter = _FilterKind.all;
  _Density _density = _Density.comfy;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final discounts = ref.watch(discountsProvider);
    final selected = ref.watch(selectedDiscountProvider);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== Header =====
              Row(
                children: [
                  Container(
                    height: 42,
                    width: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.local_offer_outlined,
                        color: theme.colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Choose Discount',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  // density toggle (no grid)
                  SegmentedButton<_Density>(
                    segments: const [
                      ButtonSegment(value: _Density.comfy, label: Text('Comfy')),
                      ButtonSegment(value: _Density.compact, label: Text('Compact')),
                    ],
                    selected: {_density},
                    style: ButtonStyle(
                      visualDensity:
                          const VisualDensity(horizontal: -2, vertical: -2),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    onSelectionChanged: (v) => setState(() => _density = v.first),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ===== Search + Filter =====
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: (_searchCtrl.text.isEmpty)
                            ? null
                            : IconButton(
                                tooltip: 'Clear',
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.clear),
                              ),
                        hintText: 'Search discount by name or code…',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<_FilterKind>(
                    segments: const [
                      ButtonSegment(value: _FilterKind.all, label: Text('All')),
                      ButtonSegment(value: _FilterKind.percent, label: Text('%')),
                      ButtonSegment(value: _FilterKind.fixed, label: Text('Fixed')),
                    ],
                    selected: {_filter},
                    style: ButtonStyle(
                      visualDensity:
                          const VisualDensity(horizontal: -2, vertical: -2),
                      shape: WidgetStatePropertyAll(
                        RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    onSelectionChanged: (v) => setState(() => _filter = v.first),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ===== Content (LIST ONLY) =====
              Expanded(
                child: discounts.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator.adaptive()),
                  error: (e, _) => Center(child: Text('Failed to load: $e')),
                  data: (list) {
                    // Filter by type
                    Iterable<Discount> filtered = switch (_filter) {
                      _FilterKind.percent =>
                        list.where((d) => d.kind == DiscountKind.percent),
                      _FilterKind.fixed =>
                        list.where((d) => d.kind != DiscountKind.percent),
                      _ => list,
                    };

                    // Filter by search
                    final q = _searchCtrl.text.trim().toLowerCase();
                    if (q.isNotEmpty) {
                      filtered = filtered.where((d) {
                        final name = d.name.toLowerCase();
                        final code = d.code.toLowerCase();
                        return name.contains(q) || code.contains(q);
                      });
                    }

                    final items = filtered.toList();
                    if (items.isEmpty) return const _EmptyState();

                    final dense = _density == _Density.compact;

                    return Scrollbar(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, __) =>
                            SizedBox(height: dense ? 8 : 12),
                        itemBuilder: (_, i) {
                          final d = items[i];
                          final isSel = (selected == d);
                          return _DiscountRow(
                            discount: d,
                            selected: isSel,
                            dense: dense,
                            onTap: () {
                              ref.read(selectedDiscountProvider.notifier).state = d;
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    );
                  },
                ),
              ),

              const SizedBox(height: 12),

              // ===== Footer =====
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        ref.read(selectedDiscountProvider.notifier).state = null;
                        Navigator.pop(context);
                      },
                      icon: const Icon(Icons.clear),
                      label: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.done_rounded),
                      label: const Text('Close'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ===== Row item (tanpa grid, clean & modern) =====
class _DiscountRow extends StatelessWidget {
  const _DiscountRow({
    required this.discount,
    required this.selected,
    required this.onTap,
    required this.dense,
  });

  final Discount discount;
  final bool selected;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPercent = discount.kind == DiscountKind.percent;
    final valueText =
        isPercent ? '${discount.value.toStringAsFixed(0)}%' : rp(discount.value.round());
    final code = discount.code.isNotEmpty ? discount.code : null;

    final pad = EdgeInsets.symmetric(horizontal: 14, vertical: dense ? 8 : 12);
    final radius = BorderRadius.circular(14);

    return InkWell(
      borderRadius: radius,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: pad,
        decoration: BoxDecoration(
          borderRadius: radius,
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: .07)
              : theme.colorScheme.surface,
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.dividerColor.withValues(alpha: .7),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            // Leading: big value chip
            _ValueBadge(text: valueText, isPercent: isPercent, dense: dense),
            const SizedBox(width: 12),
            // Title + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment:
                    dense ? MainAxisAlignment.center : MainAxisAlignment.start,
                children: [
                  Text(
                    discount.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: dense ? 14 : 15.5,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (code != null)
                    _CodeChip(code: code)
                  else
                    Text(
                      isPercent ? 'Percentage discount' : 'Fixed amount discount',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 140),
              opacity: selected ? 1 : 0,
              child: Icon(Icons.check_circle_rounded,
                  color: theme.colorScheme.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CodeChip extends StatelessWidget {
  const _CodeChip({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Code: $code',
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ValueBadge extends StatelessWidget {
  const _ValueBadge({required this.text, required this.isPercent, required this.dense});
  final String text;
  final bool isPercent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = isPercent
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.tertiaryContainer;
    final fg = isPercent
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onTertiaryContainer;

    return Container(
      width: dense ? 60 : 68,
      height: dense ? 44 : 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: dense ? 14 : 16,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_offer_outlined,
              size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 8),
          Text(
            'No discounts yet.\nGo to Settings → Discounts to add.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.colorScheme.outline),
          ),
        ],
      ),
    );
  }
}
