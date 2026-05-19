import 'package:ee_pos/widgets/settings/hardware/printer_settings_panel_bar.dart';

import '../shift/shift_history_page.dart';
import 'package:ee_pos/widgets/settings/hardware/printer_settings_panel.dart';
import 'package:ee_pos/widgets/settings/shift/shift_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../widgets/settings/sidebar_menu.dart';
import '../widgets/settings/checkout/payments_panel.dart';
import '../widgets/settings/checkout/taxes_panel.dart';
import '../widgets/settings/checkout/checkout_settings_panel.dart';
import '../widgets/settings/receipt/receipt_template_panel.dart';
// NEW
import '../widgets/settings/checkout/discounts_panel.dart';
import '../widgets/settings/checkout/order_types_panel.dart'; // NEW
import 'package:ee_pos/widgets/settings/hardware/printer_settings_panel_customer.dart';
import 'package:ee_pos/widgets/settings/hardware/printer_settings_panel_kitchen.dart';

class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});
  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  final List<SidebarItem> items = const [
    SidebarItem.header('CHECKOUT'),
    SidebarItem.item('Payments'),
    SidebarItem.item('Taxes'),
    SidebarItem.item('Discounts'),
    SidebarItem.item('Order Types'),
    SidebarItem.item('Checkout Settings'),
    SidebarItem.item('Receipt Template'),
    SidebarItem.header('HARDWARE'),
    SidebarItem.item('Printer'),
    SidebarItem.item('Kitchen Printer'),
    SidebarItem.item('Checker'),
    SidebarItem.item('Barcode Scanners'),
    SidebarItem.header('SHIFT'),
    SidebarItem.item('Shift'),
    SidebarItem.item('Shift History'),
  ];

  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = items.indexWhere((e) => e.type == SidebarItemType.item);
  }

  @override
  Widget build(BuildContext context) {
    final itemIndices = items
        .asMap()
        .entries
        .where((e) => e.value.type == SidebarItemType.item)
        .map((e) => e.key)
        .toList();
    final logicalIndex = itemIndices.indexOf(_selected);
    return Row(
      children: [
        SidebarMenu(
          items: items,
          selectedIndex: _selected,
          width: 240,
          onSelect: (i) {
            if (items[i].type == SidebarItemType.header) return;
            setState(() => _selected = i);
          },
        ),
        Expanded(
          child: Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: _buildRightPane(logicalIndex),
          ),
        ),
      ],
    );
  }

  Widget _buildRightPane(int logicalIndex) {
    if (logicalIndex < 0)
      return const Center(child: Text('Select a setting from the left'));
    switch (logicalIndex) {
      case 0:
        return const PaymentsPanel();
      case 1:
        return const TaxesPanel();
      case 2:
        return const DiscountsPanel();
      case 3:
        return const OrderTypesPanel(); // NEW
      case 4:
        return const CheckoutSettingsPanel();
      case 5:
        return const ReceiptTemplatePanel();
      // case 6: return const PrinterSettingsPanel();
      // case 7: return const PrinterSettingsPanel(profilePrefix: 'kitchen.printer', titleOverride: 'Kitchen Printer');
      case 6:
        return const CustomerPrinterSettingsPanel();
      case 7:
        return const KitchenPrinterSettingsPanel();
      case 8:
        return const BarPrinterSettingsPanel();
      case 10:
        return const ShiftPanel();
         case 11:
        return const ShiftHistoryPage(
          outletName: 'e+e Coffee n Kitchen',
          cashierNameForReprint: 'Reprint',
          paper: '80',
          methodAliases: {'BCA_QR': 'BCA QR', 'BCA_EDC': 'BCA'},
          logoAsset: 'assets/receipt/logo_bill.png',
        );
      default:
        return const Center(child: Text('This section is coming soon'));
    }
  }
}
