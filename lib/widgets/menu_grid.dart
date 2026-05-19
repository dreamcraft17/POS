import 'package:ee_pos/widgets/modifiers_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/menu.dart';
import '../models/product.dart';
import '../providers/cart_provider.dart';
import '../providers/ui_state.dart';
import '../ui/pos_theme.dart';
import '../utils/formatting.dart';

class MenuGrid extends ConsumerWidget {
  const MenuGrid({
    super.key,
    required this.menus,
  });

  /// Sudah difilter di [filteredMenusProvider].
  final List<MenuItemModel> menus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final viewMode = ref.watch(menuViewModeProvider);

    if (menus.isEmpty) {
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

    if (viewMode == MenuViewMode.grid) {
      return GridView.builder(
        key: const PageStorageKey('menuGrid'),
        padding: const EdgeInsets.only(bottom: 10),
        cacheExtent: 520,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: true,
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 240,
          childAspectRatio: 3 / 4,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: menus.length,
        itemBuilder: (_, i) {
          final m = menus[i];
          return RepaintBoundary(
            child: _MenuTile(
              key: ValueKey(m.code),
              menu: m,
              onAdd: () => _addMenuToCart(context, ref, m),
            ),
          );
        },
      );
    }

    return ListView.separated(
      key: const PageStorageKey('menuList'),
      padding: const EdgeInsets.only(bottom: 10),
      cacheExtent: 520,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: menus.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final m = menus[i];
        return RepaintBoundary(
          child: _MenuListRow(
            key: ValueKey(m.code),
            menu: m,
            onAdd: () => _addMenuToCart(context, ref, m),
          ),
        );
      },
    );
  }

  static Future<void> _addMenuToCart(
    BuildContext context,
    WidgetRef ref,
    MenuItemModel m,
  ) async {
    final res = await showModifiersDialog(context);
    if (res == null) return;
    final displayName = m.name + res.toSuffix() + res.toNoteLine();
    ref.read(cartProvider.notifier).add(
          Product('menu:${m.code}', displayName, m.priceCents, 0),
        );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.menu,
    required this.onAdd,
  });

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
          BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
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
                    child: Icon(
                      Icons.fastfood_rounded,
                      size: 32,
                      color: Colors.black54,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                menu.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                rp(menu.priceCents),
                style: const TextStyle(color: Colors.black54),
              ),
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

class _MenuListRow extends StatelessWidget {
  const _MenuListRow({
    super.key,
    required this.menu,
    required this.onAdd,
  });

  final MenuItemModel menu;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PosTheme.border),
        color: Colors.white,
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
              child: Icon(Icons.fastfood_rounded, size: 24, color: Colors.black54),
            ),
          ),
        ),
        title: Text(
          menu.name,
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
            rp(menu.priceCents),
            style: const TextStyle(color: Colors.black54),
          ),
        ),
        trailing: FilledButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
      ),
    );
  }
}
