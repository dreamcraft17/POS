import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:async';

import '../ui/pos_theme.dart';
import '../providers/ui_state.dart';

class ProductSearchBar extends ConsumerStatefulWidget {
  const ProductSearchBar({super.key});

  @override
  ConsumerState<ProductSearchBar> createState() => _ProductSearchBarState();
}

class _ProductSearchBarState extends ConsumerState<ProductSearchBar> {
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(searchQueryProvider);

    return TextField(
      onChanged: (v) {
        _debounce?.cancel();
        _debounce = Timer(const Duration(milliseconds: 180), () {
          if (!mounted) return;
          ref.read(searchQueryProvider.notifier).state = v;
        });
      },
      decoration: PosTheme.searchFieldDecoration(
        hint: 'Search Menu',
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                onPressed: () {
                  _debounce?.cancel();
                  ref.read(searchQueryProvider.notifier).state = '';
                  FocusScope.of(context).unfocus();
                },
                icon: const Icon(Icons.clear),
              ),
      ),
      textInputAction: TextInputAction.search,
    );
  }
}
