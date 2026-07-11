import 'dart:convert';
import 'dart:io';

import '../../data_fetcher/api_stats.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class BudgetGovernorTool extends Tool {
  @override
  String get name => 'BudgetGovernor';

  @override
  String get description =>
      'Inspect recent provider/API usage, quota-like failures, Wind usage state, and safe retry guidance before broad external calls.';

  @override
  String get prompt =>
      'Use BudgetGovernor(action:"status") before broad provider/search/macro/finance collection or after quota/rate-limit failures. It advises cache-first, bounded probes, or stop conditions.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'status'],
      },
      'source': {'type': 'string'},
      'minutes': {'type': 'integer', 'minimum': 1, 'maximum': 1440},
    },
  };

  @override
  bool get isReadOnly => true;

  @override
  bool get canParallel => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = (input['action'] as String?)?.trim() ?? 'status';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action != 'status') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid BudgetGovernor action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final minutes = _intValue(
      input['minutes'],
      defaultValue: 60,
    ).clamp(1, 1440);
    final source = (input['source'] as String?)?.trim();
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(_status(context, minutes, source)),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'budget-governor-help-v1',
    'actions': ['status'],
    'guidance': [
      'Use before broad or quota-consuming calls.',
      'A stop decision means use cache/readback or ask the user before more live provider calls.',
      'This tool reads local usage evidence; it does not execute provider calls or mutate quotas.',
    ],
  };
}

Map<String, dynamic> _status(ToolContext context, int minutes, String? source) {
  ApiStats.instance.init(context.basePath);
  final range = Duration(minutes: minutes);
  final summaries = ApiStats.instance.getSummary(range: range);
  final failures = ApiStats.instance.getRecentFailures(
    range: range,
    source: source?.isNotEmpty == true ? source : null,
    limit: 50,
  );
  final quotaFailures = failures.where(_isQuotaFailure).toList();
  final wind = _readWindUsage(context);
  final decision = _decision(
    quotaFailures: quotaFailures,
    failures: failures,
    windUsage: wind,
  );
  return {
    'contract': 'budget-governor-status-v1',
    'runtime': 'finagent-mobile',
    'windowMinutes': minutes,
    'source': source?.isNotEmpty == true ? source : null,
    'decision': decision,
    'summary': summaries
        .map(
          (item) => {
            'source': item.source,
            'total': item.totalRequests,
            'success': item.successCount,
            'fail': item.failCount,
            'failRate': item.failRate,
            'avgLatencyMs': item.avgLatencyMs.round(),
            'p95LatencyMs': item.p95LatencyMs.round(),
            'lastRequest': item.lastRequest?.toIso8601String(),
            'lastError': item.lastError,
          },
        )
        .toList(),
    'quotaLikeFailures': quotaFailures.map((item) => item.toJson()).toList(),
    'windUsage': wind,
    'nextAction': _nextAction(decision),
  };
}

String _decision({
  required List<ApiRequestRecord> quotaFailures,
  required List<ApiRequestRecord> failures,
  required Map<String, dynamic> windUsage,
}) {
  if (windUsage['exhausted'] == true) return 'stop_wind_calls';
  if (quotaFailures.isNotEmpty) return 'stop_broad_live_calls';
  if (failures.length >= 3) return 'narrow_or_probe_before_retry';
  return 'ok_with_cache_first';
}

String _nextAction(String decision) {
  switch (decision) {
    case 'stop_wind_calls':
      return 'Do not call Wind again for the current quota day. Use cache/readback or fallback providers.';
    case 'stop_broad_live_calls':
      return 'Stop broad live collection. Use cache/readback, fallback providers, or a bounded credential/quota probe.';
    case 'narrow_or_probe_before_retry':
      return 'Retry only a narrow provider/interface after checking ProviderRouter or RecoveryPlanner.';
    default:
      return 'Use cache/readback first; live calls may continue if scoped and necessary.';
  }
}

bool _isQuotaFailure(ApiRequestRecord record) {
  final text =
      '${record.error ?? ''} ${record.responseSummary ?? ''} ${record.statusCode}'
          .toLowerCase();
  return record.statusCode == 429 ||
      text.contains('quota') ||
      text.contains('rate limit') ||
      text.contains('rate_limit') ||
      text.contains('balance_insufficient') ||
      text.contains('frequency');
}

Map<String, dynamic> _readWindUsage(ToolContext context) {
  final file = File('${context.basePath}/memory/wind_usage.json');
  if (!file.existsSync()) return {'exists': false, 'exhausted': false};
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is Map<String, dynamic>) {
      return {'exists': true, ...decoded};
    }
  } catch (_) {}
  return {'exists': true, 'unreadable': true, 'exhausted': false};
}

int _intValue(Object? value, {required int defaultValue}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}
