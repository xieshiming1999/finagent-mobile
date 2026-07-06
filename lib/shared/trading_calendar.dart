import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../agent/log.dart';
import '../agent/data_fetcher/provider_policy.dart';
import '../domain/market/providers/data_api_interface_contract.dart';
import '../domain/market/services/cache_policy.dart';
import '../domain/market/services/trade_calendar_data_api_service.dart';

/// A-share trading calendar with online data, local cache, and user overrides.
///
/// Data source: SZSE (Shenzhen Stock Exchange) official API.
/// Persistence: {documentsDir}/agents/trading_calendar.json
class TradingCalendarStore {
  TradingCalendarStore({String? basePath, TradeCalendarDataApiService? dataApi})
    : _basePath = basePath,
      _dataApi = dataApi;

  Set<String> _tradingDays = {}; // "yyyy-MM-dd" from API
  Map<String, bool> _overrides = {}; // user manual overrides
  String? _path;
  String? _basePath;
  TradeCalendarDataApiService? _dataApi;
  DateTime? lastFetched;
  int? _dataYear; // which year's data we have

  bool get isEmpty => _tradingDays.isEmpty;
  int get tradingDayCount => _tradingDays.length;
  Map<String, bool> get overrides => Map.unmodifiable(_overrides);

  /// Load from local JSON cache.
  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _path = '${dir.path}/agents/trading_calendar.json';
    _basePath ??= '${dir.path}/agents/finance';
    _dataApi ??= TradeCalendarDataApiService(basePath: _basePath!);
    try {
      final file = File(_path!);
      if (!file.existsSync()) return;
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final days = json['tradingDays'] as List?;
      if (days != null) {
        _tradingDays = days.cast<String>().toSet();
      }
      final ovr = json['overrides'] as Map<String, dynamic>?;
      if (ovr != null) {
        _overrides = ovr.map((k, v) => MapEntry(k, v as bool));
      }
      final fetched = json['lastFetched'] as String?;
      if (fetched != null) lastFetched = DateTime.tryParse(fetched);
      _dataYear = json['dataYear'] as int?;
    } catch (e) {
      log('TradingCalendar', 'Load error: $e');
    }
  }

  void _save() {
    if (_path == null) return;
    try {
      final file = File(_path!);
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'version': 1,
          'dataYear': _dataYear,
          'lastFetched': lastFetched?.toIso8601String(),
          'tradingDayCount': _tradingDays.length,
          'tradingDays': _tradingDays.toList()..sort(),
          'overrides': _overrides,
        }),
      );
    } catch (e) {
      log('TradingCalendar', 'Save error: $e');
    }
  }

  /// Fetch trading calendar through the calendar.trade_days data API interface.
  /// Returns true if successful.
  Future<bool> fetchFromApi({int? year}) async {
    year ??= DateTime.now().year;
    final dataApi = _dataApi;
    if (dataApi == null) {
      log('TradingCalendar', 'Data API service is not initialized');
      return false;
    }
    try {
      final result = await dataApi.fetchYear(
        year: year,
        policy: const CachePolicy(mode: CachePolicyMode.liveOnly),
        constraint: const DataApiProviderConstraint(
          provider: FinanceProvider.szse,
          providerMode: DataApiProviderMode.strict,
          allowFallback: false,
        ),
      );
      final days = result.rows
          .where((row) => row['is_trading_day'] == 1)
          .map((row) => '${row['date']}')
          .where((date) => date.isNotEmpty)
          .toSet();
      if (days.isEmpty) {
        log('TradingCalendar', 'calendar.trade_days returned no open days');
        return false;
      }
      _tradingDays = days;
      _dataYear = year;
      lastFetched = DateTime.now();
      _save();
      log(
        'TradingCalendar',
        'Fetched $year: ${days.length} trading days via '
            '${result.provenance.interfaceId}/${result.provenance.provider}',
      );
      return true;
    } catch (e) {
      log('TradingCalendar', 'calendar.trade_days fetch error: $e');
      return false;
    }
  }

  /// Check if a date is a trading day.
  /// Priority: user overrides > API data > weekday fallback.
  bool isTradingDay(DateTime date) {
    final key = _dateKey(date);

    // 1. User override takes priority
    if (_overrides.containsKey(key)) return _overrides[key]!;

    // 2. API data
    if (_tradingDays.isNotEmpty) return _tradingDays.contains(key);

    // 3. Fallback: weekdays only
    return date.weekday != DateTime.saturday && date.weekday != DateTime.sunday;
  }

  /// Check if A-share market is currently open.
  bool isMarketOpen({String market = 'cn'}) {
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 8),
    ); // Beijing time
    if (!isTradingDay(now)) return false;
    final minutes = now.hour * 60 + now.minute;
    if (market == 'cn') {
      // 9:30-11:30, 13:00-15:00
      return (minutes >= 570 && minutes <= 690) ||
          (minutes >= 780 && minutes <= 900);
    }
    return true;
  }

  /// Get last N trading days before the given date.
  List<DateTime> lastTradingDays(DateTime from, int count) {
    final days = <DateTime>[];
    var d = from.subtract(const Duration(days: 1));
    var limit = 400; // safety (accounts for leap years)
    while (days.length < count && limit-- > 0) {
      if (isTradingDay(d)) days.add(d);
      d = d.subtract(const Duration(days: 1));
    }
    return days;
  }

  /// Get all days in a month with their trading status.
  List<CalendarDay> getMonthDays(int year, int month) {
    final first = DateTime(year, month, 1);
    final last = DateTime(year, month + 1, 0);
    final result = <CalendarDay>[];
    for (var d = first; !d.isAfter(last); d = d.add(const Duration(days: 1))) {
      final key = _dateKey(d);
      result.add(
        CalendarDay(
          date: d,
          isTrading: isTradingDay(d),
          isOverride: _overrides.containsKey(key),
          hasData: _tradingDays.isNotEmpty,
        ),
      );
    }
    return result;
  }

  /// Toggle a day's trading status (user override).
  void setOverride(DateTime date, bool isTrading) {
    _overrides[_dateKey(date)] = isTrading;
    _save();
  }

  /// Remove user override for a day (revert to API data).
  void removeOverride(DateTime date) {
    _overrides.remove(_dateKey(date));
    _save();
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

/// A single day in the calendar grid.
class CalendarDay {
  final DateTime date;
  final bool isTrading;
  final bool isOverride;
  final bool hasData; // whether we have API data (vs fallback)

  const CalendarDay({
    required this.date,
    required this.isTrading,
    required this.isOverride,
    required this.hasData,
  });
}
