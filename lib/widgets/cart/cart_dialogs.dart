import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../offline/sync_service.dart';
import '../../providers/auth_providers.dart';
import '../../providers/cart_provider.dart';
import '../../providers/discount_providers.dart';
import '../../providers/order_type_providers.dart';
import '../../providers/products_provider.dart';
import '../../repositories/open_bills_repo.dart';
import '../../repositories/orders_repo.dart';
import '../../services/api_service.dart';
import '../../ui/pos_theme.dart';
import '../../ui/top_message.dart';
import '../../utils/formatting.dart';
import '../bill_receipt.dart';
import 'cart_helpers.dart';
import 'cart_ui_shared.dart';
// ===================== PAYMENT DIALOG (OFFLINE-FIRST) =====================
Future<void> showCartPayDialog(
  BuildContext context,
  WidgetRef ref, {
  required int cartTotalCents,
  required double taxRate, // 0.0-1.0
  required String taxLabel,
}) async {
  final api = ApiService.shared();
  final methods = await api.paymentMethods();
  final enabled =
      methods.where((m) => m['enabled'] == true || m['enabled'] == 1).toList();
  if (enabled.isEmpty) {
    if (context.mounted) {
      showTopError(context, 'no payment methods enabled');
    }
    return;
  }

  String selected = (enabled.first['code'] as String);
  bool saving = false;

  await showGeneralDialog(
    context: context,
    barrierLabel: 'Payment',
    barrierDismissible: !saving,
    barrierColor: Colors.black.withValues(alpha: 0.30),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (_, __, ___) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, secAnim, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      return Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
              child: const SizedBox.shrink(),
            ),
          ),
          Center(
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: .98, end: 1).animate(curved),
                child: Material(
                  type: MaterialType.transparency,
                  child: CartGlassCard(
                    child: LayoutBuilder(
                      builder: (ctx, cons) {
                        final maxH = MediaQuery.of(ctx).size.height * 0.85;
                        return ConstrainedBox(
                          constraints:
                              BoxConstraints(maxWidth: 520, maxHeight: maxH),
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(
                                left: 16, right: 16, bottom: 12, top: 12),
                            child: StatefulBuilder(
                              builder: (ctx, setState) {
                                // ===== Live order summary from state =====
                                final cartNow = ref.read(cartProvider);
                                final selectedDisc =
                                    ref.read(selectedDiscountProvider);
                                final subtotalNow = cartNow.fold<int>(
                                    0, (s, it) => s + it.priceCents * it.qty);
                                int discountNow = 0;
                                if (selectedDisc != null) {
                                  discountNow =
                                      selectedDisc.kind.name == 'percent'
                                          ? (subtotalNow *
                                                  (selectedDisc.value / 100))
                                              .round()
                                          : selectedDisc.value.round();
                                  if (discountNow < 0) discountNow = 0;
                                  if (discountNow > subtotalNow) {
                                    discountNow = subtotalNow;
                                  }
                                }
                                final taxableBaseNow =
                                    (subtotalNow - discountNow)
                                        .clamp(0, 1 << 31);
                                final taxNow =
                                    (taxableBaseNow * taxRate).round();
                                final totalNow = taxableBaseNow + taxNow;


                                Future<void> doPay() async {
                                  if (saving) return;
                                  setState(() => saving = true);
                                  try {
                                    final repo = OrdersRepo();
                                    final cart = ref.read(cartProvider);
                                    final selectedDiscount =
                                        ref.read(selectedDiscountProvider);
                                    final selectedOrderTypeCode =
                                        ref.read(selectedOrderTypeCodeProvider);
                                    final orderTypeName = ref
                                        .read(effectiveOrderTypeNameProvider);
                                    final user = ref
                                        .read(authControllerProvider)
                                        .valueOrNull;
                                    final storeTitle = receiptStoreTitle(ref);

                                    // --- Nama metode payment (human readable)
                                    String methodName = selected.toUpperCase();
                                    final found = enabled.firstWhere(
                                      (m) => m['code'] == selected,
                                      orElse: () => {},
                                    );
                                    if (found is Map &&
                                        (found['name']?.toString().isNotEmpty ??
                                            false)) {
                                      methodName = found['name'];
                                    }

                                    // --- Kalkulasi server-aligned (dinamis) ---
                                    final subtotalCents = cart.fold<int>(0,
                                        (x, it) => x + it.priceCents * it.qty);

                                    int discountCents = 0;
                                    Map<String, dynamic>? discountPayload;

                                    if (selectedDiscount != null) {
                                      if (selectedDiscount.code.isNotEmpty) {
                                        // ambil diskon dari API biar valid
                                        final list = await api.discounts();
                                        final m = list.cast<Map>().firstWhere(
                                              (e) =>
                                                  (e['code'] ?? '') ==
                                                      selectedDiscount.code &&
                                                  (e['enabled'] == 1 ||
                                                      e['enabled'] == true),
                                              orElse: () => {},
                                            );
                                        if (m.isNotEmpty) {
                                          final kind =
                                              (m['kind'] ?? '').toString();
                                          final val = (m['value'] is int)
                                              ? (m['value'] as int).toDouble()
                                              : (m['value'] as num).toDouble();
                                          discountPayload = {'code': m['code']};
                                          discountCents = (kind == 'percent')
                                              ? (subtotalCents * (val / 100))
                                                  .round()
                                              : val.round();
                                        }
                                      } else {
                                        discountPayload = {
                                          'kind': selectedDiscount.kind.name,
                                          'value': selectedDiscount.value,
                                        };
                                        discountCents = (selectedDiscount
                                                    .kind.name ==
                                                'percent')
                                            ? (subtotalCents *
                                                    (selectedDiscount.value /
                                                        100))
                                                .round()
                                            : selectedDiscount.value.round();
                                      }
                                      if (discountCents < 0) discountCents = 0;
                                      if (discountCents > subtotalCents)
                                        discountCents = subtotalCents;
                                    }

                                    final taxableBase =
                                        (subtotalCents - discountCents)
                                            .clamp(0, 1 << 31);
                                    final taxCents = (taxableBase * taxRate)
                                        .round(); // taxRate dari scope dialog
                                    final serverExpectedTotal =
                                        taxableBase + taxCents;

                                    // --- Payload order untuk server ---
                                    final orderPayload = {
                                      'items': cart
                                          .map(itemToPayload)
                                          .toList(), // kirim SKU/menu ke server
                                      'tax_rate': taxRate,
                                      'discount': discountPayload,
                                      'payments': [
                                        {
                                          'method': selected,
                                          'amount_cents': serverExpectedTotal,
                                        }
                                      ],
                                      if ((selectedOrderTypeCode ?? '')
                                          .isNotEmpty)
                                        'order_type': selectedOrderTypeCode,
                                    };

                                    // --- baca tableName (customer name) dari draft aktif (jika ada) ---
                                    final sp =
                                        await SharedPreferences.getInstance();
                                    String? tableName;
                                    final activePayloadStr = sp
                                        .getString('pos.active.draft.payload');
                                    if (activePayloadStr != null) {
                                      try {
                                        final m = Map<String, dynamic>.from(
                                            jsonDecode(activePayloadStr));
                                        final nm = (m['customer_name'] ?? '')
                                            .toString()
                                            .trim();
                                        if (nm.isNotEmpty) tableName = nm;
                                      } catch (_) {}
                                    }

                                    // --- offline-first call ---
                                    final res = await repo
                                        .createOrderSmart(orderPayload);
                                    final orderIdStr = res['id']?.toString();

                                    // --- build BillData (untuk receipt & dialog sukses) ---
                                    final bill = BillData(
                                      title: '',
                                      date: DateTime.now(),
                                      items: cart
                                          .map((e) => BillLine(
                                                name: e.name,
                                                qty: e.qty,
                                                priceCentsEach: e.priceCents,
                                              ))
                                          .toList(),
                                      subtotal: subtotalCents,
                                      discount: discountCents,
                                      tax: taxCents,
                                      total: serverExpectedTotal,
                                      footer: '',
                                      orderId: orderIdStr,
                                      orderTypeName: orderTypeName,
                                      paymentSummary: methodName,
                                      tableName: tableName,
                                    );

                                    if (context.mounted) {
                                      Navigator.pop(ctx); // tutup Payment modal
                                    }

                                    // =========================
                                    //  CETAK RECEIPT CUSTOMER
                                    // =========================
                                    // Nota receipt ke profil 'printer' (customer)
                                    await ReceiptPrinter.printWithSavedPrefs(
                                        context,
                                        bill);

                                    // =========================
                                    //  CETAK NEW ORDER (QUEUE)
                                    // =========================

                                    // 1) CUSTOMER: cetak semua item sebagai NEW ORDER ke printer customer
                                    final cashierName =
                                        (user?.displayName?.isNotEmpty ?? false)
                                            ? user!.displayName!
                                            : (user?.username ?? '-');

                                    final queueNo = (orderIdStr != null &&
                                            orderIdStr.isNotEmpty)
                                        ? orderIdStr
                                        : await nextLocalQueueNo();

                                    final typeMap =
                                        await buildMenuTypeMap();
                                    final customerItems = queueItemsAll(
                                        cart);

                                    final customerTicket = QueueTicketData(
                                      queueNo: queueNo,
                                      dateTime: DateTime.now(),
                                      storeName: storeTitle,
                                      userName: cashierName,
                                      orderType: orderTypeName,
                                      items: customerItems,
                                      tableName: tableName,
                                    );

                                    // format queue Ã¢â‚¬Å“NEW ORDERÃ¢â‚¬Â ke PRINTER CUSTOMER
                                    await ReceiptPrinter
                                        .printKitchenOnCustomerPrinter(context,
                                            customerTicket);

                                    // 2) KITCHEN: semua SELAIN drink
                                    final kitchenItems = queueItemsFor(
                                      cart,
                                      typeMap,
                                      (t) => t != 'drink',
                                    );

                                    if (kitchenItems.isNotEmpty) {
                                      final kitchenTicket = QueueTicketData(
                                        queueNo: queueNo,
                                        dateTime: DateTime.now(),
                                        storeName: storeTitle,
                                        userName: cashierName,
                                        orderType: orderTypeName,
                                        items: kitchenItems,
                                        tableName: tableName,
                                      );
                                      try {
                                        await ReceiptPrinter
                                            .printKitchenWithSavedPrefs(context,
                                                kitchenTicket);
                                      } catch (_) {}
                                    }

                                    // 3) BAR: hanya drink
                                    final barItems = queueItemsFor(
                                      cart,
                                      typeMap,
                                      (t) => t == 'drink',
                                    );

                                    if (barItems.isNotEmpty) {
                                      final barTicket = QueueTicketData(
                                        queueNo: queueNo,
                                        dateTime: DateTime.now(),
                                        storeName: storeTitle,
                                        userName: cashierName,
                                        orderType: orderTypeName,
                                        items: barItems,
                                        tableName: tableName,
                                      );
                                      try {
                                        await ReceiptPrinter.printBarWithSavedPrefs(
                                            context,
                                            barTicket);
                                      } catch (_) {}
                                    }

                                    // ====== MOVE OPEN Ã¢â€ â€™ DONE (seperti semula) ======
                                    try {
                                      final activeId =
                                          sp.getString('pos.active.draft.id');
                                      final activePayloadStr2 = sp.getString(
                                          'pos.active.draft.payload');

                                      if (activeId != null &&
                                          activePayloadStr2 != null) {
                                        final repoOB = OpenBillsRepo();

                                        // hapus dari Open
                                        await repoOB.removeDraft(activeId);

                                        // siapkan payload Done
                                        final draft = Map<String, dynamic>.from(
                                            jsonDecode(activePayloadStr2));
                                        final items =
                                            draft['items'] as List? ?? const [];

                                        await repoOB.addDone({
                                          'id': activeId,
                                          'order_id': orderIdStr ?? '',
                                          'customer_name':
                                              draft['customer_name'] ?? '',
                                          'items': items,
                                          'total_cents': serverExpectedTotal,
                                          'payment_method': methodName,
                                          'paid_at':
                                              DateTime.now().toIso8601String(),
                                          'synced': (res['remote'] == true),
                                        });

                                        await sp.remove('pos.active.draft.id');
                                        await sp
                                            .remove('pos.active.draft.payload');
                                      }
                                    } catch (_) {}

                                    // bersihkan state
                                    await ref
                                        .read(cartProvider.notifier)
                                        .clear();
                                    ref
                                        .read(selectedDiscountProvider.notifier)
                                        .state = null;
                                    ref.invalidate(productsProvider);

                                    // feedback UI
                                    if (context.mounted) {
                                      if (res['remote'] != true) {
                                        unawaited(requestBackgroundSync());
                                        showTopMessage(context,
                                            'order saved offline Ã¢â‚¬â€ will sync when online');
                                      }
                                      await showCartPaymentSuccess(
                                        context: context,
                                        ref: ref,
                                        bill: bill,
                                        taxLabel:
                                            taxLabel, // sudah ada di scope dialog
                                      );
                                    }
                                  } on DioException catch (e) {
                                    setState(() => saving = false);
                                    final code = e.response?.statusCode ?? 0;
                                    if (code != 503) {
                                      if (context.mounted) {
                                        showTopError(context,
                                            'payment failed: ${e.message}');
                                      }
                                    }
                                  } catch (e) {
                                    setState(() => saving = false);
                                    if (context.mounted) {
                                      showTopError(
                                          context, 'payment failed: $e');
                                    }
                                  }
                                }

                                // ========== UI dialog ==========
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    const SizedBox(height: 6),
                                    Row(
                                      children: const [
                                        Icon(Icons.payment,
                                            size: 28, color: Colors.black87),
                                        SizedBox(width: 10),
                                        Text(
                                          'Payment',
                                          style: TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w700,
                                            color: PosTheme.black,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // ---- Payment method chips ----
                                    const Text(
                                      "Select payment method",
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final m in enabled)
                                          ChoiceChip(
                                            label: Text(m['name'] ?? m['code']),
                                            selected: selected == m['code'],
                                            onSelected: saving
                                                ? null
                                                : (_) => setState(
                                                    () => selected = m['code']),
                                            selectedColor: Colors.black,
                                            labelStyle: TextStyle(
                                              color: selected == m['code']
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                            backgroundColor:
                                                Colors.grey.shade200,
                                          ),
                                      ],
                                    ),

                                    const SizedBox(height: 16),

                                    // ---- Order summary ----
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.black12.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        children: [
                                          cartSumRow('Subtotal', subtotalNow),
                                          cartSumRow('Discount', -discountNow),
                                          cartSumRow(taxLabel, taxNow), // dinamis
                                          const Divider(),
                                          cartSumRowBold('Total', totalNow),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // ---- Actions ----
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton(
                                            onPressed: saving
                                                ? null
                                                : () => Navigator.pop(ctx),
                                            child: const Text('Cancel'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton(
                                            onPressed: saving ? null : doPay,
                                            child: saving
                                                ? const SizedBox(
                                                    height: 18,
                                                    width: 18,
                                                    child:
                                                        CircularProgressIndicator
                                                            .adaptive(
                                                                strokeWidth: 2),
                                                  )
                                                : const Text(
                                                    'Confirm and Print'),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                  ],
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

Future<void> showCartSplitDialog(
  BuildContext context,
  WidgetRef ref, {
  required int cartTotalCents,
  required double taxRate, // 0.0-1.0
  required String taxLabel,
}) async {
  final cart = ref.read(cartProvider);
  if (cart.isEmpty) return;

  // --- calculate subtotal/discount/tax exactly like in CartPanel ---
  final selectedDisc = ref.read(selectedDiscountProvider);
  final subtotal = cart.fold<int>(0, (s, it) => s + it.priceCents * it.qty);

  int discount = 0;
  if (selectedDisc != null) {
    discount = selectedDisc.kind.name == 'percent'
        ? (subtotal * (selectedDisc.value / 100)).round()
        : selectedDisc.value.round();
    if (discount < 0) discount = 0;
    if (discount > subtotal) discount = subtotal;
  }
  final taxableBase = (subtotal - discount).clamp(0, 1 << 31);
  final tax = (taxableBase * taxRate).round(); // dinamis
  final total = taxableBase + tax;

  int people = 2;

  List<int> _splitEven(int total, int n) {
    if (n <= 1) return [total];
    final base = (total / n).floor();
    final rem = total - base * n;
    return List<int>.generate(n, (i) => base + (i < rem ? 1 : 0));
  }

  await showDialog(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          List<int> amounts = _splitEven(total, people); // cents
          List<bool> locked = List<bool>.filled(people, false);

          void _resize(int newPeople) {
            newPeople = newPeople.clamp(1, 50);
            if (newPeople == people) return;
            people = newPeople;
            amounts = _splitEven(total, people);
            locked = List<bool>.filled(people, false);
            setState(() {});
          }

          int diff() => total - amounts.fold<int>(0, (s, v) => s + v);

          void _equalSplit() {
            amounts = _splitEven(total, people);
            locked = List<bool>.filled(people, false);
            setState(() {});
          }

          void _autoBalance() {
            int remaining = diff();
            final idxs = [
              for (int i = 0; i < people; i++)
                if (!locked[i]) i
            ];
            if (idxs.isEmpty) return;

            final n = idxs.length;
            final base = (remaining / n).truncate();
            final rem = remaining - base * n;

            for (final i in idxs) {
              amounts[i] += base;
            }
            final sign = remaining.sign;
            for (int k = 0; k < rem.abs(); k++) {
              final i = idxs[k % n];
              amounts[i] += sign;
            }
            setState(() {});
          }

          Future<void> printOne(int idx) async {
            if (diff() != 0) return;
            final orderTypeName = ref.read(effectiveOrderTypeNameProvider);

            final sp = await SharedPreferences.getInstance();
            String? tableName;
            final activePayloadStr = sp.getString('pos.active.draft.payload');

            if (activePayloadStr != null) {
              try {
                final m =
                    Map<String, dynamic>.from(jsonDecode(activePayloadStr));
                final nm = (m['customer_name'] ?? '').toString().trim();
                if (nm.isNotEmpty) tableName = nm;
              } catch (_) {}
            }

            final bill = BillData(
              title: '',
              date: DateTime.now(),
              items: cart
                  .map((e) => BillLine(
                        name: e.name,
                        qty: e.qty,
                        priceCentsEach: e.priceCents,
                      ))
                  .toList(),
              subtotal: subtotal,
              discount: discount,
              tax: tax,
              total: amounts[idx],
              footer: 'Split ${idx + 1} of $people',
              orderId: null,
              orderTypeName: orderTypeName,
              paymentSummary: 'SPLIT #${idx + 1}',
              tableName: tableName,
            );
            await ReceiptPrinter.printWithSavedPrefs(context, bill);
          }

          Future<void> printAll() async {
            if (diff() != 0) return;
            for (var i = 0; i < amounts.length; i++) {
              await printOne(i);
            }
            if (context.mounted) Navigator.pop(ctx);
          }

          Widget _personRow(int i) {
            final controller =
                TextEditingController(text: amounts[i].toString());
            return Row(
              children: [
                IconButton(
                  icon: Icon(locked[i] ? Icons.lock : Icons.lock_open),
                  onPressed: () => setState(() => locked[i] = !locked[i]),
                ),
                Expanded(child: Text('Person ${i + 1}')),
                SizedBox(
                  width: 140,
                  child: TextFormField(
                    controller: controller,
                    textAlign: TextAlign.right,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Cents',
                      helperText: rp(amounts[i]),
                      isDense: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    onChanged: (s) {
                      final v = int.tryParse(s) ?? amounts[i];
                      setState(() => amounts[i] = v.clamp(0, 1 << 31));
                    },
                  ),
                ),
              ],
            );
          }

          final _diff = diff();
          final canPrint = _diff == 0;

          return AlertDialog(
            title: const Text('Split Bill'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Text('People'),
                      IconButton(
                        onPressed: () => _resize(people - 1),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      Text('$people'),
                      IconButton(
                        onPressed: () => _resize(people + 1),
                        icon: const Icon(Icons.add_circle_outline),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: _equalSplit,
                        child: const Text('Equal Split'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: _autoBalance,
                        child: const Text('Auto-Balance'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black12.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Column(
                      children: [
                        cartSumRow('Grand total', total),
                        Row(
                          children: [
                            const Text('Distributed'),
                            const Spacer(),
                            Text(rp(amounts.fold<int>(0, (s, v) => s + v))),
                          ],
                        ),
                        Row(
                          children: [
                            const Text('Difference'),
                            const Spacer(),
                            Text(
                              _diff == 0
                                  ? 'OK'
                                  : (_diff > 0
                                      ? '+${rp(_diff)} not distributed'
                                      : '${rp(_diff)} over-distributed'),
                              style: TextStyle(
                                color: _diff == 0 ? Colors.green : Colors.red,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (var i = 0; i < people; i++) ...[
                    _personRow(i),
                    const Divider(height: 12),
                  ],
                  const Text(
                    'Tip: lock people whose amounts are fixed, then press Auto-Balance to adjust the remainder across the others.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
              OutlinedButton.icon(
                onPressed: canPrint ? () async => await printOne(0) : null,
                icon: const Icon(Icons.print),
                label: const Text('Print Selected (index 1)'),
              ),
              FilledButton.icon(
                onPressed: canPrint ? printAll : null,
                icon: const Icon(Icons.print),
                label: const Text('Print All'),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> printKitchenFromBill(BuildContext context, WidgetRef ref,
    {required BillData bill}) async {
  try {
    // Attempt to read cashier/user name from auth provider
    String cashier = 'Cashier';
    try {
      final auth = ref.read(authControllerProvider);
      final dyn = auth as dynamic;
      cashier = (dyn?.name ??
              dyn?.fullName ??
              dyn?.username ??
              dyn?.email ??
              'Cashier')
          .toString();
    } catch (_) {}

    // Pakai orderId server kalau sudah ada; kalau belum, pakai nomor antrian lokal
    final queueNo = (bill.orderId?.isNotEmpty == true)
        ? bill.orderId!
        : await nextLocalQueueNo();

    final queue = QueueTicketData(
      queueNo: queueNo,
      dateTime: bill.date,
      storeName: receiptStoreTitle(ref),
      userName: cashier,
      orderType: bill.orderTypeName ?? '-',
      items: bill.items
          .map((it) => QueueItem(name: it.name, qty: it.qty))
          .toList(),
      tableName: bill.tableName,
    );

    await ReceiptPrinter.printKitchenWithSavedPrefs(context, queue);
    if (context.mounted) {
      showTopMessage(context, 'printed to Kitchen');
    }
  } catch (e) {
    if (context.mounted) {
      showTopError(context, 'failed to print to Kitchen: $e');
    }
  }
}

Future<void> showCartPaymentSuccess({
  required BuildContext context,
  required WidgetRef ref,
  required BillData bill,
  String? taxLabel, // NEW
}) async {
  final label = taxLabel ?? 'Tax';
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 64),
              const SizedBox(height: 12),
              const Text(
                "Payment Successful!",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              if ((bill.orderId ?? '').isNotEmpty)
                Text(
                  "Order #${bill.orderId}",
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              if ((bill.paymentSummary ?? '').isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  bill.paymentSummary!,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
              ],
              const SizedBox(height: 16),

              // ================= Items + Totals =================
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      // ----- Items -----
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.black12.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: const [
                                Expanded(
                                  child: Text(
                                    'Items',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                      color: PosTheme.black,
                                    ),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Amount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: PosTheme.muted,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final it in bill.items) ...[
                              cartReceiptRow(
                                '${it.name} Ãƒâ€” ${it.qty}',
                                rp(it.priceCentsEach * it.qty),
                              ),
                            ],
                            const Divider(),
                            cartReceiptRow('Subtotal', rp(bill.subtotal)),
                            if ((bill.discount) > 0)
                              cartReceiptRow('Discount', rp(-bill.discount),
                                  isAccent: true),
                            cartReceiptRow(label, rp(bill.tax)), // dinamis
                            const SizedBox(height: 4),
                            cartReceiptRow(
                              'Total',
                              rp(bill.total),
                              isBold: true,
                              big: true,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: const Text("Close"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () async {
                        await ReceiptPrinter.printWithSavedPrefs(context, bill);
                      },
                      child: const Text("Print Again"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.restaurant_menu_outlined),
                  onPressed: () async {
                    await printKitchenFromBill(context, ref, bill: bill);
                  },
                  label: const Text("Print for Kitchen"),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
