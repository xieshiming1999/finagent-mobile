import 'dart:convert';

import '../log.dart';
import 'base_fetcher.dart';
import 'cache.dart';
import 'http_utils.dart';
import 'models.dart';

/// A-share market code: 1=Shanghai(6xx), 0=Shenzhen(0xx/3xx)
String _secId(String code) {
  final raw = code.trim();
  final c = _cleanCode(code);
  final market =
      raw.toUpperCase().startsWith('SH') ||
          raw.toUpperCase().endsWith('.SH') ||
          raw.toUpperCase().startsWith('CSI') ||
          raw.toUpperCase().endsWith('.CSI')
      ? '1'
      : c.startsWith('6')
      ? '1'
      : '0';
  return '$market.$c';
}

String _cleanCode(String code) {
  // Handle both prefix format (SH600519, SZ000001) and suffix format (600519.SH)
  final s = code.replaceAll(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '');
  return s.replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '');
}

double? _toDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) {
    final text = value.trim();
    if (text.isEmpty || text == '-' || text == '--') return null;
    return double.tryParse(text.replaceAll(',', ''));
  }
  return null;
}

/// EastMoney (东方财富) data fetcher.
/// Covers A-shares, ETFs, indices.
class EastMoneyFetcher extends BaseFetcher {
  @override
  String get name => '东方财富';
  @override
  int get priority => 10;

  final _rateLimiter = RateLimiter();
  final _quoteCache = DataCache<List<StockQuote>>(ttl: Duration(minutes: 20));
  final _circuitBreaker = CircuitBreaker();

  @override
  bool canHandle(String code) {
    final c = _cleanCode(code);
    return RegExp(r'^\d{6}$').hasMatch(c);
  }

  // ─── Real-time Quotes ───

  @override
  Future<List<StockQuote>> getQuotes(List<String> codes) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final quotes = <StockQuote>[];
      for (final code in codes) {
        final secId = _secId(code);
        final response = await fetchWithRetry(
          'https://push2delay.eastmoney.com/api/qt/stock/get',
          queryParams: {
            'ut': 'fa5fd1943c7b386f172d6893dbbd1d0c',
            'fltt': '2',
            'invt': '2',
            'fields':
                'f43,f44,f45,f46,f47,f48,f50,f51,f52,f55,f57,f58,f60,f116,f117,f168,f170,f171',
            'secid': secId,
          },
          rateLimiter: _rateLimiter,
        );

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final data = json['data'] as Map<String, dynamic>?;
        if (data == null) continue;

        final price = _toDouble(data['f43']) ?? 0;
        final prevClose = _toDouble(data['f60']) ?? 0;
        quotes.add(
          StockQuote(
            code: _cleanCode(code),
            name: data['f58'] as String? ?? '',
            price: price,
            change: price - prevClose,
            changePct: _toDouble(data['f170']) ?? 0,
            open: _toDouble(data['f46']) ?? 0,
            high: _toDouble(data['f44']) ?? 0,
            low: _toDouble(data['f45']) ?? 0,
            prevClose: prevClose,
            volume: _toDouble(data['f47']) ?? 0,
            amount: _toDouble(data['f48']) ?? 0,
            pe: _toDouble(data['f55']),
            pb: _toDouble(data['f51']),
            marketCap: _toDouble(data['f116']),
            turnoverRate: _toDouble(data['f168']),
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

  CircuitBreaker get circuitBreaker => _circuitBreaker;

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

    final klt = switch (period) {
      '1m' || '1min' => '1',
      '5m' || '5min' => '5',
      '15m' || '15min' => '15',
      '30m' || '30min' => '30',
      '60m' || '60min' || '1h' => '60',
      'weekly' => '102',
      'monthly' => '103',
      _ => '101',
    };
    final fqt = switch (adjust) {
      'qfq' => '1',
      'hfq' => '2',
      _ => '0',
    };

    try {
      final secid = _secId(code);
      final response = await fetchWithRetry(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get',
        queryParams: {
          'fields1': 'f1,f2,f3,f4,f5,f6',
          'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61',
          'ut': '7eea3edcaed734bea9cbfc24409ed989',
          'klt': klt,
          'fqt': fqt,
          'secid': secid,
          'beg': startDate.replaceAll('-', ''),
          'end': endDate.isNotEmpty ? endDate.replaceAll('-', '') : '20500101',
        },
        rateLimiter: _rateLimiter,
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      final klines = data?['klines'] as List? ?? [];

      if (klines.isEmpty) {
        log(
          'EastMoney',
          'getKline empty: code=$code secid=$secid data=${data?.keys.toList()}',
        );
      }

      _circuitBreaker.recordSuccess(name);

      return klines
          .map((line) {
            final parts = '$line'.split(',');
            if (parts.length < 9) return null;
            return KlineBar(
              date: parts[0],
              open: double.tryParse(parts[1]) ?? 0,
              close: double.tryParse(parts[2]) ?? 0,
              high: double.tryParse(parts[3]) ?? 0,
              low: double.tryParse(parts[4]) ?? 0,
              volume: double.tryParse(parts[5]) ?? 0,
              amount: double.tryParse(parts[6]) ?? 0,
              changePct: double.tryParse(parts[8]),
              turnoverRate: parts.length > 10
                  ? double.tryParse(parts[10])
                  : null,
            );
          })
          .whereType<KlineBar>()
          .toList();
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      rethrow;
    }
  }

  // ─── Money Flow ───

  @override
  Future<List<MoneyFlow>> getMoneyFlow(String code) async {
    if (_circuitBreaker.isOpen(name)) {
      throw DataFetchError('$name circuit open');
    }

    try {
      final response = await fetchWithRetry(
        'https://push2his.eastmoney.com/api/qt/stock/fflow/daykline/get',
        queryParams: {
          'lmt': '0',
          'klt': '101',
          'secid': _secId(code),
          'fields1': 'f1,f2,f3,f7',
          'fields2': 'f51,f52,f53,f54,f55,f56,f57,f58,f59,f60,f61,f62,f63',
          'ut': 'b2884a393a59ad64002292a3e90d46a5',
          '_': '${DateTime.now().millisecondsSinceEpoch}',
        },
        rateLimiter: _rateLimiter,
      );

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = json['data'] as Map<String, dynamic>?;
      final klines = data?['klines'] as List? ?? [];

      _circuitBreaker.recordSuccess(name);

      return klines
          .map((line) {
            final parts = '$line'.split(',');
            if (parts.length < 7) return null;
            return MoneyFlow(
              date: parts[0],
              mainNetInflow: double.tryParse(parts[1]) ?? 0,
              smallNetInflow: double.tryParse(parts[2]) ?? 0,
              mediumNetInflow: double.tryParse(parts[3]) ?? 0,
              largeNetInflow: double.tryParse(parts[4]) ?? 0,
              superLargeNetInflow: double.tryParse(parts[5]) ?? 0,
              closePrice: parts.length > 11 ? double.tryParse(parts[11]) : null,
              changePct: parts.length > 12 ? double.tryParse(parts[12]) : null,
            );
          })
          .whereType<MoneyFlow>()
          .toList();
    } catch (e) {
      _circuitBreaker.recordFailure(name);
      rethrow;
    }
  }

  // ─── ETF Quotes ───

  Future<List<StockQuote>> getETFQuotes() async {
    final cached = _quoteCache.getTracked('etf');
    if (cached != null) return cached;

    final response = await fetchWithRetry(
      'https://push2delay.eastmoney.com/api/qt/clist/get',
      queryParams: {
        'pn': '1',
        'pz': '5000',
        'po': '1',
        'np': '1',
        'ut': 'bd1d9ddb04089700cf9c27f6f7426281',
        'fltt': '2',
        'invt': '2',
        'fid': 'f12',
        'fs': 'b:MK0021,b:MK0022,b:MK0023,b:MK0024,b:MK0827',
        'fields': 'f2,f3,f4,f5,f6,f7,f8,f9,f12,f14,f15,f16,f17,f18,f20',
      },
      rateLimiter: _rateLimiter,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final diff = (json['data'] as Map?)?['diff'] as List? ?? [];

    final quotes = diff
        .map((item) {
          if (item is! Map) return null;
          final code = '${item['f12'] ?? ''}';
          if (code.isEmpty) return null;
          return StockQuote(
            code: code,
            name: '${item['f14'] ?? ''}',
            price: _d(item['f2']),
            change: _d(item['f4']),
            changePct: _d(item['f3']),
            open: _d(item['f17']),
            high: _d(item['f15']),
            low: _d(item['f16']),
            prevClose: _d(item['f18']),
            volume: _d(item['f5']),
            amount: _d(item['f6']),
            turnoverRate: _dn(item['f8']),
            pe: _dn(item['f9']),
            marketCap: _dn(item['f20']),
            source: name,
          );
        })
        .whereType<StockQuote>()
        .toList();

    _quoteCache.set('etf', quotes);
    return quotes;
  }

  Future<List<Map<String, dynamic>>> getStockList() async {
    final response = await fetchWithRetry(
      'https://push2delay.eastmoney.com/api/qt/clist/get',
      queryParams: {
        'pn': '1',
        'pz': '6000',
        'po': '1',
        'np': '1',
        'ut': 'bd1d9ddb04089700cf9c27f6f7426281',
        'fltt': '2',
        'invt': '2',
        'fid': 'f12',
        'fs': 'm:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048',
        'fields': 'f12,f14',
      },
      rateLimiter: _rateLimiter,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rows =
        (json['data'] as Map<String, dynamic>?)?['diff'] as List? ?? [];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return rows
        .map((row) {
          final data = row as Map<String, dynamic>;
          final code = '${data['f12'] ?? ''}'.trim();
          final name = '${data['f14'] ?? ''}'.trim();
          if (code.isEmpty || name.isEmpty) return null;
          return {
            'code': code,
            'name': name,
            'market': _marketFromCode(code),
            'stock_type': 'stock',
            'updated_at': updatedAt,
            'source': 'eastmoney',
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getFundList() async {
    final response = await fetchWithRetry(
      'https://fund.eastmoney.com/js/fundcode_search.js',
      headers: {'User-Agent': configuredHttpUserAgent()},
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    final rows = _parseEastmoneyFundCodeSearch(response.body);
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return rows
        .map((row) => _normalizeEastmoneyFundListRow(row, updatedAt))
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  String _marketFromCode(String code) {
    final clean = _cleanCode(code).trim();
    if (clean.startsWith('6')) return 'SH';
    if (clean.startsWith('4') ||
        clean.startsWith('8') ||
        clean.startsWith('9')) {
      return 'BJ';
    }
    return 'SZ';
  }

  Future<List<Map<String, dynamic>>> getFundNav(String fundCode) async {
    final plainCode = _normalizeFundPlainCode(fundCode);
    final response = await fetchWithRetry(
      'https://fund.eastmoney.com/pingzhongdata/$plainCode.js',
      headers: {
        'User-Agent': configuredHttpUserAgent(),
        'Referer': 'https://fund.eastmoney.com/$plainCode.html',
      },
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    return _parseEastmoneyFundNavRows(response.body, plainCode);
  }

  Future<List<Map<String, dynamic>>> getFundMoneyYield(String fundCode) async {
    final plainCode = _normalizeFundPlainCode(fundCode);
    final response = await fetchWithRetry(
      'https://fund.eastmoney.com/pingzhongdata/$plainCode.js',
      headers: {
        'User-Agent': configuredHttpUserAgent(),
        'Referer': 'https://fund.eastmoney.com/$plainCode.html',
      },
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    return _parseEastmoneyFundMoneyYieldRows(response.body, plainCode);
  }

  Future<List<Map<String, dynamic>>> getFundManagers() async {
    final response = await fetchWithRetry(
      'https://fund.eastmoney.com/Data/FundDataPortfolio_Interface.aspx',
      queryParams: {
        'dt': '14',
        'mc': 'returnjson',
        'ft': 'all',
        'pn': '500',
        'pi': '1',
        'sc': 'abbname',
        'st': 'asc',
      },
      headers: {'Referer': 'https://fund.eastmoney.com/manager/default.html'},
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    final rows = _parseEastmoneyFundManagerRows(response.body);
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    return rows
        .map((row) => _eastmoneyManagerRowToCanonical(row, updatedAt))
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getFundHolding(String fundCode) async {
    final plainCode = _normalizeFundPlainCode(fundCode);
    final response = await fetchWithRetry(
      'https://fundf10.eastmoney.com/FundArchivesDatas.aspx',
      queryParams: {
        'type': 'jjcc',
        'code': plainCode,
        'topline': '10000',
        'year': '${DateTime.now().year}',
        'month': '',
        'rt': '${DateTime.now().millisecondsSinceEpoch}',
      },
      headers: {
        'User-Agent': configuredHttpUserAgent(),
        'Referer': 'https://fundf10.eastmoney.com/ccmx_$plainCode.html',
      },
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    return _parseEastmoneyFundHoldingRows(response.body, plainCode);
  }

  Future<List<Map<String, dynamic>>> getFundPerformance() async {
    final response = await fetchWithRetry(
      'https://fund.eastmoney.com/data/rankhandler.aspx',
      queryParams: {
        'op': 'ph',
        'dt': 'kf',
        'ft': 'all',
        'rs': '',
        'gs': '0',
        'sc': '6yzf',
        'st': 'desc',
        'sd': '2024-01-01',
        'ed': '2026-12-31',
        'qdii': '',
        'tabSubtype': ',,,,,',
        'pi': '1',
        'pn': '500',
        'dx': '1',
        'v': '${DateTime.now().millisecondsSinceEpoch}',
      },
      headers: {'Referer': 'https://fund.eastmoney.com/data/fundranking.html'},
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    final rows = _parseEastmoneyFundPerformanceRows(response.body);
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    return rows
        .map(
          (row) => _normalizeFundPerformanceMetric(
            row,
            'eastmoney',
            'eastmoney.fund.performance_metrics',
            fetchedAt,
          ),
        )
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> getStockShareholders(
    String code, {
    String? reportDate,
  }) async {
    final eastmoneyCode = _eastmoneyF10Code(code);
    final latestReportDate =
        reportDate ?? await _getLatestStockShareholderReportDate(eastmoneyCode);
    if (latestReportDate == null || latestReportDate.isEmpty) return const [];
    final response = await fetchWithRetry(
      'https://emweb.securities.eastmoney.com/PC_HSF10/ShareholderResearch/PageSDGD',
      queryParams: {'code': eastmoneyCode, 'date': latestReportDate},
      headers: {
        'User-Agent': configuredHttpUserAgent(),
        'Referer':
            'https://emweb.securities.eastmoney.com/PC_HSF10/ShareholderResearch/Index?type=web&code=$eastmoneyCode',
      },
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    return _parseEastmoneyStockShareholderRows(
      response.body,
      _cleanCode(code),
      latestReportDate,
    );
  }

  Future<Map<String, dynamic>> getStockCompanyInfo(String code) async {
    final eastmoneyCode = _eastmoneyF10Code(code);
    final response = await fetchWithRetry(
      'https://emweb.securities.eastmoney.com/PC_HSF10/CompanySurvey/CompanySurveyAjax',
      queryParams: {'code': eastmoneyCode},
      headers: {
        'User-Agent': configuredHttpUserAgent(),
        'Referer':
            'https://emweb.securities.eastmoney.com/PC_HSF10/CompanySurvey/Index?type=web&code=$eastmoneyCode',
      },
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    return _parseEastmoneyStockCompanyInfo(response.body, _cleanCode(code));
  }

  DataCache<List<StockQuote>> get quoteCache => _quoteCache;

  Future<String?> _getLatestStockShareholderReportDate(
    String eastmoneyCode,
  ) async {
    final response = await fetchWithRetry(
      'https://emweb.securities.eastmoney.com/PC_HSF10/ShareholderResearch/PageAjax',
      queryParams: {'code': eastmoneyCode},
      headers: {
        'User-Agent': configuredHttpUserAgent(),
        'Referer':
            'https://emweb.securities.eastmoney.com/PC_HSF10/ShareholderResearch/Index?type=web&code=$eastmoneyCode',
      },
      timeout: const Duration(seconds: 60),
      rateLimiter: _rateLimiter,
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rows = (json['gdrs'] as List?)?.whereType<Map>().toList(
      growable: false,
    );
    if (rows == null || rows.isEmpty) return null;
    final endDate = '${rows.first['END_DATE'] ?? ''}';
    return _normalizeSimpleDate(endDate.substring(0, 10));
  }
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
double? _dn(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');

List<List<String>> _parseEastmoneyFundCodeSearch(String text) {
  final match = RegExp(r'var\s+r\s*=\s*(\[[\s\S]*\])\s*;?').firstMatch(text);
  if (match == null) return const [];
  final parsed = jsonDecode(match.group(1)!) as Object?;
  if (parsed is! List) return const [];
  return parsed
      .whereType<List>()
      .map((row) => row.map((cell) => '$cell').toList(growable: false))
      .toList(growable: false);
}

Map<String, dynamic>? _normalizeEastmoneyFundListRow(
  List<String> row,
  String updatedAt,
) {
  final plainCode = row.isNotEmpty ? row[0].trim() : '';
  final name = row.length > 2 ? row[2].trim() : '';
  if (plainCode.isEmpty || name.isEmpty) return null;
  return {
    'code': '$plainCode.OF',
    'name': name,
    'fund_type': row.length > 3 ? row[3].trim() : null,
    'company': null,
    'manager': null,
    'setup_date': null,
    'total_size': null,
    'nav': null,
    'nav_date': null,
    'return_1y': null,
    'return_3y': null,
    'return_ytd': null,
    'updated_at': updatedAt,
    'source': 'eastmoney',
    'raw_json': jsonEncode(row),
  };
}

List<List<String>> _parseEastmoneyFundManagerRows(String text) {
  final match = RegExp(
    r'data\s*:\s*(\[[\s\S]*?\])\s*,\s*record',
  ).firstMatch(text);
  if (match == null) return const [];
  final parsed = jsonDecode(match.group(1)!) as Object?;
  if (parsed is! List) return const [];
  return parsed
      .whereType<List>()
      .map((row) => row.map((cell) => '$cell').toList(growable: false))
      .toList(growable: false);
}

List<Map<String, dynamic>> _parseEastmoneyFundHoldingRows(
  String text,
  String fundCode,
) {
  final fetchedAt = DateTime.now().toUtc().toIso8601String();
  final sections = text.split(RegExp(r"<h4 class='t'>")).skip(1);
  final rows = <Map<String, dynamic>>[];
  for (final section in sections) {
    final reportDate = _parseFundHoldingReportDate(
      RegExp(r'截止至：<font[^>]*>([^<]+)</font>').firstMatch(section)?.group(1) ??
          (() {
            final quarter = RegExp(r'(\d{4})年([1-4])季度').firstMatch(section);
            if (quarter == null) return '';
            return '${quarter.group(1)}Q${quarter.group(2)}';
          })(),
    );
    final rowPattern = RegExp(
      r"<tr><td>(\d+)</td><td><a[^>]*>(\d{6})</a></td><td class='tol'><a[^>]*>([^<]+)</a></td>[\s\S]*?<td class='tor'>([^<]*)</td><td class='tor'>([^<]*)</td><td class='tor'>([^<]*)</td></tr>",
      multiLine: true,
    );
    for (final match in rowPattern.allMatches(section)) {
      rows.add({
        'fund_code': fundCode,
        'report_date': reportDate,
        'stock_code': match.group(2)?.trim() ?? '',
        'stock_name': _decodeHtml(match.group(3) ?? ''),
        'hold_pct': _safeNum(match.group(4)),
        'hold_shares': _safeNum(match.group(5)),
        'hold_value': _safeNum(match.group(6)),
        'rank': int.tryParse(match.group(1) ?? ''),
        'source': 'eastmoney',
        'fetched_at': fetchedAt,
      });
    }
  }
  return rows
      .where(
        (row) =>
            ('${row['stock_code'] ?? ''}').isNotEmpty &&
            ('${row['report_date'] ?? ''}').isNotEmpty,
      )
      .toList(growable: false);
}

List<Map<String, dynamic>> _parseEastmoneyStockShareholderRows(
  String text,
  String code,
  String reportDate,
) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  final rows =
      (json['sdgd'] as List?)?.whereType<Map>().toList(growable: false) ??
      const [];
  final fetchedAt = DateTime.now().toUtc().toIso8601String();
  final normalizedReportDate = _normalizeSimpleDate(reportDate) ?? reportDate;
  return rows
      .map((row) {
        final holderName = '${row['HOLDER_NAME'] ?? ''}'.trim();
        if (holderName.isEmpty) return null;
        return <String, dynamic>{
          'code': '${row['SECURITY_CODE'] ?? code}'.trim(),
          'report_date':
              _normalizeSimpleDate(
                '${row['END_DATE'] ?? ''}'.substring(0, 10),
              ) ??
              normalizedReportDate,
          'holder_name': holderName,
          'holder_type': '${row['SHARES_TYPE'] ?? 'top_shareholder'}'.trim(),
          'rank': _safeInt(row['HOLDER_RANK']),
          'hold_shares': _safeNum(row['HOLD_NUM']),
          'hold_pct': _safeNum(row['HOLD_NUM_RATIO']),
          'share_nature': '${row['SHARES_TYPE'] ?? ''}'.trim(),
          'announcement_date': null,
          'shareholder_note': '${row['HOLD_NUM_CHANGE'] ?? ''}'.trim().isEmpty
              ? null
              : '${row['HOLD_NUM_CHANGE']}'.trim(),
          'shareholder_count': null,
          'average_holding': null,
          'source': 'eastmoney',
          'fetched_at': fetchedAt,
          'raw_json': jsonEncode(row),
        };
      })
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

Map<String, dynamic> _parseEastmoneyStockCompanyInfo(String text, String code) {
  final json = jsonDecode(text) as Map<String, dynamic>;
  final basic = (json['jbzl'] as Map?)?.cast<String, dynamic>() ?? const {};
  final issue = (json['fxxg'] as Map?)?.cast<String, dynamic>() ?? const {};
  final fetchedAt = DateTime.now().toUtc().toIso8601String();
  final title = '${basic['gsmc'] ?? basic['agjc'] ?? basic['sshy'] ?? '公司概况'}'
      .trim();
  final summary = [
    if ('${basic['gsmc'] ?? ''}'.trim().isNotEmpty)
      '公司名称: ${'${basic['gsmc']}'.trim()}',
    if ('${basic['sshy'] ?? ''}'.trim().isNotEmpty)
      '所属行业: ${'${basic['sshy']}'.trim()}',
    if ('${basic['ssjys'] ?? ''}'.trim().isNotEmpty)
      '上市交易所: ${'${basic['ssjys']}'.trim()}',
    if ('${basic['frdb'] ?? ''}'.trim().isNotEmpty)
      '法人代表: ${'${basic['frdb']}'.trim()}',
    if ('${basic['zjl'] ?? ''}'.trim().isNotEmpty)
      '总经理: ${'${basic['zjl']}'.trim()}',
    if ('${basic['gswz'] ?? ''}'.trim().isNotEmpty)
      '公司网址: ${'${basic['gswz']}'.trim()}',
    if ('${basic['bgdz'] ?? ''}'.trim().isNotEmpty)
      '办公地址: ${'${basic['bgdz']}'.trim()}',
    if ('${issue['ssrq'] ?? ''}'.trim().isNotEmpty)
      '上市日期: ${'${issue['ssrq']}'.trim()}',
    if ('${basic['gsjj'] ?? ''}'.trim().isNotEmpty)
      '公司简介: ${'${basic['gsjj']}'.trim()}',
    if ('${basic['jyfw'] ?? ''}'.trim().isNotEmpty)
      '经营范围: ${'${basic['jyfw']}'.trim()}',
  ].join('\n');
  return {
    'code': code,
    'info_type': 'eastmoney_company_info',
    'title': title.isEmpty ? '公司概况' : title,
    'first_content': summary.isEmpty ? null : summary,
    'company_name': basic['gsmc'],
    'english_name': basic['ywmc'],
    'short_name': basic['agjc'],
    'industry': basic['sshy'],
    'industry_csrc': basic['sszjhhy'],
    'market_board': basic['zqlb'],
    'exchange': basic['ssjys'],
    'chairman': basic['dsz'],
    'general_manager': basic['zjl'],
    'legal_representative': basic['frdb'],
    'secretary': basic['zqswdb'],
    'region': basic['qy'],
    'registered_address': basic['zcdz'],
    'office_address': basic['bgdz'],
    'website': basic['gswz'],
    'email': basic['dzxx'],
    'phone': basic['lxdh'],
    'company_profile': basic['gsjj'],
    'business_scope': basic['jyfw'],
    'listing_date': issue['ssrq'],
    'listing_price': issue['mgfxj'],
    'raw_json': jsonEncode(json),
    'fetched_at': fetchedAt,
  };
}

List<Map<String, dynamic>> _parseEastmoneyFundNavRows(
  String text,
  String plainCode,
) {
  final match = RegExp(
    r'Data_netWorthTrend\s*=\s*(\[[\s\S]*?\])\s*;',
  ).firstMatch(text);
  if (match == null) return const [];
  final parsed = jsonDecode(match.group(1)!) as Object?;
  if (parsed is! List) return const [];
  final fetchedAt = DateTime.now().toUtc().toIso8601String();
  return parsed
      .whereType<Map>()
      .map((row) {
        final date = _dateFromEpochMs(row['x']);
        final nav = _safeNum(row['y']);
        if (date.isEmpty || nav == null || nav <= 0) return null;
        return {
          'code': '$plainCode.OF',
          'date': date,
          'nav': nav,
          'acc_nav': null,
          'daily_return': _safeNum(row['equityReturn']),
          'source': 'eastmoney',
          'fetched_at': fetchedAt,
          'raw_json': jsonEncode(row),
        };
      })
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
}

List<Map<String, dynamic>> _parseEastmoneyFundMoneyYieldRows(
  String text,
  String plainCode,
) {
  final income = _parseEastmoneyPointSeries(text, 'Data_millionCopiesIncome');
  final annualized = _parseEastmoneyPointSeries(
    text,
    'Data_sevenDaysYearIncome',
  );
  final fetchedAt = DateTime.now().toUtc().toIso8601String();
  final byDate = <String, Map<String, dynamic>>{};
  for (final point in income) {
    byDate[point.date] = {
      'code': plainCode,
      'date': point.date,
      'million_copies_income': point.value,
      'seven_day_annualized_yield': null,
      'source': 'eastmoney',
      'fetched_at': fetchedAt,
      'raw_json': jsonEncode({'million_copies_income': point.raw}),
    };
  }
  for (final point in annualized) {
    final existing = byDate[point.date];
    if (existing != null) {
      existing['seven_day_annualized_yield'] = point.value;
      existing['raw_json'] = jsonEncode({
        'million_copies_income': existing['million_copies_income'],
        'seven_day_annualized_yield': point.raw,
      });
    } else {
      byDate[point.date] = {
        'code': plainCode,
        'date': point.date,
        'million_copies_income': null,
        'seven_day_annualized_yield': point.value,
        'source': 'eastmoney',
        'fetched_at': fetchedAt,
        'raw_json': jsonEncode({'seven_day_annualized_yield': point.raw}),
      };
    }
  }
  final rows = byDate.values.toList(growable: false)
    ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  return rows;
}

List<({String date, double? value, Object? raw})> _parseEastmoneyPointSeries(
  String text,
  String variableName,
) {
  final match = RegExp(
    'var\\s+$variableName\\s*=\\s*(\\[[\\s\\S]*?\\]);',
  ).firstMatch(text);
  if (match == null) return const [];
  final parsed = jsonDecode(match.group(1)!) as Object?;
  if (parsed is! List) return const [];
  final rows = <({String date, double? value, Object? raw})>[];
  for (final row in parsed) {
    if (row is! List || row.length < 2) continue;
    final date = _dateFromEpochMs(row[0]);
    if (date.isEmpty) continue;
    rows.add((date: date, value: _safeNum(row[1]), raw: row));
  }
  return rows;
}

Map<String, dynamic>? _eastmoneyManagerRowToCanonical(
  List<String> row,
  String updatedAt,
) {
  final managerId = row.isNotEmpty ? row[0].trim() : '';
  final name = row.length > 1 ? row[1].trim() : '';
  if (name.isEmpty) return null;
  final company = row.length > 3 ? row[3].trim() : '';
  final fundCodes = row.length > 4
      ? row[4]
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList(growable: false)
      : const <String>[];
  final experienceDays = row.length > 6 ? _safeNum(row[6]) : null;
  return {
    'manager_id': managerId.isEmpty ? 'mgr_${name}_$company' : managerId,
    'manager_name': name,
    'name': name,
    'company': company.isEmpty ? null : company,
    'fund_code': fundCodes.isEmpty ? null : fundCodes.first,
    'fund_count': fundCodes.isEmpty ? null : fundCodes.length,
    'best_return': row.length > 11 ? _safeNum(row[11]) : null,
    'total_size': row.length > 10 ? _safeNum(row[10]) : null,
    'experience_years': experienceDays == null
        ? null
        : double.parse((experienceDays / 365.25).toStringAsFixed(2)),
    'updated_at': updatedAt,
    'source': 'eastmoney',
    'raw_json': jsonEncode(row),
  };
}

List<Map<String, dynamic>> _parseEastmoneyFundPerformanceRows(String text) {
  final match = RegExp(
    r'datas\s*:\s*\[(.*?)\]\s*,\s*allRecords',
    dotAll: true,
  ).firstMatch(text);
  if (match == null) return const [];
  final raw = '[${match.group(1)?.trim() ?? ''}]';
  if (raw.isEmpty) return const [];
  try {
    final records = jsonDecode(raw);
    if (records is! List) return const [];
    return records
        .whereType<String>()
        .where((row) => row.trim().isNotEmpty)
        .map((row) {
          final parts = row.split(',');
          return <String, dynamic>{
            'code': parts.isNotEmpty ? parts[0].trim() : '',
            'name': parts.length > 1 ? parts[1].trim() : '',
            'date': parts.length > 3 ? parts[3].trim() : '',
            'nav': parts.length > 4 ? parts[4].trim() : '',
            'return_1w': parts.length > 6 ? parts[6].trim() : '',
            'return_1m': parts.length > 7 ? parts[7].trim() : '',
            'return_3m': parts.length > 8 ? parts[8].trim() : '',
            'return_6m': parts.length > 9 ? parts[9].trim() : '',
            'return_1y': parts.length > 10 ? parts[10].trim() : '',
            'return_2y': parts.length > 11 ? parts[11].trim() : '',
            'return_3y': parts.length > 12 ? parts[12].trim() : '',
            'return_ytd': parts.length > 14 ? parts[14].trim() : '',
            'return_since_inception': parts.length > 15 ? parts[15].trim() : '',
          };
        })
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
}

Map<String, dynamic>? _normalizeFundPerformanceMetric(
  Map<String, dynamic> row,
  String provider,
  String capabilityId,
  String fetchedAt,
) {
  final code = '${row['code'] ?? ''}'.trim();
  if (code.isEmpty) return null;
  final metricDate =
      _normalizeSimpleDate('${row['date'] ?? ''}') ??
      fetchedAt.substring(0, 10);
  return {
    'code': code,
    'metric_date': metricDate,
    'provider': provider,
    'capability_id': capabilityId,
    'source_action': 'rankhandler.aspx',
    'nav': _safeNum(row['nav']),
    'return_ytd': _safeNum(row['return_ytd']),
    'return_1w': _safeNum(row['return_1w']),
    'return_1m': _safeNum(row['return_1m']),
    'return_3m': _safeNum(row['return_3m']),
    'return_6m': _safeNum(row['return_6m']),
    'return_1y': _safeNum(row['return_1y']),
    'return_2y': _safeNum(row['return_2y']),
    'return_3y': _safeNum(row['return_3y']),
    'return_since_inception': _safeNum(row['return_since_inception']),
    'fetched_at': fetchedAt,
    'raw_json': jsonEncode(row),
  };
}

String _parseFundHoldingReportDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final quarter = RegExp(r'^(\d{4})Q([1-4])$').firstMatch(trimmed);
  if (quarter != null) {
    const quarterEndMonth = {
      '1': '03-31',
      '2': '06-30',
      '3': '09-30',
      '4': '12-31',
    };
    return '${quarter.group(1)}-${quarterEndMonth[quarter.group(2)] ?? '12-31'}';
  }
  final normalized = _normalizeSimpleDate(trimmed);
  if (normalized != null) return normalized;
  return trimmed.length >= 10 ? trimmed.substring(0, 10) : trimmed;
}

String _decodeHtml(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .trim();
}

String _normalizeFundPlainCode(String value) {
  final trimmed = value.trim().toUpperCase();
  if (trimmed.endsWith('.OF')) return trimmed.substring(0, trimmed.length - 3);
  return trimmed;
}

String _eastmoneyF10Code(String value) {
  final clean = _cleanCode(value).toUpperCase();
  if (clean.startsWith('6')) return 'SH$clean';
  if (clean.startsWith('4') || clean.startsWith('8') || clean.startsWith('9')) {
    return 'BJ$clean';
  }
  return 'SZ$clean';
}

String _dateFromEpochMs(Object? value) {
  if (value == null) return '';
  final number = value is num ? value.toInt() : int.tryParse('$value');
  if (number == null) return '';
  return DateTime.fromMillisecondsSinceEpoch(
    number,
    isUtc: true,
  ).toIso8601String().substring(0, 10);
}

String? _normalizeSimpleDate(String value) {
  final compact = RegExp(r'^(\d{4})(\d{2})(\d{2})$').firstMatch(value);
  if (compact != null) {
    return '${compact.group(1)}-${compact.group(2)}-${compact.group(3)}';
  }
  final iso = RegExp(
    r'^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})$',
  ).firstMatch(value);
  if (iso != null) {
    return '${iso.group(1)}-${iso.group(2)!.padLeft(2, '0')}-${iso.group(3)!.padLeft(2, '0')}';
  }
  return null;
}

double? _safeNum(Object? value) {
  if (value == null) return null;
  final text = '$value'.trim();
  if (text.isEmpty || text == '--') return null;
  return double.tryParse(text.replaceAll(RegExp(r'[%,，,]'), ''));
}

int? _safeInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}
