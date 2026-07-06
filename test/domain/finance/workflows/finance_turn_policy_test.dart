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

  test('successful custom strategy run anchors active strategy identity', () {
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

    final sameStrategyReason = policy.blockedToolUseReason(
      const ToolUse(
        id: 'run-same',
        name: 'MarketData',
        input: {
          'action': 'custom_strategy_run',
          'strategyId': 'custom_saved_strategy_v1',
          'symbols': ['300059'],
        },
      ),
    );
    expect(sameStrategyReason, isNull);

    final reason = policy.blockedToolUseReason(
      const ToolUse(
        id: 'run-2',
        name: 'MarketData',
        input: {
          'action': 'custom_strategy_run',
          'strategyId': '600519',
          'symbols': ['600519'],
        },
      ),
    );

    expect(reason, isNotNull);
    final decoded = jsonDecode(reason!) as Map<String, dynamic>;
    expect(decoded['action'], 'finance_turn_policy_block');
    expect(decoded['status'], 'blocked');
    expect(decoded['code'], 'custom_strategy_run_wrong_identity');
    expect(decoded['strategyId'], 'custom_saved_strategy_v1');
    expect(decoded['nextAction'], 'custom_strategy_run');
  });
}
