import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_stats.dart';
import 'http_utils.dart';

/// EastMoney advanced APIs: limit-up/down pools, hot rank, dragon tiger board,
/// north-bound flow, unusual activity.
/// All free, no auth needed.
class EastMoneyAdvancedFetcher {
  final _rateLimiter = RateLimiter();
  final http.Client _client;

  EastMoneyAdvancedFetcher({http.Client? client})
    : _client = client ?? http.Client();

  // ─── Limit-up/down Pools (涨停/跌停池) — push2ex ───

  /// Get limit-up stock pool (涨停股池).
  /// Returns list of stocks that hit daily limit-up.
  Future<List<Map<String, dynamic>>> getLimitUpPool({String? date}) async {
    final d = date ?? _today();
    final response = await fetchWithRetry(
      'https://push2ex.eastmoney.com/getTopicZTPool',
      queryParams: {
        'ut': '7eea3edcaed734bea9cbfc24409ed989',
        'dpt': 'wz.ztzt',
        'Ession': d,
        'date': d,
      },
      rateLimiter: _rateLimiter,
    );
    return _parsePush2exPool(response.body);
  }

  /// Get limit-down stock pool (跌停股池).
  Future<List<Map<String, dynamic>>> getLimitDownPool({String? date}) async {
    final d = date ?? _today();
    final response = await fetchWithRetry(
      'https://push2ex.eastmoney.com/getTopicDTPool',
      queryParams: {
        'ut': '7eea3edcaed734bea9cbfc24409ed989',
        'dpt': 'wz.ztzt',
        'date': d,
      },
      rateLimiter: _rateLimiter,
    );
    return _parsePush2exPool(response.body);
  }

  /// Get yesterday's limit-up stocks (昨日涨停).
  Future<List<Map<String, dynamic>>> getYesterdayLimitUp({String? date}) async {
    final d = date ?? _today();
    final response = await fetchWithRetry(
      'https://push2ex.eastmoney.com/getYesterdayZTPool',
      queryParams: {
        'ut': '7eea3edcaed734bea9cbfc24409ed989',
        'dpt': 'wz.ztzt',
        'date': d,
      },
      rateLimiter: _rateLimiter,
    );
    return _parsePush2exPool(response.body);
  }

  /// Get failed limit-up pool (炸板股池).
  Future<List<Map<String, dynamic>>> getFailedLimitUp({String? date}) async {
    final d = date ?? _today();
    final response = await fetchWithRetry(
      'https://push2ex.eastmoney.com/getTopicZBPool',
      queryParams: {
        'ut': '7eea3edcaed734bea9cbfc24409ed989',
        'dpt': 'wz.ztzt',
        'date': d,
      },
      rateLimiter: _rateLimiter,
    );
    return _parsePush2exPool(response.body);
  }

  /// Get strong stock pool (强势股池).
  Future<List<Map<String, dynamic>>> getStrongPool({String? date}) async {
    final d = date ?? _today();
    final response = await fetchWithRetry(
      'https://push2ex.eastmoney.com/getTopicQSPool',
      queryParams: {
        'ut': '7eea3edcaed734bea9cbfc24409ed989',
        'dpt': 'wz.ztzt',
        'date': d,
      },
      rateLimiter: _rateLimiter,
    );
    return _parsePush2exPool(response.body);
  }

  // ─── Unusual Activity (盘口异动) — push2ex ───

  /// Get unusual activity (火箭发射/大笔买入/涨停打开等).
  /// type: all activity types (empty for all)
  Future<List<Map<String, dynamic>>> getUnusualActivity({
    int page = 1,
    int pageSize = 50,
  }) async {
    final response = await fetchWithRetry(
      'https://push2ex.eastmoney.com/getAllStockChanges',
      queryParams: {
        'ut': '7eea3edcaed734bea9cbfc24409ed989',
        'dpt': 'wzchanges',
        'type': '',
        'pageindex': '$page',
        'pagesize': '$pageSize',
      },
      rateLimiter: _rateLimiter,
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>?;
    final allstock = data?['allstock'] as List? ?? [];
    return allstock
        .map((item) {
          if (item is! Map) return <String, dynamic>{};
          return <String, dynamic>{
            'code': '${item['c'] ?? ''}',
            'name': '${item['n'] ?? ''}',
            'time': '${item['tm'] ?? ''}',
            'type': '${item['t'] ?? ''}',
            'info': '${item['i'] ?? ''}',
          };
        })
        .where((m) => m['code'] != '')
        .toList();
  }

  // ─── Hot Rank (人气榜) — emappdata ───

  /// Get hot stock ranking (人气排名).
  Future<List<Map<String, dynamic>>> getHotRank({
    int page = 1,
    int pageSize = 50,
  }) async {
    await _rateLimiter.wait();
    final uri = Uri.parse(
      'https://emappdata.eastmoney.com/stockrank/getAllCurrentList',
    );
    final requestBody = jsonEncode({
      'appId': 'appId01',
      'globalId': 'bfa45d2a70c74bb8a2c393c0e1aa8098',
      'marketType': '',
      'pageNo': page,
      'pageSize': pageSize,
    });
    final sw = Stopwatch()..start();
    var recorded = false;
    late final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'User-Agent': randomUserAgent(),
              'Referer': 'https://quote.eastmoney.com/',
              'Accept': 'application/json,text/plain,*/*',
            },
            body: requestBody,
          )
          .timeout(const Duration(seconds: 15));
      sw.stop();
      if (response.statusCode != 200) {
        ApiStats.instance.record(
          source: ApiStats.sourceFromUrl(uri.toString()),
          method: 'POST',
          url: uri.toString(),
          statusCode: response.statusCode,
          durationMs: sw.elapsedMilliseconds,
          success: false,
          error: 'HTTP ${response.statusCode}',
        );
        recorded = true;
        throw Exception('EastMoney hot rank HTTP ${response.statusCode}');
      }
      ApiStats.instance.record(
        source: ApiStats.sourceFromUrl(uri.toString()),
        method: 'POST',
        url: uri.toString(),
        statusCode: 200,
        durationMs: sw.elapsedMilliseconds,
        success: true,
        responseSummary: response.body.length > 200
            ? response.body.substring(0, 200)
            : response.body,
      );
      recorded = true;
    } catch (e) {
      if (sw.isRunning) sw.stop();
      if (!recorded) {
        ApiStats.instance.record(
          source: ApiStats.sourceFromUrl(uri.toString()),
          method: 'POST',
          url: uri.toString(),
          statusCode: -1,
          durationMs: sw.elapsedMilliseconds,
          success: false,
          error: '$e',
        );
      }
      rethrow;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['data'] as List? ?? [];
    final rows = data
        .map((item) {
          if (item is! Map) return <String, dynamic>{};
          return <String, dynamic>{
            'code': '${item['sc'] ?? ''}',
            'name': '${item['sn'] ?? ''}',
            'rank': item['rk'] ?? 0,
            'rankChange': item['rc'] ?? item['hisRc'],
            'hotValue': item['hv'],
            'marketCode': '${item['m'] ?? ''}',
          };
        })
        .where((m) => m['code'] != '')
        .toList();
    final names = await _fetchQuoteNames(rows.map((row) => '${row['code']}'));
    for (final row in rows) {
      if ('${row['name']}'.isNotEmpty) continue;
      row['name'] = names[_cleanCode('${row['code']}')] ?? '';
    }
    return rows;
  }

  Future<Map<String, String>> _fetchQuoteNames(Iterable<String> codes) async {
    final secids = codes
        .map(_eastmoneySecid)
        .where((id) => id.isNotEmpty)
        .toList();
    if (secids.isEmpty) return const {};
    try {
      final uri = Uri.https(
        'push2delay.eastmoney.com',
        '/api/qt/ulist.np/get',
        {
          'secids': secids.join(','),
          'fields': 'f12,f14',
          'fltt': '2',
          'invt': '2',
        },
      );
      final response = await _client.get(
        uri,
        headers: const {'Referer': 'https://quote.eastmoney.com/'},
      );
      if (response.statusCode != 200) return const {};
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final data = (json['data'] as Map?)?['diff'] as List? ?? const [];
      return {
        for (final row in data.whereType<Map>())
          if ('${row['f12'] ?? ''}'.isNotEmpty &&
              '${row['f14'] ?? ''}'.isNotEmpty)
            _cleanCode('${row['f12']}'): '${row['f14']}',
      };
    } catch (_) {
      return const {};
    }
  }

  String _eastmoneySecid(String raw) {
    final code = _cleanCode(raw);
    if (code.isEmpty) return '';
    return code.startsWith('6') ? '1.$code' : '0.$code';
  }

  String _cleanCode(String raw) {
    return raw
        .trim()
        .replaceFirst(RegExp(r'^S[HZ]', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^\d\.'), '');
  }

  // ─── Dragon Tiger Board (龙虎榜) — datacenter-web ───

  /// Get dragon tiger board data (龙虎榜).
  /// date format: YYYY-MM-DD (defaults to today)
  Future<List<Map<String, dynamic>>> getDragonTiger({
    String? date,
    int pageSize = 50,
  }) async {
    final d = date ?? _todayDash();
    final response = await fetchWithRetry(
      'https://datacenter-web.eastmoney.com/api/data/v1/get',
      queryParams: {
        'reportName': 'RPT_DAILYBILLBOARD_DETAILSNEW',
        'columns': 'ALL',
        'filter': '(TRADE_DATE>=\'$d\')',
        'pageNumber': '1',
        'pageSize': '$pageSize',
        'sortColumns': 'ACCUM_AMOUNT',
        'sortTypes': '-1',
        'source': 'WEB',
        'client': 'WEB',
      },
      rateLimiter: _rateLimiter,
    );
    return _parseDataCenter(response.body);
  }

  // ─── Northbound Flow (北向资金) — datacenter-web ───

  /// Get northbound capital flow history (北向资金历史).
  /// days: number of recent days to fetch.
  Future<List<Map<String, dynamic>>> getNorthboundFlow({int days = 20}) async {
    final response = await fetchWithRetry(
      'https://datacenter-web.eastmoney.com/api/data/v1/get',
      queryParams: {
        'reportName': 'RPT_MUTUAL_DEAL_HISTORY',
        'columns': 'ALL',
        'filter': '',
        'pageNumber': '1',
        'pageSize': '$days',
        'sortColumns': 'TRADE_DATE',
        'sortTypes': '-1',
        'source': 'WEB',
        'client': 'WEB',
      },
      rateLimiter: _rateLimiter,
    );
    return _parseDataCenter(response.body);
  }

  /// Get northbound individual stock holdings (北向持股).
  Future<List<Map<String, dynamic>>> getNorthboundHolding({
    String? code,
    int pageSize = 50,
  }) async {
    final filter = code != null ? "(SECURITY_CODE=\"$code\")" : '';
    final response = await fetchWithRetry(
      'https://datacenter-web.eastmoney.com/api/data/v1/get',
      queryParams: {
        'reportName': 'RPT_MUTUAL_STOCKHOLDDETAILS',
        'columns': 'ALL',
        'filter': filter,
        'pageNumber': '1',
        'pageSize': '$pageSize',
        'sortColumns': 'HOLD_MARKETCAP',
        'sortTypes': '-1',
        'source': 'WEB',
        'client': 'WEB',
      },
      rateLimiter: _rateLimiter,
    );
    return _parseDataCenter(response.body);
  }

  // ─── Money Flow Ranking (全市场资金流排名) ───

  /// Get market-wide money flow ranking (资金流入排名).
  /// period: 'today', '3day', '5day', '10day'
  Future<List<Map<String, dynamic>>> getFlowRanking({
    String period = 'today',
    int pageSize = 50,
  }) async {
    final fid = switch (period) {
      '3day' => 'f267',
      '5day' => 'f164',
      '10day' => 'f174',
      _ => 'f62', // today
    };
    final fields = switch (period) {
      '3day' => 'f12,f14,f267,f268,f269,f270,f271,f272',
      '5day' => 'f12,f14,f164,f165,f166,f167,f168,f169',
      '10day' => 'f12,f14,f174,f175,f176,f177,f178,f179',
      _ => 'f12,f14,f62,f66,f69,f72,f75,f78',
    };
    final response = await fetchWithRetry(
      'https://push2delay.eastmoney.com/api/qt/clist/get',
      queryParams: {
        'pn': '1',
        'pz': '$pageSize',
        'po': '1',
        'np': '1',
        'ut': 'b2884a393a59ad64002292a3e90d46a5',
        'fltt': '2',
        'invt': '2',
        'fid': fid,
        'fs': 'm:0 t:6,m:0 t:80,m:1 t:2,m:1 t:23',
        'fields': fields,
      },
      rateLimiter: _rateLimiter,
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final diff = (json['data'] as Map?)?['diff'] as List? ?? [];
    return diff
        .map((item) {
          if (item is! Map) return <String, dynamic>{};
          return <String, dynamic>{
            'code': '${item['f12'] ?? ''}',
            'name': '${item['f14'] ?? ''}',
            ...Map.fromEntries(
              item.entries
                  .where((e) => e.key != 'f12' && e.key != 'f14')
                  .map((e) => MapEntry(e.key.toString(), e.value)),
            ),
          };
        })
        .where((m) => m['code'] != '')
        .toList();
  }

  // ─── Helpers ───

  List<Map<String, dynamic>> _parsePush2exPool(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final data = json['data'] as Map<String, dynamic>?;
    final pool = data?['pool'] as List? ?? [];
    return pool
        .map((item) {
          if (item is! Map) return <String, dynamic>{};
          return <String, dynamic>{
            'code': '${item['c'] ?? ''}',
            'name': '${item['n'] ?? ''}',
            'price': _d(item['p']),
            'changePct': _d(item['zdp']),
            'amount': _d(item['amount']),
            'turnoverRate': _d(item['hs']),
            'firstLimitTime': '${item['fbt'] ?? ''}',
            'lastLimitTime': '${item['lbt'] ?? ''}',
            'limitCount': item['zbc'] ?? 0,
            'days': item['days'] ?? 0,
            'industry': '${item['hybk'] ?? ''}',
          };
        })
        .where((m) => m['code'] != '')
        .toList();
  }

  List<Map<String, dynamic>> _parseDataCenter(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final result = json['result'] as Map<String, dynamic>?;
    final data = result?['data'] as List? ?? [];
    return data.map((item) {
      if (item is! Map) return <String, dynamic>{};
      return Map<String, dynamic>.from(item);
    }).toList();
  }

  String _today() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  String _todayDash() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
