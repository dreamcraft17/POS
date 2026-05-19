import 'package:flutter/material.dart';

Future<void> showErrorDialog(
  BuildContext context, {
  String title = 'Login gagal',
  required String message,
  String primaryText = 'OK',
  VoidCallback? onPrimary,
  String? secondaryText,
  VoidCallback? onSecondary,
  bool barrierDismissible = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.error_outline, size: 24),
          const SizedBox(width: 8),
          Flexible(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: [
        if (secondaryText != null)
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onSecondary?.call();
            },
            child: Text(secondaryText),
          ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onPrimary?.call();
          },
          child: Text(primaryText),
        ),
      ],
    ),
  );
}
