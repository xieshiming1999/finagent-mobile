import 'dart:convert';

import '../../../agent/message.dart';
import '../execution/trade_prep_contract.dart';
import 'finance_workflow_state.dart';

/// Stops post-confirmation drift in strategy-to-trade turns.
///
/// The trading boundary is: collect account evidence, ask the user, then answer
/// from that decision. A confirmation answer must not become a reason to edit
/// memory, change watchlists, or execute another trading tool in the same turn.
class FinanceTradeConfirmationSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required List<ToolUse> proposedToolCalls,
  }) {
    final workflowState = FinanceWorkflowState.latestTradePrepFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
    if (!_isTradeConfirmationWorkflow(workflowState)) return null;
    final answer = _latestAskUserAnswer(messages, turnStartIndex);
    if (answer == null) return null;
    if (!proposedToolCalls.any(_isPostConfirmationDrift)) return null;

    return [
      '已记录交易确认边界，本轮停止继续调用文件、记忆、观察池或交易工具。',
      '',
      '- 用户选择：$answer。',
      '- 当前结论：只保留策略信号、账户证据和风险测算；不在本轮执行雪球模拟盘或本地模拟盘交易。',
      '- 后续执行条件：策略实际触发后，必须重新给出组合、价格、股数、投入金额、止损价、止盈价和最大亏损，并等待明确确认。',
      '- 本轮边界：未写入记忆，未追加观察池变更，未执行 XueqiuTrade 买卖或 Portfolio trade。',
      'tradePrep:${jsonEncode(_tradePrep(answer))}',
    ].join('\n');
  }

  Map<String, dynamic> _tradePrep(String answer) {
    return TradePrepContract(
      prepKind: 'strategy_trade_confirmation_stop',
      strategyId: '-',
      signal: 'confirmation_stop',
      symbol: '-',
      evidence: const {
        'askUserQuestion': true,
        'postConfirmationDriftBlocked': true,
      },
      boundaries: const [
        'confirmation_stop',
        'no_order_write',
        'no_portfolio_trade',
        'no_watchlist_mutation',
        'no_memory_write',
        'requires_explicit_confirmation_before_execution',
      ],
      confirmation: answer,
    ).toJson();
  }

  bool _isTradeConfirmationWorkflow(FinanceWorkflowState? state) {
    return state?.workflowKind == FinanceWorkflowKind.tradePrep &&
        (state?.executionMode == FinanceExecutionMode.requiresConfirmation ||
            state?.confirmationState == FinanceConfirmationState.pending ||
            state?.confirmationState == FinanceConfirmationState.answered);
  }

  String? _latestAskUserAnswer(List<Message> messages, int turnStartIndex) {
    final toolUseIds = <String>{};
    for (final message in messages.skip(turnStartIndex)) {
      final uses = message.toolUses;
      if (uses == null) continue;
      for (final use in uses) {
        if (use.name == 'AskUserQuestion') toolUseIds.add(use.id);
      }
    }
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      if (!toolUseIds.contains(result.toolUseId)) continue;
      final answer = result.content.trim();
      if (answer.isNotEmpty) return answer;
    }
    return null;
  }

  bool _isPostConfirmationDrift(ToolUse call) {
    if (call.name == 'Read' || call.name == 'Write') return true;
    if (call.name == 'FileRead' || call.name == 'FileWrite') return true;
    if (call.name == 'Skill') return true;
    if (call.name == 'Watchlist') return true;
    if (call.name == 'Portfolio') {
      final action = (call.input['action'] ?? '').toString().toLowerCase();
      return action != 'preview_trade' &&
          action != 'snapshot' &&
          action != 'risk' &&
          action != 'history' &&
          action != 'help';
    }
    if (call.name == 'XueqiuTrade') {
      final action = (call.input['action'] ?? '').toString().toLowerCase();
      return action == 'buy' ||
          action == 'sell' ||
          action == 'transfer_in' ||
          action == 'transfer_out';
    }
    if (call.name == 'MarketData') {
      final action = call.input['action']?.toString() ?? '';
      return action.startsWith('custom_strategy_') ||
          action == 'backtest' ||
          action == 'backtest_batch' ||
          action == 'backtest_composite' ||
          action == 'optimize_params';
    }
    return false;
  }
}
