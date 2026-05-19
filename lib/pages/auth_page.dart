import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';

/// Simple reusable error modal
Future<void> _showErrorDialog(
  BuildContext context, {
  String title = 'Terjadi Kesalahan',
  required String message,
  String primaryText = 'OK',
  VoidCallback? onPrimary,
  String? secondaryText,
  VoidCallback? onSecondary,
  bool barrierDismissible = true,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          const Icon(Icons.error_outline, size: 24),
          const SizedBox(width: 8),
          Flexible(child: Text(title)),
        ],
      ),
      content: Text(message),
      actions: [
        if (secondaryText != null)
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onSecondary?.call();
            },
            child: Text(secondaryText),
          ),
        FilledButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            onPrimary?.call();
          },
          child: Text(primaryText),
        ),
      ],
    ),
  );
}

class AuthPage extends ConsumerStatefulWidget {
  const AuthPage({super.key});

  @override
  ConsumerState<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends ConsumerState<AuthPage> with TickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  Widget build(BuildContext context) {
    final isLoading = ref.watch(authControllerProvider).isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const _TitleWithLogo(title: 'Sign in to Cafe POS'),
        centerTitle: true,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TabBar(
                    controller: _tab,
                    tabs: const [Tab(text: 'Login'), Tab(text: 'Register')],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 330,
                    child: TabBarView(
                      controller: _tab,
                      children: [
                        _LoginForm(isLoading: isLoading),
                        _RegisterForm(isLoading: isLoading),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LoginForm extends ConsumerStatefulWidget {
  const _LoginForm({required this.isLoading});
  final bool isLoading;

  @override
  ConsumerState<_LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends ConsumerState<_LoginForm> {
  final _form = GlobalKey<FormState>();
  final _u = TextEditingController();
  final _p = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    try {
      await ref.read(authControllerProvider.notifier).login(_u.text.trim(), _p.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Welcome back!')));
        Navigator.of(context).maybePop(); // SessionGate akan auto-switch ke app utama
      }
    } catch (e) {
      if (!mounted) return;
      // Modal error: tetap di AuthPage
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      await _showErrorDialog(
        context,
        title: 'Login gagal',
        message: msg.isEmpty ? 'Invalid username atau password.' : msg,
        secondaryText: 'Lupa password?',
        onSecondary: () {
          // TODO: arahkan ke halaman reset password jika ada
          // Navigator.of(context).pushNamed('/forgot-password');
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isLoading;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TextFormField(
            controller: _u,
            enabled: !disabled,
            decoration: const InputDecoration(labelText: 'Username'),
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _p,
            enabled: !disabled,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            obscureText: _obscure,
            onFieldSubmitted: (_) => _submit(),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: disabled ? null : _submit,
            icon: const Icon(Icons.login),
            label: const Text('Login'),
          ),
          
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: disabled
                ? null
                : () {
                    _u.clear();
                    _p.clear();
                  },
            icon: const Icon(Icons.refresh),
            label: const Text('Clear'),
          ),
          
          const Spacer(),
          const _FootNote(),
        ],
      ),
    );
  }
}

class _RegisterForm extends ConsumerStatefulWidget {
  const _RegisterForm({required this.isLoading});
  final bool isLoading;

  @override
  ConsumerState<_RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends ConsumerState<_RegisterForm> {
  final _form = GlobalKey<FormState>();
  final _u = TextEditingController();
  final _p = TextEditingController();
  final _name = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _u.dispose();
    _p.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    try {
      await ref.read(authControllerProvider.notifier).register(
            _u.text.trim(),
            _p.text,
            displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Registered. Signed in!')));
        Navigator.of(context).maybePop();
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '').trim();
      await _showErrorDialog(
        context,
        title: 'Register gagal',
        message: msg.isEmpty ? 'Tidak dapat membuat akun. Coba lagi.' : msg,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabled = widget.isLoading;
    return Form(
      key: _form,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          TextFormField(
            controller: _u,
            enabled: !disabled,
            decoration: const InputDecoration(labelText: 'Username'),
            textInputAction: TextInputAction.next,
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            enabled: !disabled,
            decoration: const InputDecoration(labelText: 'Display name (optional)'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _p,
            enabled: !disabled,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
              ),
            ),
            obscureText: _obscure,
            onFieldSubmitted: (_) => _submit(),
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : (v.length < 6 ? 'Min 6 chars' : null),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: disabled ? null : _submit,
            icon: const Icon(Icons.person_add),
            label: const Text('Register'),
          ),
          const Spacer(),
          const _FootNote(),
        ],
      ),
    );
  }
}

class _FootNote extends StatelessWidget {
  const _FootNote();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 16),
      child: Text(
        'Your session is stored securely. You can go offline; the app keeps you signed in.',
        style: TextStyle(color: Colors.black54),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TitleWithLogo extends StatelessWidget {
  const _TitleWithLogo({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset('assets/icon/logo.png', height: 100, width: 100),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
