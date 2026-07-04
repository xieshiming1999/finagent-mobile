import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../message.dart';
import '../../monitor.dart';
import '../../monitor_scheduler.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class MonitorCreateTool extends Tool {
  final MonitorStore store;
  final MonitorScheduler scheduler;

  MonitorCreateTool({required this.store, required this.scheduler});

  @override
  String get name => 'MonitorCreate';

  @override
  String get description =>
      'Create a monitor that periodically runs a JS script to fetch and display data.';

  @override
  String get prompt =>
      '''Create a code-driven monitor that runs periodically without LLM involvement.

## Preferred: Use templates

Use the `template` + `params` parameters instead of writing raw `script`.
Load the "monitor-templates" skill to see available templates and their parameters.

Templates: price_alert, change_alert, fund_nav, volume_surge, watchlist, strategy_signal, fund_rule_monitor, portfolio_rebalance_monitor.

## Bridge API (available in script)

See AGENTS.md `## Bridge API` for the full reference. Key methods for monitors:

### HTTP (sync, pre-fetched)
- `Bridge.fetch(url, params?, method?)` / `Bridge.get(url)` / `Bridge.post(url, body)` — HTTP requests
- `callService(path, params)` — backward-compatible alias for Bridge.fetch

### File
- `Bridge.readFile(path)` / `Bridge.writeFile(path, content)` / `Bridge.listDir(path?)`
- `Bridge.fileExists(path)` / `Bridge.fileStat(path)`

### Data / Stats
- `Bridge.parseCSV(text, sep?)`, `Bridge.toCSV(arr, sep?)`, `Bridge.base64Encode/Decode(text)`
- `Bridge.sum(arr)`, `Bridge.avg(arr)`, `Bridge.median(arr)`, `Bridge.groupBy(arr, key)`, `Bridge.sortBy(arr, key, desc?)`

### Agent Communication
- `Bridge.notify(message)` — display-only notification (no agent processing)
- `Bridge.alert(message)` — urgent notification with haptic feedback
- `Bridge.sendToAgent(message, data)` — send message to event agent (triggers thinking)
- `Bridge.getConfig(key)` — read API key from user config

### Monitor-only
- `Bridge.ws(url, {onMessage})` — register WebSocket for push-based monitoring
- `Bridge.sendToMonitor(monitorId, channel, data)` — push data to another monitor
- `Bridge.onPush(channel, handler)` — receive push data from other monitors/dashboards
- `state` — object persisted between executions (e.g., price history for charts)
- `console.log(...)` — debug logging

## Return value → display type mapping

Choose `display` to match the return shape:

- **value_card** (default): `{ value: 1795, label: "茅台", change: -2.3, unit: "¥" }`
  Big number with change percentage. `unit` prefixes the value. `change` shown as ±X.XX%.
- **mini_chart**: `{ series: [1780, 1790, 1795], label: "趋势", value: 1795 }`
  Sparkline chart. Use `state.history` to accumulate data points across runs:
  `if (!state.history) state.history = []; state.history.push(price); if (state.history.length > 30) state.history.shift();`
  Return `{ series: state.history, value: price, label: "..." }`.
- **status_row**: `{ items: [{label: "涨", value: 3}, {label: "跌", value: 5}, {label: "平", value: 1}] }`
  Key-value pairs. Max 3 shown in card thumbnail, all shown in detail view.
- **text**: `{ text: "市场偏多" }`
  Single text string, auto-sized to fit card. Good for qualitative status.
- **carousel**: `{ items: ["沪深涨3%", "创业板跌1%", "北向资金流入"] }`
  Rotating text items, one at a time with 3s interval. Good for multi-item summaries.
- **watchlist**: `{ rows: [{name, code, price, change, signal}], title }`
  Compact multi-row table with color-coded changes and signal icons.

## Important

- HTTP calls are synchronous (pre-fetched by Dart). Only literal path/params are supported.
- The script is test-run immediately on creation; if it fails, creation is rejected.
- Optional `condition` is a JS expression evaluated against `result` and `state`.
  When true, an alert notification is sent to this agent.
- Bridge.sendToAgent sends to the event agent for this tab.
- Bridge.ws is Monitor-only — Script and WebView do not support WebSocket registration.''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'name': {'type': 'string', 'description': 'Display name for the monitor'},
      'script': {
        'type': 'string',
        'description':
            'JavaScript code (use only if no template fits). Use callService(path, params) for data.',
      },
      'template': {
        'type': 'string',
        'enum': [
          'price_alert',
          'change_alert',
          'fund_nav',
          'volume_surge',
          'watchlist',
          'strategy_signal',
          'fund_rule_monitor',
          'portfolio_rebalance_monitor',
        ],
        'description': 'Template name. Preferred over raw script.',
      },
      'params': {
        'type': 'object',
        'description':
            'Template parameters (e.g. {ts_code, name, upper, lower})',
      },
      'interval': {
        'type': 'string',
        'description':
            'Polling interval: "1m", "5m", "30m", "1h" (default "5m"). Not needed if streamUrl is set.',
      },
      'streamUrl': {
        'type': 'string',
        'description':
            'WebSocket URL for push-based monitoring. If set, no polling — data arrives via WebSocket.',
      },
      'condition': {
        'type': 'string',
        'description':
            'Optional JS expression for alerts. Evaluated with result and state variables.',
      },
      'display': {
        'type': 'string',
        'enum': [
          'value_card',
          'status_row',
          'mini_chart',
          'text',
          'carousel',
          'watchlist',
        ],
        'description': 'Display widget type (default "value_card")',
      },
      'group': {
        'type': 'string',
        'description':
            'Optional group name for organizing related monitors (e.g. "自选股盯盘")',
      },
      'strategyId': {
        'type': 'string',
        'description':
            'Strategy artifact id when this monitor is derived from StrategySpec.',
      },
      'strategyRules': {
        'type': 'object',
        'description':
            'Structured strategy-derived rules used for monitor provenance.',
      },
      'monitorDraft': {
        'type': 'object',
        'description':
            'Structured monitor draft returned by custom_strategy_observe.',
      },
      'dcaObservation': {
        'type': 'object',
        'description':
            'Structured fund DCA observation returned by custom_strategy_observe.',
      },
      'portfolioEvidence': {
        'type': 'object',
        'description':
            'Structured portfolio evidence returned by custom_strategy_rank.',
      },
      'rebalanceDraft': {
        'type': 'object',
        'description':
            'Structured rebalance draft returned by custom_strategy_rank.',
      },
      'user_prompt': {
        'type': 'string',
        'description': 'The user\'s original request that led to this monitor',
      },
      'description': {
        'type': 'string',
        'description': 'One-line description of what this monitor does',
      },
    },
    'required': ['name', 'user_prompt', 'description'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => true;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final monitorName = input['name'] as String;
    final templateName = input['template'] as String?;
    final templateParams = input['params'] as Map<String, dynamic>?;
    var script = input['script'] as String?;
    final intervalStr = input['interval'] as String? ?? '5m';
    final condition = input['condition'] as String?;
    final display = input['display'] as String? ?? 'value_card';
    final group = input['group'] as String?;
    final strategyId = input['strategyId'] as String?;
    final strategyRules = _normalizeStrategyRules(input);
    final userPrompt = input['user_prompt'] as String?;
    final description = input['description'] as String?;
    final streamUrl = input['streamUrl'] as String?;

    // Resolve template to script
    if (templateName != null) {
      final templateInput = <String, dynamic>{
        ...?templateParams,
        for (final key in ['ts_code', 'code', 'symbol', 'name', 'fund_code'])
          if (input[key] != null && templateParams?[key] == null)
            key: input[key],
        if (input['strategyId'] != null) 'strategyId': input['strategyId'],
        if (input['strategyRules'] != null)
          'strategyRules': input['strategyRules'],
        if (input['monitorDraft'] != null)
          'monitorDraft': input['monitorDraft'],
        if (input['dcaObservation'] != null)
          'dcaObservation': input['dcaObservation'],
        if (input['portfolioEvidence'] != null)
          'portfolioEvidence': input['portfolioEvidence'],
        if (input['rebalanceDraft'] != null)
          'rebalanceDraft': input['rebalanceDraft'],
      };
      final resolved = _resolveTemplate(templateName, templateInput, context);
      if (resolved.startsWith('TEMPLATE_UNAVAILABLE:')) {
        return ToolResult(
          toolUseId: toolUseId,
          content: resolved,
          isError: true,
        );
      }
      script = resolved;
    }

    if (script == null || script.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Either "template" or "script" must be provided.',
        isError: true,
      );
    }

    final interval = _parseInterval(intervalStr);
    if (interval == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid interval "$intervalStr". Use "1m", "5m", "30m", or "1h".',
        isError: true,
      );
    }

    final id = 'mon_${DateTime.now().millisecondsSinceEpoch}';
    final monitor = Monitor(
      id: id,
      name: monitorName,
      script: script,
      interval: interval,
      condition: condition,
      displayType: display,
      userPrompt: userPrompt,
      description: description,
      groupId: group,
      groupName: group,
      strategyId: strategyId,
      strategyRules: strategyRules,
      streamUrl: streamUrl,
    );

    // Test-run the script immediately
    try {
      final result = await scheduler.executeOnce(monitor);
      monitor.lastResult = result;
      monitor.lastRunTime = DateTime.now();
    } catch (e) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Monitor script test-run failed: $e\n\n'
            'Script was NOT saved. Please fix the script and retry.',
        isError: true,
      );
    }

    final error = store.add(monitor);
    if (error.isNotEmpty) {
      return ToolResult(toolUseId: toolUseId, content: error, isError: true);
    }

    final resultPreview = monitor.lastResult.toString();
    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Monitor "$monitorName" created (id: $id).\n'
          'Interval: ${interval.inMinutes}m. Display: $display.\n'
          '${templateName != null ? 'Template: $templateName\n' : ''}'
          '${group != null ? 'Group: $group\n' : ''}'
          '${condition != null ? 'Condition: $condition\n' : ''}'
          'First run result: ${resultPreview.length > 200 ? '${resultPreview.substring(0, 200)}...' : resultPreview}\n'
          'Monitor is now active in MonitorPanel.',
    );
  }

  String _resolveTemplate(
    String name,
    Map<String, dynamic> params,
    ToolContext context,
  ) {
    final templatePath = p.join(
      context.basePath,
      'bundle',
      'skills',
      'monitor-templates',
      '$name.js',
    );
    final file = File(templatePath);
    if (!file.existsSync()) {
      return 'TEMPLATE_UNAVAILABLE: "$name" does not exist at $templatePath';
    }

    var script = file.readAsStringSync();
    final expandedParams = _expandTemplateParams(name, params, context);

    // Replace {{param}} placeholders with values
    expandedParams.forEach((key, value) {
      final placeholder = '{{$key}}';
      String replacement;
      if (value is String) {
        replacement = value;
      } else if (value is List || value is Map) {
        replacement = jsonEncode(value);
      } else {
        replacement = value?.toString() ?? 'null';
      }
      script = script.replaceAll(placeholder, replacement);
    });

    // Replace unreplaced optional params with null
    script = script.replaceAll(RegExp(r'\{\{(\w+)\}\}'), 'null');

    return script;
  }

  Map<String, dynamic> _expandTemplateParams(
    String templateName,
    Map<String, dynamic> params,
    ToolContext context,
  ) {
    final expanded = Map<String, dynamic>.from(params);
    if (templateName == 'strategy_signal') {
      final rules = _normalizeStrategyRules(params);
      final symbol =
          '${expanded['ts_code'] ?? expanded['symbol'] ?? rules?['symbol'] ?? ''}'
              .trim();
      if (symbol.isNotEmpty && expanded['ts_code'] == null) {
        final code = symbol.contains('.') ? symbol : '$symbol.SH';
        expanded['ts_code'] = code;
      }
      expanded.putIfAbsent('name', () => expanded['ts_code'] ?? 'strategy');
      expanded.putIfAbsent('market', () => 'CN');
      expanded.putIfAbsent(
        'sma_period',
        () => _indicatorPeriod(rules, 'sma', 20),
      );
      expanded.putIfAbsent(
        'volume_period',
        () => _indicatorPeriod(rules, 'volume_sma', 20),
      );
      final dataRequirements = rules?['dataRequirements'];
      if (dataRequirements is Map && dataRequirements['minBars'] != null) {
        expanded.putIfAbsent('min_bars', () => dataRequirements['minBars']);
      }
      expanded.putIfAbsent('min_bars', () => 120);
      expanded.putIfAbsent(
        'strategy_id',
        () =>
            expanded['strategyId'] ??
            rules?['id'] ??
            rules?['strategyId'] ??
            '',
      );
    } else if (templateName == 'fund_rule_monitor') {
      final rules = _normalizeStrategyRules(params);
      final monitorDraft = rules?['monitorDraft'] is Map
          ? Map<String, dynamic>.from(rules!['monitorDraft'] as Map)
          : <String, dynamic>{};
      final dcaObservation = rules?['dcaObservation'] is Map
          ? Map<String, dynamic>.from(rules!['dcaObservation'] as Map)
          : <String, dynamic>{};
      final symbol =
          '${expanded['fund_code'] ?? expanded['code'] ?? expanded['symbol'] ?? rules?['fundCode'] ?? rules?['code'] ?? rules?['symbol'] ?? monitorDraft['fundCode'] ?? monitorDraft['code'] ?? monitorDraft['symbol'] ?? ''}'
              .trim();
      if (symbol.isNotEmpty) {
        expanded.putIfAbsent('fund_code', () => symbol);
      }
      expanded.putIfAbsent(
        'name',
        () => expanded['fund_code'] ?? expanded['code'] ?? 'fund',
      );
      expanded.putIfAbsent(
        'strategy_id',
        () =>
            expanded['strategyId'] ??
            rules?['id'] ??
            rules?['strategyId'] ??
            monitorDraft['strategyId'] ??
            '',
      );
      expanded.putIfAbsent('monitor_draft', () => monitorDraft);
      expanded.putIfAbsent('dca_observation', () => dcaObservation);
      expanded.putIfAbsent('min_rows', () => expanded['minRows'] ?? 30);
    } else if (templateName == 'portfolio_rebalance_monitor') {
      final rules = _normalizeStrategyRules(params);
      final portfolioEvidence = rules?['portfolioEvidence'] is Map
          ? Map<String, dynamic>.from(rules!['portfolioEvidence'] as Map)
          : <String, dynamic>{};
      final rebalanceDraft = rules?['rebalanceDraft'] is Map
          ? Map<String, dynamic>.from(rules!['rebalanceDraft'] as Map)
          : <String, dynamic>{};
      expanded.putIfAbsent(
        'strategy_id',
        () =>
            expanded['strategyId'] ??
            rules?['id'] ??
            rules?['strategyId'] ??
            rebalanceDraft['strategyId'] ??
            portfolioEvidence['strategyId'] ??
            '',
      );
      expanded.putIfAbsent('portfolio_evidence', () => portfolioEvidence);
      expanded.putIfAbsent('rebalance_draft', () => rebalanceDraft);
      expanded.putIfAbsent(
        'review_interval',
        () => rebalanceDraft['rebalanceInterval'] ?? 'manual',
      );
    }
    final items = params['items'];
    if (items is List) {
      final market = params['market']?.toString() ?? 'CN';
      final calls = <String>[];
      for (final item in items) {
        if (item is! Map) continue;
        final code = item['ts_code']?.toString();
        if (code == null || code.trim().isEmpty) continue;
        calls.add(
          "callService('/api/finance/quote', {ts_code: ${jsonEncode(code)}, market: ${jsonEncode(market)}})",
        );
      }
      expanded['quote_calls'] = calls.join(',\n  ');
    }
    return expanded;
  }

  int _indicatorPeriod(Map<String, dynamic>? rules, String type, int fallback) {
    final indicators = rules?['indicators'];
    if (indicators is! List) return fallback;
    for (final indicator in indicators) {
      if (indicator is! Map || '${indicator['type']}' != type) continue;
      final params = indicator['params'];
      final period = params is Map ? params['period'] : null;
      if (period is num) return period.toInt();
      final parsed = int.tryParse('$period');
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  Map<String, dynamic>? _normalizeStrategyRules(Map<String, dynamic> input) {
    final rules = input['strategyRules'] is Map
        ? Map<String, dynamic>.from(input['strategyRules'] as Map)
        : <String, dynamic>{};
    if (input['monitorDraft'] is Map) {
      rules['monitorDraft'] = Map<String, dynamic>.from(
        input['monitorDraft'] as Map,
      );
    }
    if (input['dcaObservation'] is Map) {
      rules['dcaObservation'] = Map<String, dynamic>.from(
        input['dcaObservation'] as Map,
      );
    }
    if (input['portfolioEvidence'] is Map) {
      rules['portfolioEvidence'] = Map<String, dynamic>.from(
        input['portfolioEvidence'] as Map,
      );
    }
    if (input['rebalanceDraft'] is Map) {
      rules['rebalanceDraft'] = Map<String, dynamic>.from(
        input['rebalanceDraft'] as Map,
      );
    }
    if (rules.isEmpty) return null;
    return rules;
  }

  Duration? _parseInterval(String s) {
    final match = RegExp(r'^(\d+)(m|h)$').firstMatch(s);
    if (match == null) return null;
    final n = int.parse(match.group(1)!);
    return match.group(2) == 'h' ? Duration(hours: n) : Duration(minutes: n);
  }
}
