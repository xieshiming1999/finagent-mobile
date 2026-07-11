import 'dart:convert';

import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

const _runbooks = <String, Map<String, dynamic>>{
  'market_overview': {
    'workflow': 'market_overview',
    'purpose': 'Understand current market condition before stock/fund decisions.',
    'requiredEvidence': ['quote/index', 'sector', 'flow_rank', 'limit_pool', 'news_or_macro'],
    'allowedTools': ['MarketData', 'DataStore', 'Research', 'WorkflowEvidence', 'CapabilityStatus'],
    'artifactTypes': ['analysis', 'dashboard', 'data_evidence'],
    'approvalBoundary': 'No trade or simulated trade action.',
    'failureHandling': ['Use cache when provider is unhealthy.', 'Disclose stale or missing evidence.'],
    'verifier': 'WorkflowVerifier(action:"check", workflow:"market_overview") when available; otherwise CapabilityStatus(action:"evaluate").',
  },
  'stock_research': {
    'workflow': 'stock_research',
    'purpose': 'Analyze one stock with market, technical, fundamental, flow, risk, and macro context.',
    'requiredEvidence': ['quote', 'kline', 'fundamental_or_missing_reason', 'money_flow', 'risk', 'macro_if_relevant'],
    'allowedTools': ['MarketData', 'DataProcess', 'Research', 'Dashboard', 'WorkflowEvidence', 'CapabilityStatus'],
    'artifactTypes': ['analysis', 'dashboard', 'data_evidence'],
    'approvalBoundary': 'No order placement. Use trade-preparation workflow before any simulated trade.',
    'failureHandling': ['Do not invent missing PE/PB/fundamental data.', 'Name provider/cache/source-time gaps.'],
    'verifier': 'WorkflowVerifier(action:"check", workflow:"stock_research") when available; otherwise CapabilityStatus(action:"evaluate").',
  },
  'fund_selection': {
    'workflow': 'fund_selection',
    'purpose': 'Select or compare funds using fund class, NAV/yield, holdings, performance, risk, and suitability evidence.',
    'requiredEvidence': ['fund_list', 'fund_nav_or_money_yield', 'fund_performance', 'fund_holding_or_missing_reason', 'risk'],
    'allowedTools': ['MarketData', 'DataProcess', 'Research', 'WorkflowEvidence', 'CapabilityStatus'],
    'artifactTypes': ['analysis', 'data_evidence'],
    'approvalBoundary': 'No purchase instruction or simulated trade without explicit trade-preparation workflow.',
    'failureHandling': ['Do not use ordinary NAV for known money funds.', 'Separate selection evidence from buy advice.'],
    'verifier': 'WorkflowVerifier(action:"check", workflow:"fund_selection") when available; otherwise CapabilityStatus(action:"evaluate").',
  },
  'strategy_backtest': {
    'workflow': 'strategy_backtest',
    'purpose': 'Convert a strategy idea into StrategySpec, validate, backtest, report, and optionally monitor.',
    'requiredEvidence': ['StrategySpec', 'validation_report', 'backtest_data_coverage', 'fees_slippage_assumptions', 'report'],
    'allowedTools': ['DataProcess', 'MarketData', 'Watchlist', 'WorkflowEvidence', 'CapabilityStatus'],
    'artifactTypes': ['strategy', 'backtest', 'report'],
    'approvalBoundary': 'Backtest and monitor only. Simulated trade requires separate approval boundary.',
    'failureHandling': ['Reject unsupported indicators/operators with repairPlan.', 'Do not run free-form strategy strings.'],
    'verifier': 'WorkflowVerifier(action:"check", workflow:"strategy_backtest") when available; otherwise CapabilityStatus(action:"evaluate").',
  },
  'trade_preparation': {
    'workflow': 'trade_preparation',
    'purpose': 'Prepare a simulated trade with sizing, risk, stop, evidence, and explicit user approval.',
    'requiredEvidence': ['analysis', 'risk_sizing', 'cash_or_portfolio_state', 'approval_state', 'trade_boundary'],
    'allowedTools': ['Portfolio', 'XueqiuTrade', 'AskUserQuestion', 'WorkflowEvidence', 'CapabilityStatus'],
    'artifactTypes': ['trade_preparation', 'data_evidence'],
    'approvalBoundary': 'Must stop for explicit user approval before any simulated order side effect.',
    'failureHandling': ['If approval is missing, stop and ask.', 'If account/portfolio state is unavailable, do not place an order.'],
    'verifier': 'WorkflowVerifier(action:"check", workflow:"trade_preparation") when available; otherwise CapabilityStatus(action:"evaluate").',
  },
};

class RunbookTool extends Tool {
  @override
  String get name => 'Runbook';

  @override
  String get description =>
      'Return structured workflow guidance before acting on broad finance tasks.';

  @override
  String get prompt =>
      'Use Runbook(action:"get", workflow:"...") before broad finance workflows to inspect required evidence, allowed tools, artifact type, approval boundary, and failure handling.';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['help', 'list', 'get'],
        'description': 'help, list available runbooks, or get one runbook',
      },
      'workflow': {
        'type': 'string',
        'enum': _runbooks.keys.toList(),
        'description': 'Workflow id for action=get',
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
    if (action == 'list') {
      return ToolResult(
        toolUseId: toolUseId,
        content: jsonEncode({
          'contract': 'runbook-list-v1',
          'workflows': _runbooks.keys.toList(),
          'guidance': 'Call Runbook(action:"get", workflow:<id>) before broad workflow execution.',
        }),
      );
    }
    if (action != 'get') {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Invalid Runbook action "$action". Use action="help" for supported actions.',
        isError: true,
      );
    }
    final workflow = (input['workflow'] as String?)?.trim() ?? '';
    final runbook = _runbooks[workflow];
    if (runbook == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Unknown Runbook workflow "$workflow". Use Runbook(action:"list") to inspect available workflows.',
        isError: true,
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: jsonEncode({
        'contract': 'runbook-detail-v1',
        ...runbook,
      }),
    );
  }

  Map<String, dynamic> _help() => {
    'contract': 'runbook-help-v1',
    'actions': ['list', 'get'],
    'workflows': _runbooks.keys.toList(),
    'guidance': [
      'Runbook provides workflow rules as structured data, not prompt-text parsing.',
      'Use requiredEvidence and approvalBoundary before choosing tools or finalizing.',
      'If a required evidence class is missing, disclose it or use a verifier/recovery path.',
    ],
  };
}
