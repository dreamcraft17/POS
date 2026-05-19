// lib/providers/order_type_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';

/// Model order type dari backend
class OrderType {
  final String code;
  final String name;
  final bool enabled;
  final int sort;

  OrderType({
    required this.code,
    required this.name,
    required this.enabled,
    required this.sort,
  });

  factory OrderType.fromMap(Map<String, dynamic> m) => OrderType(
        code: (m['code'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        enabled: (m['enabled'] == 1 || m['enabled'] == true),
        sort: (m['sort'] is int)
            ? (m['sort'] as int)
            : int.tryParse('${m['sort'] ?? 0}') ?? 0,
      );
}

/// Ambil daftar order type yang enabled, sudah di-sort ASC by `sort`
final orderTypesProvider = FutureProvider<List<OrderType>>((ref) async {
  final api = ApiService.shared();
  final raw = await api.orderTypes(); // GET /api/order-types
  final list = raw
      .map<OrderType>(OrderType.fromMap)
      .where((e) => e.enabled)
      .toList()
    ..sort((a, b) => a.sort.compareTo(b.sort));
  return list;
});

/// StateNotifier untuk menyimpan kode order type terpilih (persist ke SharedPreferences)
class SelectedOrderTypeNotifier extends StateNotifier<String?> {
  SelectedOrderTypeNotifier() : super(null) {
    _load();
  }

  static const _key = 'selected_order_type_code';

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    state = p.getString(_key);
  }

  Future<void> set(String? code) async {
    state = code;
    final p = await SharedPreferences.getInstance();
    if (code == null || code.isEmpty) {
      await p.remove(_key);
    } else {
      await p.setString(_key, code);
    }
  }
}

/// Provider utama untuk kode order type terpilih (nullable).
/// Pakai `.notifier` untuk set nilai, pakai `ref.watch(...)` untuk baca nilai.
final selectedOrderTypeCodeProvider =
    StateNotifierProvider<SelectedOrderTypeNotifier, String?>(
  (ref) => SelectedOrderTypeNotifier(),
);

/// Helper: kembalikan NAMA dari code yang dipilih.
/// Jika belum ada pilihan atau code tidak ditemukan di list, return null.
final selectedOrderTypeNameProvider = Provider<String?>((ref) {
  final code = ref.watch(selectedOrderTypeCodeProvider);
  final list = ref.watch(orderTypesProvider).maybeWhen(
        data: (v) => v,
        orElse: () => const <OrderType>[],
      );

  final found = list.firstWhere(
    (e) => e.code == (code ?? ''),
    orElse: () => OrderType(code: '', name: '', enabled: false, sort: 0),
  );

  return found.code.isEmpty ? null : found.name;
});

/// (Opsional) Helper untuk UI: nilai code yang “efektif”
/// - Kalau user sudah memilih -> pakai itu
/// - Kalau belum memilih tapi daftar sudah ada -> pakai item pertama
/// - Kalau daftar belum ada -> null (biar Dropdown bisa nunggu data)
final effectiveOrderTypeCodeProvider = Provider<String?>((ref) {
  final selected = ref.watch(selectedOrderTypeCodeProvider);
  final asyncList = ref.watch(orderTypesProvider);
  return asyncList.maybeWhen(
    data: (list) {
      if (selected != null && selected.isNotEmpty) return selected;
      if (list.isNotEmpty) return list.first.code;
      return null;
    },
    orElse: () => selected,
  );
});

/// (Opsional) Helper untuk UI: nama “efektif” (ada default Dine-in kalau list kosong)
final effectiveOrderTypeNameProvider = Provider<String>((ref) {
  final name = ref.watch(selectedOrderTypeNameProvider);
  if (name != null && name.isNotEmpty) return name;

  // fallback aman saat list belum siap
  return 'Dine-in';
});
