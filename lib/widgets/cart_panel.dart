import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;
import 'package:dio/dio.dart';
import 'package:ee_pos/models/cart_item.dart';
import 'package:ee_pos/repositories/open_bills_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/tax_prefs.dart';
import '../providers/discount_providers.dart';
import '../providers/cart_provider.dart';
import '../providers/products_provider.dart';
import '../providers/order_type_providers.dart';
import '../services/api_service.dart';
import '../models/product.dart';
import '../ui/pos_theme.dart';
import '../utils/formatting.dart';
import './bill_receipt.dart';
import '../providers/auth_providers.dart'; // for cashier name
import '../ui/top_message.dart';
import '../repositories/orders_repo.dart';
import '../providers/tax_settings_provider.dart';
import 'cart/cart_helpers.dart';
import 'cart/cart_ui_shared.dart';
import '../offline/sync_service.dart';

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key, required this.onRefreshAll});
  final Future<void> Function() onRefreshAll;

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final selectedDiscount = ref.watch(selectedDiscountProvider);
    final taxSettings = ref.watch(taxSettingsProvider).valueOrNull;
    final taxEnabled = taxSettings?.enabled ?? kDefaultTaxEnabled;
    final taxRatePct = taxSettings?.ratePercent ?? kDefaultTaxRatePct;
    final taxRate = taxEnabled ? (taxRatePct / 100.0) : 0.0;

    final subtotal = cart.fold<int>(0, (s, it) => s + it.priceCents * it.qty);
    final discount = computeDiscountCents(selectedDiscount, subtotal);
    final taxableBase = (subtotal - discount).clamp(0, 1 << 31);
    final tax = (taxableBase * taxRate).round();
    final total = taxableBase + tax;

    final taxPctStr = (taxRate * 100).toStringAsFixed(
      ((taxRate * 100).truncateToDouble() == (taxRate * 100)) ? 0 : 1,
    );
    final taxLabel = 'Tax ($taxPctStr%)';

    return Container(
      color: PosTheme.panel,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          const _PanelHeader(),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator.adaptive(
              onRefresh: widget.onRefreshAll,
              child: _CartList(),
            ),
          ),
          const Divider(color: PosTheme.border),
          _TotalsSection(
            subtotal: subtotal,
            discount: discount,
            tax: tax,
            total: total,
            showDiscount: selectedDiscount != null,
            discountLabel: selectedDiscount == null
                ? ''
                : (selectedDiscount.code.isNotEmpty
                    ? 'Discount'
                    : "Discount (${selectedDiscount.kind.name == 'percent' ? '${selectedDiscount.value.toStringAsFixed(0)}%' : selectedDiscount.name})"),
            taxLabelOverride: taxLabel,
          ),
          const SizedBox(height: 8),
          _ActionsSection(
            onRefreshAll: widget.onRefreshAll,
            cartTotalCents: total,
            taxRate: taxRate,
            taxLabel: taxLabel,
          ),
        ],
      ),
    );
  }
}

// ===================== SUB-WIDGETS =====================

// class _CartList extends ConsumerWidget {
//   @override
//   Widget build(BuildContext context, WidgetRef ref) {
//     final cart = ref.watch(cartProvider);
//     if (cart.isEmpty) {
//       return ListView(
//         physics: const AlwaysScrollableScrollPhysics(),
//         children: [
//           SizedBox(
//             height: 220,
//             child: Center(
//               child: Text(
//                 'No Orders yet.\nTap a Menu to add to this order.',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(color: PosTheme.muted),
//               ),
//             ),
//           ),
//         ],
//       );
//     }

//     return ListView.builder(
//       physics: const AlwaysScrollableScrollPhysics(),
//       itemCount: cart.length,
//       itemBuilder: (_, i) {
//         final it = cart[i];
//         return ListTile(
//           dense: true,
//           contentPadding: const EdgeInsets.symmetric(horizontal: 8),
//           title: Text('${it.name} × ${it.qty}',
//               style: const TextStyle(
//                   fontWeight: FontWeight.w600, color: PosTheme.black)),
//           subtitle: Text(
//             '${rp(it.priceCents)} · ${rp(it.priceCents * it.qty)}',
//             style: const TextStyle(fontSize: 12, color: PosTheme.muted),
//           ),
//           trailing: Row(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               IconButton(
//                 onPressed: () => ref.read(cartProvider.notifier).dec(it.sku),
//                 icon: const Icon(Icons.remove_circle_outline),
//                 color: PosTheme.black,
//               ),
//               IconButton(
//                 onPressed: () => ref
//                     .read(cartProvider.notifier)
//                     .add(Product(it.sku, it.name, it.priceCents, 0)),
//                 icon: const Icon(Icons.add_circle_outline),
//                 color: PosTheme.black,
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }


class _CartList extends ConsumerStatefulWidget {
  @override
  ConsumerState<_CartList> createState() => _CartListState();
}

class _CartListState extends ConsumerState<_CartList> {
  // Kuota “pesanan lama” per key (sku|price_cents)
  Map<String, int> _baseQty = {};

  @override
  void initState() {
    super.initState();
    _loadBaseQuota();
  }

  Future<void> _loadBaseQuota() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final baseStr = sp.getString('pos.active.draft.base_items');
      final List base = baseStr != null ? (jsonDecode(baseStr) as List) : const [];
      _baseQty = _countMapFromList(base);
      if (mounted) setState(() {});
    } catch (_) {
      _baseQty = {};
      if (mounted) setState(() {});
    }
  }

  /// Hitung kuota dari list base_items (tiap entry bisa punya qty)
  Map<String, int> _countMapFromList(List base) {
    final m = <String, int>{};
    for (final raw in base) {
      final it = Map<String, dynamic>.from(raw as Map);
      final sku = (it['sku'] ?? (it['menu_code'] != null ? 'menu:${it['menu_code']}' : 'unknown')).toString();
      final price = (it['price_cents'] as num?)?.toInt()
          ?? (it['unit_price_cents'] as num?)?.toInt()
          ?? 0;
      final qty = (it['qty'] as num?)?.toInt() ?? 1;
      final key = '$sku|$price';
      m[key] = (m[key] ?? 0) + qty;
    }
    return m;
  }

  String _keyOf(CartItem p) {
  return '${p.sku}|${p.priceCents}';
}

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);

    if (cart.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: 220,
            child: Center(
              child: Text(
                'No Orders yet.\nTap a Menu to add to this order.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PosTheme.muted),
              ),
            ),
          ),
        ],
      );
    }

    // counter berjalan untuk menentukan “lama” vs “tambahan”
    final running = <String, int>{};
    final children = <Widget>[];
    bool separatorInserted = false;

    // (opsional) kalau ada baseQty dan belum ada tambahan sama sekali,
    // tampilkan label "Pesanan Lama" di atas
    final hasBase = _baseQty.values.any((v) => v > 0);
    if (hasBase) {
      children.add(const _CartOldLabel());
    }

    for (final item in cart) {
      final key = _keyOf(item);
      final seen = (running[key] ?? 0) + item.qty; // row menambah sesuai qty baris
      final before = running[key] ?? 0;
      running[key] = seen;

      final base = _baseQty[key] ?? 0;
      final wasWithinBase = before < base;
      final nowExceedsBase = seen > base;

      // sisipkan separator tepat di transisi pertama dari "lama" -> "tambahan"
      if (!separatorInserted && hasBase && wasWithinBase && nowExceedsBase) {
        children.add(const _CartSectionSeparator());
        separatorInserted = true;
      } else if (!separatorInserted && !hasBase) {
        // kalau tidak ada base (bukan Continue), semua adalah tambahan
        children.add(const _CartSectionSeparator());
        separatorInserted = true;
      }

      final isAdded = (running[key] ?? 0) > base;
      children.add(_CartRowWithAddedFlag(product: item, isAdded: isAdded, ref: ref));
    }

    return RefreshIndicator.adaptive(
      onRefresh: () async {
        await _loadBaseQuota(); // refresh kuota saat pull-to-refresh
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: children,
      ),
    );
  }
}

class _CartRowWithAddedFlag extends StatelessWidget {
    final CartItem product;
  final bool isAdded;
  final WidgetRef ref;

  const _CartRowWithAddedFlag({
    super.key,
    required this.product,
    required this.isAdded,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final name = isAdded ? '${product.name} (Tambahan)' : product.name;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      title: Text(
        '$name × ${product.qty}',
        style: const TextStyle(fontWeight: FontWeight.w600, color: PosTheme.black),
      ),
      subtitle: Text(
        '${rp(product.priceCents)} · ${rp(product.priceCents * product.qty)}',
        style: const TextStyle(fontSize: 12, color: PosTheme.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: () => ref.read(cartProvider.notifier).dec(product.sku),
            icon: const Icon(Icons.remove_circle_outline),
            color: PosTheme.black,
          ),
          IconButton(
            onPressed: () => ref.read(cartProvider.notifier).add(
                  Product(product.sku, product.name, product.priceCents, 0),
                ),
            icon: const Icon(Icons.add_circle_outline),
            color: PosTheme.black,
          ),
        ],
      ),
    );
  }
}

class _CartSectionSeparator extends StatelessWidget {
  const _CartSectionSeparator({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Divider(color: cs.outlineVariant)),
          const SizedBox(width: 8),
          Text(
            'Tambahan',
            style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(color: cs.outlineVariant)),
        ],
      ),
    );
  }
}

class _CartOldLabel extends StatelessWidget {
  const _CartOldLabel({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        'Pesanan Lama',
        style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant),
      ),
    );
  }
}


class _TotalsSection extends StatelessWidget {
  const _TotalsSection({
    required this.subtotal,
    required this.discount,
    required this.tax,
    required this.total,
    required this.showDiscount,
    required this.discountLabel,
    this.taxLabelOverride,
  });

  final int subtotal;
  final int discount;
  final int tax;
  final int total;
  final bool showDiscount;
  final String discountLabel;
  final String? taxLabelOverride;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        cartTotalRow('Subtotal', subtotal),
        if (showDiscount) cartTotalRowDiscount(discountLabel, -discount),
        cartTotalRow(taxLabelOverride ?? 'Tax', tax),
        cartTotalRowBold('Total', total),
      ],
    );
  }
}

class _ActionsSection extends ConsumerWidget {
  const _ActionsSection({
    required this.onRefreshAll,
    required this.cartTotalCents,
    required this.taxRate,
    required this.taxLabel,
  });

  final Future<void> Function() onRefreshAll;
  final int cartTotalCents;
  final double taxRate; // 0.0–1.0
  final String taxLabel;

  // ===== helper: mapping menu code -> type, & filter ke QueueItem =====
  // Map<String, String> _menuTypeByCode(WidgetRef ref) {
  //   final products = ref.read(productsProvider).maybeWhen(
  //         data: (d) => d,
  //         orElse: () => null,
  //       );
  //   final map = <String, String>{};
  //   if (products != null) {
  //     for (final m in products.menus) {
  //       map[m.code] = (m.type ?? '').toLowerCase();
  //     }
  //   }
  //   return map;
  // }

  // String? _typeFromSku(String sku, Map<String, String> map) {
  //   if (sku.startsWith('menu:')) {
  //     final code = sku.substring(5);
  //     return map[code];
  //   }
  //   return null; // non-menu item tidak ikut Kitchen/Bar
  // }

  // List<QueueItem> _queueItemsFor(
  //   List<CartLine> cart,
  //   Map<String, String> typeMap,
  //   bool Function(String? t) predicate,
  // ) {
  //   return cart
  //       .where((e) => predicate(_typeFromSku(e.sku, typeMap)))
  //       .map((e) => QueueItem(name: e.name, qty: e.qty))
  //       .toList();
  // }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);

    final filledBlack = FilledButton.styleFrom(
      backgroundColor: PosTheme.black,
      foregroundColor: PosTheme.white,
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
    final outlinedBlack = OutlinedButton.styleFrom(
      foregroundColor: PosTheme.black,
      side: const BorderSide(color: PosTheme.black, width: 1),
      padding: const EdgeInsets.symmetric(vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );

    Future<void> pay() async {
      if (cart.isEmpty) return;
      await _showPayDialog(
        context,
        ref,
        cartTotalCents: cartTotalCents,
        taxRate: taxRate,
        taxLabel: taxLabel,
      );
    }

    Future<String?> _askCustomerName(BuildContext context) async {
      final ctrl = TextEditingController();
      return showDialog<String>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('Customer Name'),
            content: TextField(
              controller: ctrl,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Enter customer name',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx), // batal
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx, ctrl.text.trim());
                },
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    }

    // ===== SAVE BILL: auto print QUEUE ke Customer & Bar =====
    // Future<void> saveBill() async {
    //   final cart = ref.read(cartProvider);
    //   if (cart.isEmpty) {
    //     showTopError(context, 'Cart kosong — belum ada item');
    //     return;
    //   }

    //   final repo = OrdersRepo();
    //   try {
    //     final selectedDiscount = ref.read(selectedDiscountProvider);
    //     final selectedOrderTypeCode = ref.read(selectedOrderTypeCodeProvider);
    //     final orderTypeName = ref.read(effectiveOrderTypeNameProvider);
    //     final user = ref.read(authControllerProvider).valueOrNull;

    //     // 1) minta nama customer
    //     final name = await _askCustomerName(context);
    //     if (name == null || name.isEmpty) {
    //       showTopError(context, 'Nama customer wajib diisi');
    //       return;
    //     }

    //     // 2) payload draft untuk server
    //     final draft = {
    //       'items': cart.map(itemToPayload).toList(),
    //       'tax_rate': taxRate,
    //       'discount': selectedDiscount == null
    //           ? null
    //           : {
    //               if (selectedDiscount.code.isNotEmpty)
    //                 'code': selectedDiscount.code,
    //               if (selectedDiscount.code.isEmpty)
    //                 'kind': selectedDiscount.kind.name,
    //               if (selectedDiscount.code.isEmpty)
    //                 'value': selectedDiscount.value,
    //             },
    //       'payments': [],
    //       'status': 'draft',
    //       if ((selectedOrderTypeCode ?? '').isNotEmpty)
    //         'order_type': selectedOrderTypeCode,
    //       'created_by_id': user?.id,
    //       'customer_name': name, // simpan nama — dipakai sebagai Table
    //     };

    //     // 3) kirim ke server (offline-first)
    //     final res = await repo.createOrderSmart(draft);

    //     // 4) simpan ke OpenBills lokal
    //     final rawItems = (draft['items'] as List?) ?? const [];
    //     final items =
    //         rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();

    //     final totalCents = items.fold<int>(0, (sum, it) {
    //       final price = (it['price_cents'] as num?)?.toInt() ??
    //           (it['unit_price_cents'] as num?)?.toInt() ??
    //           0;
    //       final qty = (it['qty'] as num?)?.toInt() ?? 1;
    //       return sum + price * qty;
    //     });

    //     final sp = await SharedPreferences.getInstance();
    //     final activeId = sp.getString('pos.active.draft.id');
    //     final activePayloadStr = sp.getString('pos.active.draft.payload');

    //     String? createdAt;
    //     if (activePayloadStr != null) {
    //       try {
    //         final old = Map<String, dynamic>.from(jsonDecode(activePayloadStr));
    //         final ca = (old['created_at'] ?? '').toString().trim();
    //         if (ca.isNotEmpty) createdAt = ca;
    //       } catch (_) {}
    //     }

    //     final idToUse = activeId ??
    //         (res['id']?.toString() ??
    //             DateTime.now().millisecondsSinceEpoch.toString());

    //     final ob = OpenBillsRepo();
    //     final payloadToStore = {
    //       'id': idToUse,
    //       'items': items,
    //       'total_cents': totalCents,
    //       'customer_name': name,
    //       'created_at': createdAt ?? DateTime.now().toIso8601String(),
    //       'synced': (res['remote'] == true),
    //     };

    //     if (activeId != null) {
    //       await ob.updateDraft(payloadToStore);
    //       showTopSuccess(context, 'Bill updated');
    //     } else {
    //       await ob.addDraft(payloadToStore);
    //       showTopSuccess(
    //         context,
    //         (res['remote'] == true)
    //             ? 'Bill saved (#${res['id'] ?? ''})'
    //             : 'Bill disimpan offline — akan disinkron saat online',
    //       );
    //     }

    //     await sp.setString('pos.active.draft.id', idToUse);
    //     await sp.setString(
    //         'pos.active.draft.payload', jsonEncode(payloadToStore));

    //     // ========== AUTO PRINT QUEUE ==========
    //     // Customer: semua item | Bar: drink/cake/bread | (Kitchen: tidak tercetak saat Save Bill)
    //     final typeMap = await buildMenuTypeMap();

    //     // final customerItems =
    //     //     cart.map((e) => QueueItem(name: e.name, qty: e.qty)).toList();
    //     final customerItems = queueItemsAll(cart);

    //     // final barItems = _queueItemsFor(
    //     //   cart,
    //     //   typeMap,
    //     //   (t) => t == 'drink' || t == 'cake' || t == 'bread',
    //     // );

    //     final barItems = queueItemsFor(
    //       cart,
    //       typeMap,
    //       (t) => t == 'drink' || t == 'cake' || t == 'bread',
    //     );

    //     final queueNo = res['id']?.toString().isNotEmpty == true
    //         ? res['id'].toString()
    //         : await nextLocalQueueNo();

    //     final cashierName = (user?.displayName?.isNotEmpty ?? false)
    //         ? user!.displayName!
    //         : (user?.username ?? '-');

    //     // 1) Queue ke CUSTOMER PRINTER (semua item)
    //     final cTicket = QueueTicketData(
    //       queueNo: queueNo,
    //       dateTime: DateTime.now(),
    //       storeName: 'e+e Coffee',
    //       userName: cashierName,
    //       orderType: orderTypeName,
    //       items: customerItems,
    //       tableName: name, // tampil sebagai Table
    //     );
    //     try {
    //       await ReceiptPrinter.printKitchenOnCustomerPrinter(context, cTicket);
    //     } catch (_) {}

    //     // 2) Queue ke BAR (jika ada)
    //     if (barItems.isNotEmpty) {
    //       final bTicket = QueueTicketData(
    //         queueNo: queueNo,
    //         dateTime: DateTime.now(),
    //         storeName: 'e+e Coffee',
    //         userName: cashierName,
    //         orderType: orderTypeName,
    //         items: barItems,
    //         tableName: name,
    //       );
    //       try {
    //         await ReceiptPrinter.printBarWithSavedPrefs(context, bTicket);
    //       } catch (_) {}
    //     }

    //     // === [NEW] Auto-print ke KITCHEN (food only) setelah Save Bill ===
    //     try {
    //       // Ambil info pendukung
    //       final orderTypeName = ref.read(effectiveOrderTypeNameProvider);
    //       final user = ref.read(authControllerProvider).valueOrNull;

    //       final cashierName = (user?.displayName?.isNotEmpty ?? false)
    //           ? user!.displayName!
    //           : (user?.username ?? '-');

    //       // nomor antrian: pakai id dari server kalau ada; kalau tidak, queue lokal
    //       final queueNo = (res['id'] != null && '${res['id']}'.isNotEmpty)
    //           ? '${res['id']}'
    //           : await nextLocalQueueNo();

    //       // filter item: hanya FOOD
    //       final typeMap = await buildMenuTypeMap();
    //       final foodItems = queueItemsFor(
    //         cart,
    //         typeMap,
    //         (t) => t == 'food',
    //       );

    //       if (foodItems.isNotEmpty) {
    //         final kitchenTicket = QueueTicketData(
    //           queueNo: queueNo,
    //           dateTime: DateTime.now(),
    //           storeName:
    //               'e+e Coffee', // ganti kalau kamu punya store name dari prefs
    //           userName: cashierName,
    //           orderType: orderTypeName,
    //           items: foodItems,
    //           // optional: kamu bisa tambahkan tableName kalau printer kitchen ingin menampilkan
    //           // tableName: name, // <- nama yang kamu input saat Save Bill
    //         );

    //         // cetak ke printer Kitchen yang sudah diset di Settings
    //         await ReceiptPrinter.printKitchenWithSavedPrefs(
    //             context, kitchenTicket);
    //       }
    //     } catch (e) {
    //       // jangan blokir flow — cukup kasih info kalau gagal print kitchen
    //       if (context.mounted) {
    //         showTopError(context, 'gagal print Kitchen: $e');
    //       }
    //     }

    //     // ===== UI cleanup =====
    //     await ref.read(cartProvider.notifier).clear();
    //     ref.invalidate(productsProvider);
    //   } catch (e) {
    //     showTopError(context, 'Save bill failed: $e');
    //   }
    // }

Future<void> clearActiveDraftPrefs() async {
  final sp = await SharedPreferences.getInstance();
  await sp.remove('pos.active.draft.id');
  await sp.remove('pos.active.draft.payload');
  await sp.remove('pos.active.draft.base_items');
  await sp.remove('pos.active.draft.mode'); // ⬅️ new
}

Future<void> setActiveDraftMode(String mode) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setString('pos.active.draft.mode', mode); // "new" | "continue"
}

Future<String?> getActiveDraftMode() async {
  final sp = await SharedPreferences.getInstance();
  return sp.getString('pos.active.draft.mode');
}


Future<void> saveBillLocalOnly() async {
  final cart = ref.read(cartProvider);
  if (cart.isEmpty) {
    showTopError(context, 'Cart kosong');
    return;
  }

  try {
    final sp = await SharedPreferences.getInstance();
    final fromOpen = sp.getBool('pos.active.from_open') == true; // <-- kunci

    // ===== 1) Tentukan Billing Name =====
    String? tableName;

    if (fromOpen) {
      // mode CONTINUE → boleh reuse nama dari draft aktif
      final payloadStr = sp.getString('pos.active.draft.payload');
      if (payloadStr != null) {
        try {
          final m = Map<String, dynamic>.from(jsonDecode(payloadStr));
          final nm = (m['customer_name'] ?? '').toString().trim();
          if (nm.isNotEmpty) tableName = nm;
        } catch (_) {}
      }
      // kalau kosong juga, tetap minta
      if ((tableName ?? '').isEmpty) {
        tableName = await askBillingName(context);
        if ((tableName ?? '').isEmpty) return;
      }
    } else {
      // BUKAN dari Continue → PESANAN BARU → WAJIB minta nama BARU
      tableName = await askBillingName(context);
      if ((tableName ?? '').isEmpty) return;
    }

    // ===== 2) Hitung ringkas =====
    final subtotalCents = cart.fold<int>(0, (x, it) => x + it.priceCents * it.qty);

    final taxCents = (subtotalCents * taxRate).round();
    final totalCents = subtotalCents + taxCents;

    // helper: cart -> list
    List<Map<String, dynamic>> _cartToMaps() => cart
        .map((e) => {
              'sku': e.sku,
              'name': e.name,
              'qty': e.qty,
              'price_cents': e.priceCents,
            })
        .toList();

    final ob = OpenBillsRepo();

    if (fromOpen) {
      // ================= UPDATE DRAFT AKTIF (hasil Continue) =================
      final activeId = sp.getString('pos.active.draft.id');
      final payloadStr = sp.getString('pos.active.draft.payload');
      final baseItemsJson = sp.getString('pos.active.draft.base_items');

      if (activeId == null || payloadStr == null) {
        // kalau flag nyasar → jatuhkan ke create baru
      } else {
        final draft = Map<String, dynamic>.from(jsonDecode(payloadStr));

        final base = baseItemsJson != null
            ? (jsonDecode(baseItemsJson) as List).cast<Map>()
            : ((draft['items'] as List?) ?? const []).cast<Map>();

        final nowItems = _cartToMaps();
        final delta = diffAddedItems(base, nowItems);
        if (delta.isEmpty) {
          if (context.mounted) showTopMessage(context, 'Tidak ada item tambahan');
          return;
        }

        final edits = (draft['edits'] as List?)?.cast<Map<String, dynamic>>() ?? <Map<String, dynamic>>[];
        edits.add({
          'created_at': DateTime.now().toIso8601String(),
          'items': delta,
        });

        final updated = {
          ...draft,
          'customer_name': tableName ?? (draft['customer_name'] ?? ''),
          'items': draft['items'],
          'edits': edits,
          'subtotal_cents': subtotalCents,
          'tax_cents': taxCents,
          'total_cents': totalCents,
          'updated_at': DateTime.now().toIso8601String(),
        };

        await ob.removeDraft(activeId);
        await ob.addDraft(updated);

        await sp.setString('pos.active.draft.payload', jsonEncode(updated));
        await sp.setString('pos.active.draft.base_items', jsonEncode(nowItems));
        // from_open tetap true biar bisa nambah lagi di bill yg sama

        if (context.mounted) {
          showTopSuccess(context, 'Bill diupdate (tambahan) ke Open Bills');
          await ref.read(cartProvider.notifier).clear();
          ref.invalidate(productsProvider);
        }
        return;
      }
    }

    // ================= PESANAN BARU → CREATE DRAFT BARU =================
    final draftId = DateTime.now().millisecondsSinceEpoch.toString();
    final draftPayload = {
      'id': draftId,
      'customer_name': tableName ?? '', // <-- nama BARU
      'items': _cartToMaps(),           // batch awal
      'edits': <Map<String, dynamic>>[],
      'subtotal_cents': subtotalCents,
      'tax_cents': taxCents,
      'total_cents': totalCents,
      'created_at': DateTime.now().toIso8601String(),
      'synced': false,
    };

    await ob.addDraft(draftPayload);

    // tandai jadi draft aktif BARU
    await sp.setString('pos.active.draft.id', draftId);
    await sp.setString('pos.active.draft.payload', jsonEncode(draftPayload));
    await sp.setString('pos.active.draft.base_items', jsonEncode(draftPayload['items']));

    // penting: hapus flag from_open (karena ini bukan hasil Continue)
    await sp.remove('pos.active.from_open');

    if (context.mounted) {
      showTopSuccess(context, 'Bill baru disimpan ke Open Bills');
      await ref.read(cartProvider.notifier).clear();
      ref.invalidate(productsProvider);
    }
  } catch (e) {
    if (context.mounted) showTopError(context, 'Gagal simpan bill: $e');
  }
}

// ===== helper diff tetap sama =====
// List<Map<String, dynamic>> _diffAddedItems(
//   List<Map> base,
//   List<Map<String, dynamic>> now,
// ) {
//   String keyOf(Map m) => '${m['sku']}|${m['price_cents']}';

//   final baseQty = <String, int>{};
//   for (final m in base) {
//     final k = keyOf(m);
//     baseQty[k] = (baseQty[k] ?? 0) + ((m['qty'] ?? 1) as int);
//   }
//   final add = <Map<String, dynamic>>[];
//   for (final m in now) {
//     final k = keyOf(m);
//     final qtyNow = (m['qty'] ?? 1) as int;
//     final qtyBase = baseQty[k] ?? 0;
//     final extra = qtyNow - qtyBase;
//     if (extra > 0) {
//       add.add({
//         'sku': m['sku'],
//         'name': m['name'],
//         'qty': extra,
//         'price_cents': m['price_cents'],
//       });
//     }
//   }
//   return add;
// }

// Bandingkan base vs now; kembalikan daftar item yang merupakan TAMBAHAN

// Dialog kecil untuk isi Billing Name (pakai yang dari jawaban sebelumnya)



    Future<void> showSplitDialog() async {
      if (cart.isEmpty) return;
      await _showSplitDialog(
        context,
        ref,
        cartTotalCents: cartTotalCents,
        taxRate: taxRate,
        taxLabel: taxLabel,
      );
    }

    /// ========= Print Queue: PAKAI QUEUE LOKAL kalau orderId belum ada =========
    // Future<void> printQueue() async {
    //   final cart = ref.read(cartProvider);
    //   if (cart.isEmpty) return;

    //   // hitung total dengan tax dinamis
    //   final selectedDiscount = ref.read(selectedDiscountProvider);
    //   final subtotal = cart.fold<int>(0, (s, it) => s + it.priceCents * it.qty);
    //   final discount = computeDiscountCents(selectedDiscount, subtotal);
    //   final taxableBase = (subtotal - discount).clamp(0, 1 << 31);
    //   final tax = (taxableBase * taxRate).round();
    //   final total = taxableBase + tax;

    //   final orderTypeName = ref.read(effectiveOrderTypeNameProvider);

    //   final bill = BillData(
    //     title: 'Order',
    //     date: DateTime.now(),
    //     items: cart
    //         .map((it) => BillLine(
    //             name: it.name, qty: it.qty, priceCentsEach: it.priceCents))
    //         .toList(),
    //     subtotal: subtotal,
    //     discount: discount,
    //     tax: tax,
    //     total: total,
    //     footer: '',
    //     orderId: null,
    //     orderTypeName: orderTypeName,
    //   );

    //   await _printKitchenFromBill(context, ref, bill: bill);
    // }

    Future<void> printQueue() async {
      final cart = ref.read(cartProvider);
      if (cart.isEmpty) return;

      // order type & cashier (opsional)
      final orderTypeName = ref.read(effectiveOrderTypeNameProvider);
      final user = ref.read(authControllerProvider).valueOrNull;
      final cashierName = (user?.displayName?.isNotEmpty ?? false)
          ? user!.displayName!
          : (user?.username ?? '-');

      // nomor antrian lokal (karena belum ada orderId server)
      final queueNo = await nextLocalQueueNo(); // util yang sudah ada

      // ambil nama customer/table dari draft aktif (kalau ada)
      String? tableName;
      try {
        final sp = await SharedPreferences.getInstance();
        final activePayloadStr = sp.getString('pos.active.draft.payload');
        if (activePayloadStr != null) {
          final m = Map<String, dynamic>.from(jsonDecode(activePayloadStr));
          final nm = (m['customer_name'] ?? '').toString().trim();
          if (nm.isNotEmpty) tableName = nm;
        }
      } catch (_) {}

      // item untuk customer: semua item cart
      final customerItems = queueItemsAll(cart);

      final ticket = QueueTicketData(
        queueNo: queueNo,
        dateTime: DateTime.now(),
        storeName: 'e+e Coffee', // ganti kalau punya store name dari prefs
        userName: cashierName,
        orderType: orderTypeName,
        items: customerItems,
        tableName: tableName, // ✅ tampilkan di tiket Queue
      );

      // CETAK ke PRINTER CUSTOMER (bukan kitchen)
      await ReceiptPrinter.printKitchenOnCustomerPrinter(context, ticket);
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cart.isEmpty ? null : saveBillLocalOnly,
                style: outlinedBlack,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Bill'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cart.isEmpty ? null : printQueue,
                style: outlinedBlack,
                icon: const Icon(Icons.print),
                label: const Text('Print Queue'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cart.isEmpty ? null : showSplitDialog,
                style: outlinedBlack,
                icon: const Icon(Icons.call_split),
                label: const Text('Split Bill'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: cart.isEmpty ? null : pay,
                style: filledBlack,
                child: const Text('Pay'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: cart.isEmpty
                    ? null
                    : () => ref.read(cartProvider.notifier).clear(),
                style: outlinedBlack,
                child: const Text('Clear'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PanelHeader extends ConsumerWidget {
  const _PanelHeader();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderTypeName = ref.watch(effectiveOrderTypeNameProvider);
    return Row(
      children: [
        const Text(
          'Orders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: PosTheme.black,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _OrderTypeDropdown()),
              const SizedBox(width: 8),
              Flexible(
                fit: FlexFit.loose,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      orderTypeName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OrderTypeDropdown extends ConsumerWidget {
  const _OrderTypeDropdown();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(orderTypesProvider);
    final selectedCode = ref.watch(effectiveOrderTypeCodeProvider);

    return typesAsync.when(
      loading: () => const _LoadingDropdownSkeleton(),
      error: (e, _) => DropdownButtonFormField<String>(
        initialValue: selectedCode,
        isExpanded: true,
        items: const [],
        onChanged: null,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          labelText: 'Order type',
        ),
      ),
      data: (types) {
        final value = (types.any((t) => t.code == (selectedCode ?? '')))
            ? selectedCode
            : (types.isNotEmpty ? types.first.code : null);

        return DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          items: [
            for (final t in types)
              DropdownMenuItem(
                value: t.code,
                child: Text(t.name, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) {
            ref.read(selectedOrderTypeCodeProvider.notifier).set(v);
          },
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            labelText: 'Order type',
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        );
      },
    );
  }
}

class _LoadingDropdownSkeleton extends StatelessWidget {
  const _LoadingDropdownSkeleton();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          labelText: 'Order type',
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        child: Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            height: 14,
            width: 100,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black12,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===================== HELPERS (rows) =====================
Widget _row(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: PosTheme.muted)),
          const Spacer(),
          Text(rp(value), style: const TextStyle(color: PosTheme.black)),
        ],
      ),
    );

Widget _rowBold(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: Row(
        children: [
          Text(label,
              style: const TextStyle(
                  color: PosTheme.black, fontWeight: FontWeight.w700)),
          const Spacer(),
          Text(
            rp(value),
            style: const TextStyle(
                color: PosTheme.black,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );

Widget _rowDiscount(String label, int value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      child: Row(
        children: [
          Text(label, style: const TextStyle(color: Colors.green)),
          const Spacer(),
          Text(rp(value), style: const TextStyle(color: Colors.green)),
        ],
      ),
    );

// ===================== PAYMENT DIALOG (OFFLINE-FIRST) =====================
Future<void> _showPayDialog(
  BuildContext context,
  WidgetRef ref, {
  required int cartTotalCents,
  required double taxRate, // 0.0–1.0
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

                                // Future<void> doPay() async {
                                //   if (saving) return;
                                //   setState(() => saving = true);
                                //   try {
                                //     final repo = OrdersRepo();
                                //     final cart = ref.read(cartProvider);
                                //     final selectedDiscount =
                                //         ref.read(selectedDiscountProvider);
                                //     final selectedOrderTypeCode =
                                //         ref.read(selectedOrderTypeCodeProvider);
                                //     final orderTypeName = ref
                                //         .read(effectiveOrderTypeNameProvider);

                                //     final user = ref
                                //         .read(authControllerProvider)
                                //         .valueOrNull;

                                //     String methodName = selected.toUpperCase();
                                //     final found = enabled.firstWhere(
                                //       (m) => m['code'] == selected,
                                //       orElse: () => {},
                                //     );
                                //     if (found is Map &&
                                //         (found['name']?.toString().isNotEmpty ??
                                //             false)) {
                                //       methodName = found['name'];
                                //     }

                                //     // kalkulasi server-aligned (dinamis)
                                //     final subtotalCents = cart.fold<int>(0,
                                //         (x, it) => x + it.priceCents * it.qty);
                                //     int discountCents = 0;
                                //     Map<String, dynamic>? discountPayload;

                                //     if (selectedDiscount != null) {
                                //       if (selectedDiscount.code.isNotEmpty) {
                                //         final list = await api.discounts();
                                //         final m = list.cast<Map>().firstWhere(
                                //               (e) =>
                                //                   (e['code'] ?? '') ==
                                //                       selectedDiscount.code &&
                                //                   (e['enabled'] == 1 ||
                                //                       e['enabled'] == true),
                                //               orElse: () => {},
                                //             );
                                //         if (m.isNotEmpty) {
                                //           final kind =
                                //               (m['kind'] ?? '').toString();
                                //           final val = (m['value'] is int)
                                //               ? (m['value'] as int).toDouble()
                                //               : (m['value'] as num).toDouble();
                                //           discountPayload = {'code': m['code']};
                                //           discountCents = (kind == 'percent')
                                //               ? (subtotalCents * (val / 100))
                                //                   .round()
                                //               : val.round();
                                //         }
                                //       } else {
                                //         discountPayload = {
                                //           'kind': selectedDiscount.kind.name,
                                //           'value': selectedDiscount.value,
                                //         };
                                //         discountCents = (selectedDiscount
                                //                     .kind.name ==
                                //                 'percent')
                                //             ? (subtotalCents *
                                //                     (selectedDiscount.value /
                                //                         100))
                                //                 .round()
                                //             : selectedDiscount.value.round();
                                //       }
                                //       if (discountCents < 0) discountCents = 0;
                                //       if (discountCents > subtotalCents)
                                //         discountCents = subtotalCents;
                                //     }

                                //     final taxableBase =
                                //         (subtotalCents - discountCents)
                                //             .clamp(0, 1 << 31);
                                //     final taxCents =
                                //         (taxableBase * taxRate).round();
                                //     final serverExpectedTotal =
                                //         taxableBase + taxCents;

                                //     final order = {
                                //       'items': cart.map(itemToPayload).toList(),
                                //       'tax_rate': taxRate,
                                //       'discount': discountPayload,
                                //       'payments': [
                                //         {
                                //           'method': selected,
                                //           'amount_cents': serverExpectedTotal
                                //         }
                                //       ],
                                //       if ((selectedOrderTypeCode ?? '')
                                //           .isNotEmpty)
                                //         'order_type': selectedOrderTypeCode,
                                //     };

                                //     final sp =
                                //         await SharedPreferences.getInstance();
                                //     String? tableName;
                                //     final activePayloadStr = sp
                                //         .getString('pos.active.draft.payload');
                                //     if (activePayloadStr != null) {
                                //       try {
                                //         final m = Map<String, dynamic>.from(
                                //             jsonDecode(activePayloadStr));
                                //         final nm = (m['customer_name'] ?? '')
                                //             .toString()
                                //             .trim();
                                //         if (nm.isNotEmpty) tableName = nm;
                                //       } catch (_) {}
                                //     }

                                //     // offline-first call
                                //     final res =
                                //         await repo.createOrderSmart(order);
                                //     final orderIdStr = res['id']?.toString();

                                //     final bill = BillData(
                                //       title: '',
                                //       date: DateTime.now(),
                                //       items: cart
                                //           .map((e) => BillLine(
                                //                 name: e.name,
                                //                 qty: e.qty,
                                //                 priceCentsEach: e.priceCents,
                                //               ))
                                //           .toList(),
                                //       subtotal: subtotalCents,
                                //       discount: discountCents,
                                //       tax: taxCents,
                                //       total: serverExpectedTotal,
                                //       footer: '',
                                //       orderId: orderIdStr,
                                //       orderTypeName: orderTypeName,
                                //       paymentSummary: methodName,
                                //       tableName: tableName,
                                //     );

                                //     if (context.mounted) {
                                //       Navigator.pop(ctx); // close Payment modal
                                //     }

                                //     // 1) Print nota CUSTOMER (semua item)
                                //     await ReceiptPrinter.printWithSavedPrefs(
                                //         context, bill);

                                //     // 2) Print QUEUE terpisah:
                                //     // Kitchen: hanya food; Bar: drink/cake/bread
                                //     // final typeMap = _menuTypeByCode(ref);
                                //     final typeMap = await buildMenuTypeMap();

                                //     // final kitchenItems = _queueItemsFor(
                                //     //   cart,
                                //     //   typeMap,
                                //     //   (t) => t == 'food',
                                //     // );
                                //     final kitchenItems = queueItemsFor(
                                //       cart,
                                //       typeMap,
                                //       (t) => t == 'food',
                                //     );
                                //     // final barItems = _queueItemsFor(
                                //     //   cart,
                                //     //   typeMap,
                                //     //   (t) =>
                                //     //       t == 'drink' ||
                                //     //       t == 'cake' ||
                                //     //       t == 'bread',
                                //     // );
                                //     final barItems = queueItemsFor(
                                //       cart,
                                //       typeMap,
                                //       (t) =>
                                //           t == 'drink' ||
                                //           t == 'cake' ||
                                //           t == 'bread',
                                //     );

                                //     final queueNo = (orderIdStr != null &&
                                //             orderIdStr.isNotEmpty)
                                //         ? orderIdStr
                                //         : await nextLocalQueueNo();

                                //     final cashierName =
                                //         (user?.displayName?.isNotEmpty ?? false)
                                //             ? user!.displayName!
                                //             : (user?.username ?? '-');

                                //     if (kitchenItems.isNotEmpty) {
                                //       final kitchenTicket = QueueTicketData(
                                //         queueNo: queueNo,
                                //         dateTime: DateTime.now(),
                                //         storeName: 'e+e Coffee',
                                //         userName: cashierName,
                                //         orderType: orderTypeName,
                                //         items: kitchenItems,
                                //         tableName: tableName,
                                //       );
                                //       try {
                                //         await ReceiptPrinter
                                //             .printKitchenWithSavedPrefs(
                                //                 context, kitchenTicket);
                                //       } catch (_) {}
                                //     }

                                //     if (barItems.isNotEmpty) {
                                //       final barTicket = QueueTicketData(
                                //         queueNo: queueNo,
                                //         dateTime: DateTime.now(),
                                //         storeName: 'e+e Coffee',
                                //         userName: cashierName,
                                //         orderType: orderTypeName,
                                //         items: barItems,
                                //         tableName: tableName,
                                //       );
                                //       try {
                                //         await ReceiptPrinter
                                //             .printBarWithSavedPrefs(
                                //                 context, barTicket);
                                //       } catch (_) {}
                                //     }

                                //     // ====== MOVE OPEN → DONE (jika “Continue”) ======
                                //     try {
                                //       final sp =
                                //           await SharedPreferences.getInstance();
                                //       final activeId =
                                //           sp.getString('pos.active.draft.id');
                                //       final activePayloadStr = sp.getString(
                                //           'pos.active.draft.payload');

                                //       if (activeId != null &&
                                //           activePayloadStr != null) {
                                //         final repo = OpenBillsRepo();

                                //         // hapus dari Open
                                //         await repo.removeDraft(activeId);

                                //         // siapkan payload Done
                                //         final draft = Map<String, dynamic>.from(
                                //             jsonDecode(activePayloadStr));
                                //         final items =
                                //             draft['items'] as List? ?? const [];

                                //         await repo.addDone({
                                //           'id': activeId,
                                //           'order_id': orderIdStr ?? '',
                                //           'customer_name':
                                //               draft['customer_name'] ?? '',
                                //           'items': items,
                                //           'total_cents': serverExpectedTotal,
                                //           'payment_method': methodName,
                                //           'paid_at':
                                //               DateTime.now().toIso8601String(),
                                //           'synced': (res['remote'] == true),
                                //         });

                                //         await sp.remove('pos.active.draft.id');
                                //         await sp
                                //             .remove('pos.active.draft.payload');
                                //       }
                                //     } catch (_) {}

                                //     // bersihkan state
                                //     await ref
                                //         .read(cartProvider.notifier)
                                //         .clear();
                                //     ref
                                //         .read(selectedDiscountProvider.notifier)
                                //         .state = null;
                                //     ref.invalidate(productsProvider);

                                //     // feedback UI
                                //     if (context.mounted) {
                                //       if (res['remote'] != true) {
                                //         showTopMessage(context,
                                //             'order saved offline — will sync when online');
                                //       }
                                //       await _showSuccess(
                                //         context: context,
                                //         ref: ref,
                                //         bill: bill,
                                //         taxLabel: taxLabel,
                                //       );
                                //     }
                                //   } on DioException catch (e) {
                                //     setState(() => saving = false);
                                //     final code = e.response?.statusCode ?? 0;

                                //     if (code == 503) {
                                //       // (biarkan fallback 503 kamu seperti semula)
                                //     } else {
                                //       if (context.mounted) {
                                //         showTopError(context,
                                //             'payment failed: ${e.message}');
                                //       }
                                //     }
                                //   } catch (e) {
                                //     setState(() => saving = false);
                                //     if (context.mounted) {
                                //       showTopError(
                                //           context, 'payment failed: $e');
                                //     }
                                //   }
                                // }

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
                                        bill); // <- receipt customer :contentReference[oaicite:5]{index=5}

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
                                        : await nextLocalQueueNo(); // helper yang sudah ada:contentReference[oaicite:6]{index=6}

                                    final typeMap =
                                        await buildMenuTypeMap(); // map menu_code -> type:contentReference[oaicite:7]{index=7}
                                    final customerItems = queueItemsAll(
                                        cart); // semua item untuk customer:contentReference[oaicite:8]{index=8}

                                    final customerTicket = QueueTicketData(
                                      queueNo: queueNo,
                                      dateTime: DateTime.now(),
                                      storeName:
                                          'e+e Coffee', // ganti kalau punya storeName dinamis
                                      userName: cashierName,
                                      orderType: orderTypeName,
                                      items: customerItems,
                                      tableName: tableName,
                                    );

                                    // format queue “NEW ORDER” ke PRINTER CUSTOMER
                                    await ReceiptPrinter
                                        .printKitchenOnCustomerPrinter(context,
                                            customerTicket); //:contentReference[oaicite:9]{index=9}

                                    // 2) KITCHEN: semua SELAIN drink
                                    final kitchenItems = queueItemsFor(
                                      cart,
                                      typeMap,
                                      (t) => t != 'drink',
                                    ); //:contentReference[oaicite:10]{index=10}

                                    if (kitchenItems.isNotEmpty) {
                                      final kitchenTicket = QueueTicketData(
                                        queueNo: queueNo,
                                        dateTime: DateTime.now(),
                                        storeName: 'e+e Coffee',
                                        userName: cashierName,
                                        orderType: orderTypeName,
                                        items: kitchenItems,
                                        tableName: tableName,
                                      );
                                      try {
                                        await ReceiptPrinter
                                            .printKitchenWithSavedPrefs(context,
                                                kitchenTicket); //:contentReference[oaicite:11]{index=11}
                                      } catch (_) {}
                                    }

                                    // 3) BAR: hanya drink
                                    final barItems = queueItemsFor(
                                      cart,
                                      typeMap,
                                      (t) => t == 'drink',
                                    ); //:contentReference[oaicite:12]{index=12}

                                    if (barItems.isNotEmpty) {
                                      final barTicket = QueueTicketData(
                                        queueNo: queueNo,
                                        dateTime: DateTime.now(),
                                        storeName: 'e+e Coffee',
                                        userName: cashierName,
                                        orderType: orderTypeName,
                                        items: barItems,
                                        tableName: tableName,
                                      );
                                      try {
                                        await ReceiptPrinter.printBarWithSavedPrefs(
                                            context,
                                            barTicket); //:contentReference[oaicite:13]{index=13}
                                      } catch (_) {}
                                    }

                                    // ====== MOVE OPEN → DONE (seperti semula) ======
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
                                            'order saved offline — will sync when online');
                                      }
                                      await _showSuccess(
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

Future<void> _showSplitDialog(
  BuildContext context,
  WidgetRef ref, {
  required int cartTotalCents,
  required double taxRate, // 0.0–1.0
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

Future<void> _printKitchenFromBill(BuildContext context, WidgetRef ref,
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
      storeName: 'e+e coffee', // TODO: ganti ke dynamic kalau tersedia
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

Future<void> _showSuccess({
  required BuildContext context,
  required WidgetRef ref,
  required BillData bill,
  String? taxLabel, // NEW
}) async {
  final label = taxLabel ?? 'Tax';
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => Dialog(
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
                                '${it.name} × ${it.qty}',
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
                      onPressed: () => Navigator.pop(_),
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
                    await _printKitchenFromBill(context, ref, bill: bill);
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
