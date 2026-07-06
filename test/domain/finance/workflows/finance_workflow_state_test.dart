import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('derives strategy backtest state from governed tool result', () {
    final state = FinanceWorkflowState.latestFromMessages([
      Message(role: Role.user, content: 'any user wording'),
      Message(
        role: Role.assistant,
        toolUses: const [
          ToolUse(
            id: 'bt',
            name: 'MarketData',
            input: {
              'action': 'custom_strategy_backtest',
              'symbols': ['600519'],
              'strategySpec': {'assetClass': 'stock', 'symbol': '600519'},
            },
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'bt',
          content: '''
{
  "action": "custom_strategy_backtest",
  "status": "backtested",
  "symbol": "600519",
  "validation": {
    "spec": {"assetClass": "stock", "symbol": "600519"}
  }
}
''',
        ),
      ),
    ], turnStartIndex: 1);

    expect(state, isNotNull);
    expect(state!.workflowKind, FinanceWorkflowKind.strategyReview);
    expect(state.intentMode, FinanceIntentMode.backtest);
    expect(state.executionMode, FinanceExecutionMode.previewOnly);
    expect(state.subject, '600519');
  });

  test('uses explicit workflowState instead of parsing prompt text', () {
    final state = FinanceWorkflowState.latestFromMessages([
      Message(role: Role.user, content: 'arbitrary text'),
      Message(
        role: Role.assistant,
        toolUses: const [
          ToolUse(
            id: 'validate',
            name: 'MarketData',
            input: {
              'action': 'custom_strategy_validate',
              'workflowState': {
                'contract': 'finance-workflow-state-v1',
                'workflowKind': 'strategyDesign',
                'assetClass': 'stock',
                'intentMode': 'validate',
                'executionMode': 'previewOnly',
                'safetyBoundary': 'validate only',
                'evidenceRefs': ['custom_strategy_validate'],
                'confirmationState': 'none',
                'source': 'agent-structured-intent',
              },
            },
          ),
        ],
      ),
    ], turnStartIndex: 1);

    expect(state, isNotNull);
    expect(state!.intentMode, FinanceIntentMode.validate);
    expect(state.safetyBoundary, 'validate only');
    expect(state.source, 'agent-structured-intent');
  });

  test('accepts cross-runtime snake_case workflowState values', () {
    final state = FinanceWorkflowState.fromJson({
      'contract': 'finance-workflow-state-v1',
      'workflowKind': 'evidence_review',
      'assetClass': 'mixed',
      'intentMode': 'review',
      'executionMode': 'preview_only',
      'safetyBoundary': 'read-only evidence review',
      'evidenceRefs': ['analysis-evidence-v1'],
      'confirmationState': 'none',
      'source': 'agent-structured-intent',
    });

    expect(state.workflowKind, FinanceWorkflowKind.evidenceReview);
    expect(state.assetClass, FinanceAssetClass.mixed);
    expect(state.intentMode, FinanceIntentMode.review);
    expect(state.executionMode, FinanceExecutionMode.previewOnly);
    expect(state.isEvidenceReview, isTrue);
  });

  test('preserves structured blocked tools', () {
    final state = FinanceWorkflowState.fromJson({
      'contract': 'finance-workflow-state-v1',
      'workflowKind': 'trade_prep',
      'assetClass': 'stock',
      'intentMode': 'size',
      'executionMode': 'requires_confirmation',
      'safetyBoundary': 'trade preparation only',
      'evidenceRefs': ['trade-prep-v1'],
      'confirmationState': 'pending',
      'source': 'agent-structured-intent',
      'blockedTools': ['XueqiuTrade', 'Read'],
    });

    expect(state.workflowKind, FinanceWorkflowKind.tradePrep);
    expect(state.blockedTools, containsAll(['XueqiuTrade', 'Read']));
    expect(state.toJson()['blockedTools'], ['XueqiuTrade', 'Read']);
  });

  test('preserves structured multi-subject state', () {
    final state = FinanceWorkflowState.fromJson({
      'contract': 'finance-workflow-state-v1',
      'workflowKind': 'strategy_design',
      'assetClass': 'stock',
      'intentMode': 'backtest',
      'executionMode': 'preview_only',
      'safetyBoundary': 'read-only rank',
      'evidenceRefs': ['custom_strategy_rank'],
      'confirmationState': 'none',
      'source': 'agent-structured-intent',
      'subject': '600519',
      'subjects': ['600519', '000858', '300059'],
    });

    expect(state.subject, '600519');
    expect(state.subjects, ['600519', '000858', '300059']);
    expect(state.toJson()['subjects'], ['600519', '000858', '300059']);
  });

  test('recognizes rejected custom strategy as blocked unsupported state', () {
    final state = FinanceWorkflowState.fromToolResult(
      ToolResult(
        toolUseId: 'validation',
        content: '''
{
  "action": "custom_strategy_validate",
  "status": "rejected",
  "strategyId": "bad_strategy",
  "errors": ["unsupported news sentiment signal"]
}
''',
      ),
    );

    expect(state, isNotNull);
    expect(state!.executionMode, FinanceExecutionMode.blocked);
    expect(state.hasUnsupportedExecutableParts, isTrue);
    expect(state.safetyBoundary, 'unsupported strategy parts');
  });

  test(
    'does not infer unsupported custom strategy state from tool-call text',
    () {
      final state = FinanceWorkflowState.fromToolCall(
        ToolUse(
          id: 'validation',
          name: 'MarketData',
          input: {
            'action': 'custom_strategy_validate',
            'strategySpec': {
              'name': 'news sentiment proxy',
              'entry': {
                'conditions': [
                  {'indicator': 'rsi', 'operator': '>', 'value': 40},
                ],
              },
            },
          },
        ),
      );

      expect(state, isNotNull);
      expect(state!.hasUnsupportedExecutableParts, isFalse);
    },
  );

  test('preserves explicit unsupported state from tool call workflowState', () {
    final state = FinanceWorkflowState.fromToolCall(
      ToolUse(
        id: 'validation',
        name: 'MarketData',
        input: {
          'action': 'custom_strategy_validate',
          'workflowState': {
            'contract': 'finance-workflow-state-v1',
            'workflowKind': 'strategy_design',
            'assetClass': 'stock',
            'intentMode': 'validate',
            'executionMode': 'blocked',
            'safetyBoundary': 'unsupported strategy parts',
            'evidenceRefs': ['StrategySpec'],
            'confirmationState': 'none',
            'source': 'agent-structured-intent',
            'hasUnsupportedExecutableParts': true,
          },
          'strategySpec': {'name': 'proxy strategy'},
        },
      ),
    );

    expect(state, isNotNull);
    expect(state!.hasUnsupportedExecutableParts, isTrue);
    expect(state.executionMode, FinanceExecutionMode.blocked);
  });

  test('derives trade-prep state from strategy signal data payload', () {
    final state = FinanceWorkflowState.latestFromMessages([
      Message(
        role: Role.user,
        content:
            'runtime event\n'
            'data: {"template":"strategy_signal","strategyId":"s1","code":"300059.SZ","signal":"entry","price":20.1,"confirmationRequired":true}',
      ),
    ]);

    expect(state, isNotNull);
    expect(state!.workflowKind, FinanceWorkflowKind.tradePrep);
    expect(state.intentMode, FinanceIntentMode.size);
    expect(state.executionMode, FinanceExecutionMode.requiresConfirmation);
    expect(state.confirmationState, FinanceConfirmationState.pending);
    expect(state.subject, '300059.SZ');
  });
}
