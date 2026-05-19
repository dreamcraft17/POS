import 'package:shared_preferences/shared_preferences.dart';

const _QUEUE_KEY_PREFIX = 'kitchen.queue.seq';

String _todayKey({String prefix = _QUEUE_KEY_PREFIX}) {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$prefix.$y$m$d';
}

/// Ambil nomor antrian lokal berikutnya (format "YYYYMMDD-XXX")
Future<String> nextLocalQueueNo({String prefix = _QUEUE_KEY_PREFIX}) async {
  final sp = await SharedPreferences.getInstance();
  final key = _todayKey(prefix: prefix);
  final last = sp.getInt(key) ?? 0;
  final next = last + 1;
  await sp.setInt(key, next);
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$y$m$d-${next.toString().padLeft(3, '0')}';
}

/// Reset hari ini → next akan kembali ke 1 (…-001)
Future<void> resetTodayQueue({String prefix = _QUEUE_KEY_PREFIX}) async {
  final sp = await SharedPreferences.getInstance();
  await sp.remove(_todayKey(prefix: prefix));
}

/// Set “nomor berikutnya” menjadi angka tertentu.
/// Misal setNextQueueTo(50) → berikutnya akan jadi …-050.
Future<void> setNextQueueTo(int nextNumber, {String prefix = _QUEUE_KEY_PREFIX}) async {
  if (nextNumber < 1) nextNumber = 1;
  final sp = await SharedPreferences.getInstance();
  final key = _todayKey(prefix: prefix);
  // Disimpan sebagai "last", jadi nextLocalQueueNo() mengeluarkan nextNumber
  await sp.setInt(key, nextNumber - 1);
}

/// Opsional: hapus semua histori counter semua hari
Future<int> resetAllQueues({String prefix = _QUEUE_KEY_PREFIX}) async {
  final sp = await SharedPreferences.getInstance();
  int removed = 0;
  for (final k in sp.getKeys()) {
    if (k.startsWith(prefix)) {
      await sp.remove(k);
      removed++;
    }
  }
  return removed;
}
