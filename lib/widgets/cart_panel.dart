import 'dart:convert';
import 'package:ee_pos/models/cart_item.dart';
import 'package:ee_pos/repositories/open_bills_repo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/discount_providers.dart';
import '../providers/cart_provider.dart';
import '../providers/products_provider.dart';
import '../providers/order_type_providers.dart';
import '../models/product.dart';
import '../ui/pos_theme.dart';
import '../utils/formatting.dart';
import './bill_receipt.dart';
import '../providers/auth_providers.dart'; // for cashier name
import '../ui/top_message.dart';
import '../providers/cart_draft_provider.dart';
import '../providers/cart_totals_provider.dart';
import 'cart/cart_dialogs.dart';
import 'cart/cart_helpers.dart';
import 'cart/cart_ui_shared.dart';

class CartPanel extends ConsumerStatefulWidget {
  const CartPanel({super.key, required this.onRefreshAll});
  final Future<void> Function() onRefreshAll;

  @override
  ConsumerState<CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends ConsumerState<CartPanel> {
  @override
  Widget build(BuildContext context) {
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
              child: const _CartList(),
            ),
          ),
          const Divider(color: PosTheme.border),
          _CartTotalsBlock(onRefreshAll: widget.onRefreshAll),
        ],
      ),
    );
  }
}

/// Total + tombol aksi — terpisah dari list agar scroll cart tidak rebuild footer.
class _CartTotalsBlock extends ConsumerWidget {
  const _CartTotalsBlock({required this.onRefreshAll});
  final Future<void> Function() onRefreshAll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final totals = ref.watch(cartTotalsProvider);
    return Column(
      children: [
        _TotalsSection(
          subtotal: totals.subtotal,
          discount: totals.discount,
          tax: totals.tax,
          total: totals.total,
          showDiscount: totals.showDiscount,
          discountLabel: totals.discountLabel,
          taxLabelOverride: totals.taxLabel,
        ),
        const SizedBox(height: 8),
        _ActionsSection(
          onRefreshAll: onRefreshAll,
          cartTotalCents: totals.total,
          taxRate: totals.taxRate,
          taxLabel: totals.taxLabel,
        ),
      ],
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
//           title: Text('${it.name} Ã— ${it.qty}',
//               style: const TextStyle(
//                   fontWeight: FontWeight.w600, color: PosTheme.black)),
//           subtitle: Text(
//             '${rp(it.priceCents)} Â· ${rp(it.priceCents * it.qty)}',
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


class _CartList extends ConsumerWidget {
  const _CartList();

  static String _keyOf(CartItem p) => '${p.sku}|${p.priceCents}';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider);
    final baseAsync = ref.watch(cartDraftBaseQuotaProvider);
    final baseQty = baseAsync.valueOrNull ?? const {};

    if (cart.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
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

    final rows = _buildRowMeta(cart, baseQty);
    final hasBase = baseQty.values.any((v) => v > 0);
    final itemCount = rows.length + (hasBase ? 1 : 0);

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      cacheExtent: 240,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (hasBase && index == 0) {
          return const _CartOldLabel();
        }
        final rowIndex = hasBase ? index - 1 : index;
        final meta = rows[rowIndex];
        if (meta.showSeparator) {
          return const _CartSectionSeparator();
        }
        final item = meta.item!;
        return _CartRowWithAddedFlag(
          key: ValueKey('${item.sku}|${item.priceCents}|${item.qty}'),
          product: item,
          isAdded: meta.isAdded,
        );
      },
    );
  }

  static List<_CartRowMeta> _buildRowMeta(
    List<CartItem> cart,
    Map<String, int> baseQty,
  ) {
    final running = <String, int>{};
    final out = <_CartRowMeta>[];
    var separatorInserted = false;
    final hasBase = baseQty.values.any((v) => v > 0);

    for (final item in cart) {
      final key = _keyOf(item);
      final before = running[key] ?? 0;
      final seen = before + item.qty;
      running[key] = seen;

      final base = baseQty[key] ?? 0;
      final wasWithinBase = before < base;
      final nowExceedsBase = seen > base;

      if (!separatorInserted && hasBase && wasWithinBase && nowExceedsBase) {
        out.add(const _CartRowMeta.separator());
        separatorInserted = true;
      } else if (!separatorInserted && !hasBase) {
        out.add(const _CartRowMeta.separator());
        separatorInserted = true;
      }

      out.add(_CartRowMeta(
        item: item,
        isAdded: seen > base,
      ));
    }
    return out;
  }
}

class _CartRowMeta {
  const _CartRowMeta({required this.item, required this.isAdded})
      : showSeparator = false;
  const _CartRowMeta.separator()
      : item = null,
        isAdded = false,
        showSeparator = true;

  final CartItem? item;
  final bool isAdded;
  final bool showSeparator;
}

class _CartRowWithAddedFlag extends ConsumerWidget {
  const _CartRowWithAddedFlag({
    super.key,
    required this.product,
    required this.isAdded,
  });

  final CartItem product;
  final bool isAdded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
  final double taxRate; // 0.0â€“1.0
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
    final cartEmpty = ref.watch(cartProvider.select((c) => c.isEmpty));

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
      if (ref.read(cartProvider).isEmpty) return;
      await showCartPayDialog(
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
    //     showTopError(context, 'Cart kosong â€” belum ada item');
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
    //       'customer_name': name, // simpan nama â€” dipakai sebagai Table
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
    //             : 'Bill disimpan offline â€” akan disinkron saat online',
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
    //       // jangan blokir flow â€” cukup kasih info kalau gagal print kitchen
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
  await sp.remove('pos.active.draft.mode'); // â¬…ï¸ new
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
      // mode CONTINUE â†’ boleh reuse nama dari draft aktif
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
      // BUKAN dari Continue â†’ PESANAN BARU â†’ WAJIB minta nama BARU
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
        // kalau flag nyasar â†’ jatuhkan ke create baru
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
          ref.invalidate(cartDraftBaseQuotaProvider);
        }
        return;
      }
    }

    // ================= PESANAN BARU â†’ CREATE DRAFT BARU =================
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
      ref.invalidate(cartDraftBaseQuotaProvider);
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
      if (ref.read(cartProvider).isEmpty) return;
      await showCartSplitDialog(
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
        storeName: receiptStoreTitle(ref),
        userName: cashierName,
        orderType: orderTypeName,
        items: customerItems,
        tableName: tableName, // âœ… tampilkan di tiket Queue
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
                onPressed: cartEmpty ? null : saveBillLocalOnly,
                style: outlinedBlack,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save Bill'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: cartEmpty ? null : printQueue,
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
                onPressed: cartEmpty ? null : showSplitDialog,
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
                onPressed: cartEmpty ? null : pay,
                style: filledBlack,
                child: const Text('Pay'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: cartEmpty
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
