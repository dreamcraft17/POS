import 'package:flutter/material.dart';
import 'bootstrap/splash_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Jangan init di sini supaya splash keburu tampil.
  runApp(const SplashBootstrap());
}
