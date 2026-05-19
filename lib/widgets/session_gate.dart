// lib/widgets/session_gate.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';

class SessionGate extends ConsumerWidget {
  final Widget child;
  final Widget Function(BuildContext context)? unauthBuilder;

  const SessionGate({
    super.key,
    required this.child,
    this.unauthBuilder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return auth.when(
      data: (u) {
        if (u == null) {
          return unauthBuilder?.call(context) ??
              const Center(child: Text('Please login'));
        }
        return child;
      },
      error: (e, _) => Center(child: Text('Auth error: $e')),
      loading: () => const Center(child: CircularProgressIndicator()),
    );
  }
}
