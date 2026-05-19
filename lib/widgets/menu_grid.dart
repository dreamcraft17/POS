import 'package:ee_pos/widgets/modifiers_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../ui/pos_theme.dart';
import '../utils/formatting.dart';
import '../models/menu.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/ui_state.dart'; // searchQueryProvider + menuViewModeProvider

class MenuGrid extends ConsumerWidget {
  const MenuGrid({
    super.key,
    required this.menus,
    this.selectedType, // null => All
  });

  final List<MenuItemModel> menus;
  final String? selectedType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(searchQueryProvider).trim().toLowerCase();
    final viewMode = ref.watch(menuViewModeProvider);

    final filteredMenus = menus.where((m) {
      // === filter berdasarkan query ===
      final matchesQuery = query.isEmpty ||
          m.name.toLowerCase().contains(query) ||
          m.code.toLowerCase().contains(query) ||
          m.components.any((c) => c.productSku.toLowerCase().contains(query));

      // === filter berdasarkan type dinamis (All jika null) ===
      final t = m.type?.trim().toLowerCase();
      final matchesType =
          selectedType == null || selectedType!.toLowerCase() == t;

      return matchesQuery && matchesType;
    }).toList();

    if (filteredMenus.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 140),
          Center(
            child: Text(
              'Tidak ada menu',
              style: TextStyle(color: PosTheme.muted),
            ),
          ),
          SizedBox(height: 140),
        ],
      );
    }

    // ======== GRID MODE ========
    if (viewMode == MenuViewMode.grid) {
      return GridView.builder(
        key: const PageStorageKey('menuGrid'),
        padding: const EdgeInsets.only(bottom: 10),
        cacheExtent: 480,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          childAspectRatio: 3 / 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: filteredMenus.length,
        itemBuilder: (_, i) {
          final m = filteredMenus[i];
          return _MenuTile(
            menu: m,
            onAdd: () async {
              final pseudoSku = 'menu:${m.code}';
              final res = await showModifiersDialog(context);
              if (res == null) return;
              final displayName = m.name + res.toSuffix() + res.toNoteLine();
              ref.read(cartProvider.notifier).add(
                    Product(pseudoSku, displayName, m.priceCents, 0),
                  );
            },
          );
        },
      );
    }

    // ======== LIST MODE ========
    return ListView.separated(
      key: const PageStorageKey('menuList'),
      padding: const EdgeInsets.only(bottom: 10),
      cacheExtent: 480,
      itemCount: filteredMenus.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = filteredMenus[i];
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PosTheme.border),
            color: Colors.white,
            boxShadow: const [
              BoxShadow(
                color: Color(0x0D000000),
                blurRadius: 6,
                offset: Offset(0, 3),
              )
            ],
          ),
          child: ListTile(
            leading: DecoratedBox(
              decoration: BoxDecoration(
                color: PosTheme.panel,
                border: Border.all(color: PosTheme.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SizedBox(
                width: 42,
                height: 42,
                child: Center(
                  child: Icon(Icons.fastfood_rounded,
                      size: 24, color: Colors.black54),
                ),
              ),
            ),
            title: Text(
              m.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14.5,
                height: 1.2,
                color: PosTheme.black,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                rp(m.priceCents),
                style: const TextStyle(color: Colors.black54),
              ),
            ),
            trailing: FilledButton.icon(
              onPressed: () async {
                final pseudoSku = 'menu:${m.code}';
                final res = await showModifiersDialog(context);
                if (res == null) return;
                final displayName = m.name + res.toSuffix() + res.toNoteLine();
                ref.read(cartProvider.notifier).add(
                      Product(pseudoSku, displayName, m.priceCents, 0),
                    );
              },
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ),
        );
      },
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({required this.menu, required this.onAdd});
  final MenuItemModel menu;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: PosTheme.border),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Color(0x0D000000), blurRadius: 8, offset: Offset(0, 4))
        ],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onAdd,
        child: Padding(
          padding: const EdgeInsets.all(10),
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
                    child: Icon(Icons.fastfood_rounded,
                        size: 32, color: Colors.black54),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                menu.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontWeight: FontWeight.w800, height: 1.15),
              ),
              const SizedBox(height: 6),
              Text(rp(menu.priceCents),
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add),
                  label: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
