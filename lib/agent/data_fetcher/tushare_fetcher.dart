import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_stats.dart';
import 'base_fetcher.dart';
import 'cache.dart';
import 'http_utils.dart';
import 'models.dart';

String _normalizeCode(String code) {
  final s = code.replaceAll(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '');
  return s.replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '');
}

bool isTushareRateLimitMessage(String message) {
  return RegExp(
    r'频率|limit|每分钟|最多访问|访问.*次',
    caseSensitive: false,
  ).hasMatch(message);
}

/// Tushare Pro data fetcher.
/// Requires TUSHARE_TOKEN in API config.
/// API: POST http://api.tushare.pro with JSON body.
class TushareFetcher extends BaseFetcher {
  final String token;

  @override
  String get name => 'Tushare';
  @override
  int get priority => 40;

  static const _apiUrl = 'http://api.tushare.pro';

  final _rateLimiter = RateLimiter(minInterval: Duration(milliseconds: 500));
  final _circuitBreaker = CircuitBreaker();
  final _klineCache = DataCache<List<KlineBar>>(ttl: Duration(minutes: 30));
  final _endpointLastCall = <String, DateTime>{};

  static const _endpointMinIntervals = <String, Duration>{
    'trade_cal': Duration(seconds: 61),
  };
  static const _disabledApis = <String>{
    'fina_indicator',
    'income',
    'balancesheet',
    'cashflow',
    'moneyflow',
    'fund_basic',
    'fund_nav',
  };

  TushareFetcher({required this.token});

  /// Generic raw API call — pass any api_name + params.
  Future<Map<String, dynamic>> callRaw(
    String apiName,
    Map<String, dynamic> params, {
    String fields = '',
  }) async {
    return _call(apiName, params, fields: fields);
  }

  @override
  bool canHandle(String code) {
    final c = _normalizeCode(code);
    return RegExp(r'^\d{6}$').hasMatch(c);
  }

  /// Call Tushare API.
  Future<Map<String, dynamic>> _call(
    String apiName,
    Map<String, dynamic> params, {
    String fields = '',
  }) async {
    final sw = Stopwatch()..start();
    try {
      _enforceEndpointGuard(apiName);
      await _rateLimiter.wait();

      final body = jsonEncode({
        'api_name': apiName,
        'token': token,
        'params': params,
        if (fields.isNotEmpty) 'fields': fields,
      });

      final response = await http
          .post(
            Uri.parse(_apiUrl),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 15));
      sw.stop();

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final code = json['code'] as int?;

      if (code != 0) {
        final msg = json['msg'] as String? ?? 'Unknown error';
        ApiStats.instance.record(
          source: 'tushare',
          method: 'POST',
          url: '$_apiUrl ($apiName)',
          statusCode: response.statusCode,
          durationMs: sw.elapsedMilliseconds,
          success: false,
          error: msg,
        );
        if (msg.contains('权限') ||
            msg.contains('积分') ||
            msg.contains('permission')) {
          throw DataFetchError('Tushare 权限不足: $msg (需要更多积分或更高权限)');
        }
        if (isTushareRateLimitMessage(msg)) {
          throw DataFetchError(
            'TUSHARE_RATE_LIMIT: $apiName frequency limited by Tushare: $msg',
          );
        }
        throw DataFetchError('Tushare API error ($code): $msg');
      }

      ApiStats.instance.record(
        source: 'tushare',
        method: 'POST',
        url: '$_apiUrl ($apiName)',
        statusCode: 200,
        durationMs: sw.elapsedMilliseconds,
        success: true,
      );
      return json['data'] as Map<String, dynamic>? ?? {};
    } catch (e) {
      if (!sw.isRunning) rethrow;
      sw.stop();
      ApiStats.instance.record(
        source: 'tushare',
        method: 'POST',
        url: '$_apiUrl ($apiName)',
        statusCode: -1,
        durationMs: sw.elapsedMilliseconds,
        success: false,
        error: '$e',
      );
      rethrow;
    }
  }

  void _enforceEndpointGuard(String apiName) {
    if (_disabledApis.contains(apiName)) {
      throw DataFetchError(
        'UNSUPPORTED_TUSHARE_API: $apiName is disabled in this app because the configured Tushare permission set cannot access it. Use local cache, EastMoney/AkShare, Yahoo, or Wind where available.',
      );
    }
    final interval = _endpointMinIntervals[apiName];
    if (interval == null) return;
    final now = DateTime.now();
    final last = _endpointLastCall[apiName];
    if (last != null) {
      final wait = interval - now.difference(last);
      if (!wait.isNegative && wait.inMilliseconds > 0) {
        throw DataFetchError(
          'TUSHARE_RATE_LIMIT: $apiName has an endpoint frequency window; wait ${wait.inSeconds + 1}s before retrying.',
        );
      }
    }
    _endpointLastCall[apiName] = now;
  }

  String _tsCode(String code) {
    final c = _normalizeCode(code);
    return c.startsWith('6') ? '$c.SH' : '$c.SZ';
  }

  // ─── Quotes ───

  @override
  Future<List<StockQuote>> getQuotes(List<String> codes) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      // Tushare daily API with trade_date for bulk data
      final today = DateTime.now();
      final dateStr =
          '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';

      final data = await _call(
        'daily',
        {'trade_date': dateStr},
        fields:
            'ts_code,open,high,low,close,pre_close,change,pct_chg,vol,amount',
      );

      final items = data['items'] as List? ?? [];
      final fields = data['fields'] as List? ?? [];

      final quotes = <StockQuote>[];
      for (final row in items) {
        if (row is! List || row.length < fields.length) continue;
        final map = <String, dynamic>{};
        for (var i = 0; i < fields.length; i++) {
          map['${fields[i]}'] = row[i];
        }

        final tsCode = map['ts_code'] as String? ?? '';
        final pureCode = tsCode.split('.').first;
        if (codes.isNotEmpty &&
            !codes.any((c) => _normalizeCode(c) == pureCode)) {
          continue;
        }

        quotes.add(
          StockQuote(
            code: pureCode,
            name: '',
            price: _d(map['close']),
            change: _d(map['change']),
            changePct: _d(map['pct_chg']),
            open: _d(map['open']),
            high: _d(map['high']),
            low: _d(map['low']),
            prevClose: _d(map['pre_close']),
            volume: _d(map['vol']) * 100, // Tushare vol in 手
            amount: _d(map['amount']) * 1000, // Tushare amount in 千元
            source: name,
          ),
        );
      }

      _circuitBreaker.recordSuccess(name);
      return quotes;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      rethrow;
    }
  }

  // ─── K-Line ───

  @override
  Future<List<KlineBar>> getKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    final cacheKey = '$code|$period|$startDate|$endDate|$adjust';
    final cached = _klineCache.getTracked(cacheKey);
    if (cached != null) return cached;

    try {
      // For simplicity, always use daily API
      final params = <String, dynamic>{
        'ts_code': _tsCode(code),
        if (startDate.isNotEmpty) 'start_date': startDate.replaceAll('-', ''),
        if (endDate.isNotEmpty) 'end_date': endDate.replaceAll('-', ''),
      };

      final data = await _call(
        'daily',
        params,
        fields: 'trade_date,open,high,low,close,vol,amount,pct_chg',
      );

      final items = data['items'] as List? ?? [];
      final fields = data['fields'] as List? ?? [];

      final bars = <KlineBar>[];
      for (final row in items) {
        if (row is! List || row.length < fields.length) continue;
        final map = <String, dynamic>{};
        for (var i = 0; i < fields.length; i++) {
          map['${fields[i]}'] = row[i];
        }

        final dateStr = '${map['trade_date']}';
        final date = dateStr.length >= 8
            ? '${dateStr.substring(0, 4)}-${dateStr.substring(4, 6)}-${dateStr.substring(6, 8)}'
            : dateStr;

        bars.add(
          KlineBar(
            date: date,
            open: _d(map['open']),
            high: _d(map['high']),
            low: _d(map['low']),
            close: _d(map['close']),
            volume: _d(map['vol']) * 100,
            amount: _d(map['amount']) * 1000,
            changePct: _dn(map['pct_chg']),
          ),
        );
      }

      // Tushare returns newest first, reverse for chronological order
      bars.sort((a, b) => a.date.compareTo(b.date));

      _circuitBreaker.recordSuccess(name);
      _klineCache.set(cacheKey, bars);
      return bars;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      rethrow;
    }
  }

  @override
  Future<List<MoneyFlow>> getMoneyFlow(String code) async {
    throw DataFetchError(
      'UNSUPPORTED_TUSHARE_API: moneyflow is disabled in this app because the configured Tushare permission set cannot access it. Use EastMoney money flow or local query_money_flow instead.',
    );
  }

  /// Get trade calendar.
  Future<List<String>> getTradeCal({
    String startDate = '',
    String endDate = '',
  }) async {
    final data = await _call('trade_cal', {
      'exchange': 'SSE',
      'is_open': '1',
      if (startDate.isNotEmpty) 'start_date': startDate.replaceAll('-', ''),
      if (endDate.isNotEmpty) 'end_date': endDate.replaceAll('-', ''),
    }, fields: 'cal_date');

    final items = data['items'] as List? ?? [];
    return items
        .map((r) => r is List && r.isNotEmpty ? '${r[0]}' : '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Get stock basic info.
  Future<List<Map<String, dynamic>>> getStockBasic() async {
    final data = await _call('stock_basic', {
      'list_status': 'L',
    }, fields: 'ts_code,name,area,industry,list_date,market');
    final items = data['items'] as List? ?? [];
    final fields = data['fields'] as List? ?? [];
    return items.map((row) {
      if (row is! List) return <String, dynamic>{};
      final map = <String, dynamic>{};
      for (var i = 0; i < fields.length && i < row.length; i++) {
        map['${fields[i]}'] = row[i];
      }
      return map;
    }).toList();
  }

  CircuitBreaker get circuitBreaker => _circuitBreaker;
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
double? _dn(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
