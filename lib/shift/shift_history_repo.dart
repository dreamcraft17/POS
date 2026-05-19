import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'shift_service.dart';

class ShiftHistoryEntry {
  final DateTime startAt;
  final DateTime endAt;
  final int openingCashCents;
  final ShiftSummary summary;

  ShiftHistoryEntry({
    required this.startAt,
    required this.endAt,
    required this.openingCashCents,
    required this.summary,
  });

  Map<String, dynamic> toJson() => {
        'startAt': startAt.toIso8601String(),
        'endAt': endAt.toIso8601String(),
        'openingCashCents': openingCashCents,
        'summary': {
          'ordersCount': summary.ordersCount,
          'soldItems': summary.soldItems,
          'grossCents': summary.grossCents,
          'discountCents': summary.discountCents,
          'taxCents': summary.taxCents,
          'netCents': summary.netCents,
          'byPayment': summary.byPayment,
          'items': summary.items
              .map((e) => {
                    'name': e.name,
                    'qty': e.qty,
                    'totalCents': e.totalCents,
                  })
              .toList(),
          'startAt': summary.startAt.toIso8601String(),
          'endAt': summary.endAt.toIso8601String(),
        },
      };

  static ShiftHistoryEntry fromJson(Map<String, dynamic> m) {
    final sum = m['summary'] as Map<String, dynamic>;
    final items = (sum['items'] as List? ?? const [])
        .map((x) => SoldItem(
              name: (x['name'] ?? '').toString(),
              qty: (x['qty'] as num?)?.toInt() ?? 0,
              totalCents: (x['totalCents'] as num?)?.toInt() ?? 0,
            ))
        .toList();

    return ShiftHistoryEntry(
      startAt: DateTime.parse(m['startAt'] as String),
      endAt: DateTime.parse(m['endAt'] as String),
      openingCashCents: (m['openingCashCents'] as num?)?.toInt() ?? 0,
      summary: ShiftSummary(
        startAt: DateTime.parse((sum['startAt'] ?? m['startAt']) as String),
        endAt: DateTime.parse((sum['endAt'] ?? m['endAt']) as String),
        ordersCount: (sum['ordersCount'] as num?)?.toInt() ?? 0,
        soldItems: (sum['soldItems'] as num?)?.toInt() ?? 0,
        grossCents: (sum['grossCents'] as num?)?.toInt() ?? 0,
        discountCents: (sum['discountCents'] as num?)?.toInt() ?? 0,
        taxCents: (sum['taxCents'] as num?)?.toInt() ?? 0,
        netCents: (sum['netCents'] as num?)?.toInt() ?? 0,
        byPayment: Map<String, int>.from(
            (sum['byPayment'] as Map? ?? const {}).map(
          (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
        )),
        items: items,
      ),
    );
  }
}

class ShiftHistoryRepo {
  static const _kHistory = 'shift.history.v1';

  Future<List<ShiftHistoryEntry>> list() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kHistory) ?? const [];
    final entries = <ShiftHistoryEntry>[];
    for (final s in raw) {
      try {
        entries.add(ShiftHistoryEntry.fromJson(
            Map<String, dynamic>.from(jsonDecode(s))));
      } catch (_) {}
    }
    entries.sort((a, b) => b.endAt.compareTo(a.endAt));
    return entries;
  }

  Future<void> add(ShiftHistoryEntry e) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_kHistory) ?? <String>[];
    raw.add(jsonEncode(e.toJson()));
    await sp.setStringList(_kHistory, raw);
  }

  Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_kHistory);
  }
}
