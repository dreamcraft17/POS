import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import '../offline/outbox_repo.dart';
import '../services/api_service.dart';
import '../repositories/offline_queue_repo.dart';

/// Single background sync runner for the app.
///
/// Drains:
/// - `offline_queue` (simple payloads, e.g. order.create)
/// - `outbox` (generic POST with idempotency headers)
class SyncManager {
  static final SyncManager instance = SyncManager._();
  SyncManager._();

  final _api = ApiService.shared();
  final _queue = OfflineQueueRepo();
  final _outbox = OutboxRepo();
  StreamSubscription<List<ConnectivityResult>>? _sub;
  Timer? _timer;
  Timer? _connectivityDebounce;
  bool _running = false;
  bool _syncing = false;
  DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);

  static const Duration _syncInterval = Duration(seconds: 30);
  static const Duration _minSyncGap = Duration(seconds: 5);
  static const Duration _connectivityDebounceDelay = Duration(seconds: 2);

  Future<void> init() async {
    if (_running) return;
    _running = true;

    _sub = Connectivity().onConnectivityChanged.listen((_) {
      _connectivityDebounce?.cancel();
      _connectivityDebounce = Timer(_connectivityDebounceDelay, () {
        unawaited(_kick());
      });
    });
    _timer = Timer.periodic(_syncInterval, (_) {
      unawaited(_kick());
    });

    unawaited(_kick());
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _timer?.cancel();
    _connectivityDebounce?.cancel();
    _running = false;
  }

  /// Manual trigger (e.g. after payment queued offline).
  Future<void> syncNow() => _kick();

  Future<void> _kick() async {
    if (!_running || _syncing) return;

    final now = DateTime.now();
    if (now.difference(_lastSyncAt) < _minSyncGap) return;

    _syncing = true;
    try {
      final conn = await Connectivity().checkConnectivity();
      final hasNet = conn.any((c) => c != ConnectivityResult.none);
      if (!hasNet) return;

      await _syncOfflineQueue();
      await _syncOutbox();
    } finally {
      _lastSyncAt = DateTime.now();
      _syncing = false;
    }
  }

  Future<void> _syncOfflineQueue() async {
    final items = await _queue.all();
    for (final row in items) {
      final id = row['id'] as int;
      final kind = row['kind'] as String;
      final payloadStr = row['payload'] as String;
      final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

      try {
        if (kind == 'order.create') {
          await _api.createOrder(payload);
          await _queue.remove(id);
        } else {
          await _queue.remove(id);
        }
      } catch (e) {
        await _queue.markTried(id, error: e.toString());
        if (_isTransient(e)) break;
      }
    }
  }

  Future<void> _syncOutbox() async {
    var batch = await _outbox.all(limit: 50);
    while (batch.isNotEmpty) {
      for (final it in batch) {
        try {
          await _api.rawRequest(
            method: it.method,
            path: it.endpoint,
            body: it.body,
            extraHeaders: {'Idempotency-Key': it.idempotencyKey},
            attachAudit: false,
          );
          await _outbox.remove(it.id!);
        } catch (e) {
          await _outbox.markTried(it.id!, error: e.toString());
          if (_isTransient(e)) return;
        }
      }
      batch = await _outbox.all(limit: 50);
    }
  }

  bool _isTransient(Object e) {
    if (e is DioException) {
      final code = e.response?.statusCode ?? 0;
      return code == 0 || code >= 500;
    }
    return true;
  }
}
