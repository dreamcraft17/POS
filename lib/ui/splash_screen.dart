import 'package:flutter/material.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white, // ganti sesuai brand kalau perlu
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            // Logo
            SizedBox(
              width: 120,
              height: 120,
              child: Image(
                image: AssetImage('assets/icon/logo.png'),
                fit: BoxFit.contain,
              ),
            ),
            SizedBox(height: 16),
            // Judul
            Text(
              'e+e POS',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
                color: Colors.black87,
              ),
            ),
            SizedBox(height: 16),
            // Loading kecil
            SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      ),
    );
  }
}
