import 'dart:convert';

import '../../../agent/data_fetcher/api_stats.dart';
import '../../../agent/data_fetcher/http_utils.dart';

class YahooMarketDataSupport {
  const YahooMarketDataSupport();

  static final Map<String, _YahooProviderGate> _providerGates = {};

  Map<String, String> get requestHeaders => {
    'User-Agent': configuredHttpUserAgent(),
    'Accept': 'application/json,text/plain,*/*',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  String yahooHttpFailure(String label, int statusCode) {
    final gate = switch (statusCode) {
      401 || 403 => 'credential-gated',
      429 => 'quota-gated',
      _ => null,
    };
    if (gate == null) return '$label returned $statusCode';
    return '$label returned $statusCode ($gate). Reuse query_yfinance cache when available, or retry later through the governed yfinance provider path.';
  }

  String? yahooGateMessage(String key, String label) {
    final gate = _providerGates[key];
    if (gate == null) return null;
    final now = DateTime.now().toUtc();
    if (gate.until.isBefore(now)) {
      _providerGates.remove(key);
      return null;
    }
    return '$label provider gate open until ${gate.until.toIso8601String()} (${gate.gateType}). ${gate.error}';
  }

  void recordYahooGate(String key, String label, int statusCode) {
    final gateType = switch (statusCode) {
      401 || 403 => 'credential-gated',
      429 => 'quota-gated',
      _ => null,
    };
    if (gateType == null) return;
    final cooldown = gateType == 'quota-gated'
        ? const Duration(minutes: 10)
        : const Duration(minutes: 30);
    _providerGates[key] = _YahooProviderGate(
      gateType: gateType,
      error: yahooHttpFailure(label, statusCode),
      until: DateTime.now().toUtc().add(cooldown),
    );
  }

  void clearYahooGate(String key) {
    _providerGates.remove(key);
  }

  static void resetProviderGatesForTest() {
    _providerGates.clear();
  }

  void assertGlobalSymbol(String symbol) {
    final value = symbol.trim();
    if (RegExp(r'^\d{6}$').hasMatch(value)) {
      throw ArgumentError(
        'Yahoo/yfinance is global-only and must not be used for A-share 6-digit symbol $value. Use quote/kline with A-share providers or EastMoney/TDX interfaces instead.',
      );
    }
  }

  void assertGlobalSymbols(Iterable<String> symbols) {
    for (final symbol in symbols) {
      assertGlobalSymbol(symbol);
    }
  }

  void recordApi(
    Uri uri,
    int statusCode,
    int durationMs, {
    required bool success,
    String? error,
  }) {
    ApiStats.instance.record(
      source: 'yahoo',
      method: 'GET',
      url: uri.toString(),
      statusCode: statusCode,
      durationMs: durationMs,
      success: success,
      error: error,
    );
  }

  int inputLimit(Map<String, dynamic> input, int fallback) {
    final value = input['limit'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return fallback;
  }

  double? lastNumber(List values) {
    for (var i = values.length - 1; i >= 0; i--) {
      final value = values[i];
      if (value is num) return value.toDouble();
    }
    return null;
  }

  Object? rawValue(Object? value) {
    if (value is Map && value.containsKey('raw')) return value['raw'];
    return value;
  }

  int? yahooUnixFromDate(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    final text = '$value'.trim();
    if (text.isEmpty) return null;
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    final parsed = DateTime.tryParse(text);
    if (parsed == null) return null;
    return parsed.toUtc().millisecondsSinceEpoch ~/ 1000;
  }

  String? yahooDateFromUnix(Object? value) {
    final unix = yahooUnixFromDate(value);
    if (unix == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      unix * 1000,
      isUtc: true,
    ).toIso8601String().substring(0, 10);
  }

  String? yahooDateTimeFromUnix(Object? value) {
    final unix = yahooUnixFromDate(value);
    if (unix == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      unix * 1000,
      isUtc: true,
    ).toIso8601String();
  }

  double? splitRatio(Map row) {
    final numerator = rawValue(row['numerator']);
    final denominator = rawValue(row['denominator']);
    if (numerator is num && denominator is num && denominator != 0) {
      return numerator / denominator;
    }
    final splitRatio = row['splitRatio'];
    if (splitRatio is String && splitRatio.contains(':')) {
      final parts = splitRatio.split(':');
      final left = double.tryParse(parts.first);
      final right = double.tryParse(parts.last);
      if (left != null && right != null && right != 0) return left / right;
    }
    return null;
  }

  String yahooPeriod(Object? value) {
    if (value is Map) {
      final fmt = value['fmt'];
      if (fmt != null && '$fmt'.isNotEmpty) return '$fmt';
      final raw = value['raw'];
      if (raw is num) {
        return DateTime.fromMillisecondsSinceEpoch(
          raw.toInt() * 1000,
          isUtc: true,
        ).toIso8601String().substring(0, 10);
      }
    }
    return 'unknown';
  }

  Map<String, dynamic> newsRow(String symbol, Map item, String updatedAt) {
    final published = yahooDateTimeFromUnix(item['providerPublishTime']);
    return {
      'symbol': symbol.toUpperCase(),
      'news_id':
          '${item['uuid'] ?? item['link'] ?? item['title'] ?? '${symbol}_$published'}',
      'title': item['title'],
      'publisher': item['publisher'],
      'published_at': published,
      'link': item['link'],
      'summary': item['summary'],
      'source': 'yahoo',
      'updated_at': updatedAt,
      'raw_json': jsonEncode(item),
    };
  }

  List<Map<String, dynamic>> optionRows(
    String symbol,
    String optionType,
    String? expiryDate,
    List contracts,
    String updatedAt,
  ) {
    return contracts.whereType<Map>().map((row) {
      return {
        'symbol': symbol.toUpperCase(),
        'expiry_date':
            yahooDateFromUnix(row['expiration'] ?? row['expirationDate']) ??
            expiryDate,
        'option_type': optionType,
        'contract_symbol': row['contractSymbol'],
        'strike': rawValue(row['strike']),
        'last_price': rawValue(row['lastPrice']),
        'bid': rawValue(row['bid']),
        'ask': rawValue(row['ask']),
        'change': rawValue(row['change']),
        'percent_change': rawValue(row['percentChange']),
        'volume': rawValue(row['volume']),
        'open_interest': rawValue(row['openInterest']),
        'implied_volatility': rawValue(row['impliedVolatility']),
        'in_the_money': row['inTheMoney'] == true ? 1 : 0,
        'currency': row['currency'],
        'last_trade_date': yahooDateTimeFromUnix(row['lastTradeDate']),
        'source': 'yahoo',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      };
    }).toList();
  }

  List<Map<String, dynamic>> corporateActionRows(
    String symbol,
    String actionType,
    Object? payload,
    String updatedAt,
  ) {
    if (payload is! Map) return const [];
    return payload.values
        .whereType<Map>()
        .map((row) {
          return {
            'symbol': symbol.toUpperCase(),
            'action_type': actionType,
            'action_date': yahooDateFromUnix(row['date']),
            'value': actionType == 'split'
                ? splitRatio(row)
                : rawValue(row['amount']),
            'source': 'yahoo',
            'updated_at': updatedAt,
            'raw_json': jsonEncode(row),
          };
        })
        .where((row) => row['action_date'] != null)
        .toList();
  }

  List<Map<String, dynamic>> profileRows(
    String symbol,
    Map<String, dynamic> fields,
    String updatedAt,
  ) {
    return fields.entries.map((entry) {
      final raw = rawValue(entry.value);
      return {
        'symbol': symbol.toUpperCase(),
        'field_key': entry.key,
        'field_value': raw == null ? null : '$raw',
        'field_type': raw == null ? 'null' : raw.runtimeType.toString(),
        'source': 'yahoo',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(entry.value),
      };
    }).toList();
  }

  List<Map<String, dynamic>> statementRows(
    String symbol,
    String statementType,
    List statements,
    String updatedAt,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final statement in statements) {
      if (statement is! Map) continue;
      final period = yahooPeriod(statement['endDate']);
      for (final entry in statement.entries) {
        if (entry.key == 'endDate' || entry.key == 'maxAge') continue;
        final raw = rawValue(entry.value);
        if (raw is! num) continue;
        rows.add({
          'symbol': symbol.toUpperCase(),
          'statement_type': statementType,
          'period': period,
          'item': '${entry.key}',
          'value': raw.toDouble(),
          'source': 'yahoo',
          'updated_at': updatedAt,
          'raw_json': jsonEncode(entry.value),
        });
      }
    }
    return rows;
  }

  List<Map<String, dynamic>> recommendationRows(
    String symbol,
    List recommendations,
    String updatedAt,
  ) {
    return recommendations.whereType<Map>().map((row) {
      return {
        'symbol': symbol.toUpperCase(),
        'period': '${row['period'] ?? 'unknown'}',
        'strong_buy': rawValue(row['strongBuy']),
        'buy': rawValue(row['buy']),
        'hold': rawValue(row['hold']),
        'sell': rawValue(row['sell']),
        'strong_sell': rawValue(row['strongSell']),
        'source': 'yahoo',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      };
    }).toList();
  }

  List<Map<String, dynamic>> holderRows(
    String symbol,
    String holderType,
    List holders,
    String updatedAt,
  ) {
    return holders.whereType<Map>().map((row) {
      return {
        'symbol': symbol.toUpperCase(),
        'holder_type': holderType,
        'holder_name':
            '${row['organization'] ?? row['holder'] ?? row['name'] ?? 'unknown'}',
        'reported_date': yahooPeriod(row['reportDate']),
        'pct_held': rawValue(row['pctHeld']),
        'shares': rawValue(row['position'] ?? row['shares']),
        'value': rawValue(row['value']),
        'source': 'yahoo',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      };
    }).toList();
  }

  List<Map<String, dynamic>> majorHolderRows(
    String symbol,
    Map<String, dynamic> breakdown,
    String updatedAt,
  ) {
    const labels = {
      'insidersPercentHeld': 'insiders_percent_held',
      'institutionsPercentHeld': 'institutions_percent_held',
      'institutionsFloatPercentHeld': 'institutions_float_percent_held',
      'institutionsCount': 'institutions_count',
    };
    return labels.entries
        .map((entry) {
          final raw = rawValue(breakdown[entry.key]);
          if (raw is! num) return null;
          return {
            'symbol': symbol.toUpperCase(),
            'holder_type': 'major_holders',
            'holder_name': entry.value,
            'reported_date': 'latest',
            'pct_held': entry.value.contains('percent') ? raw : null,
            'shares': null,
            'value': entry.value == 'institutions_count' ? raw : null,
            'source': 'yahoo',
            'updated_at': updatedAt,
            'raw_json': jsonEncode({entry.key: breakdown[entry.key]}),
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  List<Map<String, dynamic>> insiderRows(
    String symbol,
    List transactions,
    String updatedAt,
  ) {
    return transactions.whereType<Map>().map((row) {
      final date = yahooPeriod(row['startDate']);
      final insider = '${row['filerName'] ?? row['insider'] ?? 'unknown'}';
      return {
        'symbol': symbol.toUpperCase(),
        'transaction_id':
            '${date}_${insider}_${row['transactionText'] ?? row['shares'] ?? ''}',
        'insider': insider,
        'position': row['filerRelation'],
        'transaction_text': row['transactionText'],
        'start_date': date,
        'ownership': row['ownership'],
        'shares': rawValue(row['shares']),
        'value': rawValue(row['value']),
        'source': 'yahoo',
        'updated_at': updatedAt,
        'raw_json': jsonEncode(row),
      };
    }).toList();
  }
}

class _YahooProviderGate {
  final String gateType;
  final String error;
  final DateTime until;

  const _YahooProviderGate({
    required this.gateType,
    required this.error,
    required this.until,
  });
}
