import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('does not infer workflow state from natural-language prompt text', () {
    expect(FinanceWorkflowState.fromUserContent('帮我设计一个策略并保存'), isNull);
    expect(
      FinanceWorkflowState.fromUserContent('如果可以买入贵州茅台，请帮我计算仓位并准备下单'),
      isNull,
    );
    expect(FinanceWorkflowState.fromUserContent('请确认是否继续下一步回测并加入观察池'), isNull);
  });

  test('ignores JSON payloads without an explicit workflowState contract', () {
    final state = FinanceWorkflowState.fromUserContent('''
{"intent":"trade_prep","symbol":"600519","confirmationRequired":true}
''');

    expect(state, isNull);
  });

  test('accepts explicit whole-message workflowState JSON', () {
    final state = FinanceWorkflowState.fromUserContent('''
{
  "workflowState": {
    "contract": "finance-workflow-state-v1",
    "workflowKind": "trade_prep",
    "assetClass": "stock",
    "intentMode": "size",
    "executionMode": "requires_confirmation",
    "safetyBoundary": "trade preparation only",
    "evidenceRefs": ["trade-prep-v1"],
    "confirmationState": "pending",
    "subject": "600519",
    "source": "agent-structured-intent"
  }
}
''');

    expect(state, isNotNull);
    expect(state!.workflowKind, FinanceWorkflowKind.tradePrep);
    expect(state.intentMode, FinanceIntentMode.size);
    expect(state.confirmationState, FinanceConfirmationState.pending);
    expect(state.subject, '600519');
    expect(state.source, 'agent-structured-intent');
  });

  test('latest state scan does not classify ordinary user turns', () {
    final state = FinanceWorkflowState.latestFromMessages([
      Message(role: Role.user, content: '今天市场怎么样？请给我一个策略建议。'),
      Message(role: Role.assistant, content: '我会先检查工具。'),
    ]);

    expect(state, isNull);
  });

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

  test('accepts trade_preparation scenario workflowState alias', () {
    final state = FinanceWorkflowState.fromJson({
      'contract': 'finance-workflow-state-v1',
      'workflowKind': 'trade_preparation',
      'assetClass': 'stock',
      'intentMode': 'execute_after_confirmation',
      'executionMode': 'xueqiu_moni',
      'confirmationState': 'required',
      'safetyBoundary': 'Xueqiu MONI simulated trade only',
      'evidenceRefs': ['xueqiu_preview_order'],
      'requiredVerifier': {
        'tool': 'WorkflowVerifier',
        'action': 'check',
        'workflow': 'trade_preparation',
      },
    });

    expect(state.workflowKind, FinanceWorkflowKind.tradePrep);
    expect(state.assetClass, FinanceAssetClass.stock);
    expect(state.requiredVerifier?['workflow'], 'trade_preparation');
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

  test('reads data workflowState before trailing context update', () {
    final state = FinanceWorkflowState.fromUserContent(
      '查看已保存策略，选择一个在 300059 和 600519 上分别跑一次，并比较结果。\n\n'
      'data:{"workflowState":{"workflowKind":"strategyReview","assetClass":"stock","intentMode":"rerun","executionMode":"previewOnly","safetyBoundary":"reuse saved strategy artifact","evidenceRefs":["custom_strategy_list","custom_strategy_run"],"confirmationState":"none","subjects":["300059","600519"],"source":"scenario:standalone-p0-005"}}\n\n'
      '[Context update]\n'
      '[04:43:06] 已切换看板：Market Overview',
    );

    expect(state, isNotNull);
    expect(state!.workflowKind, FinanceWorkflowKind.strategyReview);
    expect(state.intentMode, FinanceIntentMode.rerun);
    expect(state.executionMode, FinanceExecutionMode.previewOnly);
    expect(state.subjects, ['300059', '600519']);
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
