import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/api_stats.dart';
import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/http_utils.dart';

class MarginTradingMarketDataService {
  final DataManager _dataManager;
  final http.Client _httpClient;

  MarginTradingMarketDataService({
    DataManager? dataManager,
    http.Client? httpClient,
  }) : _dataManager = dataManager ?? DataManager(),
       _httpClient = httpClient ?? http.Client();

  Future<Map<String, dynamic>> fetch(
    String code, {
    String? date,
    String? provider,
  }) async {
    final cleanCode = _normalizeCode(code);
    if (cleanCode.isEmpty) {
      throw ArgumentError('code required for margin_trading');
    }
    final tradeDate = _normalizeTradeDate(date);
    final route = _resolveRoute(cleanCode, provider);
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final rows = route == _MarginRoute.sse
        ? await _fetchSseRows(cleanCode, tradeDate, fetchedAt)
        : await _fetchSzseRows(cleanCode, tradeDate, fetchedAt);
    _dataManager.saveMarginTradingRows(rows);
    return {
      'action': 'margin_trading',
      'code': cleanCode,
      'date': tradeDate,
      'provider': 'szse',
      'interfaceId': 'market.margin_trading',
      'capabilityId': 'szse.market.margin_trading',
      'canonicalSchema': 'margin_trading',
      'canonicalTable': 'margin_trading',
      'sourceDataTime': _tradeDateIso(tradeDate),
      'asOf': _tradeDateIso(tradeDate),
      'fetchedAt': fetchedAt,
      'persisted': rows.isNotEmpty,
      'count': rows.length,
      'data': rows,
    };
  }

  Future<List<Map<String, dynamic>>> _fetchSseRows(
    String code,
    String tradeDate,
    String fetchedAt,
  ) async {
    final uri =
        Uri.https('query.sse.com.cn', '/marketdata/tradedata/queryMargin.do', {
          'isPagination': 'true',
          'tabType': 'mxtype',
          'detailsDate': tradeDate,
          'stockCode': code,
          'beginDate': '',
          'endDate': '',
          'pageHelp.pageSize': '5000',
          'pageHelp.pageCount': '50',
          'pageHelp.pageNo': '1',
          'pageHelp.beginPage': '1',
          'pageHelp.cacheSize': '1',
          'pageHelp.endPage': '21',
        });
    final response = await _get(
      uri,
      source: 'szse',
      headers: {
        'Referer': 'https://www.sse.com.cn/',
        'User-Agent': configuredHttpUserAgent(),
      },
    );
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final result = (body['result'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row.cast<String, dynamic>()))
        .toList(growable: false);
    return result
        .map((row) => _normalizeSseRow(row, tradeDate, fetchedAt))
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> _fetchSzseRows(
    String code,
    String tradeDate,
    String fetchedAt,
  ) async {
    final uri = Uri.https('www.szse.cn', '/api/report/ShowReport/data', {
      'SHOWTYPE': 'JSON',
      'CATALOGID': '1837_xxpl',
      'txtDate': _tradeDateIso(tradeDate),
      'txtZqdm': code,
      'tab2PAGENO': '1',
      'random': '0.24279342734085696',
      'TABKEY': 'tab2',
    });
    final response = await _get(
      uri,
      source: 'szse',
      headers: {
        'Referer': 'https://www.szse.cn/disclosure/margin/margin/index.html',
        'User-Agent': configuredHttpUserAgent(),
      },
    );
    final body = jsonDecode(response.body) as List<dynamic>;
    final table = body.isEmpty
        ? const <dynamic>[]
        : (body.first as Map<String, dynamic>)['data'] as List<dynamic>? ??
              const [];
    return table
        .whereType<Map>()
        .map(
          (row) => _normalizeSzseRow(
            Map<String, dynamic>.from(row.cast<String, dynamic>()),
            tradeDate,
            fetchedAt,
          ),
        )
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<http.Response> _get(
    Uri uri, {
    required String source,
    required Map<String, String> headers,
  }) async {
    final sw = Stopwatch()..start();
    try {
      final response = await _httpClient.get(uri, headers: headers);
      sw.stop();
      if (response.statusCode != 200) {
        _recordApi(
          source: source,
          uri: uri,
          statusCode: response.statusCode,
          durationMs: sw.elapsedMilliseconds,
          success: false,
          error: 'HTTP ${response.statusCode}',
        );
        throw StateError(
          'margin trading provider returned ${response.statusCode}',
        );
      }
      _recordApi(
        source: source,
        uri: uri,
        statusCode: response.statusCode,
        durationMs: sw.elapsedMilliseconds,
        success: true,
      );
      return response;
    } catch (e) {
      if (e is StateError &&
          '$e'.contains('margin trading provider returned')) {
        rethrow;
      }
      sw.stop();
      _recordApi(
        source: source,
        uri: uri,
        statusCode: 0,
        durationMs: sw.elapsedMilliseconds,
        success: false,
        error: '$e',
      );
      rethrow;
    }
  }

  Map<String, dynamic>? _normalizeSseRow(
    Map<String, dynamic> row,
    String tradeDate,
    String fetchedAt,
  ) {
    final code = _normalizeCode(
      '${row['stockCode'] ?? row['证券代码'] ?? row['code'] ?? ''}',
    );
    if (code.isEmpty) return null;
    return {
      'trade_date': _tradeDateIso(tradeDate),
      'code': code,
      'name': '${row['securityAbbr'] ?? row['证券简称'] ?? row['name'] ?? ''}',
      'provider': 'szse',
      'capability_id': 'szse.market.margin_trading',
      'source_action': 'sse.queryMargin.do',
      'financing_buy': _toNum(row['rzmre'] ?? row['融资买入额']),
      'financing_balance': _toNum(row['rzye'] ?? row['融资余额']),
      'margin_sell_volume': _toNum(row['rqmcl'] ?? row['融券卖出量']),
      'margin_balance_volume': _toNum(row['rqyl'] ?? row['融券余量']),
      'margin_balance': _toNum(row['rqye'] ?? row['rqylje'] ?? row['融券余额']),
      'total_balance': _toNum(
        row['rzrqye'] ?? row['rzrqjyzl'] ?? row['融资融券余额'],
      ),
      'fetched_at': fetchedAt,
      'raw_json': jsonEncode(row),
    };
  }

  Map<String, dynamic>? _normalizeSzseRow(
    Map<String, dynamic> row,
    String tradeDate,
    String fetchedAt,
  ) {
    final code = _normalizeCode(
      '${row['zqdm'] ?? row['证券代码'] ?? row['code'] ?? ''}',
    );
    if (code.isEmpty) return null;
    return {
      'trade_date': _tradeDateIso(tradeDate),
      'code': code,
      'name': '${row['zqjc'] ?? row['证券简称'] ?? row['name'] ?? ''}',
      'provider': 'szse',
      'capability_id': 'szse.market.margin_trading',
      'source_action': 'szse.ShowReport.data.tab2',
      'financing_buy': _toNum(row['jrrzmr'] ?? row['融资买入额']),
      'financing_balance': _toNum(row['jrrzye'] ?? row['融资余额']),
      'margin_sell_volume': _toNum(row['jrrjmc'] ?? row['融券卖出量']),
      'margin_balance_volume': _toNum(row['jrrjyl'] ?? row['融券余量']),
      'margin_balance': _toNum(row['jrrjye'] ?? row['融券余额']),
      'total_balance': _toNum(row['jrrzrjye'] ?? row['融资融券余额']),
      'fetched_at': fetchedAt,
      'raw_json': jsonEncode(row),
    };
  }

  void _recordApi({
    required String source,
    required Uri uri,
    required int statusCode,
    required int durationMs,
    required bool success,
    String? error,
  }) {
    ApiStats.instance.record(
      source: source,
      method: 'GET',
      url: uri.toString(),
      statusCode: statusCode,
      durationMs: durationMs,
      success: success,
      error: error,
    );
  }
}

enum _MarginRoute { sse, szse }

_MarginRoute _resolveRoute(String code, String? provider) {
  final normalizedProvider = provider?.trim().toLowerCase();
  if (normalizedProvider == 'sse') return _MarginRoute.sse;
  if (normalizedProvider == 'szse') return _MarginRoute.szse;
  if (code.startsWith('6') || code.startsWith('5') || code.startsWith('9')) {
    return _MarginRoute.sse;
  }
  return _MarginRoute.szse;
}

String _normalizeCode(String code) {
  final stripped = code
      .replaceAll(RegExp(r'\.(SH|SZ|BJ|OF)$', caseSensitive: false), '')
      .replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '')
      .trim();
  return RegExp(r'^\d{6}$').hasMatch(stripped) ? stripped : '';
}

String _normalizeTradeDate(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }
  final digits = raw.replaceAll('-', '').replaceAll('/', '');
  if (RegExp(r'^\d{8}$').hasMatch(digits)) return digits;
  throw ArgumentError('date must be YYYY-MM-DD or YYYYMMDD for margin_trading');
}

String _tradeDateIso(String compact) =>
    '${compact.substring(0, 4)}-${compact.substring(4, 6)}-${compact.substring(6, 8)}';

double? _toNum(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final cleaned = value.toString().replaceAll(',', '').trim();
  if (cleaned.isEmpty || cleaned == '--') return null;
  return double.tryParse(cleaned);
}
