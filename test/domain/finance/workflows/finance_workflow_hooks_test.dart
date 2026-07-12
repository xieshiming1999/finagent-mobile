import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stock workflow does not finalize with accidental fund evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(workflowKind: 'stock_research', assetClass: 'stock'),
      _assistantWithToolUse('fund-performance', 'MarketData', {
        'action': 'fund_performance',
      }),
      _tool('fund-performance', _fundPerformancePayload()),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: null,
      toolCalls: const [
        ToolUse(id: 'dp-1', name: 'DataProcess', input: {'action': 'signals'}),
      ],
    );

    expect(interception, isNull);
  });

  test('fund workflow can finalize from structured fund comparison evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(workflowKind: 'fund_research', assetClass: 'fund'),
      _assistantWithToolUse('fund-performance', 'MarketData', {
        'action': 'fund_performance',
      }),
      _tool('fund-performance', _fundPerformancePayload()),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: null,
      toolCalls: const [
        ToolUse(id: 'dp-1', name: 'DataProcess', input: {'action': 'signals'}),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.answer, contains('基金比较证据口径'));
  });

  test('empty stock final answer recovers from structured stock evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(workflowKind: 'stock_research', assetClass: 'stock'),
      _tool('quote', {
        'action': 'query_quote',
        'source': 'local quote_snapshot',
        'cacheStatus': 'cache-hit',
        'sourceDataTime': '2026-07-12T12:14:21Z',
        'fetchedAt': '2026-07-12T12:14:21Z',
        'data': [
          {
            'code': '300059',
            'name': '东方财富',
            'price': 20.19,
            'changePct': -1.94,
            'source': '东方财富',
          },
        ],
      }),
      _tool('kline', {
        'action': 'query_kline',
        'symbol': '300059',
        'source': 'local kline_daily',
        'cacheStatus': 'cache-hit',
        'data': [
          {'date': '2026-07-09', 'close': 20.59},
          {'date': '2026-07-10', 'close': 20.19},
        ],
      }),
      _tool('valuation', {
        'action': 'query_stock_daily_valuation',
        'symbol': '300059',
        'source': 'local fundamental',
        'cacheStatus': 'cache-miss',
        'count': 0,
        'data': const [],
      }),
    ];

    final answer = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: null,
      answer: '',
    );

    expect(answer, isNotNull);
    expect(answer, contains('东方财富 300059'));
    expect(answer, contains('最终模型输出为空或被截断'));
    expect(answer, contains('风险'));
  });

  test('required verifier gate blocks final answer until verifier passes', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(
        workflowKind: 'strategy_review',
        assetClass: 'stock',
        requiredVerifier: {
          'tool': 'WorkflowVerifier',
          'action': 'check',
          'workflow': 'strategy_rerun',
        },
      ),
      _assistantWithToolUse('run', 'MarketData', {
        'action': 'custom_strategy_run',
        'strategyId': 'custom_moutai_low_risk_pullback_v1_v1',
        'symbols': ['300059'],
      }),
      _tool('run', {
        'action': 'custom_strategy_run',
        'strategyId': 'custom_moutai_low_risk_pullback_v1_v1',
        'code': '300059',
        'dataCoverage': {'symbol': '300059', 'sufficient': true},
      }),
    ];

    expect(
      hooks.finalAnswerNeedsRequiredVerifier(
        messages: messages,
        turnStartIndex: 0,
      ),
      isTrue,
    );

    final verifiedMessages = [
      ...messages,
      _assistantWithToolUse('verify', 'WorkflowVerifier', {
        'action': 'check',
        'workflow': 'strategy_rerun',
        'strategyId': 'custom_moutai_low_risk_pullback_v1_v1',
        'targetSymbols': ['300059'],
      }),
      _tool('verify', {
        'contract': 'workflow-verifier-check-v1',
        'workflow': 'strategy_rerun',
        'passed': true,
        'missing': const [],
      }),
    ];

    expect(
      hooks.finalAnswerNeedsRequiredVerifier(
        messages: verifiedMessages,
        turnStartIndex: 0,
      ),
      isFalse,
    );
  });

  test('strategy rerun requires verifier after rerun evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(
        workflowKind: 'strategy_review',
        assetClass: 'stock',
        requiredVerifier: {
          'tool': 'WorkflowVerifier',
          'action': 'check',
          'workflow': 'strategy_rerun',
        },
      ),
      _assistantWithToolUse('early-verify', 'WorkflowVerifier', {
        'action': 'check',
        'workflow': 'strategy_rerun',
      }),
      _tool('early-verify', {
        'contract': 'workflow-verifier-check-v1',
        'workflow': 'strategy_rerun',
        'passed': true,
        'missing': const [],
      }),
      _assistantWithToolUse('run', 'MarketData', {
        'action': 'custom_strategy_run',
        'strategyId': 'custom_moutai_low_risk_pullback_v1_v1',
        'symbols': ['300059'],
      }),
      _tool('run', {
        'action': 'custom_strategy_run',
        'strategyId': 'custom_moutai_low_risk_pullback_v1_v1',
        'code': '300059',
        'dataCoverage': {'symbol': '300059', 'sufficient': true},
      }),
    ];

    expect(
      hooks.finalAnswerNeedsRequiredVerifier(
        messages: messages,
        turnStartIndex: 0,
      ),
      isTrue,
    );
  });

  test('strategy rerun preflight emits verifier before summary answer', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(
        workflowKind: 'strategy_review',
        assetClass: 'stock',
        requiredVerifier: {
          'tool': 'WorkflowVerifier',
          'action': 'check',
          'workflow': 'strategy_rerun',
        },
      ),
      _assistantWithToolUse('run', 'MarketData', {
        'action': 'custom_strategy_run',
        'strategyId': 'custom_low_risk_entry_v3',
        'symbols': ['300059'],
      }),
      _tool('run', {
        'action': 'custom_strategy_run',
        'strategyId': 'custom_low_risk_entry_v3',
        'code': '300059',
        'metrics': {'totalReturnPct': 0.0},
        'dataCoverage': {'symbol': '300059', 'sufficient': true},
      }),
    ];

    expect(hooks.buildPreflightAnswer(messages), isNull);
    final calls = hooks.buildPreflightToolCalls(messages);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'WorkflowVerifier');
    expect(calls.single.input['action'], 'check');
    expect(calls.single.input['workflow'], 'strategy_rerun');
    expect(calls.single.input['strategyId'], 'custom_low_risk_entry_v3');
    expect(calls.single.input['targetSymbols'], ['300059']);
  });

  test('trade preparation preflight starts with runbook not verifier', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(
        workflowKind: 'trade_prep',
        assetClass: 'stock',
        requiredVerifier: {
          'tool': 'WorkflowVerifier',
          'action': 'check',
          'workflow': 'trade_preparation',
        },
      ),
    ];

    final calls = hooks.buildPreflightToolCalls(messages);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'Runbook');
    expect(calls.single.input, {
      'action': 'get',
      'workflow': 'trade_preparation',
    });
  });

  test('trade preparation verifier waits for trade evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      _userWithState(
        workflowKind: 'trade_prep',
        assetClass: 'stock',
        requiredVerifier: {
          'tool': 'WorkflowVerifier',
          'action': 'check',
          'workflow': 'trade_preparation',
        },
      ),
      _assistantWithToolUse('runbook', 'Runbook', {
        'action': 'get',
        'workflow': 'trade_preparation',
      }),
      _tool('runbook', {
        'action': 'get',
        'workflow': 'trade_preparation',
      }),
    ];

    expect(hooks.buildPreflightToolCalls(messages), isNull);

    final withEvidence = [
      ...messages,
      _assistantWithToolUse('preview', 'XueqiuTrade', {
        'action': 'preview_order',
        'side': 'buy',
        'symbol': '300059',
        'shares': 1,
      }),
      _tool('preview', {
        'action': 'preview_order',
        'sideEffect': false,
        'order': {'symbol': '300059', 'shares': 1},
      }),
    ];
    final calls = hooks.buildPreflightToolCalls(withEvidence);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'WorkflowVerifier');
    expect(calls.single.input['workflow'], 'trade_preparation');
  });
}

Message _userWithState({
  required String workflowKind,
  required String assetClass,
  Map<String, dynamic>? requiredVerifier,
}) {
  return Message(
    role: Role.user,
    content:
        'data: ${jsonEncode({
          'workflowState': {
            'contract': 'finance-workflow-state-v1',
            'workflowKind': workflowKind,
            'assetClass': assetClass,
            'intentMode': 'analysis',
            'executionMode': 'none',
            'safetyBoundary': 'read-only analysis',
            'evidenceRefs': ['structured-evidence'],
            'confirmationState': 'none',
            if (requiredVerifier != null)
              'requiredVerifier': requiredVerifier,
            'source': 'test',
          },
        })}',
  );
}

Message _assistantWithToolUse(
  String id,
  String name,
  Map<String, dynamic> input,
) {
  return Message(
    role: Role.assistant,
    content: '',
    toolUses: [ToolUse(id: id, name: name, input: input)],
  );
}

Message _tool(String id, Map<String, dynamic> payload) {
  return Message(
    role: Role.tool,
    toolResult: ToolResult(toolUseId: id, content: jsonEncode(payload)),
  );
}

Map<String, dynamic> _fundPerformancePayload() {
  return {
    'action': 'fund_performance',
    'count': 2,
    'source': 'eastmoney',
    'data': [
      {
        'code': '018815',
        'name': '基金A',
        'metric_date': '2026-07-10',
        'return_1y': 12.3,
        'return_ytd': 5.1,
      },
      {
        'code': '018816',
        'name': '基金B',
        'metric_date': '2026-07-10',
        'return_1y': 10.2,
        'return_ytd': 4.8,
      },
    ],
  };
}
