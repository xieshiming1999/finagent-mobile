import 'package:flutter_test/flutter_test.dart';

import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_custom_strategy_evidence.dart';

Message _user(String content) => Message(role: Role.user, content: content);

Message _assistantTool(String id, Map<String, dynamic> input) => Message(
  role: Role.assistant,
  content: '',
  toolUses: [ToolUse(id: id, name: 'MarketData', input: input)],
);

Message _tool(String id, String content, {bool isError = false}) => Message(
  role: Role.tool,
  content: '',
  toolResult: ToolResult(toolUseId: id, content: content, isError: isError),
);

String _backtest(String symbol, num totalReturnPct, num trades) =>
    '''
{
  "action": "custom_strategy_backtest",
  "status": "backtested",
  "symbol": "$symbol",
  "strategyId": "strategy_$symbol",
  "actualStartDate": "2025-07-01",
  "actualEndDate": "2026-06-30",
  "bars": 240,
  "dataCoverage": {
    "mode": "strategy_backtest_kline_coverage",
    "symbol": "$symbol",
    "rows": 240,
    "requiredBars": 120,
    "sufficient": true,
    "actualStartDate": "2025-07-01",
    "actualEndDate": "2026-06-30",
    "source": "local kline_daily",
    "cacheStatus": "local-hit"
  },
  "metrics": {
    "tradeCount": $trades,
    "totalReturnPct": $totalReturnPct,
    "maxDrawdownPct": 8,
    "winRatePct": 50
  },
  "assumptions": {
    "commissionPct": 0.1,
    "slippagePct": 0.05
  },
  "validation": {
    "spec": {"id": "strategy_$symbol", "symbol": "$symbol"}
  }
}
''';

void main() {
  group('FinanceCustomStrategyEvidence', () {
    test('builds comparison answer from comparable custom backtests', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user(
          'compare structured strategies\n'
          'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"backtest","executionMode":"preview_only","safetyBoundary":"read-only backtest","evidenceRefs":["custom_strategy_backtest"],"confirmationState":"none","source":"agent-structured-intent"}}',
        ),
        _assistantTool('bt-600519', {
          'action': 'custom_strategy_backtest',
          'code': '600519',
        }),
        _tool('bt-600519', _backtest('600519', 3, 1)),
        _assistantTool('bt-000858', {
          'action': 'custom_strategy_backtest',
          'code': '000858',
        }),
        _tool('bt-000858', _backtest('000858', 6, 2)),
        _assistantTool('bt-300059', {
          'action': 'custom_strategy_backtest',
          'code': '300059',
        }),
        _tool('bt-300059', _backtest('300059', 1, 1)),
      ];

      final answer = evidence.comparison(
        messages: messages,
        turnStartIndex: 1,
      );

      expect(answer, contains('多标的动量策略比较'));
      expect(answer, contains('600519'));
      expect(answer, contains('000858'));
      expect(answer, contains('300059'));
      expect(answer, contains('优先候选为 000858'));
      expect(answer, contains('覆盖满足'));
      expect(answer, contains('cache=local-hit'));
    });

    test('does not build comparison answer from prompt text alone', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user('帮我比较茅台、五粮液、东方财富，找出更适合动量策略的一只，并说明数据来源和回测假设。'),
        _assistantTool('bt-600519', {
          'action': 'custom_strategy_backtest',
          'code': '600519',
        }),
        _tool('bt-600519', _backtest('600519', 3, 1)),
        _assistantTool('bt-000858', {
          'action': 'custom_strategy_backtest',
          'code': '000858',
        }),
        _tool('bt-000858', _backtest('000858', 6, 2)),
      ];

      final answer = evidence.comparison(
        messages: messages,
        turnStartIndex: 1,
      );

      expect(answer, isNull);
    });

    test('builds single backtest answer from dataCoverage evidence', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user('帮我从自选股里找一只适合趋势策略的股票，设计策略并用本地数据回测，先不要下单。'),
        _assistantTool('bt', {
          'action': 'custom_strategy_backtest',
          'code': '002129',
        }),
        _tool('bt', _backtest('002129', 12, 2)),
      ];

      final answer = evidence.backtest(messages, 1);

      expect(answer, contains('标的：002129'));
      expect(answer, contains('数据覆盖：2025-07-01 ~ 2026-06-30'));
      expect(answer, contains('覆盖满足'));
      expect(answer, contains('cache=local-hit'));
    });

    test('reports validation-only save and failed rerun as non-runnable', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user(
          'rerun structured saved strategy\n'
          'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"rerun","executionMode":"preview_only","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_save"],"confirmationState":"none","source":"agent-structured-intent"}}',
        ),
        _assistantTool('save', {'action': 'custom_strategy_save'}),
        _tool('save', '''
{
  "action": "custom_strategy_save",
  "strategyId": "custom_fund_watch_v1",
  "version": 1,
  "status": "validated",
  "spec": {"id": "custom_fund_watch_v1", "name": "基金定投观察策略"},
  "validation": {"status": "validated"},
  "evidence": null
}
'''),
        _assistantTool('run', {
          'action': 'custom_strategy_run',
          'strategyId': 'custom_fund_watch_v1',
        }),
        _tool(
          'run',
          'custom strategy custom_fund_watch_v1 is not runnable; status=validated. Run custom_strategy_backtest and save backtested evidence first.',
          isError: true,
        ),
      ];

      final answer = evidence.saveRunBoundary(
        messages: messages,
        turnStartIndex: 1,
      );

      expect(answer, contains('策略保存与重跑边界'));
      expect(answer, contains('保存状态：validated'));
      expect(answer, contains('不能声明“按 strategyId 重跑一致”'));
      expect(answer, contains('backtested evidence'));
    });

    test('builds save-rerun boundary from structured save and run evidence without prompt parsing', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user('把刚才验证通过的策略保存下来，然后重新按策略 ID 跑一次，确认结果一致。'),
        _assistantTool('save', {'action': 'custom_strategy_save'}),
        _tool('save', '''
{
  "action": "custom_strategy_save",
  "strategyId": "custom_ema_v1",
  "version": 1,
  "status": "backtested",
  "spec": {"id": "custom_ema_v1", "name": "贵州茅台_EMA趋势"},
  "validation": {"status": "validated"},
  "evidence": {"status": "backtested", "bars": 240}
}
'''),
        _assistantTool('run', {
          'action': 'custom_strategy_run',
          'strategyId': 'custom_ema_v1',
          'code': '000858',
        }),
        _tool('run', '''
{
  "action": "custom_strategy_run",
  "code": "000858",
  "strategyId": "custom_ema_v1",
  "status": "backtested",
  "actualStartDate": "2025-07-01",
  "actualEndDate": "2026-06-30",
  "bars": 240,
  "metrics": {"tradeCount": 1, "totalReturnPct": 4, "maxDrawdownPct": 8, "winRatePct": 50},
  "dataCoverage": {"symbol": "000858", "rows": 240, "requiredBars": 120, "sufficient": true, "source": "local kline_daily", "cacheStatus": "local-hit"}
}
'''),
      ];

      final answer = evidence.saveRunBoundary(
        messages: messages,
        turnStartIndex: 1,
      );

      expect(answer, contains('策略保存与重跑完成'));
      expect(answer, contains('strategyId：custom_ema_v1'));
      expect(answer, contains('标的：000858'));
      expect(answer, contains('数据覆盖'));
    });

    test('builds rerun answer from custom_strategy_run evidence without same-turn save', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user('换成五粮液000858重跑已保存策略。'),
        _assistantTool('run', {
          'action': 'custom_strategy_run',
          'strategyId': 'custom_ema_v1',
          'code': '000858',
        }),
        _tool('run', '''
{
  "action": "custom_strategy_run",
  "code": "000858",
  "strategyId": "custom_ema_v1",
  "status": "backtested",
  "actualStartDate": "2025-07-01",
  "actualEndDate": "2026-06-30",
  "bars": 240,
  "metrics": {"tradeCount": 1, "totalReturnPct": 4, "maxDrawdownPct": 8, "winRatePct": 50},
  "dataCoverage": {"symbol": "000858", "rows": 240, "requiredBars": 120, "sufficient": true, "source": "local kline_daily", "cacheStatus": "local-hit"}
}
'''),
      ];

      final answer = evidence.saveRunBoundary(
        messages: messages,
        turnStartIndex: 1,
      );

      expect(answer, contains('策略保存与重跑完成'));
      expect(answer, contains('strategyId：custom_ema_v1'));
      expect(answer, contains('标的：000858'));
    });

    test('does not close natural-language save-rerun turn after save only', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user('保存刚才验证通过的策略，然后换一只股票重跑。'),
        _assistantTool('save', {'action': 'custom_strategy_save'}),
        _tool('save', '''
{
  "action": "custom_strategy_save",
  "strategyId": "custom_ema_v1",
  "version": 1,
  "status": "backtested",
  "spec": {"id": "custom_ema_v1", "name": "贵州茅台_EMA趋势"},
  "validation": {"status": "validated"},
  "evidence": {"status": "backtested", "bars": 240}
}
'''),
      ];

      final answer = evidence.save(messages, 0);

      expect(answer, isNull);
    });

    test('reports rejected validation without parsing error vocabulary', () {
      final evidence = FinanceCustomStrategyEvidence();
      final messages = [
        _user('structured validation'),
        _assistantTool('validate', {'action': 'custom_strategy_validate'}),
        _tool('validate', '''
{
  "action": "custom_strategy_validate",
  "status": "rejected",
  "strategyId": "bad_exit_v1",
  "errors": ["exit operator missing", "exit rule has no executable right-hand value"]
}
'''),
      ];

      final answer = evidence.rejectedValidation(messages, 1);

      expect(answer, contains('验证状态：rejected'));
      expect(answer, contains('exit operator missing'));
      expect(answer, contains('exit rule has no executable right-hand value'));
    });
  });
}
