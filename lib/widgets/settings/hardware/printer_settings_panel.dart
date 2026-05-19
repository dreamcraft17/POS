import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../ui/pos_theme.dart';
import '../../../services/printer_prefs.dart';
import 'package:flutter_usb_thermal_plugin/flutter_usb_thermal_plugin.dart';
import 'package:flutter_usb_thermal_plugin/model/usb_device_model.dart';
// Aktifkan plugin BT
import 'package:blue_thermal_printer/blue_thermal_printer.dart';

class PrinterSettingsPanel extends StatefulWidget {
  const PrinterSettingsPanel({
    super.key,
    required this.profilePrefix, // 'printer' | 'kitchen.printer'
    required this.titleOverride, // label judul panel
  });

  final String profilePrefix;
  final String titleOverride;

  @override
  State<PrinterSettingsPanel> createState() => _PrinterSettingsPanelState();
}

class _PrinterSettingsPanelState extends State<PrinterSettingsPanel> {
  late Future<PrinterPrefs> _loader;

  // Form controllers
  final ipCtrl = TextEditingController(text: '192.168.0.100');
  final portCtrl = TextEditingController(text: '9100');

  final btNameCtrl = TextEditingController();
  final btAddrCtrl = TextEditingController();

  final usbVidCtrl = TextEditingController(text: '0x0416');
  final usbPidCtrl = TextEditingController(text: '0x5011');

  String type = PrinterType.none.name; // 'none' | 'bluetooth' | 'network' | 'usb'
  String paper = '58';                 // '58' | '80'

  bool saving = false;
  bool testing = false;

  // supaya apply prefs cuma SEKALI
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    // ✅ load sesuai prefix agar panel independen
    _loader = PrinterPrefs.loadWithPrefix(widget.profilePrefix);
  }

  @override
  void dispose() {
    ipCtrl.dispose();
    portCtrl.dispose();
    btNameCtrl.dispose();
    btAddrCtrl.dispose();
    usbVidCtrl.dispose();
    usbPidCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply(PrinterPrefs pr) async {
    type = pr.type.name;
    paper = pr.paper;
    ipCtrl.text = pr.netIp;
    portCtrl.text = pr.netPort.toString();
    btNameCtrl.text = pr.btName;
    btAddrCtrl.text = pr.btAddress;
    usbVidCtrl.text = pr.usbVendorIdHex;
    usbPidCtrl.text = pr.usbProductIdHex;
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      // Validasi ringan
      if (type == 'network' && ipCtrl.text.trim().isEmpty) {
        throw 'IP Address harus diisi untuk Network printer';
      }
      if (type == 'bluetooth' &&
          btNameCtrl.text.trim().isEmpty &&
          btAddrCtrl.text.trim().isEmpty) {
        throw 'Isi Device Name atau MAC Address untuk Bluetooth printer';
      }
      if (type == 'usb' &&
          (usbVidCtrl.text.trim().isEmpty || usbPidCtrl.text.trim().isEmpty)) {
        throw 'Vendor ID dan Product ID harus diisi untuk USB printer';
      }

      final prefs = PrinterPrefs(
        type: PrinterTypeX.fromName(type),
        paper: paper,
        netIp: ipCtrl.text.trim(),
        netPort: int.tryParse(portCtrl.text.trim()) ?? 9100,
        btName: btNameCtrl.text.trim(),
        btAddress: btAddrCtrl.text.trim(),
        usbVendorIdHex: usbVidCtrl.text.trim(),
        usbProductIdHex: usbPidCtrl.text.trim(),
      );

      // ✅ simpan ke prefix yang sesuai (independen)
      await prefs.saveWithPrefix(widget.profilePrefix);

      // Sinkronkan state sekarang juga biar UI konsisten
      await _apply(prefs);
      if (mounted) setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Printer settings saved')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  // Tes cetak dummy (preview snackbar)
  Future<void> _testPrint() async {
    setState(() => testing = true);
    try {
      final now = DateTime.now();
      final sample = <String>[
        'MENZU POS',
        'Test Print',
        'Date: ${now.day.toString().padLeft(2,'0')}/${now.month.toString().padLeft(2,'0')}/${now.year} '
            '${now.hour.toString().padLeft(2,'0')}:${now.minute.toString().padLeft(2,'0')}',
        '------------------------------',
        'Nasi Goreng x1     Rp 20.000',
        'Teh Manis x2       Rp 10.000',
        '------------------------------',
        'TOTAL              Rp 40.000',
      ];
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test ticket:\n${sample.join('\n')}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Test print failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PrinterPrefs>(
      future: _loader,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final loaded = snap.data ?? PrinterPrefs.defaults();

        if (!_hydrated) {
          _hydrated = true;
          // panggil setelah frame supaya gak setState di tengah build
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            await _apply(loaded);
            if (mounted) setState(() {});
          });
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                const Icon(Icons.print_rounded, color: PosTheme.black),
                const SizedBox(width: 8),
                Text(
                  widget.titleOverride, // ✅ pakai judul dari caller
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: testing ? null : _testPrint,
                  icon: testing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.print_rounded),
                  label: Text(testing ? 'Testing...' : 'Test Print'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: saving ? null : _save,
                  icon: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_rounded),
                  label: Text(saving ? 'Saving...' : 'Save'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(),

            // Body
            Expanded(
              child: ListView(
                children: [
                  // Tipe + Paper
                  Row(
                    children: [
                      Expanded(child: _typePicker()),
                      const SizedBox(width: 12),
                      SizedBox(width: 220, child: _paperPicker()),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (ctx) {
                      switch (PrinterTypeX.fromName(type)) {
                        case PrinterType.network:
                          return _networkCard();
                        case PrinterType.bluetooth:
                          return _bluetoothCard();
                        case PrinterType.usb:
                          return _usbCard();
                        case PrinterType.none:
                          return _noneCard();
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _typePicker() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Printer Type',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: type,
          items: const [
            DropdownMenuItem(value: 'none', child: Text('Not Set')),
            DropdownMenuItem(value: 'network', child: Text('Network (TCP/IP)')),
            DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth')),
            DropdownMenuItem(value: 'usb', child: Text('USB OTG (Android)')),
          ],
          onChanged: (v) => setState(() => type = v ?? 'none'),
        ),
      ),
    );
  }

  Widget _paperPicker() {
    return InputDecorator(
      decoration: const InputDecoration(
        labelText: 'Paper Size',
        border: OutlineInputBorder(),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: paper,
          items: const [
            DropdownMenuItem(value: '58', child: Text('58 mm')),
            DropdownMenuItem(value: '80', child: Text('80 mm')),
          ],
          onChanged: (v) => setState(() => paper = v ?? '80'),
        ),
      ),
    );
  }

  Widget _noneCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Pilih tipe printer untuk mengatur koneksi. '
          'Setelah disimpan, proses print akan otomatis menggunakan printer ini.',
          style: TextStyle(color: Colors.black.withValues(alpha: .7)),
        ),
      ),
    );
  }

  Widget _networkCard() {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Network Printer (TCP/IP)', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: ipCtrl,
                    decoration: const InputDecoration(
                      labelText: 'IP Address',
                      hintText: 'e.g. 192.168.0.100',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: portCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Port',
                      hintText: '9100',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Kebanyakan printer LAN pakai port 9100 (RAW). Pastikan device dan HP berada di jaringan yang sama.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bluetoothCard() {
    final unsupported = kIsWeb || (!Platform.isAndroid && !Platform.isIOS);
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bluetooth Printer', style: TextStyle(fontWeight: FontWeight.w700)),
            if (unsupported) ...[
              const SizedBox(height: 8),
              const Text(
                'Bluetooth hanya didukung di Android/iOS.',
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: btNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Device Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: btAddrCtrl,
                    decoration: const InputDecoration(
                      labelText: 'MAC Address',
                      hintText: 'e.g. 00:11:22:33:44:55',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Isi salah satu (name/address) cukup. Kamu juga bisa pilih dari daftar perangkat yang sudah terpasang (paired).',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const SizedBox(height: 8),

            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: unsupported ? null : () async {
                  try {
                    final bt = BlueThermalPrinter.instance;
                    final bonded = await bt.getBondedDevices();
                    if (!mounted) return;
                    if (bonded.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Tidak ada perangkat Bluetooth ter-pair. Pair di Settings.')),
                      );
                      return;
                    }
                    showModalBottomSheet(
                      context: context,
                      builder: (_) => ListView(
                        children: bonded.map((d) => ListTile(
                          title: Text(d.name ?? '-'),
                          subtitle: Text(d.address ?? ''),
                          onTap: () {
                            btNameCtrl.text = d.name ?? '';
                            btAddrCtrl.text = d.address ?? '';
                            Navigator.pop(context);
                          },
                        )).toList(),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text('Scan gagal: $e')));
                  }
                },
                icon: const Icon(Icons.search),
                label: const Text('Scan Paired Devices'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Widget _usbCard() {
  //   final unsupported = kIsWeb || !Platform.isAndroid;
  //   return Card(
  //     elevation: 0,
  //     child: Padding(
  //       padding: const EdgeInsets.all(16),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           const Text('USB OTG (Android)', style: TextStyle(fontWeight: FontWeight.w700)),
  //           if (unsupported) ...[
  //             const SizedBox(height: 8),
  //             const Text(
  //               'USB OTG hanya didukung di Android.',
  //               style: TextStyle(fontSize: 12, color: Colors.redAccent),
  //             ),
  //           ],
  //           const SizedBox(height: 12),
  //           Row(
  //             children: [
  //               Expanded(
  //                 child: TextField(
  //                   controller: usbVidCtrl,
  //                   decoration: const InputDecoration(
  //                     labelText: 'Vendor ID (hex / decimal)',
  //                     hintText: '0x0416 atau 1046',
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   keyboardType: TextInputType.text,
  //                 ),
  //               ),
  //               const SizedBox(width: 12),
  //               Expanded(
  //                 child: TextField(
  //                   controller: usbPidCtrl,
  //                   decoration: const InputDecoration(
  //                     labelText: 'Product ID (hex / decimal)',
  //                     hintText: '0x5011 atau 20497',
  //                     border: OutlineInputBorder(),
  //                   ),
  //                   keyboardType: TextInputType.text,
  //                 ),
  //               ),
  //             ],
  //           ),
  //           const SizedBox(height: 8),
  //           const Text(
  //             'Kamu bisa lihat VID/PID dari Device Info / ADB / dokumentasi printer.',
  //             style: TextStyle(fontSize: 12, color: Colors.black54),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

  Widget _usbCard() {
  final unsupported = kIsWeb || !Platform.isAndroid;

  // helper kecil untuk format hex (mirip _asHex di ReceiptPrinter)
  String _asHex(dynamic v) {
    if (v == null) return '??';
    if (v is int) return '0x${v.toRadixString(16)}';
    final s = v.toString().trim();
    final sl = s.toLowerCase();
    if (sl.startsWith('0x')) return s;
    final i = int.tryParse(s);
    return (i != null) ? '0x${i.toRadixString(16)}' : s;
  }

  Future<void> _scanUsb() async {
    if (unsupported) return;
    try {
      final usb = FlutterUsbThermalPlugin();
      final List<UsbDevice> devices = await usb.getUSBDeviceList();

      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No USB devices detected. Check OTG/power/cable.')),
        );
        return;
      }

      await showModalBottomSheet(
        context: context,
        builder: (_) => SafeArea(
          child: ListView.separated(
            itemCount: devices.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final d = devices[i];
              final vid = _asHex(d.vendorId);
              final pid = _asHex(d.productId);
              return ListTile(
                leading: const Icon(Icons.usb),
                title: Text(d.productName),
                subtitle: Text('VID: $vid   PID: $pid'),
                onTap: () {
                  usbVidCtrl.text = vid;
                  usbPidCtrl.text = pid;
                  Navigator.pop(_);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Selected: ${d.productName}')),
                  );
                },
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Scan failed: $e')),
      );
    }
  }

  return Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('USB OTG (Android)', style: TextStyle(fontWeight: FontWeight.w700)),
          if (unsupported) ...[
            const SizedBox(height: 8),
            const Text(
              'USB OTG hanya didukung di Android.',
              style: TextStyle(fontSize: 12, color: Colors.redAccent),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: usbVidCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Vendor ID (hex / decimal)',
                    hintText: '0x0416 atau 1046',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: usbPidCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Product ID (hex / decimal)',
                    hintText: '0x5011 atau 20497',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: unsupported ? null : _scanUsb,
                icon: const Icon(Icons.usb),
                label: const Text('Scan USB Devices'),
              ),
              const SizedBox(width: 8),
              const Flexible(
                child: Text(
                  'Kamu bisa scan untuk auto-isi VID/PID atau lihat dari Device Info/ADB/dokumen printer.',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}



}
