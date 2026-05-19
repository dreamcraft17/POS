import 'package:intl/intl.dart';

final _idr = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp', decimalDigits: 0);

String rp(int cents) => _idr.format(cents);

String padRight(String s, int width) {
  if (s.length >= width) return s;
  return s + ' ' * (width - s.length);
}
