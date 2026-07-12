import 'dart:convert';
import 'dart:io';

import '../../artifact_registry.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

const _workflows = <String, Map<String, dynamic>>{
  'market_overview': {
    'requiredAnyTools': ['MarketData', 'DataStore', 'Research'],
    'artifactKinds': ['analysis', 'dashboard', 'data_snapshot'],
    'approvalBoundary': 'no_trade',
  },
  'stock_research': {
    'requiredAnyTools': ['MarketData', 'DataStore', 'DataProcess', 'Research'],
    'artifactKinds': ['analysis', 'dashboard', 'data_snapshot'],
    'approvalBoundary': 'no_trade',
  },
  'stock_selection': {
    'requiredAnyTools': ['MarketData', 'DataStore', 'DataProcess', 'Research'],
    'artifactKinds': ['analysis', 'data_snapshot'],
    'artifactRequired': false,
    'approvalBoundary': 'no_trade',
  },
  'watchlist_handoff': {
    'requiredAnyTools': ['Watchlist'],
    'artifactKinds': ['data_snapshot', 'analysis'],
    'artifactRequired': false,
    'approvalBoundary': 'no_trade',
  },
  'fund_selection': {
    'requiredAnyTools': ['MarketData', 'DataStore', 'DataProcess', 'Research'],
    'artifactKinds': ['analysis', 'data_snapshot'],
    'artifactRequired': false,
    'approvalBoundary': 'no_trade',
  },
  'strategy_backtest': {
    'requiredAnyTools': ['DataProcess', 'MarketData'],
    'artifactKinds': ['strategy', 'backtest', 'report'],
    'approvalBoundary': 'no_trade',
  },
  'strategy_rerun': {
    'requiredAnyTools': ['DataProcess', 'MarketData', 'ArtifactRegistry'],
    'artifactKinds': ['strategy', 'backtest', 'report'],
    'approvalBoundary': 'no_trade',
  },
  'trade_preparation': {
    'requiredAnyTools': ['Portfolio', 'XueqiuTrade', 'AskUserQuestion'],
    'artifactKinds': ['trade_preparation', 'analysis'],
    'artifactRequired': false,
    'approvalBoundary': 'explicit_approval_required',
  },
  'trade_review': {
    'requiredAnyTools': ['Portfolio', 'XueqiuTrade'],
    'artifactKinds': ['analysis', 'data_snapshot'],
    'artifactRequired': false,
    'approvalBoundary': 'no_trade',
  },
  'macro_factor_lookup': {
    'requiredAnyTools': ['SourceReader', 'DataStore', 'Research'],
    'artifactKinds': ['macro_evidence', 'research', 'data_snapshot'],
    'approvalBoundary': 'no_trade',
    'macroEvidenceRecord': true,
  },
};

class WorkflowVerifierTool extends Tool {
  @override
  String get name => 'WorkflowVerifier';

  @override
  String get description =>
      'Verify whether a workflow has enough structured evidence before the agent finalizes a claim or proceeds to a boundary.';

  @override
  String get prompt =>
      'Use WorkflowVerifier(action:"check", workflow:"...") before final answers for broad finance workflows. It checks structured tool/session/artifact evidence and returns missing evidence plus recovery guidance.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'list', 'check'],
      },
      'workflow': {'type': 'string', 'enum': _workflows.keys.toList()},
      'artifactId': {
        'type': 'string',
        'description':
            'Optional artifact id/stable ref to require for this check.',
      },
      'workflowStateId': {
        'type': 'string',
        'description':
            'Optional saved FinanceWorkflowState id to require for this check.',
      },
      'requireWorkflowState': {
        'type': 'boolean',
        'description':
            'Require a saved typed workflow-state record that matches this workflow family.',
      },
      'providerHealth': {
        'type': 'array',
        'items': {'type': 'object'},
        'description':
            'Optional provider-health rows from ProviderRouter/API health/probes. Blocking statuses fail this verifier check.',
      },
      'strategyId': {
        'type': 'string',
        'description':
            'Optional saved StrategySpec id expected in strategy_rerun evidence.',
      },
      'targetSymbols': {
        'type': 'array',
        'items': {'type': 'string'},
        'description':
            'Optional target symbols expected in custom_strategy_run evidence.',
      },
      'limit': {'type': 'integer', 'minimum': 1, 'maximum': 100},
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
    if (action == 'list') {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'workflow-verifier-list-v1',
          'workflows': _workflows.keys.toList(),
          'guidance':
              'Call WorkflowVerifier(action:"check", workflow:<id>) before final workflow claims.',
        }),
      );
    }
    if (action != 'check') {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Invalid WorkflowVerifier action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final workflow = (input['workflow'] as String?)?.trim() ?? '';
    final spec = _workflows[workflow];
    if (spec == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Unknown WorkflowVerifier workflow "$workflow". Use action="list" to inspect available workflows.',
        isError: true,
      );
    }
    final limit = _intValue(input['limit'], defaultValue: 50).clamp(1, 100);
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode(
        _checkWorkflow(
          context,
          workflow: workflow,
          spec: spec,
          artifactId: (input['artifactId'] as String?)?.trim(),
          workflowStateId: (input['workflowStateId'] as String?)?.trim(),
          requireWorkflowState: input['requireWorkflowState'] == true,
          providerHealth: input['providerHealth'],
          strategyId: _optionalString(input['strategyId']),
          targetSymbols: _stringList(input['targetSymbols']),
          limit: limit,
        ),
      ),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'workflow-verifier-help-v1',
    'actions': ['list', 'check'],
    'workflows': _workflows.keys.toList(),
    'checks': [
      'tool_calls_present',
      'required_tool_family',
      'no_tool_errors',
      'no_pending_interactions',
      'artifact_evidence',
      'approval_boundary',
      'workflow_state',
      'provider_health',
    ],
    'guidance': [
      'This tool checks structured session, interaction, and artifact evidence.',
      'It does not parse the user prompt to infer intent.',
      'If a check fails, collect evidence, register an artifact, resolve pending input, or stop at the approval boundary.',
    ],
  };
}

Map<String, dynamic> _checkWorkflow(
  ToolContext context, {
  required String workflow,
  required Map<String, dynamic> spec,
  required String? artifactId,
  required String? workflowStateId,
  required bool requireWorkflowState,
  required Object? providerHealth,
  required String? strategyId,
  required List<String> targetSymbols,
  required int limit,
}) {
  final session = _readSession(context, limit);
  final pending = _pendingInteractionsForSession(session);
  final artifactEvidence = _artifactEvidence(context, spec, artifactId);
  final workflowStateEvidence = _workflowStateEvidence(
    context,
    workflow: workflow,
    workflowStateId: workflowStateId,
    required: requireWorkflowState || workflowStateId != null,
  );
  final providerHealthEvidence = _providerHealthEvidence(providerHealth);
  final workflowSpecificEvidence = _workflowSpecificEvidence(
    workflow,
    session,
    strategyId: strategyId,
    targetSymbols: targetSymbols,
  );
  final workflowSpecificPassed =
      ((workflowSpecificEvidence['checks'] as List)
              .whereType<Map<String, dynamic>>())
          .every((check) => check['passed'] == true);
  final approvalBoundary = spec['approvalBoundary'] as String? ?? 'none';
  final approvalBoundaryEvidence = _approvalBoundaryEvidence(
    approvalBoundary,
    workflow,
    session,
    pending.length,
  );
  final requiredAnyTools = _stringList(spec['requiredAnyTools']);
  final toolNames = (session['toolNames'] as List).whereType<String>().toSet();
  final usedRequiredTool = requiredAnyTools.any(toolNames.contains);
  final toolErrorCount = session['toolErrorCount'] as int;
  final unrecoveredErrors = _unrecoveredToolErrors(
    session,
    workflow: workflow,
    workflowSpecificPassed: workflowSpecificPassed,
  );
  final checks = [
    _check(
      'tool_calls_present',
      (session['toolCallCount'] as int) > 0,
      'At least one tool call is visible.',
      'No tool call is visible for this workflow.',
    ),
    _check(
      'required_tool_family',
      usedRequiredTool,
      'A required tool family was used.',
      'No required tool family was used. Expected one of: ${requiredAnyTools.join(', ')}.',
    ),
    _check(
      'no_tool_errors',
      unrecoveredErrors.isEmpty,
      toolErrorCount == 0
          ? 'No tool errors are visible.'
          : '${toolErrorCount - unrecoveredErrors.length} recovered tool error(s); no unrecovered tool errors remain.',
      '${unrecoveredErrors.length} unrecovered tool error(s) are visible: ${unrecoveredErrors.join('; ')}',
    ),
    _check(
      'no_pending_interactions',
      pending.isEmpty,
      'No pending AskUserQuestion or approval is visible.',
      '${pending.length} pending interaction(s) must be resolved before finalizing.',
    ),
    _check(
      'artifact_evidence',
      artifactEvidence['passed'] == true,
      artifactEvidence['reason'] as String? ??
          'Required artifact evidence is registered.',
      artifactEvidence['reason'] as String? ??
          'Required artifact evidence is missing.',
    ),
    _check(
      'approval_boundary',
      approvalBoundaryEvidence['passed'] == true,
      approvalBoundaryEvidence['passedMessage'] as String,
      approvalBoundaryEvidence['reason'] as String,
    ),
    _check(
      'workflow_state',
      workflowStateEvidence['passed'] == true,
      workflowStateEvidence['passedMessage'] as String? ??
          'Typed workflow state is valid.',
      workflowStateEvidence['reason'] as String? ??
          'Typed workflow state is missing or invalid.',
    ),
    _check(
      'provider_health',
      providerHealthEvidence['passed'] == true,
      providerHealthEvidence['passedMessage'] as String? ??
          'Provider health is valid.',
      providerHealthEvidence['reason'] as String? ??
          'Provider health contains blocking evidence.',
    ),
    ...((workflowSpecificEvidence['checks'] as List)
        .whereType<Map<String, dynamic>>()),
  ];
  final missing = checks
      .where((check) => check['passed'] != true)
      .map((check) => check['id'])
      .toList();
  return {
    'contract': 'workflow-verifier-check-v1',
    'workflow': workflow,
    'passed': missing.isEmpty,
    'missing': missing,
    'checks': checks,
    'observed': {
      'toolNames': toolNames.toList()..sort(),
      'pendingInteractions': pending.length,
      'artifact': artifactEvidence['artifact'],
      'workflowState': workflowStateEvidence['record'],
      'providerHealth': providerHealthEvidence['observed'],
      'approvalBoundary': approvalBoundaryEvidence['observed'],
      'workflowSpecific': workflowSpecificEvidence['observed'],
    },
    'nextAction': missing.isEmpty
        ? 'Final answer may cite the verified workflow evidence.'
        : 'Do not finalize yet. Resolve missing checks: ${missing.join(', ')}.',
  };
}

List<Map<String, dynamic>> _pendingInteractionsForSession(
  Map<String, dynamic> session,
) {
  final calls = (session['calls'] as List).whereType<Map<String, dynamic>>();
  return calls.where((call) {
    if (call.containsKey('result')) return false;
    final name = '${call['name'] ?? ''}';
    return name == 'AskUserQuestion' ||
        name == 'Approval' ||
        name == 'Permission';
  }).toList();
}

Map<String, dynamic> _readSession(ToolContext context, int limit) {
  final file = File('${context.basePath}/sessions/current.jsonl');
  if (!file.existsSync()) {
    return {'toolCallCount': 0, 'toolErrorCount': 0, 'toolNames': <String>[]};
  }
  final toolNames = <String>{};
  final pendingCalls = <String, Map<String, dynamic>>{};
  final calls = <Map<String, dynamic>>[];
  var toolCallCount = 0;
  var toolErrorCount = 0;
  for (final line in file.readAsLinesSync().reversed.take(limit).toList().reversed) {
    final text = line.trim();
    if (text.isEmpty) continue;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map<String, dynamic>) continue;
      final toolUses = decoded['toolUses'];
      if (toolUses is List) {
        toolCallCount += toolUses.length;
        for (final item in toolUses) {
          if (item is Map && item['name'] is String) {
            final name = item['name'] as String;
            toolNames.add(name);
            final input = item['input'];
            final evidence = <String, dynamic>{
              'name': name,
              'input': input is Map
                  ? Map<String, dynamic>.from(input)
                  : <String, dynamic>{},
            };
            final id = item['id'];
            if (id is String && id.isNotEmpty) pendingCalls[id] = evidence;
            calls.add(evidence);
          }
        }
      }
      final result = decoded['toolResult'] ?? decoded['tool_result'];
      if (result is Map) {
        final isError = result['isError'] == true;
        if (isError) toolErrorCount++;
        final toolUseId = result['toolUseId'];
        final evidence = toolUseId is String ? pendingCalls[toolUseId] : null;
        if (evidence != null) {
          evidence['result'] = result['content'] is String
              ? result['content'] as String
              : jsonEncode(result['content'] ?? '');
          evidence['isError'] = isError;
        }
      }
    } catch (_) {
      continue;
    }
  }
  return {
    'toolCallCount': toolCallCount,
    'toolErrorCount': toolErrorCount,
    'toolNames': toolNames.toList(),
    'calls': calls,
  };
}

Map<String, dynamic> _workflowSpecificEvidence(
  String workflow,
  Map<String, dynamic> session,
  {String? strategyId, List<String> targetSymbols = const []}
) {
  if (workflow == 'fund_selection') return _fundSelectionEvidence(session);
  if (workflow == 'watchlist_handoff') {
    return _watchlistHandoffEvidence(session);
  }
  if (workflow == 'strategy_rerun') {
    return _strategyRerunEvidence(
      session,
      strategyId: strategyId,
      targetSymbols: targetSymbols,
    );
  }
  if (workflow == 'trade_preparation') {
    return _tradePreparationEvidence(session);
  }
  return {'checks': <Map<String, dynamic>>[], 'observed': <String, dynamic>{}};
}

Map<String, dynamic> _approvalBoundaryEvidence(
  String approvalBoundary,
  String workflow,
  Map<String, dynamic> session,
  int pendingCount,
) {
  if (approvalBoundary != 'explicit_approval_required') {
    return {
      'passed': true,
      'passedMessage': 'Workflow has no trade approval boundary.',
      'reason': 'Workflow has no trade approval boundary.',
      'observed': {'boundary': approvalBoundary},
    };
  }
  if (workflow != 'trade_preparation') {
    return {
      'passed': pendingCount > 0,
      'passedMessage': 'Explicit approval or user question is pending.',
      'reason':
          'Workflow requires explicit approval evidence before any side-effect.',
      'observed': {
        'boundary': approvalBoundary,
        'pendingInteractions': pendingCount,
      },
    };
  }
  final tradeEvidence = _tradePreparationEvidence(session);
  final observed = Map<String, dynamic>.from(
    tradeEvidence['observed'] as Map,
  );
  final sideEffects = (observed['sideEffectCalls'] as List?) ?? const [];
  final hasAccount = observed['accountEvidence'] == true;
  final hasSizing = observed['sizingEvidence'] == true;
  return {
    'passed': sideEffects.isEmpty && hasAccount && hasSizing,
    'passedMessage':
        'Trade-preparation boundary is satisfied: account/sizing evidence exists and no order side-effect is visible.',
    'reason': sideEffects.isNotEmpty
        ? 'Trade-preparation has order side-effect calls: ${sideEffects.join(', ')}.'
        : 'Trade-preparation needs account evidence and sizing/quote evidence while avoiding order side-effect calls.',
    'observed': observed,
  };
}

Map<String, dynamic> _tradePreparationEvidence(Map<String, dynamic> session) {
  final calls = (session['calls'] as List).whereType<Map<String, dynamic>>();
  final accountCalls = calls.where((call) {
    if (call['isError'] == true) return false;
    final name = '${call['name'] ?? ''}';
    final input = call['input'];
    final action = input is Map ? '${input['action'] ?? ''}' : '';
    if (name == 'XueqiuTrade') {
      return const {'balance', 'portfolios', 'positions', 'history'}
          .contains(action);
    }
    if (name == 'Portfolio') {
      return const {'snapshot', 'positions'}.contains(action);
    }
    return false;
  }).toList();
  final sizingCalls = calls.where((call) {
    if (call['isError'] == true) return false;
    final name = '${call['name'] ?? ''}';
    final input = call['input'];
    final action = input is Map ? '${input['action'] ?? ''}' : '';
    if (name == 'MarketData' &&
        const {'quote', 'query_quote'}.contains(action)) {
      return true;
    }
    if (name == 'DataStore' && action == 'query_quote') return true;
    if (name == 'DataProcess' &&
        const {'position_sizing', 'risk_sizing', 'indicators', 'support'}
            .contains(action)) {
      return true;
    }
    if (name == 'Portfolio' &&
        const {'preview_trade', 'position_sizing'}.contains(action)) {
      return true;
    }
    return false;
  }).toList();
  final sideEffectCalls = calls
      .where(_isTradeSideEffectCall)
      .map((call) {
        final input = call['input'];
        final action = input is Map ? '${input['action'] ?? ''}' : '';
        return action.isNotEmpty ? '${call['name']}.$action' : '${call['name']}';
      })
      .toList();
  return {
    'checks': [
      _check(
        'trade_account_evidence',
        accountCalls.isNotEmpty,
        'Simulated account or portfolio state evidence is visible.',
        'Trade preparation needs simulated account/portfolio state before sizing.',
      ),
      _check(
        'trade_sizing_evidence',
        sizingCalls.isNotEmpty,
        'Sizing, quote, or risk evidence is visible.',
        'Trade preparation needs quote/sizing/risk evidence before finalizing.',
      ),
      _check(
        'trade_no_side_effect',
        sideEffectCalls.isEmpty,
        'No simulated order or cash-transfer side-effect call is visible.',
        'Trade preparation must not include order/cash-transfer side effects: ${sideEffectCalls.join(', ')}.',
      ),
    ],
    'observed': {
      'accountEvidence': accountCalls.isNotEmpty,
      'sizingEvidence': sizingCalls.isNotEmpty,
      'sideEffectCalls': sideEffectCalls,
      'accountCalls': accountCalls.map(_summarizeCall).toList(),
      'sizingCalls': sizingCalls.map(_summarizeCall).toList(),
    },
  };
}

bool _isTradeSideEffectCall(Map<String, dynamic> call) {
  final name = '${call['name'] ?? ''}';
  final input = call['input'];
  final action = input is Map ? '${input['action'] ?? ''}'.toLowerCase() : '';
  if (name == 'XueqiuTrade') {
    return const {
      'buy',
      'sell',
      'transfer_in',
      'transfer_out',
      'bank_transfer',
      'add_transaction',
      'transaction_add',
    }.contains(action);
  }
  if (name == 'Portfolio') {
    return const {'trade', 'buy', 'sell', 'transfer'}.contains(action);
  }
  return false;
}

Map<String, dynamic> _watchlistHandoffEvidence(Map<String, dynamic> session) {
  final calls = (session['calls'] as List).whereType<Map<String, dynamic>>();
  final addCalls = calls.where((call) {
    if (call['isError'] == true || call['name'] != 'Watchlist') return false;
    final input = call['input'];
    return input is Map && '${input['action'] ?? ''}' == 'add';
  }).toList();
  final readbackCalls = calls.where((call) {
    if (call['isError'] == true || call['name'] != 'Watchlist') return false;
    final input = call['input'];
    final action = input is Map ? '${input['action'] ?? ''}' : '';
    return const {'list', 'get', 'readback'}.contains(action);
  }).toList();
  final conditionCalls = addCalls.where((call) {
    final input = call['input'];
    if (input is! Map) return false;
    return _hasText(input['entryCondition']) ||
        _hasText(input['exitCondition']) ||
        input.containsKey('targetEntryPrice') ||
        input.containsKey('stopLoss') ||
        input.containsKey('targetPrice') ||
        input['conditions'] is List;
  }).toList();
  final sourceCalls = addCalls.where((call) {
    final input = call['input'];
    if (input is! Map) return false;
    return _hasText(input['source']) ||
        _hasText(input['sourceTime']) ||
        _hasText(input['fetchedAt']) ||
        _hasText(input['strategyId']) ||
        _hasText(input['score']) ||
        _hasText(input['rating']);
  }).toList();
  final sideEffectCalls = calls
      .where(_isTradeSideEffectCall)
      .map((call) {
        final input = call['input'];
        final action = input is Map ? '${input['action'] ?? ''}' : '';
        return action.isNotEmpty ? '${call['name']}.$action' : '${call['name']}';
      })
      .toList();
  return {
    'checks': [
      _check(
        'watchlist_add_evidence',
        addCalls.isNotEmpty,
        'Watchlist add evidence is visible.',
        'Watchlist handoff needs Watchlist(action:"add") evidence before finalizing.',
      ),
      _check(
        'watchlist_readback_evidence',
        readbackCalls.isNotEmpty,
        'Watchlist readback evidence is visible.',
        'Watchlist handoff needs Watchlist(action:"list"|"get"|"readback") after mutation before finalizing.',
      ),
      _check(
        'watchlist_condition_evidence',
        conditionCalls.isNotEmpty,
        'Watchlist condition evidence is visible.',
        'Watchlist handoff needs structured observation conditions such as entryCondition, exitCondition, targetEntryPrice, stopLoss, targetPrice, or conditions[].',
      ),
      _check(
        'watchlist_source_evidence',
        sourceCalls.isNotEmpty,
        'Watchlist source/provenance evidence is visible.',
        'Watchlist handoff needs source, sourceTime/fetchedAt, strategyId, score, or rating evidence on the added item.',
      ),
      _check(
        'watchlist_no_trade_side_effect',
        sideEffectCalls.isEmpty,
        'No trade side-effect call is visible.',
        'Watchlist handoff must not include trade side effects: ${sideEffectCalls.join(', ')}.',
      ),
    ],
    'observed': {
      'added': addCalls.map(_summarizeCall).toList(),
      'readback': readbackCalls.map(_summarizeCall).toList(),
      'conditionEvidence': conditionCalls.map(_summarizeCall).toList(),
      'sourceEvidence': sourceCalls.map(_summarizeCall).toList(),
      'sideEffectCalls': sideEffectCalls,
    },
  };
}

Map<String, dynamic> _fundSelectionEvidence(Map<String, dynamic> session) {
  final fundList = _successfulAction(session, 'query_fund_list');
  final performance = _successfulAction(session, 'query_fund_performance');
  final navOrYield = _successfulAction(session, 'query_fund_nav') ??
      _successfulAction(session, 'query_fund_money_yield');
  final holding = _successfulAction(session, 'query_fund_holding');
  final calls = (session['calls'] as List).whereType<Map<String, dynamic>>();
  final macroOrNewsCalls = calls.where((call) {
    final input = call['input'];
    final action = input is Map ? '${input['action'] ?? ''}' : '';
    return action.startsWith('query_macro') || action == 'query_finance_news';
  }).length;
  return {
    'checks': [
      _check(
        'fund_identity_evidence',
        fundList != null,
        'Fund identity/category readback is visible.',
        'Fund selection needs query_fund_list evidence before finalizing.',
      ),
      _check(
        'fund_return_evidence',
        performance != null || navOrYield != null,
        'Fund return evidence is visible.',
        'Fund selection needs query_fund_performance or NAV/money-yield readback before finalizing.',
      ),
      _check(
        'fund_nav_or_yield_evidence',
        navOrYield != null,
        'Fund NAV or money-yield evidence is visible.',
        'Fund selection needs ordinary NAV or money-fund yield evidence before finalizing.',
      ),
      _check(
        'fund_holding_or_missing_reason',
        holding != null || navOrYield != null,
        'Fund holding evidence is visible or NAV/yield evidence is enough for a bounded first pass.',
        'Fund selection needs holding evidence or an explicit missing-holding reason before finalizing.',
      ),
      _check(
        'fund_primary_evidence_not_macro_only',
        fundList != null &&
            navOrYield != null &&
            macroOrNewsCalls < (session['toolCallCount'] as int),
        'Fund evidence is primary; macro/news evidence may be secondary context.',
        'Fund selection cannot finalize as a macro/news-only answer. Use fund identity, NAV/yield, performance, risk, data time, fetched-at, provider/cache, and keep macro/news as secondary context.',
      ),
    ],
    'observed': {
      'fundList': _summarizeCall(fundList),
      'performance': _summarizeCall(performance),
      'navOrYield': _summarizeCall(navOrYield),
      'holding': _summarizeCall(holding),
      'macroOrNewsCalls': macroOrNewsCalls,
    },
  };
}

bool _hasText(Object? value) =>
    value is String && value.trim().isNotEmpty;

Map<String, dynamic>? _successfulAction(
  Map<String, dynamic> session,
  String action,
) {
  final calls = (session['calls'] as List).whereType<Map<String, dynamic>>();
  for (final call in calls) {
    if (call['isError'] == true) continue;
    final input = call['input'];
    if (input is! Map || '${input['action'] ?? ''}' != action) continue;
    final result = '${call['result'] ?? ''}';
    if (result.startsWith('Skipped:')) continue;
    return call;
  }
  return null;
}

Map<String, dynamic>? _summarizeCall(Map<String, dynamic>? call) {
  if (call == null) return null;
  final input = call['input'];
  final args = input is Map ? input : const <String, dynamic>{};
  final result = '${call['result'] ?? ''}';
  return {
    'tool': call['name'],
    'action': args['action'],
    'code': args['code'] ?? args['fundCode'] ?? args['symbol'],
    'resultPreview': result.length > 220 ? result.substring(0, 220) : result,
  };
}

Map<String, dynamic> _strategyRerunEvidence(
  Map<String, dynamic> session, {
  required String? strategyId,
  required List<String> targetSymbols,
}) {
  final runs = <Map<String, Map<String, dynamic>>>[];
  for (final call in _successfulActions(session, 'custom_strategy_run')) {
    final payload = _strategyRunPayload(call);
    if (payload['action'] != 'custom_strategy_run') continue;
    runs.add({'call': call, 'payload': payload});
  }
  final strategyMatched = strategyId == null ||
      runs.any((item) {
        final call = item['call']!;
        final payload = item['payload']!;
        final input = call['input'];
        final inputId =
            input is Map ? '${input['strategyId'] ?? input['strategy_id'] ?? ''}' : '';
        final outputId =
            '${payload['strategyId'] ?? payload['strategy_id'] ?? ''}';
        return inputId == strategyId || outputId == strategyId;
      });
  final missingTargets = targetSymbols.where((symbol) {
    final expected = _normalizeSymbol(symbol);
    return !runs.any((item) {
      return _observedSymbolsForStrategyRun(
        item['call']!,
        item['payload'],
      ).contains(expected);
    });
  }).toList();
  return {
    'checks': [
      _check(
        'strategy_rerun_call',
        runs.isNotEmpty,
        'A successful custom_strategy_run result is visible.',
        'Strategy rerun needs MarketData(action:"custom_strategy_run") evidence before finalizing.',
      ),
      _check(
        'strategy_rerun_strategy_identity',
        strategyMatched,
        strategyId == null
            ? 'No specific strategyId was required for this check.'
            : 'custom_strategy_run evidence matches strategyId $strategyId.',
        'custom_strategy_run evidence does not match required strategyId $strategyId.',
      ),
      _check(
        'strategy_rerun_target_symbols',
        missingTargets.isEmpty,
        targetSymbols.isEmpty
            ? 'No specific target symbol was required for this check.'
            : 'custom_strategy_run evidence covers target symbol(s): ${targetSymbols.join(', ')}.',
        'custom_strategy_run evidence is missing target symbol(s): ${missingTargets.join(', ')}.',
      ),
    ],
    'observed': {
      'expectedStrategyId': strategyId,
      'expectedTargetSymbols': targetSymbols,
      'runs': runs.map((item) {
        final call = item['call']!;
        final payload = item['payload']!;
        final input = call['input'];
        final dataCoverage = payload['dataCoverage'];
        return {
          'input': input,
          'strategyId': payload['strategyId'] ?? payload['strategy_id'],
          'action': payload['action'],
          'code': payload['code'] ?? payload['symbol'],
          'dataCoverage': dataCoverage,
        };
      }).toList(),
    },
  };
}

List<Map<String, dynamic>> _successfulActions(
  Map<String, dynamic> session,
  String action,
) {
  final calls = (session['calls'] as List).whereType<Map<String, dynamic>>();
  return calls.where((call) {
    if (call['isError'] == true) return false;
    final input = call['input'];
    if (input is! Map || '${input['action'] ?? ''}' != action) return false;
    final result = '${call['result'] ?? ''}';
    return !result.startsWith('Skipped:');
  }).toList();
}

Map<String, dynamic>? _jsonObject(String value) {
  try {
    final decoded = jsonDecode(value);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

Map<String, dynamic> _strategyRunPayload(Map<String, dynamic> call) {
  final result = '${call['result'] ?? ''}';
  final parsed = _jsonObject(result);
  if (parsed?['action'] == 'custom_strategy_run') return parsed!;
  final input = call['input'];
  final args = input is Map ? input : const {};
  final symbols = args['symbols'];
  return {
    'action': 'custom_strategy_run',
    'strategyId':
        args['strategyId'] ??
        args['strategy_id'] ??
        RegExp(r'"strategyId"\s*:\s*"([^"]+)"')
            .firstMatch(result)
            ?.group(1),
    'strategy_id': args['strategy_id'],
    'code':
        args['code'] ??
        args['symbol'] ??
        (symbols is List && symbols.isNotEmpty ? symbols.first : null) ??
        RegExp(r'"code"\s*:\s*"([^"]+)"').firstMatch(result)?.group(1) ??
        RegExp(r'"symbol"\s*:\s*"([^"]+)"').firstMatch(result)?.group(1),
  };
}

Set<String> _observedSymbolsForStrategyRun(
  Map<String, dynamic> call,
  Map<String, dynamic>? payload,
) {
  final input = call['input'];
  final args = input is Map ? input : const {};
  final coverage = payload?['dataCoverage'];
  final symbols = <String>{};
  for (final value in [
    args['code'],
    args['symbol'],
    payload?['code'],
    payload?['symbol'],
    if (coverage is Map) coverage['symbol'],
  ]) {
    final normalized = _normalizeSymbol(value);
    if (normalized.isNotEmpty) symbols.add(normalized);
  }
  for (final value in [args['codes'], args['symbols']]) {
    for (final item in _stringList(value)) {
      final normalized = _normalizeSymbol(item);
      if (normalized.isNotEmpty) symbols.add(normalized);
    }
  }
  return symbols;
}

Map<String, dynamic> _artifactEvidence(
  ToolContext context,
  Map<String, dynamic> spec,
  String? artifactId,
) {
  final registry = ArtifactRegistry(context.basePath);
  final artifacts = registry.list();
  final normalizedId = artifactId != null && artifactId.startsWith('artifact:')
      ? artifactId.substring(9)
      : artifactId;
  if (normalizedId != null && normalizedId.isNotEmpty) {
    for (final artifact in artifacts) {
      if (artifact.id == normalizedId || artifact.stableRef == artifactId) {
        return {'passed': true, 'artifact': artifact.toJson()};
      }
    }
    return {
      'passed': false,
      'reason': 'Required artifact "$artifactId" is not registered.',
    };
  }
  if (spec['artifactRequired'] == false) {
    return {
      'passed': true,
      'reason': 'Artifact evidence is optional for this workflow.',
    };
  }
  final kinds = _stringList(spec['artifactKinds']);
  for (final artifact in artifacts) {
    if (kinds.contains(artifact.kind.wireName)) {
      return {'passed': true, 'artifact': artifact.toJson()};
    }
  }
  if (spec['macroEvidenceRecord'] == true) {
    final evidence = _macroEvidenceRecordEvidence(context);
    if (evidence['passed'] == true) return evidence;
  }
  return {
    'passed': false,
    'reason': 'No registered artifact of required kind: ${kinds.join(', ')}.',
  };
}

Map<String, dynamic> _macroEvidenceRecordEvidence(ToolContext context) {
  final dir = Directory('${context.memoryDir}/macro_evidence');
  if (!dir.existsSync()) {
    return {
      'passed': false,
      'reason':
          'No macro evidence record directory exists. Use SourceReader(action:"macroEvidence") before finalizing.',
    };
  }
  final files = dir
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  for (final file in files) {
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) continue;
      final record = Map<String, dynamic>.from(decoded);
      final missing = _missingMacroEvidenceFields(record);
      if (missing.isNotEmpty) {
        return {
          'passed': false,
          'reason':
              'Latest macro evidence record is missing structured fields: ${missing.join(', ')}.',
          'artifact': record,
        };
      }
      return {
        'passed': true,
        'artifact': {
          'kind': 'macro_evidence',
          'path': file.path,
          'record': record,
        },
      };
    } catch (_) {
      continue;
    }
  }
  return {
    'passed': false,
    'reason':
        'No readable macro-evidence-record-v1 JSON file exists. Use SourceReader(action:"macroEvidence").',
  };
}

List<String> _missingMacroEvidenceFields(Map<String, dynamic> record) {
  final missing = <String>[];
  for (final field in [
    'contract',
    'source',
    'title',
    'topic',
    'region',
    'assetClass',
    'confidenceEffect',
    'tradeBoundary',
  ]) {
    final value = record[field];
    if (value == null || value.toString().trim().isEmpty) missing.add(field);
  }
  if (record['contract'] != 'macro-evidence-record-v1') missing.add('contract:macro-evidence-record-v1');
  if (record['keyClaims'] is! List || (record['keyClaims'] as List).isEmpty) {
    missing.add('keyClaims');
  }
  if (record['affectedAssets'] is! List ||
      (record['affectedAssets'] as List).isEmpty) {
    missing.add('affectedAssets');
  }
  return missing;
}

Map<String, dynamic> _workflowStateEvidence(
  ToolContext context, {
  required String workflow,
  required String? workflowStateId,
  required bool required,
}) {
  final expectedKind = _workflowKindForVerifierWorkflow(workflow);
  final records = _readWorkflowStateRecords(context);
  Map<String, dynamic>? record;
  if (workflowStateId != null && workflowStateId.isNotEmpty) {
    record = records.cast<Map<String, dynamic>?>().firstWhere(
      (item) => item?['id'] == workflowStateId,
      orElse: () => null,
    );
  } else {
    record = records.cast<Map<String, dynamic>?>().firstWhere((item) {
      final state = item?['workflowState'];
      return item?['status'] == 'active' &&
          state is Map &&
          state['workflowKind'] == expectedKind;
    }, orElse: () => null);
  }
  if (record == null) {
    if (!required) {
      return {
        'passed': true,
        'passedMessage':
            'Typed workflow state was not required for this check.',
      };
    }
    return {
      'passed': false,
      'reason': workflowStateId != null && workflowStateId.isNotEmpty
          ? 'Required workflow state "$workflowStateId" is not saved.'
          : 'No active saved FinanceWorkflowState for expected kind "$expectedKind".',
    };
  }
  final state = record['workflowState'];
  final kind = state is Map ? state['workflowKind'] : null;
  if (kind != expectedKind) {
    return {
      'passed': false,
      'record': record,
      'reason':
          'Saved workflow state kind "$kind" does not match expected "$expectedKind".',
    };
  }
  if (record['status'] == 'blocked') {
    return {
      'passed': false,
      'record': record,
      'reason':
          'Saved workflow state is blocked: ${record['blocker'] ?? 'blocker not specified'}.',
    };
  }
  return {
    'passed': true,
    'passedMessage': 'Typed workflow state is saved and matches this workflow.',
    'record': record,
  };
}

Map<String, dynamic> _providerHealthEvidence(Object? raw) {
  final rows = raw is List
      ? raw
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList()
      : const <Map<String, dynamic>>[];
  if (rows.isEmpty) {
    return {
      'passed': true,
      'passedMessage':
          'Provider health evidence was not supplied for this check.',
      'observed': rows,
    };
  }
  const blockingStatuses = {
    'unhealthy',
    'blocked',
    'runtime_unavailable',
    'transport_unstable',
    'quota_exhausted',
    'credential_missing',
    'credential-or-quota-required',
  };
  final blocking = rows.where((row) {
    final status = '${row['status'] ?? row['classification'] ?? ''}'
        .trim()
        .toLowerCase();
    return blockingStatuses.contains(status);
  }).toList();
  if (blocking.isNotEmpty) {
    final labels = blocking
        .map((row) {
          final provider = row['provider'] ?? row['source'] ?? 'provider';
          final status = row['status'] ?? row['classification'] ?? 'blocked';
          return '$provider:$status';
        })
        .join(', ');
    return {
      'passed': false,
      'reason': 'Provider health has blocking rows: $labels.',
      'observed': rows,
    };
  }
  return {
    'passed': true,
    'passedMessage': 'Provider health evidence has no blocking rows.',
    'observed': rows,
  };
}

List<Map<String, dynamic>> _readWorkflowStateRecords(ToolContext context) {
  final file = File('${context.memoryDir}/workflows/state.json');
  if (!file.existsSync()) return const [];
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map) return const [];
    final records = decoded['records'];
    if (records is! List) return const [];
    return records
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    return const [];
  }
}

String _workflowKindForVerifierWorkflow(String workflow) {
  switch (workflow) {
    case 'market_overview':
      return 'market_analysis';
    case 'stock_research':
      return 'stock_research';
    case 'stock_selection':
      return 'stock_selection';
    case 'watchlist_handoff':
      return 'watchlist_handoff';
    case 'fund_selection':
      return 'fund_research';
    case 'strategy_backtest':
      return 'strategy_review';
    case 'strategy_rerun':
      return 'strategy_rerun';
    case 'trade_preparation':
      return 'trade_preparation';
    case 'trade_review':
      return 'trade_review';
    case 'trade_prep':
      return 'trade_prep';
    case 'macro_factor_lookup':
      return 'macro_attribution';
    default:
      return 'unknown';
  }
}

Map<String, dynamic> _check(
  String id,
  bool passed,
  String passedMessage,
  String failedMessage,
) => {
  'id': id,
  'passed': passed,
  'message': passed ? passedMessage : failedMessage,
};

List<String> _unrecoveredToolErrors(
  Map<String, dynamic> session, {
  required String workflow,
  required bool workflowSpecificPassed,
}) {
  final calls = (session['calls'] as List?)?.whereType<Map>().toList() ?? [];
  final failures = <String>[];
  for (var index = 0; index < calls.length; index++) {
    final call = calls[index];
    if (call['isError'] != true) continue;
    if (_isRecoveredByWorkflowEvidence(
      call,
      workflow: workflow,
      workflowSpecificPassed: workflowSpecificPassed,
    )) {
      continue;
    }
    final input = call['input'];
    final action = input is Map ? '${input['action'] ?? ''}' : '';
    final name = '${call['name'] ?? ''}';
    final recovered = calls.skip(index + 1).any((later) {
      if (later['isError'] == true || later['name'] != name) return false;
      final laterInput = later['input'];
      final laterAction = laterInput is Map ? '${laterInput['action'] ?? ''}' : '';
      return laterAction == action;
    });
    if (!recovered) failures.add(action.isEmpty ? name : '$name.$action');
  }
  return failures;
}

bool _isRecoveredByWorkflowEvidence(
  Map<dynamic, dynamic> call, {
  required String workflow,
  required bool workflowSpecificPassed,
}) {
  if (!workflowSpecificPassed || workflow != 'watchlist_handoff') return false;
  final name = '${call['name'] ?? ''}';
  return name == 'DataStore' ||
      name == 'MarketData' ||
      name == 'DataProcess' ||
      name == 'Research';
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList();
}

String? _optionalString(Object? value) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? null : text;
}

String _normalizeSymbol(Object? value) => '${value ?? ''}'.trim().toUpperCase();

int _intValue(Object? value, {required int defaultValue}) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? defaultValue;
}
