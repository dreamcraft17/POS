// lib/services/receipt_printer.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

// ✅ PLUGINS yang dipakai di project kamu:
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter_usb_thermal_plugin/flutter_usb_thermal_plugin.dart'; // <- benar
import '../services/printer_prefs.dart';

/// Cetak baris teks ke printer sesuai setting yang disimpan di Customer Printer Settings.
/// Default profilePrefix = 'printer' (lihat CustomerPrinterSettingsPanel). :contentReference[oaicite:4]{index=4}
class ReceiptPrinter {
  static Future<void> printWithSavedPrefs(
  BuildContext context,
  List<String> lines, {
  String profilePrefix = 'printer',
  int feed = 3,
}) async {
  final prefs = await PrinterPrefs.loadWithPrefix(profilePrefix);
  final type = prefs.type;

  // convert lines -> bytes (support IMG:)
  final buffer = StringBuffer();
  for (final l in lines) {
    if (l.startsWith('IMG:')) {
      // Marker image, skip text, actual handling depends on plugin
      // Misalnya pakai esc_pos_utils untuk render image ke bytes
      // Untuk sekarang, kasih placeholder
      buffer.writeln('[IMAGE:${l.substring(4)}]');
    } else {
      buffer.writeln(l);
    }
  }
  final text = buffer.toString();

  switch (type) {
    case PrinterType.network:
      await _printNetwork(context, prefs, text);
      break;
    case PrinterType.bluetooth:
      await _printBluetooth(context, prefs, text);
      break;
    case PrinterType.usb:
      await _printUsb(context, prefs, text);
      break;
    case PrinterType.none:
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer belum disetel')),
        );
      }
      return;
  }
}


  /// Normalize lebar karakter untuk 58/80 mm
  static String _normalize(List<String> lines, {required String paper}) {
    // 58 ~ 32 kolom, 80 ~ 48 kolom (informasi saja; di sini kita cukup join)
    final buf = StringBuffer();
    for (final l in lines) buf.writeln(l);
    buf.writeln('\n\n'); // feed
    return buf.toString();
  }

  static Future<void> _printNetwork(
    BuildContext context,
    PrinterPrefs prefs,
    String text,
  ) async {
    if (prefs.netIp.trim().isEmpty || prefs.netPort <= 0) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('IP/Port belum diisi untuk Network printer')),
        );
      }
      return;
    }
    try {
      final socket = await Socket.connect(
        prefs.netIp,
        prefs.netPort,
        timeout: const Duration(seconds: 5),
      );
      socket.add(utf8.encode(text));
      await socket.flush();
      await socket.close();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tercetak via Network printer')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal cetak (Network): $e')));
      }
    }
  }

  static Future<void> _printBluetooth(
    BuildContext context,
    PrinterPrefs prefs,
    String text,
  ) async {
    if (kIsWeb) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bluetooth tidak didukung di Web')));
      }
      return;
    }
    try {
      final bt = BlueThermalPrinter.instance;
      bool connected = await bt.isConnected ?? false;

      // pilih device ter-pair berdasarkan name/MAC dari prefs (panel-mu juga pakai ini). :contentReference[oaicite:5]{index=5}
      if (!connected) {
        final bonded = await bt.getBondedDevices();
        final dev = bonded.firstWhere(
          (d) =>
              (prefs.btAddress.isNotEmpty &&
                  (d.address ?? '').toLowerCase() ==
                      prefs.btAddress.toLowerCase()) ||
              (prefs.btName.isNotEmpty &&
                  (d.name ?? '').toLowerCase() == prefs.btName.toLowerCase()),
          orElse: () => bonded.isNotEmpty
              ? bonded.first
              : (throw 'Tidak ada perangkat BT ter-pair'),
        );
        await bt.connect(dev);
        connected = await bt.isConnected ?? false;
      }

      if (!connected) throw 'BT not connected';

      final bytes = Uint8List.fromList(utf8.encode(text));
      await bt.writeBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tercetak via Bluetooth printer')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal cetak (Bluetooth): $e')));
      }
    }
  }

  static Future<void> _printUsb(
  BuildContext context,
  PrinterPrefs prefs,
  String text,
) async {
  try {
    final usb = FlutterUsbThermalPlugin();

    // cek device list (opsional)
    final devices = await usb.getUSBDeviceList();
    if (devices.isEmpty) {
      throw 'Tidak ada USB printer terdeteksi';
    }

    // connect: plugin ini pakai positional arguments (int vid, int pid)
    final ok = await usb.connect(prefs.usbVendorId, prefs.usbProductId);
    if (ok != true) throw 'USB connect failed ($ok)';

    // kirim teks
    await usb.printText(text + '\n\n\n');

    // close connection
    await usb.close();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tercetak via USB printer')),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Gagal cetak (USB): $e')));
    }
  }
}

}
