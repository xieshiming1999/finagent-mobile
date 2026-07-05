import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/api_stats.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/data_task_engine.dart';
import '../providers/data_api_interface_contract.dart';
import '../providers/output_only_api_interface_contract.dart';
import 'market_data_runtime_probe_service.dart';

class MarketDataSupportService {
  final DataManager _dataManager;
  final DataApiInterfaceContract _contract;
  final OutputOnlyApiInterfaceContract _outputOnlyContract;
  final DataTaskEngine? _dataTaskEngine;

  MarketDataSupportService({
    DataManager? dataManager,
    DataApiInterfaceContract contract = dataApiInterfaceContract,
    OutputOnlyApiInterfaceContract outputOnlyContract =
        const OutputOnlyApiInterfaceContract(),
    DataTaskEngine? dataTaskEngine,
  }) : _dataManager = dataManager ?? DataManager(),
       _contract = contract,
       _outputOnlyContract = outputOnlyContract,
       _dataTaskEngine = dataTaskEngine;

  Map<String, dynamic> sources() {
    final status = Map<String, dynamic>.from(_dataManager.getSourceStatus());
    return {
      'action': 'sources',
      'interfaceId': 'provider.source_status',
      'provider': 'local',
      'providerId': 'local',
      'capabilityId': 'local.provider.source_status',
      'cacheStatus': 'local-evidence',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'provider_source_status',
      'canonicalTable': 'provider_source_status',
      'readbackAction': 'sources',
      'availableSources': _dataManager.sourceNames,
      'tip':
          'Use source param to force specific source: MarketData(action:"quote", symbols:["600519"], source:"tdx")',
      ...status,
    };
  }

  Map<String, dynamic> stats() {
    final stats = Map<String, dynamic>.from(_dataManager.stats());
    return {
      'action': 'stats',
      'interfaceId': 'data.store_stats',
      'provider': 'local',
      'providerId': 'local',
      'capabilityId': 'local.data.store_stats',
      'cacheStatus': 'local-evidence',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'data_store_stats',
      'canonicalTable': 'data_store_stats',
      'readbackAction': 'stats',
      ...stats,
    };
  }

  Map<String, dynamic> coverage({String? code}) {
    final hasCode = code != null && code.isNotEmpty;
    final data = code != null && code.isNotEmpty
        ? _dataManager.coverage(code: code)
        : _dataManager.reusableSummary();
    final symbol = code?.trim().toUpperCase();
    return {
      'action': hasCode ? 'coverage' : 'reusable_summary',
      'interfaceId': 'data.coverage',
      'provider': 'local',
      'capabilityId': 'local.data.coverage',
      'cacheStatus': 'local-evidence',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'data_coverage',
      'canonicalTable': 'data_coverage',
      'readbackAction': hasCode ? 'coverage' : 'reusable_summary',
      if (hasCode && symbol != null && !_isAshareSymbol(symbol))
        'globalYfinanceCoverage': _globalYfinanceCoverage(data),
      if (hasCode && symbol != null && _isAshareSymbol(symbol))
        'globalYfinanceCoverageExcluded': true,
      if (hasCode && symbol != null && _isAshareSymbol(symbol))
        'globalYfinanceCoverageReason':
            'A-share symbol; use China-market interfaces instead of Yahoo/yfinance.',
      ...data,
    };
  }

  Map<String, dynamic> interfaceCatalog({
    String? category,
    String? provider,
    String? health,
    int limit = 30,
  }) {
    final boundedLimit = limit.clamp(1, 200);
    final reusable = _dataManager.reusableSummary();
    final apiSummaries = {
      for (final item in ApiStats.instance.getSummary())
        item.source: {
          'source': item.source,
          'totalRequests': item.totalRequests,
          'successCount': item.successCount,
          'failCount': item.failCount,
          'failRate': item.failRate,
          'avgLatencyMs': item.avgLatencyMs,
          'p95LatencyMs': item.p95LatencyMs,
          'lastRequest': item.lastRequest?.toIso8601String(),
          'lastError': item.lastError,
          'lastFailureClass': item.lastFailureClass,
        },
    };
    final normalizedCategory = category?.trim().toLowerCase();
    final normalizedHealth = health?.trim().toLowerCase();
    final requestedProvider = _normalizeSupportProvider(provider);
    final governedRows = _contract.interfaces
        .map(
          (definition) => _interfaceHealth(definition, reusable, apiSummaries),
        )
        .where((row) {
          if (normalizedCategory != null &&
              normalizedCategory.isNotEmpty &&
              row['category'] != normalizedCategory) {
            return false;
          }
          if (normalizedHealth != null &&
              normalizedHealth.isNotEmpty &&
              row['health'] != normalizedHealth) {
            return false;
          }
          if (requestedProvider != null) {
            final capabilities = (row['capabilities'] as List?) ?? const [];
            if (!capabilities.whereType<Map>().any(
              (capability) => capability['provider'] == requestedProvider.name,
            )) {
              return false;
            }
          }
          return true;
        })
        .toList();
    final outputOnlyRows = normalizedCategory == 'provider_diagnostic'
        ? _outputOnlyCatalogRows(requestedProvider)
        : const <Map<String, dynamic>>[];
    final rows = [...governedRows, ...outputOnlyRows]
      ..sort(_compareInterfaceHealth);
    return {
      'action': 'interfaces',
      'interfaceId': 'data.interface_catalog',
      'provider': 'local',
      'providerId': 'local',
      'capabilityId': 'local.data.interface_catalog',
      'cacheStatus': 'local-evidence',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'data_interface_catalog',
      'canonicalTable': 'finance_data_interface_catalog',
      'readbackAction': 'interfaces',
      'filters': {
        'category': normalizedCategory,
        'provider': requestedProvider?.name,
        'health': normalizedHealth,
        'limit': boundedLimit,
      },
      'summary': {
        'interfaces': rows.length,
        'categories': rows
            .map((row) => row['category'] as String? ?? 'other')
            .toSet()
            .length,
        'ready': rows.where((row) => row['health'] == 'ready').length,
        'attention': rows.where((row) => row['health'] == 'attention').length,
        'gaps': rows.where((row) => row['health'] == 'gap').length,
      },
      'interfaces': rows
          .take(boundedLimit)
          .map(
            (row) => {
              'interfaceId': row['interfaceId'],
              'label': row['label'],
              'category': row['category'],
              'purpose': row['purpose'],
              'canonicalSchema': row['canonicalSchema'],
              'canonicalTables': row['canonicalTables'],
              'queryActions': row['queryActions'],
              'supportedProviders': row['supportedProviders'],
              'gatedProviders': row['gatedProviders'],
              'outputOnlyProviders': row['outputOnlyProviders'],
              'persistencePolicy': row['persistencePolicy'],
              'unknownSchemaPolicy': row['unknownSchemaPolicy'],
              'health': row['health'],
              'localRows': row['localRows'],
              'latestSourceTime': row['latestSourceTime'],
              'nextAction': row['nextAction'],
            },
          )
          .toList(),
      'tip':
          'Use interface_describe with interfaceId for the full contract, then interface_availability before provider retries or direct diagnostics.',
    };
  }

  Map<String, dynamic> interfaceDescribe(String interfaceId) {
    final requestedInterfaceId = interfaceId;
    interfaceId = _canonicalInterfaceId(interfaceId);
    final definition = _contract.getInterface(interfaceId);
    if (definition == null) {
      final customStrategy = _customStrategyInterfaceDescribe(
        requestedInterfaceId,
        interfaceId,
      );
      if (customStrategy != null) return customStrategy;
      final outputOnly = _outputOnlyInterfaceById(interfaceId);
      if (outputOnly != null) return _outputOnlyInterfaceDescribe(outputOnly);
      throw ArgumentError('Unknown interfaceId: $interfaceId');
    }
    final reusable = _dataManager.reusableSummary();
    final apiSummaries = {
      for (final item in ApiStats.instance.getSummary())
        item.source: {
          'source': item.source,
          'totalRequests': item.totalRequests,
          'successCount': item.successCount,
          'failCount': item.failCount,
          'failRate': item.failRate,
          'avgLatencyMs': item.avgLatencyMs,
          'p95LatencyMs': item.p95LatencyMs,
          'lastRequest': item.lastRequest?.toIso8601String(),
          'lastError': item.lastError,
          'lastFailureClass': item.lastFailureClass,
        },
    };
    final row = _interfaceHealth(definition, reusable, apiSummaries);
    return {
      'action': 'interface_describe',
      'interfaceId': definition.id,
      if (requestedInterfaceId != definition.id)
        'requestedInterfaceId': requestedInterfaceId,
      'provider': 'local',
      'providerId': 'local',
      'capabilityId': 'local.data.interface_describe',
      'cacheStatus': 'local-evidence',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'data_interface_contract',
      'canonicalTable': 'finance_data_interface_contract',
      'readbackAction': 'interface_describe',
      'contract': {
        'id': definition.id,
        'label': definition.label,
        'category': row['category'],
        'canonicalSchema': definition.canonicalSchema,
        'canonicalTables': definition.dataStoreTables,
        'queryActions': definition.queryActions,
        'params': definition.params,
        'freshnessPolicy': definition.freshnessPolicy,
      },
      'health': row,
      'tip':
          'Use interface_availability with the same interfaceId to decide whether local rows are already reusable or a provider refresh is needed.',
    };
  }

  Map<String, dynamic>? _customStrategyInterfaceDescribe(
    String requestedInterfaceId,
    String interfaceId,
  ) {
    if (!interfaceId.startsWith('custom_strategy_')) return null;
    const actions = {
      'custom_strategy_help',
      'custom_strategy_validate',
      'custom_strategy_backtest',
      'custom_strategy_observe',
      'custom_strategy_fund_backtest',
      'custom_strategy_rank',
      'custom_strategy_save',
      'custom_strategy_list',
      'custom_strategy_compare',
      'custom_strategy_run',
    };
    if (!actions.contains(interfaceId)) return null;
    return {
      'action': 'interface_describe',
      'interfaceId': interfaceId,
      'requestedInterfaceId': requestedInterfaceId,
      'category': 'strategy',
      'providerMode': 'local-engine',
      'cacheStatus': 'not-market-data',
      'canonicalSchema': 'strategy_spec',
      'supportedActions': actions.toList(),
      'description':
          'Custom strategy actions are MarketData strategy-engine actions, not finance data provider interfaces.',
      if (interfaceId == 'custom_strategy_rank')
        'outputEvidence': {
          'portfolioEvidence':
              'Selected-symbol aggregate metrics, correlation evidence, portfolio risk evidence, and portfolioBacktestEvidence.',
          'portfolioBacktestEvidence':
              'Evidence-only equal-weight selected-symbol portfolio return/drawdown series. It is not execution, rebalance approval, or a trade ledger.',
          'rebalanceDraft':
              'Top-N target-weight draft for watchlist/monitor/trade-preparation provenance. It must not place orders or mutate holdings.',
        },
      'workflow':
          'Use custom_strategy_help, then custom_strategy_validate. If validation status is rejected, report unsupported parts and stop; do not backtest, save, or create proxy rules unless the user explicitly asks for a separate proxy redesign.',
    };
  }

  Map<String, dynamic> interfaceAvailability(
    String interfaceId, {
    String? provider,
    String? providerMode,
  }) {
    final requestedInterfaceId = interfaceId;
    interfaceId = _canonicalInterfaceId(interfaceId);
    final definition = _contract.getInterface(interfaceId);
    if (definition == null) {
      final outputOnly = _outputOnlyInterfaceById(interfaceId);
      if (outputOnly != null) {
        return _outputOnlyInterfaceAvailability(
          outputOnly,
          provider: provider,
          providerMode: providerMode,
        );
      }
      throw ArgumentError('Unknown interfaceId: $interfaceId');
    }
    final reusable = _dataManager.reusableSummary();
    final apiSummaries = {
      for (final item in ApiStats.instance.getSummary())
        item.source: {
          'source': item.source,
          'totalRequests': item.totalRequests,
          'successCount': item.successCount,
          'failCount': item.failCount,
          'failRate': item.failRate,
          'avgLatencyMs': item.avgLatencyMs,
          'p95LatencyMs': item.p95LatencyMs,
          'lastRequest': item.lastRequest?.toIso8601String(),
          'lastError': item.lastError,
          'lastFailureClass': item.lastFailureClass,
        },
    };
    final row = _interfaceHealth(definition, reusable, apiSummaries);
    final requestedProvider = _normalizeSupportProvider(provider);
    final constraint = DataApiProviderConstraint(
      provider: requestedProvider,
      providerMode: _normalizeProviderMode(providerMode),
    );
    final registered = _contract.registeredCapabilities(
      definition.id,
      constraint: constraint,
    );
    final eligible = _contract.eligibleCapabilities(
      definition.id,
      constraint: constraint,
    );
    final runtimeReport = loadRuntimeLiveStatusReport(_dataManager.basePath);
    final runtimeEligible = _runtimeEligibleCapabilities(
      definition.id,
      eligible,
      runtimeReport,
      allowDegraded: constraint.allowDegraded,
    );
    final runtimeBlocked = registered
        .map((capability) {
          final decision = _runtimeRouteDecision(
            definition.id,
            capability,
            runtimeReport,
            allowDegraded: constraint.allowDegraded,
          );
          if (decision.eligible) return null;
          return {
            ..._runtimeCapabilitySummary(capability),
            'routeState': decision.routeState,
            'routeReason': decision.reason,
            'evidenceStatus': decision.evidenceStatus,
            'liveValidationState': decision.liveValidationState,
            'liveFailureClass': decision.liveFailureClass,
            'temporaryBlockUntil': decision.temporaryBlockUntil,
            'routeBlockScope': decision.routeBlockScope,
          };
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final localRows = (row['localRows'] as int?) ?? 0;
    final cacheStatus = definition.dataStoreTables.isEmpty
        ? 'none'
        : localRows > 0
        ? 'local-hit'
        : 'local-miss';
    final routeReadiness = runtimeEligible.isNotEmpty
        ? runtimeEligible.first['routeState'] == 'validated'
              ? 'allowed'
              : 'degraded'
        : localRows > 0
        ? 'cached-only'
        : 'blocked';
    return {
      'action': 'interface_availability',
      'interfaceId': definition.id,
      if (requestedInterfaceId != definition.id)
        'requestedInterfaceId': requestedInterfaceId,
      'provider': requestedProvider?.name ?? 'local',
      'providerId': requestedProvider?.name ?? 'local',
      'capabilityId': 'local.data.interface_availability',
      'cacheStatus': cacheStatus,
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'canonicalSchema': 'data_interface_availability',
      'canonicalTable': 'finance_data_interface_availability',
      'readbackAction': 'interface_availability',
      'request': {
        'provider': requestedProvider?.name,
        'providerMode': constraint.providerMode.name,
      },
      'availability': {
        'label': definition.label,
        'category': row['category'],
        'health': row['health'],
        'localRows': localRows,
        'latestSourceTime': row['latestSourceTime'],
        'queryActions': definition.queryActions,
        'freshnessPolicy': definition.freshnessPolicy,
        'supportedProviders': row['supportedProviders'],
        'gatedProviders': row['gatedProviders'],
        'outputOnlyProviders': row['outputOnlyProviders'],
        'recentFailures': row['recentFailures'],
        'lastFailureClass': row['lastFailureClass'],
        'nextAction': row['nextAction'],
        'routeReadiness': routeReadiness,
      },
      'registeredCapabilities': registered
          .map((capability) => _runtimeCapabilitySummary(capability))
          .toList(),
      'eligibleCapabilities': runtimeEligible,
      'blockedCapabilities': runtimeBlocked,
      'tip': localRows > 0
          ? 'Use the queryActions/readback path first; runtime routing will avoid blocked or unvalidated provider paths unless you explicitly move into diagnostics.'
          : 'No reusable local rows were found; use the governed fetch action only when interface availability shows a runtime-eligible provider path.',
    };
  }

  Map<String, dynamic> fetchTaskQueue({
    String? basePath,
    String? status,
    int limit = 20,
  }) {
    final engine = _queueEngine(basePath);
    final requestedStatus = _normalizeTaskStatus(status);
    final tasks = requestedStatus == null
        ? engine.list()
        : engine.list(status: requestedStatus);
    final ordered = tasks.reversed.take(limit).map(_taskRow).toList();
    final actionableFailures = ordered
        .where((row) => row['actionableFailure'] == true)
        .toList();
    final nonActionableEvidence = ordered
        .where((row) => row['nonActionableEvidence'] == true)
        .toList();
    final pendingOrRunning = tasks
        .where(
          (task) =>
              task.status == DataTaskStatus.pending ||
              task.status == DataTaskStatus.running,
        )
        .length;
    final failed = tasks
        .where((task) => task.status == DataTaskStatus.failed)
        .length;
    final cacheStatus = ordered.isEmpty ? 'cache-miss' : 'cache-hit';
    return {
      'action': 'fetch_status',
      'interfaceId': 'provider.fetch_task_queue',
      'provider': 'local',
      'providerId': 'local',
      'capabilityId': 'local.provider.fetch_task_queue',
      'cacheStatus': cacheStatus,
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': ordered.isEmpty
          ? 'cacheFirst read durable local data-task queue; no matching queued task rows were found'
          : 'cacheFirst read durable local data-task queue before any retry; reusable task rows were found',
      'canonicalSchema': 'fetch_task_queue',
      'canonicalTable': 'data_tasks',
      'readbackAction': 'fetch_status',
      'count': ordered.length,
      'summary': {
        'requestedStatus': requestedStatus?.name,
        'pendingOrRunning': pendingOrRunning,
        'failed': failed,
        'actionableFailures': actionableFailures.length,
        'nonActionableEvidence': nonActionableEvidence.length,
        'totalObserved': tasks.length,
      },
      'actionableFailures': actionableFailures,
      'nonActionableEvidence': nonActionableEvidence,
      'source': 'local data_tasks',
      'data': ordered,
    };
  }

  OutputOnlyApiInterface? _outputOnlyInterfaceById(String interfaceId) {
    for (final item in _outputOnlyContract.interfaces) {
      if (item.id == interfaceId) return item;
    }
    return null;
  }

  List<Map<String, dynamic>> _outputOnlyCatalogRows(
    FinanceProvider? requestedProvider,
  ) {
    return _outputOnlyContract.interfaces
        .map((definition) => _outputOnlyHealth(definition))
        .where((row) {
          if (requestedProvider == null) return true;
          final capabilities = (row['capabilities'] as List?) ?? const [];
          return capabilities.whereType<Map>().any(
            (capability) => capability['provider'] == requestedProvider.name,
          );
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _outputOnlyHealth(OutputOnlyApiInterface definition) {
    final capabilities = definition.capabilities
        .map(_outputOnlyCapabilityRow)
        .toList(growable: false);
    return {
      'interfaceId': definition.id,
      'label': definition.label,
      'category': _categoryForInterface(definition.id),
      'purpose':
          'Known output-only boundary. It is controlled and documented, but it is not a reusable canonical data workflow in this runtime.',
      'canonicalSchema': definition.schemaId,
      'canonicalTables': const <String>[],
      'queryActions': const <String>[],
      'supportedProviders': const <String>[],
      'gatedProviders': const <String>[],
      'outputOnlyProviders': capabilities
          .map((capability) => capability['provider'])
          .toList(growable: false),
      'capabilities': capabilities,
      'health': 'attention',
      'localRows': 0,
      'latestSourceTime': null,
      'recentFailures': 0,
      'unstableProviders': const <String>[],
      'nextAction':
          'Do not use this as normal reusable data. Use governed interfaces and readbacks first; use bounded diagnostics only outside normal workflow.',
      'persistencePolicy': definition.persistencePolicy,
      'unknownSchemaPolicy': definition.unknownSchemaPolicy,
    };
  }

  Map<String, dynamic> _outputOnlyInterfaceDescribe(
    OutputOnlyApiInterface definition,
  ) {
    final health = _outputOnlyHealth(definition);
    return {
      'action': 'interface_describe',
      'interfaceId': definition.id,
      'provider': 'local',
      'providerId': 'local',
      'capabilityId': 'local.data.interface_describe',
      'cacheStatus': 'not-cacheable',
      'cacheDecision':
          'output-only interface is controlled for bounded inspection but is not eligible for canonical persistence, cache reuse, or normal provider routing',
      'cacheMode': 'no-cache',
      'cachePolicyMode': 'outputOnly',
      'canonicalSchema': 'output_only_interface_contract',
      'canonicalTable': null,
      'readbackAction': 'interface_describe',
      'contract': {
        'id': definition.id,
        'label': definition.label,
        'category': _categoryForInterface(definition.id),
        'canonicalSchema': definition.schemaId,
        'canonicalTables': const <String>[],
        'queryActions': const <String>[],
        'params': const <String, dynamic>{},
        'freshnessPolicy': 'output-only; not a cache/readback workflow',
        'persistencePolicy': definition.persistencePolicy,
        'unknownSchemaPolicy': definition.unknownSchemaPolicy,
      },
      'health': health,
      'capabilities': health['capabilities'],
      'normalWorkflow': 'not-supported',
      'tip': definition.id == 'market.optimize_params'
          ? 'Use MarketData(action:"optimize_params") with symbols, strategy, period, and a small paramGrid. Do not query raw K-line files or run Script for this workflow.'
          : 'This interface is known and controlled, but mobile does not expose it as normal reusable data. Use governed interfaces, runtime_probe, or explicit WebFetch diagnostics outside normal data workflow.',
    };
  }

  Map<String, dynamic> _outputOnlyInterfaceAvailability(
    OutputOnlyApiInterface definition, {
    String? provider,
    String? providerMode,
  }) {
    final requestedProvider = _normalizeSupportProvider(provider);
    final allCapabilities = definition.capabilities;
    final matchingCapabilities = requestedProvider == null
        ? allCapabilities
        : allCapabilities
              .where(
                (capability) => capability.provider == requestedProvider.name,
              )
              .toList(growable: false);
    return {
      'action': 'interface_availability',
      'interfaceId': definition.id,
      'provider': requestedProvider?.name ?? 'local',
      'providerId': requestedProvider?.name ?? 'local',
      'capabilityId': 'local.data.interface_availability',
      'cacheStatus': 'not-cacheable',
      'cacheDecision':
          'output-only interface availability is a routing guard; use governed interfaces/readbacks for normal reusable data',
      'cacheMode': 'no-cache',
      'cachePolicyMode': 'outputOnly',
      'canonicalSchema': 'data_interface_availability',
      'canonicalTable': 'finance_data_interface_availability',
      'readbackAction': 'interface_availability',
      'request': {
        'provider': requestedProvider?.name,
        'providerMode': _normalizeProviderMode(providerMode).name,
      },
      'availability': {
        'label': definition.label,
        'category': _categoryForInterface(definition.id),
        'health': 'attention',
        'localRows': 0,
        'latestSourceTime': null,
        'queryActions': const <String>[],
        'freshnessPolicy': 'output-only; not a cache/readback workflow',
        'supportedProviders': const <String>[],
        'gatedProviders': const <String>[],
        'outputOnlyProviders': matchingCapabilities
            .map((capability) => capability.provider)
            .toList(growable: false),
        'recentFailures': 0,
        'lastFailureClass': null,
        'nextAction':
            'Do not route normal workflow to this output-only diagnostic surface. Use governed interfaces and readbacks first.',
        'routeReadiness': 'blocked',
      },
      'registeredCapabilities': matchingCapabilities
          .map(_outputOnlyCapabilityRow)
          .toList(growable: false),
      'eligibleCapabilities': const <Map<String, dynamic>>[],
      'blockedCapabilities': matchingCapabilities
          .map(
            (capability) => {
              ..._outputOnlyCapabilityRow(capability),
              'routeState': 'blocked',
              'routeReason':
                  'Output-only diagnostic surface is not executable as normal mobile data workflow.',
            },
          )
          .toList(growable: false),
      'tip':
          'Known output-only boundary. Keep it out of normal provider routing unless a future batch promotes it with normalizer, persistence, readback, provenance, and tests.',
    };
  }

  Map<String, dynamic> _outputOnlyCapabilityRow(
    OutputOnlyApiCapability capability,
  ) {
    return {
      'capabilityId': capability.id,
      'id': capability.id,
      'interfaceId': capability.interfaceId,
      'provider': capability.provider,
      'status': capability.status,
      'priority': capability.priority,
      'schemaId': capability.schemaId,
      'adapter': capability.adapter,
      'normalizer': capability.normalizer,
      'persistencePolicy': capability.persistencePolicy,
    };
  }

  List<Map<String, dynamic>> _globalYfinanceCoverage(
    Map<String, dynamic> coverage,
  ) {
    const specs = <Map<String, String?>>[
      {
        'key': 'yfinance_profile_fields',
        'dataset': 'profile',
        'interfaceId': 'global.company_profile',
        'canonicalSchema': 'yfinance_profile_fields',
        'readbackAction': 'query_global_company_profile',
      },
      {
        'key': 'yfinance_statement_items',
        'dataset': 'statements',
        'interfaceId': 'global.financial_statements',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_financial_statements',
      },
      {
        'key': 'yfinance_income_statement',
        'dataset': 'income_statement',
        'interfaceId': 'global.income_statement',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_income_statement',
      },
      {
        'key': 'yfinance_balance_sheet',
        'dataset': 'balance_sheet',
        'interfaceId': 'global.balance_sheet',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_balance_sheet',
      },
      {
        'key': 'yfinance_cash_flow',
        'dataset': 'cash_flow',
        'interfaceId': 'global.cash_flow',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_cash_flow',
      },
      {
        'key': 'yfinance_earnings_calendar',
        'dataset': 'earnings_calendar',
        'interfaceId': 'global.earnings_calendar',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_earnings_calendar',
      },
      {
        'key': 'yfinance_earnings_history',
        'dataset': 'earnings_history',
        'interfaceId': 'global.earnings_history',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_earnings_history',
      },
      {
        'key': 'yfinance_earnings_estimates',
        'dataset': 'earnings_estimates',
        'interfaceId': 'global.earnings_estimates',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_earnings_estimates',
      },
      {
        'key': 'yfinance_eps_revisions',
        'dataset': 'eps_revisions',
        'interfaceId': 'global.eps_revisions',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_eps_revisions',
      },
      {
        'key': 'yfinance_eps_trend',
        'dataset': 'eps_trend',
        'interfaceId': 'global.eps_trend',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_eps_trend',
      },
      {
        'key': 'yfinance_quarterly_financial_statements',
        'dataset': 'quarterly_financial_statements',
        'interfaceId': 'global.quarterly_financial_statements',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_quarterly_financial_statements',
      },
      {
        'key': 'yfinance_quarterly_income_statement',
        'dataset': 'quarterly_income_statement',
        'interfaceId': 'global.quarterly_income_statement',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_quarterly_income_statement',
      },
      {
        'key': 'yfinance_quarterly_balance_sheet',
        'dataset': 'quarterly_balance_sheet',
        'interfaceId': 'global.quarterly_balance_sheet',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_quarterly_balance_sheet',
      },
      {
        'key': 'yfinance_quarterly_cash_flow',
        'dataset': 'quarterly_cash_flow',
        'interfaceId': 'global.quarterly_cash_flow',
        'canonicalSchema': 'yfinance_statement_items',
        'readbackAction': 'query_global_quarterly_cash_flow',
      },
      {
        'key': 'yfinance_recommendations',
        'dataset': 'recommendations',
        'interfaceId': 'global.recommendations',
        'canonicalSchema': 'yfinance_recommendations',
        'readbackAction': 'query_global_recommendations',
      },
      {
        'key': 'yfinance_upgrade_downgrade_events',
        'dataset': 'upgrade_downgrade_events',
        'interfaceId': 'global.upgrade_downgrade_events',
        'canonicalSchema': 'yfinance_recommendations',
        'readbackAction': 'query_global_upgrade_downgrade_events',
      },
      {
        'key': 'yfinance_news',
        'dataset': 'news',
        'interfaceId': 'global.finance_news',
        'canonicalSchema': 'yfinance_news',
        'readbackAction': 'query_global_finance_news',
      },
      {
        'key': 'yfinance_option_expiries',
        'dataset': 'option_expiries',
        'interfaceId': 'option.expiry_calendar',
        'canonicalSchema': 'yfinance_option_expiries',
        'readbackAction': 'query_option_expiry_calendar',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'options',
        'interfaceId': 'option.quote',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_quote',
      },
      {
        'key': 'kline_daily',
        'dataset': 'option_daily_kline',
        'interfaceId': 'option.daily_kline',
        'canonicalSchema': 'kline_daily',
        'readbackAction': 'query_option_daily_kline',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'options',
        'interfaceId': 'option.contract_list',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_contract_list',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'option_open_interest',
        'interfaceId': 'option.open_interest',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_open_interest',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'option_volume',
        'interfaceId': 'option.volume',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_volume',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'option_implied_volatility',
        'interfaceId': 'option.implied_volatility',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_implied_volatility',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'option_moneyness',
        'interfaceId': 'option.moneyness',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_moneyness',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'option_bid_ask_spread',
        'interfaceId': 'option.bid_ask_spread',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_bid_ask_spread',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'option_price_change',
        'interfaceId': 'option.price_change',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_price_change',
      },
      {
        'key': 'yfinance_option_contracts',
        'dataset': 'option_trade_recency',
        'interfaceId': 'option.trade_recency',
        'canonicalSchema': 'yfinance_option_contracts',
        'readbackAction': 'query_option_trade_recency',
      },
      {
        'key': 'yfinance_corporate_actions',
        'dataset': 'actions',
        'interfaceId': 'global.corporate_actions',
        'canonicalSchema': 'yfinance_corporate_actions',
        'readbackAction': 'query_global_corporate_actions',
      },
      {
        'key': 'yfinance_dividends',
        'dataset': 'dividends',
        'interfaceId': 'global.dividends',
        'canonicalSchema': 'yfinance_corporate_actions',
        'readbackAction': 'query_global_dividends',
      },
      {
        'key': 'yfinance_capital_gains',
        'dataset': 'capital_gains',
        'interfaceId': 'global.capital_gains',
        'canonicalSchema': 'yfinance_corporate_actions',
        'readbackAction': 'query_global_capital_gains',
      },
      {
        'key': 'yfinance_splits',
        'dataset': 'splits',
        'interfaceId': 'global.stock_splits',
        'canonicalSchema': 'yfinance_corporate_actions',
        'readbackAction': 'query_global_stock_splits',
      },
      {
        'key': 'yfinance_holders',
        'dataset': 'holders',
        'interfaceId': 'global.holders',
        'canonicalSchema': 'yfinance_holders',
        'readbackAction': 'query_global_holders',
      },
      {
        'key': 'yfinance_major_holders',
        'dataset': 'major_holders',
        'interfaceId': 'global.major_holders',
        'canonicalSchema': 'yfinance_holders',
        'readbackAction': 'query_global_major_holders',
      },
      {
        'key': 'yfinance_institutional_holders',
        'dataset': 'institutional_holders',
        'interfaceId': 'global.institutional_holders',
        'canonicalSchema': 'yfinance_holders',
        'readbackAction': 'query_global_institutional_holders',
      },
      {
        'key': 'yfinance_mutual_fund_holders',
        'dataset': 'mutual_fund_holders',
        'interfaceId': 'global.mutual_fund_holders',
        'canonicalSchema': 'yfinance_holders',
        'readbackAction': 'query_global_mutual_fund_holders',
      },
      {
        'key': 'yfinance_insider_transactions',
        'dataset': 'insiders',
        'interfaceId': 'global.insider_transactions',
        'canonicalSchema': 'yfinance_insider_transactions',
        'readbackAction': 'query_global_insider_transactions',
      },
    ];
    return specs.map((spec) {
      final row = coverage[spec['key']] as Map<String, dynamic>? ?? const {};
      final count = _coverageRows(row);
      return {
        'interfaceId': spec['interfaceId'],
        'provider': 'yahoo',
        'capabilityId': 'yfinance.${spec['interfaceId']}',
        'dataset': spec['dataset'],
        'canonicalSchema': spec['canonicalSchema'],
        'canonicalTable': spec['canonicalSchema'],
        'readbackAction': spec['readbackAction'] ?? 'query_yfinance',
        'cacheStatus': count > 0 ? 'local-hit' : 'local-miss',
        'count': count,
        if (row['latest'] != null) 'latest': row['latest'],
        if (row['sources'] != null) 'sources': row['sources'],
      };
    }).toList();
  }

  int _coverageRows(Map<String, dynamic> row) {
    final value = row['count'] ?? row['rows'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  bool _isAshareSymbol(String symbol) {
    return RegExp(r'^\d{6}(\.(SH|SZ|BJ))?$').hasMatch(symbol.toUpperCase());
  }

  String _canonicalInterfaceId(String interfaceId) {
    final normalized = interfaceId.trim();
    return switch (normalized) {
      'stock.kline' ||
      'stock.daily' ||
      'stock.daily_ohlcv' => 'stock.daily_kline',
      'index.kline' ||
      'index.daily' ||
      'index.daily_ohlcv' => 'index.daily_kline',
      _ => normalized,
    };
  }

  DataTaskEngine _queueEngine(String? basePath) {
    if (_dataTaskEngine != null) return _dataTaskEngine;
    final trimmed = (basePath ?? '').trim();
    if (trimmed.isEmpty) {
      throw StateError(
        'fetch_status requires ToolContext.basePath or an injected DataTaskEngine.',
      );
    }
    final engine = DataTaskEngine(basePath: trimmed);
    engine.load();
    return engine;
  }

  DataTaskStatus? _normalizeTaskStatus(String? status) {
    final value = status?.trim().toLowerCase();
    return switch (value) {
      null || '' || 'all' => null,
      'pending' => DataTaskStatus.pending,
      'running' => DataTaskStatus.running,
      'completed' || 'done' => DataTaskStatus.completed,
      'failed' => DataTaskStatus.failed,
      'cancelled' || 'canceled' => DataTaskStatus.cancelled,
      _ => null,
    };
  }

  Map<String, dynamic> _taskRow(DataTask task) {
    final actionableFailure = _isActionableDataTaskFailure(task);
    final nonActionableEvidence =
        task.status == DataTaskStatus.failed && !actionableFailure;
    return {
      'taskId': task.id,
      'taskType': task.type,
      'status': task.status.name,
      'progress': task.progress,
      'params': task.params,
      'result': task.result,
      'error': task.error,
      'actionableFailure': actionableFailure,
      'nonActionableEvidence': nonActionableEvidence,
      'nextAction': _dataTaskNextAction(task, actionableFailure),
      'createdAt': task.createdAt.toUtc().toIso8601String(),
      'completedAt': task.completedAt?.toUtc().toIso8601String(),
    };
  }

  bool _isActionableDataTaskFailure(DataTask task) {
    if (task.status != DataTaskStatus.failed) return false;
    final error = (task.error ?? '').toLowerCase();
    if (_isStaleOrRecoveredTaskError(error)) return false;
    if (error.startsWith('code required') && !_hasTaskCodeLikeParam(task)) {
      return false;
    }
    return true;
  }

  bool _isStaleOrRecoveredTaskError(String error) =>
      error.contains(
        'manual data-feed verification recovered stale active task',
      ) ||
      error.contains('manual verification interrupted before completion') ||
      error.contains('stale active task recovered on startup') ||
      error.contains('recovered stale active task');

  bool _hasTaskCodeLikeParam(DataTask task) {
    for (final key in const ['code', 'symbol', 'symbols', 'codes']) {
      final value = task.params[key];
      if (value is String && value.trim().isNotEmpty) return true;
      if (value is Iterable && value.isNotEmpty) return true;
    }
    return false;
  }

  String _dataTaskNextAction(DataTask task, bool actionableFailure) {
    if (task.status == DataTaskStatus.pending ||
        task.status == DataTaskStatus.running) {
      return 'Wait for current task evidence before enqueueing another run.';
    }
    if (task.status == DataTaskStatus.completed) {
      return 'Use local query/readback before enqueueing another provider run.';
    }
    if (task.status == DataTaskStatus.cancelled) {
      return 'Task was cancelled; inspect workflow intent before retrying.';
    }
    final error = (task.error ?? '').toLowerCase();
    if (_isStaleOrRecoveredTaskError(error)) {
      return 'No provider retry is needed for this stale recovered task marker; inspect current fetch_status/data_health first.';
    }
    if (error.startsWith('code required') && !_hasTaskCodeLikeParam(task)) {
      return 'Add task scope/code parameters before running this task again.';
    }
    if (actionableFailure) {
      return 'Inspect data_health failureActionQueue and provider evidence before retrying this task.';
    }
    return 'Inspect fetch_status and data_health before deciding whether retry is needed.';
  }

  Map<String, dynamic> dataHealth({
    String section = 'summary',
    int limit = 20,
  }) {
    final boundedLimit = limit.clamp(1, 100);
    final reusable = _dataManager.reusableSummary();
    final apiSummaries = {
      for (final item in ApiStats.instance.getSummary())
        item.source: {
          'source': item.source,
          'totalRequests': item.totalRequests,
          'successCount': item.successCount,
          'failCount': item.failCount,
          'failRate': item.failRate,
          'avgLatencyMs': item.avgLatencyMs,
          'p95LatencyMs': item.p95LatencyMs,
          'lastRequest': item.lastRequest?.toIso8601String(),
          'lastError': item.lastError,
          'lastFailureClass': item.lastFailureClass,
        },
    };
    final interfaces =
        _contract.interfaces
            .map(
              (definition) =>
                  _interfaceHealth(definition, reusable, apiSummaries),
            )
            .toList()
          ..sort(_compareInterfaceHealth);
    final providers = _providerHealth(apiSummaries)..sort(_compareProvider);
    final runtimeReport = loadRuntimeLiveStatusReport(_dataManager.basePath);
    final queueRows = _capabilityQueueRows(interfaces, runtimeReport)
      ..sort(_compareProviderGap);
    final credentialValidated = queueRows
        .where(_isCredentialValidatedRow)
        .toList();
    final credentialActivations = queueRows
        .where(_isCredentialActivationRow)
        .where((row) => !_isCredentialValidatedRow(row))
        .toList();
    final policyDisabled = queueRows.where(_isPolicyDisabledRow).toList();
    final providerGaps = queueRows
        .where(
          (row) =>
              !_isCredentialActivationRow(row) && !_isPolicyDisabledRow(row),
        )
        .toList();
    final failureActions = _failureActionQueue(interfaces, providers)
      ..sort(_compareFailureAction);
    final normalizedSection = _normalizeSection(section);
    final payload = <String, dynamic>{
      'action': 'data_health',
      'section': normalizedSection,
      'summary': {
        'interfaces': interfaces.length,
        'providers': FinanceProvider.values.length,
        'ready': interfaces.where((row) => row['health'] == 'ready').length,
        'attention': interfaces
            .where((row) => row['health'] == 'attention')
            .length,
        'gaps': interfaces.where((row) => row['health'] == 'gap').length,
        'recentProviderFailures': providers.fold<int>(
          0,
          (sum, row) => sum + (row['recentFailures'] as int),
        ),
        'providerGapRows': providerGaps.length,
        'credentialActivationRows': credentialActivations.length,
        'credentialValidatedRows': credentialValidated.length,
        'policyDisabledRows': policyDisabled.length,
        'credentialActivationLiveObserved': credentialActivations
            .where((row) => row['liveStatus'] == 'passed')
            .length,
        'credentialValidatedLiveObserved': credentialValidated
            .where((row) => row['liveStatus'] == 'passed')
            .length,
        'providerGapClassCounts': _providerGapClassCounts(providerGaps),
        'credentialActivationClassCounts': _providerGapClassCounts(
          credentialActivations,
        ),
        'policyDisabledClassCounts': _providerGapClassCounts(policyDisabled),
        'contractProblems': _contract.validate().length,
      },
      'provenance': {
        'interfaceId': 'data.health',
        'providerId': 'local',
        'provider': 'local',
        'capabilityId': 'local.data_health',
        'providerMode': 'local-evidence',
        'cacheStatus': 'local-evidence',
        'canonicalSchema': 'data_health_report',
        'canonicalTable': 'finance_data_health_report',
        'readbackAction': 'data_health',
        'failureClass': null,
        'source':
            'MarketData reusable summary, data API contract, and ApiStats recent provider log',
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      },
    };
    if (normalizedSection == 'interfaces' || normalizedSection == 'all') {
      payload['interfaces'] = interfaces.take(boundedLimit).toList();
    }
    if (normalizedSection == 'providers' || normalizedSection == 'all') {
      payload['providers'] = providers.take(boundedLimit).toList();
    }
    if (normalizedSection == 'gaps' || normalizedSection == 'all') {
      payload['providerGapQueue'] = providerGaps.take(boundedLimit).toList();
      payload['providerGaps'] = providerGaps.take(boundedLimit).toList();
      payload['credentialActivationQueue'] = credentialActivations
          .take(boundedLimit)
          .toList();
      payload['credentialActivations'] = credentialActivations
          .take(boundedLimit)
          .toList();
      payload['credentialValidatedQueue'] = credentialValidated
          .take(boundedLimit)
          .toList();
      payload['credentialValidated'] = credentialValidated
          .take(boundedLimit)
          .toList();
      payload['policyDisabledQueue'] = policyDisabled
          .take(boundedLimit)
          .toList();
      payload['policyDisabled'] = policyDisabled.take(boundedLimit).toList();
    }
    if (normalizedSection == 'failures' || normalizedSection == 'all') {
      payload['failureActionQueue'] = failureActions
          .take(boundedLimit)
          .toList();
      payload['failureActions'] = failureActions.take(boundedLimit).toList();
    }
    if (normalizedSection == 'summary') {
      payload['attentionInterfaces'] = interfaces
          .where((row) => row['health'] != 'ready')
          .take(boundedLimit)
          .toList();
      payload['providerAttention'] = providers
          .where((row) => row['health'] != 'ready')
          .take(boundedLimit)
          .toList();
      payload['providerGapQueue'] = providerGaps.take(boundedLimit).toList();
      payload['providerGaps'] = providerGaps.take(boundedLimit).toList();
      payload['credentialActivationQueue'] = credentialActivations
          .take(boundedLimit)
          .toList();
      payload['credentialActivations'] = credentialActivations
          .take(boundedLimit)
          .toList();
      payload['credentialValidatedQueue'] = credentialValidated
          .take(boundedLimit)
          .toList();
      payload['credentialValidated'] = credentialValidated
          .take(boundedLimit)
          .toList();
      payload['policyDisabledQueue'] = policyDisabled
          .take(boundedLimit)
          .toList();
      payload['policyDisabled'] = policyDisabled.take(boundedLimit).toList();
      payload['failureActionQueue'] = failureActions
          .take(boundedLimit)
          .toList();
      payload['failureActions'] = failureActions.take(boundedLimit).toList();
    }
    return overlayDataHealthWithRuntimeEvidence(
      payload,
      loadRuntimeLiveStatusReport(_dataManager.basePath),
    );
  }

  FinanceProvider? _normalizeSupportProvider(String? provider) {
    if (provider == null || provider.trim().isEmpty) return null;
    final providers = const ProviderPolicy().normalizeProviders(provider);
    return providers.isEmpty ? null : providers.first;
  }

  DataApiProviderMode _normalizeProviderMode(String? providerMode) {
    return switch (providerMode?.trim().toLowerCase() ?? '') {
      'preferred' => DataApiProviderMode.preferred,
      'strict' => DataApiProviderMode.strict,
      _ => DataApiProviderMode.auto,
    };
  }

  Map<String, dynamic> _interfaceHealth(
    DataApiInterfaceDefinition definition,
    Map<String, dynamic> reusable,
    Map<String, Map<String, dynamic>> apiSummaries,
  ) {
    final supported = <String>[];
    final gated = <String>[];
    final outputOnly = <String>[];
    final unstable = <String>[];
    final disabled = <String>[];
    final notSupported = <String>[];
    var credentialGatedReusable = false;
    var recentFailures = 0;
    String? lastFailure;
    String? lastFailureClass;
    final declaredProviders = <FinanceProvider>{};
    for (final capability in definition.capabilities) {
      final provider = capability.provider.name;
      declaredProviders.add(capability.provider);
      switch (capability.status) {
        case DataApiCapabilityStatus.supported:
        case DataApiCapabilityStatus.globalOnly:
          supported.add(provider);
        case DataApiCapabilityStatus.credentialGated:
        case DataApiCapabilityStatus.quotaGated:
          gated.add(provider);
          credentialGatedReusable =
              credentialGatedReusable ||
              (capability.normalizer != null &&
                  capability.canonicalTable != null);
        case DataApiCapabilityStatus.outputOnly:
          outputOnly.add(provider);
        case DataApiCapabilityStatus.transportUnstable:
          unstable.add(provider);
        case DataApiCapabilityStatus.disabled:
          disabled.add(provider);
        case DataApiCapabilityStatus.notSupported:
          notSupported.add(provider);
      }
      final api = apiSummaries[_apiStatsSource(capability.provider)];
      final failures = (api?['failCount'] as int?) ?? 0;
      if (failures > 0) {
        recentFailures += failures;
        lastFailure ??= api?['lastError'] as String?;
      }
    }
    lastFailureClass = definition.capabilities
        .map((capability) => apiSummaries[_apiStatsSource(capability.provider)])
        .map((api) => api?['lastFailureClass'] as String?)
        .whereType<String>()
        .firstOrNull;
    final localRows = definition.dataStoreTables.fold<int>(
      0,
      (sum, table) => sum + _tableRows(reusable[table]),
    );
    final latestSourceTime = _latest(
      definition.dataStoreTables.map((table) => _tableLatest(reusable[table])),
    );
    final implicitNotSupportedProviderDetails = FinanceProvider.values
        .where((provider) => !declaredProviders.contains(provider))
        .map(
          (provider) => {
            'provider': provider.name,
            'status': 'not-supported',
            'capabilityId': null,
            'reason': _implicitNotSupportedReason(provider, definition.id),
          },
        )
        .toList();
    final health = recentFailures > 0 || unstable.isNotEmpty
        ? 'attention'
        : supported.isEmpty
        ? 'gap'
        : 'ready';
    return {
      'interfaceId': definition.id,
      'label': definition.label,
      'category': _categoryForInterface(definition.id),
      'purpose': definition.label,
      'canonicalSchema': definition.canonicalSchema,
      'canonicalTables': definition.dataStoreTables,
      'queryActions': definition.queryActions,
      'freshnessPolicy': definition.freshnessPolicy,
      'supportedProviders': supported,
      'gatedProviders': gated,
      'outputOnlyProviders': outputOnly,
      'unstableProviders': unstable,
      'disabledProviders': disabled,
      'notSupportedProviders': notSupported,
      'implicitNotSupportedProviderDetails':
          implicitNotSupportedProviderDetails,
      'localRows': localRows,
      'latestSourceTime': latestSourceTime,
      'recentFailures': recentFailures,
      'lastFailure': lastFailure,
      'lastFailureClass': lastFailureClass,
      'health': health,
      'nextAction': _nextAction(
        health: health,
        recentFailures: recentFailures,
        lastFailureClass: lastFailureClass,
        supportedProviders: supported,
        gatedProviders: gated,
        outputOnlyProviders: outputOnly,
        unstableProviders: unstable,
        credentialGatedReusable: credentialGatedReusable,
      ),
      'capabilities': definition.capabilities
          .map(
            (capability) => {
              'capabilityId': capability.id,
              'provider': capability.provider.name,
              'status': _statusName(capability.status),
              'priority': capability.priority,
              'adapter': capability.adapter,
              'normalizer': capability.normalizer,
              'canonicalTable': capability.canonicalTable,
              'probeId': capability.probeId,
              'reason': capability.reason,
            },
          )
          .toList(),
    };
  }

  String _implicitNotSupportedReason(
    FinanceProvider provider,
    String interfaceId,
  ) {
    return 'No ${provider.name} provider capability is registered for '
        '$interfaceId; keep this implicit not-supported provider out of '
        'routing unless a provider-specific adapter, normalizer, canonical '
        'persistence, readback, and evidence are added.';
  }

  List<Map<String, dynamic>> _providerHealth(
    Map<String, Map<String, dynamic>> apiSummaries,
  ) {
    return FinanceProvider.values.map((provider) {
      var supported = 0;
      var gated = 0;
      var outputOnly = 0;
      var unstable = 0;
      var disabled = 0;
      var notSupported = 0;
      for (final definition in _contract.interfaces) {
        final caps = definition.capabilities.where(
          (capability) => capability.provider == provider,
        );
        for (final capability in caps) {
          switch (capability.status) {
            case DataApiCapabilityStatus.supported:
            case DataApiCapabilityStatus.globalOnly:
              supported += 1;
            case DataApiCapabilityStatus.credentialGated:
            case DataApiCapabilityStatus.quotaGated:
              gated += 1;
            case DataApiCapabilityStatus.outputOnly:
              outputOnly += 1;
            case DataApiCapabilityStatus.transportUnstable:
              unstable += 1;
            case DataApiCapabilityStatus.disabled:
              disabled += 1;
            case DataApiCapabilityStatus.notSupported:
              notSupported += 1;
          }
        }
      }
      final api = apiSummaries[_apiStatsSource(provider)];
      final recentFailures = (api?['failCount'] as int?) ?? 0;
      final lastFailure = api?['lastError'] as String?;
      final health = recentFailures > 0 || unstable > 0
          ? 'attention'
          : supported > 0
          ? 'ready'
          : 'gap';
      return {
        'provider': provider.name,
        'supported': supported,
        'gated': gated,
        'outputOnly': outputOnly,
        'unstable': unstable,
        'disabled': disabled,
        'notSupported': notSupported,
        'recentFailures': recentFailures,
        'lastFailure': lastFailure,
        'lastFailureClass': api?['lastFailureClass'] as String?,
        'apiStats': api,
        'health': health,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _capabilityQueueRows(
    List<Map<String, dynamic>> interfaces,
    Map<String, dynamic>? runtimeReport,
  ) {
    return interfaces.expand((definition) {
      final capabilities = (definition['capabilities'] as List?) ?? const [];
      return capabilities
          .whereType<Map>()
          .where((capability) {
            final status = capability['status'] as String? ?? '';
            return status != 'supported' &&
                status != 'global-only' &&
                status != 'not-supported';
          })
          .map((capability) {
            final status = capability['status'] as String? ?? '';
            final routeWiringStatus = status == 'output-only'
                ? 'normalizer-readback-required'
                : null;
            final routeImplementationRequired = status == 'output-only';
            final gapClass = _gapClassFor(
              status,
              routeWiringStatus,
              routeImplementationRequired,
            );
            final nextAction = _capabilityNextAction(
              status,
              capability['reason'] as String?,
              normalizer: capability['normalizer'] as String?,
              canonicalTable: capability['canonicalTable'] as String?,
            );
            final runtimeRow = _runtimeRowForQueueCapability(
              runtimeReport,
              capability,
            );
            final liveStatus = runtimeRow?['status'] as String?;
            final liveValidationState =
                runtimeRow?['validationState'] as String?;
            final liveFailureClass = runtimeRow?['failureClass'] as String?;
            final activationState = _activationStateForQueueRow(
              status: status,
              liveStatus: liveStatus,
              liveValidationState: liveValidationState,
              liveFailureClass: liveFailureClass,
              normalizer: capability['normalizer'] as String?,
              canonicalTable: capability['canonicalTable'] as String?,
              routeImplementationRequired: routeImplementationRequired,
            );
            return {
              'id':
                  'gap:${definition['interfaceId']}:${capability['provider']}',
              'interfaceId': definition['interfaceId'],
              'category': definition['category'],
              'purpose': definition['purpose'] ?? definition['label'],
              'canonicalSchema': definition['canonicalSchema'],
              'provider': capability['provider'],
              'status': capability['status'],
              'capabilityId': capability['capabilityId'],
              'adapter': capability['adapter'],
              'normalizer': capability['normalizer'],
              'canonicalTable': capability['canonicalTable'],
              'probeId': capability['probeId'],
              'liveStatus': liveStatus,
              'liveValidationState': liveValidationState,
              'liveFailureClass': liveFailureClass,
              'activationState': activationState,
              'reason': capability['reason'],
              'routeWiringStatus': routeWiringStatus,
              'routeImplementationRequired': routeImplementationRequired,
              'gapClass': gapClass,
              'actionPriority': _gapActionPriority(gapClass),
              'promotionCandidate': false,
              'presenceReason': _capabilityPresenceReason(
                status: status,
                interfaceId: definition['interfaceId'] as String? ?? '',
                provider: capability['provider'] as String? ?? '',
                reason: capability['reason'] as String?,
                gapClass: gapClass,
              ),
              'exitCondition': _capabilityExitCondition(
                status: status,
                gapClass: gapClass,
              ),
              'retryPolicy': _capabilityRetryPolicy(
                status: status,
                gapClass: gapClass,
              ),
              'cacheDecision': _capabilityCacheDecision(
                status: status,
                gapClass: gapClass,
              ),
              'nextAction': nextAction,
            };
          });
    }).toList();
  }

  bool _isCredentialActivationRow(Map<String, dynamic> row) {
    final status = row['status'] as String? ?? '';
    return status == 'credential-gated' || status == 'quota-gated';
  }

  bool _isCredentialValidatedRow(Map<String, dynamic> row) {
    return _isCredentialActivationRow(row) &&
        row['activationState'] == 'configured-live-validated';
  }

  Map<String, dynamic>? _runtimeRowForQueueCapability(
    Map<String, dynamic>? runtimeReport,
    Map<dynamic, dynamic> capability,
  ) {
    if (runtimeReport == null) return null;
    final probeId = capability['probeId'] as String?;
    if (probeId == null || probeId.isEmpty) return null;
    for (final row in [
      ..._runtimeRows(runtimeReport['passedApis']),
      ..._runtimeRows(runtimeReport['failures']),
    ]) {
      if (_runtimeProbeIdMatches(probeId, row['id'])) return row;
    }
    return null;
  }

  String? _activationStateForQueueRow({
    required String status,
    required String? liveStatus,
    required String? liveValidationState,
    required String? liveFailureClass,
    required String? normalizer,
    required String? canonicalTable,
    required bool routeImplementationRequired,
  }) {
    if (status != 'credential-gated' && status != 'quota-gated') return null;
    if (liveStatus == 'passed' &&
        (liveValidationState == null ||
            liveValidationState.isEmpty ||
            liveValidationState == 'configured-live-validated' ||
            liveValidationState == 'valid-schema-observed') &&
        liveFailureClass == null &&
        normalizer != null &&
        canonicalTable != null &&
        !routeImplementationRequired) {
      return 'configured-live-validated';
    }
    if (liveFailureClass == 'quota-or-rate-limit' ||
        liveValidationState == 'quota-gated' ||
        status == 'quota-gated') {
      return 'configured-quota-blocked';
    }
    if (liveFailureClass == 'credential-or-permission' ||
        liveValidationState == 'credential-gated') {
      return 'configured-provider-blocked';
    }
    if (liveStatus != null && liveStatus != 'passed') {
      return 'configured-validation-failed';
    }
    return 'configured-awaiting-validation';
  }

  bool _isPolicyDisabledRow(Map<String, dynamic> row) {
    return row['status'] == 'disabled' && row['gapClass'] == 'policy-disabled';
  }

  List<Map<String, dynamic>> _failureActionQueue(
    List<Map<String, dynamic>> interfaces,
    List<Map<String, dynamic>> providers,
  ) {
    final interfaceFailures = interfaces
        .where(((row) => ((row['recentFailures'] as int?) ?? 0) > 0))
        .map((row) {
          final affectedCapabilities = _affectedCapabilitiesForInterface(row);
          return {
            'id': 'failure:${row['interfaceId']}',
            'probeId': row['interfaceId'],
            'provider': null,
            'family': row['interfaceId'],
            'status': 'recent-failure',
            'validationState': row['health'],
            'failureClass': row['lastFailureClass'],
            'affectedInterfaces': [row['interfaceId']],
            'affectedCapabilities': affectedCapabilities,
            'canonicalSchema': row['canonicalSchema'],
            'canonicalTable': _firstString(row['canonicalTables']),
            'readbackAction': _firstString(row['queryActions']),
            'readbackActions': row['queryActions'],
            'capabilityId': _firstCapabilityId(affectedCapabilities),
            'nextAction': row['nextAction'],
            'reason': _failureReason(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              row['interfaceId'] as String? ?? 'interface failure',
              null,
            ),
            'recoveryPolicy': _failureRecoveryPolicy(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              _firstString(row['queryActions']),
            ),
            'retryPolicy': _failureRetryPolicy(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
            ),
            'cacheDecision': _failureCacheDecision(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              _firstString(row['queryActions']),
            ),
            'presenceReason': _failurePresenceReason(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              row['interfaceId'] as String? ?? 'interface failure',
              null,
              row['lastFailure'] as String?,
            ),
            'exitCondition': _failureExitCondition(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
            ),
            'error': row['lastFailure'],
          };
        });
    final providerFailures = providers
        .where(((row) => ((row['recentFailures'] as int?) ?? 0) > 0))
        .map((row) {
          final provider = row['provider'] as String? ?? '';
          return {
            'id': 'failure:provider:$provider',
            'probeId': 'provider:$provider',
            'provider': provider,
            'family': 'provider',
            'status': 'recent-failure',
            'validationState': row['health'],
            'failureClass': row['lastFailureClass'],
            'affectedInterfaces': _interfacesForProvider(interfaces, provider),
            'affectedCapabilities': _affectedCapabilitiesForProvider(
              interfaces,
              provider,
            ),
            'nextAction': _providerNextAction(row),
            'reason': _failureReason(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              'provider:$provider',
              provider,
            ),
            'recoveryPolicy': _failureRecoveryPolicy(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              null,
            ),
            'retryPolicy': _failureRetryPolicy(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
            ),
            'cacheDecision': _failureCacheDecision(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              null,
            ),
            'presenceReason': _failurePresenceReason(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
              'provider:$provider',
              provider,
              row['lastFailure'] as String?,
            ),
            'exitCondition': _failureExitCondition(
              row['lastFailureClass'] as String?,
              row['health'] as String?,
            ),
            'error': row['lastFailure'],
          };
        });
    return [...interfaceFailures, ...providerFailures];
  }

  List<String> _interfacesForProvider(
    List<Map<String, dynamic>> interfaces,
    String provider,
  ) {
    return interfaces
        .where((row) {
          final capabilities = (row['capabilities'] as List?) ?? const [];
          return capabilities.whereType<Map>().any((capability) {
            final status = capability['status'] as String? ?? '';
            return capability['provider'] == provider &&
                status != 'not-supported';
          });
        })
        .map((row) => row['interfaceId'] as String?)
        .whereType<String>()
        .toSet()
        .toList()
      ..sort();
  }

  List<Map<String, dynamic>> _affectedCapabilitiesForInterface(
    Map<String, dynamic> row,
  ) {
    final capabilities = (row['capabilities'] as List?) ?? const [];
    return capabilities
        .whereType<Map>()
        .where((capability) {
          return capability['status'] != 'not-supported';
        })
        .map((capability) {
          return {
            'interfaceId': row['interfaceId'],
            'capabilityId': capability['capabilityId'],
            'provider': capability['provider'],
            'status': capability['status'],
            'canonicalSchema': row['canonicalSchema'],
            'canonicalTable':
                capability['canonicalTable'] ??
                _firstString(row['canonicalTables']),
            'readbackAction': _firstString(row['queryActions']),
            'readbackActions': row['queryActions'],
            'normalizer': capability['normalizer'],
          };
        })
        .toList();
  }

  List<Map<String, dynamic>> _affectedCapabilitiesForProvider(
    List<Map<String, dynamic>> interfaces,
    String provider,
  ) {
    final rows = <Map<String, dynamic>>[];
    for (final row in interfaces) {
      final capabilities = (row['capabilities'] as List?) ?? const [];
      for (final capability in capabilities.whereType<Map>()) {
        final status = capability['status'] as String? ?? '';
        if (capability['provider'] != provider || status == 'not-supported') {
          continue;
        }
        rows.add({
          'interfaceId': row['interfaceId'],
          'capabilityId': capability['capabilityId'],
          'provider': capability['provider'],
          'status': status,
          'canonicalSchema': row['canonicalSchema'],
          'canonicalTable':
              capability['canonicalTable'] ??
              _firstString(row['canonicalTables']),
          'readbackAction': _firstString(row['queryActions']),
          'readbackActions': row['queryActions'],
          'normalizer': capability['normalizer'],
        });
      }
    }
    rows.sort((a, b) {
      final interfaceCompare = (a['interfaceId'] as String? ?? '').compareTo(
        b['interfaceId'] as String? ?? '',
      );
      if (interfaceCompare != 0) return interfaceCompare;
      return (a['capabilityId'] as String? ?? '').compareTo(
        b['capabilityId'] as String? ?? '',
      );
    });
    return rows;
  }
}

String? _firstCapabilityId(List<Map<String, dynamic>> capabilities) {
  if (capabilities.isEmpty) return null;
  return capabilities.first['capabilityId'] as String?;
}

String? _firstString(Object? value) {
  if (value is List && value.isNotEmpty) {
    final first = value.first;
    return first == null ? null : '$first';
  }
  if (value is String && value.isNotEmpty) return value;
  return null;
}

String _normalizeSection(String value) {
  final normalized = value.trim().toLowerCase();
  return switch (normalized) {
    'interfaces' || 'providers' || 'gaps' || 'failures' || 'all' => normalized,
    _ => 'summary',
  };
}

String _categoryForInterface(String interfaceId) {
  final family = interfaceId.split('.').first;
  return switch (family) {
    'stock' => 'stock',
    'index' => 'index',
    'market' => 'market',
    'fund' => 'fund_etf',
    'calendar' => 'calendar',
    'news' => 'news',
    'technical' => 'technical',
    'yfinance' => 'global_market',
    'wind' => 'professional_data',
    'provider' => 'provider_diagnostic',
    _ => 'other',
  };
}

int _compareInterfaceHealth(Map<String, dynamic> a, Map<String, dynamic> b) {
  final score = _interfaceScore(b).compareTo(_interfaceScore(a));
  if (score != 0) return score;
  return (a['interfaceId'] as String).compareTo(b['interfaceId'] as String);
}

int _interfaceScore(Map<String, dynamic> row) {
  return ((row['recentFailures'] as int?) ?? 0) * 1000 +
      ((row['unstableProviders'] as List?)?.length ?? 0) * 100 +
      ((row['outputOnlyProviders'] as List?)?.length ?? 0) * 30 +
      ((row['gatedProviders'] as List?)?.length ?? 0) * 20 +
      (row['health'] == 'gap'
          ? 10
          : row['health'] == 'attention'
          ? 50
          : 0);
}

int _compareProvider(Map<String, dynamic> a, Map<String, dynamic> b) {
  final score = _providerScore(b).compareTo(_providerScore(a));
  if (score != 0) return score;
  return (a['provider'] as String).compareTo(b['provider'] as String);
}

int _providerScore(Map<String, dynamic> row) {
  return ((row['recentFailures'] as int?) ?? 0) * 1000 +
      ((row['unstable'] as int?) ?? 0) * 100 +
      ((row['outputOnly'] as int?) ?? 0) * 30 +
      ((row['gated'] as int?) ?? 0) * 20 +
      (row['health'] == 'gap'
          ? 10
          : row['health'] == 'attention'
          ? 50
          : 0);
}

int _compareProviderGap(Map<String, dynamic> a, Map<String, dynamic> b) {
  final priority = ((a['actionPriority'] as int?) ?? 9).compareTo(
    (b['actionPriority'] as int?) ?? 9,
  );
  if (priority != 0) return priority;
  final score = _providerGapScore(b).compareTo(_providerGapScore(a));
  if (score != 0) return score;
  final interfaceCompare = (a['interfaceId'] as String? ?? '').compareTo(
    b['interfaceId'] as String? ?? '',
  );
  if (interfaceCompare != 0) return interfaceCompare;
  return (a['provider'] as String? ?? '').compareTo(
    b['provider'] as String? ?? '',
  );
}

Map<String, int> _providerGapClassCounts(List<Map<String, dynamic>> rows) {
  final counts = <String, int>{};
  for (final row in rows) {
    final gapClass = row['gapClass'] as String? ?? 'unknown';
    counts[gapClass] = (counts[gapClass] ?? 0) + 1;
  }
  return counts;
}

String _gapClassFor(
  String status,
  String? routeWiringStatus,
  bool routeImplementationRequired,
) {
  return switch (status) {
    'transport-unstable' => 'serial-live-retry',
    'credential-gated' || 'quota-gated' => 'credential-or-quota-required',
    'disabled' => 'policy-disabled',
    'output-only' when routeWiringStatus == 'non-equivalent-wrapper' =>
      'non-equivalent-output-only',
    'output-only' when routeImplementationRequired =>
      'route-implementation-required',
    'output-only' => 'output-only-review',
    _ => 'capability-gap',
  };
}

int _gapActionPriority(String gapClass) {
  return switch (gapClass) {
    'serial-live-retry' => 1,
    'route-implementation-required' => 1,
    'credential-or-quota-required' => 2,
    'output-only-review' => 3,
    'non-equivalent-output-only' => 4,
    'policy-disabled' => 5,
    _ => 9,
  };
}

int _providerGapScore(Map<String, dynamic> row) {
  return (row['promotionCandidate'] == true ? 100 : 0) +
      (row['routeImplementationRequired'] == true ? 50 : 0) +
      (row['status'] == 'output-only'
          ? 30
          : row['status'] == 'credential-gated' ||
                row['status'] == 'quota-gated'
          ? 20
          : 10);
}

String _capabilityPresenceReason({
  required String status,
  required String interfaceId,
  required String provider,
  required String? reason,
  required String gapClass,
}) {
  if (reason != null && reason.trim().isNotEmpty) return reason;
  return switch (status) {
    'credential-gated' =>
      '$provider capability for $interfaceId is known but waits for configured credential and live evidence.',
    'quota-gated' =>
      '$provider capability for $interfaceId is known but waits for quota availability and live evidence.',
    'disabled' =>
      '$provider capability for $interfaceId is policy-disabled and must stay out of normal routing.',
    'output-only' when gapClass == 'route-implementation-required' =>
      '$provider capability for $interfaceId has output evidence but still lacks reusable normalizer, persistence, or readback.',
    'output-only' =>
      '$provider capability for $interfaceId is normalized output-only and needs a reuse decision.',
    'transport-unstable' =>
      '$provider capability for $interfaceId is isolated because recent live evidence is transport-unstable.',
    _ =>
      '$provider capability for $interfaceId needs explicit implementation, gate, disable, unsupported, or diagnostic classification.',
  };
}

String _capabilityExitCondition({
  required String status,
  required String gapClass,
}) {
  return switch (status) {
    'credential-gated' || 'quota-gated' =>
      'Leaves this queue after credential/quota state is verified by a bounded probe and the capability is promoted, kept gated with fresh evidence, disabled, or marked unsupported.',
    'disabled' =>
      'Leaves this queue only after policy or provider permission changes and a new classification is committed with evidence.',
    'output-only' when gapClass == 'route-implementation-required' =>
      'Leaves this queue after adapter, normalizer, canonical persistence, readback, provenance fields, and focused tests are implemented, or after the capability is explicitly kept output-only.',
    'output-only' =>
      'Leaves this queue after the surface is promoted to a governed interface, retained as normalized output-only with evidence, or marked unsupported/diagnostic.',
    'transport-unstable' =>
      'Leaves this queue after serial live probes produce stable evidence or the provider is reclassified as gated, disabled, unsupported, or diagnostic.',
    _ =>
      'Leaves this queue after implementation, explicit gate, disabled/not-supported status, or diagnostic classification is recorded.',
  };
}

String _capabilityRetryPolicy({
  required String status,
  required String gapClass,
}) {
  return switch (status) {
    'credential-gated' || 'quota-gated' =>
      'no broad retry; run only the registered credential/quota probe after config or quota changes',
    'disabled' => 'do not retry while policy-disabled',
    'transport-unstable' =>
      'serial retry only with conservative timeout and preserved raw evidence',
    'output-only' when gapClass == 'route-implementation-required' =>
      'do not retry as reusable data until normalizer and readback are implemented',
    'output-only' =>
      'manual review before promotion; output-only diagnostics may be rerun with bounded scope',
    _ => 'manual classification required before retry',
  };
}

String _capabilityCacheDecision({
  required String status,
  required String gapClass,
}) {
  return switch (status) {
    'credential-gated' || 'quota-gated' =>
      'Use existing cache/readback or eligible fallback providers first; do not call this provider live until credential/quota evidence is current.',
    'disabled' =>
      'Do not use this provider capability for normal workflow or cache refresh while policy-disabled.',
    'transport-unstable' =>
      'Keep cached data when available; retry only through bounded serial probe evidence before normal routing.',
    'output-only' when gapClass == 'route-implementation-required' =>
      'Not eligible for canonical cache reuse yet; implement adapter, normalizer, persistence, and readback before normal workflow.',
    'output-only' =>
      'Treat as bounded output-only evidence; do not assume reusable cache/readback until promoted or explicitly retained output-only.',
    _ =>
      'Normal cache/readback behavior is not available until this capability is classified or implemented.',
  };
}

int _compareFailureAction(Map<String, dynamic> a, Map<String, dynamic> b) {
  final score = _failureActionScore(b).compareTo(_failureActionScore(a));
  if (score != 0) return score;
  final providerCompare = (a['provider'] as String? ?? '').compareTo(
    b['provider'] as String? ?? '',
  );
  if (providerCompare != 0) return providerCompare;
  return (a['family'] as String? ?? '').compareTo(b['family'] as String? ?? '');
}

int _failureActionScore(Map<String, dynamic> row) {
  return switch (row['failureClass']) {
    'schema-or-contract' => 100,
    'credential-or-permission' || 'quota-or-rate-limit' => 80,
    'transport' || 'timeout' => 60,
    _ => 10,
  };
}

String _capabilityNextAction(
  String status,
  String? reason, {
  String? normalizer,
  String? canonicalTable,
}) {
  return switch (status) {
    'supported' || 'global-only' =>
      'Use interface route with cache/readback before provider refresh.',
    'credential-gated' || 'quota-gated'
        when normalizer != null && canonicalTable != null =>
      'Credential-gated provider has canonical shape registered; use cache/readback first and require configured credentials before live refresh.',
    'credential-gated' || 'quota-gated' =>
      'Configure credential/quota, then run serial live probe and readback verification.',
    'output-only'
        when (reason ?? '').contains('normalizer') ||
            (reason ?? '').contains('readback') =>
      'Add provider normalizer, canonical persistence, and readback before marking supported.',
    'output-only' =>
      'Evaluate whether this output-only capability has reusable business-data value.',
    'transport-unstable' =>
      'Keep serial probes with conservative timeout; classify transport separately from schema failure.',
    'disabled' =>
      'Do not route normal workflows here; fix policy/permission before enabling.',
    _ => 'Review capability classification.',
  };
}

String _providerNextAction(Map<String, dynamic> row) {
  final failureClass = row['lastFailureClass'] as String?;
  if (((row['recentFailures'] as int?) ?? 0) > 0) {
    if (failureClass == 'transport' || failureClass == 'timeout') {
      return 'Inspect recent provider failures and rerun only serial probes.';
    }
    if (failureClass == 'credential-or-permission') {
      return 'Fix credentials/permission; do not retry broad provider calls.';
    }
    if (failureClass == 'quota-or-rate-limit') {
      return 'Use cache/fallback until quota resets.';
    }
    return 'Triage recent failures before expanding provider routing.';
  }
  if (((row['unstable'] as int?) ?? 0) > 0) {
    return 'Keep unstable capabilities isolated and validate with serial probes.';
  }
  if (((row['outputOnly'] as int?) ?? 0) > 0) {
    return 'Promote high-value output-only capabilities only after normalizer/readback exists.';
  }
  if (((row['gated'] as int?) ?? 0) > 0) {
    return 'Use credentials and quota checks before live validation.';
  }
  if (((row['disabled'] as int?) ?? 0) > 0) {
    return 'Keep disabled capabilities out of normal workflows.';
  }
  if (((row['supported'] as int?) ?? 0) == 0) {
    return 'Provider has no supported interfaces; keep it out of normal routing.';
  }
  return 'Provider has supported governed interfaces.';
}

String _failureReason(
  String? failureClass,
  String? validationState,
  String subject,
  String? provider,
) {
  final source = provider ?? 'Provider';
  if (failureClass == 'auth_permission') {
    return '$source rejected $subject because the configured credential lacks endpoint entitlement or account permission.';
  }
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return '$source failed because credentials or provider permissions are not accepted for $subject.';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return '$source failed because quota or rate limit is exhausted for $subject.';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return '$source response did not satisfy the expected provider/interface contract for $subject.';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return '$source failed due to transport, timeout, or provider instability for $subject.';
  }
  if (failureClass == 'runtime_unavailable' ||
      validationState == 'runtime-blocked') {
    return '$source runtime dependency is unavailable for $subject.';
  }
  return '$source failure requires classified triage before widening use for $subject.';
}

String _failureRecoveryPolicy(
  String? failureClass,
  String? validationState,
  String? readbackAction,
) {
  final cacheText = readbackAction == null
      ? ''
      : ' Reuse $readbackAction cache when available.';
  if (failureClass == 'auth_permission') {
    return 'Keep this provider capability gated; fix provider-side entitlement or account permission, then rerun only the bounded probe.$cacheText';
  }
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'Keep provider gate active; fix credentials or provider permission before live refresh.$cacheText';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'Stop broad provider collection until quota resets; prefer reusable cache and eligible fallback providers.$cacheText';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'Fix adapter/parser/normalizer contract before persisting additional rows.';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'Retry only with serial probes and provider-specific timeout after provider/network recovery.';
  }
  if (failureClass == 'runtime_unavailable' ||
      validationState == 'runtime-blocked') {
    return 'Restore the runtime dependency before retrying the probe.';
  }
  return 'Classify root cause, update provider evidence, and rerun focused verification before widening routing.';
}

String _failureRetryPolicy(String? failureClass, String? validationState) {
  if (failureClass == 'auth_permission') {
    return 'no automatic retry until provider entitlement or permission changes';
  }
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'no automatic retry until credential or permission changes';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'no broad retry until quota reset; cache/readback first';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'no retry until adapter or schema contract is fixed';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'serial retry only after provider/network recovery';
  }
  if (failureClass == 'runtime_unavailable' ||
      validationState == 'runtime-blocked') {
    return 'retry only after runtime dependency is restored';
  }
  return 'manual triage required before retry';
}

String _failureCacheDecision(
  String? failureClass,
  String? validationState,
  String? readbackAction,
) {
  final cacheText = readbackAction != null && readbackAction.isNotEmpty
      ? ' Use $readbackAction readback if local data is fresh enough.'
      : ' Use local cache/readback or healthy fallback providers when available.';
  if (failureClass == 'auth_permission') {
    return 'Keep this provider out of live routing until entitlement changes.$cacheText';
  }
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'Keep provider gate active and avoid live refresh until credentials or permissions change.$cacheText';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'Do not spend more quota on broad retry; prefer cache/readback and fallback providers.$cacheText';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'Do not persist or reuse new provider output until adapter, parser, normalizer, and readback contract are fixed.';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'Preserve existing cached data; retry only with a bounded serial probe after provider/network recovery.$cacheText';
  }
  if (failureClass == 'runtime_unavailable' ||
      validationState == 'runtime-blocked') {
    return 'Provider refresh is blocked by runtime dependency; use cache/readback until the dependency is restored.$cacheText';
  }
  return 'Classify root cause before widening live routing.$cacheText';
}

String _failurePresenceReason(
  String? failureClass,
  String? validationState,
  String subject,
  String? provider,
  String? error,
) {
  if (error != null && error.trim().isNotEmpty) {
    return error;
  }
  return _failureReason(failureClass, validationState, subject, provider);
}

String _failureExitCondition(String? failureClass, String? validationState) {
  if (failureClass == 'auth_permission') {
    return 'Leaves this queue after endpoint entitlement or account permission changes are verified by the bounded probe, or after this provider capability is reclassified.';
  }
  if (failureClass == 'credential-or-permission' ||
      validationState == 'credential-gated') {
    return 'Leaves this queue after credential or permission changes are verified by a bounded probe, or after the capability is reclassified as gated, disabled, unsupported, or supported.';
  }
  if (failureClass == 'quota-or-rate-limit' ||
      validationState == 'quota-gated') {
    return 'Leaves this queue after quota availability is verified or the capability is reclassified with explicit quota policy.';
  }
  if (failureClass == 'schema-or-contract' ||
      validationState == 'unsupported-by-provider') {
    return 'Leaves this queue after adapter/parser/normalizer contract is fixed and focused readback verification passes, or after the path is marked unsupported/diagnostic.';
  }
  if (failureClass == 'transport' ||
      failureClass == 'timeout' ||
      validationState == 'transport-or-provider-unstable') {
    return 'Leaves this queue after serial retry produces stable evidence or the provider is reclassified as unstable, disabled, unsupported, or gated.';
  }
  if (failureClass == 'runtime_unavailable' ||
      validationState == 'runtime-blocked') {
    return 'Leaves this queue after the runtime dependency is restored and the registered probe is rerun successfully or reclassified.';
  }
  return 'Leaves this queue after root cause classification, provider evidence update, and focused verification.';
}

int _tableRows(Object? value) {
  if (value is Map<String, dynamic>) {
    return (value['rows'] as num?)?.toInt() ?? 0;
  }
  if (value is Map) return (value['rows'] as num?)?.toInt() ?? 0;
  return 0;
}

String? _tableLatest(Object? value) {
  if (value is Map<String, dynamic>) return value['latest'] as String?;
  if (value is Map) return value['latest'] as String?;
  return null;
}

String? _latest(Iterable<String?> values) {
  final filtered = values.whereType<String>().where(
    (value) => value.isNotEmpty,
  );
  if (filtered.isEmpty) return null;
  final sorted = filtered.toList()..sort();
  return sorted.last;
}

String _statusName(DataApiCapabilityStatus status) {
  return switch (status) {
    DataApiCapabilityStatus.credentialGated => 'credential-gated',
    DataApiCapabilityStatus.quotaGated => 'quota-gated',
    DataApiCapabilityStatus.transportUnstable => 'transport-unstable',
    DataApiCapabilityStatus.notSupported => 'not-supported',
    DataApiCapabilityStatus.outputOnly => 'output-only',
    DataApiCapabilityStatus.globalOnly => 'global-only',
    _ => status.name,
  };
}

String _apiStatsSource(FinanceProvider provider) {
  return switch (provider) {
    FinanceProvider.local => 'local',
    FinanceProvider.eastmoneyDirect => 'eastmoney',
    FinanceProvider.yfinance => 'yahoo',
    _ => provider.name,
  };
}

String _nextAction({
  required String health,
  required int recentFailures,
  required String? lastFailureClass,
  required List<String> supportedProviders,
  required List<String> gatedProviders,
  required List<String> outputOnlyProviders,
  required List<String> unstableProviders,
  required bool credentialGatedReusable,
}) {
  if (recentFailures > 0) {
    if (lastFailureClass == 'timeout' || lastFailureClass == 'transport') {
      return 'Inspect recent API errors; retry only a narrow serial provider probe with a provider-specific timeout.';
    }
    if (lastFailureClass == 'credential-or-permission') {
      return 'Stop retries and fix provider credentials or permission before live calls.';
    }
    if (lastFailureClass == 'quota-or-rate-limit') {
      return 'Use cache or fallback until quota/frequency resets.';
    }
    if (lastFailureClass == 'schema-or-contract') {
      return 'Fix parser or normalizer contract before persisting more rows.';
    }
    return 'Triage recent provider failures before broad provider routing.';
  }
  if (unstableProviders.isNotEmpty) {
    return 'Keep unstable providers isolated and validate with serial probes.';
  }
  if (outputOnlyProviders.isNotEmpty) {
    return 'Promote output-only providers only after normalizer, persistence, and readback exist.';
  }
  if (gatedProviders.isNotEmpty) {
    if (credentialGatedReusable) {
      return 'Credential-gated provider has canonical shape registered; use cache/readback first and require configured credentials before live refresh.';
    }
    return 'Verify credential-gated providers before enabling fallback.';
  }
  if (supportedProviders.isEmpty || health == 'gap') {
    return 'Add a supported provider capability or keep the interface explicitly unsupported.';
  }
  return 'Ready for normal cache-first interface routing.';
}

class _RuntimeCapabilityDecision {
  final bool eligible;
  final int sortRank;
  final String routeState;
  final String reason;
  final String? evidenceStatus;
  final String? liveValidationState;
  final String? liveFailureClass;
  final String? temporaryBlockUntil;
  final String? routeBlockScope;

  const _RuntimeCapabilityDecision({
    required this.eligible,
    required this.sortRank,
    required this.routeState,
    required this.reason,
    this.evidenceStatus,
    this.liveValidationState,
    this.liveFailureClass,
    this.temporaryBlockUntil,
    this.routeBlockScope,
  });
}

List<Map<String, dynamic>> _runtimeEligibleCapabilities(
  String interfaceId,
  List<DataApiProviderCapability> capabilities,
  Map<String, dynamic>? runtimeReport, {
  bool allowDegraded = false,
}) {
  final rows = capabilities
      .map((capability) {
        final decision = _runtimeRouteDecision(
          interfaceId,
          capability,
          runtimeReport,
          allowDegraded: allowDegraded,
        );
        if (!decision.eligible) return null;
        return {
          ..._runtimeCapabilitySummary(capability),
          'routeState': decision.routeState,
          'routeReason': decision.reason,
          'evidenceStatus': decision.evidenceStatus,
          'liveValidationState': decision.liveValidationState,
          'liveFailureClass': decision.liveFailureClass,
          'temporaryBlockUntil': decision.temporaryBlockUntil,
          'routeBlockScope': decision.routeBlockScope,
          '_sortRank': decision.sortRank,
        };
      })
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
  rows.sort((a, b) {
    final rank = ((a['_sortRank'] as int?) ?? 9).compareTo(
      (b['_sortRank'] as int?) ?? 9,
    );
    if (rank != 0) return rank;
    return ((a['priority'] as int?) ?? 999).compareTo(
      (b['priority'] as int?) ?? 999,
    );
  });
  for (final row in rows) {
    row.remove('_sortRank');
  }
  return rows;
}

_RuntimeCapabilityDecision _runtimeRouteDecision(
  String interfaceId,
  DataApiProviderCapability capability,
  Map<String, dynamic>? runtimeReport, {
  bool allowDegraded = false,
}) {
  if (runtimeReport == null) {
    return const _RuntimeCapabilityDecision(
      eligible: true,
      sortRank: 1,
      routeState: 'allowed-unvalidated',
      reason:
          'No blocking runtime evidence is recorded for this capability; treat it as available but prefer validated providers when possible.',
    );
  }
  final runtime = _runtimeRowForCapability(runtimeReport, capability);
  if (runtime == null) {
    return const _RuntimeCapabilityDecision(
      eligible: true,
      sortRank: 1,
      routeState: 'allowed-unvalidated',
      reason:
          'No blocking runtime evidence is recorded for this capability; treat it as available but prefer validated providers when possible.',
    );
  }
  final status = '${runtime['status'] ?? ''}'.trim().toLowerCase();
  final validationState = '${runtime['validationState'] ?? ''}'
      .trim()
      .toLowerCase();
  final failureClass = '${runtime['failureClass'] ?? ''}'.trim().toLowerCase();
  final temporaryBlockUntil = _runtimeTemporaryBlockUntil(
    runtime,
    runtimeReport,
  );
  final routeBlockScope = '${runtime['routeBlockScope'] ?? ''}'.trim();
  if (status == 'passed' &&
      (validationState.isEmpty ||
          validationState == 'configured-live-validated' ||
          validationState == 'valid-schema-observed')) {
    return _RuntimeCapabilityDecision(
      eligible: true,
      sortRank: 0,
      routeState: 'validated',
      reason: 'Recent runtime probe validated this provider capability.',
      evidenceStatus: status,
      liveValidationState: validationState,
      liveFailureClass: failureClass.isEmpty ? null : failureClass,
      routeBlockScope: routeBlockScope.isEmpty ? null : routeBlockScope,
    );
  }
  if (failureClass == 'transport' || failureClass == 'timeout') {
    if (_isExpiredIsoTime(temporaryBlockUntil)) {
      return _RuntimeCapabilityDecision(
        eligible: true,
        sortRank: 1,
        routeState: 'allowed-unvalidated',
        reason:
            'Previous transient runtime block expired at $temporaryBlockUntil; route may be retried through bounded provider routing or runtime_probe.',
        evidenceStatus: status.isEmpty ? null : status,
        liveValidationState: validationState.isEmpty ? null : validationState,
        liveFailureClass: failureClass,
        temporaryBlockUntil: temporaryBlockUntil,
        routeBlockScope: routeBlockScope.isEmpty ? null : routeBlockScope,
      );
    }
    return _RuntimeCapabilityDecision(
      eligible: allowDegraded,
      sortRank: allowDegraded ? 2 : 9,
      routeState: allowDegraded
          ? 'degraded-allowed'
          : temporaryBlockUntil == null
          ? 'blocked-transport'
          : 'temporarily-blocked',
      reason: allowDegraded
          ? temporaryBlockUntil == null
                ? 'Recent runtime evidence shows transport instability; degraded routing is explicitly allowed.'
                : 'Transient provider block is active until $temporaryBlockUntil; degraded routing is explicitly allowed.'
          : temporaryBlockUntil == null
          ? 'Recent runtime evidence shows transport instability; keep retry narrow and avoid normal routing.'
          : 'Transient provider block is active until $temporaryBlockUntil; use cache/readback or fallback providers before retrying.',
      evidenceStatus: status.isEmpty ? null : status,
      liveValidationState: validationState.isEmpty ? null : validationState,
      liveFailureClass: failureClass,
      temporaryBlockUntil: temporaryBlockUntil,
      routeBlockScope: routeBlockScope.isEmpty ? null : routeBlockScope,
    );
  }
  if (failureClass == 'credential-or-permission' ||
      failureClass == 'quota-or-rate-limit' ||
      failureClass == 'runtime-blocked' ||
      validationState == 'runtime-blocked') {
    return _RuntimeCapabilityDecision(
      eligible: false,
      sortRank: 9,
      routeState: failureClass == 'credential-or-permission'
          ? 'blocked-provider-permission'
          : failureClass == 'quota-or-rate-limit'
          ? 'blocked-quota'
          : 'blocked-runtime',
      reason:
          'Recent runtime evidence marks this provider path blocked for normal workflow.',
      evidenceStatus: status.isEmpty ? null : status,
      liveValidationState: validationState.isEmpty ? null : validationState,
      liveFailureClass: failureClass.isEmpty ? null : failureClass,
      routeBlockScope: routeBlockScope.isEmpty ? null : routeBlockScope,
    );
  }
  return _RuntimeCapabilityDecision(
    eligible: true,
    sortRank: 1,
    routeState: 'allowed-unvalidated',
    reason:
        'No blocking runtime evidence is recorded for this capability; treat it as available but prefer validated providers when possible.',
    evidenceStatus: status.isEmpty ? null : status,
    liveValidationState: validationState.isEmpty ? null : validationState,
    liveFailureClass: failureClass.isEmpty ? null : failureClass,
    routeBlockScope: routeBlockScope.isEmpty ? null : routeBlockScope,
  );
}

String? _runtimeTemporaryBlockUntil(
  Map<String, dynamic> runtime,
  Map<String, dynamic> report,
) {
  final explicit = '${runtime['temporaryBlockUntil'] ?? ''}'.trim();
  if (explicit.isNotEmpty) return explicit;
  final failureClass = '${runtime['failureClass'] ?? ''}'.trim().toLowerCase();
  if (failureClass != 'transport' && failureClass != 'timeout') return null;
  final generatedAt = DateTime.tryParse('${report['generatedAt'] ?? ''}');
  if (generatedAt == null) return null;
  final ttl = failureClass == 'timeout'
      ? const Duration(minutes: 15)
      : const Duration(minutes: 30);
  return generatedAt.toUtc().add(ttl).toIso8601String();
}

bool _isExpiredIsoTime(String? value) {
  if (value == null || value.isEmpty) return false;
  final parsed = DateTime.tryParse(value);
  return parsed != null && !parsed.toUtc().isAfter(DateTime.now().toUtc());
}

Map<String, dynamic>? _runtimeRowForCapability(
  Map<String, dynamic> report,
  DataApiProviderCapability capability,
) {
  final rows = <Map<String, dynamic>>[
    ..._runtimeRows(report['passedApis']),
    ..._runtimeRows(report['failures']),
  ];
  for (final row in rows) {
    if (_runtimeProbeIdMatches(capability.probeId, row['id'])) {
      return row;
    }
    if (row['capabilityId'] == capability.id) return row;
  }
  return null;
}

bool _runtimeProbeIdMatches(String? capabilityProbeId, Object? rowId) {
  if (capabilityProbeId == null || capabilityProbeId.isEmpty) return false;
  final runtimeId = '$rowId';
  if (runtimeId == capabilityProbeId) return true;
  const aliases = {
    'mobile_yahoo_earnings': ['mobile_marketdata_yahoo_earnings'],
    'mobile_yahoo_options': ['mobile_marketdata_yahoo_options'],
  };
  return aliases[capabilityProbeId]?.contains(runtimeId) ?? false;
}

List<Map<String, dynamic>> _runtimeRows(Object? rows) {
  if (rows is! List) return const [];
  return rows
      .whereType<Map>()
      .map((row) => row.map((key, value) => MapEntry('$key', value)))
      .toList(growable: false);
}

Map<String, dynamic> _runtimeCapabilitySummary(
  DataApiProviderCapability capability,
) {
  return {
    'capabilityId': capability.id,
    'provider': capability.provider.name,
    'status': _statusName(capability.status),
    'priority': capability.priority,
    'adapter': capability.adapter,
    'normalizer': capability.normalizer,
    'canonicalTable': capability.canonicalTable,
    'probeId': capability.probeId,
    'reason': capability.reason,
  };
}
