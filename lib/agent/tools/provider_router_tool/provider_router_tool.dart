import 'dart:convert';

import '../../../domain/market/providers/data_api_interface_contract.dart';
import '../../data_fetcher/api_stats.dart';
import '../../data_fetcher/provider_policy.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../tool_catalog_tool/provider_module_descriptors.dart';

typedef ProviderHealthProvider = List<Map<String, dynamic>> Function();

class ProviderRouterTool extends Tool {
  ProviderRouterTool({ProviderHealthProvider? runtimeHealthProvider})
    : _runtimeHealthProvider = runtimeHealthProvider;

  final ProviderHealthProvider? _runtimeHealthProvider;

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
      'providerHealth': {
        'type': 'array',
        'items': {'type': 'object'},
        'description':
            'Optional health rows: provider, status, reason. unhealthy/blocked/quota_exhausted/credential_missing statuses are skipped.',
      },
      'includeRuntimeHealth': {
        'type': 'boolean',
        'description':
            'Default true. Merge recent runtime API health from the app statistics store so provider health can affect routing without manual rows.',
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
    final healthRows = _combinedHealthRows(task, input);
    final healthBlocks = _healthBlocks(healthRows);
    final effectiveGates = ProviderGates(
      windConfigured: gates.windConfigured,
      windQuotaAvailable: gates.windQuotaAvailable,
      tushareConfigured: gates.tushareConfigured,
      tusharePermissionLikely: gates.tusharePermissionLikely,
      allowAkshareCompatibility: gates.allowAkshareCompatibility,
      allowBroadAkshare: gates.allowBroadAkshare,
      temporarilyBlockedProviders: {
        ...gates.temporarilyBlockedProviders,
        ...healthBlocks.keys,
      },
    );
    final preferred = policy.normalizeProviders(input['preferredProviders']);
    final allowed = policy.orderFor(
      task,
      gates: effectiveGates,
      preferredProviders: preferred,
    );
    final base = _baseOrder(task);
    final skipped = base
        .where((provider) => !allowed.contains(provider))
        .map(
          (provider) => {
            'provider': _providerName(provider),
            'reason':
                healthBlocks[provider] ??
                _skipReason(provider, effectiveGates, preferred),
          },
        )
        .toList();
    return {
      'contract': 'provider-router-route-v1',
      'runtime': 'finagent-mobile',
      'task': _taskName(task),
      'order': allowed.map(_providerName).toList(),
      'providerModules': base.map((provider) {
        final name = _providerName(provider);
        final descriptor = _descriptorForProvider(provider);
        return {
          'provider': name,
          'routeEffect': allowed.contains(provider) ? 'selected' : 'skipped',
          if (descriptor != null) 'descriptor': descriptor.toJson(),
          'descriptorStatus': descriptor == null ? 'missing' : 'registered',
        };
      }).toList(),
      'preferredProviders': preferred.map(_providerName).toList(),
      'skipped': skipped,
      'serialProviders': allowed
          .where(policy.requiresSerialCalls)
          .map(_providerName)
          .toList(),
      'gates': _gatesJson(effectiveGates),
      'providerHealth': healthBlocks.entries
          .map(
            (entry) => {
              'provider': _providerName(entry.key),
              'routeEffect': 'skipped',
              'reason': entry.value,
            },
          )
          .toList(),
      'providerHealthSource': _providerHealthSource(input, healthRows),
      'descriptorSource': {
        'version': providerModuleDescriptorVersion,
        'registeredProviders': providerModuleDescriptors
            .map((descriptor) => descriptor.provider)
            .toList(),
      },
      'nextAction': allowed.isEmpty
          ? 'No provider is currently allowed. Use cache/readback, configure credentials, or clear temporary provider blocks before retrying.'
          : 'Use providers in returned order; do not override order from prompt knowledge.',
    };
  }

  List<Map<String, dynamic>> _combinedHealthRows(
    FinanceDataTask task,
    Map<String, dynamic> input,
  ) {
    final rows = <Map<String, dynamic>>[];
    final provided = input['providerHealth'];
    if (provided is List) {
      rows.addAll(provided.whereType<Map>().map(Map<String, dynamic>.from));
    }
    if (input['includeRuntimeHealth'] == false) return rows;
    rows.addAll(contractProviderHealthRows(task));
    final runtime =
        _runtimeHealthProvider?.call() ?? runtimeProviderHealthRows();
    rows.addAll(runtime);
    return rows;
  }
}

ProviderModuleDescriptor? _descriptorForProvider(FinanceProvider provider) {
  final name = _providerName(provider);
  for (final descriptor in providerModuleDescriptors) {
    if (descriptor.provider == name) return descriptor;
  }
  return null;
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

Map<FinanceProvider, String> _healthBlocks(List<Map<String, dynamic>> rows) {
  const policy = ProviderPolicy();
  final out = <FinanceProvider, String>{};
  for (final row in rows) {
    final providers = policy.normalizeProviders([row['provider']]);
    if (providers.isEmpty) continue;
    final provider = providers.first;
    final status = '${row['status'] ?? ''}'.trim();
    const blocked = {
      'unhealthy',
      'blocked',
      'runtime_unavailable',
      'transport_unstable',
      'quota_exhausted',
      'credential_missing',
    };
    if (blocked.contains(status)) {
      out[provider] =
          'health_$status:${row['reason'] ?? 'provider health blocked routing'}';
    }
  }
  return out;
}

List<Map<String, dynamic>> runtimeProviderHealthRows({
  Duration range = const Duration(minutes: 30),
}) {
  return ApiStats.instance
      .getSummary(range: range)
      .where((summary) => summary.totalRequests > 0)
      .map((summary) {
        final status = _runtimeHealthStatus(summary);
        return {
          'provider': summary.source,
          'status': status,
          'reason': status == 'ready'
              ? 'runtime health ready: ${summary.successCount}/${summary.totalRequests} recent calls succeeded'
              : 'runtime health $status: ${summary.failCount}/${summary.totalRequests} recent calls failed${summary.lastError == null ? '' : ' (${summary.lastError})'}',
          'source': 'ApiStats',
          'total': summary.totalRequests,
          'success': summary.successCount,
          'failures': summary.failCount,
          'p95LatencyMs': summary.p95LatencyMs,
          'lastRequest': summary.lastRequest?.toIso8601String(),
        };
      })
      .toList(growable: false);
}

List<Map<String, dynamic>> contractProviderHealthRows(FinanceDataTask task) {
  final interfaceIds = _taskInterfaceIds(task);
  if (interfaceIds.isEmpty) return const [];
  final rows = <Map<String, dynamic>>[];
  for (final interfaceId in interfaceIds) {
    final definition = dataApiInterfaceContract.getInterface(interfaceId);
    if (definition == null) continue;
    for (final capability in definition.capabilities) {
      final status = _contractBlockingStatus(capability.status);
      if (status == null) continue;
      rows.add({
        'provider': capability.provider.name,
        'status': status,
        'reason':
            'contract $status: ${capability.id} for ${definition.id}${capability.probeId == null ? '' : ' probe=${capability.probeId}'}${capability.reason == null ? '' : ' (${capability.reason})'}',
        'source': 'dataApiInterfaceContract',
        'interfaceId': definition.id,
        'capabilityId': capability.id,
        'probeId': capability.probeId,
      });
    }
  }
  return rows;
}

String? _contractBlockingStatus(DataApiCapabilityStatus status) {
  if (status == DataApiCapabilityStatus.disabled) return 'blocked';
  if (status == DataApiCapabilityStatus.transportUnstable) {
    return 'transport_unstable';
  }
  return null;
}

List<String> _taskInterfaceIds(FinanceDataTask task) => switch (task) {
  FinanceDataTask.quote => const ['stock.quote'],
  FinanceDataTask.indexQuote => const ['index.quote'],
  FinanceDataTask.kline => const ['stock.daily_kline'],
  FinanceDataTask.indexKline => const ['index.daily_kline'],
  FinanceDataTask.intradayTick => const [
    'stock.tick_chart_intraday',
    'stock.transactions',
  ],
  FinanceDataTask.sector => const ['market.sector_ranking'],
  FinanceDataTask.limitPool => const ['market.limit_pool'],
  FinanceDataTask.dragonTiger => const ['market.dragon_tiger'],
  FinanceDataTask.fundamental => const [
    'stock.daily_valuation',
    'stock.company_info',
  ],
  FinanceDataTask.macro => const ['wind.economic_series'],
  FinanceDataTask.fund => const ['fund.identity_list', 'fund.nav_history'],
  FinanceDataTask.moneyFlow => const ['stock.money_flow', 'market.flow_rank'],
};

String _runtimeHealthStatus(SourceSummary summary) {
  if (summary.failCount <= 0) return 'ready';
  if (summary.successCount <= 0) return 'runtime_unavailable';
  if (summary.failRate >= 0.5) return 'transport_unstable';
  return 'degraded';
}

Map<String, dynamic> _providerHealthSource(
  Map<String, dynamic> input,
  List<Map<String, dynamic>> rows,
) => {
  'manualRows': input['providerHealth'] is List
      ? (input['providerHealth'] as List).length
      : 0,
  'runtimeRows': input['includeRuntimeHealth'] == false
      ? 0
      : rows.length -
            (input['providerHealth'] is List
                ? (input['providerHealth'] as List).length
                : 0),
  'contractRows': rows
      .where((row) => row['source'] == 'dataApiInterfaceContract')
      .length,
  'runtimeEnabled': input['includeRuntimeHealth'] != false,
};

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
