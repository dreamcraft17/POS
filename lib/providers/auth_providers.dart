// lib/providers/auth_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/auth_repo.dart';
import '../models/auth_user.dart';

final authRepoProvider = Provider<AuthRepo>((ref) => AuthRepo());

/// User aktif (null jika belum login). Auto-refresh dari /me; fallback cache.
final authUserProvider = FutureProvider<AuthUserModel?>((ref) async {
  final repo = ref.read(authRepoProvider);
  try {
    return await repo.me(refreshFromServer: true);
  } catch (_) {
    return repo.me(refreshFromServer: false);
  }
});

class AuthController extends StateNotifier<AsyncValue<AuthUserModel?>> {
  final AuthRepo _repo;
  AuthController(this._repo) : super(const AsyncValue.loading()) {
    _init();
  }

  Future<void> _init() async {
    try {
      final u = await _repo.me(refreshFromServer: true);
      state = AsyncValue.data(u);
    } catch (_) {
      final u = await _repo.me(refreshFromServer: false);
      state = AsyncValue.data(u);
    }
  }

  Future<void> login(String username, String password) async {
    state = const AsyncValue.loading();
    try {
      final u = await _repo.login(username, password);
      state = AsyncValue.data(u);
    } catch (e, st) {
      // KUNCI: jangan bikin state=error, supaya tetap di AuthPage
      state = const AsyncValue.data(null);
      // lempar lagi agar UI bisa munculin modal
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> register(String username, String password, {String? displayName}) async {
    state = const AsyncValue.loading();
    try {
      final u = await _repo.register(
        username: username,
        password: password,
        displayName: displayName,
      );
      state = AsyncValue.data(u);
    } catch (e, st) {
      // Sama seperti login: jangan bikin state=error
      state = const AsyncValue.data(null);
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<void> logout() async {
    // Hindari state error/flicker saat logout gagal.
    // (Opsional) Bisa set loading ringan; kalau mau bebas flicker, hapus baris di bawah.
    state = const AsyncValue.loading();
    try {
      await _repo.logout();
      state = const AsyncValue.data(null);
    } catch (e, st) {
      // Tetap pertahankan user lama (jangan error page).
      // Kalau sebelumnya kita set loading, kembalikan ke data(user lama) bila ada.
      final prev = await _safeMeFallback();
      state = AsyncValue.data(prev);
      Error.throwWithStackTrace(e, st);
    }
  }

  Future<AuthUserModel?> _safeMeFallback() async {
    try {
      return await _repo.me(refreshFromServer: false);
    } catch (_) {
      return null;
    }
  }
}

final authControllerProvider =
    StateNotifierProvider<AuthController, AsyncValue<AuthUserModel?>>(
  (ref) => AuthController(ref.read(authRepoProvider)),
);
