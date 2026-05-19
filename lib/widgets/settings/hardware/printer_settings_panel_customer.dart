import 'package:flutter/material.dart';
import 'printer_settings_panel.dart';

class CustomerPrinterSettingsPanel extends StatelessWidget {
  const CustomerPrinterSettingsPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return const PrinterSettingsPanel(
      key: ValueKey('customer.printer.panel'),
      profilePrefix: 'printer',               // profil printer biasa
      titleOverride: 'Printer',
    );
  }
}
