import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';

class OutboxItem {
  final int? id;
  final String op;
  final String endpoint;
  final String method;
  final Map<String, dynamic> body;
  final String idempotencyKey;
  final int tryCount;
  final int createdAt;
  final String? lastError;

  OutboxItem({
    this.id,
    required this.op,
    required this.endpoint,
    required this.method,
    required this.body,
    required this.idempotencyKey,
    required this.tryCount,
    required this.createdAt,
    this.lastError,
  });

  Map<String, dynamic> toRow() => {
        if (id != null) 'id': id,
        'op': op,
        'endpoint': endpoint,
        'method': method,
        'body': jsonEncode(body),
        'idempotency_key': idempotencyKey,
        'try_count': tryCount,
        'created_at': createdAt,
        'last_error': lastError,
      };

  static OutboxItem fromRow(Map<String, Object?> r) => OutboxItem(
        id: r['id'] as int?,
        op: r['op'] as String,
        endpoint: r['endpoint'] as String,
        method: r['method'] as String,
        body: jsonDecode(r['body'] as String) as Map<String, dynamic>,
        idempotencyKey: r['idempotency_key'] as String,
        tryCount: (r['try_count'] as int?) ?? 0,
        createdAt: (r['created_at'] as int?) ?? 0,
        lastError: r['last_error'] as String?,
      );
}

class OutboxRepo {
  Future<int> enqueue({
    required String op,
    required String endpoint,
    required String method,
    required Map<String, dynamic> body,
    required String idempotencyKey,
  }) async {
    final db = await LocalDB.instance;
    return db.insert('outbox', {
      'op': op,
      'endpoint': endpoint,
      'method': method,
      'body': jsonEncode(body),
      'idempotency_key': idempotencyKey,
      'try_count': 0,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'last_error': null,
    });
  }

  Future<List<OutboxItem>> all({int limit = 50}) async {
    final db = await LocalDB.instance;
    final rows = await db.query(
      'outbox',
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(OutboxItem.fromRow).toList();
  }

  Future<void> markTried(int id, {String? error}) async {
    final db = await LocalDB.instance;
    final current = Sqflite.firstIntValue(
          await db.rawQuery('SELECT try_count FROM outbox WHERE id=?', [id]),
        ) ??
        0;
    await db.update(
      'outbox',
      {
        'try_count': current + 1,
        'last_error': error,
      },
      where: 'id=?',
      whereArgs: [id],
    );
  }

  Future<void> remove(int id) async {
    final db = await LocalDB.instance;
    await db.delete('outbox', where: 'id=?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    final db = await LocalDB.instance;
    await db.delete('outbox');
  }
}
