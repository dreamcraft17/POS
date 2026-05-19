import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/sync_manager.dart';

/// Legacy hook — sync is handled by [SyncManager] started in [SplashBootstrap].
/// Call [SyncManager.instance.syncNow] if you need a manual flush.
final syncServiceProvider = Provider<void>((ref) {
  // No-op: prevents accidental second timer from old code paths.
});

Future<void> requestBackgroundSync() => SyncManager.instance.syncNow();
