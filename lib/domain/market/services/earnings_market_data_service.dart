import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/api_stats.dart';
import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/http_utils.dart';
import '../../../agent/tool_context.dart';
import '../repositories/earnings_market_data_repository.dart';
import 'yahoo_market_data_service.dart';

class EarningsMarketDataService {
  final EarningsMarketDataRepository _repository;
  final YahooMarketDataService _yahooService;
  final http.Client _httpClient;

  EarningsMarketDataService({
    DataManager? dataManager,
    http.Client? httpClient,
    YahooMarketDataService? yahooService,
  }) : this._internal(dataManager ?? DataManager(), httpClient, yahooService);

  EarningsMarketDataService._internal(
    DataManager dataManager,
    http.Client? httpClient,
    YahooMarketDataService? yahooService,
  ) : _repository = EarningsMarketDataRepository(dataManager),
      _yahooService =
          yahooService ??
          YahooMarketDataService(
            dataManager: dataManager,
            httpClient: httpClient ?? http.Client(),
          ),
      _httpClient = httpClient ?? http.Client();

  Future<Map<String, dynamic>> fetch(String symbol, ToolContext context) async {
    final clean = _normalizeSymbol(symbol);
    final isAShare = RegExp(r'^\d{6}$').hasMatch(clean);
    if (!isAShare) {
      return _yahooService.earnings(symbol, const <String, dynamic>{}, context);
    }

    final prefix = clean.startsWith('6')
        ? 'SH'
        : (clean.startsWith('9') || clean.startsWith('4') ? 'BJ' : 'SZ');
    final uri = Uri.parse(
      'https://emweb.securities.eastmoney.com/PC_HSF10/NewFinanceAnalysis/ZYZBAjaxNew?type=0&code=$prefix$clean',
    );

    final sw = Stopwatch()..start();
    http.Response resp;
    try {
      resp = await _httpClient.get(
        uri,
        headers: {'User-Agent': configuredHttpUserAgent()},
      );
    } catch (e) {
      sw.stop();
      _recordApi(uri, 0, sw.elapsedMilliseconds, success: false, error: '$e');
      rethrow;
    }
    sw.stop();
    _recordApi(
      uri,
      resp.statusCode,
      sw.elapsedMilliseconds,
      success: resp.statusCode == 200,
      error: resp.statusCode == 200 ? null : 'HTTP ${resp.statusCode}',
    );
    if (resp.statusCode != 200) {
      throw StateError('EastMoney API returned ${resp.statusCode}');
    }

    final body = jsonDecode(resp.body);
    final List<dynamic> data = body['data'] ?? [];
    if (data.isEmpty) {
      throw StateError('no financial data for $symbol');
    }

    final periods = data.take(4).map((d) {
      final m = d as Map<String, dynamic>;
      String fmt(dynamic v) =>
          v == null ? '—' : (v is num ? v.toStringAsFixed(2) : v.toString());
      String pct(dynamic v) =>
          v == null ? '—' : '${(v as num).toStringAsFixed(2)}%';
      String yi(dynamic v) =>
          v == null ? '—' : '${((v as num) / 1e8).toStringAsFixed(2)}亿';
      return {
        'period': m['REPORT_DATE_NAME'] ?? '',
        'reportDate': (m['REPORT_DATE'] as String?)?.substring(0, 10) ?? '',
        'revenue': yi(m['TOTALOPERATEREVE']),
        'revenueYoY': pct(m['TOTALOPERATEREVETZ']),
        'netProfit': yi(m['PARENTNETPROFIT']),
        'netProfitYoY': pct(m['PARENTNETPROFITTZ']),
        'deductedProfit': yi(m['KCFJCXSYJLR']),
        'deductedProfitYoY': pct(m['KCFJCXSYJLRTZ']),
        'grossMargin': pct(m['XSMLL']),
        'netMargin': pct(m['XSJLL']),
        'roe': pct(m['ROEJQ']),
        'eps': fmt(m['EPSJB']),
        'bps': fmt(m['BPS']),
        'cashFlowPerShare': fmt(m['MGJYXJJE']),
        'debtRatio': pct(m['ZCFZL']),
        'currentRatio': fmt(m['LD']),
      };
    }).toList();

    final latest = data.first as Map<String, dynamic>;
    _repository.saveEastmoneyFundamentals(clean, data);

    return {
      'action': 'earnings',
      'source': '东方财富',
      'symbol': symbol,
      'name': latest['SECURITY_NAME_ABBR'] ?? '',
      'latestReport': periods.first['period'],
      'periods': periods,
    };
  }

  void _recordApi(
    Uri uri,
    int statusCode,
    int durationMs, {
    required bool success,
    String? error,
  }) {
    ApiStats.instance.record(
      source: 'eastmoney',
      method: 'GET',
      url: uri.toString(),
      statusCode: statusCode,
      durationMs: durationMs,
      success: success,
      error: error,
    );
  }

  String _normalizeSymbol(String code) {
    final stripped = code.replaceAll(
      RegExp(r'\.(SH|SZ|BJ|HK)$', caseSensitive: false),
      '',
    );
    return stripped.replaceAll(
      RegExp(r'^(SH|SZ|BJ)', caseSensitive: false),
      '',
    );
  }
}
