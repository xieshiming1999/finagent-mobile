import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_turn_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom strategy post-save block is structured JSON', () {
    final policy = FinanceTurnPolicy();
    const saveCall = ToolUse(
      id: 'save-1',
      name: 'MarketData',
      input: {
        'action': 'custom_strategy_save',
        'strategySpec': {'id': 'custom_strategy_v1'},
      },
    );
    policy.recordToolResult(
      saveCall,
      ToolResult(
        toolUseId: 'save-1',
        content: jsonEncode({
          'action': 'custom_strategy_save',
          'strategyId': 'custom_strategy_v1',
        }),
        isError: false,
      ),
    );

    final reason = policy.blockedToolUseReason(
      const ToolUse(
        id: 'quote-1',
        name: 'MarketData',
        input: {'action': 'query_quote', 'symbols': ['600519']},
      ),
    );

    expect(reason, isNotNull);
    final decoded = jsonDecode(reason!) as Map<String, dynamic>;
    expect(decoded['action'], 'finance_turn_policy_block');
    expect(decoded['status'], 'blocked');
    expect(decoded['code'], 'custom_strategy_post_save_drift');
    expect(decoded['strategyId'], 'custom_strategy_v1');
    expect(decoded['nextAction'], 'custom_strategy_run');
  });

  test('successful custom strategy run leaves verifier path open', () {
    final policy = FinanceTurnPolicy();
    const runCall = ToolUse(
      id: 'run-1',
      name: 'MarketData',
      input: {
        'action': 'custom_strategy_run',
        'strategyId': 'custom_saved_strategy_v1',
        'symbols': ['600519'],
      },
    );
    final result = ToolResult(
      toolUseId: 'run-1',
      content: jsonEncode({
        'action': 'custom_strategy_run',
        'status': 'backtested',
        'strategyId': 'custom_saved_strategy_v1',
        'symbol': '600519',
      }),
      isError: false,
    );

    policy.recordToolResult(runCall, result);

    expect(policy.shouldStopToolBatchAfterResult(runCall, result), isFalse);

    final verifierReason = policy.blockedToolUseReason(
      const ToolUse(
        id: 'verifier-1',
        name: 'WorkflowVerifier',
        input: {
          'action': 'check',
          'workflow': 'strategy_rerun',
        },
      ),
    );
    expect(verifierReason, isNull);

    final unrelatedReason = policy.blockedToolUseReason(
      const ToolUse(
        id: 'quote-1',
        name: 'DataStore',
        input: {'action': 'query_quote', 'symbol': '300059'},
      ),
    );
    expect(unrelatedReason, isNull);
  });
}
