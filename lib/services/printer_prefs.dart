import 'package:shared_preferences/shared_preferences.dart';
import 'package:esc_pos_utils/esc_pos_utils.dart' show PaperSize;

enum PrinterType { none, bluetooth, network, usb }

extension PrinterTypeX on PrinterType {
  static PrinterType fromName(String name) {
    switch (name) {
      case 'bluetooth':
        return PrinterType.bluetooth;
      case 'network':
        return PrinterType.network;
      case 'usb':
        return PrinterType.usb;
      default:
        return PrinterType.none;
    }
  }

  String get name {
    switch (this) {
      case PrinterType.bluetooth:
        return 'bluetooth';
      case PrinterType.network:
        return 'network';
      case PrinterType.usb:
        return 'usb';
      case PrinterType.none:
        return 'none';
    }
  }
}

class PrinterPrefs {
  final PrinterType type;
  final String paper; // '58' | '80'

  // Network
  final String netIp;
  final int netPort;

  // Bluetooth
  final String btName;
  final String btAddress;

  // USB
  final String usbVendorIdHex;
  final String usbProductIdHex;

  const PrinterPrefs({
    required this.type,
    required this.paper,
    this.netIp = '',
    this.netPort = 9100,
    this.btName = '',
    this.btAddress = '',
    this.usbVendorIdHex = '',
    this.usbProductIdHex = '',
  });

  factory PrinterPrefs.defaults() =>
      const PrinterPrefs(type: PrinterType.none, paper: '58');

  PaperSize get paperSize =>
      paper == '80' ? PaperSize.mm80 : PaperSize.mm58;

  int get usbVendorId => _parseHexOrDec(usbVendorIdHex);
  int get usbProductId => _parseHexOrDec(usbProductIdHex);

  static int _parseHexOrDec(String s) {
    final v = s.trim();
    if (v.isEmpty) return 0;
    if (v.startsWith('0x') || v.startsWith('0X')) {
      return int.tryParse(v.substring(2), radix: 16) ?? 0;
    }
    return int.tryParse(v) ?? 0;
  }

  static Future<PrinterPrefs> loadBar() => loadWithPrefix('bar.printer');
  Future<void> saveAsBar() => saveWithPrefix('bar.printer');

  // ===== Legacy keys (tanpa prefix) =====
  static const _kType = 'printer.type';
  static const _kPaper = 'printer.paper';
  static const _kIp = 'printer.net.ip';
  static const _kPort = 'printer.net.port';
  static const _kBtName = 'printer.bt.name';
  static const _kBtAddr = 'printer.bt.addr';
  static const _kVid = 'printer.usb.vid';
  static const _kPid = 'printer.usb.pid';

  // ===== Raw keys untuk prefixable profiles =====
  static const __type = 'type';
  static const __paper = 'paper';
  static const __ip = 'net.ip';
  static const __port = 'net.port';
  static const __btName = 'bt.name';
  static const __btAddr = 'bt.addr';
  static const __vid = 'usb.vid';
  static const __pid = 'usb.pid';

  static Future<PrinterPrefs> load() async {
    final sp = await SharedPreferences.getInstance();
    return PrinterPrefs(
      type: PrinterTypeX.fromName(sp.getString(_kType) ?? 'none'),
      paper: sp.getString(_kPaper) ?? '58',
      netIp: sp.getString(_kIp) ?? '',
      netPort: sp.getInt(_kPort) ?? 9100,
      btName: sp.getString(_kBtName) ?? '',
      btAddress: sp.getString(_kBtAddr) ?? '',
      usbVendorIdHex: sp.getString(_kVid) ?? '',
      usbProductIdHex: sp.getString(_kPid) ?? '',
    );
  }

  Future<void> save() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kType, type.name);
    await sp.setString(_kPaper, paper);
    await sp.setString(_kIp, netIp);
    await sp.setInt(_kPort, netPort);
    await sp.setString(_kBtName, btName);
    await sp.setString(_kBtAddr, btAddress);
    await sp.setString(_kVid, usbVendorIdHex);
    await sp.setString(_kPid, usbProductIdHex);
  }

  // ===== Scoped profiles (prefix: "printer" / "kitchen.printer" dsb) =====
  static String _k(String prefix, String key) => '$prefix.$key';

  static Future<PrinterPrefs> loadWithPrefix(String prefix) async {
    final sp = await SharedPreferences.getInstance();
    return PrinterPrefs(
      type: PrinterTypeX.fromName(sp.getString(_k(prefix, __type)) ?? 'none'),
      paper: sp.getString(_k(prefix, __paper)) ?? '58',
      netIp: sp.getString(_k(prefix, __ip)) ?? '',
      netPort: sp.getInt(_k(prefix, __port)) ?? 9100,
      btName: sp.getString(_k(prefix, __btName)) ?? '',
      btAddress: sp.getString(_k(prefix, __btAddr)) ?? '',
      usbVendorIdHex: sp.getString(_k(prefix, __vid)) ?? '',
      usbProductIdHex: sp.getString(_k(prefix, __pid)) ?? '',
    );
  }

  Future<void> saveWithPrefix(String prefix) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_k(prefix, __type), type.name);
    await sp.setString(_k(prefix, __paper), paper);
    await sp.setString(_k(prefix, __ip), netIp);
    await sp.setInt(_k(prefix, __port), netPort);
    await sp.setString(_k(prefix, __btName), btName);
    await sp.setString(_k(prefix, __btAddr), btAddress);
    await sp.setString(_k(prefix, __vid), usbVendorIdHex);
    await sp.setString(_k(prefix, __pid), usbProductIdHex);
  }

  static Future<PrinterPrefs> loadCustomerAny() async {
    final prefixed = await loadWithPrefix('printer');
    if (prefixed.type != PrinterType.none) return prefixed;
    return const PrinterPrefs(type: PrinterType.none, paper: '58');
  }

  static Future<PrinterPrefs> loadKitchen() =>
      loadWithPrefix('kitchen.printer');
  Future<void> saveAsKitchen() => saveWithPrefix('kitchen.printer');
}
