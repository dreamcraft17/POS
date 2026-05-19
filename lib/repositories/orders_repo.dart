// lib/repositories/orders_repo.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import 'offline_queue_repo.dart';
import '../repositories/auth_repo.dart';
import '../models/auth_user.dart';

// ====== KODE LAMA (TETAP ADA) ======
class OrdersRepo {
  // final ApiService _api = ApiService();
   final ApiService _api = ApiService.shared();
  final OfflineQueueRepo _queue = OfflineQueueRepo();

  /// Coba kirim ke server dulu. Kalau gagal karena jaringan/server,
  /// simpan ke offline_queue sebagai "order.create"
  Future<Map<String, dynamic>> createOrderSmart(Map<String, dynamic> order) async {
    try {
      final res = await _api.createOrder(order);
      return {'ok': true, 'remote': true, ...res};
    } on DioException catch (e) {
      // Transient?
      final code = e.response?.statusCode ?? 0;
      final transient = code == 0 ||
          code == 503 ||
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout;

      if (transient) {
        final id = await _queue.enqueue('order.create', order);
        return {'ok': true, 'remote': false, 'queued_id': id};
      }
      rethrow;
    } catch (_) {
      // Error lain — tetap antrikan agar tidak hilang
      final id = await _queue.enqueue('order.create', order);
      return {'ok': true, 'remote': false, 'queued_id': id};
    }
  }
}

// ====== TAMBAHAN BARU (Integrasi User) ======


extension OrdersRepoWithUser on OrdersRepo {
  /// Versi smart yang otomatis menyisipkan info user (jika ada) ke payload.
  /// Tidak memaksa backend — by default menambah field `created_by`.
  Future<Map<String, dynamic>> createOrderSmartWithUser(
    Map<String, dynamic> order, {
    AuthRepo? authRepo,
    bool includeUsernameField = true,
    bool includeUserIdField = false,
  }) async {
    final repo = authRepo ?? AuthRepo();
    AuthUserModel? u;
    try {
      // offline cache cukup, ga perlu hit server di titik ini
      u = await repo.me(refreshFromServer: false);
    } catch (_) {}

    final augmented = Map<String, dynamic>.from(order);
    if (u != null) {
      if (includeUsernameField) augmented['created_by'] = u.username;
      if (includeUserIdField) augmented['created_by_id'] = u.id;
    }
    return createOrderSmart(augmented);
  }
}


// ====== Open Bills (draft orders) ======
extension OrdersRepoOpenBills on OrdersRepo {
  Future<List<Map<String, dynamic>>> listDrafts() async {
    // Ambil ID kasir yang login
    int createdById = 0;
    try {
      final u = await AuthRepo().me(refreshFromServer: false);
      createdById = (u?.id ?? 0); // <- int
    } catch (_) {
      createdById = 0;
    }

    // Tarik 30 hari terakhir lalu filter status draft
    final since = DateTime.now().subtract(const Duration(days: 30));
    final rows = await _api.orders(
      createdBy: createdById,                    // << int, OK
      sinceIso: since.toIso8601String(),
    );

    return rows
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) => (m['status'] ?? '').toString().toLowerCase() == 'draft')
        .toList();
  }

  Future<void> deleteDraft(String id) async {
    // Belum ada endpoint delete di ApiService; biarkan no-op dulu.
    return;
  }
}
