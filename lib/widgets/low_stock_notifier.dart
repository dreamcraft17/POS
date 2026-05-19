import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/low_stock_provider.dart';
import '../providers/products_provider.dart';

class LowStockNotifier extends ConsumerWidget {
  const LowStockNotifier({
    super.key,
    this.showAsBanner = true,
    this.maxVisible = 5,
  });

  /// true = MaterialBanner, false = Card list 
  final bool showAsBanner;
  final int maxVisible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    final lowOut = ref.watch(lowStockProvider);
    final threshold = ref.watch(lowStockThresholdProvider);

    return productsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => _wrap(
        context,
        child: _StatusRow(
          text:
              'Gagal memuat stok: $e',
          icon: Icons.error_outline,
          color: Colors.red,
          onRefresh: () => ref.invalidate(productsProvider),
        ),
        showAsBanner: showAsBanner,
      ),
      data: (_) {
        final low = lowOut.low;
        final out = lowOut.out;

        if (low.isEmpty && out.isEmpty) {
          // Tidak tampil apa-apa jika stok aman
          return const SizedBox.shrink();
        }

        // Compose teks ringkas
        final msg = [
          if (out.isNotEmpty) '${out.length} produk HABIS',
          if (low.isNotEmpty) '${low.length} produk <= $threshold',
        ].join(' • ');

        // Daftar singkat untuk ditampilkan
        final items = [
          ...out.map((p) => ('${p.name} (SKU: ${p.sku}) — 0')),
          ...low.map((p) => ('${p.name} (SKU: ${p.sku}) — ${p.stock}')),
        ];

        return _wrap(
          context,
          showAsBanner: showAsBanner,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _StatusRow(
                text: msg,
                icon: Icons.inventory_2_outlined,
                color: Colors.orange,
                onRefresh: () => ref.invalidate(productsProvider),
              ),
              const SizedBox(height: 8),
              _ChipsWrap(
                labels: items.take(maxVisible).toList(),
                overflowCount: items.length - maxVisible,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.text,
    required this.icon,
    required this.color,
    required this.onRefresh,
  });

  final String text;
  final IconData icon;
  final Color color;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Refresh stok',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

Widget _wrap(BuildContext context, {required Widget child, required bool showAsBanner}) {
  if (showAsBanner) {
    return MaterialBanner(
      backgroundColor: Colors.orange.withValues(alpha: 0.08),
      content: child,
      actions: const [SizedBox.shrink()],
      elevation: 0,
      dividerColor: Colors.transparent,
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    );
  }
  return Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: child,
    ),
  );
}

class _ChipsWrap extends StatelessWidget {
  const _ChipsWrap({required this.labels, required this.overflowCount});
  final List<String> labels;
  final int overflowCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: -6,
      children: [
        for (final s in labels)
          Chip(
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            label: Text(s, overflow: TextOverflow.ellipsis),
          ),
        if (overflowCount > 0)
          Chip(
            label: Text('+$overflowCount lagi'),
            avatar: const Icon(Icons.more_horiz, size: 18),
          ),
      ],
    );
  }
}
