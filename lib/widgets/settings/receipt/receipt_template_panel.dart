import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../providers/receipt_settings_provider.dart';
import '../../../widgets/bill_receipt.dart'; // for BillData & BillLine preview helpers
import '../../../utils/formatting.dart';

/// ===== ASCII separator helper (looks like printed receipt) =====
String _repeatChar(String ch, int len) => List.filled(len, ch).join();
Widget _asciiSeparatorUI({String ch = '=', required String paper}) {
  // 58mm ≈ 32 chars, 80mm ≈ 48 chars (approx)
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

class ReceiptTemplatePanel extends ConsumerStatefulWidget {
  const ReceiptTemplatePanel({super.key});
  @override
  ConsumerState<ReceiptTemplatePanel> createState() =>
      _ReceiptTemplatePanelState();
}

class _ReceiptTemplatePanelState extends ConsumerState<ReceiptTemplatePanel> {
  late TextEditingController _title;
  late TextEditingController _footer;
  late TextEditingController _taxLabel;
  late TextEditingController _social;
  bool _showSocialLogo = true;
  late TextEditingController _wifiSsid;
  late TextEditingController _wifiPass;
  bool _showWifi = true;

  String _dateFormat = 'dd/MM/yyyy HH:mm';
  bool _showOrderId = true;
  bool _showOrderType = true; // NEW
  bool _showPayment = true;
  bool _showSubtotal = true;
  bool _showTax = true;
  String _paper = '58';
  bool _centerTotal = false;
  double _cutFeed = 0;

  @override
  void initState() {
    super.initState();
    final s = ref.read(receiptSettingsProvider);
    _title = TextEditingController(text: s.title);
    _footer = TextEditingController(text: s.footer);
    _taxLabel = TextEditingController(text: s.taxLabel);
    _dateFormat = s.dateFormat;
    _showOrderId = s.showOrderId;
    _showPayment = s.showPayment;
    _showSubtotal = s.showSubtotal;
    _showTax = s.showTax;
    _paper = s.paper;
    _centerTotal = s.centerTotal;
    _cutFeed = s.cutFeed.toDouble();
    _social = TextEditingController(text: 'eecoffee.id');

    _showOrderType = true;
    _social = TextEditingController(text: 'eecoffee.id');
    SharedPreferences.getInstance().then((sp) {
      final savedText = sp.getString('receipt_social');
      final savedLogo = sp.getBool('receipt_social_logo');
      if (!mounted) return;
      setState(() {
        if (savedText != null) _social.text = savedText;
        _showSocialLogo = savedLogo ?? true;
      });
    });

    _wifiSsid = TextEditingController(text: '');
    _wifiPass = TextEditingController(text: '');
    SharedPreferences.getInstance().then((sp) {
      final ssid = sp.getString('receipt_wifi_ssid');
      final pass = sp.getString('receipt_wifi_pass');
      final show = sp.getBool('receipt_wifi_show');
      if (!mounted) return;
      setState(() {
        if (ssid != null) _wifiSsid.text = ssid;
        if (pass != null) _wifiPass.text = pass;
        _showWifi = show ?? true;
      });
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _footer.dispose();
    _taxLabel.dispose();
    _social.dispose();
    _wifiSsid.dispose();
    _wifiPass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = ReceiptSettings(
      title: _title.text.trim().isEmpty
          ? 'e+e Coffee Kitchen'
          : _title.text.trim(),
      footer: _footer.text.trim(),
      dateFormat: _dateFormat,
      showOrderId: _showOrderId,
      showPayment: _showPayment,
      showSubtotal: _showSubtotal,
      showTax: _showTax,
      taxLabel:
          _taxLabel.text.trim().isEmpty ? 'VAT (10%)' : _taxLabel.text.trim(),
      paper: _paper,
      centerTotal: _centerTotal,
      cutFeed: _cutFeed.round(),
    );
    await ref.read(receiptSettingsProvider.notifier).save(next);
    if (mounted) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('receipt_social', _social.text.trim());
      await sp.setBool('receipt_social_logo', _showSocialLogo);
      await sp.setString('receipt_wifi_ssid', _wifiSsid.text.trim());
      await sp.setString('receipt_wifi_pass', _wifiPass.text.trim());
      await sp.setBool('receipt_wifi_show', _showWifi);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Receipt template saved')),
      );
      setState(() {}); // refresh preview
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(receiptSettingsProvider);

    // Sample preview data (doesn’t affect real data)
    // final sample = BillData(
    //   title: _title.text.isEmpty ? s.title : _title.text,
    //   // NEW: contoh info toko (nanti real dari display_name user login saat cetak nyata)
    //   storeInfo: 'PT E+E Coffee — Jl. Melati No. 12, Bandung',
    //   date: DateTime.now(),
    //   items: const [
    //     BillLine(name: 'Cappuccino', qty: 1, priceCentsEach: 25000),
    //     BillLine(name: 'Grilled Bread', qty: 2, priceCentsEach: 12000),
    //   ],
    //   subtotal: 49000,
    //   discount: 0, // BillData requires 'discount'
    //   tax: 5390,
    //   total: 54390,
    //   orderId: _showOrderId ? '12345' : null,
    //   orderTypeName: _showOrderType ? 'Dine-in' : null, // NEW: show sample type
    //   paymentSummary: _showPayment ? 'QRIS BCA' : null,
    //   paymentLines: null,
    //   footer: _footer.text.isEmpty ? s.footer : _footer.text,
    // );

    final sample = BillData(
      title: _title.text.isEmpty ? s.title : _title.text,
      date: DateTime.now(), // ← storeInfo dihapus
      items: const [
        BillLine(name: 'Cappuccino', qty: 1, priceCentsEach: 25000),
        BillLine(name: 'Grilled Bread', qty: 2, priceCentsEach: 12000),
      ],
      subtotal: 49000,
      discount: 0,
      tax: 5390,
      total: 54390,
      orderId: _showOrderId ? '12345' : null,
      orderTypeName: _showOrderType ? 'Dine-in' : null,
      paymentSummary: _showPayment ? 'QRIS BCA' : null,
      paymentLines: null,
      footer: _footer.text.isEmpty ? s.footer : _footer.text,
    );

    return LayoutBuilder(
      builder: (ctx, c) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: form
            Expanded(
              flex: 2,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  const Text('Receipt Template',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Header Title',
                      hintText: 'e.g. e+e Coffee Kitchen',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _footer,
                    decoration: const InputDecoration(
                      labelText: 'Footer',
                      hintText: 'e.g. thank you',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _social,
                    decoration: const InputDecoration(
                      labelText: 'Social / Instagram line',
                      hintText: 'Instagram: eecoffee.id',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _showSocialLogo,
                    onChanged: (v) => setState(() => _showSocialLogo = v),
                    title: const Text('Show Instagram logo on receipt'),
                  ),
                  const SizedBox(height: 12),
                  Text('Wi-Fi (untuk ditampilkan di struk)',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _wifiSsid,
                    decoration: const InputDecoration(
                      labelText: 'Wi-Fi SSID (opsional)',
                      hintText: 'e.g. ee-coffee-free',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  StatefulBuilder(
                    builder: (ctx, setSt) {
                      // gunakan ValueNotifier kecil kalau mau, tapi simple aja:
                      return TextField(
                        controller: _wifiPass,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Wi-Fi Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            tooltip: 'Show/Hide',
                            onPressed: () {
                              // simple trick: rebuild parent setState untuk toggle
                              setState(() {}); // biar rebuild
                            },
                            icon: const Icon(Icons.visibility),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      );
                    },
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _showWifi,
                    onChanged: (v) => setState(() => _showWifi = v),
                    title: const Text('Show Wi-Fi on receipt'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _dateFormat,
                    decoration: const InputDecoration(
                      labelText: 'Date format',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'dd/MM/yyyy HH:mm',
                          child: Text('dd/MM/yyyy HH:mm')),
                      DropdownMenuItem(
                          value: 'yyyy-MM-dd HH:mm',
                          child: Text('yyyy-MM-dd HH:mm')),
                      DropdownMenuItem(
                          value: 'dd MMM yyyy HH:mm',
                          child: Text('dd MMM yyyy HH:mm')),
                    ],
                    onChanged: (v) =>
                        setState(() => _dateFormat = v ?? _dateFormat),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _paper,
                          decoration: const InputDecoration(
                            labelText: 'Paper size',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: '58', child: Text('58 mm')),
                            DropdownMenuItem(value: '80', child: Text('80 mm')),
                          ],
                          onChanged: (v) => setState(() => _paper = v ?? '80'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _taxLabel,
                          decoration: const InputDecoration(
                            labelText: 'Tax label',
                            hintText: 'VAT (10%)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    runSpacing: 6,
                    children: [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showOrderId,
                        onChanged: (v) => setState(() => _showOrderId = v),
                        title: const Text('Show Order ID'),
                      ),
                      // NEW: Show Order Type
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showOrderType,
                        onChanged: (v) => setState(() => _showOrderType = v),
                        title: const Text('Show Order Type'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showPayment,
                        onChanged: (v) => setState(() => _showPayment = v),
                        title: const Text('Show Payment method'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showSubtotal,
                        onChanged: (v) => setState(() => _showSubtotal = v),
                        title: const Text('Show Subtotal'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _showTax,
                        onChanged: (v) => setState(() => _showTax = v),
                        title: const Text('Show Tax line'),
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _centerTotal,
                        onChanged: (v) => setState(() => _centerTotal = v),
                        title: const Text('Center BIG TOTAL'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Text('Cut/Feed lines'),
                      Expanded(
                        child: Slider(
                          min: 0,
                          max: 5,
                          divisions: 5,
                          value: _cutFeed,
                          label: _cutFeed.round().toString(),
                          onChanged: (v) => setState(() => _cutFeed = v),
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: Text('${_cutFeed.round()}'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setState(() {
                              final d = ReceiptSettings.def;
                              _title.text = d.title;
                              _footer.text = d.footer;
                              _dateFormat = d.dateFormat;
                              _showOrderId = d.showOrderId;
                              _showOrderType =
                                  true; // keep previewing type by default
                              _showPayment = d.showPayment;
                              _showSubtotal = d.showSubtotal;
                              _showTax = d.showTax;
                              _taxLabel.text = d.taxLabel;
                              _paper = d.paper;
                              _centerTotal = d.centerTotal;
                              _cutFeed = d.cutFeed.toDouble();
                            });
                          },
                          child: const Text('Reset to default'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Right: live preview
            Expanded(
              child: Card(
                margin: const EdgeInsets.all(12),
                surfaceTintColor: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (ctx, c) {
                      // Simulated paper width: 58mm ~ 240px; 80mm ~ 320px (approx)
                      final paperWidth = (_paper == '80') ? 320.0 : 240.0;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.max,
                        children: [
                          const Text('Preview',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 12),
                          Expanded(
                            child: SingleChildScrollView(
                              child: Center(
                                child: Container(
                                  width: paperWidth,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    border: Border.all(color: Colors.black12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: _ReceiptPreview(
                                    data: sample,
                                    showSubtotal: _showSubtotal,
                                    showTax: _showTax,
                                    taxLabel: _taxLabel.text.isEmpty
                                        ? 'VAT (10%)'
                                        : _taxLabel.text,
                                    dateFormat: _dateFormat,
                                    centerTotal: _centerTotal,
                                    paper: _paper,
                                    socialText: _social.text,
                                    showSocialLogo: _showSocialLogo,
                                    wifiSsid: _wifiSsid.text,
                                    wifiPass: _wifiPass.text,
                                    showWifi: _showWifi,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Paper: ${_paper}mm   •   Cut/Feed: ${_cutFeed.round()}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.black54),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ReceiptPreview extends StatelessWidget {
  const _ReceiptPreview({
    required this.data,
    required this.showSubtotal,
    required this.showTax,
    required this.taxLabel,
    required this.dateFormat,
    required this.centerTotal,
    required this.paper,
    required this.socialText,
    required this.showSocialLogo,
    required this.wifiSsid,
    required this.wifiPass,
    required this.showWifi,
  });
  final BillData data;
  final bool showSubtotal;
  final bool showTax;
  final String taxLabel;
  final String dateFormat;
  final bool centerTotal;
  final String paper;
  final String socialText;
  final bool showSocialLogo;
  final String wifiSsid;
  final String wifiPass;
  final bool showWifi;

  @override
  Widget build(BuildContext context) {
    final dt = data.date;
    final dateStr = _fmt(dt, dateFormat);

    final hasOrder = (data.orderId ?? '').isNotEmpty;
    final hasType = (data.orderTypeName ?? '').isNotEmpty;

    return DefaultTextStyle(
      style: Theme.of(context).textTheme.bodyMedium!,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Text(
          //   data.title,
          //   textAlign: TextAlign.center,
          //   style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          // ),

          Center(
            child: Image.asset(
              'assets/receipt/logo_bill.png',
              height: 56,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => Text(
                data.title,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ),
          ),
          // NEW: baris info toko tepat di bawah title
          if ((data.storeInfo ?? '').isNotEmpty)
            Text(
              data.storeInfo!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12),
            ),

          Text('Date: $dateStr', textAlign: TextAlign.center),

          if (hasOrder)
            Text('Order: #${data.orderId}', textAlign: TextAlign.center),
          if (hasOrder && hasType)
            _asciiSeparatorUI(
                paper: paper), // ==== separator between Order & Type
          if (hasType)
            Text('Type: ${data.orderTypeName}', textAlign: TextAlign.center),

          // ==== header -> items
          _asciiSeparatorUI(paper: paper),

          // ...data.items.expand((it) => [
          //       Text('${it.name} x${it.qty}'),
          //       Row(
          //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
          //         children: [
          //           Text('  ${rp(it.priceCentsEach)}'),
          //           Text(rp(it.lineTotal))
          //         ],
          //       ),
          //     ]),
          ...data.items.map((it) => Row(
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
              )),

          // ==== items -> totals
          _asciiSeparatorUI(paper: paper),

          if (showSubtotal) _row('Subtotal', rp(data.subtotal)),
          // if (data.discount > 0) _row('Discount', '-${rp(data.discount)}'), // sample discount off by default
          if (showTax) _row(taxLabel, rp(data.tax)),
          if (!centerTotal)
            _row('TOTAL', rp(data.total), big: true, bold: true)
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                rp(data.total),
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ),

          if ((data.paymentSummary?.isNotEmpty ?? false) ||
              (data.paymentLines?.isNotEmpty ?? false)) ...[
            // ==== totals -> payment
            _asciiSeparatorUI(paper: paper),
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
          Text(data.footer ?? '', textAlign: TextAlign.center),
          if (socialText.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (showSocialLogo)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Image.asset(
                      'assets/receipt/instagram_mono.png',
                      width: 14,
                      height: 14,
                      fit: BoxFit.contain,
                    ),
                  ),
                Flexible(
                  child: Text(
                    socialText.trim(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                ),
              ],
            ),
          ],
          if (showWifi && wifiPass.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              wifiSsid.trim().isNotEmpty
                  ? 'Wi-Fi: ${wifiSsid.trim()}  •  Password: ${wifiPass.trim()}'
                  : 'Wi-Fi Password: ${wifiPass.trim()}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
          ],
        ],
      ),
    );
  }

  String _fmt(DateTime d, String f) {
    // simple formatter (no intl)
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = '${d.year}';
    final HH = d.hour.toString().padLeft(2, '0');
    final MM = d.minute.toString().padLeft(2, '0');

    // English month names
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
        ));
  }
}
