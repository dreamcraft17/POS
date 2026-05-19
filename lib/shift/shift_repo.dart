import 'package:shared_preferences/shared_preferences.dart';

class ShiftRepo {
  static const _kStartAt = 'shift.start_at_iso';
  static const _kOpeningCash = 'shift.opening_cash_cents';
  static const _kEndedDate = 'shift.ended_date_iso';

  Future<void> startShift({required int openingCashCents, DateTime? startAt}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_kStartAt, (startAt ?? DateTime.now()).toIso8601String());
    await sp.setInt(_kOpeningCash, openingCashCents);
  }

  Future<({DateTime? startAt, int openingCashCents})> current() async {
    final sp = await SharedPreferences.getInstance();
    final iso = sp.getString(_kStartAt);
    final cash = sp.getInt(_kOpeningCash) ?? 0;
    return (startAt: iso == null ? null : DateTime.parse(iso), openingCashCents: cash);
  }

  

  // Future<void> endShift() async {
  //   final sp = await SharedPreferences.getInstance();
  //   await sp.remove(_kStartAt);
  //   await sp.remove(_kOpeningCash);
  // }

  Future<void> endShift() async{
    final sp = await SharedPreferences.getInstance();
    final today = DateTime.now();
    await sp.setString(_kEndedDate, DateTime(today.year, today.month, today.day).toIso8601String());
    await sp.remove(_kStartAt);
    await sp.remove(_kOpeningCash);
  }

  Future<bool> hasEndedToday() async {
    final sp = await SharedPreferences.getInstance();
    final iso = sp.getString(_kEndedDate);
    if(iso == null) return false;
    final endedDate = DateTime.parse(iso);
    final today = DateTime.now();
    return endedDate.year == today.year && endedDate.month == today.month && endedDate.day == today.day;
  }


  

  
}
