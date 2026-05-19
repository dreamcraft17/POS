import 'package:flutter/material.dart';
import '../../bill_receipt.dart'; // QueueTicketData, QueueItem, ReceiptPrinter
import 'printer_settings_panel.dart';
import 'package:ee_pos/widgets/settings/hardware/queue_reset_card.dart';


class KitchenPrinterSettingsPanel extends StatelessWidget {
  const KitchenPrinterSettingsPanel({super.key});

  Future<void> _testKitchenPrint(BuildContext context) async {
    try {
      final demo = QueueTicketData(
        queueNo: 'TEST-001',
        dateTime: DateTime.now(),
        storeName: 'Kitchen Test',
        userName: 'Tester',
        orderType: 'Takeaway',
        items: const [
          QueueItem(name: 'Americano', qty: 1),
          QueueItem(name: 'Latte', qty: 2),
          QueueItem(name: 'Nasi Goreng Spesial', qty: 1),
        ],
      );
      await ReceiptPrinter.printKitchenWithSavedPrefs(context, demo);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test ticket terkirim ke Kitchen Printer')),
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
    // ❗ Jangan pakai mainAxisSize: min di sini, biar panel setting dapat tinggi penuh
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Biar ngisi ruang kanan, pakai Expanded
        Expanded(
          child: PrinterSettingsPanel(
            key: const ValueKey('kitchen.printer.panel'),
            profilePrefix: 'kitchen.printer', // profil printer dapur/bar
            titleOverride: 'Kitchen Printer',
          ),
        ),
        const SizedBox(height: 12),
        const QueueResetCard(
  prefix: 'kitchen.queue.seq',
  title: 'Kitchen Queue Number',
),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.print),
            label: const Text('Test Kitchen Print'),
            onPressed: () => _testKitchenPrint(context),
          ),
        ),
      ],
    );
  }
}
