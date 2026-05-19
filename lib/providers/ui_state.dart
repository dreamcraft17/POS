import 'package:flutter_riverpod/flutter_riverpod.dart';

final searchQueryProvider = StateProvider<String>((ref) => '');

enum MenuViewMode { grid, list }

final menuViewModeProvider =
    StateProvider<MenuViewMode>((ref) => MenuViewMode.grid);


enum MenuTypeFilter { all, food, drink, cake, bread }

final menuTypeFilterProvider =
    StateProvider<MenuTypeFilter>((ref) => MenuTypeFilter.all);
