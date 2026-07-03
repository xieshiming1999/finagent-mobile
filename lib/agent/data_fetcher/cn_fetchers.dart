import 'dart:convert';

import 'base_fetcher.dart';
import 'http_utils.dart';
import 'models.dart';

String _normalizeCode(String code) {
  final s = code.replaceAll(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '');
  return s.replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '');
}

bool _isShanghaiSymbol(String code) {
  final raw = code.trim().toUpperCase();
  return raw.startsWith('SH') ||
      raw.endsWith('.SH') ||
      raw.startsWith('CSI') ||
      raw.endsWith('.CSI');
}

/// Sina Finance (新浪财经) data fetcher — fallback for real-time quotes.
class SinaFetcher extends BaseFetcher {
  @override
  String get name => '新浪财经';
  @override
  int get priority => 20;

  final _rateLimiter = RateLimiter();
  final _circuitBreaker = CircuitBreaker();

  @override
  bool canHandle(String code) =>
      RegExp(r'^\d{6}$').hasMatch(_normalizeCode(code));

  String _sinaCode(String code) {
    final c = _normalizeCode(code);
    return _isShanghaiSymbol(code) || c.startsWith('6') ? 'sh$c' : 'sz$c';
  }

  String _sinaFundCode(String code) {
    final c = _normalizeCode(code);
    return c.startsWith('5') ? 'sh$c' : 'sz$c';
  }

  @override
  Future<List<StockQuote>> getQuotes(List<String> codes) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final sinaCodes = codes.map((c) => _sinaCode(c)).join(',');
      final response = await fetchWithRetry(
        'https://hq.sinajs.cn/list=$sinaCodes',
        headers: {'Referer': 'http://finance.sina.com.cn'},
        rateLimiter: _rateLimiter,
      );

      final quotes = <StockQuote>[];
      final lines = response.body
          .split('\n')
          .where((l) => l.contains('"'))
          .toList();

      for (final line in lines) {
        final codeMatch = RegExp(r'hq_str_(s[hz]\d{6})').firstMatch(line);
        final dataMatch = RegExp(r'"(.+)"').firstMatch(line);
        if (codeMatch == null || dataMatch == null) continue;

        final rawCode = codeMatch.group(1)!;
        final stockCode = rawCode.substring(2);
        final parts = dataMatch.group(1)!.split(',');
        if (parts.length < 32) continue;

        quotes.add(
          StockQuote(
            code: stockCode,
            name: parts[0],
            price: double.tryParse(parts[3]) ?? 0,
            change:
                (double.tryParse(parts[3]) ?? 0) -
                (double.tryParse(parts[2]) ?? 0),
            changePct: _pct(parts[3], parts[2]),
            open: double.tryParse(parts[1]) ?? 0,
            high: double.tryParse(parts[4]) ?? 0,
            low: double.tryParse(parts[5]) ?? 0,
            prevClose: double.tryParse(parts[2]) ?? 0,
            volume: double.tryParse(parts[8]) ?? 0,
            amount: double.tryParse(parts[9]) ?? 0,
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

  @override
  Future<List<KlineBar>> getKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) async {
    if (period != 'daily') {
      throw DataFetchError('$name supports only daily kline');
    }
    if (adjust != 'none') {
      throw DataFetchError(
        '$name supports only unadjusted kline; use adjust=none',
      );
    }

    final response = await fetchWithRetry(
      'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData',
      headers: {'Referer': 'https://finance.sina.com.cn/'},
      queryParams: {
        'symbol': _sinaCode(code),
        'scale': '240',
        'ma': 'no',
        'datalen': '1023',
      },
      timeout: const Duration(seconds: 30),
      rateLimiter: _rateLimiter,
    );
    if (response.statusCode != 200) {
      throw DataFetchError('$name kline HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw DataFetchError('$name kline returned unexpected schema');
    }
    final bars = decoded
        .whereType<Map>()
        .map(
          (row) => KlineBar(
            date: _formatDate('${row['day'] ?? row['date'] ?? ''}'),
            open: double.tryParse('${row['open'] ?? 0}') ?? 0,
            high: double.tryParse('${row['high'] ?? 0}') ?? 0,
            low: double.tryParse('${row['low'] ?? 0}') ?? 0,
            close: double.tryParse('${row['close'] ?? 0}') ?? 0,
            volume: double.tryParse('${row['volume'] ?? 0}') ?? 0,
            amount: double.tryParse('${row['amount'] ?? 0}') ?? 0,
          ),
        )
        .where(
          (bar) =>
              bar.date.isNotEmpty &&
              bar.close > 0 &&
              (startDate.isEmpty ||
                  bar.date.compareTo(_formatDate(startDate)) >= 0) &&
              (endDate.isEmpty ||
                  bar.date.compareTo(_formatDate(endDate)) <= 0),
        )
        .toList();
    if (bars.isEmpty) {
      throw DataFetchError('$name kline returned no valid bars');
    }
    return bars;
  }

  Future<List<Map<String, dynamic>>> getIntradayOhlcvBars(
    String code, {
    int intervalMinutes = 5,
    int limit = 240,
  }) async {
    if (![5, 15, 30, 60].contains(intervalMinutes)) {
      throw DataFetchError(
        '$name intraday OHLCV supports intervalMinutes 5, 15, 30, or 60',
      );
    }
    final boundedLimit = limit.clamp(1, 1023).toInt();
    final sinaSymbol = _sinaCode(code);
    final response = await fetchWithRetry(
      'https://money.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_MarketData.getKLineData',
      headers: {'Referer': 'https://finance.sina.com.cn/'},
      queryParams: {
        'symbol': sinaSymbol,
        'scale': '$intervalMinutes',
        'ma': 'no',
        'datalen': '$boundedLimit',
      },
      timeout: const Duration(seconds: 30),
      rateLimiter: _rateLimiter,
    );
    if (response.statusCode != 200) {
      throw DataFetchError('$name intraday OHLCV HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw DataFetchError('$name intraday OHLCV returned unexpected schema');
    }
    final rows = <Map<String, dynamic>>[];
    for (final row in decoded.whereType<Map>()) {
      final barTime = '${row['day'] ?? row['date'] ?? row['time'] ?? ''}';
      final close = double.tryParse('${row['close'] ?? ''}');
      if (barTime.isEmpty || close == null || close <= 0) continue;
      rows.add({
        'code': sinaSymbol,
        'bar_time': barTime,
        'trade_date': _formatDate(barTime),
        'interval_minutes': intervalMinutes,
        'open': double.tryParse('${row['open'] ?? ''}'),
        'high': double.tryParse('${row['high'] ?? ''}'),
        'low': double.tryParse('${row['low'] ?? ''}'),
        'close': close,
        'volume': double.tryParse('${row['volume'] ?? ''}'),
        'amount': double.tryParse('${row['amount'] ?? ''}'),
        'source': name,
        'raw_json': Map<String, dynamic>.from(row),
      });
    }
    if (rows.isEmpty) {
      throw DataFetchError('$name intraday OHLCV returned no valid bars');
    }
    return rows;
  }

  Future<List<Map<String, dynamic>>> getFundDividendFactors(
    String code, {
    int limit = 240,
  }) async {
    final boundedLimit = limit.clamp(1, 240).toInt();
    final sinaSymbol = _sinaFundCode(code);
    final response = await fetchWithRetry(
      'https://finance.sina.com.cn/realstock/company/$sinaSymbol/hfq.js',
      headers: {'Referer': 'https://finance.sina.com.cn/'},
      timeout: const Duration(seconds: 30),
      rateLimiter: _rateLimiter,
    );
    if (response.statusCode != 200) {
      throw DataFetchError(
        '$name fund dividend/factor HTTP ${response.statusCode}',
      );
    }

    final decoded = _decodeSinaAssignment(response.body);
    final data = decoded is Map ? decoded['data'] : null;
    if (data is! List) {
      throw DataFetchError(
        '$name fund dividend/factor returned unexpected schema',
      );
    }
    final rows = <Map<String, dynamic>>[];
    for (final row in data.whereType<Map>().take(boundedLimit)) {
      final eventDate = '${row['d'] ?? row['date'] ?? row['fsrq'] ?? ''}';
      if (eventDate.isEmpty) continue;
      rows.add({
        'code': sinaSymbol,
        'event_date': eventDate,
        'dividend': double.tryParse(
          '${row['u'] ?? row['fh'] ?? row['dividend'] ?? ''}',
        ),
        'factor': double.tryParse(
          '${row['f'] ?? row['s'] ?? row['factor'] ?? ''}',
        ),
        'source': name,
        'raw_json': Map<String, dynamic>.from(row),
      });
    }
    if (rows.isEmpty) {
      throw DataFetchError('$name fund dividend/factor returned no valid rows');
    }
    return rows;
  }

  @override
  Future<List<MoneyFlow>> getMoneyFlow(String code) async {
    throw DataFetchError('$name does not support money flow');
  }

  Future<List<StockQuote>> getETFQuotes({int limit = 200}) async {
    final pageSize = limit.clamp(1, 200).toInt();
    final response = await fetchWithRetry(
      "https://vip.stock.finance.sina.com.cn/quotes_service/api/jsonp.php/IO.XSRV2.CallbackList['da_yPT46_Ll7K6WD']/Market_Center.getHQNodeDataSimple",
      headers: {'Referer': 'https://finance.sina.com.cn/'},
      queryParams: {
        'page': '1',
        'num': '$pageSize',
        'sort': 'symbol',
        'asc': '0',
        'node': 'etf_hq_fund',
      },
      timeout: const Duration(seconds: 30),
      rateLimiter: _rateLimiter,
    );
    if (response.statusCode != 200) {
      throw DataFetchError('$name ETF quote HTTP ${response.statusCode}');
    }

    final decoded = _decodeJsonp(response.body);
    if (decoded is! List) {
      throw DataFetchError('$name ETF quote returned unexpected schema');
    }
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final quotes = decoded
        .whereType<Map>()
        .map((row) {
          final code = '${row['symbol'] ?? row['code'] ?? ''}'
              .replaceFirst(RegExp(r'^(sh|sz)', caseSensitive: false), '')
              .trim();
          if (code.isEmpty) return null;
          return StockQuote(
            code: code,
            timestamp: fetchedAt,
            fetchedAt: fetchedAt,
            name: '${row['name'] ?? code}',
            price: _num(row['trade'] ?? row['price']),
            change: _num(row['pricechange']),
            changePct: _num(row['changepercent']),
            open: _num(row['open']),
            high: _num(row['high']),
            low: _num(row['low']),
            prevClose: _num(row['settlement']),
            volume: _num(row['volume']),
            amount: _num(row['amount']),
            source: name,
          );
        })
        .whereType<StockQuote>()
        .toList();
    if (quotes.isEmpty) {
      throw DataFetchError('$name ETF quote returned no valid rows');
    }
    return quotes;
  }

  Future<List<Map<String, dynamic>>> getSectorRanking({
    String boardType = 'industry',
  }) async {
    final url = switch (boardType) {
      'concept' => 'https://money.finance.sina.com.cn/q/view/newFLJK.php',
      _ => 'https://vip.stock.finance.sina.com.cn/q/view/newSinaHy.php',
    };
    final response = await fetchWithRetry(
      url,
      headers: {'Referer': 'https://finance.sina.com.cn/'},
      queryParams: boardType == 'concept' ? {'param': 'class'} : null,
      timeout: const Duration(seconds: 30),
      rateLimiter: _rateLimiter,
    );
    if (response.statusCode != 200) {
      throw DataFetchError('$name sector ranking HTTP ${response.statusCode}');
    }

    final rows = _parseSinaSectorRanking(
      decodeResponseBody(response),
      boardType: boardType,
    );
    if (rows.isEmpty) {
      throw DataFetchError('$name sector ranking returned no valid rows');
    }
    return rows;
  }

  Future<List<StockQuote>> getSectorStocks(
    String sectorCode, {
    int limit = 200,
  }) async {
    final pageSize = limit.clamp(1, 200).toInt();
    final response = await fetchWithRetry(
      'https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData',
      headers: {'Referer': 'https://finance.sina.com.cn/'},
      queryParams: {
        'page': '1',
        'num': '$pageSize',
        'sort': 'symbol',
        'asc': '1',
        'node': sectorCode,
        'symbol': '',
        '_s_r_a': 'page',
      },
      timeout: const Duration(seconds: 30),
      rateLimiter: _rateLimiter,
    );
    if (response.statusCode != 200) {
      throw DataFetchError(
        '$name sector constituents HTTP ${response.statusCode}',
      );
    }

    final decoded = jsonDecode(decodeResponseBody(response));
    if (decoded is! List) {
      throw DataFetchError(
        '$name sector constituents returned unexpected schema',
      );
    }
    final quotes = decoded
        .whereType<Map>()
        .map((row) {
          final code = '${row['code'] ?? row['symbol'] ?? ''}'
              .replaceFirst(RegExp(r'^(sh|sz|bj)', caseSensitive: false), '')
              .trim();
          if (code.isEmpty) return null;
          return StockQuote(
            code: code,
            name: '${row['name'] ?? code}',
            price: _num(row['trade']),
            change: _num(row['pricechange']),
            changePct: _num(row['changepercent']),
            open: _num(row['open']),
            high: _num(row['high']),
            low: _num(row['low']),
            prevClose: _num(row['settlement']),
            volume: _num(row['volume']),
            amount: _num(row['amount']),
            pe: _nullableNum(row['per']),
            pb: _nullableNum(row['pb']),
            turnoverRate: _nullableNum(row['turnoverratio']),
            marketCap: _nullableNum(row['mktcap']),
            source: name,
          );
        })
        .whereType<StockQuote>()
        .toList();
    if (quotes.isEmpty) {
      throw DataFetchError('$name sector constituents returned no valid rows');
    }
    return quotes;
  }

  Future<List<Map<String, dynamic>>> getTransactions(
    String code, {
    int limit = 60,
    String? tradeDate,
  }) async {
    final symbol = _sinaSymbol(code);
    final date = _dashDate(tradeDate) ?? _todayDate();
    final pageSize = limit.clamp(1, 60).toInt();
    final response = await fetchWithRetry(
      'https://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/CN_Bill.GetBillList',
      headers: {
        'Referer':
            'https://vip.stock.finance.sina.com.cn/quotes_service/view/cn_bill.php?symbol=$symbol',
      },
      queryParams: {
        'symbol': symbol,
        'num': '$pageSize',
        'page': '1',
        'sort': 'ticktime',
        'asc': '0',
        'volume': '0',
        'amount': '0',
        'type': '0',
        'day': date,
      },
      timeout: const Duration(seconds: 20),
      rateLimiter: _rateLimiter,
    );
    if (response.statusCode != 200) {
      throw DataFetchError('$name transactions HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(decodeResponseBody(response));
    if (decoded is! List) {
      throw DataFetchError('$name transactions returned unexpected schema');
    }
    final rows = decoded
        .whereType<Map>()
        .map((row) {
          final price = _nullableNum(row['price']);
          final volume = _nullableNum(row['volume']);
          return {
            'time': '${row['ticktime'] ?? ''}',
            'price': price,
            'volume': volume,
            'trades': null,
            'amount': price != null && volume != null ? price * volume : null,
            'direction': _sinaDirection('${row['kind'] ?? ''}'),
            'raw': Map<String, dynamic>.from(row),
          };
        })
        .where((row) => '${row['time']}'.isNotEmpty)
        .toList();
    if (rows.isEmpty) {
      throw DataFetchError('$name transactions returned no valid rows');
    }
    return rows;
  }

  double _pct(String current, String prev) {
    final c = double.tryParse(current) ?? 0;
    final p = double.tryParse(prev) ?? 0;
    return p != 0 ? (c - p) / p * 100 : 0;
  }

  Object? _decodeJsonp(String body) {
    final text = body
        .trim()
        .replaceFirst(RegExp(r'^/\*[\s\S]*?\*/'), '')
        .trim();
    try {
      return jsonDecode(text);
    } catch (_) {
      final start = text.indexOf('(');
      final end = text.lastIndexOf(')');
      if (start >= 0 && end > start) {
        return jsonDecode(text.substring(start + 1, end));
      }
      rethrow;
    }
  }

  Object? _decodeSinaAssignment(String body) {
    final text = body.trim();
    final match = RegExp(
      r'^\s*var\s+[A-Za-z0-9_]+\s*=\s*([\s\S]*?)\s*;?\s*$',
    ).firstMatch(text);
    return jsonDecode(match?.group(1) ?? text);
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }

  double? _nullableNum(Object? value) {
    if (value == null || '$value'.isEmpty) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  String _sinaSymbol(String code) {
    final clean = code
        .replaceFirst(RegExp(r'^(sh|sz|bj)', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '');
    return '${clean.startsWith('6') ? 'sh' : 'sz'}$clean';
  }

  String? _dashDate(String? value) {
    if (value == null || value.isEmpty) return null;
    final clean = value.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 8) return value;
    return '${clean.substring(0, 4)}-${clean.substring(4, 6)}-${clean.substring(6, 8)}';
  }

  String _todayDate() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _sinaDirection(String kind) {
    if (kind == 'U') return 'buy';
    if (kind == 'D') return 'sell';
    if (kind == 'E') return 'neutral';
    return kind;
  }

  List<Map<String, dynamic>> _parseSinaSectorRanking(
    String body, {
    required String boardType,
  }) {
    final objectMatch = RegExp(r'\{([\s\S]*)\}').firstMatch(body);
    if (objectMatch == null) return const [];
    final entryPattern = RegExp(
      r'''["']?([^"',:{}\s]+)["']?\s*:\s*["']([^"']*)["']''',
    );
    final rows = <Map<String, dynamic>>[];
    for (final match in entryPattern.allMatches(objectMatch.group(1)!)) {
      final key = match.group(1) ?? '';
      final parts = (match.group(2) ?? '').split(',');
      if (parts.length < 2) continue;
      final code = parts[0].trim().isNotEmpty ? parts[0].trim() : key.trim();
      final name = parts[1].trim().isNotEmpty ? parts[1].trim() : key.trim();
      if (code.isEmpty || name.isEmpty) continue;
      rows.add({
        'code': code,
        'name': name,
        'changePct': _num(parts.length > 5 ? parts[5] : null),
        'changeAmount': null,
        'turnoverRate': null,
        'upCount': 0,
        'downCount': 0,
        'leadingStock': parts.length > 12 && parts[12].trim().isNotEmpty
            ? parts[12].trim()
            : (parts.length > 8 ? parts[8].trim() : ''),
        'leadingChangePct': _num(parts.length > 9 ? parts[9] : null),
        'source': name,
        'boardType': boardType,
      });
    }
    return rows;
  }

  CircuitBreaker get circuitBreaker => _circuitBreaker;
}

String _formatDate(String value) {
  final text = value.trim();
  if (text.length >= 10 && text.contains('-')) return text.substring(0, 10);
  if (text.length == 8 && RegExp(r'^\d{8}$').hasMatch(text)) {
    return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
  }
  return text;
}

double _parseNum(Object? value) => double.tryParse('$value') ?? 0;

/// Tencent Finance (腾讯财经) data fetcher — fallback for real-time quotes.
class TencentFetcher extends BaseFetcher {
  @override
  String get name => '腾讯财经';
  @override
  int get priority => 30;

  final _rateLimiter = RateLimiter();
  final _circuitBreaker = CircuitBreaker();

  @override
  bool canHandle(String code) =>
      RegExp(r'^\d{6}$').hasMatch(_normalizeCode(code)) ||
      RegExp(r'^hk\d{5}$', caseSensitive: false).hasMatch(code.trim()) ||
      RegExp(r'^us[A-Za-z0-9.]+$', caseSensitive: false).hasMatch(code.trim());

  String _txCode(String code) {
    final raw = code.trim();
    if (RegExp(r'^hk\d{5}$', caseSensitive: false).hasMatch(raw)) {
      return raw.toLowerCase();
    }
    if (RegExp(r'^us[A-Za-z0-9.]+$', caseSensitive: false).hasMatch(raw)) {
      return 'us${raw.substring(2).toUpperCase()}';
    }
    final c = _normalizeCode(code);
    return _isShanghaiSymbol(code) || c.startsWith('6') ? 'sh$c' : 'sz$c';
  }

  String _txIndexCode(String code) {
    final c = _normalizeCode(code);
    return _isShanghaiSymbol(code) || !c.startsWith('399') ? 'sh$c' : 'sz$c';
  }

  String _txConvertibleBondCode(String code) {
    final c = _normalizeCode(code);
    if (c.startsWith('11')) return 'sh$c';
    if (c.startsWith('12')) return 'sz$c';
    return _txCode(c);
  }

  @override
  Future<List<StockQuote>> getQuotes(List<String> codes) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final txCodes = codes.map((c) => _txCode(c)).join(',');
      final response = await fetchWithRetry(
        'https://qt.gtimg.cn/q=$txCodes',
        headers: {'Referer': 'https://stockhtm.finance.qq.com'},
        rateLimiter: _rateLimiter,
      );

      final quotes = <StockQuote>[];
      final lines = response.body
          .split(';')
          .where((l) => l.contains('~'))
          .toList();

      for (final line in lines) {
        final symbolMatch = RegExp(
          r'v_([a-z]{2}[A-Za-z0-9]+)=',
          caseSensitive: false,
        ).firstMatch(line);
        final dataMatch = RegExp(r'"(.+)"').firstMatch(line);
        if (dataMatch == null) continue;
        final parts = dataMatch.group(1)!.split('~');
        if (parts.length < 45) continue;

        quotes.add(
          StockQuote(
            code: _quoteCode(symbolMatch?.group(1), parts[2]),
            name: parts[1],
            price: double.tryParse(parts[3]) ?? 0,
            change: double.tryParse(parts[31]) ?? 0,
            changePct: double.tryParse(parts[32]) ?? 0,
            open: double.tryParse(parts[5]) ?? 0,
            high: double.tryParse(parts[33]) ?? 0,
            low: double.tryParse(parts[34]) ?? 0,
            prevClose: double.tryParse(parts[4]) ?? 0,
            volume: (double.tryParse(parts[6]) ?? 0) * 100,
            amount: (double.tryParse(parts[37]) ?? 0) * 10000,
            pe: double.tryParse(parts[39]),
            turnoverRate: double.tryParse(parts[38]),
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

  String _quoteCode(String? requestedSymbol, String providerCode) {
    final requested = requestedSymbol?.trim() ?? '';
    if (RegExp(r'^hk\d{5}$', caseSensitive: false).hasMatch(requested)) {
      return requested.toLowerCase();
    }
    if (RegExp(
      r'^us[A-Za-z0-9.]+$',
      caseSensitive: false,
    ).hasMatch(requested)) {
      return 'us${requested.substring(2).toUpperCase()}';
    }
    final provider = providerCode.trim();
    if (provider.isNotEmpty && provider != '0') return provider;
    if (requested.length > 2) return requested.substring(2);
    return providerCode;
  }

  Future<List<StockQuote>> getIndexQuotes(List<String> codes) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final txCodes = codes.map((c) => _txIndexCode(c)).join(',');
      final response = await fetchWithRetry(
        'https://qt.gtimg.cn/q=$txCodes',
        headers: {'Referer': 'https://stockhtm.finance.qq.com'},
        rateLimiter: _rateLimiter,
      );

      final quotes = <StockQuote>[];
      final lines = response.body
          .split(';')
          .where((l) => l.contains('~'))
          .toList();

      for (final line in lines) {
        final dataMatch = RegExp(r'"(.+)"').firstMatch(line);
        if (dataMatch == null) continue;
        final parts = dataMatch.group(1)!.split('~');
        if (parts.length < 45) continue;
        final code = parts[2];
        final price = double.tryParse(parts[3]) ?? 0;
        if (code.isEmpty || price <= 0) continue;

        quotes.add(
          StockQuote(
            code: code,
            name: parts[1],
            price: price,
            change: double.tryParse(parts[31]) ?? 0,
            changePct: double.tryParse(parts[32]) ?? 0,
            open: double.tryParse(parts[5]) ?? 0,
            high: double.tryParse(parts[33]) ?? 0,
            low: double.tryParse(parts[34]) ?? 0,
            prevClose: double.tryParse(parts[4]) ?? 0,
            volume: (double.tryParse(parts[6]) ?? 0) * 100,
            amount: (double.tryParse(parts[37]) ?? 0) * 10000,
            pe: double.tryParse(parts[39]),
            turnoverRate: double.tryParse(parts[38]),
            source: '$name:index_quote',
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

  @override
  Future<List<KlineBar>> getKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'qfq',
  }) async {
    return getStockDailyKline(
      code,
      period: period,
      startDate: startDate,
      endDate: endDate,
      adjust: adjust,
    );
  }

  @override
  Future<List<MoneyFlow>> getMoneyFlow(String code) async {
    throw DataFetchError('$name does not support money flow');
  }

  Future<List<StockQuote>> getETFQuotes({int limit = 20}) async {
    final boundedLimit = limit.clamp(1, _tencentEtfSymbols.length).toInt();
    final symbols = _tencentEtfSymbols.take(boundedLimit).toList();
    final quotes = await getQuotes(symbols);
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    return quotes
        .map(
          (quote) => StockQuote(
            code: quote.code,
            timestamp: quote.timestamp ?? fetchedAt,
            fetchedAt: quote.fetchedAt ?? fetchedAt,
            name: quote.name,
            price: quote.price,
            change: quote.change,
            changePct: quote.changePct,
            open: quote.open,
            high: quote.high,
            low: quote.low,
            prevClose: quote.prevClose,
            volume: quote.volume,
            amount: quote.amount,
            pe: quote.pe,
            pb: quote.pb,
            turnoverRate: quote.turnoverRate,
            marketCap: quote.marketCap,
            source: '$name:etf',
          ),
        )
        .toList(growable: false);
  }

  Future<List<StockQuote>> getListedFundQuotes({int limit = 20}) async {
    final boundedLimit = limit
        .clamp(1, _tencentListedFundSymbols.length)
        .toInt();
    final symbols = _tencentListedFundSymbols.take(boundedLimit).toList();
    final quotes = await getQuotes(symbols);
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    return quotes
        .map(
          (quote) => StockQuote(
            code: quote.code,
            timestamp: quote.timestamp ?? fetchedAt,
            fetchedAt: quote.fetchedAt ?? fetchedAt,
            name: quote.name,
            price: quote.price,
            change: quote.change,
            changePct: quote.changePct,
            open: quote.open,
            high: quote.high,
            low: quote.low,
            prevClose: quote.prevClose,
            volume: quote.volume,
            amount: quote.amount,
            pe: quote.pe,
            pb: quote.pb,
            turnoverRate: quote.turnoverRate,
            marketCap: quote.marketCap,
            source: '$name:listed_fund',
          ),
        )
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getStockList({int limit = 200}) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final boundedLimit = limit.clamp(1, 1000).toInt();
      final response = await fetchWithRetry(
        'https://proxy.finance.qq.com/cgi/cgi-bin/rank/hs/getBoardRankList',
        headers: {'Referer': 'https://stockapp.finance.qq.com/mstats/'},
        queryParams: {
          '_appver': '11.17.0',
          'board_code': 'aStock',
          'sort_type': 'price',
          'direct': 'down',
          'offset': '0',
          'count': '$boundedLimit',
        },
        timeout: const Duration(seconds: 30),
        rateLimiter: _rateLimiter,
      );
      if (response.statusCode != 200) {
        throw DataFetchError('$name stock list HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      final data = decoded is Map ? decoded['data'] : null;
      final rows = data is Map ? data['rank_list'] : null;
      if (rows is! List) {
        throw DataFetchError('$name stock list unexpected schema');
      }
      final fetchedAt = DateTime.now().toUtc().toIso8601String();
      final parsed = rows
          .whereType<Map>()
          .map((row) {
            final code = _normalizeCode('${row['code'] ?? ''}');
            final nameValue = '${row['name'] ?? ''}'.trim();
            if (code.length != 6 || nameValue.isEmpty) return null;
            return {
              'code': code,
              'name': nameValue,
              'market': code.startsWith('6') ? 'SH' : 'SZ',
              'industry': null,
              'stock_type': 'stock',
              'updated_at': fetchedAt,
              'source': '$name:stock_rank_list',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
      if (parsed.isEmpty) {
        throw DataFetchError('$name stock list returned no valid rows');
      }

      _circuitBreaker.recordSuccess(name);
      return parsed;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      rethrow;
    }
  }

  Future<List<StockQuote>> getConvertibleBondQuotes(List<String> codes) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final txCodes = codes.map(_txConvertibleBondCode).join(',');
      final response = await fetchWithRetry(
        'https://qt.gtimg.cn/q=$txCodes',
        headers: {'Referer': 'https://stockhtm.finance.qq.com'},
        rateLimiter: _rateLimiter,
      );

      final fetchedAt = DateTime.now().toUtc().toIso8601String();
      final quotes = <StockQuote>[];
      final lines = response.body
          .split(';')
          .where((line) => line.contains('~'))
          .toList();

      for (final line in lines) {
        final dataMatch = RegExp(r'"(.+)"').firstMatch(line);
        if (dataMatch == null) continue;
        final parts = dataMatch.group(1)!.split('~');
        if (parts.length < 45) continue;
        final code = parts[2];
        final price = double.tryParse(parts[3]) ?? 0;
        if (code.isEmpty || price <= 0) continue;

        quotes.add(
          StockQuote(
            code: code,
            timestamp: fetchedAt,
            fetchedAt: fetchedAt,
            name: parts[1],
            price: price,
            change: double.tryParse(parts[31]) ?? 0,
            changePct: double.tryParse(parts[32]) ?? 0,
            open: double.tryParse(parts[5]) ?? 0,
            high: double.tryParse(parts[33]) ?? 0,
            low: double.tryParse(parts[34]) ?? 0,
            prevClose: double.tryParse(parts[4]) ?? 0,
            volume: (double.tryParse(parts[6]) ?? 0) * 100,
            amount: (double.tryParse(parts[37]) ?? 0) * 10000,
            pe: double.tryParse(parts[39]),
            pb: double.tryParse(parts[46]),
            turnoverRate: double.tryParse(parts[38]),
            source: '$name:convertible_bond',
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

  Future<List<KlineBar>> getStockDailyKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'none',
  }) async {
    if (period != 'daily') {
      throw DataFetchError('$name stock K-line supports only daily period');
    }
    if (adjust != 'none') {
      throw DataFetchError('$name stock daily kline supports only adjust=none');
    }
    return _getDailyKline(
      symbol: _txCode(code),
      startDate: startDate,
      endDate: endDate,
      label: 'stock',
    );
  }

  Future<List<KlineBar>> getIndexDailyKline(
    String code, {
    String period = 'daily',
    String startDate = '',
    String endDate = '',
    String adjust = 'none',
  }) async {
    if (period != 'daily') {
      throw DataFetchError('$name index K-line supports only daily period');
    }
    if (adjust != 'none') {
      throw DataFetchError('$name index daily kline supports only adjust=none');
    }
    return _getDailyKline(
      symbol: _txIndexCode(code),
      startDate: startDate,
      endDate: endDate,
      label: 'index',
    );
  }

  Future<List<KlineBar>> getConvertibleBondDailyKline(
    String code, {
    String startDate = '',
    String endDate = '',
    String adjust = 'none',
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    if (adjust != 'none') {
      throw DataFetchError(
        '$name convertible-bond daily kline supports only adjust=none',
      );
    }
    return _getDailyKline(
      symbol: _txConvertibleBondCode(code),
      startDate: startDate,
      endDate: endDate,
      label: 'convertible-bond',
    );
  }

  Future<List<KlineBar>> getEtfDailyKline(
    String code, {
    String startDate = '',
    String endDate = '',
    String adjust = 'none',
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }
    if (adjust != 'none') {
      throw DataFetchError('$name ETF daily kline supports only adjust=none');
    }

    return _getDailyKline(
      symbol: _txCode(code),
      startDate: startDate,
      endDate: endDate,
      label: 'ETF',
    );
  }

  Future<List<KlineBar>> _getDailyKline({
    required String symbol,
    required String startDate,
    required String endDate,
    required String label,
  }) async {
    try {
      final params = {
        '_var': 'kline_day',
        'param': '$symbol,day,$startDate,$endDate,640,',
        'r': '0.1',
      };
      final response = await fetchWithRetry(
        'https://proxy.finance.qq.com/ifzqgtimg/appstock/app/newfqkline/get',
        headers: {'Referer': 'https://stockapp.finance.qq.com/mstats/'},
        queryParams: params,
        timeout: const Duration(seconds: 30),
        rateLimiter: _rateLimiter,
      );

      final jsonText = _extractTencentJson(response.body);
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map) {
        throw DataFetchError('$name $label kline unexpected schema');
      }
      final data = decoded['data'];
      final symbolData = data is Map ? data[symbol] : null;
      final rawRows = symbolData is Map ? symbolData['day'] : null;
      if (rawRows is! List) {
        throw DataFetchError('$name $label kline returned no rows');
      }

      final start = _formatDate(startDate);
      final end = _formatDate(endDate);
      final bars = rawRows
          .whereType<List>()
          .map((row) {
            final date = _formatDate('${row.isNotEmpty ? row[0] : ''}');
            return KlineBar(
              date: date,
              open: _parseNum(row.length > 1 ? row[1] : null),
              close: _parseNum(row.length > 2 ? row[2] : null),
              high: _parseNum(row.length > 3 ? row[3] : null),
              low: _parseNum(row.length > 4 ? row[4] : null),
              volume: _parseNum(row.length > 5 ? row[5] : null),
              amount: _parseNum(row.length > 8 ? row[8] : null),
            );
          })
          .where(
            (bar) =>
                bar.date.isNotEmpty &&
                bar.close > 0 &&
                (start.isEmpty || bar.date.compareTo(start) >= 0) &&
                (end.isEmpty || bar.date.compareTo(end) <= 0),
          )
          .toList(growable: false);
      if (bars.isEmpty) {
        throw DataFetchError('$name $label kline no valid bars');
      }

      _circuitBreaker.recordSuccess(name);
      return bars;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getEtfTransactions(
    String code, {
    int limit = 70,
  }) async {
    return _getTransactionRows(code, limit: limit, label: 'ETF transactions');
  }

  Future<List<Map<String, dynamic>>> getStockTransactions(
    String code, {
    int limit = 70,
  }) async {
    return _getTransactionRows(code, limit: limit, label: 'stock transactions');
  }

  Future<List<Map<String, dynamic>>> _getTransactionRows(
    String code, {
    required int limit,
    required String label,
  }) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final symbol = _txCode(code);
      final response = await fetchWithRetry(
        'http://stock.gtimg.cn/data/index.php',
        headers: {'Referer': 'https://stockapp.finance.qq.com/mstats/'},
        queryParams: {
          'appn': 'detail',
          'action': 'data',
          'c': symbol,
          'p': '0',
        },
        timeout: const Duration(seconds: 30),
        rateLimiter: _rateLimiter,
      );
      if (response.statusCode != 200) {
        throw DataFetchError('$name $label HTTP ${response.statusCode}');
      }

      final rows = _parseTencentTransactionRows(response.body, limit: limit);
      if (rows.isEmpty) {
        throw DataFetchError('$name $label returned no valid rows');
      }

      _circuitBreaker.recordSuccess(name);
      return rows;
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      rethrow;
    }
  }

  CircuitBreaker get circuitBreaker => _circuitBreaker;
}

String _extractTencentJson(String text) {
  final start = text.indexOf('{');
  final end = text.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw DataFetchError('Tencent response did not contain JSON payload');
  }
  return text.substring(start, end + 1);
}

List<Map<String, dynamic>> _parseTencentTransactionRows(
  String body, {
  int limit = 70,
}) {
  final text = body.trim();
  final match = RegExp(r'"([^"]*)"').firstMatch(text);
  final payload = match?.group(1) ?? text;
  return payload
      .split('|')
      .where((row) => row.trim().isNotEmpty)
      .take(limit.clamp(1, 1000).toInt())
      .map((row) {
        final parts = row.split('/');
        if (parts.length < 7) return null;
        final price = _parseNum(parts[2]);
        final volume = _parseNum(parts[4]);
        final amount = _parseNum(parts[5]);
        final direction = switch (parts[6].trim().toUpperCase()) {
          'B' => 'buy',
          'S' => 'sell',
          'M' => 'neutral',
          final value => value.toLowerCase(),
        };
        return {
          'time': parts[1].trim(),
          'price': price,
          'change': _parseNum(parts[3]),
          'volume': volume,
          'trades': null,
          'amount': amount,
          'direction': direction,
          'raw': row,
        };
      })
      .whereType<Map<String, dynamic>>()
      .where((row) => '${row['time']}'.isNotEmpty && row['price'] != null)
      .toList(growable: false);
}

const _tencentEtfSymbols = <String>[
  '510300',
  '510500',
  '510050',
  '588000',
  '159915',
  '159919',
  '512100',
  '512880',
  '513100',
  '513500',
  '518880',
  '515790',
  '512010',
  '512660',
  '515030',
  '159995',
  '159949',
  '159928',
  '159901',
  '159605',
];

const _tencentListedFundSymbols = <String>[
  '511880',
  '511990',
  '160222',
  '161725',
];
