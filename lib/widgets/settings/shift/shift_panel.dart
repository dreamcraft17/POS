import 'package:ee_pos/providers/auth_providers.dart';
import 'package:flutter/material.dart';
import '../../../shift/shift_page.dart'; // panggil ShiftPage yg udah kita buat
import '../../../services/api_service.dart'; // sesuaikan path
import 'package:flutter_riverpod/flutter_riverpod.dart';
// import '../../../auth/auth_controller.dart'; // kalau pakai riverpod auth

class ShiftPanel extends ConsumerWidget {
  const ShiftPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider).valueOrNull;
    if (auth == null) {
      return const Center(child: Text('Harus login dulu untuk buka Shift'));
    }
    return ShiftPage(
      outletName: 'e+e Coffee n Kitchen', // bisa tarik dari config/outlet state
      cashierName: auth.displayName ?? auth.username,
      currentUserId: auth.id,
      sendToPrinter: (text) async {
        // Integrasi ke ReceiptPrinter milikmu
        // contoh:
        // await ReceiptPrinter.printWithSavedPrefs(context, text.split('\n'));
      },
    );
  }
}
