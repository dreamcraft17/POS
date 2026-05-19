import 'package:flutter/material.dart';

class CheckoutSettingsPanel extends StatelessWidget {
  const CheckoutSettingsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: const [
        Text('Checkout Settings', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        SizedBox(height: 12),
        Expanded(child: Center(child: Text('Checkout settings (coming soon)'))),
      ],
    );
  }
}
