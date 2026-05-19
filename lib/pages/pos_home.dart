import 'package:ee_pos/pages/open_bills_page.dart';

import '../providers/ui_state.dart';
import 'package:ee_pos/widgets/discount_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/menu_grid.dart';
import '../ui/pos_theme.dart';
import '../providers/products_provider.dart';
import '../widgets/product_search_bar.dart';
import '../widgets/cart_panel.dart';
import '../providers/menus_provider.dart';

class POSHome extends ConsumerStatefulWidget {
  const POSHome({super.key});

  @override
  ConsumerState<POSHome> createState() => _POSHomeState();
}

class _POSHomeState extends ConsumerState<POSHome> {
  String? _selectedType; // null == All

  Future<void> _refreshAll() async {
    // ✅ refresh keduanya: products & menus
    ref.invalidate(productsProvider);
    ref.invalidate(menusProvider);
    try {
      await Future.wait([
        ref.read(productsProvider.future),
        ref.read(menusProvider.future),
      ]);
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    // 🔁 Auto refresh sekali saat halaman pertama kali dibuka
    Future.microtask(_refreshAll);
  }

  @override
  Widget build(BuildContext context) {
    final menusAsync = ref.watch(menusProvider);

    // Kumpulkan daftar type yang unik dari data menus (dinamis)
    final typeChips = menusAsync.maybeWhen<List<String>>(
      data: (menus) {
        final set = <String>{};
        for (final m in menus) {
          final t = (m.type ?? '').trim().toLowerCase();
          if (t.isNotEmpty) set.add(t);
        }
        final list = set.toList()..sort();
        return list;
      },
      orElse: () => const [],
    );

    String pretty(String s) =>
        s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);

    return Scaffold(
      backgroundColor: PosTheme.white,
      body: Row(
        children: [
          // ================== PRODUCTS ==================
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                      children: [
                        // Search + Discount button
                        Row(
                          children: [
                            const Expanded(child: ProductSearchBar()),
                            const SizedBox(width: 8),

                            // === Toggle Grid/List ===
                            IconButton(
                              tooltip: 'Toggle view',
                              onPressed: () {
                                final current = ref.read(menuViewModeProvider);
                                ref.read(menuViewModeProvider.notifier).state =
                                    current == MenuViewMode.grid
                                        ? MenuViewMode.list
                                        : MenuViewMode.grid;
                              },
                              icon: Icon(
                                ref.watch(menuViewModeProvider) ==
                                        MenuViewMode.grid
                                    ? Icons.view_list
                                    : Icons.grid_view,
                              ),
                            ),

                            const SizedBox(width: 8),
                            FilledButton.icon(
                              onPressed: () => showDiscountDialog(context),
                              icon: const Icon(Icons.local_offer_outlined),
                              label: const Text('Discount'),
                            ),

                            const SizedBox(width: 8),

                            // === Open Bills (berlabel, 2 baris) ===
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => const OpenBillsPage()),
                                );
                              },
                              icon: const Icon(Icons.folder_open),
                              label: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: const [
                                  Text('Open Bills'),
                                ],
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // ========= DINAMIS CATEGORY (berdasarkan type dari menus) =========
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              ChoiceChip(
                                label: const Text('All'),
                                selected: _selectedType == null,
                                onSelected: (_) {
                                  setState(() => _selectedType = null);
                                },
                              ),
                              for (final t in typeChips)
                                ChoiceChip(
                                  label: Text(pretty(t)),
                                  selected: _selectedType == t,
                                  onSelected: (_) {
                                    setState(() => _selectedType = t);
                                  },
                                ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 10),
                        Expanded(
                          child: RefreshIndicator.adaptive(
                            onRefresh: _refreshAll,
                            child: menusAsync.when(
                              data: (menus) => MenuGrid(
                                menus: menus,
                                // kirim type terpilih ke MenuGrid untuk filtering
                                selectedType: _selectedType,
                              ),
                              loading: () => const Center(
                                child: CircularProgressIndicator.adaptive(),
                              ),
                              error: (e, _) => Center(
                                child: Text(
                                  'Error: $e',
                                  style:
                                      const TextStyle(color: PosTheme.muted),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          // ================== CART ==================
          Expanded(flex: 1, child: CartPanel(onRefreshAll: _refreshAll)),
        ],
      ),
    );
  }
}
