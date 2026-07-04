import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../shared/api_config.dart';
import '../../data_fetcher/api_stats.dart';
import '../../data_fetcher/models.dart';
import '../../data_fetcher/normalizers.dart';
import '../../data_fetcher/reusable_data_store.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

const _windServers = {
  'stock_data': 'https://mcp.wind.com.cn/vserver_stock_data/mcp/',
  'global_stock_data': 'https://mcp.wind.com.cn/vserver_global_stock_data/mcp/',
  'fund_data': 'https://mcp.wind.com.cn/vserver_fund_data/mcp/',
  'index_data': 'https://mcp.wind.com.cn/vserver_index_data/mcp/',
  'bond_data': 'https://mcp.wind.com.cn/vserver_bond_data/mcp/',
  'financial_docs': 'https://mcp.wind.com.cn/vserver_financial_docs/mcp/',
  'economic_data': 'https://mcp.wind.com.cn/vserver_economic_data/mcp/',
  'analytics_data': 'https://mcp.wind.com.cn/vserver_analytics_data/mcp/',
};

const _windToolsByServer = {
  'stock_data': [
    'get_stock_price_indicators',
    'get_stock_kline',
    'get_stock_quote',
    'get_stock_basicinfo',
    'get_stock_fundamentals',
    'get_stock_equity_holders',
    'get_stock_events',
    'get_stock_technicals',
    'get_risk_metrics',
  ],
  'global_stock_data': [
    'get_global_stock_price_indicators',
    'get_global_stock_kline',
    'get_global_stock_quote',
    'get_global_stock_basicinfo',
    'get_global_stock_fundamentals',
    'get_global_stock_equity_holders',
    'get_global_stock_events',
    'get_global_stock_technicals',
    'get_global_stock_risk_metrics',
  ],
  'fund_data': [
    'get_fund_price_indicators',
    'get_fund_kline',
    'get_fund_quote',
    'get_fund_info',
    'get_fund_financials',
    'get_fund_holdings',
    'get_fund_performance',
    'get_fund_holders',
    'get_fund_company_info',
  ],
  'index_data': [
    'get_index_price_indicators',
    'get_index_kline',
    'get_index_quote',
    'get_index_basicinfo',
    'get_index_fundamentals',
    'get_index_technicals',
  ],
  'bond_data': [
    'get_bond_basicinfo',
    'get_bond_issuer_info',
    'get_bond_market_data',
    'get_bond_financial_data',
  ],
  'financial_docs': ['get_company_announcements', 'get_financial_news'],
  'economic_data': ['get_economic_data'],
  'analytics_data': ['get_financial_data'],
};

class WindMcpTool extends Tool {
  final ApiConfigStore? apiConfig;
  final String basePath;
  final http.Client _client;

  WindMcpTool({required this.basePath, this.apiConfig, http.Client? client})
    : _client = client ?? http.Client();

  @override
  String get name => 'WindMcp';

  @override
  String get description =>
      'Call Wind AIFinMarket MCP data tools over direct HTTPS. Requires WIND_API_KEY in Settings.';

  @override
  String get prompt =>
      '''Call Wind AIFinMarket financial data tools through direct HTTPS JSON-RPC.

Use action="help" to list server groups and tool names. Use action="call" with server, tool, and arguments.
Use official Wind parameter names: market data tools use windcode, price indicator tools also require indexes, NL tools use question, document tools use query, and economic_data uses metricIdsStr.
The tool reads WIND_API_KEY from Settings and records Wind same-day quota/balance errors so later calls avoid retrying an exhausted daily quota.
Prefer targeted calls and reuse recent results before making broad or repeated Wind requests.''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'call', 'usage'],
        'description':
            'help lists tools, usage shows local daily usage, call invokes Wind.',
      },
      'server': {
        'type': 'string',
        'enum': _windServers.keys.toList(),
        'description': 'Wind MCP server group.',
      },
      'tool': {
        'type': 'string',
        'description': 'Wind tool name, e.g. get_stock_quote.',
      },
      'arguments': {
        'type': 'object',
        'description': 'Arguments passed to the Wind tool.',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => true;

  @override
  bool get canParallel => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    if (action != 'call') return null;
    final server = input['server'] as String?;
    final tool = input['tool'] as String?;
    if (server == null || !_windServers.containsKey(server)) {
      return 'INVALID_SERVER: server must be one of: ${_windServers.keys.join(', ')}. Use WindMcp(action: "help") to inspect server groups.';
    }
    if (tool == null || tool.isEmpty) {
      return 'MISSING_TOOL: tool is required for action=call. Use WindMcp(action: "help") to choose a tool for server "$server".';
    }
    if (!_windToolsByServer[server]!.contains(tool)) {
      return 'INVALID_TOOL: "$tool" is not listed for server "$server". Use WindMcp(action: "help") and retry with one of: ${_windToolsByServer[server]!.join(', ')}.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    try {
      if (action == 'help') {
        return ToolResult(toolUseId: toolUseId, content: _help());
      }
      if (action == 'usage') {
        return ToolResult(
          toolUseId: toolUseId,
          content: jsonEncode(_readUsage()),
        );
      }
      if (action != 'call') {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'INVALID_ACTION: "$action" is not supported. Use action="help" to discover tools, action="usage" to check daily quota, or action="call" to invoke Wind.',
          isError: true,
        );
      }

      final apiKey = apiConfig?.get('WIND_API_KEY')?.trim() ?? '';
      if (apiKey.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'KEY_MISSING: set WIND_API_KEY in Settings > Data Sources before using WindMcp. Do not retry Wind calls until the key is configured.',
          isError: true,
        );
      }

      final usage = _readUsage();
      if (usage['exhausted'] == true) {
        final code = usage['exhaustedCode'] as String? ?? 'RATE_LIMIT_DAILY';
        final message =
            usage['exhaustedMessage'] as String? ??
            'Wind reported daily quota exhaustion or insufficient balance.';
        return ToolResult(
          toolUseId: toolUseId,
          content:
              '$code: stored Wind daily limitation for quota date ${usage['date']} (reset offset ${usage['resetUtcOffset']}). $message Stop Wind calls for this quota day. It is appropriate to try Wind again after the next quota day starts, or after the Wind account/key is updated. Until then, fall back to cache, EastMoney, TDX, Yahoo, or DataStore.',
          isError: true,
        );
      }

      final server = input['server'] as String;
      final tool = input['tool'] as String;
      final args =
          (input['arguments'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final result = await _callWind(apiKey, server, tool, args);
      _incrementUsage();
      if (result.isError && _isCreditExhausted(result.content)) {
        _markUsageExhausted(result.content);
      }
      if (!result.isError) {
        _persistKnownWindResult(server, tool, args, result.content);
      }
      return ToolResult(
        toolUseId: toolUseId,
        content: result.content,
        isError: result.isError,
      );
    } catch (err) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'NETWORK_ERROR: Wind HTTPS request failed before a usable MCP response was parsed. Details: $err. Retry only if this looks transient; otherwise fall back to non-Wind sources.',
        isError: true,
      );
    }
  }

  Future<_WindResult> _callWind(
    String apiKey,
    String server,
    String tool,
    Map<String, dynamic> args,
  ) async {
    final headers = {
      'Authorization': 'Bearer $apiKey',
      'Accept': 'application/json, text/event-stream',
      'Content-Type': 'application/json',
    };
    final endpoint = Uri.parse(_windServers[server]!);
    final initResp = await _postJson(
      endpoint,
      headers,
      {
        'jsonrpc': '2.0',
        'id': DateTime.now().millisecondsSinceEpoch,
        'method': 'initialize',
        'params': {
          'protocolVersion': '2025-03-26',
          'capabilities': <String, dynamic>{},
          'clientInfo': {'name': 'cc-mobile-finagent', 'version': '1.0.0'},
        },
      },
      const Duration(seconds: 30),
      '$server.initialize',
    );
    final initErr = _httpError(initResp);
    if (initErr != null) return _WindResult(initErr, true);

    final resp = await _postJson(
      endpoint,
      headers,
      {
        'jsonrpc': '2.0',
        'id': DateTime.now().millisecondsSinceEpoch + 1,
        'method': 'tools/call',
        'params': {
          'name': tool,
          'arguments': args,
          '_meta': {'clientVersion': '1.6.1'},
        },
      },
      const Duration(seconds: 60),
      '$server.$tool',
    );
    final httpErr = _httpError(resp);
    if (httpErr != null) return _WindResult(httpErr, true);
    return _parseResponse(resp.body);
  }

  Future<http.Response> _postJson(
    Uri endpoint,
    Map<String, String> headers,
    Map<String, dynamic> payload,
    Duration timeout,
    String label,
  ) async {
    final start = DateTime.now();
    try {
      final resp = await _client
          .post(endpoint, headers: headers, body: jsonEncode(payload))
          .timeout(timeout);
      ApiStats.instance.record(
        source: 'wind',
        method: 'POST',
        url: '${endpoint.toString()} ($label)',
        statusCode: resp.statusCode,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        success: resp.statusCode >= 200 && resp.statusCode < 300,
        error: resp.statusCode >= 200 && resp.statusCode < 300
            ? null
            : resp.body,
        responseSummary: resp.body,
      );
      return resp;
    } catch (err) {
      ApiStats.instance.record(
        source: 'wind',
        method: 'POST',
        url: '${endpoint.toString()} ($label)',
        statusCode: 0,
        durationMs: DateTime.now().difference(start).inMilliseconds,
        success: false,
        error: err.toString(),
      );
      rethrow;
    }
  }

  String? _httpError(http.Response resp) {
    if (resp.statusCode >= 200 && resp.statusCode < 300) return null;
    final code = switch (resp.statusCode) {
      401 => 'KEY_INVALID',
      403 => 'KEY_FORBIDDEN_SERVER',
      429 => 'RATE_LIMIT_QPS',
      >= 500 => 'SERVER_5XX',
      _ => 'HTTP_${resp.statusCode}',
    };
    final guidance = switch (resp.statusCode) {
      401 => 'Check WIND_API_KEY and do not retry until corrected.',
      403 =>
        'The key may not have access to this Wind server group; try a different server or update account permissions.',
      429 =>
        'Slow down requests; if this persists, stop broad collection and retry later.',
      >= 500 =>
        'Wind server error; retry once later or fall back to another data source.',
      _ => 'Inspect status/body and retry only with corrected input.',
    };
    return '$code: Wind HTTP ${resp.statusCode}. $guidance Body: ${resp.body}';
  }

  _WindResult _parseResponse(String body) {
    final payload = jsonDecode(_extractJson(body)) as Map<String, dynamic>;
    if (payload['error'] != null) {
      return _WindResult(
        'MCP_PROTOCOL_ERROR: Wind returned a JSON-RPC error. Check server/tool/arguments and retry with corrected input. Error: ${jsonEncode(payload['error'])}',
        true,
      );
    }
    final result = payload['result'];
    if (result is! Map<String, dynamic>) {
      return _WindResult(jsonEncode(payload), false);
    }
    if (result['isError'] == true) {
      return _WindResult(_contentText(result), true);
    }
    final text = _contentText(result);
    final innerError = _innerError(text);
    if (innerError != null) return _WindResult(innerError, true);
    return _WindResult(text.isEmpty ? jsonEncode(result) : text, false);
  }

  String _extractJson(String body) {
    final dataLines = body
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trim())
        .where((line) => line.isNotEmpty && line != '[DONE]')
        .toList();
    return dataLines.isEmpty ? body : dataLines.last;
  }

  String _contentText(Map<String, dynamic> result) {
    final content = result['content'];
    if (content is List && content.isNotEmpty) {
      final first = content.first;
      if (first is Map && first['text'] != null) {
        return first['text'].toString();
      }
    }
    return jsonEncode(result);
  }

  String? _innerError(String text) {
    try {
      final parsed = jsonDecode(text);
      if (parsed is Map<String, dynamic>) {
        final errCode = parsed['mcp_tool_error_code'];
        if (errCode != null && errCode != 0) {
          return 'WIND_TOOL_ERROR: Wind tool returned mcp_tool_error_code=$errCode. Check arguments against Wind help/docs before retrying. Body: $text';
        }
        if (parsed['error'] != null) {
          return 'WIND_TOOL_ERROR: Wind tool returned an application error. Check arguments or fall back if this is quota/access related. Error: ${jsonEncode(parsed['error'])}';
        }
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _readUsage() {
    final offset = _usageUtcOffset();
    final today = _usageDate(offset);
    final file = File('$basePath/memory/wind_usage.json');
    try {
      if (file.existsSync()) {
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        if (data['date'] == today) {
          return {
            'date': today,
            'resetUtcOffset': offset,
            'count': data['count'] as int? ?? 0,
            'exhausted': data['exhausted'] == true,
            if (data['exhaustedCode'] != null)
              'exhaustedCode': data['exhaustedCode'],
            if (data['exhaustedMessage'] != null)
              'exhaustedMessage': data['exhaustedMessage'],
            if (data['exhaustedAt'] != null) 'exhaustedAt': data['exhaustedAt'],
          };
        }
      }
    } catch (_) {}
    return {
      'date': today,
      'resetUtcOffset': offset,
      'count': 0,
      'exhausted': false,
    };
  }

  void _incrementUsage() {
    final usage = _readUsage();
    usage['count'] = (usage['count'] as int) + 1;
    _writeUsage(usage);
  }

  void _markUsageExhausted(String message) {
    final usage = _readUsage();
    usage['exhausted'] = true;
    usage['exhaustedCode'] = _quotaErrorCode(message);
    usage['exhaustedMessage'] = message;
    usage['exhaustedAt'] = DateTime.now().toUtc().toIso8601String();
    _writeUsage(usage);
  }

  void _writeUsage(Map<String, dynamic> usage) {
    final file = File('$basePath/memory/wind_usage.json');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(usage));
  }

  bool _isCreditExhausted(String content) =>
      content.contains('RATE_LIMIT_DAILY') ||
      content.contains('BALANCE_INSUFFICIENT');

  String _quotaErrorCode(String content) {
    if (content.contains('BALANCE_INSUFFICIENT')) return 'BALANCE_INSUFFICIENT';
    return 'RATE_LIMIT_DAILY';
  }

  String _usageUtcOffset() {
    final raw = apiConfig?.get('WIND_DAILY_RESET_UTC_OFFSET')?.trim();
    final parsed = _parseUtcOffset(raw == null || raw.isEmpty ? '+08:00' : raw);
    return parsed?.$1 ?? '+08:00';
  }

  String _usageDate(String normalizedOffset) {
    final offset =
        _parseUtcOffset(normalizedOffset)?.$2 ?? const Duration(hours: 8);
    return DateTime.now()
        .toUtc()
        .add(offset)
        .toIso8601String()
        .substring(0, 10);
  }

  (String, Duration)? _parseUtcOffset(String raw) {
    final match = RegExp(r'^([+-])(\d{1,2})(?::?(\d{2}))?$').firstMatch(raw);
    if (match == null) return null;
    final hours = int.tryParse(match.group(2) ?? '');
    final minutes = int.tryParse(match.group(3) ?? '0');
    if (hours == null || minutes == null || hours > 14 || minutes > 59) {
      return null;
    }
    final sign = match.group(1) == '-' ? -1 : 1;
    final normalized =
        '${sign < 0 ? '-' : '+'}${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}';
    return (normalized, Duration(minutes: sign * (hours * 60 + minutes)));
  }

  String _help() {
    final lines = <String>[
      'WindMcp uses direct HTTPS JSON-RPC to Wind AIFinMarket MCP endpoints.',
      '',
      'Progressive use:',
      '1. action="usage" before broad collection to check same-day Wind quota status.',
      '2. action="help" to choose a server/tool.',
      '3. action="call" with server, tool, and targeted arguments.',
      '',
      'Example:',
      '{"action":"call","server":"stock_data","tool":"get_stock_price_indicators","arguments":{"windcode":"600519.SH","indexes":"中文简称,最新成交价,涨跌幅"}}',
      '',
      'Required config: WIND_API_KEY in Settings > Data Sources.',
      'Usage: memory/wind_usage.json stores local call count for visibility and same-day Wind quota/balance errors. It is not official Wind credit accounting. Daily rollover uses WIND_DAILY_RESET_UTC_OFFSET internally, default +08:00 because the official skill only says next-day 00:00 refresh.',
      'Parameter rules: quote/K-line/price tools use windcode; price tools require Chinese indexes from the bundled indicators reference; NL tools use question; financial_docs tools use query; economic_data uses metricIdsStr.',
      'Failures: stop Wind calls on RATE_LIMIT_DAILY or BALANCE_INSUFFICIENT; fall back to cache, EastMoney, TDX, Yahoo, or DataStore.',
      '',
      'Servers and tools:',
    ];
    for (final entry in _windToolsByServer.entries) {
      lines.add('- ${entry.key}: ${entry.value.join(', ')}');
    }
    return lines.join('\n');
  }

  void _persistKnownWindResult(
    String server,
    String tool,
    Map<String, dynamic> args,
    String content,
  ) {
    final code = args['windcode']?.toString();
    final store = ReusableDataStore(basePath);
    if (server == 'financial_docs') {
      store.saveWindDocuments(
        tryNormalizeWindDocumentPayload(
          content,
          tool: tool,
          query: args['query']?.toString(),
        ),
      );
      if (tool == 'get_financial_news') {
        final financeNewsRows = tryNormalizeWindFinanceNewsPayload(
          content,
          query: args['query']?.toString(),
        );
        if (financeNewsRows.isNotEmpty) {
          store.saveFinanceNews(financeNewsRows);
        }
        final rows = tryNormalizeWindGlobalNewsPayload(
          content,
          code: code ?? '',
        );
        if (rows.isNotEmpty) {
          store.saveYfinanceNews(rows);
        }
      }
      return;
    }
    if (server == 'economic_data') {
      store.saveWindEconomicSeries(
        tryNormalizeWindEconomicPayload(
          content,
          metricQuery: args['metricIdsStr']?.toString() ?? '',
        ),
      );
      return;
    }
    if (server == 'analytics_data') {
      store.saveWindAnalyticsResults(
        tryNormalizeWindAnalyticsPayload(
          content,
          question: args['question']?.toString() ?? '',
        ),
      );
      return;
    }
    if (!_isPersistableMarketServer(server)) return;
    if (server == 'fund_data' && tool == 'get_fund_kline') {
      final rows = tryNormalizeWindFundNavPayload(content, fundCode: code);
      if (rows.isNotEmpty) {
        store.saveFundNav(rows);
      }
      return;
    }
    if (server == 'fund_data' && tool == 'get_fund_info') {
      final fundRows = tryNormalizeWindFundListPayload(content, fundCode: code);
      if (fundRows.isNotEmpty) {
        store.saveFundList(fundRows);
      }
      final managerRows = tryNormalizeWindFundManagerPayload(
        content,
        fundCode: code,
      );
      if (managerRows.isNotEmpty) {
        store.saveFundManagerRows(managerRows, source: 'Wind');
      }
    }
    if (_isWindKlineTool(tool) && _isDailyKlineArgs(args)) {
      final result = tryNormalizeWindKlinePayload(content, code: code);
      if (result == null) return;
      store.saveKline(
        result.code,
        result.bars,
        source: 'Wind',
        adjust: _windAdjust(args),
      );
      return;
    }
    if (_isWindQuoteTool(tool)) {
      final quote = tryNormalizeWindQuotePayload(content, code: code);
      if (quote == null) return;
      store.saveQuoteSnapshots([quote], 'Wind');
      final stockRow = _windStockListRow(server, args, quote);
      if (stockRow != null) {
        store.saveStockListRows([stockRow], source: 'Wind');
      }
      return;
    }
    if (_isWindFundamentalTool(tool)) {
      final rows = tryNormalizeWindFundamentalPayload(content, code: code);
      if (rows.isNotEmpty) {
        store.saveFundamentalRows(rows, source: 'Wind');
      }
      if (tool == 'get_global_stock_fundamentals') {
        final statementRows = tryNormalizeWindGlobalStatementPayload(
          content,
          symbol: code,
        );
        if (statementRows.isNotEmpty) {
          store.saveYfinanceStatementItems(statementRows);
        }
        final recommendationRows = tryNormalizeWindGlobalRecommendationPayload(
          content,
          symbol: code,
        );
        if (recommendationRows.isNotEmpty) {
          store.saveYfinanceRecommendations(recommendationRows);
        }
      }
      return;
    }
    if (tool == 'get_global_stock_equity_holders') {
      final rows = tryNormalizeWindGlobalHolderPayload(content, symbol: code);
      if (rows.isNotEmpty) {
        store.saveYfinanceHolders(rows);
      }
      return;
    }
    if (tool == 'get_stock_equity_holders') {
      final rows = tryNormalizeWindStockShareholderPayload(content, code: code);
      if (rows.isNotEmpty) {
        store.saveStockShareholders(rows, source: 'Wind');
      }
      return;
    }
    if (tool == 'get_global_stock_basicinfo') {
      final rows = tryNormalizeWindGlobalProfilePayload(content, symbol: code);
      if (rows.isNotEmpty) {
        store.saveYfinanceProfileFields(rows);
      }
    }
    if (tool == 'get_stock_technicals') {
      final result = tryNormalizeWindMoneyFlowPayload(content, code: code);
      if (result != null && result.rows.isNotEmpty) {
        store.saveMoneyFlowRows(result.code, result.rows, source: 'Wind');
      }
    }
    if (tool == 'get_stock_events') {
      final result = tryNormalizeWindXdxrPayload(content, code: code);
      if (result != null && result.rows.isNotEmpty) {
        store.saveXdxrEvents(result.code, result.rows, source: 'Wind');
      }
    }
    if (tool == 'get_global_stock_events') {
      final rows = tryNormalizeWindCorporateActionPayload(
        content,
        symbol: code,
      );
      if (rows.isNotEmpty) {
        store.saveYfinanceCorporateActions(rows);
      }
    }
    if (tool == 'get_index_technicals') {
      final result = tryNormalizeWindIndexMomentumPayload(content, code: code);
      if (result != null && result.values.isNotEmpty) {
        store.saveIndexMomentum(
          result.code,
          {'momentum': result.values},
          source: 'Wind',
          tradeDate: result.tradeDate,
        );
      }
      return;
    }
    if (tool == 'get_fund_holdings') {
      final rows = tryNormalizeWindFundHoldingPayload(content, fundCode: code);
      if (rows.isEmpty) return;
      store.saveFundHolding(rows, source: 'Wind');
      return;
    }
    if (tool == 'get_fund_performance') {
      final rows = tryNormalizeWindFundPerformancePayload(
        content,
        fundCode: code,
      );
      if (rows.isNotEmpty) {
        store.saveFundPerformanceMetrics(rows, source: 'wind');
      }
      return;
    }
    if (_isWindCompanyInfoTool(tool)) {
      final normalized = tryNormalizeWindCompanyInfoPayload(
        content,
        code: code,
        infoType: tool,
      );
      if (normalized == null) return;
      final rows =
          (normalized.payload['rows'] as List?)
              ?.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList() ??
          const <Map<String, dynamic>>[];
      final stockRows = <Map<String, dynamic>>[];
      final categories =
          (normalized.payload['categories'] as List?)
              ?.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList() ??
          const <Map<String, dynamic>>[];
      for (var i = 0; i < rows.length; i++) {
        final title =
            (categories.length > i ? '${categories[i]['title'] ?? ''}' : '')
                .trim();
        final row = rows[i];
        store.saveCompanyInfo(
          normalized.code,
          title.isEmpty ? tool : '$tool:$title',
          {
            'title': title.isEmpty ? tool : title,
            'first_content': _previewWindCompanyInfoRow(row),
            'entry': row,
          },
          source: 'Wind',
        );
        final name = _extractWindCompanyInfoName(row);
        if (name != null) {
          final market = _windMarketFromCode(
            args['windcode']?.toString(),
            normalized.code,
            server: server,
          );
          if (market != null) {
            stockRows.add({
              'code': normalized.code,
              'name': name,
              'market': market,
              'stock_type': _windStockType(server),
            });
          }
        }
      }
      store.saveCompanyInfo(
        normalized.code,
        tool,
        normalized.payload,
        source: 'Wind',
      );

      if (_isWindIdentityInfoTool(tool) && stockRows.isNotEmpty) {
        store.saveStockListRows(stockRows, source: 'Wind');
      }
    }
  }

  String? _extractWindCompanyInfoName(Map<String, dynamic> row) {
    for (final key in const [
      '基金名称',
      '债券简称',
      '指数简称',
      '证券简称',
      '中文简称',
      '名称',
      'name',
    ]) {
      final value = row[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value != null && value.toString().trim().isNotEmpty)
        return value.toString().trim();
    }
    return null;
  }

  bool _isPersistableMarketServer(String server) =>
      server == 'stock_data' ||
      server == 'global_stock_data' ||
      server == 'fund_data' ||
      server == 'index_data' ||
      server == 'bond_data';

  bool _isWindQuoteTool(String tool) =>
      tool.endsWith('_quote') || tool.endsWith('_price_indicators');

  bool _isWindKlineTool(String tool) => tool.endsWith('_kline');

  bool _isWindFundamentalTool(String tool) =>
      tool.endsWith('_fundamentals') ||
      tool == 'get_fund_financials' ||
      tool == 'get_bond_financial_data';

  bool _isWindCompanyInfoTool(String tool) => const {
    'get_stock_basicinfo',
    'get_stock_equity_holders',
    'get_stock_events',
    'get_stock_technicals',
    'get_risk_metrics',
    'get_global_stock_basicinfo',
    'get_global_stock_equity_holders',
    'get_global_stock_events',
    'get_global_stock_technicals',
    'get_global_stock_risk_metrics',
    'get_fund_info',
    'get_fund_holdings',
    'get_fund_performance',
    'get_fund_holders',
    'get_fund_company_info',
    'get_index_basicinfo',
    'get_index_technicals',
    'get_bond_basicinfo',
    'get_bond_issuer_info',
    'get_bond_market_data',
  }.contains(tool);

  bool _isWindIdentityInfoTool(String tool) => const {
    'get_stock_basicinfo',
    'get_global_stock_basicinfo',
    'get_fund_info',
    'get_fund_company_info',
    'get_index_basicinfo',
    'get_bond_basicinfo',
    'get_bond_issuer_info',
  }.contains(tool);

  bool _isDailyKlineArgs(Map<String, dynamic> args) {
    final period = args['period']?.toString().trim();
    return period == null || period.isEmpty || period == '10';
  }

  String _windAdjust(Map<String, dynamic> args) {
    final aftype = args['aftype']?.toString().trim();
    return aftype == '1' ? 'hfq' : 'qfq';
  }

  Map<String, dynamic>? _windStockListRow(
    String server,
    Map<String, dynamic> args,
    StockQuote quote,
  ) {
    final market = _windMarketFromCode(
      args['windcode']?.toString(),
      quote.code,
      server: server,
    );
    if (market == null || market.isEmpty) return null;
    return {
      'code': quote.code,
      'name': quote.name,
      'market': market,
      'stock_type': _windStockType(server),
    };
  }

  String _windStockType(String server) {
    switch (server) {
      case 'fund_data':
        return 'fund';
      case 'index_data':
        return 'index';
      case 'bond_data':
        return 'bond';
      default:
        return 'stock';
    }
  }

  String? _windMarketFromCode(
    String? windcode,
    String fallbackCode, {
    String? server,
  }) {
    final raw = (windcode ?? fallbackCode).trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('.')) {
      if (server == 'bond_data') return 'IB';
      if (server == 'fund_data') return 'OF';
      if (server == 'index_data') return 'SH';
      return null;
    }
    final suffix = raw.contains('.')
        ? raw.split('.').last.trim().toUpperCase()
        : '';
    if (suffix.isEmpty) return null;
    switch (suffix) {
      case 'O':
      case 'N':
      case 'KQ':
        return 'US';
      default:
        return suffix;
    }
  }

  String _previewWindCompanyInfoRow(Map<String, dynamic> row) {
    final pairs = <String>[];
    row.forEach((key, value) {
      if (value == null || '$value'.trim().isEmpty) return;
      pairs.add('$key: $value');
    });
    return pairs.isEmpty ? jsonEncode(row) : pairs.join('\n');
  }
}

class _WindResult {
  final String content;
  final bool isError;

  _WindResult(this.content, this.isError);
}
