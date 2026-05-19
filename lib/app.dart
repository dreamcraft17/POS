// import 'package:ee_pos/widgets/session_gate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'pages/pos_home.dart';
import 'pages/products_page.dart';
import 'pages/stock_page.dart';
import 'pages/settings_page.dart';
import 'pages/menus_page.dart';
import 'providers/auth_providers.dart';
// NEW
import 'pages/auth_page.dart';
import '../widgets/session_gate.dart'; // sesuai file yang sudah kamu punya di kanvas
import 'pages/transactions_page.dart';
import 'providers/products_provider.dart';
import 'providers/low_stock_provider.dart';

class POSApp extends StatelessWidget {
  const POSApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: Colors.black,
      brightness: Brightness.light,
    ).copyWith(
      primary: Colors.black,
      onPrimary: Colors.white,
      secondary: Colors.black,
      onSecondary: Colors.white,
      surface: Colors.white,
      onSurface: Colors.black,
      background: Colors.white,
      onBackground: Colors.black,
      surfaceVariant: const Color(0xFFF7F7F7),
      outline: const Color(0xFFE5E5E5),
      outlineVariant: const Color(0xFFE5E5E5),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Cafe POS',
      themeMode: ThemeMode.light,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0.5,
          shadowColor: Colors.black12,
          surfaceTintColor: Colors.white,
          centerTitle: true,
        ),
        dividerTheme: const DividerThemeData(
          color: Color(0xFFE5E5E5),
          thickness: 1,
        ),
        cardTheme: CardThemeData(
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFFE5E5E5)),
          ),
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Colors.black, width: 1.2),
          ),
          labelStyle: const TextStyle(color: Colors.black),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: const BorderSide(color: Colors.black, width: 1),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: ButtonStyle(
            foregroundColor: const MaterialStatePropertyAll(Colors.black),
            padding: const MaterialStatePropertyAll(EdgeInsets.all(8)),
            visualDensity: VisualDensity.compact,
          ),
        ),
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: Colors.white,
          selectedIconTheme: IconThemeData(color: Colors.black),
          unselectedIconTheme: IconThemeData(color: Colors.black54),
          selectedLabelTextStyle:
              TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
          unselectedLabelTextStyle: TextStyle(color: Colors.black54),
          indicatorColor: Colors.black12,
        ),
        navigationDrawerTheme: const NavigationDrawerThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          indicatorColor: Colors.black12,
        ),
        listTileTheme: const ListTileThemeData(
          iconColor: Colors.black,
          textColor: Colors.black,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.black),
          bodyLarge: TextStyle(color: Colors.black),
          titleMedium: TextStyle(color: Colors.black),
          titleLarge: TextStyle(color: Colors.black),
        ),
      ),
      // GATE: kalau belum login tampil AuthPage; kalau sudah login tampil _AppShell
      home: SessionGate(
        child: const _AppShell(),
        unauthBuilder: (ctx) => const AuthPage(),
      ),
    );
  }
}

class _AppShell extends ConsumerStatefulWidget {
  const _AppShell({super.key});
  @override
  ConsumerState<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<_AppShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  int _index = 0;
  bool _showRail = false;
  bool _stockDialogOpen = false;

  // ====== Anti-spam auto-popup (POS) ======
  bool _stockDialogEverShown = false; // auto-show sekali per sesi
  DateTime? _stockDialogLastShown;
  static const Duration _stockDialogCooldown = Duration(minutes: 10);

  bool _canAutoShow() {
    if (_index != 0 || _stockDialogOpen) return false;
    if (_stockDialogEverShown) return false;
    if (_stockDialogLastShown != null &&
        DateTime.now().difference(_stockDialogLastShown!) <
            _stockDialogCooldown) {
      return false;
    }
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_canAutoShow()) _maybeShowPosStockDialog();
    });
  }

  void _maybeShowPosStockDialog() {
    if (!_canAutoShow()) return;

    final productsAsync = ref.read(productsProvider);
    if (!productsAsync.hasValue) return;
    // if (!productsAsync.hasValue) {
    //   ref.listen(productsProvider, (prev, next) {
    //     if (_index == 0 &&
    //         !_stockDialogOpen &&
    //         next.hasValue &&
    //         _canAutoShow()) {
    //       Future.microtask(_maybeShowPosStockDialog);
    //     }
    //   });
    //   return;
    // }

    final lowOut = ref.read(lowStockProvider);
    final threshold = ref.read(lowStockThresholdProvider);
    final low = lowOut.low;
    final out = lowOut.out;

    if (low.isEmpty && out.isEmpty) return;

    _stockDialogOpen = true;
    _stockDialogEverShown = true;
    _stockDialogLastShown = DateTime.now();

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final total = low.length + out.length;
        final titleText = total == 1
            ? '1 product needs attention'
            : '$total products need attention';
        return AlertDialog(
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          title: Row(
            children: [
              Image.asset('assets/icon/logo.png', height: 100, width: 100),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titleText,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (out.isNotEmpty)
                  _BadgeLine(
                    icon: Icons.warning_amber_rounded,
                    color: Colors.red,
                    text: '${out.length} product(s) OUT OF STOCK',
                  ),
                if (low.isNotEmpty)
                  _BadgeLine(
                    icon: Icons.inventory_2_outlined,
                    color: Colors.orange,
                    text: '${low.length} product(s) ≤ $threshold left',
                  ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: -6,
                  children: [
                    ...out.take(6).map(
                          (p) => Chip(
                            label: Text('${p.name} — 0'),
                            avatar: const Icon(Icons.error, size: 18),
                          ),
                        ),
                    ...low.take(6 - (out.length >= 6 ? 6 : out.length)).map(
                          (p) => Chip(
                            label: Text('${p.name} — ${p.stock}'),
                            avatar: const Icon(Icons.trending_down, size: 18),
                          ),
                        ),
                  ],
                ),
                const SizedBox(height: 6),
                if ((low.length + out.length) > 6)
                  Text(
                    '+${(low.length + out.length) - 6} more',
                    style: const TextStyle(color: Colors.black54),
                  ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                ref.invalidate(productsProvider);
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                setState(() => _index = 2);
              },
              icon: const Icon(Icons.inventory_2),
              label: const Text('View Products'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _stockDialogOpen = false);
    });
  }

  Future<void> _confirmAndLogout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 24),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.logout, size: 60, color: Colors.black),
                const SizedBox(height: 16),
                const Text(
                  'Sign Out',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Are you sure you want to end this session?',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Log Out'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (shouldLogout != true) return;

    try {
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Logged out successfully')),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Logout failed: $err')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = const [
      POSHome(),
      MenusPage(),
      ProductsPage(),
      StockPage(),
      TransactionsPage(),
      SettingsPage(),
    ];
    final titles = const ['POS', 'Menus', 'Products', 'Stock','Transactions', 'Settings'];

    final rail = NavigationRail(
      selectedIndex: _index,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          selectedIcon: Icon(Icons.point_of_sale),
          label: Text('POS'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.restaurant_menu_outlined),
          selectedIcon: Icon(Icons.restaurant_menu),
          label: Text('Menus'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: Text('Products'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.warehouse_outlined),
          selectedIcon: Icon(Icons.warehouse),
          label: Text('Stock'),
        ),
         NavigationRailDestination(
    icon: Icon(Icons.receipt_long_outlined),
    selectedIcon: Icon(Icons.receipt_long),
    label: Text('Transactions'), // NEW
  ),
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
      ],
      onDestinationSelected: (i) {
        setState(() {
          _index = i;
          final wide = MediaQuery.of(context).size.width >= 900;
          if (wide) _showRail = false;
        });
        if (i == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_canAutoShow()) _maybeShowPosStockDialog();
          });
        }
      },
    );

    final drawer = NavigationDrawer(
      selectedIndex: _index,
      onDestinationSelected: (i) {
        Navigator.pop(context);
        setState(() => _index = i);
        if (i == 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_canAutoShow()) _maybeShowPosStockDialog();
          });
        }
      },
      children: const [
        SizedBox(height: 8),
        NavigationDrawerDestination(
          icon: Icon(Icons.point_of_sale_outlined),
          selectedIcon: Icon(Icons.point_of_sale),
          label: Text('POS'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.restaurant_menu_outlined),
          selectedIcon: Icon(Icons.restaurant_menu),
          label: Text('Menus'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.inventory_2_outlined),
          selectedIcon: Icon(Icons.inventory_2),
          label: Text('Products'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.warehouse_outlined),
          selectedIcon: Icon(Icons.warehouse),
          label: Text('Stock'),
        ),
        NavigationDrawerDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 900;

        return Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
  title: _TitleWithLogo(title: titles[_index]),
  leading: _SidebarToggleButton(
    isOpen: wide ? _showRail : false,
    onPressed: () {
      if (wide) {
        setState(() => _showRail = !_showRail);
      } else {
        _scaffoldKey.currentState?.openDrawer();
      }
    },
  ),
  actions: [
    Consumer(
      builder: (context, ref, _) {
        final user = ref.watch(authControllerProvider).valueOrNull;
        final username = user?.displayName ?? 'User';
        return Row(
          children: [
            Text(
              'Hi, $username',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              tooltip: 'Logout',
              icon: const Icon(Icons.logout),
              onPressed: _confirmAndLogout,
            ),
          ],
        );
      },
    ),
  ],
),

          drawer: wide ? null : Drawer(child: drawer),
          body: Row(
            children: [
              if (wide)
                SizedBox(
                  width: _showRail ? 88 : 0,
                  child: ClipRect(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      widthFactor: _showRail ? 1 : 0,
                      child: rail,
                    ),
                  ),
                ),
              if (wide && _showRail) const VerticalDivider(width: 1),
              Expanded(
                child: IndexedStack(
                  index: _index,
                  children: pages,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BadgeLine extends StatelessWidget {
  const _BadgeLine({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TitleWithLogo extends StatelessWidget {
  const _TitleWithLogo({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(
          'assets/icon/logo.png',
          height: 100,
          width: 100,
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SidebarToggleButton extends StatelessWidget {
  const _SidebarToggleButton({
    required this.isOpen,
    required this.onPressed,
    super.key,
  });

  final bool isOpen;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isOpen ? Colors.black : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black, width: 1),
          ),
          child: Icon(
            isOpen ? Icons.close : Icons.menu,
            color: isOpen ? Colors.white : Colors.black,
          ),
        ),
      ),
    );
  }
}
