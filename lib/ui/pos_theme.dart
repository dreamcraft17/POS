import 'package:flutter/material.dart';

class PosTheme {
  static const black = Colors.black;
  static const white = Colors.white;
  static const panel = Color(0xFFF7F7F7);
  static const border = Color(0xFFE5E5E5);
  static const muted = Color(0xFF6B6B6B);

  static InputDecoration searchFieldDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: const Icon(Icons.search),
      isDense: true,
      filled: true,
      fillColor: panel,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: border),
      ),
      suffixIcon: suffixIcon,
    );
  }
}
