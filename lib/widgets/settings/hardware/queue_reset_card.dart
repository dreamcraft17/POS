import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ====== STORAGE HELPER (SharedPreferences) ======

const _QUEUE_KEY_PREFIX_DEFAULT = 'kitchen.queue.seq';

String _todayKey({required String prefix}) {
  final now = DateTime.now();
  final y = now.year.toString().padLeft(4, '0');
  final m = now.month.toString().padLeft(2, '0');
  final d = now.day.toString().padLeft(2, '0');
  return '$prefix.$y$m$d';
}

/// Ambil nomor antrian lokal berikutnya (format "YYYYMMDD-XXX") dan auto-increment
Future<String> nextLocalQueueNo({String prefix = _QUEUE_KEY_PREFIX_DEFAULT}) async {
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

/// Reset counter hari ini (hapus key hari ini) → next kembali ke 001
Future<void> resetTodayQueue({String prefix = _QUEUE_KEY_PREFIX_DEFAULT}) async {
  final sp = await SharedPreferences.getInstance();
  await sp.remove(_todayKey(prefix: prefix));
}

/// Set “nomor berikutnya” jadi angka tertentu (>=1)
/// Contoh: setNextQueueTo(50) → panggilan nextLocalQueueNo berikutnya hasilnya …-050
Future<void> setNextQueueTo(int nextNumber, {String prefix = _QUEUE_KEY_PREFIX_DEFAULT}) async {
  if (nextNumber < 1) nextNumber = 1;
  final sp = await SharedPreferences.getInstance();
  final key = _todayKey(prefix: prefix);
  // simpan "last" = next-1 supaya call berikutnya mengeluarkan nextNumber
  await sp.setInt(key, nextNumber - 1);
}

/// Hapus semua histori counter lintas hari (opsional)
Future<int> resetAllQueues({String prefix = _QUEUE_KEY_PREFIX_DEFAULT}) async {
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

/// Lihat angka “next” saat ini (tanpa increment)
Future<int> currentNextNumber({String prefix = _QUEUE_KEY_PREFIX_DEFAULT}) async {
  final sp = await SharedPreferences.getInstance();
  final key = _todayKey(prefix: prefix);
  final last = sp.getInt(key) ?? 0;
  return last + 1;
}

/// ====== UI CARD: Reset Hari Ini & Set Next Number ======

class QueueResetCard extends StatefulWidget {
  const QueueResetCard({
    super.key,
    this.prefix = _QUEUE_KEY_PREFIX_DEFAULT,
    this.title = 'Queue Number',
  });

  /// Ganti prefix kalau mau punya line berbeda (mis. 'kitchen.queue.seq.bar')
  final String prefix;

  /// Judul kartu
  final String title;

  @override
  State<QueueResetCard> createState() => _QueueResetCardState();
}

class _QueueResetCardState extends State<QueueResetCard> {
  bool _busy = false;
  int? _peekNext;

  @override
  void initState() {
    super.initState();
    _refreshPeek();
  }

  Future<void> _refreshPeek() async {
    final n = await currentNextNumber(prefix: widget.prefix);
    if (mounted) setState(() => _peekNext = n);
  }

  Future<void> _doResetToday() async {
    setState(() => _busy = true);
    try {
      await resetTodayQueue(prefix: widget.prefix);
      await _refreshPeek();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Queue hari ini direset ke 001')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal reset: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doSetNext() async {
    final ctrl = TextEditingController(text: '1');
    final formKey = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Set Next Number'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nomor berikutnya (>=1)',
              border: OutlineInputBorder(),
            ),
            validator: (s) {
              final v = int.tryParse((s ?? '').trim());
              if (v == null || v < 1) return 'Minimal 1';
              if (v > 999999) return 'Kegedean (maks 999999)';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: const Text('Batal')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.pop(_, true);
              }
            },
            child: const Text('Set'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _busy = true);
    try {
      final v = int.parse(ctrl.text.trim());
      await setNextQueueTo(v, prefix: widget.prefix);
      await _refreshPeek();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Next number diset ke ${v.toString().padLeft(3, '0')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal set next number: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextLabel = (_peekNext == null) ? '…' : _peekNext!.toString().padLeft(3, '0');

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.title, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Atur nomor antrian dapur (lokal per-hari). Reset ke 001 atau set “nomor berikutnya”.',
              style: TextStyle(fontSize: 12, color: Colors.black.withValues(alpha: .7)),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Chip(label: Text('Next: $nextLabel')),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _busy ? null : _refreshPeek,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _doResetToday,
                    icon: _busy
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.restore),
                    label: Text(_busy ? 'Working…' : 'Reset Hari Ini ke 001'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _doSetNext,
                    icon: const Icon(Icons.edit),
                    label: const Text('Set Next Number…'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
  