/// A-share trading calendar: detect trading days and market hours.
///
/// Supports external data injection from [TradingCalendarStore] via
/// [setExternalSource]. Falls back to weekday heuristic if no source set.
class TradingCalendar {
  static bool Function(DateTime)? _externalCheck;

  static void setExternalSource(bool Function(DateTime) checker) {
    _externalCheck = checker;
  }

  /// Check if a date is a trading day.
  static bool isTradingDay(DateTime date) {
    if (_externalCheck != null) return _externalCheck!(date);
    // Fallback: weekdays only (inaccurate for holidays/调班)
    return date.weekday != DateTime.saturday && date.weekday != DateTime.sunday;
  }

  /// Get last N trading days before a date.
  static List<DateTime> lastTradingDays(DateTime from, int count) {
    final days = <DateTime>[];
    var d = from.subtract(const Duration(days: 1));
    var limit = 400;
    while (days.length < count && limit-- > 0) {
      if (isTradingDay(d)) days.add(d);
      d = d.subtract(const Duration(days: 1));
    }
    return days;
  }

  /// Check if market is currently open (A-share: 9:30-11:30, 13:00-15:00 Beijing time).
  static bool isMarketOpen({String market = 'cn'}) {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 8),
    ); // Beijing time
    if (!isTradingDay(now)) return false;
    final minutes = now.hour * 60 + now.minute;
    if (market == 'cn') {
      return (minutes >= 570 && minutes <= 690) ||
          (minutes >= 780 && minutes <= 900);
    }
    return true;
  }
}
