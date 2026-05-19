// // lib/printing/customer_printer_sender.dart
// import 'dart:convert';
// import 'dart:io';
// import 'dart:typed_data';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';

// // ambil prefs & enum printer type yang sudah ada di project kamu
// import '../services/printer_prefs.dart';
// // plugin yang sudah dipakai di settings panel
// import 'package:blue_thermal_printer/blue_thermal_printer.dart';
// import 'package:flutter_usb_thermal_plugin/flutter_usb_thermal_plugin.dart';
// import 'package:flutter_usb_thermal_plugin/model/usb_device_model.dart';

// /// Resolver: balikin callback pengirim teks ke printer customer (profile 'printer')
// Future<Future<void> Function(String)> resolveCustomerPrinterSender(BuildContext context) async {
//   final prefs = await PrinterPrefs.loadWithPrefix('printer'); // sama persis dg panel customer

//   switch (prefs.type) {
//     case PrinterType.network:
//       return (String text) async {
//         final ip = prefs.netIp.trim();
//         final port = prefs.netPort;
//         if (ip.isEmpty || port <= 0) {
//           throw 'IP/Port printer belum diset.';
//         }
//         final socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 5));
//         try {
//           socket.add(utf8.encode(text));
//           await socket.flush();
//         } finally {
//           await socket.close();
//         }
//       };

//     case PrinterType.bluetooth:
//       return (String text) async {
//         final bt = BlueThermalPrinter.instance;
//         // konek by address kalau ada, kalau tidak pakai nama
//         final addr = prefs.btAddress.trim();
//         final name = prefs.btName.trim();
//         bool connected = false;

//         try {
//           if (await bt.isConnected ?? false) {
//             connected = true;
//           } else {
//             if (addr.isNotEmpty) {
//               await bt.connect(address: addr);
//             } else if (name.isNotEmpty) {
//               // cari dari bonded devices
//               final bonded = await bt.getBondedDevices();
//               final target = bonded.firstWhere(
//                 (d) => (d.name ?? '').trim() == name,
//                 orElse: () => (throw 'Perangkat BT "$name" tidak ditemukan.'),
//               );
//               await bt.connect(address: target.address!);
//             } else {
//               throw 'Nama atau MAC Address Bluetooth belum diisi.';
//             } 
//             connected = true;
//           }

//           if (connected) {
//             final bytes = Uint8List.fromList(utf8.encode(text));
//             await bt.writeBytes(bytes);
//           }
//         } finally {
//           // biarkan tetap connect untuk cepat cetak berikutnya
//         }
//       };

//     case PrinterType.usb:
//       return (String text) async {
//         if (kIsWeb || !Platform.isAndroid) {
//           throw 'USB OTG hanya didukung di Android.';
//         }
//         final usb = FlutterUsbThermalPlugin();

//         // helper: parse “0x0416” atau “1046” → int
//         int _parseVidPid(String raw) {
//           final s = raw.trim().toLowerCase();
//           if (s.startsWith('0x')) {
//             return int.parse(s.substring(2), radix: 16);
//           }
//           return int.parse(s);
//         }

//         final int vid = _parseVidPid(prefs.usbVendorIdHex);
//         final int pid = _parseVidPid(prefs.usbProductIdHex);

//         final devs = await usb.getUSBDeviceList();
//         final target = devs.firstWhere(
//           (d) => (d.vendorId == vid) && (d.productId == pid),
//           orElse: () => (throw 'USB device dengan VID/PID sesuai tidak ditemukan.'),
//         );

//         // beberapa printer perlu open dulu lalu kirim string
//         await usb.connect(vid: vid, pid: pid);
//         try {
//           await usb.writeString(text);
//           // feed cut sederhana
//           await usb.writeString('\n\n\n');
//         } finally {
//           await usb.disconnect();
//         }
//       };

//     case PrinterType.none:
//     default:
//       return (String _) async {
//         throw 'Printer belum diset untuk profile "printer". Buka Settings → Printer.';
//       };
//   }
// }
