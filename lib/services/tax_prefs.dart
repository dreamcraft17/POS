import 'package:shared_preferences/shared_preferences.dart';

/// ===== Keys =====
const String kTaxEnabledKey = 'tax_enabled';
const String kTaxRatePctKey = 'tax_rate_percent';

/// ===== Defaults =====
const bool   kDefaultTaxEnabled = true;
const double kDefaultTaxRatePct = 10.0;

/// Simpan setting pajak (enable + persen)
Future<void> saveTaxSettings({
  required bool enabled,
  required double ratePercent,
}) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setBool(kTaxEnabledKey, enabled);
  // clamp() -> num, jadi pastikan jadi double
  final double clamped = ratePercent.clamp(0.0, 100.0).toDouble();
  await sp.setDouble(kTaxRatePctKey, clamped);
}

/// Ambil setting pajak sebagai named record: (enabled, ratePercent)
Future<({bool enabled, double ratePercent})> loadTaxSettings() async {
  final sp = await SharedPreferences.getInstance();
  final bool enabled = sp.getBool(kTaxEnabledKey) ?? kDefaultTaxEnabled;
  final double rate  = sp.getDouble(kTaxRatePctKey) ?? kDefaultTaxRatePct;
  final double clamped = rate.clamp(0.0, 100.0).toDouble();
  return (enabled: enabled, ratePercent: clamped);
}

/// Helper: ambil tax rate sebagai pecahan 0.0–1.0 (mis. 11% -> 0.11).
/// Jika tax disabled, hasilnya 0.0.
Future<double> currentTaxRateFraction() async {
  final s = await loadTaxSettings();
  return s.enabled ? (s.ratePercent / 100.0) : 0.0;
}

/// Opsional: toggle cepat untuk ON/OFF pajak (tanpa ubah persen)
Future<void> setTaxEnabled(bool enabled) async {
  final sp = await SharedPreferences.getInstance();
  await sp.setBool(kTaxEnabledKey, enabled);
}

/// Opsional: set hanya persen pajak (0–100), tanpa sentuh enable flag
Future<void> setTaxRatePercent(double ratePercent) async {
  final sp = await SharedPreferences.getInstance();
  final double clamped = ratePercent.clamp(0.0, 100.0).toDouble();
  await sp.setDouble(kTaxRatePctKey, clamped);
}
