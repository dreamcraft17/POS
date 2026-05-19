// lib/models/menu.dart
class MenuComponent {
  final String productSku;
  final int qty;
  MenuComponent({required this.productSku, required this.qty});

  factory MenuComponent.fromJson(Map<String, dynamic> j) =>
      MenuComponent(productSku: j['product_sku'], qty: (j['qty'] as num).toInt());
  Map<String, dynamic> toJson() => {'product_sku': productSku, 'qty': qty};
}

// class MenuItemModel {
//   final String code;
//   final String name;
//   final int priceCents; // base price (boleh 0 kalau by variant)
//   // final String? imageUrl; // relative path dari server /menu-images/xxx.jpg
//   final bool enabled;
//   final int sort;
//   final List<MenuComponent> components;

//   // NEW
//   final List<dynamic> variants; // gunakan MenuVariant.fromJson saat parse

//   // NEW (opsional, buat audit)
//   final int? createdById; 
//   final String? createdBy;

//   MenuItemModel({
//     required this.code,
//     required this.name,
//     required this.priceCents,
//     // required this.imageUrl,
//     required this.enabled,
//     required this.sort,
//     required this.components,
//     required this.variants,
//     this.createdById,        // NEW
//     this.createdBy,          // NEW
//   });

//   factory MenuItemModel.fromJson(Map<String, dynamic> j) => MenuItemModel(
//         code: j['code'],
//         name: j['name'],
//         priceCents: (j['price_cents'] as num).toInt(),
//         // imageUrl: j['image_url'],
//         enabled: (j['enabled'] == true || j['enabled'] == 1),
//         sort: (j['sort'] ?? 999) is int ? j['sort'] : int.tryParse('${j['sort'] ?? 999}') ?? 999,
//         components: (j['components'] as List? ?? [])
//             .map((e) => MenuComponent.fromJson(Map<String, dynamic>.from(e)))
//             .toList(),
//         variants: (j['variants'] as List? ?? []),
//         // kalau backend balikin, kita baca; kalau nggak ya null
//         createdById: (j['created_by_id'] as num?)?.toInt(),
//         createdBy: j['created_by']?.toString(),
//       );

//   Map<String, dynamic> toCreateBody() => {
//         'code': code,
//         'name': name,
//         'price_cents': priceCents,
//         // 'image_url': imageUrl,
//         'enabled': enabled,
//         'sort': sort,
//         // 'components': components.map((e) => e.toJson()).toList(),
//         if (components.isNotEmpty) 'components': components.map((e) => e.toJson()).toList(),
//           'components': components.map((e) => e.toJson()).toList(),
//         'variants': variants,
//         if (createdById != null) 'created_by_id': createdById, // NEW
//         if (createdBy != null) 'created_by': createdBy,       // NEW
//       };
// }


class MenuItemModel {
  final String code;
  final String name;
  final int priceCents;
  final bool enabled;
  final int sort;
  final List<MenuComponent> components;
  final List<dynamic> variants;

  // NEW
  final String? type;

  // NEW (opsional, buat audit)
  final int? createdById;
  final String? createdBy;

  MenuItemModel({
    required this.code,
    required this.name,
    required this.priceCents,
    required this.enabled,
    required this.sort,
    required this.components,
    required this.variants,
    this.type,               // NEW
    this.createdById,
    this.createdBy,
  });

  factory MenuItemModel.fromJson(Map<String, dynamic> j) => MenuItemModel(
        code: j['code'],
        name: j['name'],
        priceCents: (j['price_cents'] as num).toInt(),
        enabled: (j['enabled'] == true || j['enabled'] == 1),
        sort: (j['sort'] ?? 999) is int ? j['sort'] : int.tryParse('${j['sort'] ?? 999}') ?? 999,
        components: (j['components'] as List? ?? [])
            .map((e) => MenuComponent.fromJson(Map<String, dynamic>.from(e)))
            .toList(),
        variants: (j['variants'] as List? ?? []),
        type: j['type']?.toString(),   // NEW
        createdById: (j['created_by_id'] as num?)?.toInt(),
        createdBy: j['created_by']?.toString(),
      );

  Map<String, dynamic> toCreateBody() => {
        'code': code,
        'name': name,
        'price_cents': priceCents,
        'enabled': enabled,
        'sort': sort,
        if (components.isNotEmpty) 'components': components.map((e) => e.toJson()).toList(),
        'variants': variants,
        if (type != null) 'type': type,              // NEW
        if (createdById != null) 'created_by_id': createdById,
        if (createdBy != null) 'created_by': createdBy,
      };
}
