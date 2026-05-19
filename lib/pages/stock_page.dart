// lib/pages/stock_page.dart
import 'dart:ui' show FontFeature, ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/products_provider.dart';
import '../services/api_service.dart';

class StockPage extends ConsumerStatefulWidget {
  const StockPage({super.key});
  @override
  ConsumerState<StockPage> createState() => _StockPageState();
}

class _StockPageState extends ConsumerState<StockPage> {
  bool onlyZero = false;
  String? workingSku; // when non-null, show small loader for that SKU
  String query = '';

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

    // Monochrome (white background) — clean & elegant
    final theme = Theme.of(context).copyWith(
      colorScheme: const ColorScheme.light(
        primary: Colors.black,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: Colors.black,
        secondary: Colors.black,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: Colors.black.withValues(alpha: 0.04),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Colors.black12),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.black),
      dividerTheme: const DividerThemeData(color: Colors.black12, thickness: 1, space: 1),
      textTheme: Theme.of(context).textTheme.apply(
            bodyColor: Colors.black,
            displayColor: Colors.black,
          ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: Colors.black,
        contentTextStyle: TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.black.withValues(alpha: 0.04),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black26),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Colors.black87, width: 1.2),
        ),
        prefixIconColor: Colors.black54,
        hintStyle: const TextStyle(color: Colors.black45),
        labelStyle: const TextStyle(color: Colors.black87),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.black,
          side: const BorderSide(color: Colors.black54),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: Colors.black),
      ),
    );

    return Theme(
      data: theme,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header Row
            Material(
              color: Colors.black.withValues(alpha: 0.04),
              elevation: 0,
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    const _Title(),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Refresh',
                      onPressed: () => ref.invalidate(productsProvider),
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Segmented toggle (All / Out of stock)
                _Segmented(
                  onlyZero: onlyZero,
                  onChanged: (v) => setState(() => onlyZero = v),
                ),
                const SizedBox(width: 12),
                // Search
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => query = v.trim()),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search by name or SKU',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: productsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                error: (e, _) => Center(child: Text('Error: $e')),
                data: (list) {
                  // Sort by stock asc, then name
                  final items = [...list]
                    ..sort((a, b) {
                      final s = a.stock.compareTo(b.stock);
                      return s != 0 ? s : a.name.toLowerCase().compareTo(b.name.toLowerCase());
                    });

                  // Filter by toggle & search
                  Iterable<dynamic> filtered = items;
                  if (onlyZero) filtered = filtered.where((p) => p.stock <= 0);
                  if (query.isNotEmpty) {
                    final q = query.toLowerCase();
                    filtered = filtered.where((p) =>
                        p.name.toLowerCase().contains(q) || p.sku.toLowerCase().contains(q));
                  }
                  final data = filtered.toList();

                  if (data.isEmpty) {
                    return const _EmptyState();
                  }

                  return GlassCard(
                    child: ListView.separated(
                      itemCount: data.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final p = data[i];
                        final busy = workingSku == p.sku;
                        final zebra = i.isEven;
                        final isOut = p.stock <= 0;
                        final isLow = !isOut && p.stock <= 3;

                        return AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: busy ? 0.65 : 1,
                          child: Container(
                            color: zebra ? Colors.black.withValues(alpha: 0.02) : Colors.transparent,
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              leading: _StockBubble(stock: p.stock),
                              title: Text(
                                p.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: DefaultTextStyle.merge(
                                  style: const TextStyle(
                                    fontFeatures: [FontFeature.tabularFigures()],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              'SKU: ${p.sku}',
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Text('Price: Rp ${p.priceCents}'),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      _StockMeter(value: _stockValue(p.stock)),
                                    ],
                                  ),
                                ),
                              ),
                              trailing: Wrap(
                                spacing: 6,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  if (isOut) const _Badge(label: 'OUT'),
                                  if (isLow) const _Badge(label: 'LOW', outlined: true),
                                  IconButton(
                                    tooltip: 'Decrease by 1',
                                    onPressed: busy ? null : () => _bump(p.sku, -1),
                                    icon: busy
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.remove),
                                  ),
                                  IconButton(
                                    tooltip: 'Increase by 1',
                                    onPressed: busy ? null : () => _bump(p.sku, 1),
                                    icon: busy
                                        ? const SizedBox(
                                            width: 20,
                                            height: 20,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.add),
                                  ),
                                  OutlinedButton(
                                    onPressed: busy ? null : () => _restockDialog(p.sku),
                                    child: const Text('Restock'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  static double _stockValue(int stock) {
    if (stock <= 0) return 0;
    if (stock <= 3) return 0.2;
    if (stock <= 10) return 0.5;
    return 0.85;
  }

  Future<void> _bump(String sku, int delta) async {
    setState(() {
      workingSku = sku;
    });
    try {
      await ApiService.shared().adjustStock(
        sku,
        delta,
        reason: delta > 0 ? 'restock-quick' : 'adjust-quick',
      );
      ref.invalidate(productsProvider);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed: $e')),
      );
    } finally {
      if (!mounted) return;
      setState(() {
        workingSku = null;
      });
    }
  }

  Future<void> _restockDialog(String sku) async {
    final ctrl = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restock'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Quantity (+)',
            hintText: 'e.g. 10',
          ),
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final n = int.tryParse(ctrl.text.trim()) ?? 0;
              if (n > 0) {
                Navigator.pop(context);
                await _bump(sku, n);
                if (!mounted) return;
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Restock successful')));
              }
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title();
  @override
  Widget build(BuildContext context) {
    return const Text(
      'Inventory',
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _Segmented extends StatelessWidget {
  final bool onlyZero;
  final ValueChanged<bool> onChanged;
  const _Segmented({required this.onlyZero, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black54),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SegBtn(
              label: 'All',
              selected: !onlyZero,
              onTap: () => onChanged(false),
            ),
            _SegBtn(
              label: 'Out of stock',
              selected: onlyZero,
              onTap: () => onChanged(true),
            ),
          ],
        ),
      ),
    );
  }
}

class _SegBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: selected ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.black : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.black,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool outlined;
  const _Badge({required this.label, this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : Colors.black,
        border: Border.all(color: Colors.black54),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: outlined ? Colors.black : Colors.white,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _StockBubble extends StatelessWidget {
  final int stock;
  const _StockBubble({required this.stock});

  @override
  Widget build(BuildContext context) {
    final out = stock <= 0;
    return CircleAvatar(
      radius: 18,
      backgroundColor: out ? Colors.black : Colors.transparent,
      child: Text(
        '$stock',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: out ? Colors.white : Colors.black,
        ),
      ),
    );
  }
}

class _StockMeter extends StatelessWidget {
  final double value; // 0..1
  const _StockMeter({required this.value});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Stack(
        children: [
          Container(height: 4, color: Colors.black12),
          FractionallySizedBox(
            alignment: Alignment.centerLeft,
            widthFactor: value.clamp(0.0, 1.0),
            child: Container(height: 4, color: Colors.black),
          ),
        ],
      ),
    );
  }
}

class GlassCard extends StatelessWidget {
  final Widget child;
  const GlassCard({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.04),
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: child,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.inventory_2_outlined, size: 36, color: Colors.black45),
          SizedBox(height: 8),
          Text(
            'All items are in stock',
            style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}