import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_strategy_budget_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('structured strategy comparison state enables budget summary', () {
    final summary = FinanceStrategyBudgetSummary().buildComparison(
      messages: [
        _user(_state()),
        _tool('indicators', {
          'symbol': '600519',
          'source': 'local indicators',
          'sourceDataTime': '2026-07-02',
          'fetchedAt': '2026-07-02T10:00:00Z',
          'range': '2025-07-02 ~ 2026-07-02',
          'rsi': 42.3,
          'macd_dif': -1.2,
          'macd_hist': -0.3,
          'boll_lower': 1100,
          'boll_mid': 1200,
          'boll_upper': 1300,
          'price_vs_ma20': -0.04,
        }),
      ],
      turnStartIndex: 0,
    );

    expect(summary, isNotNull);
    expect(summary, contains('策略/信号对比'));
    expect(summary, contains('600519'));
    expect(summary, contains('RSI=42.3'));
  });

  test(
    'strategy comparison prompt text alone does not enable budget summary',
    () {
      final summary = FinanceStrategyBudgetSummary().buildComparison(
        messages: [
          _user('比较 RSI、MACD、布林线和均线策略'),
          _tool('indicators', {
            'symbol': '600519',
            'rsi': 42.3,
            'macd_dif': -1.2,
            'boll_upper': 1300,
          }),
        ],
        turnStartIndex: 0,
      );

      expect(summary, isNull);
    },
  );

  test('broad comparison-like evidence refs do not enable budget summary', () {
    final summary = FinanceStrategyBudgetSummary().buildComparison(
      messages: [
        _user(_state(evidenceRefs: ['not_a_comparison_contract'])),
        _tool('indicators', {
          'symbol': '600519',
          'rsi': 42.3,
          'macd_dif': -1.2,
          'boll_upper': 1300,
        }),
      ],
      turnStartIndex: 0,
    );

    expect(summary, isNull);
  });

  test('builds optimize summary from structured optimize_params result', () {
    final summary = FinanceStrategyBudgetSummary().buildOptimize(
      messages: [
        _user('optimize structured strategy'),
        _tool('opt', {
          'action': 'optimize_params',
          'symbol': '600519',
          'period': '3y',
          'bars': 726,
          'combinations': 200,
          'bestParams': {'period': 8, 'oversold': 20, 'overbought': 65},
          'bestResult': {
            'totalReturn': 42.33,
            'winRate': 66.67,
            'sharpe': 8.35,
            'maxDrawdown': -10.16,
            'trades': 9,
          },
          'overfit_note': 'in-sample only',
        }),
      ],
      turnStartIndex: 0,
    );

    expect(summary, contains('RSI 参数优化结果（600519）'));
    expect(summary, contains('搜索组合 200 组'));
    expect(summary, contains('收益 42.33%'));
  });

  test('ignores prose-only optimize_params mentions', () {
    final summary = FinanceStrategyBudgetSummary().buildOptimize(
      messages: [
        _user('optimize structured strategy'),
        _toolText('opt', 'action optimize_params best result in prose only'),
      ],
      turnStartIndex: 0,
    );

    expect(summary, isNull);
  });
}

Message _user(String content) => Message(role: Role.user, content: content);

Message _tool(String id, Map<String, dynamic> payload) => Message(
  role: Role.tool,
  toolResult: ToolResult(toolUseId: id, content: jsonEncode(payload)),
);

Message _toolText(String id, String content) => Message(
  role: Role.tool,
  toolResult: ToolResult(toolUseId: id, content: content),
);

String _state({List<String>? evidenceRefs}) {
  final refs = evidenceRefs ??
      [
        'strategy_compare',
        'technical_indicator_comparison',
      ];
  return 'structured strategy comparison\n'
      'data: ${jsonEncode({
        'workflowState': {
          'contract': 'finance-workflow-state-v1',
          'workflowKind': 'strategy_review',
          'assetClass': 'stock',
          'intentMode': 'review',
          'executionMode': 'preview_only',
          'safetyBoundary': 'read-only strategy comparison',
          'evidenceRefs': refs,
          'confirmationState': 'none',
          'subject': '600519',
          'source': 'agent-structured-intent',
        },
      })}';
}
