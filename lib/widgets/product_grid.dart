// lib/widgets/product_grid.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ui/pos_theme.dart';
import '../utils/formatting.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/ui_state.dart';
import 'edit_product_dialog.dart';

class ProductGrid extends ConsumerWidget {
  const ProductGrid({super.key, required this.products});
  final List<Product> products;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final filtered = products.where((p) {
      if (query.isEmpty) return true;
      return p.name.toLowerCase().contains(query) ||
          p.sku.toLowerCase().contains(query);
    }).toList();

    // Tetap scrollable (agar RefreshIndicator parent tetap jalan) saat kosong
    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 140),
          Center(
            child: Text(
              'Tidak ada produk yang cocok',
              style: TextStyle(color: PosTheme.muted),
            ),
          ),
          SizedBox(height: 140),
        ],
      );
    }

    return GridView.builder(
      key: const PageStorageKey('productGrid'),
      padding: const EdgeInsets.only(bottom: 10),
      cacheExtent: 520,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 240, // ukuran kartu stabil ~240px
        childAspectRatio: 3 / 4, // kartu sedikit lebih tinggi
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
      ),
      itemCount: filtered.length,
      itemBuilder: (context, i) {
        final p = filtered[i];
        return RepaintBoundary(
          child: _ProductTile(
            key: ValueKey(p.sku),
            product: p,
            onAddToCart: () => ref.read(cartProvider.notifier).add(p),
            onLongPress: () => showEditProductDialog(context, ref, p),
          ),
        );
      },
    );
  }
}

class _ProductTile extends StatefulWidget {
  const _ProductTile({
    super.key,
    required this.product,
    required this.onAddToCart,
    required this.onLongPress,
  });

  final Product product;
  final VoidCallback onAddToCart;
  final VoidCallback onLongPress;

  @override
  State<_ProductTile> createState() => _ProductTileState();
}

class _ProductTileState extends State<_ProductTile> {
  static DateTime _lastSnackAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _hover = false;
  bool _pressed = false;

  String _initials(String s) {
    final parts = s.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final initials = _initials(p.name);
    final canHover = kIsWeb ||
        Theme.of(context).platform == TargetPlatform.windows ||
        Theme.of(context).platform == TargetPlatform.linux ||
        Theme.of(context).platform == TargetPlatform.macOS;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      transform:
          _pressed ? (Matrix4.identity()..scale(.985)) : Matrix4.identity(),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PosTheme.border),
        color: Colors.white,
        boxShadow: _hover
            ? const [
                BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 16,
                    offset: Offset(0, 8))
              ]
            : const [
                BoxShadow(
                    color: Color(0x0D000000),
                    blurRadius: 8,
                    offset: Offset(0, 4))
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () {
  setState(() => _pressed = false);
  widget.onAddToCart();

  final screenW = MediaQuery.of(context).size.width;
  const desired = 280.0; // target lebar snackbar
  const minSide = 12.0;  // minimal gutter kiri/kanan
  final side = screenW > desired + minSide * 2
      ? (screenW - desired) / 2
      : minSide; // kalau layar sempit, tetap kasih gutter minimal

  final now = DateTime.now();
  if (now.difference(_lastSnackAt) >= const Duration(milliseconds: 250)) {
    _lastSnackAt = now;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(side, 0, side, 10), // << bikin tidak full width
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: 0,
          backgroundColor: Colors.black.withValues(alpha: 0.65),
          duration: const Duration(milliseconds: 900),
          content: Text(
            'Added ${p.name}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, height: 1.1, fontWeight: FontWeight.w400, color: Colors.white),
          ),
        ),
      );
  }
},
            onLongPress: widget.onLongPress,
            onHover: canHover ? (v) => setState(() => _hover = v) : null,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Stack(
                children: [
                  // ===== isi utama kartu =====
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Media/thumbnail — di-Expanded agar area ini yang melar
                      Expanded(child: _MediaBox(initials: initials)),
                      const SizedBox(height: 10),

                      // Nama
                      Text(
                        p.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          height: 1.2,
                          color: PosTheme.black,
                        ),
                      ),
                      const SizedBox(height: 6),

                      // Baris info: SKU badge + Stok
                      Row(
                        children: [
                          _SkuBadge(sku: p.sku),
                          const Spacer(),
                          _StockChip(stock: p.stock),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Price chip
                      _PriceChip(text: rp(p.priceCents)),
                      const SizedBox(height: 6),

                      // Tombol Add
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: widget.onAddToCart,
                          style: FilledButton.styleFrom(
                            backgroundColor: PosTheme.black,
                            foregroundColor: Colors.white,
                            padding:
                                const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.add_shopping_cart_rounded,
                              size: 18),
                          label: const Text('Add'),
                        ),
                      ),
                    ],
                  ),

                  // ===== Overlay halus saat hover/tap (AMAN: tanpa duplikasi child) =====
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !(_hover || _pressed),
                      child: AnimatedOpacity(
                        opacity: (_hover || _pressed) ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Color.fromRGBO(0, 0, 0, .08),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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

// ======= sub-widgets =======

class _MediaBox extends StatelessWidget {
  const _MediaBox({required this.initials});
  final String initials;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: PosTheme.panel,
        border: Border.all(color: PosTheme.border),
        borderRadius: BorderRadius.circular(10),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF7F8FB), Color(0xFFFFFFFF)],
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.1,
            color: PosTheme.black,
          ),
        ),
      ),
    );
  }
}

class _PriceChip extends StatelessWidget {
  const _PriceChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: PosTheme.border)),
        color: Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            letterSpacing: .2,
          ),
        ),
      ),
    );
  }
}

class _SkuBadge extends StatelessWidget {
  const _SkuBadge({required this.sku});
  final String sku;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: StadiumBorder(side: BorderSide(color: PosTheme.border)),
        color: const Color(0xFFF7F7F9),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_rounded,
                size: 14, color: Colors.black54),
            const SizedBox(width: 4),
            Text(
              sku,
              style:
                  const TextStyle(fontSize: 12, color: Colors.black87),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _StockChip extends StatelessWidget {
  const _StockChip({required this.stock});
  final int stock;

  @override
  Widget build(BuildContext context) {
    final low = stock <= 3;
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: low ? const Color(0xFFFFF2F0) : const Color(0xFFF4FFF4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              low
                  ? Icons.warning_amber_rounded
                  : Icons.inventory_2_rounded,
              size: 14,
              color: low
                  ? const Color(0xFFD13B2F)
                  : const Color(0xFF2F8F2F),
            ),
            const SizedBox(width: 4),
            Text(
              'Stock: $stock',
              style: TextStyle(
                fontSize: 12,
                color: low
                    ? const Color(0xFFD13B2F)
                    : const Color(0xFF1E6E1E),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

