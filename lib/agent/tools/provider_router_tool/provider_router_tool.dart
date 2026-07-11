import 'dart:convert';

import '../../data_fetcher/provider_policy.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class ProviderRouterTool extends Tool {
  @override
  String get name => 'ProviderRouter';

  @override
  String get description =>
      'Explain code-owned finance provider routing order, provider gates, skipped providers, and serial-call requirements.';

  @override
  String get prompt =>
      'Use ProviderRouter(action:"route", task:"quote") before choosing finance data providers manually. Provider order is code-owned; do not infer it from prompt text.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'tasks', 'route'],
      },
      'task': {
        'type': 'string',
        'enum': FinanceDataTask.values.map(_taskName).toList(),
      },
      'preferredProviders': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'temporarilyBlockedProviders': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'gates': {
        'type': 'object',
        'description':
            'Optional provider gates: windConfigured, windQuotaAvailable, tushareConfigured, tusharePermissionLikely, allowAkshareCompatibility, allowBroadAkshare.',
      },
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
    final action = (input['action'] as String?)?.trim() ?? 'tasks';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action == 'tasks') {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'provider-router-tasks-v1',
          'tasks': FinanceDataTask.values.map(_taskName).toList(),
        }),
      );
    }
    if (action != 'route') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid ProviderRouter action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final task = _parseTask(input['task']);
    if (task == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'ProviderRouter(action:"route") requires a supported task. Use action="tasks" to inspect tasks.',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(_route(task, input)),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'provider-router-help-v1',
    'actions': ['tasks', 'route'],
    'guidance': [
      'Provider routing is code-owned and can account for credentials, quota, compatibility gates, and temporary provider blocks.',
      'Use preferredProviders only to request a provider already allowed by policy; unsupported preferences are ignored with explanation.',
      'Use the returned order and skipped list in final provenance instead of inventing provider order.',
    ],
  };

  Map<String, dynamic> _route(
    FinanceDataTask task,
    Map<String, dynamic> input,
  ) {
    const policy = ProviderPolicy();
    final gates = _gates(input);
    final preferred = policy.normalizeProviders(input['preferredProviders']);
    final allowed = policy.orderFor(
      task,
      gates: gates,
      preferredProviders: preferred,
    );
    final base = _baseOrder(task);
    final skipped = base
        .where((provider) => !allowed.contains(provider))
        .map(
          (provider) => {
            'provider': _providerName(provider),
            'reason': _skipReason(provider, gates, preferred),
          },
        )
        .toList();
    return {
      'contract': 'provider-router-route-v1',
      'runtime': 'finagent-mobile',
      'task': _taskName(task),
      'order': allowed.map(_providerName).toList(),
      'preferredProviders': preferred.map(_providerName).toList(),
      'skipped': skipped,
      'serialProviders': allowed
          .where(policy.requiresSerialCalls)
          .map(_providerName)
          .toList(),
      'gates': _gatesJson(gates),
      'nextAction': allowed.isEmpty
          ? 'No provider is currently allowed. Use cache/readback, configure credentials, or clear temporary provider blocks before retrying.'
          : 'Use providers in returned order; do not override order from prompt knowledge.',
    };
  }
}

const _rawOrders = <FinanceDataTask, List<FinanceProvider>>{
  FinanceDataTask.quote: [
    FinanceProvider.tdx,
    FinanceProvider.eastmoneyDirect,
    FinanceProvider.sina,
    FinanceProvider.tencent,
  ],
  FinanceDataTask.indexQuote: [
    FinanceProvider.tdx,
    FinanceProvider.eastmoneyDirect,
    FinanceProvider.akshare,
  ],
  FinanceDataTask.kline: [FinanceProvider.tdx, FinanceProvider.eastmoneyDirect],
  FinanceDataTask.indexKline: [
    FinanceProvider.tdx,
    FinanceProvider.eastmoneyDirect,
  ],
  FinanceDataTask.intradayTick: [FinanceProvider.tdx],
  FinanceDataTask.sector: [
    FinanceProvider.eastmoneyDirect,
    FinanceProvider.akshare,
    FinanceProvider.tdx,
  ],
  FinanceDataTask.limitPool: [
    FinanceProvider.eastmoneyDirect,
    FinanceProvider.akshare,
  ],
  FinanceDataTask.dragonTiger: [FinanceProvider.eastmoneyDirect],
  FinanceDataTask.fundamental: [
    FinanceProvider.wind,
    FinanceProvider.tushare,
    FinanceProvider.eastmoneyDirect,
    FinanceProvider.tdx,
  ],
  FinanceDataTask.macro: [
    FinanceProvider.wind,
    FinanceProvider.tushare,
    FinanceProvider.akshare,
  ],
  FinanceDataTask.fund: [
    FinanceProvider.eastmoneyDirect,
    FinanceProvider.akshare,
    FinanceProvider.wind,
  ],
  FinanceDataTask.moneyFlow: [
    FinanceProvider.eastmoneyDirect,
    FinanceProvider.akshare,
    FinanceProvider.wind,
  ],
};

List<FinanceProvider> _baseOrder(FinanceDataTask task) =>
    _rawOrders[task] ?? const [];

ProviderGates _gates(Map<String, dynamic> input) {
  final gates = input['gates'];
  final map = gates is Map
      ? Map<String, dynamic>.from(gates)
      : const <String, dynamic>{};
  const policy = ProviderPolicy();
  return ProviderGates(
    windConfigured: map['windConfigured'] == true,
    windQuotaAvailable: map['windQuotaAvailable'] != false,
    tushareConfigured: map['tushareConfigured'] == true,
    tusharePermissionLikely: map['tusharePermissionLikely'] != false,
    allowAkshareCompatibility: map['allowAkshareCompatibility'] == true,
    allowBroadAkshare: map['allowBroadAkshare'] == true,
    temporarilyBlockedProviders: policy
        .normalizeProviders(input['temporarilyBlockedProviders'])
        .toSet(),
  );
}

String _skipReason(
  FinanceProvider provider,
  ProviderGates gates,
  List<FinanceProvider> preferred,
) {
  if (gates.temporarilyBlockedProviders.contains(provider)) {
    return 'temporarily_blocked';
  }
  if (provider == FinanceProvider.wind && !gates.windAvailable) {
    return gates.windConfigured
        ? 'wind_quota_unavailable'
        : 'wind_not_configured';
  }
  if (provider == FinanceProvider.tushare && !gates.tushareAvailable) {
    return gates.tushareConfigured
        ? 'tushare_permission_unlikely'
        : 'tushare_not_configured';
  }
  if (provider == FinanceProvider.akshare && !gates.allowAkshareCompatibility) {
    return 'akshare_compatibility_disabled';
  }
  if (preferred.isNotEmpty && !preferred.contains(provider))
    return 'not_preferred';
  return 'not_allowed_by_policy';
}

Map<String, dynamic> _gatesJson(ProviderGates gates) => {
  'windConfigured': gates.windConfigured,
  'windQuotaAvailable': gates.windQuotaAvailable,
  'tushareConfigured': gates.tushareConfigured,
  'tusharePermissionLikely': gates.tusharePermissionLikely,
  'allowAkshareCompatibility': gates.allowAkshareCompatibility,
  'allowBroadAkshare': gates.allowBroadAkshare,
  'temporarilyBlockedProviders': gates.temporarilyBlockedProviders
      .map(_providerName)
      .toList(),
};

FinanceDataTask? _parseTask(Object? value) {
  final text = value?.toString().trim();
  for (final task in FinanceDataTask.values) {
    if (_taskName(task) == text) return task;
  }
  return null;
}

String _taskName(FinanceDataTask task) => task.name;

String _providerName(FinanceProvider provider) => provider.name;
