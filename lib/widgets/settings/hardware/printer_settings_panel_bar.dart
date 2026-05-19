// lib/widgets/settings/hardware/bar_printer_settings_panel.dart
import 'package:flutter/material.dart';
import '../../bill_receipt.dart'; // QueueTicketData, QueueItem, ReceiptPrinter
import 'printer_settings_panel.dart';

class BarPrinterSettingsPanel extends StatelessWidget {
  const BarPrinterSettingsPanel({super.key});

  Future<void> _testBarPrint(BuildContext context) async {
    try {
      final demo = QueueTicketData(
        queueNo: 'TEST-BAR-001',
        dateTime: DateTime.now(),
        storeName: 'Bar Test',
        userName: 'Tester',
        orderType: 'Dine-in',
        items: const [
          QueueItem(name: 'Iced Latte', qty: 2),
          QueueItem(name: 'Americano', qty: 1),
          QueueItem(name: 'Cheese Cake', qty: 1),
        ],
      );
      await ReceiptPrinter.printBarWithSavedPrefs(context, demo);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test ticket terkirim ke Bar Printer')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal tes cetak: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: PrinterSettingsPanel(
            key: const ValueKey('bar.printer.panel'),
            profilePrefix: 'bar.printer', // ✅ konsisten dengan ReceiptPrinter
            titleOverride: 'Bar Printer',
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Test Bar Print'),
            onPressed: () => _testBarPrint(context),
          ),
        ),
      ],
    );
  }
}
