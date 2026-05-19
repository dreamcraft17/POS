// lib/repositories/auth_repo.dart
import 'package:sqflite/sqflite.dart';
import '../db/local_db.dart';
import '../services/api_service.dart';
import '../models/auth_user.dart';

class AuthRepo {
  // final ApiService _api;
  // AuthRepo({ApiService? api}) : _api = api ?? ApiService();
  final ApiService _api;
  AuthRepo({ApiService? api}) : _api = api ?? ApiService.shared();

  Future<void> _ensureTable() async {
    final db = await LocalDB.instance;
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auth_user (
        id INTEGER PRIMARY KEY,
        username TEXT NOT NULL,
        display_name TEXT NULL
      )
    ''');
  }

  Future<AuthUserModel?> me({bool refreshFromServer = true}) async {
    await _ensureTable();
    if (refreshFromServer) {
      final u = await _api.me(); // pastikan ApiService punya me()
      if (u != null) {
        final db = await LocalDB.instance;
        await db.insert(
          'auth_user',
          {'id': u.id, 'username': u.username, 'display_name': u.displayName},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        return AuthUserModel(
            id: u.id, username: u.username, displayName: u.displayName);
      }
    }
    // fallback cache
    final db = await LocalDB.instance;
    final rows = await db.query('auth_user', limit: 1);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return AuthUserModel(
      id: (r['id'] as num).toInt(),
      username: r['username'] as String,
      displayName: r['display_name'] as String?,
    );
  }

  Future<AuthUserModel> login(String username, String password) async {
    await _ensureTable();
    final u = await _api.login(username: username, password: password);
    final db = await LocalDB.instance;
    await db.insert(
      'auth_user',
      {'id': u.id, 'username': u.username, 'display_name': u.displayName},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return AuthUserModel(
        id: u.id, username: u.username, displayName: u.displayName);
  }

  Future<AuthUserModel> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    await _ensureTable();
    final u = await _api.register(
      username: username,
      password: password,
      displayName: displayName,
    );
    final db = await LocalDB.instance;
    await db.insert(
      'auth_user',
      {'id': u.id, 'username': u.username, 'display_name': u.displayName},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return AuthUserModel(
        id: u.id, username: u.username, displayName: u.displayName);
  }

  Future<void> logout() async {
    await _api.logout();
    final db = await LocalDB.instance;
    await db.delete('auth_user');
  }
}
