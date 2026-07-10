import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_preset_backtest_evidence_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds cost evidence from structured preset backtest results', () {
    final summary = FinancePresetBacktestEvidenceSummary().build(
      messages: [
        Message(role: Role.user, content: 'compare strategies'),
        _tool({
          'action': 'backtest',
          'symbol': '600519',
          'strategy': 'turtle_breakout',
          'actualStartDate': '2025-07-11',
          'actualEndDate': '2026-07-10',
          'bars': 242,
          'total_trades': 0,
          'total_return_pct': 0.0,
          'cost_assumption':
              'commission=0.1‰ + slippage=0.05‰ + stamp_tax=0.1‰ (sell)',
        }),
      ],
      turnStartIndex: 0,
    );

    expect(summary, contains('回测成本假设与证据边界'));
    expect(summary, contains('turtle_breakout'));
    expect(summary, contains('commission=0.1‰'));
    expect(summary, contains('242 根'));
  });
}

Message _tool(Map<String, dynamic> payload) => Message(
  role: Role.tool,
  toolResult: ToolResult(toolUseId: 'tool_1', content: jsonEncode(payload)),
);
