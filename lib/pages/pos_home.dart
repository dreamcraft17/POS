import 'package:ee_pos/pages/open_bills_page.dart';
import 'package:ee_pos/widgets/discount_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/menu_filter_providers.dart';
import '../providers/menus_provider.dart';
import '../providers/ui_state.dart';
import '../ui/pos_theme.dart';
import '../widgets/cart_panel.dart';
import '../widgets/menu_grid.dart';
import '../widgets/product_search_bar.dart';

class POSHome extends ConsumerStatefulWidget {
  const POSHome({super.key});

  @override
  ConsumerState<POSHome> createState() => _POSHomeState();
}

class _POSHomeState extends ConsumerState<POSHome> {
  Future<void> _refreshAll() async {
    await ref.read(menusProvider.notifier).reloadFromNetwork();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PosTheme.white,
      body: Row(
        children: [
          Expanded(
            flex: 2,
            child: _PosCatalogPane(onRefreshAll: _refreshAll),
          ),
          Expanded(
            flex: 1,
            child: CartPanel(onRefreshAll: _refreshAll),
          ),
        ],
      ),
    );
  }
}

/// Panel kiri: hanya bagian ini yang rebuild saat menu/search/kategori berubah.
class _PosCatalogPane extends ConsumerWidget {
  const _PosCatalogPane({required this.onRefreshAll});
  final Future<void> Function() onRefreshAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menusAsync = ref.watch(menusProvider);
    final typeChips = ref.watch(menuTypeChipsProvider);
    final selectedType = ref.watch(posMenuCategoryProvider);

    String pretty(String s) =>
        s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(child: ProductSearchBar()),
              const SizedBox(width: 8),
              Consumer(
                builder: (context, ref, _) {
                  final grid =
                      ref.watch(menuViewModeProvider) == MenuViewMode.grid;
                  return IconButton(
                    tooltip: 'Toggle view',
                    onPressed: () {
                      ref.read(menuViewModeProvider.notifier).state =
                          grid ? MenuViewMode.list : MenuViewMode.grid;
                    },
                    icon: Icon(grid ? Icons.view_list : Icons.grid_view),
                  );
                },
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => showDiscountDialog(context),
                icon: const Icon(Icons.local_offer_outlined),
                label: const Text('Discount'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const OpenBillsPage()),
                  );
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Open Bills'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: selectedType == null,
                  onSelected: (_) {
                    ref.read(posMenuCategoryProvider.notifier).state = null;
                  },
                ),
                for (final t in typeChips)
                  ChoiceChip(
                    label: Text(pretty(t)),
                    selected: selectedType == t,
                    onSelected: (_) {
                      ref.read(posMenuCategoryProvider.notifier).state = t;
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: RefreshIndicator.adaptive(
              onRefresh: onRefreshAll,
              child: menusAsync.when(
                data: (_) {
                  final filtered = ref.watch(filteredMenusProvider);
                  return MenuGrid(menus: filtered);
                },
                loading: () => const Center(
                  child: CircularProgressIndicator.adaptive(),
                ),
                error: (e, _) => Center(
                  child: Text(
                    'Error: $e',
                    style: const TextStyle(color: PosTheme.muted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
