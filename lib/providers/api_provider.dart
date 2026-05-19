import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/api_service.dart';

/// Single shared HTTP client (cookies/session reused app-wide).
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService.shared();
});
