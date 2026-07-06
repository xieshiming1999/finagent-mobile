import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_data_budget_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('market workflow state uses broad market budget', () {
    final policy = FinanceDataBudgetPolicy();

    expect(
      policy.wouldExceedBudget(
        prompt: _state('market_analysis'),
        currentDataToolCalls: 7,
        existingBudgetWarnings: 0,
        proposedToolCalls: const [
          ToolUse(id: 'm', name: 'MarketData', input: {'action': 'quote'}),
          ToolUse(id: 'd', name: 'DataProcess', input: {'action': 'signals'}),
        ],
      ),
      isTrue,
    );
  });

  test('prompt text alone does not enable finance bypass boundary', () {
    final policy = FinanceDataBudgetPolicy();

    expect(
      policy.wouldExceedBudget(
        prompt: '帮我分析股票并读取文件',
        currentDataToolCalls: 1,
        existingBudgetWarnings: 0,
        proposedToolCalls: const [
          ToolUse(id: 'r', name: 'Read', input: {'file_path': 'x'}),
        ],
      ),
      isFalse,
    );
  });

  test('workflow state blocks bypass tools after finance data calls', () {
    final policy = FinanceDataBudgetPolicy();

    expect(
      policy.wouldExceedBudget(
        prompt: _state('stock_research'),
        currentDataToolCalls: 1,
        existingBudgetWarnings: 0,
        proposedToolCalls: const [
          ToolUse(id: 'r', name: 'Read', input: {'file_path': 'x'}),
        ],
      ),
      isTrue,
    );
  });
}

String _state(String workflowKind) {
  return 'structured finance request\n'
      'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"$workflowKind","assetClass":"stock","intentMode":"analysis","executionMode":"preview_only","safetyBoundary":"read-only evidence","evidenceRefs":["budget"],"confirmationState":"none","source":"agent-structured-intent"}}';
}
