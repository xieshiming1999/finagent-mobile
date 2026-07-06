import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/data_fetcher/data_manager.dart';
import 'package:finagent/agent/tools/market_data_tool/market_data_tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final options = _Options.parse(args);
  final basePath = options.basePath ?? _defaultBasePath();
  Directory(basePath).createSync(recursive: true);
  _bootstrapBundledTdxServers(basePath);

  final credentials = _Credentials.load(options);
  final dataManager = DataManager(
    tushareToken: credentials.tushareToken,
    basePath: basePath,
  );
  final tool = MarketDataTool(dataManager: dataManager);
  final context = ToolContext(
    basePath: basePath,
    serviceBaseUrl: options.serviceBaseUrl,
    skipPermissions: true,
  );

  final specs = options.includeReadback
      ? [..._probeSpecs, ..._readbackSpecs]
      : _probeSpecs;
  final selected = options.actions.isEmpty
      ? specs
      : specs
            .where((spec) => options.actions.contains(spec.action))
            .toList(growable: false);
  final rows = <Map<String, dynamic>>[];
  final providerFailures = <String, int>{};
  for (final spec in selected) {
    final failureCount = providerFailures[spec.provider] ?? 0;
    if (failureCount >= options.maxProviderFailures) {
      rows.add(
        _failureRow(
          spec,
          DateTime.now().toUtc(),
          'runtime_unavailable',
          'runtime-blocked',
          '${spec.provider} probe circuit open after $failureCount failures',
        ),
      );
      continue;
    }
    if (spec.credential == 'tushare' && !credentials.hasTushare) {
      rows.add(
        _gatedRow(spec, 'credential-gated', 'TUSHARE_TOKEN unavailable'),
      );
      continue;
    }
    final started = DateTime.now().toUtc();
    try {
      final result = await tool
          .call('probe_${spec.action}', spec.input, context)
          .timeout(Duration(milliseconds: options.timeoutMs));
      final parsed = _parseResult(result.content);
      rows.add({
        'id': spec.id,
        'runtime': 'shared_mobile',
        'tool': 'MarketData',
        'action': spec.action,
        'provider': spec.provider,
        'params': spec.input,
        'status': result.isError ? 'failed' : 'passed',
        'validationState': result.isError
            ? _failureValidationState(result.content)
            : _successValidationState(parsed),
        'failureClass': result.isError ? _failureClass(result.content) : null,
        'error': result.isError ? result.content : null,
        'durationMs': DateTime.now().toUtc().difference(started).inMilliseconds,
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
        'rowCount': _rowCount(parsed),
        'columns': _columns(parsed),
        'firstRowSchema': _firstRowSchema(parsed),
        'preview': _preview(parsed),
      });
    } on TimeoutException catch (e) {
      rows.add(_failureRow(spec, started, 'timeout', 'runtime-blocked', '$e'));
      providerFailures[spec.provider] = failureCount + 1;
    } catch (e) {
      rows.add(
        _failureRow(
          spec,
          started,
          _failureClass('$e'),
          _failureValidationState('$e'),
          '$e',
        ),
      );
      providerFailures[spec.provider] = failureCount + 1;
    }
    if (options.waitMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: options.waitMs));
    }
  }

  final payload = {
    'generatedAt': DateTime.now().toUtc().toIso8601String(),
    'runtime': 'shared_mobile_finagent',
    'source': 'finagent/tool/finance_mobile_live_probe.dart',
    'basePath': basePath,
    'credentialSources': credentials.sources,
    'summary': _summary(rows),
    'rows': rows,
  };
  final text = const JsonEncoder.withIndent('  ').convert(payload);
  if (options.output == null) {
    stdout.writeln(text);
  } else {
    final file = File(options.output!);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('$text\n');
  }
  exitCode = 0;
  exit(0);
}

Map<String, dynamic> _gatedRow(_ProbeSpec spec, String state, String message) =>
    {
      'id': spec.id,
      'runtime': 'shared_mobile',
      'tool': 'MarketData',
      'action': spec.action,
      'provider': spec.provider,
      'params': spec.input,
      'status': 'credential-gated',
      'validationState': state,
      'failureClass': 'missing_credential',
      'error': message,
      'durationMs': 0,
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      'rowCount': 0,
      'columns': <String>[],
      'firstRowSchema': <String, String>{},
      'preview': null,
    };

Map<String, dynamic> _failureRow(
  _ProbeSpec spec,
  DateTime started,
  String failureClass,
  String validationState,
  String error,
) => {
  'id': spec.id,
  'runtime': 'shared_mobile',
  'tool': 'MarketData',
  'action': spec.action,
  'provider': spec.provider,
  'params': spec.input,
  'status': 'failed',
  'validationState': validationState,
  'failureClass': failureClass,
  'error': error,
  'durationMs': DateTime.now().toUtc().difference(started).inMilliseconds,
  'fetchedAt': DateTime.now().toUtc().toIso8601String(),
  'rowCount': 0,
  'columns': <String>[],
  'firstRowSchema': <String, String>{},
  'preview': null,
};

Map<String, int> _summary(List<Map<String, dynamic>> rows) {
  final summary = <String, int>{'total': rows.length};
  for (final row in rows) {
    final status = row['status'] as String? ?? 'unknown';
    summary[status] = (summary[status] ?? 0) + 1;
    final state = row['validationState'] as String? ?? 'unknown';
    summary[state] = (summary[state] ?? 0) + 1;
  }
  return summary;
}

dynamic _parseResult(String content) {
  try {
    return jsonDecode(content);
  } catch (_) {
    return {'text': content};
  }
}

String _successValidationState(dynamic parsed) {
  final count = _rowCount(parsed);
  return count > 0 ? 'valid-schema-observed' : 'valid-empty-response';
}

String _failureValidationState(String error) {
  final text = error.toLowerCase();
  if (_isQuotaOrRateLimit(text)) {
    return 'quota-gated';
  }
  if (text.contains('missing') && text.contains('token')) {
    return 'credential-gated';
  }
  if (text.contains('permission') ||
      text.contains('权限') ||
      text.contains('401') ||
      text.contains('unauthorized')) {
    return 'credential-gated';
  }
  if (text.contains('unsupported') || text.contains('unknown action')) {
    return 'unsupported-by-provider';
  }
  if (text.contains('required') || text.contains('invalid')) {
    return 'invalid-parameters';
  }
  if (text.contains('timeout')) return 'runtime-blocked';
  return 'transport-or-provider-unstable';
}

String _failureClass(String error) {
  final text = error.toLowerCase();
  if (_isQuotaOrRateLimit(text)) {
    return 'quota-or-rate-limit';
  }
  if (text.contains('permission') ||
      text.contains('token') ||
      text.contains('权限') ||
      text.contains('401') ||
      text.contains('unauthorized')) {
    return 'credential-or-permission';
  }
  if (text.contains('required') || text.contains('invalid')) {
    return 'invalid-parameters';
  }
  if (text.contains('unsupported') || text.contains('unknown action')) {
    return 'schema-or-contract';
  }
  if (text.contains('timeout')) return 'timeout';
  return 'transport';
}

bool _isQuotaOrRateLimit(String text) =>
    text.contains('quota') ||
    text.contains('429') ||
    text.contains('too many requests') ||
    text.contains('rate limit') ||
    text.contains('tushare_rate_limit') ||
    text.contains('frequency') ||
    text.contains('频率') ||
    text.contains('超限');

int _rowCount(dynamic parsed) {
  if (parsed is List) return parsed.length;
  if (parsed is Map) {
    for (final key in const [
      'data',
      'rows',
      'items',
      'quotes',
      'news',
      'options',
    ]) {
      final value = parsed[key];
      if (value is List) return value.length;
    }
    for (final value in parsed.values) {
      if (value is List) return value.length;
    }
    return parsed.isEmpty ? 0 : 1;
  }
  return parsed == null ? 0 : 1;
}

List<String> _columns(dynamic parsed) {
  final row = _firstRow(parsed);
  if (row is Map) return row.keys.map((key) => '$key').toList()..sort();
  if (parsed is Map) return parsed.keys.map((key) => '$key').toList()..sort();
  return <String>[];
}

Map<String, String> _firstRowSchema(dynamic parsed) {
  final row = _firstRow(parsed);
  if (row is! Map) return <String, String>{};
  return row.map(
    (key, value) => MapEntry('$key', value.runtimeType.toString()),
  );
}

dynamic _preview(dynamic parsed) {
  final row = _firstRow(parsed);
  if (row != null) return row;
  return parsed;
}

dynamic _firstRow(dynamic parsed) {
  if (parsed is List && parsed.isNotEmpty) return parsed.first;
  if (parsed is Map) {
    for (final key in const [
      'data',
      'rows',
      'items',
      'quotes',
      'news',
      'options',
    ]) {
      final value = parsed[key];
      if (value is List && value.isNotEmpty) return value.first;
    }
    for (final value in parsed.values) {
      if (value is List && value.isNotEmpty) return value.first;
    }
  }
  return null;
}

String _defaultBasePath() {
  final home = Platform.environment['HOME'] ?? Directory.current.path;
  return p.join(home, '.finagent', 'finance_mobile_live_probe');
}

void _bootstrapBundledTdxServers(String basePath) {
  final repoRoot = p.normalize(p.join(Directory.current.path, '..'));
  final copies = {
    p.join(repoRoot, 'finagent', 'assets', 'finance', 'tdx_servers.json'): p
        .join(basePath, 'memory', '.tdx_servers.json'),
    p.join(repoRoot, 'finagent', 'assets', 'finance', 'tdx_ex_servers.json'): p
        .join(basePath, 'memory', '.tdx_ex_servers.json'),
  };
  for (final entry in copies.entries) {
    final source = File(entry.key);
    final target = File(entry.value);
    if (!source.existsSync() || target.existsSync()) continue;
    target.parent.createSync(recursive: true);
    target.writeAsStringSync(source.readAsStringSync());
  }
}

class _Credentials {
  final String? tushareToken;
  final Map<String, String> sources;

  const _Credentials({required this.tushareToken, required this.sources});

  bool get hasTushare => tushareToken != null && tushareToken!.isNotEmpty;

  static _Credentials load(_Options options) {
    final config = _readFinElectronConfig();
    final tushare =
        options.tushareToken ??
        Platform.environment['TUSHARE_TOKEN'] ??
        Platform.environment['TUSHARE_API_TOKEN'] ??
        config['TUSHARE_TOKEN'];
    return _Credentials(
      tushareToken: tushare,
      sources: {
        'TUSHARE_TOKEN': tushare == null || tushare.isEmpty
            ? 'missing'
            : options.tushareToken != null
            ? 'cli'
            : Platform.environment['TUSHARE_TOKEN'] != null ||
                  Platform.environment['TUSHARE_API_TOKEN'] != null
            ? 'environment'
            : '~/.finagent-mobile/config.json apiKeys',
      },
    );
  }
}

Map<String, String> _readFinElectronConfig() {
  final home = Platform.environment['HOME'];
  if (home == null || home.isEmpty) return const {};
  final file = File(p.join(home, '.finagent-mobile', 'config.json'));
  if (!file.existsSync()) return const {};
  try {
    final parsed = jsonDecode(file.readAsStringSync());
    if (parsed is! Map) return const {};
    final apiKeys = parsed['apiKeys'];
    if (apiKeys is! Map) return const {};
    return apiKeys.map((key, value) => MapEntry('$key', '$value'));
  } catch (_) {
    return const {};
  }
}

class _Options {
  final String? output;
  final String? basePath;
  final String? tushareToken;
  final String serviceBaseUrl;
  final int waitMs;
  final int timeoutMs;
  final int maxProviderFailures;
  final bool includeReadback;
  final Set<String> actions;

  const _Options({
    required this.output,
    required this.basePath,
    required this.tushareToken,
    required this.serviceBaseUrl,
    required this.waitMs,
    required this.timeoutMs,
    required this.maxProviderFailures,
    required this.includeReadback,
    required this.actions,
  });

  static _Options parse(List<String> args) {
    final parsed = <String, String>{};
    for (var i = 0; i < args.length; i++) {
      final raw = args[i];
      if (!raw.startsWith('--')) continue;
      final key = raw.substring(2);
      final next = i + 1 < args.length ? args[i + 1] : null;
      if (next == null || next.startsWith('--')) {
        parsed[key] = 'true';
      } else {
        parsed[key] = next;
        i++;
      }
    }
    final actionText = parsed['actions'] ?? '';
    return _Options(
      output: parsed['output'],
      basePath: parsed['base-path'],
      tushareToken: parsed['tushare-token'],
      serviceBaseUrl: parsed['service-base-url'] ?? 'http://localhost:3033',
      waitMs: int.tryParse(parsed['wait-ms'] ?? '') ?? 2000,
      timeoutMs: int.tryParse(parsed['timeout-ms'] ?? '') ?? 30000,
      maxProviderFailures:
          int.tryParse(parsed['max-provider-failures'] ?? '') ?? 2,
      includeReadback: parsed['include-readback'] != 'false',
      actions: actionText
          .split(',')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet(),
    );
  }
}

class _ProbeSpec {
  final String action;
  final String provider;
  final Map<String, dynamic> input;
  final String? credential;

  const _ProbeSpec({
    required this.action,
    required this.provider,
    required this.input,
    this.credential,
  });

  String get id => 'mobile_marketdata_$action';
}

const _probeSpecs = [
  _ProbeSpec(
    action: 'quote',
    provider: 'local',
    input: {
      'action': 'quote',
      'symbols': ['600519'],
      'source': 'tdx',
      'cache': false,
    },
  ),
  _ProbeSpec(
    action: 'kline',
    provider: 'local',
    input: {
      'action': 'kline',
      'symbols': ['600519'],
      'period': 'daily',
      'startDate': '2026-01-01',
      'source': 'tdx',
      'cache': false,
    },
  ),
  _ProbeSpec(
    action: 'flow',
    provider: 'eastmoney',
    input: {
      'action': 'flow',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'flow_rank',
    provider: 'eastmoney',
    input: {'action': 'flow_rank', 'period': 'today', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'sector',
    provider: 'eastmoney',
    input: {'action': 'sector', 'boardType': 'industry', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'chip',
    provider: 'eastmoney',
    input: {
      'action': 'chip',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(action: 'etf', provider: 'eastmoney', input: {'action': 'etf'}),
  _ProbeSpec(
    action: 'earnings',
    provider: 'eastmoney',
    input: {
      'action': 'earnings',
      'symbols': ['000858'],
    },
  ),
  _ProbeSpec(
    action: 'price',
    provider: 'yfinance',
    input: {
      'action': 'price',
      'symbols': ['AAPL'],
    },
  ),
  _ProbeSpec(
    action: 'yahoo_history',
    provider: 'yfinance',
    input: {
      'action': 'yahoo_history',
      'symbols': ['AAPL'],
      'period': '1mo',
    },
  ),
  _ProbeSpec(
    action: 'yahoo_earnings',
    provider: 'yfinance',
    input: {
      'action': 'yahoo_earnings',
      'symbols': ['AAPL'],
    },
  ),
  _ProbeSpec(
    action: 'yahoo_news',
    provider: 'yfinance',
    input: {
      'action': 'yahoo_news',
      'symbols': ['AAPL'],
      'limit': 3,
    },
  ),
  _ProbeSpec(
    action: 'yahoo_options',
    provider: 'yfinance',
    input: {
      'action': 'yahoo_options',
      'symbols': ['AAPL'],
    },
  ),
  _ProbeSpec(
    action: 'yahoo_actions',
    provider: 'yfinance',
    input: {
      'action': 'yahoo_actions',
      'symbols': ['AAPL'],
      'period': '1y',
    },
  ),
  _ProbeSpec(
    action: 'scan',
    provider: 'tradingview',
    input: {
      'action': 'scan',
      'symbols': ['NASDAQ:AAPL'],
      'indicators': ['close', 'RSI', 'Recommend.All'],
      'timeframe': '1d',
    },
  ),
  _ProbeSpec(
    action: 'limit_up',
    provider: 'eastmoney',
    input: {'action': 'limit_up', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'limit_down',
    provider: 'eastmoney',
    input: {'action': 'limit_down', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'hot_rank',
    provider: 'eastmoney',
    input: {'action': 'hot_rank', 'pageSize': 5},
  ),
  _ProbeSpec(
    action: 'dragon_tiger',
    provider: 'eastmoney',
    input: {'action': 'dragon_tiger', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'northbound',
    provider: 'eastmoney',
    input: {'action': 'northbound', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'unusual',
    provider: 'eastmoney',
    input: {'action': 'unusual', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'tdx_tick_chart',
    provider: 'tdx',
    input: {
      'action': 'tdx_tick_chart',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_transactions',
    provider: 'tdx',
    input: {
      'action': 'tdx_transactions',
      'symbols': ['600519'],
      'count': 10,
    },
  ),
  _ProbeSpec(
    action: 'tdx_finance',
    provider: 'tdx',
    input: {
      'action': 'tdx_finance',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_xdxr',
    provider: 'tdx',
    input: {
      'action': 'tdx_xdxr',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_unusual',
    provider: 'tdx',
    input: {'action': 'tdx_unusual'},
  ),
  _ProbeSpec(
    action: 'tdx_index_info',
    provider: 'tdx',
    input: {
      'action': 'tdx_index_info',
      'symbols': ['000001'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_count',
    provider: 'tdx',
    input: {'action': 'tdx_count'},
  ),
  _ProbeSpec(
    action: 'tdx_sampling',
    provider: 'tdx',
    input: {
      'action': 'tdx_sampling',
      'symbols': ['000001'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_stock_list',
    provider: 'tdx',
    input: {'action': 'tdx_stock_list', 'market': 1, 'start': 0, 'count': 10},
  ),
  _ProbeSpec(
    action: 'tdx_volume_profile',
    provider: 'tdx',
    input: {
      'action': 'tdx_volume_profile',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_auction',
    provider: 'tdx',
    input: {
      'action': 'tdx_auction',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_history_tick',
    provider: 'tdx',
    input: {
      'action': 'tdx_history_tick',
      'symbols': ['600519'],
      'date': '20260519',
    },
  ),
  _ProbeSpec(
    action: 'tdx_momentum',
    provider: 'tdx',
    input: {
      'action': 'tdx_momentum',
      'symbols': ['000001'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_history_trans',
    provider: 'tdx',
    input: {
      'action': 'tdx_history_trans',
      'symbols': ['600519'],
      'date': '20260519',
    },
  ),
  _ProbeSpec(
    action: 'tdx_top_board',
    provider: 'tdx',
    input: {'action': 'tdx_top_board'},
  ),
  _ProbeSpec(
    action: 'tdx_quotes_list',
    provider: 'tdx',
    input: {'action': 'tdx_quotes_list', 'market': 1, 'start': 0, 'count': 10},
  ),
  _ProbeSpec(
    action: 'tdx_index_bars',
    provider: 'tdx',
    input: {
      'action': 'tdx_index_bars',
      'symbols': ['000001'],
      'count': 10,
    },
  ),
  _ProbeSpec(
    action: 'tdx_company_info',
    provider: 'tdx',
    input: {
      'action': 'tdx_company_info',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'tdx_block',
    provider: 'tdx',
    input: {
      'action': 'tdx_block',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'ex_categories',
    provider: 'tdx',
    input: {'action': 'ex_categories'},
  ),
  _ProbeSpec(
    action: 'ex_count',
    provider: 'tdx',
    input: {'action': 'ex_count'},
  ),
  _ProbeSpec(
    action: 'ex_sampling',
    provider: 'tdx',
    input: {
      'action': 'ex_sampling',
      'params': {'category': 30, 'code': 'RBL8'},
    },
  ),
  _ProbeSpec(
    action: 'ex_table',
    provider: 'tdx',
    input: {'action': 'ex_table'},
  ),
  _ProbeSpec(
    action: 'ex_kline',
    provider: 'tdx',
    input: {
      'action': 'ex_kline',
      'params': {'category': 30, 'code': 'RBL8', 'count': 10},
    },
  ),
  _ProbeSpec(
    action: 'ex_quote',
    provider: 'tdx',
    input: {
      'action': 'ex_quote',
      'params': {'category': 30, 'code': 'RBL8'},
    },
  ),
  _ProbeSpec(
    action: 'ex_list',
    provider: 'tdx',
    input: {
      'action': 'ex_list',
      'params': {'start': 0, 'count': 10},
    },
  ),
  _ProbeSpec(
    action: 'tushare',
    provider: 'tushare',
    credential: 'tushare',
    input: {
      'action': 'tushare',
      'api_name': 'trade_cal',
      'params': {
        'exchange': 'SSE',
        'start_date': '20260601',
        'end_date': '20260630',
      },
      'fields': 'exchange,cal_date,is_open,pretrade_date',
    },
  ),
];

const _readbackSpecs = [
  _ProbeSpec(
    action: 'help',
    provider: 'local-readback',
    input: {'action': 'help'},
  ),
  _ProbeSpec(
    action: 'sources',
    provider: 'local-readback',
    input: {'action': 'sources'},
  ),
  _ProbeSpec(
    action: 'coverage',
    provider: 'local-readback',
    input: {
      'action': 'coverage',
      'symbols': ['600519'],
    },
  ),
  _ProbeSpec(
    action: 'reusable_summary',
    provider: 'local-readback',
    input: {'action': 'reusable_summary'},
  ),
  _ProbeSpec(
    action: 'query_quote',
    provider: 'local-readback',
    input: {
      'action': 'query_quote',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_kline',
    provider: 'local-readback',
    input: {
      'action': 'query_kline',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_fundamental',
    provider: 'local-readback',
    input: {
      'action': 'query_fundamental',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_money_flow',
    provider: 'local-readback',
    input: {
      'action': 'query_money_flow',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_fund_nav',
    provider: 'local-readback',
    input: {
      'action': 'query_fund_nav',
      'symbols': ['110022'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_fund_list',
    provider: 'local-readback',
    input: {'action': 'query_fund_list', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_trade_calendar',
    provider: 'local-readback',
    input: {'action': 'query_trade_calendar', 'market': 'SSE', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_stock_list',
    provider: 'local-readback',
    input: {'action': 'query_stock_list', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_industry_map',
    provider: 'local-readback',
    input: {'action': 'query_industry_map', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_sector',
    provider: 'local-readback',
    input: {'action': 'query_sector', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_chip',
    provider: 'local-readback',
    input: {
      'action': 'query_chip',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_ex_categories',
    provider: 'local-readback',
    input: {'action': 'query_ex_categories', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_tdx_count',
    provider: 'local-readback',
    input: {'action': 'query_tdx_count', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_tdx_sampling',
    provider: 'local-readback',
    input: {
      'action': 'query_tdx_sampling',
      'symbols': ['000001'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_ex_table',
    provider: 'local-readback',
    input: {'action': 'query_ex_table', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_tick_chart',
    provider: 'local-readback',
    input: {
      'action': 'query_tick_chart',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_transactions',
    provider: 'local-readback',
    input: {
      'action': 'query_transactions',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_volume_profile',
    provider: 'local-readback',
    input: {
      'action': 'query_volume_profile',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_xdxr',
    provider: 'local-readback',
    input: {
      'action': 'query_xdxr',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_auction',
    provider: 'local-readback',
    input: {
      'action': 'query_auction',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_momentum',
    provider: 'local-readback',
    input: {
      'action': 'query_momentum',
      'symbols': ['000001'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_top_board',
    provider: 'local-readback',
    input: {'action': 'query_top_board', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_tdx_block_member',
    provider: 'local-readback',
    input: {'action': 'query_tdx_block_member', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_company_info',
    provider: 'local-readback',
    input: {
      'action': 'query_company_info',
      'symbols': ['600519'],
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_hot_rank',
    provider: 'local-readback',
    input: {'action': 'query_hot_rank', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_dragon_tiger',
    provider: 'local-readback',
    input: {'action': 'query_dragon_tiger', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_limit_pool',
    provider: 'local-readback',
    input: {'action': 'query_limit_pool', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_northbound',
    provider: 'local-readback',
    input: {'action': 'query_northbound', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_unusual',
    provider: 'local-readback',
    input: {'action': 'query_unusual', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_flow_rank',
    provider: 'local-readback',
    input: {'action': 'query_flow_rank', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_wind_document',
    provider: 'local-readback',
    input: {'action': 'query_wind_document', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_wind_economic',
    provider: 'local-readback',
    input: {'action': 'query_wind_economic', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_wind_analytics',
    provider: 'local-readback',
    input: {'action': 'query_wind_analytics', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_yfinance',
    provider: 'local-readback',
    input: {
      'action': 'query_yfinance',
      'symbols': ['AAPL'],
      'dataset': 'profile',
      'limit': 5,
    },
  ),
  _ProbeSpec(
    action: 'query_raw_payload',
    provider: 'local-readback',
    input: {'action': 'query_raw_payload', 'limit': 5},
  ),
  _ProbeSpec(
    action: 'query_api_calls',
    provider: 'local-readback',
    input: {'action': 'query_api_calls', 'minutes': 60, 'limit': 5},
  ),
];
