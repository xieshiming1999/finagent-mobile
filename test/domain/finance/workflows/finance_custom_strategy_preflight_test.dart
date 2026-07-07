import 'dart:convert';

import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('prompt text alone does not discover custom StrategySpec contract', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content: '帮我为贵州茅台设计一个低风险买入策略，必须包含入场、止损、止盈、仓位规则，并验证哪些条件当前系统支持。',
      ),
    ]);

    expect(calls, isNull);
  });

  test('structured strategy state discovers contract without prompt words', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'prepare artifact\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"stock","intentMode":"validate","executionMode":"preview_only","safetyBoundary":"read-only validation","evidenceRefs":["StrategySpec"],"confirmationState":"none","source":"agent-structured-intent"},"strategySpec":{"id":"state_strategy_v1","assetClass":"stock","symbol":"300059","symbols":["300059"]}}',
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'custom_strategy_help');
  });

  test('structured strategy spec is used after contract discovery', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'prepare artifact\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"stock","intentMode":"validate","executionMode":"preview_only","safetyBoundary":"read-only validation","evidenceRefs":["StrategySpec"],"confirmationState":"none","source":"agent-structured-intent"},"strategySpec":{"id":"state_strategy_v1","assetClass":"stock","symbol":"300059","symbols":["300059"],"timeframe":"1d"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'help',
            name: 'MarketData',
            input: {'action': 'custom_strategy_help'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'help',
          content: '{"action":"custom_strategy_help"}',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.single.input['action'], 'custom_strategy_validate');
    expect(
      calls.single.input['strategySpec'],
      containsPair('id', 'state_strategy_v1'),
    );
    expect(
      calls.single.input['strategySpec'],
      containsPair('symbol', '300059'),
    );
  });

  test('contract discovery without StrategySpec does not draft validation', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'prepare artifact\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"stock","intentMode":"validate","executionMode":"preview_only","safetyBoundary":"read-only validation","evidenceRefs":["StrategySpec"],"confirmationState":"none","subject":"600519","source":"agent-structured-intent"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: [
          ToolUse(
            id: 'help',
            name: 'MarketData',
            input: {'action': 'custom_strategy_help'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'help',
          content: '{"action":"custom_strategy_help"}',
        ),
      ),
    ]);

    expect(calls, isNull);
  });

  test(
    'structured multi-stock StrategySpec backtests every requested symbol',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

      final calls = hooks.buildPreflightToolCalls([
        Message(
          role: Role.user,
          content:
              'prepare comparison\n'
              'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"stock","intentMode":"backtest","executionMode":"preview_only","safetyBoundary":"read-only backtest","evidenceRefs":["StrategySpec"],"confirmationState":"none","source":"agent-structured-intent"},"strategySpec":{"id":"state_compare_v1","assetClass":"stock","symbols":["600519","000858","300059"],"timeframe":"1d"}}',
        ),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'help',
              name: 'MarketData',
              input: {'action': 'custom_strategy_help'},
            ),
          ],
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'help',
            content: '{"action":"custom_strategy_help"}',
          ),
        ),
      ]);

      expect(calls, isNotNull);
      expect(calls, hasLength(3));
      expect(calls!.map((call) => call.input['action']).toSet(), {
        'custom_strategy_backtest',
      });
      expect(calls.map((call) => (call.input['symbols'] as List).single), {
        '600519',
        '000858',
        '300059',
      });
    },
  );

  test('strategy signal monitor payload supplies trade sizing symbol', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 金风科技_002202_策略信号监控] 策略信号已触发：金风科技 002202.SZ。请先计算可以买多少和风险，不要直接下单；需要用户确认后才允许进入雪球模拟盘或 Portfolio 写入。\n'
            'data: {"template":"strategy_signal","strategyId":"workflow_test_strategy_signal_002202","code":"002202.SZ","name":"金风科技","signal":"entry","price":23.9,"confirmationRequired":true}',
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'query_quote');
    expect(calls.single.input['symbols'], ['002202']);
  });

  test(
    'structured strategy signal payload triggers trade sizing without prompt words',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

      final calls = hooks.buildPreflightToolCalls([
        Message(
          role: Role.user,
          content:
              'event\n'
              'data: {"template":"strategy_signal","strategyId":"state_test","code":"300059.SZ","signal":"entry","price":20.1,"confirmationRequired":true}',
        ),
      ]);

      expect(calls, isNotNull);
      expect(calls, hasLength(1));
      expect(calls!.single.name, 'MarketData');
      expect(calls.single.input['action'], 'query_quote');
      expect(calls.single.input['symbols'], ['300059']);
    },
  );

  test('stock candidate evidence does not replace missing StrategySpec', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'prepare candidate strategy\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"stock","intentMode":"backtest","executionMode":"preview_only","safetyBoundary":"read-only backtest","evidenceRefs":["watchlist"],"confirmationState":"none","source":"agent-structured-intent"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'help',
            name: 'MarketData',
            input: {'action': 'custom_strategy_help'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'help',
          content: '{"action":"custom_strategy_help"}',
        ),
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'watchlist',
            name: 'Watchlist',
            input: {'action': 'list'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'watchlist',
          content: '''
{
  "count": 2,
  "items": [
    {"symbol":"001480","name":"财通成长优选混合A","type":"fund","status":"watching"},
    {"symbol":"300059","name":"东方财富","type":"stock","status":"watching"}
  ]
}
''',
        ),
      ),
    ]);

    expect(calls, isNull);
  });

  test('structured fund strategy state enters fund evidence preflight', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'fund workflow\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"fund","intentMode":"observe","executionMode":"preview_only","safetyBoundary":"fund observation only","evidenceRefs":["fund_nav"],"confirmationState":"none","source":"agent-structured-intent"}}',
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'Watchlist');
    expect(calls.single.input['action'], 'list');
  });

  test('prompt-only fund strategy wording does not enter preflight', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content: '帮我设计一个基金定投观察策略，要求考虑回撤和净值趋势，不要使用股票 K 线信号。',
      ),
    ]);

    expect(calls, isNull);
  });

  test('structured trade sizing state starts account evidence preflight', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
    ]);

    expect(calls, isNotNull);
    expect(calls!.map((call) => call.name), contains('XueqiuTrade'));
    expect(calls.map((call) => call.name), contains('Portfolio'));
    expect(
      calls
          .where((call) => call.name == 'XueqiuTrade')
          .map((call) => call.input['action']),
      contains('balance'),
    );
  });

  test(
    'portfolio rebalance monitor creation does not trigger trade sizing',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      const prompt = '''
请只为已保存的 strategyId=workflow_portfolio_rank_monitor_v1 创建一个新的组合再平衡复核监控，使用 MonitorCreate(template:"portfolio_rebalance_monitor")。
rebalanceDraft.positions 必须包含：600519 targetWeight 0.33、000858 targetWeight 0.33、300059 targetWeight 0.34。
rebalanceDraft.rebalanceInterval="monthly"，rebalanceDraft.maxPositionWeight=0.4。
只做复核监控，不做任何交易写入。
''';

      final calls = hooks.buildPreflightToolCalls([
        Message(role: Role.user, content: prompt),
      ]);

      expect(calls?.map((call) => call.name), isNot(contains('XueqiuTrade')));
      expect(calls?.map((call) => call.name), isNot(contains('Portfolio')));
    },
  );

  test('trade sizing preflight does not call unavailable XueqiuTrade tool', () {
    final hooks = FinanceWorkflowHooks(
      isBypassTool: (_) => false,
      availableToolNames: const {'MarketData', 'Portfolio', 'AskUserQuestion'},
    );

    final calls = hooks.buildPreflightToolCalls([
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
    ]);

    expect(calls, isNotNull);
    expect(calls!.map((call) => call.name), isNot(contains('XueqiuTrade')));
    expect(calls.map((call) => call.name), contains('Portfolio'));
  });

  test('trade sizing preflight honors forbidden XueqiuTrade control', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content: _tradeSizingStateContent(
          '300059',
          blockedTools: const ['Bash', 'Script', 'Read', 'XueqiuTrade'],
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.map((call) => call.name), isNot(contains('XueqiuTrade')));
    expect(calls.map((call) => call.name), contains('Portfolio'));
  });

  test('trade sizing preflight does not retry failed Xueqiu read', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content: 'HandshakeException: Connection terminated during handshake',
          isError: true,
        ),
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '模拟盘为空。Initial cash: 100000.00。',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.map((call) => call.name), isNot(contains('XueqiuTrade')));
    expect(calls.single.name, 'AskUserQuestion');
  });

  test(
    'strategy signal trigger event does not create another monitor recovery',
    () async {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      var recoveryCalledTool = false;
      final answer = await hooks.buildRecovery(
        prompt:
            '[Monitor 通知 from 002202 金风科技 strategy_signal 监控] 策略信号已触发：金风科技 002202.SZ。\n'
            'data: {"template":"strategy_signal","strategyId":"workflow_test_strategy_signal_002202","code":"002202.SZ","confirmationRequired":true}',
        messages: [
          Message(role: Role.user, content: 'monitor event'),
          Message(
            role: Role.tool,
            toolResult: ToolResult(
              toolUseId: 'quote',
              content: '''
{
  "action": "query_quote",
  "data": [{"code": "002202", "price": 23.9, "timestamp": "2026-06-30T12:00:27Z", "fetchedAt": "2026-06-30T12:00:27Z"}]
}
''',
            ),
          ),
        ],
        toolByName: (name) => _FakeTool(name),
        callTool: (tool, toolUseId, input) async {
          recoveryCalledTool = true;
          return ToolResult(toolUseId: toolUseId, content: '{}');
        },
      );

      expect(answer, isNull);
      expect(recoveryCalledTool, isFalse);
    },
  );

  test('strategy signal trigger event does not start custom strategy preflight', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            '[Monitor 通知 from 002202 金风科技 strategy_signal 监控] 策略信号已触发：金风科技 002202.SZ。\n'
            'data: {"template":"strategy_signal","strategyId":"workflow_test_strategy_signal_002202","code":"002202.SZ","confirmationRequired":true}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'quote',
            name: 'MarketData',
            input: {
              'action': 'query_quote',
              'symbols': ['002202'],
            },
          ),
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
          ToolUse(id: 'ask', name: 'AskUserQuestion', input: {'questions': []}),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'quote',
          content:
              '{"action":"query_quote","data":[{"code":"002202","price":23.9}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '模拟盘为空。初始资金: 977959.95。',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'ask',
          content:
              'User has answered your questions: "策略信号触发后，是否允许进入雪球模拟盘或本地模拟盘执行？"="只计算不下单".',
        ),
      ),
    ]);

    expect(calls, isNull);
  });

  test('trade confirmation blocks post-answer custom strategy drift', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final interception = hooks.interceptToolCalls(
      messages: [
        Message(role: Role.user, content: _tradeSizingStateContent('002202')),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'ask',
              name: 'AskUserQuestion',
              input: {'questions': []},
            ),
          ],
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'ask',
            content:
                'User has answered your questions: "策略信号触发后，是否允许进入雪球模拟盘或本地模拟盘执行？"="只计算不下单".',
          ),
        ),
      ],
      turnStartIndex: 0,
      prompt: _tradeSizingStateContent('002202'),
      toolCalls: const [
        ToolUse(
          id: 'list',
          name: 'MarketData',
          input: {'action': 'custom_strategy_list'},
        ),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.answer, contains('只保留策略信号、账户证据和风险测算'));
    final prep = _tradePrep(interception.answer);
    expect(prep['contract'], 'trade-prep-v1');
    expect(prep['prepKind'], 'strategy_trade_confirmation_stop');
    expect(prep['boundaries'], contains('no_memory_write'));
    expect(prep['boundaries'], contains('no_watchlist_mutation'));
    expect(interception.skippedReason, contains('strategy trade confirmation'));
  });

  test(
    'trade confirmation answer finishes preflight without another LLM turn',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final answer = hooks.buildPreflightAnswer([
        Message(role: Role.user, content: _tradeSizingStateContent('002202')),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'quote',
              name: 'MarketData',
              input: {'action': 'query_quote'},
            ),
            ToolUse(
              id: 'snapshot',
              name: 'Portfolio',
              input: {'action': 'snapshot'},
            ),
            ToolUse(
              id: 'ask',
              name: 'AskUserQuestion',
              input: {'questions': []},
            ),
          ],
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'quote',
            content: '''
{
  "action": "query_quote",
  "source": "local quote_snapshot",
  "provider": "local",
  "data": [{"code": "002202", "price": 23.9, "source": "通达信", "timestamp": "2026-06-30T12:00:27Z", "fetchedAt": "2026-06-30T12:00:27Z"}]
}
''',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'snapshot',
            content: '模拟盘为空。初始资金: 977959.95。',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'ask',
            content:
                'User has answered your questions: "策略信号触发后，是否允许进入雪球模拟盘或本地模拟盘执行？"="只计算不下单".',
          ),
        ),
      ]);

      expect(answer, isNotNull);
      expect(answer, contains('本轮只计算，不直接交易'));
      expect(answer, contains('未执行交易工具写操作'));
      final prep = _tradePrep(answer!);
      expect(prep['contract'], 'trade-prep-v1');
      expect(prep['prepKind'], 'strategy_signal_position_sizing');
      expect(prep['symbol'], '002202');
      expect(prep['boundaries'], contains('no_order_write'));
    },
  );

  test('trade sizing preflight reads quote for latest strategy symbol', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'backtest',
          content: '''
{
  "action": "custom_strategy_backtest",
  "status": "backtested",
  "symbol": "300059",
  "strategyId": "custom_strategy_v1"
}
''',
        ),
      ),
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
    ]);

    expect(calls, isNotNull);
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'query_quote');
    expect(calls.single.input['symbols'], ['300059']);
  });

  test('trade sizing asks confirmation after local-only sizing evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content: _tradeSizingStateContent(
          '300059',
          blockedTools: const ['Bash', 'Script', 'Read', 'XueqiuTrade'],
        ),
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: [
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        content: '',
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '{"action":"snapshot","cash":100000}',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.single.name, 'AskUserQuestion');
  });

  test('trade sizing confirmation produces preview-only tool calls', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'backtest',
          content: '''
{
  "action": "custom_strategy_backtest",
  "status": "backtested",
  "symbol": "300059",
  "strategyId": "custom_strategy_v1"
}
''',
        ),
      ),
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'quote',
            name: 'MarketData',
            input: {
              'action': 'query_quote',
              'symbols': ['300059'],
            },
          ),
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance'},
          ),
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
          ToolUse(id: 'ask', name: 'AskUserQuestion', input: {'questions': []}),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'quote',
          content:
              '{"action":"query_quote","data":[{"code":"300059","price":20.0}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content:
              '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '{"action":"snapshot","cash":200000,"assets":200000}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'ask',
          content:
              '{"decision":"allow_preview","selectedOptionIndex":3,"selectedOptionLabel":"允许模拟执行"}',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.map((call) => call.name), ['Portfolio', 'XueqiuTrade']);
    expect(calls.first.input, {
      'action': 'preview_trade',
      'market': 'cn',
      'symbol': '300059',
      'side': 'buy',
      'shares': 1000,
      'price': 20.0,
    });
    expect(calls.last.input, {
      'action': 'preview_order',
      'side': 'buy',
      'symbol': '300059',
      'shares': 1000,
      'price': 20.0,
    });
  });

  test(
    'trade sizing preview can use monitor payload price after structured confirmation',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

      final calls = hooks.buildPreflightToolCalls([
        Message(
          role: Role.user,
          content:
              '[Monitor Notification: 东方财富_300059_策略信号监控] 策略信号已触发：东方财富 300059。请先计算可以买多少和风险，不要直接下单；需要用户确认后才允许进入雪球模拟盘或 Portfolio 写入。\n'
              'data: {"template":"strategy_signal","strategyId":"workflow_trade_preview_strategy_300059","code":"300059","name":"东方财富","signal":"entry","price":21.89,"confirmationRequired":true}',
        ),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'quote',
              name: 'MarketData',
              input: {
                'action': 'query_quote',
                'symbols': ['300059'],
              },
            ),
            ToolUse(
              id: 'balance',
              name: 'XueqiuTrade',
              input: {'action': 'balance'},
            ),
            ToolUse(
              id: 'snapshot',
              name: 'Portfolio',
              input: {'action': 'snapshot', 'market': 'cn'},
            ),
            ToolUse(
              id: 'ask',
              name: 'AskUserQuestion',
              input: {'questions': []},
            ),
          ],
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'quote',
            content:
                '{"action":"query_quote","data":[{"code":"300059","price":20.97}]}',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'balance',
            content:
                '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'snapshot',
            content: '{"action":"snapshot","cash":200000,"assets":200000}',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'ask',
            content:
                '{"decision":"allow_preview","selectedOptionIndex":3,"selectedOptionLabel":"允许模拟执行"}',
          ),
        ),
      ]);

      expect(calls, isNotNull);
      expect(calls!.map((call) => call.name), ['Portfolio', 'XueqiuTrade']);
      expect(calls.first.input['action'], 'preview_trade');
      expect(calls.first.input['symbol'], '300059');
      expect(calls.first.input['price'], 20.97);
      expect(calls.first.input['shares'], 900);
    },
  );

  test('trade sizing preview accepts AskUserQuestion contract answer', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 东方财富_300059_策略信号监控] 策略信号已触发：东方财富 300059。\n'
            'data: {"template":"strategy_signal","strategyId":"workflow_trade_preview_strategy_300059","code":"300059","name":"东方财富","signal":"entry","price":21.89,"confirmationRequired":true}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'quote',
            name: 'MarketData',
            input: {
              'action': 'query_quote',
              'symbols': ['300059'],
            },
          ),
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance'},
          ),
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
          ToolUse(id: 'ask', name: 'AskUserQuestion', input: {'questions': []}),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'quote',
          content:
              '{"action":"query_quote","data":[{"code":"300059","price":21.17}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content:
              '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '{"action":"snapshot","cash":200000,"assets":200000}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'ask',
          content: '''
User has answered your questions: "策略信号触发后，是否允许进入雪球模拟盘或本地模拟盘执行？"="{\\"decision\\":\\"allow_preview\\",\\"selectedOptionIndex\\":3,\\"selectedOptionLabel\\":\\"允许模拟执行\\"}". You can now continue with the user's answers in mind.
askUserQuestion:{"contract":"ask-user-question-v1","answers":[{"question":"策略信号触发后，是否允许进入雪球模拟盘或本地模拟盘执行？","answer":"{\\"decision\\":\\"allow_preview\\",\\"selectedOptionIndex\\":3,\\"selectedOptionLabel\\":\\"允许模拟执行\\"}","structuredAnswer":{"decision":"allow_preview","selectedOptionIndex":3,"selectedOptionLabel":"允许模拟执行"}}]}''',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.map((call) => call.name), ['Portfolio', 'XueqiuTrade']);
    expect(calls.first.input['action'], 'preview_trade');
    expect(calls.first.input['symbol'], '300059');
    expect(calls.first.input['price'], 21.17);
    expect(calls.first.input['shares'], 900);
  });

  test('trade sizing does not authorize preview from plain AskUserQuestion text', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 东方财富_300059_策略信号监控] 策略信号已触发：东方财富 300059。\n'
            'data: {"template":"strategy_signal","strategyId":"workflow_trade_preview_strategy_300059","code":"300059","name":"东方财富","signal":"entry","price":21.89,"confirmationRequired":true}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'quote',
            name: 'MarketData',
            input: {
              'action': 'query_quote',
              'symbols': ['300059'],
            },
          ),
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance'},
          ),
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
          ToolUse(id: 'ask', name: 'AskUserQuestion', input: {'questions': []}),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'quote',
          content:
              '{"action":"query_quote","data":[{"code":"300059","price":20.97}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content:
              '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '{"action":"snapshot","cash":200000,"assets":200000}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'ask', content: '允许模拟执行'),
      ),
    ]);

    expect(calls, isNull);
  });

  test(
    'trade sizing summary includes portfolio rebalance draft evidence only',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final answer = hooks.buildPreflightAnswer([
        Message(role: Role.user, content: _tradeSizingStateContent('600519')),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'balance',
              name: 'XueqiuTrade',
              input: {'action': 'balance'},
            ),
            ToolUse(
              id: 'snapshot',
              name: 'Portfolio',
              input: {'action': 'snapshot', 'market': 'cn'},
            ),
            ToolUse(
              id: 'watchlist',
              name: 'Watchlist',
              input: {
                'action': 'list',
                'strategyId': 'rank_strategy_v1',
                'status': 'watching',
              },
            ),
            ToolUse(
              id: 'ask',
              name: 'AskUserQuestion',
              input: {'questions': []},
            ),
          ],
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'balance',
            content:
                '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'snapshot',
            content: '{"action":"snapshot","cash":200000,"assets":200000}',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'watchlist',
            content: '''
{
  "action": "list",
  "items": [
    {
      "symbol": "600519",
      "strategyId": "rank_strategy_v1",
      "strategyRules": {
        "portfolioEvidence": {
          "aggregateMetrics": {
            "expectedReturnPct": 8.4,
            "portfolioMaxDrawdownPct": -6.2,
            "selectedSymbols": ["600519", "000858"]
          }
        },
        "rebalanceDraft": {
          "mode": "equal_weight_top_n",
          "rebalanceInterval": "monthly",
          "positions": [
            {"symbol": "600519", "targetWeight": 0.4, "weightCapped": true},
            {"symbol": "000858", "targetWeight": 0.4, "weightCapped": true}
          ],
          "tradeBoundary": "Requires confirmation before any order."
        }
      }
    }
  ]
}
''',
          ),
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(toolUseId: 'ask', content: '触发时再确认'),
        ),
      ]);

      expect(answer, isNotNull);
      expect(answer, contains('## 组合再平衡草案'));
      expect(answer, contains('600519：目标权重 40.0%'));
      expect(answer, contains('000858：目标权重 40.0%'));
      expect(answer, contains('按当前现金估算金额 40000.00'));
      expect(answer, contains('不会自动调仓'));
      expect(answer, contains('不会调用 XueqiuTrade(buy)'));
    },
  );

  test('fund strategy evidence stops file-read drift', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (name) => name == 'Read');
    final messages = [
      Message(
        role: Role.user,
        content: '帮我设计一个基金定投观察策略，要求考虑回撤和净值趋势，不要使用股票 K 线信号。',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'fund-nav',
            name: 'MarketData',
            input: {'action': 'query_fund_nav'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'fund-nav',
          content: '''
{
  "action": "query_fund_nav",
  "source": "local fund_nav",
  "cacheStatus": "cache-hit",
  "seriesSummary": [
    {
      "code": "001480",
      "rows": 5,
      "startDate": "2026-06-23",
      "endDate": "2026-06-29",
      "startNav": 9.809,
      "endNav": 9.935,
      "cumulativeReturnPct": 1.2845,
      "maxDrawdownPct": -5.5685,
      "source": "eastmoney",
      "fetchedAt": "2026-07-01T02:52:10.346136Z"
    }
  ]
}
''',
        ),
      ),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: '帮我设计一个基金定投观察策略，要求考虑回撤和净值趋势，不要使用股票 K 线信号。',
      toolCalls: const [
        ToolUse(
          id: 'read',
          name: 'Read',
          input: {'file_path': 'memory/.tool_outputs/tool_output.txt'},
        ),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.answer, contains('基金定投观察策略'));
    expect(interception.answer, contains('query_fund_nav'));
    expect(interception.skippedReason, contains('structured fund evidence'));
  });

  test(
    'fund strategy preflight turns governed fund readback into observation',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final messages = [
        Message(
          role: Role.user,
          content:
              'fund workflow\n'
              'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"fund","intentMode":"observe","executionMode":"preview_only","safetyBoundary":"fund observation only","evidenceRefs":["fund_nav"],"confirmationState":"none","source":"agent-structured-intent"}}',
        ),
        Message(
          role: Role.assistant,
          content: '',
          toolUses: const [
            ToolUse(
              id: 'fund-nav',
              name: 'MarketData',
              input: {
                'action': 'query_fund_nav',
                'symbols': ['001480'],
                'limit': 60,
              },
            ),
          ],
        ),
        Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: 'fund-nav',
            content: '001480 fund NAV | interface:fund.nav_history',
          ),
        ),
      ];

      final calls = hooks.buildPreflightToolCalls(messages);

      expect(calls, isNotNull);
      expect(calls!.single.name, 'MarketData');
      expect(calls.single.input['action'], 'custom_strategy_observe');
      expect(calls.single.input['symbols'], ['001480']);
      expect(
        calls.single.input['strategySpec'],
        containsPair('fundCode', '001480'),
      );
    },
  );

  test('fund strategy evidence stops stock strategy tool drift', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content: '帮我设计一个基金定投观察策略，要求考虑回撤和净值趋势，不要使用股票 K 线信号。',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'fund-nav',
            name: 'MarketData',
            input: {'action': 'query_fund_nav'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'fund-nav',
          content: '''
{
  "action": "query_fund_nav",
  "source": "local fund_nav",
  "cacheStatus": "cache-hit",
  "seriesSummary": [
    {
      "code": "001480",
      "rows": 20,
      "startDate": "2026-06-01",
      "endDate": "2026-06-29",
      "startNav": 7.653,
      "endNav": 9.935,
      "cumulativeReturnPct": 29.8184,
      "maxDrawdownPct": -6.4261,
      "source": "eastmoney",
      "fetchedAt": "2026-07-01T02:52:10.346136Z"
    }
  ]
}
''',
        ),
      ),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: '帮我设计一个基金定投观察策略，要求考虑回撤和净值趋势，不要使用股票 K 线信号。',
      toolCalls: const [
        ToolUse(
          id: 'stock-strategy',
          name: 'DataProcess',
          input: {'action': 'strategy_execute', 'symbol': '001480'},
        ),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.answer, contains('基金定投观察策略'));
    expect(interception.answer, contains('不使用股票 K 线'));
    expect(interception.skippedReason, contains('stock-strategy'));
  });

  test('fund strategy evidence stops stock kline drift', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content: '帮我设计一个基金定投观察策略，要求考虑回撤和净值趋势，不要使用股票 K 线信号。',
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'fund-nav',
          content: '''
{
  "action": "query_fund_nav",
  "source": "local fund_nav",
  "cacheStatus": "cache-hit",
  "seriesSummary": [
    {
      "code": "001480",
      "rows": 120,
      "startDate": "2025-12-25",
      "endDate": "2026-06-29",
      "startNav": 4.051,
      "endNav": 9.935,
      "cumulativeReturnPct": 145.2481,
      "maxDrawdownPct": -9.1034,
      "source": "eastmoney",
      "fetchedAt": "2026-07-01T02:52:10.346136Z"
    }
  ]
}
''',
        ),
      ),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: '帮我设计一个基金定投观察策略，要求考虑回撤和净值趋势，不要使用股票 K 线信号。',
      toolCalls: const [
        ToolUse(
          id: 'kline',
          name: 'MarketData',
          input: {'action': 'query_kline', 'symbol': '001480'},
        ),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.answer, contains('基金定投观察策略'));
    expect(interception.answer, contains('不使用股票 K 线'));
    expect(interception.skippedReason, contains('stock-strategy'));
  });

  test('strategy comparison evidence owns the final comparison summary', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            'compare existing strategy evidence\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"backtest","executionMode":"preview_only","safetyBoundary":"read-only backtest comparison","evidenceRefs":["custom_strategy_backtest"],"confirmationState":"none","source":"agent-structured-intent"}}',
      ),
      _customBacktestCall('bt-600519', '600519'),
      _customBacktestResult(
        'bt-600519',
        '600519',
        totalReturnPct: 3,
        trades: 1,
      ),
      _customBacktestCall('bt-000858', '000858'),
      _customBacktestResult(
        'bt-000858',
        '000858',
        totalReturnPct: 6,
        trades: 2,
      ),
      _customBacktestCall('bt-300059', '300059'),
      _customBacktestResult(
        'bt-300059',
        '300059',
        totalReturnPct: 1,
        trades: 1,
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 1,
      prompt: messages.first.content,
      answer: 'model-generated free-form answer',
    );

    expect(rewritten, isNotNull);
    expect(rewritten!, contains('多标的动量策略比较'));
    expect(rewritten, contains('600519'));
    expect(rewritten, contains('000858'));
    expect(rewritten, contains('300059'));
  });

  test(
    'comparison rewrite ignores final-answer prose without complete evidence',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
      final messages = [
        Message(
          role: Role.user,
          content: '帮我比较茅台、五粮液、东方财富，找出更适合动量策略的一只，并说明数据来源和回测假设。',
        ),
        _customBacktestCall('bt-600519', '600519'),
        _customBacktestResult(
          'bt-600519',
          '600519',
          totalReturnPct: 3,
          trades: 1,
        ),
      ];

      final rewritten = hooks.rewriteFinalAnswer(
        messages: messages,
        turnStartIndex: 1,
        prompt: messages.first.content,
        answer: '我需要先验证更多数据，请你确认下一步。',
      );

      expect(rewritten, isNull);
    },
  );

  test('trade budget summary reads canonical quote payloads', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'quote',
            name: 'MarketData',
            input: {'action': 'query_quote', 'symbol': '300059'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'quote',
          content: '''
{
  "action": "quote",
  "readbackAction": "query_quote",
  "canonicalSchema": "quote_snapshot",
  "cacheStatus": "local-hit",
  "source": "local quote_snapshot",
  "data": [
    {
      "code": "300059",
      "timestamp": "2026-07-01T05:32:46.578933Z",
      "fetchedAt": "2026-07-01T05:32:46.578933Z",
      "price": 21.89,
      "source": "通达信"
    }
  ]
}
''',
        ),
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance', 'portfolio': 'finasimu'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content: '''
{
  "source": "xueqiu",
  "portfolio": {"name": "finasimu", "gid": 6705388713207579},
  "performances": [
    {"market": "ALL", "assets": 100000.0, "cash": 100000.0}
  ]
}
''',
        ),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '暂不买入。',
    );

    expect(rewritten, isNotNull);
    expect(rewritten!, contains('标的：300059；参考价：21.89'));
    expect(rewritten, contains('913 股'));
    expect(rewritten, contains('19985.57'));
    expect(rewritten, contains('source=local quote_snapshot'));
    expect(rewritten, contains('provider=通达信'));
  });

  test('trade budget summary does not enter from prompt text alone', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(role: Role.user, content: '如果策略今天触发买入信号，帮我计算雪球模拟盘可以买多少，但不要直接交易。'),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance', 'portfolio': 'finasimu'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content:
              '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
        ),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '暂不买入。',
    );

    expect(rewritten, isNull);
  });

  test('trade budget summary reports post-confirmation preview evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'quote',
            name: 'MarketData',
            input: {'action': 'query_quote', 'symbol': '300059'},
          ),
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance', 'portfolio': 'finasimu'},
          ),
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
          ToolUse(
            id: 'portfolio_preview',
            name: 'Portfolio',
            input: {
              'action': 'preview_trade',
              'symbol': '300059',
              'side': 'buy',
              'shares': 900,
              'price': 21.89,
            },
          ),
          ToolUse(
            id: 'xueqiu_preview',
            name: 'XueqiuTrade',
            input: {
              'action': 'preview_order',
              'symbol': '300059',
              'side': 'buy',
              'shares': 900,
              'price': 21.89,
            },
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'quote',
          content:
              '{"action":"query_quote","source":"local quote_snapshot","data":[{"code":"300059","price":21.89,"source":"通达信"}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content:
              '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '{"action":"snapshot","cash":200000,"assets":200000}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'portfolio_preview',
          content:
              '{"action":"preview_trade","sideEffect":false,"executionAllowed":true,"order":{"symbol":"300059","side":"buy","shares":900,"price":21.89},"estimated":{"cashBefore":200000,"cashAfter":180299}}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'xueqiu_preview',
          content:
              '{"action":"preview_order","sideEffect":false,"order":{"symbol":"300059","side":"buy","shares":900,"price":21.89},"readbackEvidence":{"balance":{},"position":{}}}',
        ),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '预览完成。',
    );

    expect(rewritten, isNotNull);
    expect(rewritten!, contains('## 非写入预览'));
    expect(rewritten, contains('Portfolio(action:"preview_trade")'));
    expect(rewritten, contains('XueqiuTrade(action:"preview_order")'));
    expect(rewritten, contains('sideEffect=false'));
    expect(rewritten, contains('预览结果不代表已下单'));
    expect(rewritten, contains('不会调用 XueqiuTrade(buy)'));
  });

  test('trade budget summary waits for preview evidence after approval', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 东方财富_300059_策略信号监控] 策略信号已触发：东方财富 300059。请先计算可以买多少和风险，不要直接下单；需要用户确认后才允许进入雪球模拟盘或 Portfolio 写入。\n'
            'data: {"template":"strategy_signal","strategyId":"workflow_trade_preview_strategy_300059","code":"300059","name":"东方财富","signal":"entry","price":21.89,"confirmationRequired":true}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance'},
          ),
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
          ToolUse(
            id: 'ask',
            name: 'AskUserQuestion',
            input: {'question': '是否允许模拟执行？'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content:
              '{"portfolio":{"name":"finasimu"},"performances":[{"cash":100000,"assets":100000}]}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '{"action":"snapshot","cash":200000,"assets":200000}',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'ask', content: '允许模拟执行'),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '已确认。',
    );

    expect(rewritten, isNotNull);
    expect(rewritten, contains('本轮只计算，不直接交易'));
    expect(rewritten, isNot(contains('## 非写入预览')));
  });

  test('trade budget summary falls back to local portfolio snapshot', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(role: Role.user, content: _tradeSizingStateContent('300059')),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'quote',
            name: 'MarketData',
            input: {
              'action': 'query_quote',
              'symbols': ['300059'],
            },
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'quote',
          content: '''
{
  "action": "query_quote",
  "source": "local quote_snapshot",
  "data": [
    {
      "code": "300059",
      "timestamp": "2026-07-01T05:32:46.578933Z",
      "fetchedAt": "2026-07-01T05:32:46.578933Z",
      "price": 21.89,
      "source": "通达信"
    }
  ]
}
''',
        ),
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content: '模拟盘为空。Initial cash: 100000.00。',
        ),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '暂不买入。',
    );

    expect(rewritten, isNotNull);
    expect(rewritten!, contains('Portfolio(snapshot) local fallback'));
    expect(rewritten, contains('标的：300059；参考价：21.89'));
    expect(rewritten, contains('900 股'));
  });

  test('trade budget summary preserves monitor strategy signal evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 金风科技_002202_策略信号监控] 策略信号已触发：金风科技 002202。请先计算可以买多少和风险，不要直接下单；需要用户确认后才允许进入雪球模拟盘或 Portfolio 写入。\n'
            'data: {"template":"strategy_signal","strategyId":"workflow_test_strategy_signal_002202","code":"002202","name":"金风科技","signal":"entry","price":23.9,"confirmationRequired":true}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'balance',
            name: 'XueqiuTrade',
            input: {'action': 'balance', 'portfolio': 'finasimu'},
          ),
          ToolUse(
            id: 'snapshot',
            name: 'Portfolio',
            input: {'action': 'snapshot', 'market': 'cn'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'balance',
          content: '''
{
  "source": "xueqiu",
  "portfolio": {"name": "finasimu", "gid": 6705388713207579},
  "performances": [
    {"market": "ALL", "assets": 100000.0, "cash": 100000.0}
  ]
}
''',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'snapshot',
          content:
              'The paper portfolio is empty. Initial cash: 1000000.00. Use trade to buy positions.',
        ),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '本轮只计算，不直接交易。',
    );

    expect(rewritten, isNotNull);
    expect(
      rewritten,
      contains('strategyId=workflow_test_strategy_signal_002202'),
    );
    expect(rewritten, contains('signal=entry'));
    expect(rewritten, contains('标的：002202；参考价：23.90'));
    expect(rewritten, contains('source=strategy_signal'));
    expect(rewritten, contains('未调用 buy/sell/transfer'));
  });

  test('fund monitor trigger builds fund observation review summary', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 基金定投观察] 基金观察策略已触发：易方达消费行业 110022。请先复核基金净值、回撤、波动和定投边界，不要直接申购、赎回或写入模拟交易。\n'
            'data: {"template":"fund_rule_monitor","strategyId":"fund_dca_observation_110022_v1","code":"110022","signal":"observe_or_prepare","value":3.4567,"monitorDraft":{"mode":"fund_rule_monitor","cadenceDays":30},"dcaObservation":{"mode":"fund_observation_only","cadenceDays":30},"confirmationRequired":true}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'ask',
            name: 'AskUserQuestion',
            input: {
              'question': '是否进入基金观察复核？',
              'options': ['1. 只复核，不交易', '2. 取消'],
            },
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'ask', content: '1'),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '继续观察。',
    );

    expect(rewritten, isNotNull);
    expect(rewritten!, contains('基金观察监控已触发'));
    expect(rewritten, contains('strategyId=fund_dca_observation_110022_v1'));
    expect(rewritten, contains('fund=110022'));
    expect(rewritten, contains('fund_rule_monitor'));
    expect(rewritten, contains('不申购、不赎回'));
    expect(rewritten, contains('不使用股票 K 线信号'));
    final evidence = _analysisEvidence(rewritten);
    expect(evidence['contract'], 'analysis-evidence-v1');
    expect(evidence['kind'], 'fund_analysis');
    expect(evidence['strategyReadiness'], 'analysis_only');
    expect((evidence['subject'] as Map<String, dynamic>)['id'], '110022');
    expect(
      (evidence['sourceCoverage'] as Map<String, dynamic>)['interfaceId'],
      'fund.monitor_event',
    );
    expect(rewritten, isNot(contains('XueqiuTrade(action:"balance")')));
  });

  test('fund monitor trigger asks fund-specific confirmation first', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 基金定投观察] 基金观察策略已触发：易方达消费行业 110022。请先复核基金净值、回撤、波动和定投边界，不要直接申购、赎回或写入模拟交易。\n'
            'data: {"template":"fund_rule_monitor","strategyId":"fund_dca_observation_110022_v1","code":"110022","signal":"observe_or_prepare","confirmationRequired":true}',
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls!.single.name, 'AskUserQuestion');
    final question = (calls.single.input['questions'] as List).single as Map;
    expect(question['header'], '基金观察');
  });

  test(
    'portfolio rebalance monitor asks portfolio-specific confirmation first',
    () {
      final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

      final calls = hooks.buildPreflightToolCalls([
        Message(
          role: Role.user,
          content:
              '[Monitor Notification: 组合再平衡复核] 组合策略复核触发：strategyId=portfolio_rank_v1。请复核 portfolioEvidence、rebalanceDraft 和再平衡边界，不要自动调仓或下单。\n'
              'data: {"template":"portfolio_rebalance_monitor","strategyId":"portfolio_rank_v1","signal":"review_rebalance","portfolioEvidence":{"mode":"equal_weight_selected_metrics","selectedCount":2,"aggregateMetrics":{"selectedSymbols":["600519","000858"],"expectedReturnPct":8.4,"portfolioMaxDrawdownPct":-5.2}},"rebalanceDraft":{"mode":"equal_weight_top_n","rebalanceInterval":"monthly","maxPositionWeight":0.4,"positions":[{"symbol":"600519","targetWeight":0.4,"weightCapped":true},{"symbol":"000858","targetWeight":0.4}],"tradeBoundary":"evidence only; confirmation required before any order"},"confirmationRequired":true}',
        ),
      ]);

      expect(calls, isNotNull);
      expect(calls!.single.name, 'AskUserQuestion');
      final question = (calls.single.input['questions'] as List).single as Map;
      expect(question['header'], '组合复核');
    },
  );

  test('portfolio rebalance monitor builds review-only summary', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            '[Monitor Notification: 组合再平衡复核] 组合策略复核触发：strategyId=portfolio_rank_v1。请复核 portfolioEvidence、rebalanceDraft 和再平衡边界，不要自动调仓或下单。\n'
            'data: {"template":"portfolio_rebalance_monitor","strategyId":"portfolio_rank_v1","signal":"review_rebalance","portfolioEvidence":{"mode":"equal_weight_selected_metrics","selectedCount":2,"aggregateMetrics":{"selectedSymbols":["600519","000858"],"expectedReturnPct":8.4,"portfolioMaxDrawdownPct":-5.2},"portfolioBacktestEvidence":{"bars":120,"portfolioReturnPct":6.1}},"rebalanceDraft":{"mode":"equal_weight_top_n","rebalanceInterval":"monthly","maxPositionWeight":0.4,"positions":[{"symbol":"600519","targetWeight":0.4,"weightCapped":true},{"symbol":"000858","targetWeight":0.4}],"tradeBoundary":"evidence only; confirmation required before any order"},"confirmationRequired":true}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'ask',
            name: 'AskUserQuestion',
            input: {
              'question': '是否进入组合复核？',
              'options': ['1. 只复核，不调仓', '2. 取消'],
            },
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'ask', content: '1'),
      ),
    ];

    final rewritten = hooks.rewriteFinalAnswer(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      answer: '继续观察。',
    );

    expect(rewritten, isNotNull);
    expect(rewritten!, contains('组合再平衡监控已触发'));
    expect(rewritten, contains('strategyId=portfolio_rank_v1'));
    expect(rewritten, contains('portfolio_rebalance_monitor'));
    expect(rewritten, contains('600519、000858'));
    expect(rewritten, contains('targetWeight=40.0%'));
    expect(rewritten, contains('不自动调仓'));
    expect(rewritten, contains('不写入 Portfolio 交易'));
    final review = _strategyReview(rewritten);
    expect(review['contract'], 'strategy-review-v1');
    expect(review['reviewKind'], 'portfolio_rebalance_monitor');
    expect(review['strategyId'], 'portfolio_rank_v1');
    expect(review['subjects'], containsAll(['600519', '000858']));
    expect(review['boundaries'], contains('no_portfolio_mutation'));
    expect(rewritten, isNot(contains('XueqiuTrade(action:"balance")')));
  });

  test('save-and-rerun preflight saves latest backtested strategy evidence', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(role: Role.user, content: '帮我设计策略并用本地数据回测。'),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'backtest',
            name: 'MarketData',
            input: {'action': 'custom_strategy_backtest'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'backtest',
          content: '''
{
  "action": "custom_strategy_backtest",
  "status": "backtested",
  "symbol": "300059",
  "strategyId": "custom_low_risk_entry_v1",
  "validation": {
    "strategyId": "custom_low_risk_entry_v1",
    "spec": {
      "id": "custom_low_risk_entry_v1",
      "symbol": "300059",
      "symbols": ["300059"]
    }
  },
  "metrics": {"tradeCount": 3}
}

''',
        ),
      ),
      Message(
        role: Role.user,
        content:
            'persist strategy artifact\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"save","executionMode":"preview_only","safetyBoundary":"save strategy artifact only","evidenceRefs":["custom_strategy_backtest"],"confirmationState":"none","source":"agent-structured-intent"}}',
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'custom_strategy_save');
    expect(
      calls.single.input['strategySpec'],
      containsPair('symbol', '300059'),
    );
    final evidence = calls.single.input['evidence'] as Map<String, dynamic>;
    expect(evidence['status'], 'backtested');
  });

  test('save-and-rerun preflight runs saved backtested strategy by id', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'rerun saved strategy\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"rerun","executionMode":"preview_only","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_save"],"confirmationState":"none","source":"agent-structured-intent"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'save',
            name: 'MarketData',
            input: {'action': 'custom_strategy_save'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'save',
          content: '''
{
  "action": "custom_strategy_save",
  "status": "evidence_attached",
  "strategyId": "custom_low_risk_entry_v1",
  "spec": {
    "id": "custom_low_risk_entry_v1",
    "symbol": "300059",
    "symbols": ["300059"]
  },
  "evidence": {
    "status": "backtested",
    "actualStartDate": "2025-12-24",
    "actualEndDate": "2026-06-30",
    "bars": 122
  }
}
''',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'custom_strategy_run');
    expect(calls.single.input['strategyId'], 'custom_low_risk_entry_v1');
    expect(calls.single.input['symbols'], ['300059']);
  });

  test('saved strategy list drives multi-symbol rerun from workflow state', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'rerun saved strategy\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"rerun","executionMode":"preview_only","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_list","custom_strategy_run"],"confirmationState":"none","subjects":["300059","600519"],"source":"scenario"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'list',
            name: 'MarketData',
            input: {'action': 'custom_strategy_list'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'list',
          content: '''
{
  "action": "custom_strategy_list",
  "strategies": [
    {
      "strategyId": "custom_low_risk_entry_v1",
      "status": "backtested",
      "assetClass": "stock",
      "symbols": ["300059"]
    },
    {
      "strategyId": "momentum_breakout_v1",
      "status": "backtested",
      "assetClass": "stock",
      "symbols": ["600519", "000858", "300059"]
    }
  ]
}
''',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(2));
    expect(
      calls!.map((call) => call.input['action']),
      everyElement('custom_strategy_run'),
    );
    expect(
      calls.map((call) => call.input['strategyId']),
      everyElement('momentum_breakout_v1'),
    );
    expect(calls.map((call) => call.input['symbols']).toList(), [
      ['300059'],
      ['600519'],
    ]);
  });

  test('saved strategy rerun discovers list before generic strategy help', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            '查看已保存策略，选择一个在 300059 和 600519 上分别跑一次，并比较结果。\n\n'
            'data:{"workflowState":{"workflowKind":"strategyReview","assetClass":"stock","intentMode":"rerun","executionMode":"previewOnly","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_list","custom_strategy_run"],"confirmationState":"none","subjects":["300059","600519"],"source":"scenario:standalone-p0-005"}}\n\n'
            '[Context update]\n'
            '[04:43:06] 已切换看板：Market Overview',
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'custom_strategy_list');
  });

  test('saved strategy rerun accepts exact scenario workflow state casing', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            '查看已保存策略，选择一个在 300059 和 600519 上分别跑一次，并比较结果。\n\n'
            'data:{"workflowState":{"workflowKind":"strategyReview","assetClass":"stock","intentMode":"rerun","executionMode":"previewOnly","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_list","custom_strategy_run"],"confirmationState":"none","subjects":["300059","600519"],"source":"scenario:standalone-p0-005"}}\n\n'
            '[Context update]\n'
            '[04:43:06] 已切换看板：Market Overview',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'list',
            name: 'MarketData',
            input: {'action': 'custom_strategy_list'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'list',
          content: '''
{
  "action": "custom_strategy_list",
  "strategies": [
    {
      "strategyId": "momentum_breakout_v1",
      "status": "backtested",
      "assetClass": "stock",
      "symbols": ["600519", "000858", "300059"]
    }
  ]
}
''',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(2));
    expect(
      calls!.map((call) => call.input['strategyId']),
      everyElement('momentum_breakout_v1'),
    );
  });

  test('saved strategy rerun only issues missing subject runs', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'rerun saved strategy\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"rerun","executionMode":"preview_only","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_list","custom_strategy_run"],"confirmationState":"none","subjects":["300059","600519"],"source":"scenario"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'list',
            name: 'MarketData',
            input: {'action': 'custom_strategy_list'},
          ),
          ToolUse(
            id: 'run-300059',
            name: 'MarketData',
            input: {
              'action': 'custom_strategy_run',
              'strategyId': 'momentum_breakout_v1',
              'symbols': ['300059'],
            },
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'list',
          content: '''
{
  "action": "custom_strategy_list",
  "strategies": [
    {
      "strategyId": "momentum_breakout_v1",
      "status": "backtested",
      "assetClass": "stock",
      "symbols": ["600519", "000858", "300059"]
    }
  ]
}
''',
        ),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'run-300059',
          content: '''
{
  "action": "custom_strategy_run",
  "status": "backtested",
  "strategyId": "momentum_breakout_v1",
  "symbol": "300059"
}
''',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(1));
    expect(calls!.single.input['action'], 'custom_strategy_run');
    expect(calls.single.input['strategyId'], 'momentum_breakout_v1');
    expect(calls.single.input['symbols'], ['600519']);
  });

  test('explicit strategy id rerun is not replaced by latest saved strategy', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content:
            'rerun explicit saved strategy\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"rerun","executionMode":"preview_only","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_save"],"confirmationState":"none","subject":"custom_20_v1","source":"agent-structured-intent"},"strategySpec":{"symbol":"600519","symbols":["600519"]}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'save',
            name: 'MarketData',
            input: {'action': 'custom_strategy_save'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'save',
          content: '''
{
  "action": "custom_strategy_save",
  "status": "backtested",
  "strategyId": "custom_low_risk_entry_v1",
  "spec": {
    "id": "custom_low_risk_entry_v1",
    "symbol": "300059",
    "symbols": ["300059"]
  }
}
''',
        ),
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(1));
    expect(calls!.single.name, 'MarketData');
    expect(calls.single.input['action'], 'custom_strategy_run');
    expect(calls.single.input['strategyId'], 'custom_20_v1');
    expect(calls.single.input['symbols'], ['600519']);
  });

  test('saved strategy read and run evidence finishes rerun workflow', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final answer = hooks.buildPreflightAnswer([
      Message(
        role: Role.user,
        content:
            'rerun saved strategy\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"rerun","executionMode":"preview_only","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_read","custom_strategy_run"],"confirmationState":"none","subject":"custom_low_risk_entry_v1","source":"agent-structured-intent"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'read',
            name: 'MarketData',
            input: {'action': 'custom_strategy_read'},
          ),
          ToolUse(
            id: 'run',
            name: 'MarketData',
            input: {'action': 'custom_strategy_run'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'read', content: _strategyReadResult),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'run', content: _strategyRunResult),
      ),
    ]);

    expect(answer, isNotNull);
    expect(answer, contains('已完成已保存策略的读取与重跑'));
    expect(answer, contains('custom_low_risk_entry_v1'));
    expect(answer, contains('未调用 Portfolio、XueqiuTrade'));
  });

  test('saved strategy run evidence stops repeated wrong identity rerun', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            'rerun saved strategy\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_review","assetClass":"stock","intentMode":"rerun","executionMode":"preview_only","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_read","custom_strategy_run"],"confirmationState":"none","subject":"custom_low_risk_entry_v1","source":"agent-structured-intent"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'read',
            name: 'MarketData',
            input: {'action': 'custom_strategy_read'},
          ),
          ToolUse(
            id: 'run',
            name: 'MarketData',
            input: {'action': 'custom_strategy_run'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'read', content: _strategyReadResult),
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'run', content: _strategyRunResult),
      ),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      toolCalls: const [
        ToolUse(
          id: 'wrong-run',
          name: 'MarketData',
          input: {
            'action': 'custom_strategy_run',
            'strategyId': '300059',
            'symbols': ['300059'],
          },
        ),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.answer, contains('已完成已保存策略的读取与重跑'));
    expect(interception.skippedReason, contains('successful custom_strategy'));
  });

  test('portfolio rank evidence does not suppress structured backtest', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            'structured strategy workflow\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"stock","intentMode":"backtest","executionMode":"preview_only","safetyBoundary":"read-only backtest","evidenceRefs":["custom_strategy_rank"],"confirmationState":"none","source":"agent-structured-intent"},"strategySpec":{"id":"rank_then_backtest_v1","assetClass":"stock","symbols":["600519","300059"],"universe":{"symbols":["600519","300059"]}}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'rank',
            name: 'MarketData',
            input: {'action': 'custom_strategy_rank'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'rank', content: _rankResult),
      ),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      toolCalls: const [
        ToolUse(
          id: 'backtest',
          name: 'MarketData',
          input: {
            'action': 'custom_strategy_backtest',
            'symbols': ['600519'],
          },
        ),
      ],
    );

    expect(interception, isNull);
  });

  test('portfolio rank evidence still stops file and DataProcess drift', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);
    final messages = [
      Message(
        role: Role.user,
        content:
            'structured portfolio observation\n'
            'data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"strategy_design","assetClass":"stock","intentMode":"backtest","executionMode":"preview_only","safetyBoundary":"portfolio observation only","evidenceRefs":["custom_strategy_rank"],"confirmationState":"none","source":"agent-structured-intent"}}',
      ),
      Message(
        role: Role.assistant,
        content: '',
        toolUses: const [
          ToolUse(
            id: 'rank',
            name: 'MarketData',
            input: {'action': 'custom_strategy_rank'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(toolUseId: 'rank', content: _rankResult),
      ),
    ];

    final interception = hooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: 0,
      prompt: messages.first.content,
      toolCalls: const [
        ToolUse(
          id: 'score',
          name: 'DataProcess',
          input: {'action': 'score_technical'},
        ),
      ],
    );

    expect(interception, isNotNull);
    expect(interception!.answer, contains('自选股策略组合观察方案'));
    expect(interception.skippedReason, contains('custom_strategy_rank'));
  });
}

const _strategyReadResult = '''
{
  "action": "custom_strategy_read",
  "strategyId": "custom_low_risk_entry_v1",
  "status": "backtested",
  "savedStatus": "backtested",
  "runnable": true,
  "strategySpec": {
    "id": "custom_low_risk_entry_v1",
    "symbol": "300059",
    "symbols": ["300059"],
    "indicators": [{"id": "sma20", "type": "sma"}]
  }
}
''';

const _strategyRunResult = '''
{
  "action": "custom_strategy_run",
  "strategyId": "custom_low_risk_entry_v1",
  "symbol": "300059",
  "status": "backtested",
  "actualStartDate": "2025-07-08",
  "actualEndDate": "2026-07-01",
  "bars": 238,
  "metrics": {
    "tradeCount": 7,
    "totalReturnPct": -4.18,
    "maxDrawdownPct": 7.47,
    "winRatePct": 14.29
  },
  "assumptions": {
    "commissionPct": 0.1,
    "slippagePct": 0.05
  },
  "dataCoverage": {
    "source": "local kline_daily",
    "rows": 238,
    "actualStartDate": "2025-07-08",
    "actualEndDate": "2026-07-01"
  }
}
''';

const _rankResult = '''
{
  "action": "custom_strategy_rank",
  "status": "ranked",
  "strategyId": "custom_rank_then_backtest_v1",
  "ranked": [
    {
      "symbol": "600519",
      "rank": 1,
      "score": 1.2,
      "status": "ranked",
      "selectionEvidence": {"selectedForDraft": true},
      "dataCoverage": {"bars": 240}
    },
    {
      "symbol": "300059",
      "rank": 2,
      "score": 0.8,
      "status": "ranked",
      "selectionEvidence": {"selectedForDraft": true},
      "dataCoverage": {"bars": 240}
    }
  ],
  "portfolioEvidence": {
    "mode": "equal_weight_selected_metrics",
    "selectedCount": 2,
    "aggregateMetrics": {
      "portfolioReturnPct": 6.1,
      "portfolioMaxDrawdownPct": -5.2
    }
  },
  "rebalanceDraft": {
    "mode": "equal_weight_top_n",
    "rebalanceInterval": "monthly",
    "maxPositionWeight": 0.35
  }
}
''';

Message _customBacktestCall(String id, String symbol) => Message(
  role: Role.assistant,
  content: '',
  toolUses: [
    ToolUse(
      id: id,
      name: 'MarketData',
      input: {'action': 'custom_strategy_backtest', 'code': symbol},
    ),
  ],
);

Message _customBacktestResult(
  String id,
  String symbol, {
  required num totalReturnPct,
  required num trades,
}) => Message(
  role: Role.tool,
  toolResult: ToolResult(
    toolUseId: id,
    content:
        '''
{
  "action": "custom_strategy_backtest",
  "status": "backtested",
  "symbol": "$symbol",
  "strategyId": "strategy_$symbol",
  "actualStartDate": "2025-07-01",
  "actualEndDate": "2026-06-30",
  "bars": 240,
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
''',
  ),
);

Map<String, dynamic> _analysisEvidence(String summary) {
  final line = summary
      .split('\n')
      .firstWhere((item) => item.startsWith('analysisEvidence:'));
  return jsonDecode(line.substring('analysisEvidence:'.length))
      as Map<String, dynamic>;
}

Map<String, dynamic> _strategyReview(String summary) {
  final line = summary
      .split('\n')
      .firstWhere((item) => item.startsWith('strategyReview:'));
  return jsonDecode(line.substring('strategyReview:'.length))
      as Map<String, dynamic>;
}

Map<String, dynamic> _tradePrep(String summary) {
  final line = summary
      .split('\n')
      .firstWhere((item) => item.startsWith('tradePrep:'));
  return jsonDecode(line.substring('tradePrep:'.length))
      as Map<String, dynamic>;
}

String _tradeSizingStateContent(
  String symbol, {
  List<String> blockedTools = const [],
}) {
  return 'structured trade sizing request\n'
      'data: ${jsonEncode({
        'workflowState': {
          'contract': 'finance-workflow-state-v1',
          'workflowKind': 'trade_prep',
          'assetClass': 'stock',
          'intentMode': 'size',
          'executionMode': 'requires_confirmation',
          'safetyBoundary': 'trade preparation only',
          'evidenceRefs': ['trade-prep-v1'],
          'confirmationState': 'pending',
          'subject': symbol,
          'source': 'agent-structured-intent',
          if (blockedTools.isNotEmpty) 'blockedTools': blockedTools,
        },
      })}';
}

class _FakeTool extends Tool {
  @override
  final String name;

  _FakeTool(this.name);

  @override
  String get description => name;

  @override
  Map<String, dynamic> get inputSchema => const {};

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async => ToolResult(toolUseId: toolUseId, content: '{}');
}
