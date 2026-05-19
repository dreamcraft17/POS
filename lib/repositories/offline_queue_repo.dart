import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';

class OfflineQueueRepo {
  Future<int> enqueue(String kind, Map<String, dynamic> payload) async {
    final db = await LocalDB.instance;
    return await db.insert('offline_queue', {
      'kind': kind,
      'payload': jsonEncode(payload),
      'try_count': 0,
      'last_error': null,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<List<Map<String, dynamic>>> all() async {
    final db = await LocalDB.instance;
    final rows = await db.query(
      'offline_queue',
      orderBy: 'id ASC',
      limit: 100,
    );
    return rows;
  }

  Future<void> markTried(int id, {String? error}) async {
    final db = await LocalDB.instance;
    // Naikkan try_count + set last_error
    await db.updatePlus(
      'offline_queue',
      {
        'try_count': Field.inc, // << increment 1
        'last_error': error,
      },
      where: 'id=?',
      whereArgs: [id],
      // conflictAlgorithm tidak dipakai di rawUpdate; aman diabaikan
    );
  }

  Future<void> remove(int id) async {
    final db = await LocalDB.instance;
    await db.delete('offline_queue', where: 'id=?', whereArgs: [id]);
  }
}

/// Marker untuk operasi increment kolom (mis. SET col = col + by)
class Field {
  final num by;
  const Field(this.by);

  /// alias nyaman
  static const one = Field(1);
  static const inc = Field(1);
}

/// Ekstensi Database: updatePlus() akan otomatis memakai rawUpdate
/// jika ada nilai bertipe Field (increment). Kalau tidak ada, fallback ke update biasa.
extension UpdatePlusExt on Database {
  Future<int> updatePlus(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) async {
    final hasInc = values.values.any((v) => v is Field);

    if (!hasInc) {
      // Pakai update standar dari sqflite
      return update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );
    }

    // Bangun SQL: kolom Field -> "col = col + ?"; lainnya "col = ?"
    final sets = <String>[];
    final args = <Object?>[];

    values.forEach((k, v) {
      if (v is Field) {
        sets.add('$k = $k + ?');
        args.add(v.by);
      } else {
        sets.add('$k = ?');
        args.add(v);
      }
    });

    final whereSql = where != null ? ' WHERE $where' : '';
    final sql = 'UPDATE $table SET ${sets.join(', ')}$whereSql';
    if (whereArgs != null) args.addAll(whereArgs);

    return rawUpdate(sql, args);
  }
}
