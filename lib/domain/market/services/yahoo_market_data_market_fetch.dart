import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/http_utils.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/tool_context.dart';
import '../repositories/yahoo_market_data_repository.dart';
import 'yahoo_market_data_support.dart';

class YahooMarketDataMarketFetch {
  final YahooMarketDataRepository _repository;
  final YahooMarketDataSupport _support;
  final http.Client _httpClient;

  YahooMarketDataMarketFetch({
    required YahooMarketDataRepository repository,
    required YahooMarketDataSupport support,
    required http.Client httpClient,
  }) : _repository = repository,
       _support = support,
       _httpClient = httpClient;

  Future<Map<String, dynamic>> price(
    List<String> symbols,
    ToolContext context,
  ) async {
    final results = <Map<String, dynamic>>[];
    final quotesToPersist = <StockQuote>[];

    for (final symbol in symbols) {
      final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=2d',
      );
      try {
        final sw = Stopwatch()..start();
        final response = await _httpClient
            .get(uri, headers: {'User-Agent': configuredHttpUserAgent()})
            .timeout(const Duration(seconds: 12));
        sw.stop();

        if (response.statusCode != 200) {
          _support.recordApi(
            uri,
            response.statusCode,
            sw.elapsedMilliseconds,
            success: false,
            error: 'HTTP ${response.statusCode}',
          );
          results.add({
            'symbol': symbol,
            'error': 'HTTP ${response.statusCode}',
          });
          continue;
        }
        _support.recordApi(uri, 200, sw.elapsedMilliseconds, success: true);

        final decoded = json.decode(response.body) as Map<String, dynamic>;
        final chart = decoded['chart'] as Map<String, dynamic>?;
        final resultList = chart?['result'] as List?;
        if (resultList == null || resultList.isEmpty) {
          results.add({'symbol': symbol, 'error': 'No data'});
          continue;
        }

        final meta = resultList[0]['meta'] as Map<String, dynamic>? ?? {};
        final quotes = resultList[0]['indicators']?['quote'] as List?;
        final timestamps = resultList[0]['timestamp'] as List? ?? [];
        final quote = quotes?.isNotEmpty == true
            ? quotes![0] as Map<String, dynamic>?
            : null;
        final closes = quote?['close'] as List? ?? [];
        final opens = quote?['open'] as List? ?? [];
        final highs = quote?['high'] as List? ?? [];
        final lows = quote?['low'] as List? ?? [];
        final volumes = quote?['volume'] as List? ?? [];
        final validCloses = closes.where((c) => c != null).toList();

        final price = (meta['regularMarketPrice'] as num?)?.toDouble();
        final prevClose = validCloses.length >= 2
            ? (validCloses[validCloses.length - 2] as num).toDouble()
            : null;
        final change = (price != null && prevClose != null && prevClose != 0)
            ? ((price - prevClose) / prevClose * 100)
            : null;
        final lastOpen = _support.lastNumber(opens);
        final lastHigh = _support.lastNumber(highs);
        final lastLow = _support.lastNumber(lows);
        final lastVolume = _support.lastNumber(volumes);
        final lastTimestamp = timestamps.isNotEmpty
            ? _support.yahooDateTimeFromUnix(timestamps.last)
            : null;

        if (price != null) {
          quotesToPersist.add(
            StockQuote(
              code: symbol,
              timestamp: lastTimestamp,
              name: (meta['shortName'] ?? meta['symbol'] ?? symbol).toString(),
              price: price,
              change: price - (prevClose ?? price),
              changePct: change ?? 0,
              open: lastOpen ?? price,
              high: lastHigh ?? price,
              low: lastLow ?? price,
              prevClose: prevClose ?? price,
              volume: lastVolume ?? 0,
              amount: 0,
              marketCap: (meta['marketCap'] as num?)?.toDouble(),
              source: 'yahoo',
            ),
          );
        }

        results.add({
          'symbol': symbol,
          'price': price,
          'previousClose': prevClose,
          'change%': change != null
              ? double.parse(change.toStringAsFixed(2))
              : null,
          'currency': meta['currency'],
          'marketState': meta['marketState'],
          'fiftyTwoWeekHigh': meta['fiftyTwoWeekHigh'],
          'fiftyTwoWeekLow': meta['fiftyTwoWeekLow'],
        });
      } catch (e) {
        _support.recordApi(uri, 0, 0, success: false, error: '$e');
        results.add({'symbol': symbol, 'error': '$e'});
      }
    }

    _repository.saveQuoteSnapshots(context, quotesToPersist);
    return {
      'action': 'price',
      'source': 'Yahoo Finance',
      'count': results.length,
      'data': results,
    };
  }

  Future<List<KlineBar>> fetchHistoryBars(
    String symbol,
    String period, {
    ToolContext? context,
  }) async {
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=$period',
    );
    final sw = Stopwatch()..start();
    http.Response response;
    try {
      response = await _httpClient
          .get(uri, headers: {'User-Agent': configuredHttpUserAgent()})
          .timeout(const Duration(seconds: 15));
    } catch (e) {
      sw.stop();
      _support.recordApi(
        uri,
        0,
        sw.elapsedMilliseconds,
        success: false,
        error: '$e',
      );
      return const [];
    }
    sw.stop();
    _support.recordApi(
      uri,
      response.statusCode,
      sw.elapsedMilliseconds,
      success: response.statusCode == 200,
      error: response.statusCode == 200 ? null : 'HTTP ${response.statusCode}',
    );
    if (response.statusCode != 200) return const [];

    final decoded = json.decode(response.body) as Map<String, dynamic>;
    final result = (decoded['chart'] as Map?)?['result'] as List?;
    if (result == null || result.isEmpty) return const [];

    final timestamps = result[0]['timestamp'] as List? ?? const [];
    final quote =
        (result[0]['indicators']?['quote'] as List?)?.first
            as Map<String, dynamic>? ??
        const {};
    final opens = quote['open'] as List? ?? const [];
    final highs = quote['high'] as List? ?? const [];
    final lows = quote['low'] as List? ?? const [];
    final closes = quote['close'] as List? ?? const [];
    final volumes = quote['volume'] as List? ?? const [];

    final bars = <KlineBar>[];
    for (var i = 0; i < timestamps.length; i++) {
      if (i >= opens.length ||
          opens[i] == null ||
          highs[i] == null ||
          lows[i] == null ||
          closes[i] == null) {
        continue;
      }
      final ts = timestamps[i] as int;
      final dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);
      bars.add(
        KlineBar(
          date:
              '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
          open: (opens[i] as num).toDouble(),
          high: (highs[i] as num).toDouble(),
          low: (lows[i] as num).toDouble(),
          close: (closes[i] as num).toDouble(),
          volume: (volumes.length > i && volumes[i] != null)
              ? (volumes[i] as num).toDouble()
              : 0,
        ),
      );
    }
    if (context != null) {
      _repository.saveKline(context, symbol, bars);
    }
    return bars;
  }

  Future<Map<String, dynamic>> history(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final period =
        (input['period'] as String? ?? input['range'] as String? ?? '6mo')
            .trim();
    final bars = await fetchHistoryBars(symbol, period, context: context);
    if (bars.isEmpty) {
      throw StateError('no Yahoo history for $symbol');
    }
    return {
      'action': 'yahoo_history',
      'symbol': symbol.toUpperCase(),
      'period': period,
      'source': 'yahoo',
      'count': bars.length,
      'ingestion': {
        'persisted': true,
        'tables': ['kline_daily'],
      },
      'data': bars
          .map(
            (bar) => {
              'date': bar.date,
              'open': bar.open,
              'high': bar.high,
              'low': bar.low,
              'close': bar.close,
              'volume': bar.volume,
            },
          )
          .toList(),
    };
  }

  Future<Map<String, dynamic>> news(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final limit = _support.inputLimit(input, 10).clamp(1, 50).toInt();
    final rows = <Map<String, dynamic>>[];
    final errors = <Map<String, dynamic>>[];
    final updatedAt = DateTime.now().toUtc().toIso8601String();

    for (final symbol in symbols) {
      final uri = Uri.https('query1.finance.yahoo.com', '/v1/finance/search', {
        'q': symbol,
        'quotesCount': '0',
        'newsCount': '$limit',
      });
      final sw = Stopwatch()..start();
      try {
        final response = await _httpClient
            .get(uri, headers: {'User-Agent': configuredHttpUserAgent()})
            .timeout(const Duration(seconds: 15));
        sw.stop();
        _support.recordApi(
          uri,
          response.statusCode,
          sw.elapsedMilliseconds,
          success: response.statusCode == 200,
          error: response.statusCode == 200
              ? null
              : 'HTTP ${response.statusCode}',
        );
        if (response.statusCode != 200) {
          errors.add({
            'symbol': symbol,
            'error': 'HTTP ${response.statusCode}',
          });
          continue;
        }
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final news = json['news'] as List? ?? const [];
        rows.addAll(
          news
              .whereType<Map>()
              .take(limit)
              .map((item) => _support.newsRow(symbol, item, updatedAt)),
        );
      } catch (e) {
        sw.stop();
        _support.recordApi(
          uri,
          0,
          sw.elapsedMilliseconds,
          success: false,
          error: '$e',
        );
        errors.add({'symbol': symbol, 'error': '$e'});
      }
    }

    _repository.saveNews(context, rows);
    return {
      'action': 'yahoo_news',
      'source': 'Yahoo Finance',
      'persisted': rows.isNotEmpty,
      'tables': rows.isEmpty ? const [] : const ['yfinance_news'],
      'count': rows.length,
      'errors': errors,
      'data': rows,
    };
  }
}
