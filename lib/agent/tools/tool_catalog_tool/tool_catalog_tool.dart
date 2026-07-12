import 'dart:convert';

import '../../../domain/market/providers/data_api_interface_contract.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'provider_module_descriptors.dart';

class ToolCatalogTool extends Tool {
  final List<Tool> Function() toolsProvider;

  ToolCatalogTool({required this.toolsProvider});

  @override
  String get name => 'ToolCatalog';

  @override
  String get description =>
      'Inspect the runtime tool catalog and capability summaries. Use list first, then detail for a specific tool.';

  @override
  String get prompt =>
      'Use ToolCatalog to inspect registered tools before calling broad or unfamiliar tools. '
      'Call action="list" first; call action="detail" with a tool name for schema and action values.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': [
          'help',
          'list',
          'detail',
          'modules',
          'module',
          'providerModules',
        ],
        'description':
            'help, list all tool capabilities, detail one tool, list capability modules, detail one module, or summarize provider capability modules',
      },
      'tool': {'type': 'string', 'description': 'Tool name for detail action'},
      'module': {
        'type': 'string',
        'description': 'Module id for module action',
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
    final action = (input['action'] as String?)?.trim() ?? 'list';
    if (action == 'help') {
      return ToolResult(toolUseId: toolUseId, content: jsonEncode(_help()));
    }
    if (action == 'providerModules') {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode(_providerModules()),
      );
    }
    if (!['list', 'detail', 'modules', 'module'].contains(action)) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid ToolCatalog action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }

    final capabilities = toolsProvider().map(summarizeToolCapability).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    if (action == 'modules' || action == 'module') {
      final modules = _moduleDescriptors(capabilities);
      if (action == 'module') {
        final moduleId = (input['module'] as String?)?.trim() ?? '';
        if (moduleId.isEmpty) {
          return ToolResult(
            toolUseId: toolUseId,
            content:
                'ToolCatalog(action:"module") requires module. Use action="modules" first.',
            isError: true,
          );
        }
        final matches = modules.where((m) => m['id'] == moduleId).toList();
        if (matches.isEmpty) {
          return ToolResult(
            toolUseId: toolUseId,
            content:
                'Capability module "$moduleId" is not registered. Use ToolCatalog(action:"modules") for available modules.',
            isError: true,
          );
        }
        return ToolResult(
          toolUseId: toolUseId,
          content: jsonEncode({
            'contract': 'capability-module-result-v1',
            'action': action,
            'module': matches.single,
          }),
        );
      }
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'capability-module-result-v1',
          'action': action,
          'count': modules.length,
          'modules': modules
              .map(
                (module) => {
                  'id': module['id'],
                  'title': module['title'],
                  'permissionClass': module['permissionClass'],
                  'agentPaths': module['agentPaths'],
                  'toolCount': (module['tools'] as List).length,
                },
              )
              .toList(),
        }),
      );
    }

    if (action == 'detail') {
      final toolName = (input['tool'] as String?)?.trim() ?? '';
      if (toolName.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'ToolCatalog detail requires "tool". Use action="list" to inspect tool names.',
          isError: true,
        );
      }
      final matches = capabilities.where((c) => c.name == toolName).toList();
      if (matches.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'Tool "$toolName" is not registered. Use ToolCatalog(action:"list") for available tools.',
          isError: true,
        );
      }
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'tool-catalog-result-v1',
          'action': action,
          'tool': matches.single.toJson(),
        }),
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'tool-catalog-result-v1',
        'action': action,
        'count': capabilities.length,
        'tools': capabilities
            .map(
              (capability) => {
                'name': capability.name,
                'permission': capability.permission,
                'readOnly': capability.readOnly,
                'canParallel': capability.canParallel,
                'requiresUserInteraction': capability.requiresUserInteraction,
                'actions': capability.actionValues,
              },
            )
            .toList(),
      }),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'tool-catalog-help-v1',
    'actions': ['list', 'detail', 'modules', 'module', 'providerModules'],
    'guidance':
        'Use list/detail for individual tools. Use modules/module to inspect provider modules, cache/permission behavior, health dependencies, and runtime limitations before broad or unfamiliar work.',
  };

  Map<String, dynamic> _providerModules() {
    final byProvider = <String, _ProviderModuleAccumulator>{};
    for (final definition in dataApiInterfaceContract.interfaces) {
      for (final capability in definition.capabilities) {
        final provider = capability.provider.name;
        byProvider
            .putIfAbsent(provider, () => _ProviderModuleAccumulator(provider))
            .add(definition, capability);
      }
    }
    final descriptorByProvider = {
      for (final descriptor in providerModuleDescriptors)
        descriptor.provider: descriptor,
    };
    for (final descriptor in providerModuleDescriptors) {
      byProvider.putIfAbsent(
        descriptor.provider,
        () => _ProviderModuleAccumulator(descriptor.provider),
      );
    }
    final providers = byProvider.values.map((item) => item.toJson()).toList()
      ..sort((a, b) => '${a['provider']}'.compareTo('${b['provider']}'));
    return {
      'contract': 'provider-module-matrix-v2',
      'runtime': 'finagent-mobile',
      'sources': ['dataApiInterfaceContract', providerModuleDescriptorVersion],
      'version': dataApiInterfaceContractVersion,
      'providerCount': providers.length,
      'descriptorCount': providerModuleDescriptors.length,
      'interfaceCount': dataApiInterfaceContract.interfaces.length,
      'providers': providers.map((provider) {
        final descriptor = descriptorByProvider['${provider['provider']}'];
        return {
          ...provider,
          if (descriptor != null) 'descriptor': descriptor.toJson(),
          'descriptorStatus': descriptor == null ? 'missing' : 'registered',
        };
      }).toList(),
      'descriptorCoverage': {
        'requiredFamilies': [
          'EastMoney',
          'TDX',
          'Yahoo/yfinance',
          'Wind',
          'Tushare',
          'Sina',
          'Tencent',
          'AkShare',
          'official macro APIs',
          'search/research',
          'Xueqiu',
          'UI artifacts',
        ],
        'coveredProviders': providerModuleDescriptors
            .map((descriptor) => descriptor.provider)
            .toList(),
      },
      'guidance':
          'Use this matrix before broad provider calls. Supported/globalOnly capabilities are reusable only when normalizer, canonical table, readback, and runtime evidence are present. Gated/unstable/disabled/notSupported providers must not be retried as normal workflow.',
    };
  }

  List<Map<String, dynamic>> _moduleDescriptors(
    List<ToolCapabilitySummary> capabilities,
  ) {
    final groups = <String, List<ToolCapabilitySummary>>{};
    for (final capability in capabilities) {
      groups.putIfAbsent(_moduleId(capability.name), () => []).add(capability);
    }
    final modules = groups.entries.map((entry) {
      final descriptor = _moduleTemplate(entry.key);
      return {
        ...descriptor,
        'runtime': 'finagent-mobile',
        'tools': entry.value.map((capability) => capability.toJson()).toList(),
      };
    }).toList();
    final marketData = capabilities.where((item) => item.name == 'MarketData');
    if (marketData.isNotEmpty) {
      modules.add({
        ..._moduleTemplate('strategy-runtime'),
        'runtime': 'finagent-mobile',
        'tools': marketData.map((capability) => capability.toJson()).toList(),
      });
    }
    return modules..sort((a, b) => '${a['id']}'.compareTo('${b['id']}'));
  }

  String _moduleId(String toolName) {
    const exact = {
      'MarketData': 'finance-data',
      'DataStore': 'finance-data',
      'ProviderRouter': 'finance-data',
      'BudgetGovernor': 'finance-data',
      'Research': 'research-source',
      'WebFetch': 'research-source',
      'SourceReader': 'research-source',
      'Runbook': 'workflow-harness',
      'WorkflowVerifier': 'workflow-harness',
      'WorkflowEvidence': 'workflow-harness',
      'FinanceWorkflowState': 'workflow-harness',
      'RecoveryPlanner': 'workflow-harness',
      'AgentSelfDebug': 'workflow-harness',
      'InteractionEvidence': 'workflow-harness',
      'ArtifactRegistry': 'artifact',
      'UIControl': 'ui-artifact',
      'UIQuery': 'ui-artifact',
      'WebView': 'ui-artifact',
      'XueqiuTrade': 'trading',
      'Portfolio': 'trading',
      'Agent': 'sub-agent',
      'TaskOutput': 'sub-agent',
      'AskUserQuestion': 'interaction',
    };
    return exact[toolName] ?? 'runtime-tool';
  }

  Map<String, dynamic> _moduleTemplate(String id) {
    const templates = {
      'finance-data': {
        'id': 'finance-data',
        'title': 'Finance data providers and cache',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Available to chat and event agents through ToolCatalog/ProviderRouter. Event usage should stay bounded for scheduled refresh, watchlist, monitor, probe, and recovery workflows.',
        'permissionClass': 'read-only provider/cache',
        'cacheDataContract':
            'Use local reusable data first when freshness and coverage are sufficient; provider paths must expose source/as-of/fetched-at when available.',
        'healthEvidence':
            'ProviderRouter, BudgetGovernor, API stats, and data provenance rows explain provider order, gates, and skips.',
        'limitations':
            'Mobile has no Python/gotdx sidecar; provider availability is mobile-native and config/network dependent.',
        'discovery':
            'Call ProviderRouter(action:"tasks") and ToolCatalog(action:"detail", tool:"MarketData") before broad provider calls.',
      },
      'research-source': {
        'id': 'research-source',
        'title': 'Research, web, macro, and source ingestion',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Available to chat and event agents. Event usage should prefer bounded source refresh or macro update tasks, not broad unattended browsing.',
        'permissionClass': 'read-only network',
        'cacheDataContract':
            'Persist durable source evidence or artifact records when content is reused in analysis.',
        'healthEvidence':
            'BudgetGovernor and tool errors expose quota/network/source failures.',
        'limitations':
            'Some sites require browser/WebView interaction or source-specific access.',
        'discovery': 'Use tool help before fetching broad source collections.',
      },
      'workflow-harness': {
        'id': 'workflow-harness',
        'title':
            'Workflow state, runbooks, verification, recovery, and debugging',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Available to chat and event agents for typed state, verification, recovery, and debugging. Do not replace this with prompt-text parsing.',
        'permissionClass': 'read-only plus state writes',
        'cacheDataContract':
            'Workflow state and evidence live under runtime memory; do not infer intent from prompt text.',
        'healthEvidence':
            'Runtime state, pending interactions, repeated failures, and verifier output are agent-visible.',
        'limitations':
            'Verifier coverage is contract-based; domain-specific checks must be added per workflow family.',
        'discovery':
            'Start with Runbook, FinanceWorkflowState, WorkflowVerifier, AgentSelfDebug, and RecoveryPlanner.',
      },
      'artifact': {
        'id': 'artifact',
        'title': 'Durable artifacts',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Available to chat and event agents for durable outputs. Event-created artifacts must remain inspectable from later chat sessions.',
        'permissionClass': 'state write',
        'cacheDataContract':
            'Artifacts record kind, path, provenance, freshness, verification status, links, and owner task.',
        'healthEvidence':
            'ArtifactRegistry list/get shows reusable outputs and verification state.',
        'limitations':
            'Structural UI rendering depends on artifact kind and app surface.',
        'discovery': 'Use ArtifactRegistry(action:"help").',
      },
      'ui-artifact': {
        'id': 'ui-artifact',
        'title': 'UI pages, dashboards, and visual observation',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Chat can create and inspect UI artifacts. Event agent may update or queue UI artifacts only when the runtime has a valid UI bridge.',
        'permissionClass': 'UI interaction',
        'cacheDataContract':
            'Generated pages should be linked as dashboard/report artifacts when reused.',
        'healthEvidence':
            'UI tool results and workflow evidence show created/opened artifacts.',
        'limitations':
            'Mobile presentation is compact and may differ from workstation full views.',
        'discovery': 'Use UI tool help and ArtifactRegistry links.',
      },
      'trading': {
        'id': 'trading',
        'title': 'Trade preparation and simulated trading',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Chat handles trade preparation and user approval. Event agent may monitor or review, but must not execute trade side effects without explicit approval state.',
        'permissionClass': 'approval/side-effect boundary',
        'cacheDataContract':
            'Trade-preparation artifacts must separate analysis, sizing, approval, and execution evidence.',
        'healthEvidence':
            'Workflow state, pending approval, and broker/provider status must be visible before action.',
        'limitations':
            'Real side effects require explicit approval and configured provider state.',
        'discovery': 'Use Runbook and FinanceWorkflowState before trade tools.',
      },
      'strategy-runtime': {
        'id': 'strategy-runtime',
        'title': 'StrategySpec validation, backtest, save, read, and rerun',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Chat can design, validate, backtest, save, and rerun strategies. Event agent can monitor saved strategy conditions and recovery state when configured.',
        'permissionClass':
            'read-only computation plus strategy artifact writes',
        'cacheDataContract':
            'Agent-created strategies must flow through StrategySpec, validation report, data coverage, backtest or fund observation evidence, saved artifact, and readback/run evidence before reuse.',
        'healthEvidence':
            'WorkflowVerifier(strategy_backtest), ArtifactRegistry, FinanceWorkflowState, and MarketData custom_strategy_* results expose lifecycle status, unsupported parts, assumptions, and data coverage.',
        'limitations':
            'Mobile strategy execution is sandboxed and data-dependent. Unsupported indicators, macro prose, news sentiment, arbitrary code, or broker actions must remain rejected unless the StrategySpec contract explicitly supports them.',
        'discovery':
            'Call Runbook(action:"get", workflow:"strategy_backtest"), ToolCatalog(action:"detail", tool:"MarketData"), then MarketData(action:"custom_strategy_help") before validate/backtest/save/run.',
      },
      'sub-agent': {
        'id': 'sub-agent',
        'title': 'Sub-agent tasks and handoff',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat'],
        'usability':
            'Primary use is chat-agent decomposition. Event-agent sub-agent use must be explicit and bounded to avoid unattended recursion.',
        'permissionClass': 'runtime task',
        'cacheDataContract':
            'Task output should become structured evidence or an artifact before parent completion.',
        'healthEvidence':
            'Task state and TaskOutput determine whether dependent work is complete.',
        'limitations': 'Output validation depends on task contract.',
        'discovery': 'Use Agent/TaskOutput help and workflow verifier.',
      },
      'interaction': {
        'id': 'interaction',
        'title': 'User questions and approvals',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Both paths can expose pending user questions or approvals. Test automation should inspect and answer deliberately instead of hidden fixed-choice parsing.',
        'permissionClass': 'requires user input',
        'cacheDataContract':
            'Pending interaction state is evidence; do not hide answers in test code.',
        'healthEvidence':
            'InteractionEvidence and runtimeState expose pending user input.',
        'limitations': 'Requires deliberate operator/user answer.',
        'discovery': 'Use InteractionEvidence and AgentSelfDebug.',
      },
      'runtime-tool': {
        'id': 'runtime-tool',
        'title': 'General runtime tools',
        'schema': 'provider-module-descriptor-v1',
        'agentPaths': ['chat', 'event'],
        'usability':
            'Availability is tool-specific. Inspect detail and module metadata before use.',
        'permissionClass': 'tool-specific',
        'cacheDataContract': 'Inspect each tool detail before use.',
        'healthEvidence':
            'Tool result errors and CapabilityStatus summarize failures.',
        'limitations': 'Behavior is tool-specific.',
        'discovery': 'Use ToolCatalog(action:"detail").',
      },
    };
    return Map<String, dynamic>.from(
      templates[id] ?? templates['runtime-tool']!,
    );
  }
}

class _ProviderModuleAccumulator {
  _ProviderModuleAccumulator(this.provider);

  final String provider;
  final interfaces = <String>{};
  final schemas = <String>{};
  final readbacks = <String>{};
  final probes = <String>{};
  final statusCounts = <String, int>{};
  final unsupportedExamples = <String>[];

  void add(
    DataApiInterfaceDefinition definition,
    DataApiProviderCapability capability,
  ) {
    interfaces.add(definition.id);
    if (definition.canonicalSchema.isNotEmpty)
      schemas.add(definition.canonicalSchema);
    readbacks.addAll(definition.queryActions);
    final probeId = capability.probeId;
    if (probeId != null && probeId.isNotEmpty) probes.add(probeId);
    final status = capability.status.name;
    statusCounts[status] = (statusCounts[status] ?? 0) + 1;
    if (capability.status == DataApiCapabilityStatus.notSupported ||
        capability.status == DataApiCapabilityStatus.disabled ||
        capability.status == DataApiCapabilityStatus.transportUnstable) {
      if (unsupportedExamples.length < 5) {
        unsupportedExamples.add('${definition.id}:${capability.status.name}');
      }
    }
  }

  Map<String, dynamic> toJson() => {
    'provider': provider,
    'interfaceCount': interfaces.length,
    'schemaCount': schemas.length,
    'readbackActionCount': readbacks.length,
    'probeCount': probes.length,
    'statusCounts': statusCounts,
    'sampleInterfaces': interfaces.take(8).toList(),
    'sampleSchemas': schemas.take(8).toList(),
    'sampleReadbacks': readbacks.take(8).toList(),
    'unsupportedExamples': unsupportedExamples,
  };
}
