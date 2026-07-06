import 'package:flutter_test/flutter_test.dart';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_custom_strategy_policy.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_state.dart';

void main() {
  const policy = FinanceCustomStrategyPolicy(isBypassTool: _neverBypass);

  test('blocks proxy validation only from structured unsupported state', () {
    const state = FinanceWorkflowState(
      workflowKind: FinanceWorkflowKind.strategyDesign,
      assetClass: FinanceAssetClass.stock,
      intentMode: FinanceIntentMode.validate,
      executionMode: FinanceExecutionMode.blocked,
      safetyBoundary: 'unsupported strategy parts',
      evidenceRefs: ['StrategySpec'],
      confirmationState: FinanceConfirmationState.none,
      source: 'agent-structured-intent',
      hasUnsupportedExecutableParts: true,
    );
    final answer = policy.unsupportedProxyStopAnswer(
      state: state,
      toolCalls: [_proxyValidateCall()],
    );

    expect(answer, contains('结构化工作流状态'));
    expect(answer, contains('未创建代理规则'));
  });

  test(
    'does not block proxy validation without structured unsupported state',
    () {
      const state = FinanceWorkflowState(
        workflowKind: FinanceWorkflowKind.strategyDesign,
        assetClass: FinanceAssetClass.stock,
        intentMode: FinanceIntentMode.validate,
        executionMode: FinanceExecutionMode.previewOnly,
        safetyBoundary: 'read-only validation',
        evidenceRefs: ['StrategySpec'],
        confirmationState: FinanceConfirmationState.none,
        source: 'agent-structured-intent',
      );
      final answer = policy.unsupportedProxyStopAnswer(
        state: state,
        toolCalls: [_proxyValidateCall()],
      );

      expect(answer, isNull);
    },
  );
}

bool _neverBypass(String _) => false;

ToolUse _proxyValidateCall() => ToolUse(
  id: 'proxy',
  name: 'MarketData',
  input: {
    'action': 'custom_strategy_validate',
    'strategySpec': {
      'name': 'proxy strategy',
      'entry': {
        'conditions': [
          {'indicator': 'rsi', 'operator': '>', 'value': 40},
        ],
      },
    },
  },
);
