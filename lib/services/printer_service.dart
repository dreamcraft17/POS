// // lib/services/printer_service.dart
// import 'dart:io';
// import 'package:flutter/foundation.dart';
// import 'package:esc_pos_utils/esc_pos_utils.dart';
// import 'package:esc_pos_printer/esc_pos_printer.dart' show NetworkPrinter, PosPrintResult;
// import 'package:blue_thermal_printer/blue_thermal_printer.dart';
// import 'package:usb_esc_pos_printer/usb_esc_pos_printer.dart';

// /// Simple cart item shape used by generator (adapt ke model kamu kalau perlu)
// class PrintLineItem {
//   final String name;
//   final int qty;
//   final int priceCentsEach;
//   const PrintLineItem({
//     required this.name,
//     required this.qty,
//     required this.priceCentsEach,
//   });
//   int get lineTotal => qty * priceCentsEach;
// }

// /// Utility: format rupiah (fallback jika kamu mau pakai yg lain)
// String _rp(int cents) {
//   // cents di app kamu sudah rupiah "cents" (tanpa koma). Jadi treat as IDR integer.
//   final s = cents.toString();
//   final buf = StringBuffer();
//   for (int i = 0; i < s.length; i++) {
//     final idx = s.length - i;
//     buf.write(s[i]);
//     if (idx > 1 && idx % 3 == 1) buf.write('.');
//   }
//   // fallback sederhana
//   return 'Rp $s';
// }

// class PrinterService {
//   // ==== 1) Generate ESC/POS bytes (mm58 kertas kecil / ganti mm80 bila 80mm)
//   static Future<List<int>> buildTicket({
//     required List<PrintLineItem> items,
//     required int subtotal,
//     required int tax,
//     required int total,
//     String title = 'e+e Coffee Kitchen',
//     String? footer,
//     PaperSize paper = PaperSize.mm58,
//   }) async {
//     final profile = await CapabilityProfile.load();
//     final gen = Generator(paper, profile);

//     List<int> bytes = [];
//     bytes += gen.text(title,
//         styles: PosStyles(
//           align: PosAlign.center,
//           bold: true,
//           height: PosTextSize.size2,
//           width: PosTextSize.size2,
//         ));

//     final now = DateTime.now();
//     final dateStr =
//         '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
//         '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
//     bytes += gen.text('Date: $dateStr', styles: PosStyles(align: PosAlign.center));

//     bytes += gen.hr();

//     for (final it in items) {
//       // Nama
//       bytes += gen.text('${it.name} x${it.qty}');
//       // Harga → Total kanan
//       bytes += gen.row([
//         PosColumn(text: '  ${_rp(it.priceCentsEach)}', width: 6),
//         PosColumn(
//           text: _rp(it.lineTotal),
//           width: 6,
//           styles: PosStyles(align: PosAlign.right),
//         ),
//       ]);
//     }

//     bytes += gen.hr();
//     bytes += gen.row([
//       PosColumn(text: 'Subtotal', width: 6),
//       PosColumn(text: _rp(subtotal), width: 6, styles: PosStyles(align: PosAlign.right)),
//     ]);
//     bytes += gen.row([
//       PosColumn(text: 'Tax (11%)', width: 6),
//       PosColumn(text: _rp(tax), width: 6, styles: PosStyles(align: PosAlign.right)),
//     ]);
//     bytes += gen.row([
//       PosColumn(text: 'TOTAL', width: 6),
//       PosColumn(
//         text: _rp(total),
//         width: 6,
//         styles: PosStyles(align: PosAlign.right, bold: true, height: PosTextSize.size2),
//       ),
//     ]);
//     bytes += gen.hr();

//     if (footer != null && footer.isNotEmpty) {
//       bytes += gen.text(footer, styles: PosStyles(align: PosAlign.center));
//     } else {
//       bytes += gen.text('Thank you for your Purchase!', styles: PosStyles(align: PosAlign.center));
//     }

//     bytes += gen.feed(2);
//     bytes += gen.cut();
//     return bytes;
//   }

//   // ==== 2) Bluetooth (BlueThermalPrinter)
//   static Future<void> printBluetooth({
//     required List<int> ticketBytes,
//     // kalau kamu mau UI pilih, kirimkan device dari luar; kalau null → connect ke first bonded
//     BlueThermalPrinter? instance,
//     BluetoothDevice? device,
//   }) async {
//     final bt = instance ?? BlueThermalPrinter.instance;
//     bool? connected = await bt.isConnected;
//     if (connected != true) {
//       final bonded = await bt.getBondedDevices();
//       if (bonded.isEmpty) {
//         throw 'No paired Bluetooth printers found';
//       }
//       final target = device ?? bonded.first;
//       await bt.connect(target);
//     }
//     await bt.writeBytes(ticketBytes);
//   }

//   // ==== 3) LAN / Wi-Fi (esc_pos_printer)
//   static Future<void> printNetwork({
//     required List<int> ticketBytes,
//     required String ip,
//     int port = 9100,
//     PaperSize paper = PaperSize.mm58,
//   }) async {
//     final profile = await CapabilityProfile.load();
//     final printer = NetworkPrinter(paper, profile);
//     final PosPrintResult res = await printer.connect(ip, port: port, timeout: const Duration(seconds: 5));
//     if (res != PosPrintResult.success) {
//       throw 'Network connect failed: $res';
//     }
//     printer.rawBytes(ticketBytes);
//     printer.disconnect();
//   }

//   // ==== 4) USB OTG Android (usb_esc_pos_printer)
//   static Future<void> printUsb({
//     required List<int> ticketBytes,
//     required int vendorId,
//     required int productId,
//   }) async {
//     if (!Platform.isAndroid) {
//       throw 'USB printing supported on Android only';
//     }
//     final usbPrinter = UsbEscPosPrinter(
//       vendorId: vendorId,
//       productId: productId,
//       // optional: width dan codeTable
//       // width: 32, // characters per line for 58mm
//     );
//     final ok = await usbPrinter.connect();
//     if (ok != true) {
//       throw 'USB connect failed';
//     }
//     // library ini butuh text, tapi kita bisa langsung kirim raw jika support:
//     await usbPrinter.writeBytes(ticketBytes);
//     await usbPrinter.disconnect();
//   }
// }
