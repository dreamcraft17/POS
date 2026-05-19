// lib/customer_display_main.dart
import 'package:ee_pos/providers/cart_provider.dart';
import 'package:ee_pos/utils/formatting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';


@pragma('vm:entry-point') // penting untuk secondary engine
void customerDisplayMain() {
  runApp(const ProviderScope(child: CustomerDisplayApp()));
}

class CustomerDisplayApp extends StatelessWidget {
  const CustomerDisplayApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Customer Display',
      theme: ThemeData(useMaterial3: true, brightness: Brightness.light),
      home: const CustomerDisplayScreen(),
    );
  }
}

class CustomerDisplayScreen extends ConsumerWidget {
  const CustomerDisplayScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart = ref.watch(cartProvider); // ← keranjang yang sama:contentReference[oaicite:1]{index=1}
    final subtotal = cart.fold<int>(0, (s, it) => s + it.priceCents * it.qty);
    // (opsional) kalau mau konsisten dengan panel, ambil pajak/diskon sama seperti CartPanel:contentReference[oaicite:2]{index=2}
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Welcome 👋',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text('Order Preview',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: Colors.black54)),
              const SizedBox(height: 16),
              Expanded(
                child: cart.isEmpty
                    ? const Center(
                        child: Text(
                          'No items yet',
                          style: TextStyle(fontSize: 18, color: Colors.black54),
                        ),
                      )
                    : ListView.builder(
                        itemCount: cart.length,
                        itemBuilder: (_, i) {
                          final it = cart[i];
                          return ListTile(
                            title: Text('${it.name} × ${it.qty}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            trailing:
                                Text(rp(it.priceCents * it.qty)), // formattermu
                            subtitle:
                                Text(rp(it.priceCents), style: const TextStyle(fontSize: 12)),
                          );
                        },
                      ),
              ),
              const Divider(),
              Row(
                children: [
                  const Text('Subtotal', style: TextStyle(color: Colors.black54)),
                  const Spacer(),
                  Text(rp(subtotal), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 8),
              Text('Thank you!', textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.green.shade700, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }
}
