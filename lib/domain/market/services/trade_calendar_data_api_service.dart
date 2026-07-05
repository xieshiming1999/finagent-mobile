import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/http_utils.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../providers/data_api_interface_contract.dart';
import '../providers/data_api_interface_router.dart';
import '../providers/tushare_market_provider.dart';
import 'cache_policy.dart';

typedef TradeCalendarHttpGet =
    Future<http.Response> Function(Uri uri, {Map<String, String>? headers});

class TradeCalendarRouteResult {
  final List<Map<String, dynamic>> rows;
  final DataApiRouteProvenance provenance;

  const TradeCalendarRouteResult({
    required this.rows,
    required this.provenance,
  });
}

class TradeCalendarDataApiService {
  final String basePath;
  final DataManager? _dataManager;
  final ReusableDataStore _store;
  final DataApiInterfaceRouter _router;
  final TradeCalendarHttpGet _httpGet;
  TushareMarketProvider? _tushareProvider;

  TradeCalendarDataApiService({
    required this.basePath,
    DataManager? dataManager,
    ReusableDataStore? store,
    DataApiInterfaceRouter? router,
    TradeCalendarHttpGet? httpGet,
    TushareMarketProvider? tushareProvider,
  }) : _dataManager = dataManager,
       _store = store ?? ReusableDataStore(basePath),
       _router =
           router ??
           DataApiInterfaceRouter(runtimeBasePathProvider: () => basePath),
       _httpGet = httpGet ?? _defaultHttpGet,
       _tushareProvider = tushareProvider;

  Future<TradeCalendarRouteResult> fetchRange({
    String? startDate,
    String? endDate,
    int? year,
    String market = 'CN',
    CachePolicy policy = const CachePolicy(),
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    final range = _resolveRange(
      startDate: startDate,
      endDate: endDate,
      year: year,
    );
    final years = <int>{
      for (var y = range.start.year; y <= range.end.year; y++) y,
    }.toList(growable: false);
    final allRows = <Map<String, dynamic>>[];
    DataApiRouteProvenance? lastProvenance;
    for (final itemYear in years) {
      final result = await fetchYear(
        year: itemYear,
        market: market,
        policy: policy,
        constraint: constraint,
      );
      lastProvenance = result.provenance;
      allRows.addAll(result.rows);
    }
    final filtered =
        allRows
            .where((row) {
              final date = _normalizeSzseDate('${row['date'] ?? ''}');
              if (date == null) return false;
              return date.compareTo(range.startText) >= 0 &&
                  date.compareTo(range.endText) <= 0;
            })
            .toList(growable: false)
          ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    return TradeCalendarRouteResult(
      rows: filtered,
      provenance:
          lastProvenance ??
          const DataApiRouteProvenance(
            interfaceId: 'calendar.trade_days',
            capabilityId: 'local.cache',
            provider: 'local',
            providerName: 'local',
            canonicalSchema: 'trade_calendar',
            canonicalTable: 'trade_calendar',
            cacheStatus: 'cache-hit',
            cacheDecision:
                'cacheFirst read reusable local data; trade_calendar range produced no provider route iterations and returned local calendar provenance',
          ),
    );
  }

  Future<TradeCalendarRouteResult> fetchYear({
    required int year,
    String market = 'CN',
    CachePolicy policy = const CachePolicy(),
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) async {
    final result = await _router.runCapability<List<Map<String, dynamic>>>(
      interfaceId: 'calendar.trade_days',
      call: (capability) async {
        switch (capability.provider) {
          case FinanceProvider.szse:
            return DataApiProviderExecution(
              data: await _fetchSzseYear(year, market: market),
              source: 'SZSE',
              providerName: 'SZSE',
            );
          case FinanceProvider.tushare:
            return DataApiProviderExecution(
              data: await _fetchTushareYear(year, market: market),
              source: 'Tushare',
              providerName: 'Tushare',
            );
          default:
            return null;
        }
      },
      isUsable: (rows) => rows.isNotEmpty,
      emptyMessage: 'returned empty trade calendar rows',
      failureMessage: 'All trade calendar providers failed',
      constraint: constraint,
      cachePolicy: policy,
      readCache: () async {
        final rows = _cachedYearRows(year, market);
        if (!_hasYearCoverage(rows, year)) return null;
        return DataApiLocalCacheResult(
          data: rows,
          source: 'local trade_calendar',
          providerName: 'local',
        );
      },
    );

    if (result.provenance.cacheStatus != 'cache-hit') {
      _store.saveTradeCalendarRows(
        result.data,
        market: market,
        source: result.provenance.providerName,
      );
    }
    return TradeCalendarRouteResult(
      rows: result.data,
      provenance: result.provenance,
    );
  }

  List<Map<String, dynamic>> _cachedYearRows(int year, String market) {
    return _store.queryTradeCalendar(
      market: market,
      start: '$year-01-01',
      end: '$year-12-31',
      limit: 400,
    );
  }

  bool _hasYearCoverage(List<Map<String, dynamic>> rows, int year) {
    if (rows.length < 200) return false;
    final months = <int>{};
    for (final row in rows) {
      final date = '${row['date'] ?? ''}';
      if (!date.startsWith('$year-')) continue;
      final month = int.tryParse(date.substring(5, 7));
      if (month != null) months.add(month);
    }
    return months.length == 12;
  }

  Future<List<Map<String, dynamic>>> _fetchSzseYear(
    int year, {
    required String market,
  }) async {
    if (market != 'CN') {
      throw StateError('SZSE trade calendar only supports CN market');
    }
    final rows = <Map<String, dynamic>>[];
    for (var month = 1; month <= 12; month++) {
      final monthText = '$year-${month.toString().padLeft(2, '0')}';
      final uri =
          Uri.parse(
            'http://www.szse.cn/api/report/exchange/onepersistenthour/monthList',
          ).replace(
            queryParameters: {
              'month': monthText,
              'random': DateTime.now().millisecondsSinceEpoch.toString(),
            },
          );
      final response = await _httpGet(
        uri,
        headers: {
          'User-Agent': configuredHttpUserAgent(),
          'Referer': 'http://www.szse.cn/aboutus/calendar/',
        },
      ).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw StateError('SZSE calendar $monthText -> ${response.statusCode}');
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'];
      if (data is! List) continue;
      for (final item in data) {
        if (item is! Map) continue;
        final date = _normalizeSzseDate('${item['jyrq'] ?? ''}');
        if (date == null) continue;
        rows.add({
          'date': date,
          'market': 'CN',
          'is_trading_day': '${item['jybz'] ?? ''}' == '1' ? 1 : 0,
          'year': year,
          'month': month,
        });
      }
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> _fetchTushareYear(
    int year, {
    required String market,
  }) async {
    if (market != 'CN') {
      throw StateError('Tushare trade calendar only supports CN market');
    }
    final data = await _requireTushareProvider().callRaw('trade_cal', {
      'exchange': 'SSE',
      'start_date': '${year}0101',
      'end_date': '${year}1231',
    }, fields: 'exchange,cal_date,is_open');
    final items = data['items'] as List? ?? const [];
    final fields = data['fields'] as List? ?? const [];
    final rows = <Map<String, dynamic>>[];
    for (final row in items) {
      if (row is! List) continue;
      final mapped = <String, dynamic>{};
      for (var i = 0; i < fields.length && i < row.length; i++) {
        mapped['${fields[i]}'] = row[i];
      }
      final date = _normalizeSzseDate('${mapped['cal_date'] ?? ''}');
      if (date == null) continue;
      rows.add({
        'date': date,
        'market': 'CN',
        'is_trading_day': '${mapped['is_open'] ?? ''}' == '1' ? 1 : 0,
        'year': year,
        'month': int.tryParse(date.substring(5, 7)),
      });
    }
    return rows;
  }

  TushareMarketProvider _requireTushareProvider() {
    return _tushareProvider ??= FetcherTushareMarketProvider(
      _dataManager ?? DataManager(),
    );
  }

  String? _normalizeSzseDate(String raw) {
    final trimmed = raw.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
    if (RegExp(r'^\d{8}$').hasMatch(trimmed)) {
      return '${trimmed.substring(0, 4)}-${trimmed.substring(4, 6)}-${trimmed.substring(6, 8)}';
    }
    return null;
  }
}

class _TradeCalendarRange {
  final DateTime start;
  final DateTime end;
  final String startText;
  final String endText;

  const _TradeCalendarRange({
    required this.start,
    required this.end,
    required this.startText,
    required this.endText,
  });
}

_TradeCalendarRange _resolveRange({
  String? startDate,
  String? endDate,
  int? year,
}) {
  final nowYear = DateTime.now().year;
  final resolvedYear =
      year ?? _parseYear(startDate) ?? _parseYear(endDate) ?? nowYear;
  final startText = _normalizeRangeDate(startDate) ?? '$resolvedYear-01-01';
  final endText = _normalizeRangeDate(endDate) ?? '$resolvedYear-12-31';
  final start = DateTime.parse(startText);
  final end = DateTime.parse(endText);
  if (end.isBefore(start)) {
    throw ArgumentError('trade_calendar endDate must be on or after startDate');
  }
  return _TradeCalendarRange(
    start: start,
    end: end,
    startText: startText,
    endText: endText,
  );
}

int? _parseYear(String? value) {
  final normalized = _normalizeRangeDate(value);
  if (normalized == null || normalized.length < 4) return null;
  return int.tryParse(normalized.substring(0, 4));
}

String? _normalizeRangeDate(String? value) {
  if (value == null) return null;
  final text = value.trim().replaceAll('/', '-');
  if (text.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return text;
  if (RegExp(r'^\d{8}$').hasMatch(text)) {
    return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
  }
  throw ArgumentError(
    'trade_calendar startDate/endDate must be YYYY-MM-DD or YYYYMMDD',
  );
}

Future<http.Response> _defaultHttpGet(Uri uri, {Map<String, String>? headers}) {
  return http.get(uri, headers: headers);
}
