import 'package:flutter/material.dart';

enum SidebarItemType { header, item }

class SidebarItem {
  final SidebarItemType type;
  final String label;
  const SidebarItem.header(this.label) : type = SidebarItemType.header;
  const SidebarItem.item(this.label) : type = SidebarItemType.item;
}

typedef SidebarTrailingBuilder = Widget? Function(int index, String label);

typedef SidebarLeadingBuilder = Widget? Function(int index, String label);

/// A grouped sidebar that visually emphasizes sections (headers) and
/// shows items inside soft cards. Keeps the same public API
/// (selectedIndex is still the index into [items]).
class SidebarMenu extends StatelessWidget {
  const SidebarMenu({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelect,
    this.width = 240,
    this.trailingBuilder,
    this.leadingBuilder,
    this.sectionSpacing = 14,
    this.itemSpacing = 2,
    this.activeColor,
  });

  final List<SidebarItem> items;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final double width;
  final SidebarTrailingBuilder? trailingBuilder;
  final SidebarLeadingBuilder? leadingBuilder;

  /// Spacing between groups
  final double sectionSpacing;

  /// Vertical spacing between items in the same group
  final double itemSpacing;

  /// Accent color for the active pill & indicator; defaults to Theme.primaryColor
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final primary = activeColor ?? colorScheme.primary;

    // Build groups from [items]. A header starts a new group; items until next header belong to it.
    final groups = <_Group>[];
    _Group? current;
    for (var i = 0; i < items.length; i++) {
      final it = items[i];
      if (it.type == SidebarItemType.header) {
        current = _Group(title: it.label);
        groups.add(current);
      } else {
        current ??= _Group(title: '');
        current.items.add(_IndexedItem(index: i, label: it.label));
      }
    }

    return Container(
      width: width,
      color: const Color(0xFFF7F7F8),
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        itemCount: groups.length,
        separatorBuilder: (_, __) => SizedBox(height: sectionSpacing),
        itemBuilder: (ctx, gi) {
          final group = groups[gi];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (group.title.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 8),
                  child: Text(
                    group.title.toUpperCase(),
                    style: TextStyle(
                      letterSpacing: .6,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.black.withValues(alpha: .55),
                    ),
                  ),
                ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12.withValues(alpha: .06)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x0F000000),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: [
                      for (var i = 0; i < group.items.length; i++) ...[
                        if (i > 0) SizedBox(height: itemSpacing),
                        _SidebarTile(
                          item: group.items[i],
                          selectedIndex: selectedIndex,
                          onTap: onSelect,
                          primary: primary,
                          trailingBuilder: trailingBuilder,
                          leadingBuilder: leadingBuilder,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required this.item,
    required this.selectedIndex,
    required this.onTap,
    required this.primary,
    this.trailingBuilder,
    this.leadingBuilder,
  });

  final _IndexedItem item;
  final int selectedIndex;
  final ValueChanged<int> onTap;
  final Color primary;
  final SidebarTrailingBuilder? trailingBuilder;
  final SidebarLeadingBuilder? leadingBuilder;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool hovering = false;

  @override
  Widget build(BuildContext context) {
    final active = widget.selectedIndex == widget.item.index;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => widget.onTap(widget.item.index),
      onHover: (v) => setState(() => hovering = v),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? widget.primary.withValues(alpha: .10)
              : (hovering ? Colors.black.withValues(alpha: .035) : Colors.transparent),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            // Active indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              width: 4,
              height: 22,
              decoration: BoxDecoration(
                color: active ? widget.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            if (widget.leadingBuilder != null)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: widget.leadingBuilder!(widget.item.index, widget.item.label) ?? const SizedBox(),
              ),
            Expanded(
              child: Text(
                widget.item.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  color: Colors.black.withValues(alpha: active ? .95 : .80),
                ),
              ),
            ),
            if (widget.trailingBuilder != null)
              widget.trailingBuilder!(widget.item.index, widget.item.label) ?? const SizedBox(),
          ],
        ),
      ),
    );
  }
}

class _Group {
  _Group({required this.title});
  final String title;
  final List<_IndexedItem> items = [];
}

class _IndexedItem {
  _IndexedItem({required this.index, required this.label});
  final int index;
  final String label;
}
