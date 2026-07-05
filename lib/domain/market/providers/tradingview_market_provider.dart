import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/api_stats.dart';
import '../../../agent/data_fetcher/http_utils.dart';

abstract class TradingviewMarketProvider {
  Future<List<Map<String, dynamic>>> readScan(
    List<String> symbols, {
    required List<String> indicators,
    required String timeframe,
  });
}

class HttpTradingviewMarketProvider implements TradingviewMarketProvider {
  final http.Client _httpClient;

  HttpTradingviewMarketProvider({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  @override
  Future<List<Map<String, dynamic>>> readScan(
    List<String> symbols, {
    required List<String> indicators,
    required String timeframe,
  }) async {
    final suffix = _kTimeframeSuffix[timeframe.toLowerCase()] ?? '';
    final scanUrl =
        'https://scanner.tradingview.com/${_detectMarket(symbols)}/scan';
    final body = json.encode({
      'symbols': {
        'tickers': symbols,
        'query': {'types': []},
      },
      'columns': suffix.isEmpty
          ? indicators
          : indicators.map((column) => '$column$suffix').toList(),
    });

    final sw = Stopwatch()..start();
    final response = await _httpClient
        .post(Uri.parse(scanUrl), headers: _browserHeaders(), body: body)
        .timeout(const Duration(seconds: 15));
    sw.stop();

    if (response.statusCode != 200) {
      ApiStats.instance.record(
        source: 'tradingview',
        method: 'POST',
        url: scanUrl,
        statusCode: response.statusCode,
        durationMs: sw.elapsedMilliseconds,
        success: false,
        error: 'HTTP ${response.statusCode}',
      );
      throw Exception(
        'TradingView Scanner HTTP ${response.statusCode}: '
        '${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
      );
    }

    ApiStats.instance.record(
      source: 'tradingview',
      method: 'POST',
      url: scanUrl,
      statusCode: 200,
      durationMs: sw.elapsedMilliseconds,
      success: true,
    );

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final data = (decoded['data'] as List? ?? []).map((item) {
      final row = item as Map<String, dynamic>;
      final values = row['d'] as List? ?? [];
      final entry = <String, dynamic>{'symbol': row['s'] as String? ?? ''};
      for (var i = 0; i < indicators.length && i < values.length; i++) {
        final value = values[i];
        entry[indicators[i]] = value is num
            ? double.parse(value.toStringAsFixed(4))
            : value;
      }
      return entry;
    }).toList();
    return data;
  }
}

Map<String, String> _browserHeaders() => {
  'User-Agent': configuredHttpUserAgent(),
  'Origin': 'https://www.tradingview.com',
  'Referer': 'https://www.tradingview.com/',
  'Content-Type': 'application/json',
};

const _kExchangeToMarket = {
  'binance': 'crypto',
  'kucoin': 'crypto',
  'coinbase': 'crypto',
  'okx': 'crypto',
  'bybit': 'crypto',
  'mexc': 'crypto',
  'bitget': 'crypto',
  'bitfinex': 'crypto',
  'gateio': 'crypto',
  'nasdaq': 'america',
  'nyse': 'america',
  'amex': 'america',
  'hkex': 'hongkong',
  'hk': 'hongkong',
  'sse': 'china',
  'szse': 'china',
  'twse': 'taiwan',
  'tpex': 'taiwan',
  'asx': 'australia',
  'bist': 'turkey',
};

const _kTimeframeSuffix = {
  '5m': '|5',
  '15m': '|15',
  '30m': '|30',
  '1h': '|60',
  '2h': '|120',
  '4h': '|240',
  '1d': '',
  '1w': '|1W',
  '1m': '|1M',
};

String _normalizeSymbol(String code) {
  final trimmed = code.replaceAll(
    RegExp(r'\.(SH|SZ|BJ|HK)$', caseSensitive: false),
    '',
  );
  return trimmed.replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '');
}

String _detectMarket(List<String> symbols) {
  if (symbols.isEmpty) return 'crypto';
  final first = symbols.first;
  final clean = _normalizeSymbol(first);
  if (RegExp(r'^\d{6}$').hasMatch(clean)) return 'china';
  if (first.toUpperCase().endsWith('.HK')) return 'hongkong';
  final exchange = first.contains(':')
      ? first.split(':').first.toLowerCase()
      : '';
  return _kExchangeToMarket[exchange] ?? 'america';
}
