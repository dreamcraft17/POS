import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app.dart';
import '../services/sync_manager.dart';
import '../ui/splash_screen.dart';

/// Root kecil untuk nampilin splash sambil init dependency.
/// Setelah init selesai, dia ganti ke POSApp (ProviderScope).
class SplashBootstrap extends StatefulWidget {
  const SplashBootstrap({super.key});

  @override
  State<SplashBootstrap> createState() => _SplashBootstrapState();
}

class _SplashBootstrapState extends State<SplashBootstrap> {
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      await SyncManager.instance.init();
      // Opsional: kasih sedikit delay biar splash kebaca
      // await Future.delayed(const Duration(milliseconds: 500));
    } catch (_) {
      // TODO: tampilkan error screen kalau mau
    } finally {
      if (mounted) setState(() => _ready = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return const ProviderScope(child: POSApp());
    }
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: SplashScreen(),
    );
  }
}
