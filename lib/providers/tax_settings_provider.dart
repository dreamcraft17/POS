import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tax_prefs.dart';

/// Shared tax settings for cart/checkout. Invalidate after saving in Settings.
final taxSettingsProvider =
    FutureProvider<({bool enabled, double ratePercent})>((ref) async {
  return loadTaxSettings();
});
