import 'package:flutter/material.dart';

/// Tampilkan “snackbar di atas” berbasis MaterialBanner.
/// [success] = true → hijau; false → merah.
/// [duration] default 2.2 detik, auto-dismiss.
void showTopMessage(
  BuildContext context,
  String message, {
  bool success = true,
  Duration duration = const Duration(milliseconds: 2200),
  IconData? icon,
}) {
  final messenger = ScaffoldMessenger.of(context);
  // pastikan bersih: tutup snackbar/banner yang masih terbuka
  messenger.clearSnackBars();
  messenger.hideCurrentMaterialBanner();

  final Color bg = success ? Colors.green : Colors.red;
  final Color fg = Colors.white;

  messenger.showMaterialBanner(
    MaterialBanner(
      backgroundColor: bg,
      elevation: 6,
      leading: Icon(icon ?? (success ? Icons.check_circle : Icons.error),
          color: fg),
      content: Text(
        message,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
      actions: [
        TextButton(
          onPressed: () => messenger.hideCurrentMaterialBanner(),
          child: Text('CLOSE', style: TextStyle(color: fg)),
        ),
      ],
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
  );

  Future.delayed(duration, () {
    // kalau context masih hidup, auto tutup
    messenger.hideCurrentMaterialBanner();
  });
}

void showTopSuccess(BuildContext context, String message) =>
    showTopMessage(context, message, success: true);

void showTopError(BuildContext context, String message) =>
    showTopMessage(context, message, success: false);
