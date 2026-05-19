import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Clipboard + rootBundle
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
// UI deps
import '../ui/pos_theme.dart';
import '../utils/formatting.dart';
import '../ui/top_message.dart';

// ESC/POS & printer deps
import 'package:esc_pos_utils/esc_pos_utils.dart';
import 'package:esc_pos_printer/esc_pos_printer.dart'
    show NetworkPrinter, PosPrintResult;
import 'package:blue_thermal_printer/blue_thermal_printer.dart';
import 'package:flutter_usb_thermal_plugin/flutter_usb_thermal_plugin.dart';
import 'package:flutter_usb_thermal_plugin/model/usb_device_model.dart';

// Read default printer settings
import '../services/printer_prefs.dart';

/// ======================= ASCII Separator Helpers =======================
String _repeatChar(String ch, int len) => List.filled(len, ch).join();
String _sepLineForText({String ch = '=', int len = 30}) => _repeatChar(ch, len);

/// For UI preview: show an ASCII line (looks the same as receipt)
/// Rough char width: 58mm ≈ 32 chars, 80mm ≈ 48 chars
Widget _asciiSeparatorUI({String ch = '=', String paper = '58'}) {
  final int len = (paper == '80') ? 48 : 32;
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Text(
      _repeatChar(ch, len),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.0),
    ),
  );
}

/// ======================= Data & Preview =======================

class BillLine {
  final String name;
  final int qty;
  final int priceCentsEach;

  /// NEW: list customize/modifiers, e.g. ["Ice", "Less sugar"]
  final List<String>? mods;

  /// NEW: per-item note
  final String? note;

  const BillLine({
    required this.name,
    required this.qty,
    required this.priceCentsEach,
    this.mods,
    this.note,
  });

  int get lineTotal => qty * priceCentsEach;
}

class BillData {
  final String title;
  final DateTime date;
  final List<BillLine> items;
  final int subtotal;
  final int discount;
  final int tax;
  final int total;
  final String? footer;

  // NEW: info toko (display name / alamat)
  final String? storeInfo;

  final String? orderId;
  final String? orderTypeName;
  final String? paymentSummary;
  final List<String>? paymentLines;
  final String? tableName;

  const BillData({
    required this.title,
    required this.date,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    this.footer,

    // NEW
    this.storeInfo,
    this.orderId,
    this.orderTypeName,
    this.paymentSummary,
    this.paymentLines,
    this.tableName,
  });
}

// ===== KITCHEN / QUEUE DATA =====
class QueueItem {
  final String name;
  final int qty;

  /// NEW: list customize/modifiers untuk NEW ORDER
  final List<String>? mods;

  /// NEW: catatan untuk NEW ORDER
  final String? note;

  const QueueItem({
    required this.name,
    required this.qty,
    this.mods,
    this.note,
  });
}

class QueueTicketData {
  final String queueNo; // from order id
  final DateTime dateTime; // order date time
  final String storeName; // e+e coffee
  final String userName; // cashier/user name
  final String orderType; // Dine in / Takeaway / etc
  final List<QueueItem> items;
  final String? tableName;

  const QueueTicketData({
    required this.queueNo,
    required this.dateTime,
    required this.storeName,
    required this.userName,
    required this.orderType,
    required this.items,
    this.tableName,
  });
}

/// Compose teks NEW ORDER (Queue) dengan lebar dinamis
/// width: 32 (58mm) atau 48 (80mm)
String composeKitchenText(QueueTicketData d, {int width = 32}) {
  String twoColFixed(String left, String right,
      {required int total, int rightWidth = 6}) {
    final lw = (total - rightWidth - 1).clamp(1, total);
    final l = left.length > lw ? left.substring(0, lw) : left;
    final r =
        right.length > rightWidth ? right.substring(0, rightWidth) : right;
    return l.padRight(lw) + ' ' + r.padLeft(rightWidth);
  }

  // separator pake '='
  String line(int total) => ''.padRight(total, '=');

  List<String> wrapLeft(String text, int width) {
    final words = text.split(RegExp(r'\s+'));
    final lines = <String>[];
    var cur = StringBuffer();
    for (final w in words) {
      final add = (cur.isEmpty ? 0 : 1) + w.length;
      if (cur.length + add > width) {
        if (cur.isNotEmpty) {
          lines.add(cur.toString());
          cur = StringBuffer();
        }
        if (w.length > width) {
          var s = w;
          while (s.length > width) {
            lines.add(s.substring(0, width));
            s = s.substring(width);
          }
          if (s.isNotEmpty) cur.write(s);
        } else {
          cur.write(w);
        }
      } else {
        if (cur.isNotEmpty) cur.write(' ');
        cur.write(w);
      }
    }
    if (cur.isNotEmpty) lines.add(cur.toString());
    return lines;
  }

  final dt = _formatDate(d.dateTime, 'dd/MM/yyyy HH:mm');
  final date = dt.split(' ').first;
  final time = dt.split(' ').last;

  const qtyCol = 5;
  final leftColWidth = width - qtyCol - 1;

  final b = StringBuffer();
  b.writeln('NEW ORDER');
  b.writeln(twoColFixed('Queue No :', d.queueNo,
      total: width, rightWidth: width - 'Queue No :'.length - 1));
  b.writeln(twoColFixed(date, time, total: width, rightWidth: time.length));
  b.writeln(twoColFixed(d.storeName, d.userName,
      total: width, rightWidth: d.userName.length));
  b.writeln(line(width));
  b.writeln('Type : ${d.orderType}');
  if ((d.tableName ?? '').isNotEmpty) {
    b.writeln('Table: ${d.tableName}'); // <-- NEW
  }
  b.writeln(line(width));

  // judul kolom
  b.writeln(twoColFixed('Item', 'Qty', total: width, rightWidth: qtyCol));
  b.writeln(line(width));

  for (final it in d.items) {
    final nameLines = wrapLeft(it.name, leftColWidth);
    final qtyStr = it.qty.toString();
    if (nameLines.isEmpty) {
      b.writeln(twoColFixed('-', qtyStr, total: width, rightWidth: qtyCol));
      continue;
    }
    // baris pertama: nama + qty
    b.writeln(
        twoColFixed(nameLines.first, qtyStr, total: width, rightWidth: qtyCol));
    // lanjutan nama (wrap)
    for (final extra in nameLines.skip(1)) {
      b.writeln(twoColFixed(extra, '', total: width, rightWidth: qtyCol));
    }

    // === NEW: customize di bawah nama ===
    if ((it.mods ?? const []).isNotEmpty) {
      for (final m in it.mods!) {
        for (final lineTxt in wrapLeft('  - $m', leftColWidth)) {
          b.writeln(twoColFixed(lineTxt, '', total: width, rightWidth: qtyCol));
        }
      }
    }

    // === NEW: note di bawah customize ===
    if ((it.note ?? '').trim().isNotEmpty) {
      for (final lineTxt in wrapLeft('  * ${it.note!.trim()}', leftColWidth)) {
        b.writeln(twoColFixed(lineTxt, '', total: width, rightWidth: qtyCol));
      }
    }
  }

  // tutup pake garis bawah
  b.writeln(line(width));

  return b.toString().trimRight();
}

class _Prefs {
  final String title;
  final String footer;
  final String dateFormat;
  final bool showOrder;
  final bool showPayment;
  final bool showSubtotal;
  final bool showTax;
  final String taxLabel;
  final String paper; // '58' | '80'
  final bool centerTotal;
  final int cutFeed;
  final String social;

  // NEW: Wi-Fi preferences
  final String wifiSsid;
  final String wifiPass;
  final bool showWifi;

  _Prefs({
    required this.title,
    required this.footer,
    required this.dateFormat,
    required this.showOrder,
    required this.showPayment,
    required this.showSubtotal,
    required this.showTax,
    required this.taxLabel,
    required this.paper,
    required this.centerTotal,
    required this.cutFeed,
    required this.social,
    // NEW
    required this.wifiSsid,
    required this.wifiPass,
    required this.showWifi,
  });

  static Future<_Prefs> load() async {
    final p = await SharedPreferences.getInstance();
    String getS(String k, String d) => p.getString(k) ?? d;
    bool getB(String k, bool d) => p.getBool(k) ?? d;
    int getI(String k, int d) => p.getInt(k) ?? d;
    return _Prefs(
      title: getS('receipt_title', 'e+e Coffee Kitchen'),
      footer: getS('receipt_footer', 'Thank you'),
      dateFormat: getS('receipt_date_format', 'dd/MM/yyyy HH:mm'),
      showOrder: getB('receipt_show_order', true),
      showPayment: getB('receipt_show_payment', true),
      showSubtotal: getB('receipt_show_subtotal', true),
      showTax: getB('receipt_show_tax', true),
      taxLabel: getS('receipt_tax_label', 'VAT (10%)'),
      paper: getS('receipt_paper', '58'),
      centerTotal: getB('receipt_center_total', false),
      cutFeed: getI('receipt_cut_feed', 0),
      social: getS('receipt_social', 'Instagram: eecoffee.id'),
      // NEW
      wifiSsid: getS('receipt_wifi_ssid', '').trim(),
      wifiPass: getS('receipt_wifi_pass', '').trim(),
      showWifi: getB('receipt_wifi_show', true),
    );
  }
}

String _formatDate(DateTime d, String f) {
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final yyyy = '${d.year}';
  final HH = d.hour.toString().padLeft(2, '0');
  final MM = d.minute.toString().padLeft(2, '0');

  // English months
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  final MMM = months[d.month - 1];

  switch (f) {
    case 'yyyy-MM-dd HH:mm':
      return '$yyyy-$mm-$dd $HH:$MM';
    case 'dd MMM yyyy HH:mm':
      return '$dd $MMM $yyyy $HH:$MM';
    default:
      return '$dd/$mm/$yyyy $HH:$MM';
  }
}

/// ======================= Text Preview (EN) with "====" separators =======================
String composeBillText(BillData d) {
  final pTitle = d.title;
  final dt = d.date;
  final dateStr = _formatDate(dt, 'dd/MM/yyyy HH:mm'); // text fallback
  final b = StringBuffer();
  b.writeln(pTitle);
  if (d.storeInfo?.isNotEmpty ?? false) b.writeln(d.storeInfo!);
  b.writeln('Date    : $dateStr');

  if((d.tableName??'').isNotEmpty){
    b.writeln('Table   : ${d.tableName}');
  }

  final hasOrder = (d.orderId ?? '').isNotEmpty;
  final hasType = (d.orderTypeName ?? '').isNotEmpty;

  if (hasOrder) b.writeln('Order   : #${d.orderId}');
  if (hasOrder && hasType)
    b.writeln(_sepLineForText()); // ==== separator between Order & Type
  if (hasType) b.writeln('Type    : ${d.orderTypeName}');

  b.writeln(_sepLineForText()); // ==== separator
  for (final it in d.items) {
    b.writeln('${it.name} x${it.qty}');
    b.writeln('  ${rp(it.priceCentsEach)}  →  ${rp(it.lineTotal)}');
    // NEW: mods & note
    if ((it.mods ?? const []).isNotEmpty) {
      for (final m in it.mods!) {
        b.writeln('  - $m');
      }
    }
    if ((it.note ?? '').trim().isNotEmpty) {
      b.writeln('  * ${it.note!.trim()}');
    }
  }
  b.writeln(_sepLineForText()); // ==== separator
  b.writeln('Subtotal : ${rp(d.subtotal)}');
  if (d.discount > 0) {
    b.writeln('Discount : -${rp(d.discount)}');
  }
  b.writeln('VAT (10%): ${rp(d.tax)}');
  b.writeln('Total    : ${rp(d.total)}');

  if ((d.paymentSummary?.isNotEmpty ?? false) ||
      (d.paymentLines?.isNotEmpty ?? false)) {
    b.writeln(_sepLineForText()); // ==== separator
    if (d.paymentSummary?.isNotEmpty ?? false)
      b.writeln('Payment  : ${d.paymentSummary}');
    if (d.paymentLines != null)
      for (final line in d.paymentLines!) b.writeln(line);
  }

  b.writeln(_sepLineForText());
  b.writeln('Instagram: eecoffee.id'); // fallback teks untuk copy-to-clipboard
  return b.toString();
}

class BillReceipt extends StatelessWidget {
  const BillReceipt({super.key, required this.data});
  final BillData data;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_Prefs>(
      future: _Prefs.load(),
      builder: (ctx, snap) {
        final pr = snap.data ??
            _Prefs(
              title: 'e+e Coffee Kitchen',
              footer: 'Thank you',
              dateFormat: 'dd/MM/yyyy HH:mm',
              showOrder: true,
              showPayment: true,
              showSubtotal: true,
              showTax: true,
              taxLabel: 'VAT (10%)',
              paper: '58',
              centerTotal: false,
              cutFeed: 0,
              social: 'Instagram: eecoffee.id',
              // NEW defaults
              wifiSsid: '',
              wifiPass: '',
              showWifi: true,
            );

        final title = (data.title.isNotEmpty ? data.title : pr.title);
        final footer =
            (data.footer?.isNotEmpty == true) ? data.footer! : pr.footer;
        final dateStr = _formatDate(data.date, pr.dateFormat);

        final hasOrder = pr.showOrder && (data.orderId ?? '').isNotEmpty;
        final hasType = (data.orderTypeName ?? '').isNotEmpty;

        Widget totalWidget;
        if (pr.centerTotal) {
          totalWidget = Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              rp(data.total),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
          );
        } else {
          totalWidget = _row('TOTAL', rp(data.total), bold: true, big: true);
        }

        return DefaultTextStyle(
          style: Theme.of(context).textTheme.bodyMedium!,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Image.asset(
                  'assets/receipt/logo_bill.png',
                  height: 56,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18),
                  ),
                ),
              ),
              Text('Date: $dateStr', textAlign: TextAlign.center),
              if((data.tableName?? '').isNotEmpty)
                Text('Table: ${data.tableName}', textAlign: TextAlign.center),

              if (hasOrder)
                Text('Order: #${data.orderId}', textAlign: TextAlign.center),
              if (hasOrder && hasType)
                _asciiSeparatorUI(
                    paper: pr.paper), // ==== separator between Order & Type
              if (hasType)
                Text('Type: ${data.orderTypeName}',
                    textAlign: TextAlign.center),

              _asciiSeparatorUI(paper: pr.paper), // ==== header -> items

              // NEW: render item sebagai blok: Nama xQty + total, lalu mods & note
              ...data.items.map((it) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text('${it.name} x${it.qty}'),
                            ),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Text(rp(it.lineTotal)),
                            ),
                          ),
                        ],
                      ),
                      if ((it.mods ?? const []).isNotEmpty)
                        ...it.mods!.map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              '  - $m',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black87),
                              textAlign: TextAlign.left,
                            ),
                          ),
                        ),
                      if ((it.note ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '  * ${it.note!.trim()}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black87),
                            textAlign: TextAlign.left,
                          ),
                        ),
                    ],
                  )),

              _asciiSeparatorUI(paper: pr.paper), // ==== items -> totals

              if (pr.showSubtotal) _row('Subtotal', rp(data.subtotal)),
              if (data.discount > 0) _row('Discount', '-${rp(data.discount)}'),
              if (pr.showTax) _row(pr.taxLabel, rp(data.tax)),
              totalWidget,

              if (pr.showPayment &&
                  ((data.paymentSummary?.isNotEmpty ?? false) ||
                      (data.paymentLines?.isNotEmpty ?? false))) ...[
                _asciiSeparatorUI(paper: pr.paper), // ==== totals -> payment
                if (data.paymentSummary?.isNotEmpty ?? false)
                  _row('Payment', data.paymentSummary!),
                if (data.paymentLines != null)
                  ...data.paymentLines!.map(
                    (e) => Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [const Text(''), Text(e)],
                    ),
                  ),
              ],

              const SizedBox(height: 6),
              Text(footer, textAlign: TextAlign.center),
              if (pr.social.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(pr.social,
                    textAlign: TextAlign.center,
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black87)),
              ],

              // NEW: Wi-Fi line under Instagram
              if (pr.showWifi && pr.wifiPass.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  pr.wifiSsid.trim().isNotEmpty
                      ? 'Wi-Fi: ${pr.wifiSsid.trim()}  •  Password: ${pr.wifiPass.trim()}'
                      : 'Wi-Fi Password: ${pr.wifiPass.trim()}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black87),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _row(String l, String v, {bool big = false, bool bold = false}) {
    final st = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
      fontSize: big ? 16 : 14,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(l, style: st),
            ),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(v, style: st),
            ),
          ),
        ],
      ),
    );
  }
}

/// ======================= Printing Helper =======================

class ReceiptPrinter {
  /// Print Kitchen/Queue ticket using saved KITCHEN printer profile
  static Future<void> printKitchenWithSavedPrefs(
      BuildContext context, QueueTicketData data) async {
    try {
      final prefs = await PrinterPrefs.loadKitchen();
      if (!context.mounted) return;
      if (prefs.type == PrinterType.none) {
        showTopError(context, 'Set Kitchen Printer first in Settings → Kitchen');
        return;
      }

      // Build bytes: simple ESC/POS text (monospace)
      final profile = await CapabilityProfile.load();
      final paper = (prefs.paper == '80') ? PaperSize.mm80 : PaperSize.mm58;
      final width = (prefs.paper == '80') ? 48 : 32;
      final generator = Generator(paper, profile);
      final text = composeKitchenText(data, width: width);
      final bytes = BytesBuilder();
      for (final line in text.split('\n')) {
        bytes.add(generator.text(line,
            styles: const PosStyles(align: PosAlign.left)));
      }
      bytes.add(generator.feed(2));
      bytes.add(generator.cut(mode: PosCutMode.partial));

      final toSend = bytes.toBytes();

      switch (prefs.type) {
        case PrinterType.network:
          final printer = NetworkPrinter(paper, profile);
          final res = await printer.connect(prefs.netIp,
              port: prefs.netPort, timeout: const Duration(seconds: 5));
          if (res != PosPrintResult.success) throw 'Connect failed: $res';
          printer.rawBytes(toSend);
          printer.disconnect();
          break;
        case PrinterType.bluetooth:
          final bt = BlueThermalPrinter.instance;
          bool? connected = await bt.isConnected;
          if (connected != true) {
            final bonded = await bt.getBondedDevices();
            if (bonded.isEmpty) throw 'No paired Bluetooth printers';
            BluetoothDevice? target;
            if (prefs.btAddress.isNotEmpty) {
              target = bonded.firstWhere(
                (d) =>
                    (d.address ?? '').toLowerCase() ==
                    prefs.btAddress.toLowerCase(),
                orElse: () => bonded.first,
              );
            } else if (prefs.btName.isNotEmpty) {
              target = bonded.firstWhere(
                (d) =>
                    (d.name ?? '').toLowerCase() == prefs.btName.toLowerCase(),
                orElse: () => bonded.first,
              );
            } else {
              target = bonded.first;
            }
            await bt.connect(target);
          }
          await bt.writeBytes(Uint8List.fromList(toSend));
          break;
        case PrinterType.usb:
          final usb = FlutterUsbThermalPlugin();
          final ok = await usb.connect(prefs.usbVendorId, prefs.usbProductId);
          if (ok != true) throw 'USB connect failed';
          await usb.write(Uint8List.fromList(toSend));
          break;
        case PrinterType.none:
          break;
      }
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st));
      if (context.mounted) {
        showTopError(context, 'kitchen print failed: $e');
      }
    }
  }

  static Future<void> printKitchenOnCustomerPrinter(
      BuildContext context, QueueTicketData data) async {
    try {
      // pakai profile printer CUSTOMER
      final prefs = await PrinterPrefs.loadWithPrefix('printer');
      if (!context.mounted) return;

      // Build ESC/POS bytes dari teks kitchen (monospace)
      final profile = await CapabilityProfile.load();
      final paper = (prefs.paper == '80') ? PaperSize.mm80 : PaperSize.mm58;
      final width = (prefs.paper == '80') ? 48 : 32;
      final generator = Generator(paper, profile);

      final text = composeKitchenText(data, width: width);
      final bytes = BytesBuilder();
      for (final line in text.split('\n')) {
        bytes.add(generator.text(line,
            styles: const PosStyles(align: PosAlign.left)));
      }
      bytes.add(generator.feed(2));
      bytes.add(generator.cut(mode: PosCutMode.partial));
      final toSend = bytes.toBytes();

      // Kirim sesuai tipe printer CUSTOMER
      switch (prefs.type) {
        case PrinterType.network:
          if (prefs.netIp.isEmpty) throw 'Printer IP not set';
          await _printNetwork(
            ticketBytes: toSend,
            ip: prefs.netIp,
            port: prefs.netPort,
            paper: paper, // penting: ikuti ukuran kertas customer
          );
          break;
        case PrinterType.bluetooth:
          await _printBluetooth(ticketBytes: toSend);
          break;
        case PrinterType.usb:
          await _printUsb(
            ticketBytes: toSend,
            vendorId: prefs.usbVendorId,
            productId: prefs.usbProductId,
          );
          break;
        case PrinterType.none:
          throw 'Customer printer not configured';
      }
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st));
      if (context.mounted) {
        showTopError(context, 'kitchen-on-customer print failed: $e');
      }
    }
  }

  // Cetak Kitchen/Queue ticket menggunakan profil BAR printer (terpisah)
  static Future<void> printBarWithSavedPrefs(
      BuildContext context, QueueTicketData data) async {
    try {
      final prefs = await PrinterPrefs.loadWithPrefix('bar.printer');
      if (!context.mounted) return;
      if (prefs.type == PrinterType.none) {
        showTopError(context, 'set Bar Printer dulu di Settings → Bar');
        return;
      }

      // Build bytes dari teks kitchen (monospace “NEW ORDER”)
      final profile = await CapabilityProfile.load();
      final paper = (prefs.paper == '80') ? PaperSize.mm80 : PaperSize.mm58;
      final width = (prefs.paper == '80') ? 48 : 32;
      final generator = Generator(paper, profile);
      final text = composeKitchenText(data, width: width);

      final bb = BytesBuilder();
      for (final line in text.split('\n')) {
        bb.add(generator.text(line,
            styles: const PosStyles(align: PosAlign.left)));
      }
      bb.add(generator.feed(2));
      bb.add(generator.cut(mode: PosCutMode.partial));
      final bytes = bb.toBytes();

      switch (prefs.type) {
        case PrinterType.network:
          if (prefs.netIp.isEmpty) throw 'Printer IP not set';
          await _printNetwork(
              ticketBytes: bytes,
              ip: prefs.netIp,
              port: prefs.netPort,
              paper: paper);
          break;
        case PrinterType.bluetooth:
          await _printBluetooth(ticketBytes: bytes);
          break;
        case PrinterType.usb:
          await _printUsb(
              ticketBytes: bytes,
              vendorId: prefs.usbVendorId,
              productId: prefs.usbProductId);
          break;
        case PrinterType.none:
          break;
      }
    } catch (e, st) {
      FlutterError.reportError(FlutterErrorDetails(exception: e, stack: st));
      if (context.mounted) {
        showTopError(context, 'bar print failed: $e');
      }
    }
  }

  /// Print using saved default printer (falls back to picker if not set)
  static Future<void> printWithSavedPrefs(
      BuildContext context, BillData billData) async {
    try {
      final prefs = await PrinterPrefs.loadWithPrefix('printer');
      if (!context.mounted) return;
      if (prefs.type == PrinterType.none) {
        await pickAndPrint(context, billData);
        return;
      }

      final bytes = await _buildEscPos(billData, forcedPaper: prefs.paperSize);

      switch (prefs.type) {
        case PrinterType.network:
          if (prefs.netIp.isEmpty) throw 'Printer IP not set';
          await _printNetwork(
              ticketBytes: bytes,
              ip: prefs.netIp,
              port: prefs.netPort,
              paper: prefs.paperSize);
          break;
        case PrinterType.bluetooth:
          final bt = BlueThermalPrinter.instance;
          bool? connected = await bt.isConnected;
          if (connected != true) {
            final bonded = await bt.getBondedDevices();
            if (bonded.isEmpty) throw 'No paired Bluetooth printers';
            BluetoothDevice? target;
            if (prefs.btAddress.isNotEmpty) {
              target = bonded.firstWhere(
                (d) =>
                    (d.address ?? '').toLowerCase() ==
                    prefs.btAddress.toLowerCase(),
                orElse: () => bonded.first,
              );
            } else if (prefs.btName.isNotEmpty) {
              target = bonded.firstWhere(
                (d) =>
                    (d.name ?? '').toLowerCase() == prefs.btName.toLowerCase(),
                orElse: () => bonded.first,
              );
            } else {
              target = bonded.first;
            }
            await bt.connect(target);
          }
          await bt.writeBytes(Uint8List.fromList(bytes));
          break;
        case PrinterType.usb:
          final usb = FlutterUsbThermalPlugin();
          final ok = await usb.connect(prefs.usbVendorId, prefs.usbProductId);
          if (ok != true) throw 'USB connect failed';
          await usb.write(Uint8List.fromList(bytes));
          break;
        case PrinterType.none:
          break;
      }

      if (context.mounted) {
        showTopSuccess(context, 'receipt sent to default printer');
      }
    } catch (e) {
      if (context.mounted) {
        showTopError(context, 'autoprint failed: $e — opening printer picker...');
      }
      if (!context.mounted) return;
      await pickAndPrint(context, billData);
    }
  }

  /// Manual printer picker
  static Future<void> pickAndPrint(
      BuildContext context, BillData billData) async {
    final ticketBytes = await _buildEscPos(billData);
    if (!context.mounted) return;

    // Choose printer mode
    String mode = 'bluetooth'; // bluetooth | lan | usb
    final ipCtrl = TextEditingController(text: '192.168.0.100');

    // Bluetooth
    final bt = BlueThermalPrinter.instance;
    List<BluetoothDevice> bonded = [];
    try {
      bonded = await bt.getBondedDevices();
    } catch (_) {}
    BluetoothDevice? selectedBt = bonded.isNotEmpty ? bonded.first : null;

    // USB
    final usb = FlutterUsbThermalPlugin();
    List<UsbDevice> usbDevices = [];
    try {
      usbDevices = await usb.getUSBDeviceList();
    } catch (_) {}
    UsbDevice? selectedUsb = usbDevices.isNotEmpty ? usbDevices.first : null;
    if (!context.mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('Choose Printer'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              RadioListTile<String>(
                value: 'bluetooth',
                groupValue: mode,
                onChanged: (v) {
                  mode = v!;
                  (ctx as Element).markNeedsBuild();
                },
                title: const Text('Bluetooth'),
              ),
              if (mode == 'bluetooth')
                Card(
                  elevation: 0,
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Paired devices:'),
                          const SizedBox(height: 8),
                          if (bonded.isEmpty)
                            const Text(
                                'No paired Bluetooth printers. Pair one in system settings.'),
                          for (final d in bonded)
                            RadioListTile<BluetoothDevice>(
                              value: d,
                              groupValue: selectedBt,
                              onChanged: (v) {
                                selectedBt = v;
                                (ctx as Element).markNeedsBuild();
                              },
                              title: Text(d.name ?? 'Unknown'),
                              subtitle: Text(d.address ?? ''),
                            ),
                        ]),
                  ),
                ),
              _asciiSeparatorUI(paper: '58'), // visual break inside dialog
              RadioListTile<String>(
                value: 'lan',
                groupValue: mode,
                onChanged: (v) {
                  mode = v!;
                  (ctx as Element).markNeedsBuild();
                },
                title: const Text('LAN / Wi-Fi (IP:9100)'),
              ),
              if (mode == 'lan')
                TextField(
                  controller: ipCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Printer IP',
                    hintText: 'e.g. 192.168.0.123',
                    border: OutlineInputBorder(),
                  ),
                ),
              _asciiSeparatorUI(paper: '58'),
              RadioListTile<String>(
                value: 'usb',
                groupValue: mode,
                onChanged: (v) {
                  mode = v!;
                  (ctx as Element).markNeedsBuild();
                },
                title: const Text('USB (Android/Windows)'),
              ),
              if (mode == 'usb')
                Card(
                  elevation: 0,
                  color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Detected USB devices:'),
                          const SizedBox(height: 8),
                          if (usbDevices.isEmpty)
                            const Text(
                                'No USB devices detected. Check OTG/power/cable.'),
                          for (final dev in usbDevices)
                            RadioListTile<UsbDevice>(
                              value: dev,
                              groupValue: selectedUsb,
                              onChanged: (v) {
                                selectedUsb = v;
                                (ctx as Element).markNeedsBuild();
                              },
                              title: Text(dev.productName),
                              subtitle: Text(
                                  'VID: ${_asHex(dev.vendorId)}  PID: ${_asHex(dev.productId)}'),
                            ),
                          if (usbDevices.isNotEmpty)
                            Text(
                              'Selected: ${selectedUsb == null ? '-' : selectedUsb!.productName}',
                                style: const TextStyle(fontSize: 12)),
                        ]),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Print')),
        ],
      ),
    );

    if (ok != true) return;

    try {
      if (mode == 'bluetooth') {
        await _printBluetooth(ticketBytes: ticketBytes, device: selectedBt);
      } else if (mode == 'lan') {
        final ip = ipCtrl.text.trim();
        if (ip.isEmpty) throw 'IP is empty';

        // baca preferensi paper: 'receipt_paper' => '58' | '80'
        final sp = await SharedPreferences.getInstance();
        final paperPref = (sp.getString('receipt_paper') ?? '58').trim();
        final paper = (paperPref == '80') ? PaperSize.mm80 : PaperSize.mm58;

        await _printNetwork(
          ticketBytes: ticketBytes,
          ip: ip,
          paper: paper, // <- penting
        );
      } else if (mode == 'usb') {
        if (selectedUsb == null) throw 'No USB device selected';
        final vid = _toInt(selectedUsb!.vendorId);
        final pid = _toInt(selectedUsb!.productId);
        await _printUsb(
            ticketBytes: ticketBytes, vendorId: vid, productId: pid);
      }

      // Small preview
      final text = composeBillText(billData);
      if (!context.mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: PosTheme.white,
          surfaceTintColor: PosTheme.white,
          title: const Text('Receipt (Preview)',
              style: TextStyle(color: PosTheme.black)),
          content: SingleChildScrollView(child: BillReceipt(data: billData)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close')),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                  backgroundColor: PosTheme.black,
                  foregroundColor: PosTheme.white),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: text));
                if (!context.mounted) return;
                showTopMessage(context, 'receipt copied to clipboard');
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy Text'),
            ),
          ],
        ),
      );

      if (context.mounted) {
        showTopMessage(context, 'receipt sent to thermal printer');
      }
    } catch (e) {
      if (context.mounted) {
        showTopError(context, 'print failed: $e');
      }
    }
  }

  /// Build ESC/POS bytes from BillData + prefs (optional forced paper)
  static Future<List<int>> _buildEscPos(BillData d,
      {PaperSize? forcedPaper}) async {
    final pr = await _Prefs.load();

    final profile = await CapabilityProfile.load();
    final paper =
        forcedPaper ?? (pr.paper == '80' ? PaperSize.mm80 : PaperSize.mm58);
    final gen = Generator(paper, profile);

    final title = (d.title.isNotEmpty ? d.title : pr.title);
    final footer = (d.footer?.isNotEmpty == true) ? d.footer! : pr.footer;
    final dateStr = _formatDate(d.date, pr.dateFormat);

    List<int> bytes = [];
    // header
    final logo = await _loadBillLogo(paper: paper);
    if (logo != null) {
      bytes += gen.image(logo, align: PosAlign.center);
      bytes += gen.feed(1);
    } else {
      // fallback ke judul teks kalau logo belum ada
      bytes += gen.text(title.isEmpty ? ' ' : title,
          styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2));
    }
    bytes +=
        gen.text('Date: $dateStr', styles: PosStyles(align: PosAlign.center));
      
    if((d.tableName?? '').isNotEmpty){
      bytes += gen.text('Table: ${d.tableName}',
          styles: PosStyles(align: PosAlign.center));
    }

    // === Separator between Order & Type (only if both exist) ===
    final hasOrder = pr.showOrder && (d.orderId ?? '').isNotEmpty;
    final hasType = (d.orderTypeName ?? '').isNotEmpty;

    if (hasOrder) {
      bytes += gen.text('Order: #${d.orderId}',
          styles: PosStyles(align: PosAlign.center));
    }
    if (hasOrder && hasType) {
      bytes += gen.hr(ch: '='); // ==== separator between Order & Type
    }
    if (hasType) {
      bytes += gen.text('Type: ${d.orderTypeName}',
          styles: PosStyles(align: PosAlign.center));
    }

    bytes += gen.hr(ch: '='); // ==== header -> items

    // items
    for (final it in d.items) {
      bytes += gen.text('${it.name} x${it.qty}');
      bytes += gen.row([
        PosColumn(text: '  ${rp(it.priceCentsEach)}', width: 6),
        PosColumn(
            text: rp(it.lineTotal),
            width: 6,
            styles: PosStyles(align: PosAlign.right)),
      ]);

      // NEW: print mods & note di bawah
      if ((it.mods ?? const []).isNotEmpty) {
        for (final m in it.mods!) {
          bytes += gen.text('  - $m');
        }
      }
      if ((it.note ?? '').trim().isNotEmpty) {
        bytes += gen.text('  * ${it.note!.trim()}');
      }
    }

    bytes += gen.hr(ch: '='); // ==== items -> totals

    // totals
    if (pr.showSubtotal) {
      bytes += gen.row([
        PosColumn(text: 'Subtotal', width: 6),
        PosColumn(
            text: rp(d.subtotal),
            width: 6,
            styles: PosStyles(align: PosAlign.right)),
      ]);
    }
    if (d.discount > 0) {
      bytes += gen.row([
        PosColumn(text: 'Discount', width: 6),
        PosColumn(
            text: '-${rp(d.discount)}',
            width: 6,
            styles: PosStyles(align: PosAlign.right)),
      ]);
    }
    if (pr.showTax) {
      bytes += gen.row([
        PosColumn(text: pr.taxLabel, width: 6),
        PosColumn(
            text: rp(d.tax),
            width: 6,
            styles: PosStyles(align: PosAlign.right)),
      ]);
    }

    if (pr.centerTotal) {
      bytes += gen.text(rp(d.total),
          styles: PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2));
    } else {
      bytes += gen.row([
        PosColumn(text: 'TOTAL', width: 6),
        PosColumn(
            text: rp(d.total),
            width: 6,
            styles: PosStyles(
                align: PosAlign.right, bold: true, height: PosTextSize.size2)),
      ]);
    }

    // payment
    if (pr.showPayment &&
        ((d.paymentSummary?.isNotEmpty ?? false) ||
            (d.paymentLines?.isNotEmpty ?? false))) {
      bytes += gen.hr(ch: '='); // ==== totals -> payment

      final method = (d.paymentSummary?.isNotEmpty ?? false)
          ? d.paymentSummary!
          : (d.paymentLines?.isNotEmpty ?? false)
              ? d.paymentLines!.first
              : '';

      String ellipsize(String s, int max) =>
          (s.length <= max) ? s : s.substring(0, max - 1) + '…';
      final maxRight = (paper == PaperSize.mm58) ? 16 : 24;
      final methodShown = ellipsize(method, maxRight);

      bytes += gen.row([
        PosColumn(
          width: 6,
          text: 'PAYMENT',
          styles: PosStyles(bold: true, align: PosAlign.left),
        ),
        PosColumn(
          width: 6,
          text: methodShown,
          styles: PosStyles(bold: true, align: PosAlign.right),
        ),
      ]);

      if ((d.paymentLines?.length ?? 0) > 1) {
        for (final line in d.paymentLines!.skip(1)) {
          bytes += gen.text(
            line,
            styles: PosStyles(align: PosAlign.right),
          );
        }
      }
    }

    // footer
    bytes += gen.hr(ch: '='); // ==== before footer
    bytes += gen.text(footer, styles: PosStyles(align: PosAlign.center));
    final sp = await SharedPreferences.getInstance();
    final socialText = (sp.getString('receipt_social') ?? '').trim();
    final showLogo = sp.getBool('receipt_social_logo') ?? true;

    if (socialText.isNotEmpty) {
      final socialImg = await _buildSocialRowImage(
        paper: paper,
        text: socialText,
        showLogo: showLogo,
      );
      if (socialImg != null) {
        bytes += gen.image(socialImg, align: PosAlign.center);
      }
    }

    // NEW: Wi-Fi line (printed after social)
    final wifiSsid = (sp.getString('receipt_wifi_ssid') ?? '').trim();
    final wifiPass = (sp.getString('receipt_wifi_pass') ?? '').trim();
    final showWifi = sp.getBool('receipt_wifi_show') ?? true;
    if (showWifi && wifiPass.isNotEmpty) {
      final wifiLine = wifiSsid.isNotEmpty
          ? 'Wi-Fi: $wifiSsid  •  Password: $wifiPass'
          : 'Wi-Fi Password: $wifiPass';
      bytes += gen.text(wifiLine, styles: PosStyles(align: PosAlign.center));
    }

    // feed & cut
    if (pr.cutFeed > 0)
      bytes += gen.feed(pr.cutFeed);
    else
      bytes += gen.feed(2);
    bytes += gen.cut();

    return bytes;
  }

  // ------- Low-level printing -------

  static Future<void> _printBluetooth(
      {required List<int> ticketBytes, BluetoothDevice? device}) async {
    final bt = BlueThermalPrinter.instance;
    bool? connected = await bt.isConnected;
    if (connected != true) {
      final bonded = await bt.getBondedDevices();
      if (bonded.isEmpty) throw 'No paired Bluetooth printers found';
      final target = device ?? bonded.first;
      await bt.connect(target);
    }
    await bt.writeBytes(Uint8List.fromList(ticketBytes));
  }

  static Future<void> _printNetwork({
    required List<int> ticketBytes,
    required String ip,
    int port = 9100,
    required PaperSize paper, // ⬅️ pakai paper yg sesuai
  }) async {
    final profile = await CapabilityProfile.load();
    final printer = NetworkPrinter(paper, profile);
    final res = await printer.connect(ip, port: port);
    if (res != PosPrintResult.success) throw 'Connect failed: $res';
    printer.rawBytes(ticketBytes);
    printer.disconnect();
  }

  static Future<void> _printUsb(
      {required List<int> ticketBytes,
      required int vendorId,
      required int productId}) async {
    final usb = FlutterUsbThermalPlugin();
    final ok = await usb.connect(vendorId, productId);
    if (ok != true) throw 'USB connect failed';
    await usb.write(Uint8List.fromList(ticketBytes));
  }

  static int _toInt(dynamic v) {
    if (v == null) throw 'null value';
    if (v is int) return v;
    final s = v.toString().trim().toLowerCase();
    if (s.startsWith('0x')) return int.parse(s.substring(2), radix: 16);
    return int.parse(s);
  }

  static String _asHex(dynamic v) {
    if (v == null) return '??';
    if (v is int) return '0x${v.toRadixString(16)}';
    final s = v.toString().trim();
    final sl = s.toLowerCase();
    if (sl.startsWith('0x')) return s;
    final i = int.tryParse(s);
    return (i != null) ? '0x${i.toRadixString(16)}' : s;
  }
}

Future<img.Image?> _loadEscPosImage(String assetPath) async {
  try {
    final bd = await rootBundle.load(assetPath);
    final bytes = bd.buffer.asUint8List();
    final decoded = img.decodeImage(bytes);
    return decoded == null ? null : img.grayscale(decoded);
  } catch (_) {
    return null;
  }
}

int _textWidthV3(img.BitmapFont font, String text) {
  // Render into a small throwaway canvas, then scan non-white columns.
  final int h = font.lineHeight + 2;
  final tmp = img.Image(2048, h); // wide enough for one line
  final white = img.getColor(255, 255, 255);
  final black = img.getColor(0, 0, 0);

  img.fill(tmp, white);
  img.drawString(tmp, font, 0, 0, text, color: black);

  int left = -1, right = -1;
  for (int x = 0; x < tmp.width; x++) {
    bool hasInk = false;
    for (int y = 0; y < tmp.height; y++) {
      if (tmp.getPixel(x, y) != white) {
        hasInk = true;
        break;
      }
    }
    if (hasInk) {
      if (left == -1) left = x;
      right = x;
    }
  }
  if (left == -1) return 0; // empty string case
  return right - left + 1;
}

Future<img.Image?> _buildSocialRowImage({
  required PaperSize paper,
  required String text,
  required bool showLogo,
  String logoAsset = 'assets/receipt/instagram_mono.png',
}) async {
  // 58mm=384, 80mm=576
  final maxW = (paper == PaperSize.mm58) ? 384 : 576;
  final h = 28;

  final canvas = img.Image(maxW, h);
  img.fill(canvas, img.getColor(255, 255, 255));

  if (showLogo) {
    final logo0 = await _loadEscPosImage(logoAsset);
    if (logo0 != null) {
      final logo = (logo0.height > (h - 4))
          ? img.copyResize(logo0, height: h - 4)
          : logo0;
      img.copyInto(
        canvas,
        logo,
        dstX: 0,
        dstY: ((h - logo.height) / 2).floor(),
        blend: false,
      );
    }
  }

  // Render text set-up
  final img.BitmapFont font = img.arial_24;
  final textH = font.lineHeight;

  final int textW = _textWidthV3(font, text);

  // Re-clear and recompute centered layout
  img.fill(canvas, img.getColor(255, 255, 255));

  img.Image? logo;
  if (showLogo) {
    final logo0 = await _loadEscPosImage(logoAsset);
    if (logo0 != null) {
      logo = (logo0.height > (h - 4))
          ? img.copyResize(logo0, height: h - 4)
          : logo0;
    }
  }

  final spacing = (logo != null) ? 6 : 0;
  final totalW = (logo?.width ?? 0) + spacing + textW;
  final startX = ((maxW - totalW) / 2).floor().clamp(0, maxW - 1);
  final centerYLogo = ((h - (logo?.height ?? h)) / 2).floor();
  final centerYText = ((h - textH) / 2).floor();

  if (logo != null) {
    img.copyInto(canvas, logo, dstX: startX, dstY: centerYLogo, blend: false);
  }
  final textX = startX + (logo?.width ?? 0) + spacing;

  img.drawString(
    canvas,
    font,
    textX,
    centerYText,
    text,
    color: img.getColor(0, 0, 0),
  );

  return canvas;
}

Future<img.Image?> _loadBillLogo({required PaperSize paper}) async {
  try {
    final data = await rootBundle.load('assets/receipt/logo_bill.png');
    final bytes = data.buffer.asUint8List();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Lebar dot umum printer thermal
    final maxW = (paper == PaperSize.mm58) ? 384 : 576;

    // Resize proporsional jika terlalu lebar; ESC/POS lebih stabil jika grayscale
    final needResize = decoded.width > maxW;
    final resized = needResize ? img.copyResize(decoded, width: maxW) : decoded;
    return img.grayscale(resized);
  } catch (_) {
    return null; // fallback ke teks jika asset tak ada
  }
}
