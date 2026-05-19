import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class OpenBillsRepo {
  static const _openKey = 'open.bills';
  static const _cancelledKey = 'cancelled.bills';
  static const _doneKey = 'done.bills';

  // ========== OPEN ==========
  Future<List<Map<String, dynamic>>> listDrafts() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_openKey) ?? [];
    return raw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
  }

  Future<void> addDraft(Map<String, dynamic> draft) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_openKey) ?? [];
    raw.add(jsonEncode(draft));
    await sp.setStringList(_openKey, raw);
  }

  Future<void> removeDraft(dynamic id) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_openKey) ?? [];
    raw.removeWhere((e) {
      final m = Map<String, dynamic>.from(jsonDecode(e));
      return m['id']?.toString() == id.toString();
    });
    await sp.setStringList(_openKey, raw);
  }

  Future<void> updateDraft(Map<String, dynamic> draft) async {
  // Replace by id
  final sp = await SharedPreferences.getInstance();
  final raw = sp.getStringList(_openKey) ?? [];
  final id = (draft['id'] ?? '').toString();

  final replaced = <String>[];
  bool found = false;
  for (final e in raw) {
    final m = Map<String, dynamic>.from(jsonDecode(e));
    if ((m['id'] ?? '').toString() == id) {
      replaced.add(jsonEncode(draft));
      found = true;
    } else {
      replaced.add(e);
    }
  }
  if (!found) replaced.add(jsonEncode(draft)); // fallback: upsert
  await sp.setStringList(_openKey, replaced);
}

Future<void> upsertDraft(Map<String, dynamic> draft) => updateDraft(draft);


  // ========== CANCELLED ==========
  Future<List<Map<String, dynamic>>> listCancelled() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_cancelledKey) ?? [];
    return raw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
  }

  Future<void> addCancelled(Map<String, dynamic> bill) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_cancelledKey) ?? [];
    raw.add(jsonEncode(bill));
    await sp.setStringList(_cancelledKey, raw);
  }

  //==============done===============
  Future<List<Map<String, dynamic>>> listDone() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_doneKey) ?? [];
    return raw.map((e) => Map<String, dynamic>.from(jsonDecode(e))).toList();
  }


  Future<void> addDone(Map<String, dynamic> bill) async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getStringList(_doneKey) ?? [];
    raw.add(jsonEncode(bill));
    await sp.setStringList(_doneKey, raw);
  }
}
