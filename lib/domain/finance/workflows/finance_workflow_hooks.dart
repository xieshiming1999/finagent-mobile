import 'dart:convert';

import '../../../agent/domain_workflow_hooks.dart';
import 'finance_custom_strategy_evidence.dart';
import 'finance_custom_strategy_policy.dart';
import 'finance_custom_strategy_preflight.dart';
import 'finance_evidence_review_summary.dart';
import 'finance_fund_candidate_summary.dart';
import 'finance_fund_comparison_summary.dart';
import 'finance_fund_monitor_summary.dart';
import 'finance_fund_strategy_evidence_summary.dart';
import 'finance_fund_watch_summary.dart';
import 'finance_market_overview_summary.dart';
import 'finance_portfolio_monitor_summary.dart';
import 'finance_stock_candidate_summary.dart';
import 'finance_stock_watch_recovery.dart';
import 'finance_strategy_budget_summary.dart';
import 'finance_strategy_monitor_recovery.dart';
import 'finance_trade_budget_summary.dart';
import 'finance_trade_confirmation_summary.dart';
import 'finance_trade_sizing_preflight.dart';
import 'finance_workflow_state.dart';
import '../../../agent/message.dart';
import '../../../agent/tool.dart';

/// Finance workflow extension boundary for the generic Dart agent loop.
///
/// The loop owns conversation mechanics. This facade owns finance workflow
/// evidence summaries, stop policies, and bounded recovery hooks.
class FinanceWorkflowHooks extends DomainWorkflowHooks {
  final FinanceCustomStrategyPolicy customStrategyPolicy;
  final FinanceCustomStrategyEvidence _customStrategyEvidence =
      FinanceCustomStrategyEvidence();
  final FinanceCustomStrategyPreflight _customStrategyPreflight =
      FinanceCustomStrategyPreflight();
  final FinanceEvidenceReviewSummary _evidenceReviewSummary =
      FinanceEvidenceReviewSummary();
  final FinanceFundCandidateSummary _fundCandidateSummary =
      FinanceFundCandidateSummary();
  final FinanceFundComparisonSummary _fundComparisonSummary =
      FinanceFundComparisonSummary();
  final FinanceFundMonitorSummary _fundMonitorSummary =
      FinanceFundMonitorSummary();
  final FinanceFundStrategyEvidenceSummary _fundStrategyEvidenceSummary =
      FinanceFundStrategyEvidenceSummary();
  final FinanceFundWatchSummary _fundWatchSummary = FinanceFundWatchSummary();
  final FinanceMarketOverviewSummary _marketOverviewSummary =
      FinanceMarketOverviewSummary();
  final FinancePortfolioMonitorSummary _portfolioMonitorSummary =
      FinancePortfolioMonitorSummary();
  final FinanceStockCandidateSummary _stockCandidateSummary =
      FinanceStockCandidateSummary();
  final FinanceStockWatchRecovery _stockWatchRecovery =
      FinanceStockWatchRecovery();
  final FinanceStrategyBudgetSummary _strategyBudgetSummary =
      FinanceStrategyBudgetSummary();
  final FinanceStrategyMonitorRecovery _strategyMonitorRecovery =
      FinanceStrategyMonitorRecovery();
  final FinanceTradeBudgetSummary _tradeBudgetSummary =
      FinanceTradeBudgetSummary();
  final FinanceTradeConfirmationSummary _tradeConfirmationSummary =
      FinanceTradeConfirmationSummary();
  late final FinanceTradeSizingPreflight _tradeSizingPreflight;

  FinanceWorkflowHooks({
    required bool Function(String toolName) isBypassTool,
    Set<String>? availableToolNames,
  }) : customStrategyPolicy = FinanceCustomStrategyPolicy(
         isBypassTool: isBypassTool,
       ) {
    _tradeSizingPreflight = FinanceTradeSizingPreflight(
      availableToolNames: availableToolNames,
    );
  }

  @override
  List<ToolUse>? buildPreflightToolCalls(List<Message> messages) {
    return _buildFundMonitorReviewPreflightToolCalls(messages) ??
        _buildPortfolioMonitorReviewPreflightToolCalls(messages) ??
        _buildFundStrategyPreflightToolCalls(messages) ??
        _evidenceReviewSummary.buildSearchToolCalls(messages) ??
        _tradeSizingPreflight.buildToolCalls(messages) ??
        _customStrategyPreflight.buildToolCalls(messages);
  }

  List<ToolUse>? _buildPortfolioMonitorReviewPreflightToolCalls(
    List<Message> messages,
  ) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final payload = _structuredMonitorPayload(messages[start].content);
    if (payload == null ||
        payload['template'] != 'portfolio_rebalance_monitor') {
      return null;
    }
    final turnMessages = messages.skip(start + 1).toList();
    if (_hasAnsweredAskUserQuestion(turnMessages)) return null;
    if (turnMessages.any(
      (message) => (message.toolUses ?? const <ToolUse>[]).any(
        (call) => call.name == 'AskUserQuestion',
      ),
    )) {
      return null;
    }
    final strategyId = '${payload['strategyId'] ?? '-'}'.trim();
    return [
      ToolUse(
        id: 'portfolio_monitor_review_confirmation_${DateTime.now().microsecondsSinceEpoch}',
        name: 'AskUserQuestion',
        input: {
          'questions': [
            {
              'question': '组合再平衡监控 $strategyId 已触发，是否进入只复核、不调仓的观察处理？',
              'header': '组合复核',
              'options': [
                {
                  'label': '只复核不调仓',
                  'description': '检查组合排序证据、目标权重和风险边界，不写 Portfolio 或雪球模拟盘交易。',
                },
                {'label': '继续观察', 'description': '记录触发结果，本轮不做进一步操作。'},
              ],
            },
          ],
        },
      ),
    ];
  }

  List<ToolUse>? _buildFundMonitorReviewPreflightToolCalls(
    List<Message> messages,
  ) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final payload = _structuredMonitorPayload(messages[start].content);
    if (payload == null || payload['template'] != 'fund_rule_monitor') {
      return null;
    }
    final turnMessages = messages.skip(start + 1).toList();
    if (_hasAnsweredAskUserQuestion(turnMessages)) return null;
    if (turnMessages.any(
      (message) => (message.toolUses ?? const <ToolUse>[]).any(
        (call) => call.name == 'AskUserQuestion',
      ),
    )) {
      return null;
    }
    final fundCode =
        '${payload['code'] ?? payload['fundCode'] ?? payload['symbol'] ?? '-'}'
            .trim();
    return [
      ToolUse(
        id: 'fund_monitor_review_confirmation_${DateTime.now().microsecondsSinceEpoch}',
        name: 'AskUserQuestion',
        input: {
          'questions': [
            {
              'question': '基金观察监控 $fundCode 已触发，是否进入只复核、不交易的观察处理？',
              'header': '基金观察',
              'options': [
                {
                  'label': '只复核不交易',
                  'description': '检查净值、回撤、波动和定投边界，不执行申购赎回或模拟交易。',
                },
                {'label': '继续观察', 'description': '记录触发结果，本轮不做进一步操作。'},
              ],
            },
          ],
        },
      ),
    ];
  }

  Map<String, dynamic>? _structuredMonitorPayload(String content) {
    final index = content.lastIndexOf('data:');
    if (index < 0) return null;
    try {
      final decoded = jsonDecode(content.substring(index + 5).trim());
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  List<ToolUse>? _buildFundStrategyPreflightToolCalls(List<Message> messages) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final workflowState = FinanceWorkflowState.fromUserContent(
      messages[start].content,
    );
    if (!_isFundStrategyWorkflow(workflowState)) return null;
    final turnMessages = messages.skip(start + 1).toList();
    if (_hasSuccessfulAction(turnMessages, 'custom_strategy_observe') ||
        _hasSuccessfulAction(turnMessages, 'custom_strategy_fund_backtest')) {
      return null;
    }
    if (_hasOrdinaryAndMoneyFundEvidence(turnMessages)) return null;
    final readbackCode = _latestSuccessfulFundReadbackCode(turnMessages);
    if (readbackCode != null) {
      return [
        ToolUse(
          id: 'fund_strategy_observe_${DateTime.now().microsecondsSinceEpoch}',
          name: 'MarketData',
          input: {
            'action': 'custom_strategy_observe',
            'symbols': [readbackCode],
            'strategySpec': _draftFundObservationStrategySpec(readbackCode),
          },
        ),
      ];
    }
    if (_hasToolCallAction(turnMessages, 'MarketData', 'query_fund_nav')) {
      return null;
    }
    final hasFundNav = _hasSuccessfulAction(turnMessages, 'query_fund_nav');
    if (hasFundNav) return null;
    final fundSymbol = _fundSymbolFromWatchlist(turnMessages);
    if (fundSymbol == null) {
      return [
        ToolUse(
          id: 'fund_strategy_watchlist_${DateTime.now().microsecondsSinceEpoch}',
          name: 'Watchlist',
          input: const {'action': 'list'},
        ),
      ];
    }
    return [
      ToolUse(
        id: 'fund_strategy_nav_${DateTime.now().microsecondsSinceEpoch}',
        name: 'MarketData',
        input: {
          'action': 'query_fund_nav',
          'symbols': [fundSymbol],
          'limit': 120,
        },
      ),
    ];
  }

  bool _isFundStrategyWorkflow(FinanceWorkflowState? state) {
    return state?.isStrategy == true &&
        state?.assetClass == FinanceAssetClass.fund &&
        (state?.intentMode == FinanceIntentMode.observe ||
            state?.intentMode == FinanceIntentMode.backtest ||
            state?.intentMode == FinanceIntentMode.validate);
  }

  bool _hasSuccessfulAction(List<Message> messages, String action) {
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is Map && decoded['action'] == action) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  bool _hasOrdinaryAndMoneyFundEvidence(List<Message> messages) {
    var hasOrdinaryNav = false;
    var hasMoneyYield = false;
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        final rows = decoded['data'];
        final hasRows = rows is List && rows.isNotEmpty;
        final action = '${decoded['action'] ?? ''}';
        if (action == 'query_fund_nav' && hasRows) hasOrdinaryNav = true;
        if ((action == 'query_fund_money_yield' ||
                action == 'fund_money_yield') &&
            hasRows) {
          hasMoneyYield = true;
        }
        if (hasOrdinaryNav && hasMoneyYield) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  bool _hasToolCallAction(
    List<Message> messages,
    String toolName,
    String action,
  ) {
    for (final message in messages) {
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        if (call.name == toolName && call.input['action'] == action) {
          return true;
        }
      }
    }
    return false;
  }

  String? _fundSymbolFromWatchlist(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        final items = decoded['items'];
        if (items is! List) continue;
        for (final item in items) {
          if (item is! Map) continue;
          final type = item['type']?.toString().toLowerCase();
          if (type != 'fund') continue;
          final symbol = item['symbol']?.toString();
          final normalized = symbol?.replaceAll(
            RegExp(r'\.OF$', caseSensitive: false),
            '',
          );
          if (normalized != null && RegExp(r'^\d{6}$').hasMatch(normalized)) {
            return normalized;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? _latestSuccessfulFundReadbackCode(List<Message> messages) {
    final successfulToolIds = <String>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (result != null && !result.isError) {
        successfulToolIds.add(result.toolUseId);
      }
    }
    for (final message in messages.reversed) {
      final uses = message.toolUses;
      if (uses == null) continue;
      for (final call in uses.reversed) {
        if (!successfulToolIds.contains(call.id)) continue;
        if (call.name != 'MarketData' && call.name != 'DataStore') continue;
        final action = '${call.input['action'] ?? ''}';
        if (action != 'query_fund_nav' && action != 'query_fund_money_yield') {
          continue;
        }
        final code = _codeFromToolInput(call.input);
        if (code != null) return code;
      }
    }
    return null;
  }

  String? _codeFromToolInput(Map<String, dynamic> input) {
    for (final key in const ['code', 'fundCode', 'symbol']) {
      final value = '${input[key] ?? ''}'.trim();
      if (RegExp(r'^\d{6}(\.OF)?$', caseSensitive: false).hasMatch(value)) {
        return value.replaceAll(RegExp(r'\.OF$', caseSensitive: false), '');
      }
    }
    for (final key in const ['symbols', 'codes']) {
      final value = input[key];
      if (value is List && value.isNotEmpty) {
        final first = '${value.first}'.trim();
        if (RegExp(r'^\d{6}(\.OF)?$', caseSensitive: false).hasMatch(first)) {
          return first.replaceAll(RegExp(r'\.OF$', caseSensitive: false), '');
        }
      }
    }
    return null;
  }

  Map<String, dynamic> _draftFundObservationStrategySpec(String fundCode) {
    return {
      'id': 'fund_dca_observation_${fundCode}_v1',
      'name': 'fund_dca_observation_$fundCode',
      'version': 1,
      'assetClass': 'fund',
      'market': 'fund',
      'fundCode': fundCode,
      'code': fundCode,
      'dataRequirements': {
        'dataClass': 'ordinary_fund_nav',
        'minBars': 60,
        'requiredFields': ['date', 'nav'],
      },
      'indicators': [
        {
          'id': 'fundDrawdown20',
          'type': 'fund_drawdown',
          'source': 'nav',
          'params': {'period': 20},
        },
        {
          'id': 'fundVolatility20',
          'type': 'fund_volatility',
          'source': 'nav',
          'params': {'period': 20},
        },
        {
          'id': 'navTrend20',
          'type': 'nav_trend',
          'source': 'nav',
          'params': {'period': 20},
        },
      ],
      'entry': {
        'all': [
          {'left': 'fundDrawdown20', 'op': '>=', 'right': 5},
          {'left': 'fundDrawdown20', 'op': '<', 'right': 15},
          {'left': 'navTrend20', 'op': '<', 'right': 0},
        ],
      },
      'exit': {
        'any': [
          {'left': 'fundDrawdown20', 'op': '>=', 'right': 15},
        ],
      },
    };
  }

  @override
  String? buildPreflightAnswer(List<Message> messages) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start >= 0 && _hasAnsweredAskUserQuestion(messages.skip(start + 1))) {
      final continuation = _tradeSizingPreflight.buildToolCalls(messages);
      if (continuation != null && continuation.isNotEmpty) return null;
      final tradeBudget = _tradeBudgetSummary.build(
        messages: messages,
        turnStartIndex: start,
        failureSummary: '无阻断性工具错误；最终回答由交易测算证据摘要接管，未执行交易工具写操作。',
      );
      if (tradeBudget != null) return tradeBudget;
      final fundMonitor = _fundMonitorSummary.build(
        messages.skip(start).toList(),
      );
      if (fundMonitor != null) return fundMonitor;
      final portfolioMonitor = _portfolioMonitorSummary.build(
        messages.skip(start).toList(),
      );
      if (portfolioMonitor != null) return portfolioMonitor;
    }
    if (start >= 0) {
      final savedRunReadback = _customStrategyEvidence.savedRunReadback(
        messages: messages,
        turnStartIndex: start,
      );
      if (savedRunReadback != null) return savedRunReadback;
      final runComparisonEvidence = _customStrategyEvidence.runComparison(
        messages: messages,
        turnStartIndex: start,
      );
      if (runComparisonEvidence != null) return runComparisonEvidence;
      final saveEvidence = _customStrategyEvidence.save(messages, start);
      if (saveEvidence != null &&
          _hasSuccessfulCustomStrategyRun(messages, start)) {
        return [
          saveEvidence,
          '',
          '已完成 `custom_strategy_run` 复用验证；后续重复保存或重复运行调用已停止。',
        ].join('\n');
      }
    }
    return _evidenceReviewSummary.buildAnswer(messages);
  }

  bool _hasAnsweredAskUserQuestion(Iterable<Message> messages) {
    final askIds = <String>{};
    for (final message in messages) {
      for (final use in message.toolUses ?? const <ToolUse>[]) {
        if (use.name == 'AskUserQuestion') askIds.add(use.id);
      }
    }
    for (final message in messages) {
      final result = message.toolResult;
      if (result != null &&
          !result.isError &&
          askIds.contains(result.toolUseId)) {
        return true;
      }
    }
    return false;
  }

  @override
  List<ToolUse> rewriteToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  }) {
    final activeStrategyId =
        _latestSuccessfulCustomStrategyRunId(messages, turnStartIndex) ??
        _firstProposedSavedStrategyRunId(toolCalls);
    if (activeStrategyId == null) return toolCalls;
    var changed = false;
    final rewritten = <ToolUse>[];
    final seenRunKeys = <String>{};
    for (final call in toolCalls) {
      if (call.name == 'MarketData' &&
          call.input['action'] == 'custom_strategy_run') {
        final requestedStrategyId = '${call.input['strategyId'] ?? ''}'.trim();
        var normalizedInput = call.input;
        if (_isStockCode(requestedStrategyId) &&
            requestedStrategyId != activeStrategyId) {
          changed = true;
          normalizedInput = {
            ...call.input,
            'strategyId': activeStrategyId,
            'symbols': [requestedStrategyId],
          };
        }
        final runKey =
            '${normalizedInput['strategyId'] ?? ''}::${_firstSymbolFromInput(normalizedInput)}';
        if (!seenRunKeys.add(runKey)) {
          changed = true;
          continue;
        }
        if (!identical(normalizedInput, call.input)) {
          rewritten.add(
            ToolUse(id: call.id, name: call.name, input: normalizedInput),
          );
          continue;
        }
      }
      rewritten.add(call);
    }
    return changed ? rewritten : toolCalls;
  }

  @override
  DomainToolInterception? interceptToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  }) {
    final tradeConfirmation = _tradeConfirmationSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      proposedToolCalls: toolCalls,
    );
    if (tradeConfirmation != null) {
      return DomainToolInterception(
        answer: tradeConfirmation,
        skippedReason:
            'Skipped: strategy trade confirmation was already answered; no file, memory, watchlist, or trade mutation is allowed in this turn.',
      );
    }

    if (toolCalls.any(
      (call) =>
          customStrategyPolicy.isBypassTool(call.name) ||
          call.name == 'Read' ||
          call.name == 'Grep' ||
          call.name == 'Glob' ||
          call.name == 'LS' ||
          call.name == 'Script' ||
          call.name == 'DataProcess' ||
          _isFundStockDataDrift(call),
    )) {
      final fundComparisonSummary = _fundComparisonSummary.build(
        messages: messages,
        turnStartIndex: turnStartIndex,
        failureSummary: '无阻断性工具错误；已停止脚本、文件读取、股票策略工具或额外 provider 调用。',
      );
      if (fundComparisonSummary != null) {
        return DomainToolInterception(
          answer: fundComparisonSummary,
          skippedReason:
              'Skipped: structured fund NAV and money-yield evidence already exists; no Script, file-read, or stock-strategy bypass is needed for this fund comparison workflow.',
        );
      }
      final fundStrategySummary = _fundStrategyEvidenceSummary.build(
        messages: messages,
        turnStartIndex: turnStartIndex,
        failureSummary: '无阻断性工具错误；已停止文件读取、脚本、股票策略工具或额外 provider 调用。',
      );
      if (fundStrategySummary != null) {
        return DomainToolInterception(
          answer: fundStrategySummary,
          skippedReason:
              'Skipped: structured fund evidence / fund strategy evidence already exists; no file-read or stock-strategy bypass is needed for this finance workflow.',
        );
      }
      final fundSummary = _fundCandidateSummary.build(
        messages: messages,
        turnStartIndex: turnStartIndex,
        failureSummary: '无阻断性工具错误；已停止文件读取、脚本、股票策略工具或额外 provider 调用。',
      );
      if (fundSummary != null) {
        return DomainToolInterception(
          answer: fundSummary,
          skippedReason:
              'Skipped: structured fund evidence already exists; no file-read or stock-strategy bypass is needed for this finance workflow.',
        );
      }
    }

    final portfolioRankEvidence = _customStrategyEvidence.portfolioRank(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    final etfQuoteOnlyEvidence = _etfQuoteOnlyStrategyBoundary(
      messages: messages,
      turnStartIndex: turnStartIndex,
      proposedToolCalls: toolCalls,
    );
    if (etfQuoteOnlyEvidence != null) {
      return DomainToolInterception(
        answer: etfQuoteOnlyEvidence,
        skippedReason:
            'Skipped: ETF quote evidence exists but no successful ETF K-line evidence exists; custom_strategy_rank/backtest requires K-line rows.',
      );
    }
    if (portfolioRankEvidence != null &&
        toolCalls.any(
          (call) =>
              call.name == 'Read' ||
              call.name == 'Grep' ||
              call.name == 'Glob' ||
              call.name == 'LS' ||
              call.name == 'DataProcess' ||
              (call.name == 'MarketData' &&
                  call.input['action'] == 'custom_strategy_run'),
        )) {
      return DomainToolInterception(
        answer: portfolioRankEvidence,
        skippedReason:
            'Skipped: custom_strategy_rank already returned portfolio evidence; no file-read, run, DataProcess, or artifact inspection is needed for this observation workflow.',
      );
    }

    final validateEvidence = _customStrategyEvidence.validation(
      messages,
      turnStartIndex,
    );
    final workflowState = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
    if (validateEvidence != null &&
        customStrategyPolicy.shouldStopAfterValidateOnly(
          state: workflowState,
          toolCalls: toolCalls,
        )) {
      return DomainToolInterception(
        answer: validateEvidence,
        skippedReason: customStrategyPolicy.validateOnlySkipReason,
      );
    }

    final rejectedEvidence = _customStrategyEvidence.rejectedValidation(
      messages,
      turnStartIndex,
    );
    if (rejectedEvidence != null &&
        customStrategyPolicy.shouldStopAfterRejectedValidation(toolCalls)) {
      return DomainToolInterception(
        answer: rejectedEvidence,
        skippedReason: customStrategyPolicy.rejectedValidationSkipReason,
      );
    }

    final unsupportedProxyAnswer = customStrategyPolicy
        .unsupportedProxyStopAnswer(state: workflowState, toolCalls: toolCalls);
    if (unsupportedProxyAnswer != null) {
      return DomainToolInterception(
        answer: unsupportedProxyAnswer,
        skippedReason: customStrategyPolicy.unsupportedProxySkipReason,
      );
    }

    final saveEvidence = _customStrategyEvidence.save(messages, turnStartIndex);
    if (saveEvidence != null &&
        _hasSuccessfulCustomStrategyRun(messages, turnStartIndex) &&
        _hasCustomStrategySaveOrRunCall(toolCalls)) {
      return DomainToolInterception(
        answer: [
          saveEvidence,
          '',
          '已完成 `custom_strategy_run` 复用验证；后续重复保存或重复运行调用已停止。',
        ].join('\n'),
        skippedReason:
            'Skipped: saved custom strategy already has a successful custom_strategy_run result in this turn.',
      );
    }
    final savedRunReadback = _customStrategyEvidence.savedRunReadback(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (savedRunReadback != null &&
        toolCalls.any(_isPostSavedStrategyRunOverrun)) {
      return DomainToolInterception(
        answer: savedRunReadback,
        skippedReason:
            'Skipped: saved custom strategy already has successful custom_strategy_read/run evidence for this turn.',
      );
    }
    if (saveEvidence != null &&
        customStrategyPolicy.shouldStopAfterSave(
          state: workflowState,
          toolCalls: toolCalls,
        )) {
      return DomainToolInterception(
        answer: saveEvidence,
        skippedReason: customStrategyPolicy.saveSkipReason,
      );
    }

    final comparisonEvidence = _customStrategyEvidence.comparison(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (comparisonEvidence != null) {
      return DomainToolInterception(
        answer: comparisonEvidence,
        skippedReason:
            'Skipped: comparable custom_strategy_backtest evidence already exists for the requested strategy comparison.',
      );
    }

    final runComparisonEvidence = _customStrategyEvidence.runComparison(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (runComparisonEvidence != null &&
        _hasCustomStrategySaveOrRunCall(toolCalls)) {
      return DomainToolInterception(
        answer: runComparisonEvidence,
        skippedReason:
            'Skipped: saved custom strategy already has successful custom_strategy_run evidence for multiple symbols in this turn.',
      );
    }

    final saveRunBoundary = _customStrategyEvidence.saveRunBoundary(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (saveRunBoundary != null &&
        customStrategyPolicy.shouldStopAfterSaveRunBoundary(toolCalls)) {
      return DomainToolInterception(
        answer: saveRunBoundary,
        skippedReason:
            'Skipped: saved custom strategy is not runnable without backtested evidence.',
      );
    }

    final backtestEvidence = _customStrategyEvidence.backtest(
      messages,
      turnStartIndex,
    );
    if (backtestEvidence != null &&
        customStrategyPolicy.shouldStopAfterBacktest(
          state: workflowState,
          toolCalls: toolCalls,
        )) {
      return DomainToolInterception(
        answer: backtestEvidence,
        skippedReason: customStrategyPolicy.backtestSkipReason,
      );
    }

    return null;
  }

  String? _etfQuoteOnlyStrategyBoundary({
    required List<Message> messages,
    required int turnStartIndex,
    required List<ToolUse> proposedToolCalls,
  }) {
    final proposedEtfKline = proposedToolCalls.any(_isProposedEtfKlineCall);
    final proposedRankOrBacktest = proposedToolCalls.any((call) {
      if (call.name != 'MarketData') return false;
      final action = '${call.input['action'] ?? ''}';
      return action == 'custom_strategy_rank' ||
          action == 'custom_strategy_backtest';
    });
    if (!proposedEtfKline && !proposedRankOrBacktest) {
      return null;
    }
    final quotes = _latestEtfQuoteRows(messages, turnStartIndex);
    if (quotes.isEmpty || _hasSuccessfulEtfKline(messages, turnStartIndex)) {
      return null;
    }
    final quoteLines = quotes.take(6).map((row) {
      final code = _textValue(row['code'] ?? row['symbol'], '-');
      final name = _textValue(row['name'], code);
      final price = _textValue(row['price'], '-');
      final pct = _textValue(row['changePct'] ?? row['pct_chg'], '-');
      return '| $code | $name | $price | $pct |';
    }).join('\n');
    return [
      '已取得 ETF 场内报价证据，但本轮尚无成功的 ETF 日线 K 线证据；因此已停止后续 ETF K-line / `custom_strategy_rank` / `custom_strategy_backtest` 扩展调用，不把报价快照冒充为可回测排名证据。',
      '',
      '## ETF 轮动观察策略',
      '',
      '- 策略阶段：设计 / 观察，不是已回测排名。',
      '- 调仓依据：未来需要场内日线 K 线的 close、open、high、low、volume 才能计算动量、均线、波动和止损。',
      '- 当前可用证据：场内报价快照，可证明 ETF 使用上市市场价格作为交易基础。',
      '- 当前缺口：未取得 NAV / IOPV，不能验证折溢价；未取得底层指数，不能验证跟踪误差或指数趋势；未取得 ETF K-line，不能排名或回测。',
      '',
      '| 代码 | 名称 | 最新价 | 涨跌幅 |',
      '|---|---|---:|---:|',
      quoteLines,
      '',
      '## 数据口径',
      '',
      '- 场内价格 / Quote：已观察，用于交易价格基础。',
      '- 场内 K-line：本轮缺失，策略排名和回测等待该证据。',
      '- NAV / IOPV：本轮未取，折溢价过滤不能声称已验证。',
      '- 底层指数：本轮未取，指数趋势确认不能声称已验证。',
      '',
      '## 下一步',
      '',
      '- 先修复或补齐 ETF K-line provider/readback，再运行 `custom_strategy_rank`。',
      '- 用户给定 ETF 篮子后，应先读取报价与 K-line；若 K-line 仍缺失，只能输出观察设计和数据缺口。',
    ].join('\n');
  }

  bool _isProposedEtfKlineCall(ToolUse call) {
    if (call.name != 'MarketData') return false;
    final action = '${call.input['action'] ?? ''}';
    if (action != 'kline' && action != 'query_kline') return false;
    final symbols = call.input['symbols'];
    if (symbols is List) {
      return symbols.any((symbol) => _isEtfCode(_textValue(symbol, '')));
    }
    return _isEtfCode(
      _textValue(call.input['symbol'] ?? call.input['code'], ''),
    );
  }

  List<Map<String, dynamic>> _latestEtfQuoteRows(
    List<Message> messages,
    int turnStartIndex,
  ) {
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        final action = '${decoded['action'] ?? ''}';
        if (action != 'quote' &&
            action != 'query_quote' &&
            action != 'query_etf_quote' &&
            action != 'listed_fund_quote') {
          continue;
        }
        final rows = decoded['data'];
        if (rows is! List) continue;
        final mapped = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where((row) => _isEtfCode(_textValue(row['code'] ?? row['symbol'], '')))
            .toList(growable: false);
        if (mapped.isNotEmpty) return mapped;
      } catch (_) {
        continue;
      }
    }
    return const <Map<String, dynamic>>[];
  }

  bool _hasSuccessfulEtfKline(List<Message> messages, int turnStartIndex) {
    for (final message in messages.skip(turnStartIndex)) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is! Map<String, dynamic>) continue;
        final action = '${decoded['action'] ?? ''}';
        if (action != 'kline' && action != 'query_kline') continue;
        final rows = decoded['data'];
        if (rows is! List || rows.isEmpty) continue;
        final symbol = _textValue(
          decoded['symbol'] ?? decoded['code'] ?? rows.first['code'],
          '',
        );
        if (symbol.isEmpty || _isEtfCode(symbol)) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  bool _isEtfCode(String value) {
    final text = value.trim().toUpperCase();
    return RegExp(r'^(51|15|58)\d{4}(\.(SH|SZ))?$').hasMatch(text);
  }

  String _textValue(Object? value, String fallback) {
    final text = '${value ?? ''}'.trim();
    return text.isEmpty ? fallback : text;
  }

  bool _isFundStockDataDrift(ToolUse call) {
    if (call.name != 'MarketData') return false;
    final action = call.input['action']?.toString() ?? '';
    return action == 'query_kline' ||
        action == 'kline' ||
        action == 'backtest' ||
        action == 'backtest_batch' ||
        action == 'custom_strategy_backtest' ||
        action == 'custom_strategy_run';
  }

  @override
  String? rewriteFinalAnswer({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required String answer,
  }) {
    final tradeBudget = _tradeBudgetSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary: '无阻断性工具错误；最终回答由交易测算证据摘要接管，未执行交易工具写操作。',
    );
    if (tradeBudget != null) return tradeBudget;
    final fundMonitor = _fundMonitorSummary.build(
      messages.skip(turnStartIndex).toList(),
    );
    if (fundMonitor != null) return fundMonitor;
    final portfolioMonitor = _portfolioMonitorSummary.build(
      messages.skip(turnStartIndex).toList(),
    );
    if (portfolioMonitor != null) return portfolioMonitor;

    final comparisonEvidence = _customStrategyEvidence.comparison(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (comparisonEvidence != null) return comparisonEvidence;

    final saveEvidence = _customStrategyEvidence.save(messages, turnStartIndex);
    if (saveEvidence != null &&
        _hasPostCustomStrategySaveBlock(messages, turnStartIndex)) {
      return saveEvidence;
    }
    if (_hasSuccessfulCustomStrategyRun(messages, turnStartIndex)) return null;
    return saveEvidence;
  }

  bool _hasCustomStrategySaveOrRunCall(List<ToolUse> toolCalls) {
    return toolCalls.any(
      (toolCall) =>
          toolCall.name == 'MarketData' &&
          (toolCall.input['action'] == 'custom_strategy_save' ||
              toolCall.input['action'] == 'custom_strategy_run'),
    );
  }

  bool _isPostSavedStrategyRunOverrun(ToolUse toolCall) {
    if (toolCall.name == 'MarketData') {
      final action = '${toolCall.input['action'] ?? ''}';
      return action == 'custom_strategy_run' ||
          action == 'custom_strategy_save' ||
          action.startsWith('query_') ||
          action == 'kline' ||
          action == 'quote' ||
          action == 'price' ||
          action == 'technical_indicator';
    }
    return toolCall.name == 'DataProcess' ||
        toolCall.name == 'Read' ||
        toolCall.name == 'Grep' ||
        toolCall.name == 'Glob' ||
        toolCall.name == 'LS' ||
        customStrategyPolicy.isBypassTool(toolCall.name);
  }

  bool _hasPostCustomStrategySaveBlock(List<Message> messages, int start) {
    for (final message in messages.skip(start)) {
      final result = message.toolResult;
      if (result == null || !result.isError) continue;
      if (_isCustomStrategyPostSaveBlock(result.content)) {
        return true;
      }
    }
    return false;
  }

  bool _isCustomStrategyPostSaveBlock(String content) {
    try {
      final decoded = jsonDecode(content.trim());
      return decoded is Map &&
          decoded['action'] == 'finance_turn_policy_block' &&
          decoded['status'] == 'blocked' &&
          decoded['code'] == 'custom_strategy_post_save_drift';
    } catch (_) {
      return false;
    }
  }

  bool _hasSuccessfulCustomStrategyRun(List<Message> messages, int start) {
    for (final message in messages.skip(start)) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content.trim());
        if (decoded is Map && decoded['action'] == 'custom_strategy_run') {
          return true;
        }
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  String? _latestSuccessfulCustomStrategyRunId(
    List<Message> messages,
    int start,
  ) {
    for (final message in messages.skip(start).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      try {
        final decoded = jsonDecode(result.content.trim());
        if (decoded is! Map || decoded['action'] != 'custom_strategy_run') {
          continue;
        }
        final strategyId = '${decoded['strategyId'] ?? ''}'.trim();
        if (strategyId.isNotEmpty && !_isStockCode(strategyId)) {
          return strategyId;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  bool _isStockCode(String value) {
    return RegExp(r'^[036]\d{5}$').hasMatch(value.trim());
  }

  String _firstSymbolFromInput(Map<String, dynamic> input) {
    final symbols = input['symbols'];
    if (symbols is List && symbols.isNotEmpty) {
      return '${symbols.first}'.trim();
    }
    return '${input['symbol'] ?? input['code'] ?? ''}'.trim();
  }

  String? _firstProposedSavedStrategyRunId(List<ToolUse> toolCalls) {
    for (final call in toolCalls) {
      if (call.name != 'MarketData' ||
          call.input['action'] != 'custom_strategy_run') {
        continue;
      }
      final strategyId = '${call.input['strategyId'] ?? ''}'.trim();
      if (strategyId.isNotEmpty && !_isStockCode(strategyId)) {
        return strategyId;
      }
    }
    return null;
  }

  @override
  String buildBudgetStopText({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required String failureSummary,
  }) {
    final fundWatch = _fundWatchSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary: failureSummary,
    );
    if (fundWatch != null) return fundWatch;
    final fundCandidates = _fundCandidateSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary: failureSummary,
    );
    if (fundCandidates != null) return fundCandidates;
    final stockCandidates = _stockCandidateSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary: failureSummary,
    );
    if (stockCandidates != null) return stockCandidates;
    final marketOverview = _marketOverviewSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary: failureSummary,
    );
    if (marketOverview != null) return marketOverview;
    final strategyComparison = _strategyBudgetSummary.buildComparison(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (strategyComparison != null) return strategyComparison;
    final customStrategySaveRun = _customStrategyEvidence.saveRunBoundary(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (customStrategySaveRun != null) return customStrategySaveRun;
    final customStrategyComparison = _customStrategyEvidence.comparison(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (customStrategyComparison != null) return customStrategyComparison;
    final portfolioRank = _customStrategyEvidence.portfolioRank(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (portfolioRank != null) return portfolioRank;
    final optimized = _strategyBudgetSummary.buildOptimize(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (optimized != null) return optimized;
    final tradeBudget = _tradeBudgetSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary: failureSummary,
    );
    if (tradeBudget != null) return tradeBudget;
    final fundMonitor = _fundMonitorSummary.build(
      messages.skip(turnStartIndex).toList(),
    );
    if (fundMonitor != null) return fundMonitor;
    final portfolioMonitor = _portfolioMonitorSummary.build(
      messages.skip(turnStartIndex).toList(),
    );
    if (portfolioMonitor != null) return portfolioMonitor;
    return 'Stopped: this turn reached the bounded finance data workflow budget. '
        'No further provider/file/script calls were executed. Use the tool evidence above, or ask a narrower follow-up.';
  }

  @override
  Future<String?> buildRecovery({
    required String? prompt,
    required List<Message> messages,
    required Tool? Function(String name) toolByName,
    required DomainRecoveryToolCall callTool,
  }) async {
    final stockWatch = await _stockWatchRecovery.build(
      messages: messages,
      toolByName: toolByName,
      callTool: callTool,
    );
    if (stockWatch != null) return stockWatch;
    return _strategyMonitorRecovery.build(
      prompt: prompt,
      messages: messages,
      toolByName: toolByName,
      callTool: callTool,
    );
  }
}
