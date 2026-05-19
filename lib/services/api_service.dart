import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
// (opsional) kalau mau deteksi platform: import 'package:flutter/foundation.dart' show kIsWeb;

import '../config.dart';
import '../offline/outbox_repo.dart';

class AuthUser {
  final int id;
  final String username;
  final String? displayName;
  const AuthUser({required this.id, required this.username, this.displayName});

  factory AuthUser.fromJson(Map<String, dynamic> m) => AuthUser(
        id: ApiService._asInt(m['id']),
        username: '${m['username']}',
        displayName: m['display_name']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'display_name': displayName,
      };
}

class ApiService {
  // ========= SHARED SINGLETON (opsional, biar cookie gak hilang) =========
  static CookieJar? _globalJar;
  static Dio? _globalDio;
  static ApiService? _sharedInstance;

  /// Pakai ini kalau mau **semua tempat** share Cookie/Dio yang sama.
  factory ApiService.shared() {
    _globalJar ??= CookieJar();
    _globalDio ??= Dio(
      BaseOptions(
        baseUrl: apiBase,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {'Accept': 'application/json'},
        validateStatus: (s) => s != null && s < 500,
        extra: {'withCredentials': true},
      ),
    )..interceptors.addAll([
        CookieManager(_globalJar!),
        InterceptorsWrapper(
          onRequest: (options, handler) {
            options.extra['withCredentials'] = true;
            handler.next(options);
          },
        ),
      ]);

    return _sharedInstance ??= ApiService._internal(
      dio: _globalDio!,
      cookies: _globalJar!,
      isShared: true,
    );
  }

  // ========= Instance biasa (kompatibel dengan kodenmu yg lama) =========
  final Dio _dio;
  final CookieJar _cookies;
  final bool _isShared;

  ApiService({CookieJar? cookieJar})
      : _cookies = cookieJar ?? CookieJar(),
        _dio = Dio(
          BaseOptions(
            baseUrl: apiBase,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {'Accept': 'application/json'},
            validateStatus: (s) => s != null && s < 500,
            // ⬇️ penting untuk Flutter Web (fetch/XHR with credentials)
            extra: {'withCredentials': true},
          ),
        ),
        _isShared = false {
    // simpan/ambil cookie 'uid' dari server
    _dio.interceptors.add(CookieManager(_cookies));

    // pastikan SEMUA request (GET/POST/…) membawa credentials di Web
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          options.extra['withCredentials'] = true;
          handler.next(options);
        },
      ),
    );
  }

  ApiService._internal({
    required Dio dio,
    required CookieJar cookies,
    required bool isShared,
  })  : _dio = dio,
        _cookies = cookies,
        _isShared = isShared;

  // ========= Helpers: audit (user) =========
  Future<Map<String, dynamic>?> _currentUserMap() async {
    try {
      final u = await me(); // method me() sendiri
      if (u == null) return null;
      return {
        'created_by_id': u.id,
        'created_by': u.username,
      };
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _withAudit(
      Map<String, dynamic> body, Map<String, dynamic>? audit) {
    if (audit == null) return body;
    // jangan override kalau sudah diisi dari luar
    return {
      ...body,
      if (!body.containsKey('created_by_id'))
        'created_by_id': audit['created_by_id'],
      if (!body.containsKey('created_by')) 'created_by': audit['created_by'],
    };
  }

  // ========= Helpers: parser =========
  static int _asInt(dynamic v, [int def = 0]) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? def;
    return def;
  }

  List<Map<String, dynamic>> _asListOfMap(dynamic data) {
    if (data is List) {
      return data
          .map<Map<String, dynamic>>((e) {
            if (e is Map<String, dynamic>) return e;
            if (e is Map) return Map<String, dynamic>.from(e);
            return <String, dynamic>{};
          })
          .where((e) => e.isNotEmpty)
          .toList();
    }
    if (data is Map) {
      final d = data as Map;
      if (d['data'] is List) return _asListOfMap(d['data']);
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return _asListOfMap(decoded);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
    return const <Map<String, dynamic>>[];
  }

  List<dynamic> _asList(dynamic data) {
    if (data is List) return data;
    if (data is Map && data['data'] is List) return data['data'] as List;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return _asList(decoded);
      } catch (_) {
        return const [];
      }
    }
    return const [];
  }

  bool _is2xx(Response r) =>
      (r.statusCode ?? 0) >= 200 && (r.statusCode ?? 0) < 300;

  List<Map<String, dynamic>> _asListOfMapFlexible(dynamic data) {
    final direct = _asListOfMap(data);
    if (direct.isNotEmpty) return direct;
    if (data is Map) {
      final m = data.cast<String, dynamic>();
      final candidates = [
        m['data'],
        (m['data'] is Map) ? (m['data'] as Map)['items'] : null,
        (m['data'] is Map) ? (m['data'] as Map)['rows'] : null,
        m['items'],
        m['rows'],
        m['result'],
        m['list'],
      ].where((e) => e != null).toList();
      for (final c in candidates) {
        final v = _asListOfMap(c);
        if (v.isNotEmpty) return v;
      }
    }
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        return _asListOfMapFlexible(decoded);
      } catch (_) {
        return const <Map<String, dynamic>>[];
      }
    }
    return const <Map<String, dynamic>>[];
  }

  // ========= Health =========
  Future<Map<String, dynamic>> health() async {
    final r = await _dio.get('/api/health');
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return Map<String, dynamic>.from(data);
    return {'ok': r.statusCode == 200};
  }

  // ========= AUTH =========
  Future<AuthUser> register({
    required String username,
    required String password,
    String? displayName,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'password': password, // backend expects plain text (demo)
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
    };
    final r = await _dio.post('/api/auth/register', data: body);
    if (!_is2xx(r)) {
      throw Exception('Register failed: ${r.statusCode} ${r.data}');
    }
    final meData = await me();
    if (meData == null) {
      final id = _asInt((r.data is Map) ? (r.data['id']) : null, 0);
      return AuthUser(id: id, username: username, displayName: displayName);
    }
    return meData;
  }

  Future<AuthUser> login({
    required String username,
    required String password,
  }) async {
    final r = await _dio.post('/api/auth/login', data: {
      'username': username,
      'password': password,
    });

    // 401 dari backend artinya kredensial salah; jangan bikin side effect selain lempar error yang bisa ditangkap UI
    if (r.statusCode == 401) {
      // backend memang respond JSON { ok:false, message:'invalid username/password' } (lihat server)
      final msg = (r.data is Map && (r.data['message'] is String))
          ? r.data['message'] as String
          : 'invalid username/password';
      throw Exception(msg);
    }

    if (!_is2xx(r)) {
      throw Exception('Login failed: ${r.statusCode} ${r.data}');
    }

    final data = (r.data is Map)
        ? Map<String, dynamic>.from(r.data as Map)
        : <String, dynamic>{};
    if (data['user'] is Map) {
      return AuthUser.fromJson(Map<String, dynamic>.from(data['user']));
    }
    return AuthUser(
      id: _asInt(data['id']),
      username: '${data['username']}',
      displayName: data['display_name']?.toString(),
    );
  }

  Future<void> logout() async {
    final r = await _dio.post('/api/auth/logout');
    if (!_is2xx(r)) {
      throw Exception('Logout failed: ${r.statusCode} ${r.data}');
    }
    await _cookies.deleteAll();
  }

  Future<AuthUser?> me() async {
    try {
      final r = await _dio.get('/api/auth/me');
      if (!_is2xx(r)) return null;
      final data =
          (r.data is Map) ? Map<String, dynamic>.from(r.data as Map) : {};
      final u = data['user'];
      if (u is Map) return AuthUser.fromJson(Map<String, dynamic>.from(u));
      return null;
    } catch (_) {
      return null;
    }
  }

  // ========= Raw request + retry =========
  Future<Response<dynamic>> rawRequest({
    required String method,
    required String path,
    Map<String, dynamic>? body,
    Map<String, String>? extraHeaders,
    bool attachAudit = false, // NEW: bisa auto-inject audit di sini juga
  }) async {
    Map<String, dynamic>? payload = body;
    if (attachAudit && body != null) {
      final audit = await _currentUserMap();
      payload = _withAudit(body, audit);
    }

    final opts = Options(
      method: method,
      headers: {if (extraHeaders != null) ...extraHeaders},
      // ⬇️ jaga-jaga kalau adapter web butuh flag ini per request
      extra: {'withCredentials': true},
    );
    final r = await _dio.request(path, data: payload, options: opts);
    if (_is2xx(r)) return r;
    throw DioException(
      requestOptions: r.requestOptions,
      response: r,
      message: 'Request failed (${r.statusCode})',
    );
  }

  Future<T> retry503<T>(
    Future<T> Function() run, {
    int maxAttempts = 3,
    Duration firstDelay = const Duration(milliseconds: 350),
  }) async {
    DioException? lastErr;
    var delay = firstDelay;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await run();
      } on DioException catch (e) {
        final code = e.response?.statusCode ?? 0;
        final transient = code == 503 ||
            e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout ||
            e.type == DioExceptionType.sendTimeout;
        if (!transient || attempt == maxAttempts) {
          lastErr = e;
          break;
        }
        await Future.delayed(delay);
        delay *= 2;
      }
    }
    throw lastErr ??
        DioException(
            requestOptions: RequestOptions(),
            message: 'Unknown error on retry503');
  }

  // ===== POST with local outbox fallback (offline/503) =====
  Future<Map<String, dynamic>> postWithQueue({
    required String op, // e.g. 'orders.create'
    required String endpoint, // e.g. '/api/orders'
    required Map<String, dynamic> body,
    required OutboxRepo outbox,
    int eagerRetries = 2,
    bool attachAudit = true, // NEW: default tempel audit
  }) async {
    final idempKey = _makeIdempotencyKey(op);

    // ⬇️ NEW: selalu augment audit, termasuk saat di-enqueue
    final audit = attachAudit ? await _currentUserMap() : null;
    final payload = attachAudit ? _withAudit(body, audit) : body;

    try {
      final res = await retry503(() async {
        final r = await rawRequest(
          method: 'POST',
          path: endpoint,
          body: payload,
          extraHeaders: {'Idempotency-Key': idempKey},
          attachAudit: false, // sudah ditempel di atas
        );
        return r;
      }, maxAttempts: max(1, eagerRetries));
      final data = res.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
      return {'ok': true, 'data': data};
    } catch (_) {
      await outbox.enqueue(
        op: op,
        endpoint: endpoint,
        method: 'POST',
        body: payload, // <= simpan yang sudah ada created_by*
        idempotencyKey: idempKey,
      );
      return {'ok': true, 'pending_sync': true, 'idempotency_key': idempKey};
    }
  }

  String _makeIdempotencyKey(String op) {
    final rnd = DateTime.now().microsecondsSinceEpoch.toString();
    return '$op-$rnd-${_rand(100000, 999999)}';
  }

  int _rand(int min, int max) =>
      min + (DateTime.now().microsecondsSinceEpoch % (max - min + 1));

  // ===== Catalog =====
  Future<List<dynamic>> products() async {
    final r = await _dio.get('/api/products');
    return _asList(r.data);
  }

  // ===== Orders =====
  Future<Map<String, dynamic>> createOrder(Map<String, dynamic> order) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(order, audit); // NEW
    final r = await _dio.post('/api/orders', data: payload);
    if (_is2xx(r)) {
      final data = r.data;
      if (data is Map<String, dynamic>) return data;
      if (data is Map) return Map<String, dynamic>.from(data);
    }
    throw Exception('POST /api/orders failed ${r.statusCode} ${r.data}');
  }

  Future<Map<String, dynamic>> createOrderWithQueue({
    required Map<String, dynamic> order,
    required OutboxRepo outbox,
    int eagerRetries = 2,
  }) async {
    return postWithQueue(
      op: 'orders.create',
      endpoint: '/api/orders',
      body: order,
      outbox: outbox,
      eagerRetries: eagerRetries,
      attachAudit: true, // NEW: pastikan audit ikut saat offline
    );
  }

  // ===== Admin: products =====
  Future<void> upsertProduct(Map<String, dynamic> p) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(p, audit); // NEW
    final r = await _dio.post('/api/products', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Upsert product failed: ${r.statusCode} ${r.data}');
    }
  }

  Future<void> updateProduct(String sku, Map<String, dynamic> patch) async {
    // PATCH juga di-augment audit (aman buat server yang ignore)
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(patch, audit); // NEW
    final r = await _dio.patch('/api/products/$sku', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Update failed: ${r.statusCode} ${r.data}');
    }
  }

  Future<void> adjustStock(String sku, int delta, {String? reason}) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit({
      'delta': delta,
      if (reason != null) 'reason': reason,
    }, audit); // NEW
    final r = await _dio.post('/api/products/$sku/stock', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Adjust stock failed: ${r.statusCode} ${r.data}');
    }
  }

  Future<void> deleteProduct(String sku) async {
    final r = await _dio.post('/api/products/$sku/delete');
    if (!_is2xx(r)) {
      throw Exception('Soft delete failed: ${r.statusCode} ${r.data}');
    }
  }

  // ===== Payment Methods =====
  Future<List<dynamic>> paymentMethods() async {
    final r = await _dio.get('/api/payment-methods');
    return _asList(r.data);
  }

  Future<void> createPaymentMethod(Map<String, dynamic> body) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(body, audit); // NEW
    final r = await _dio.post('/api/payment-methods', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Create failed: ${r.statusCode}');
    }
  }

  Future<void> updatePaymentMethod(
    String code,
    Map<String, dynamic> patch,
  ) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(patch, audit); // NEW
    final r = await _dio.patch('/api/payment-methods/$code', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Update failed: ${r.statusCode}');
    }
  }

  Future<void> deletePaymentMethod(String code) async {
    final r = await _dio.delete('/api/payment-methods/$code');
    if (!_is2xx(r)) {
      throw Exception('Delete failed: ${r.statusCode}');
    }
  }

  // ===== Discounts =====
  // Future<List<Map<String, dynamic>>> discounts() async {
  //   final r = await _dio.get('/api/discounts');
  //   return _asListOfMap(r.data);
  // }

  // ApiService.discounts()
Future<List<Map<String, dynamic>>> discounts() async {
  final r = await _dio.get('/api/discounts');
  final list = _asListOfMapFlexible(r.data);

  return list.map((e) {
    final m = Map<String, dynamic>.from(e);

    // normalize enabled -> bool
    final rawEnabled = m['enabled'];
    final boolEnabled = switch (rawEnabled) {
      bool b   => b,
      int i    => i != 0,
      String s => s.toLowerCase() == 'true' || s == '1',
      _        => true,
    };
    m['enabled'] = boolEnabled;

    // normalize value -> double (atau num)
    final rawValue = m['value'];
    final numValue = switch (rawValue) {
      num n    => n.toDouble(),
      String s => double.tryParse(s) ?? 0.0,
      _        => 0.0,
    };
    m['value'] = numValue;

    // normalize sort -> int
    final rawSort = m['sort'];
    final sort = switch (rawSort) {
      int i    => i,
      String s => int.tryParse(s) ?? 0,
      _        => 0,
    };
    m['sort'] = sort;

    // pastikan string fields
    if (m['code'] != null) m['code'] = '${m['code']}';
    if (m['name'] != null) m['name'] = '${m['name']}';
    if (m['kind'] != null) m['kind'] = '${m['kind']}'; // 'percent' | 'amount' (server)
    return m;
  }).toList();
}


  Future<void> createDiscount(Map<String, dynamic> body) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(body, audit); // NEW
    final r = await _dio.post('/api/discounts', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Create failed: ${r.statusCode}');
    }
  }

  Future<void> updateDiscount(String code, Map<String, dynamic> patch) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(patch, audit); // NEW
    final r = await _dio.patch('/api/discounts/$code', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Update failed: ${r.statusCode}');
    }
  }

  Future<void> deleteDiscount(String code) async {
    final r = await _dio.delete('/api/discounts/$code');
    if (!_is2xx(r)) {
      throw Exception('Delete failed: ${r.statusCode}');
    }
  }

  // ===== Order Types =====
  Future<List<Map<String, dynamic>>> orderTypes() async {
    final r = await _dio.get('/api/order-types');
    final list = _asListOfMapFlexible(r.data);

    return list.map((e) {
      final m = Map<String, dynamic>.from(e);
      final rawEnabled = m['enabled'];
      final boolEnabled = switch (rawEnabled) {
        bool b => b,
        int i => i != 0,
        String s => s.toLowerCase() == 'true' || s == '1',
        _ => true,
      };
      m['enabled'] = boolEnabled;

      final rawSort = m['sort'];
      final sort = switch (rawSort) {
        int i => i,
        String s => int.tryParse(s) ?? 999,
        _ => 999,
      };
      m['sort'] = sort;

      if (m['code'] != null) m['code'] = '${m['code']}';
      if (m['name'] != null) m['name'] = '${m['name']}';

      return m;
    }).toList();
  }

  Future<void> createOrderType(Map<String, dynamic> body) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit({
      'code': body['code'],
      'name': body['name'],
      if (body.containsKey('enabled')) 'enabled': body['enabled'],
      if (body.containsKey('sort')) 'sort': body['sort'],
    }, audit); // NEW

    final r = await _dio.post('/api/order-types', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Create failed: ${r.statusCode} ${r.data}');
    }
  }

  Future<void> updateOrderType(String code, Map<String, dynamic> patch) async {
    final cleanPatch = <String, dynamic>{
      if (patch.containsKey('name')) 'name': patch['name'],
      if (patch.containsKey('enabled')) 'enabled': patch['enabled'],
      if (patch.containsKey('sort')) 'sort': patch['sort'],
    };

    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(cleanPatch, audit); // NEW

    final r = await _dio.patch('/api/order-types/$code', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Update failed: ${r.statusCode} ${r.data}');
    }
  }

  Future<void> deleteOrderType(String code) async {
    final r = await _dio.delete('/api/order-types/$code');
    if (!_is2xx(r)) {
      throw Exception('Delete failed: ${r.statusCode} ${r.data}');
    }
  }

  // ===== Menus =====
  Future<List<Map<String, dynamic>>> menus() async {
    final r = await _dio.get('/api/menus');
    if (_is2xx(r)) {
      final list = _asListOfMapFlexible(r.data);
      if (list.isNotEmpty) return list;
      final raw = _asList(r.data);
      return raw
          .map((e) => e is Map<String, dynamic>
              ? e
              : (e is Map ? Map<String, dynamic>.from(e) : <String, dynamic>{}))
          .where((m) => m.isNotEmpty)
          .toList();
    }
    return const <Map<String, dynamic>>[];
  }

  Future<void> createMenu(Map<String, dynamic> body) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(body, audit); // NEW
    final r = await _dio.post('/api/menus', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Create menu failed: ${r.statusCode} ${r.data}');
    }
  }

  Future<void> updateMenu(String code, Map<String, dynamic> patch) async {
    final audit = await _currentUserMap(); // NEW
    final payload = _withAudit(patch, audit); // NEW
    final r = await _dio.patch('/api/menus/$code', data: payload);
    if (!_is2xx(r)) {
      throw Exception('Update menu failed: ${r.statusCode} ${r.data}');
    }
  }

  Future<void> deleteMenu(String code) async {
    final r = await _dio.delete('/api/menus/$code');
    if (!_is2xx(r)) {
      throw Exception('Delete menu failed: ${r.statusCode}');
    }
  }

  // ===== Upload menu image (opsional) =====
  Future<String> uploadMenuImage({
    required String menuName,
    required String filePath,
  }) async {
    final audit = await _currentUserMap(); // NEW (optional untuk logs server)
    final formMap = {
      'menu_name': menuName,
      'image': await MultipartFile.fromFile(filePath),
      if (audit != null) 'created_by_id': audit['created_by_id'],
      if (audit != null) 'created_by': audit['created_by'],
    };
    final form = FormData.fromMap(formMap);
    final r = await _dio.post('/api/upload-menu-image', data: form);
    if (_is2xx(r)) {
      final data = r.data;
      if (data is Map && (data['ok'] == true) && data['url'] is String) {
        return data['url'] as String; // e.g. '/menu-images/...'
      }
    }
    throw Exception('Upload failed: ${r.statusCode} ${r.data}');
  }

  Future<List<Map<String, dynamic>>> orders({
    required int createdBy,
    String? sinceIso,
  }) async {
    final r = await _dio.get('/api/orders', queryParameters: {
      'created_by': createdBy,
      if (sinceIso != null) 'since': sinceIso,
    });
    if (r.statusCode != null && r.statusCode! ~/ 100 == 2 && r.data is List) {
      return (r.data as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    throw Exception('GET /api/orders failed: ${r.statusCode} ${r.data}');
  }

  Future<Map<String, dynamic>> orderDetail({
  required int id,
  required int createdBy,
}) async {
  final r = await _dio.get('/api/orders/$id', queryParameters: {
    'created_by': createdBy, // server side will verify ownership
  });
  if (r.statusCode != null && r.statusCode! ~/ 100 == 2 && r.data is Map) {
    return Map<String, dynamic>.from(r.data as Map);
  }
  throw Exception('GET /api/orders/$id failed: ${r.statusCode} ${r.data}');
}
}
