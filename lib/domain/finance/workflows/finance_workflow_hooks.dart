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
import 'finance_macro_evidence_summary.dart';
import 'finance_market_overview_summary.dart';
import 'finance_portfolio_monitor_summary.dart';
import 'finance_preset_backtest_evidence_summary.dart';
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
  final FinanceMacroEvidenceSummary _macroEvidenceSummary =
      FinanceMacroEvidenceSummary();
  final FinanceMarketOverviewSummary _marketOverviewSummary =
      FinanceMarketOverviewSummary();
  final FinancePortfolioMonitorSummary _portfolioMonitorSummary =
      FinancePortfolioMonitorSummary();
  final FinancePresetBacktestEvidenceSummary _presetBacktestEvidenceSummary =
      FinancePresetBacktestEvidenceSummary();
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
    return _buildMacroConditionWatchlistPreflightToolCalls(messages) ??
        _buildMacroStockQuotePreflightToolCalls(messages) ??
        _buildFundMonitorReviewPreflightToolCalls(messages) ??
        _buildPortfolioMonitorReviewPreflightToolCalls(messages) ??
        _buildPortfolioMonitorCreateAfterRankPreflightToolCalls(messages) ??
        _buildPortfolioRankAfterSelectionPreflightToolCalls(messages) ??
        _buildPortfolioStrategySelectionPreflightToolCalls(messages) ??
        _buildFundStrategyPreflightToolCalls(messages) ??
        _evidenceReviewSummary.buildSearchToolCalls(messages) ??
        _tradeSizingPreflight.buildToolCalls(messages) ??
        _customStrategyPreflight.buildToolCalls(messages);
  }

  List<ToolUse>? _buildMacroStockQuotePreflightToolCalls(
    List<Message> messages,
  ) {
    final start = _lastUserIndex(messages);
    if (start < 0) return null;
    final turnMessages = messages.sublist(start);
    final searchTerm = _latestMacroStockSubject(turnMessages);
    if (searchTerm == null ||
        _hasMacroStockQuoteEvidence(turnMessages, searchTerm) ||
        _hasStockIdentitySearch(turnMessages, searchTerm)) {
      return null;
    }
    return [
      ToolUse(
        id: 'auto_macro_stock_identity_${DateTime.now().microsecondsSinceEpoch}',
        name: 'MarketData',
        input: {
          'action': 'query_stock_list',
          'keyword': searchTerm,
          'limit': 5,
        },
      ),
    ];
  }

  List<ToolUse>? _buildPortfolioRankAfterSelectionPreflightToolCalls(
    List<Message> messages,
  ) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final turnMessages = messages.skip(start + 1).toList(growable: false);
    if (_hasToolCallAction(
      turnMessages,
      'MarketData',
      'custom_strategy_rank',
    )) {
      return null;
    }
    final selectedStrategyId = _selectedPortfolioStrategyId(turnMessages);
    if (selectedStrategyId == null) return null;
    return [
      ToolUse(
        id: 'portfolio_strategy_rank_${DateTime.now().microsecondsSinceEpoch}',
        name: 'MarketData',
        input: {
          'action': 'custom_strategy_rank',
          'strategyId': selectedStrategyId,
          'topN': 3,
          'maxPositionWeight': 0.35,
          'rebalanceInterval': 'weekly',
        },
      ),
    ];
  }

  List<ToolUse>? _buildPortfolioMonitorCreateAfterRankPreflightToolCalls(
    List<Message> messages,
  ) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final turnMessages = messages.skip(start + 1).toList(growable: false);
    if (turnMessages.any(
      (message) => (message.toolUses ?? const <ToolUse>[]).any(
        (call) => call.name == 'MonitorCreate',
      ),
    )) {
      return null;
    }
    final rank = _latestPortfolioRankPayload(turnMessages);
    if (rank == null) return null;
    final portfolioEvidence = _mapValue(rank['portfolioEvidence']);
    final rebalanceDraft = _mapValue(rank['rebalanceDraft']);
    if (portfolioEvidence == null || rebalanceDraft == null) return null;
    final strategyId = _textValue(rank['strategyId'], 'portfolio_rank_v1');
    return [
      ToolUse(
        id: 'portfolio_monitor_create_${DateTime.now().microsecondsSinceEpoch}',
        name: 'MonitorCreate',
        input: {
          'name': '$strategyId 组合再平衡复核',
          'template': 'portfolio_rebalance_monitor',
          'strategyId': strategyId,
          'portfolioEvidence': portfolioEvidence,
          'rebalanceDraft': rebalanceDraft,
          'interval': '1d',
          'display': 'status_row',
          'user_prompt': 'portfolio rebalance monitor review',
          'description':
              'Review-only portfolio rebalance monitor generated from custom_strategy_rank evidence. It does not place Portfolio, XueqiuTrade, broker, or transfer orders.',
        },
      ),
    ];
  }

  Map<String, dynamic>? _latestPortfolioRankPayload(List<Message> messages) {
    final rankIds = <String>{};
    for (final message in messages) {
      for (final use in message.toolUses ?? const <ToolUse>[]) {
        if (use.name == 'MarketData' &&
            use.input['action'] == 'custom_strategy_rank') {
          rankIds.add(use.id);
        }
      }
    }
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null ||
          result.isError ||
          !rankIds.contains(result.toolUseId)) {
        continue;
      }
      try {
        final decoded = jsonDecode(result.content);
        if (decoded is Map<String, dynamic> &&
            decoded['action'] == 'custom_strategy_rank') {
          return decoded;
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  String? _selectedPortfolioStrategyId(List<Message> messages) {
    final candidates = _portfolioStrategyCandidates(
      messages,
    ).map((candidate) => candidate['strategyId']).whereType<String>().toSet();
    if (candidates.isEmpty) return null;
    final answers = _latestAskUserQuestionStructuredAnswers(messages);
    if (answers.isEmpty) return null;
    final structured = _mapValue(answers.first['structuredAnswer']);
    final rawLabel =
        '${structured?['selectedOptionLabel'] ?? answers.first['selectedOptionLabel'] ?? answers.first['answer'] ?? ''}'
            .trim();
    if (rawLabel.isEmpty) return null;
    final normalized = rawLabel.startsWith('使用 ')
        ? rawLabel.substring('使用 '.length).trim()
        : rawLabel;
    if (candidates.contains(normalized)) return normalized;
    return null;
  }

  List<Map<String, dynamic>> _latestAskUserQuestionStructuredAnswers(
    List<Message> messages,
  ) {
    final askIds = <String>{};
    for (final message in messages) {
      for (final use in message.toolUses ?? const <ToolUse>[]) {
        if (use.name == 'AskUserQuestion') askIds.add(use.id);
      }
    }
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null ||
          result.isError ||
          !askIds.contains(result.toolUseId)) {
        continue;
      }
      for (final line in result.content.split(RegExp(r'\r?\n'))) {
        final text = line.trim();
        if (!text.startsWith('askUserQuestion:')) continue;
        try {
          final decoded = jsonDecode(text.substring('askUserQuestion:'.length));
          if (decoded is! Map<String, dynamic>) continue;
          final rows = decoded['answers'];
          if (rows is! List) continue;
          return rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList(growable: false);
        } catch (_) {
          continue;
        }
      }
    }
    return const [];
  }

  List<ToolUse>? _buildPortfolioStrategySelectionPreflightToolCalls(
    List<Message> messages,
  ) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final turnMessages = messages.skip(start + 1).toList(growable: false);
    if (_hasAnsweredAskUserQuestion(turnMessages)) return null;
    if (turnMessages.any(
      (message) => (message.toolUses ?? const <ToolUse>[]).any(
        (call) =>
            call.name == 'AskUserQuestion' || call.name == 'MonitorCreate',
      ),
    )) {
      return null;
    }
    if (!_hasSuccessfulToolResult(turnMessages, 'MonitorList') ||
        !_hasSuccessfulToolResult(turnMessages, 'Portfolio')) {
      return null;
    }
    final candidates = _portfolioStrategyCandidates(turnMessages);
    if (candidates.isEmpty) return null;
    return [
      ToolUse(
        id: 'portfolio_strategy_selection_${DateTime.now().microsecondsSinceEpoch}',
        name: 'AskUserQuestion',
        input: {
          'questions': [
            {
              'question': '请选择本轮组合再平衡监控要绑定的策略。',
              'header': '策略选择',
              'multiSelect': false,
              'options': candidates
                  .take(3)
                  .map(
                    (candidate) => {
                      'label': '使用 ${candidate['strategyId']}',
                      'description':
                          '${candidate['name']}；标的 ${candidate['symbols']}; 选择后继续生成只复核、不自动交易的组合再平衡监控。',
                    },
                  )
                  .toList(growable: false),
            },
          ],
        },
      ),
    ];
  }

  bool _hasSuccessfulToolResult(List<Message> messages, String toolName) {
    final ids = <String>{};
    for (final message in messages) {
      for (final use in message.toolUses ?? const <ToolUse>[]) {
        if (use.name == toolName) ids.add(use.id);
      }
    }
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError || !ids.contains(result.toolUseId)) {
        continue;
      }
      return true;
    }
    return false;
  }

  List<Map<String, String>> _portfolioStrategyCandidates(
    List<Message> messages,
  ) {
    final marketDataIds = <String>{};
    for (final message in messages) {
      for (final use in message.toolUses ?? const <ToolUse>[]) {
        if (use.name == 'MarketData' &&
            use.input['action'] == 'custom_strategy_list') {
          marketDataIds.add(use.id);
        }
      }
    }
    final candidates = <Map<String, String>>[];
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null ||
          result.isError ||
          !marketDataIds.contains(result.toolUseId)) {
        continue;
      }
      final content = result.content.trim();
      if (!content.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) continue;
        final rows = decoded['runnableStrategies'];
        if (rows is! List) continue;
        for (final row in rows) {
          if (row is! Map) continue;
          final map = Map<String, dynamic>.from(row);
          final id = _textValue(map['strategyId'], '');
          if (id.isEmpty) continue;
          final symbols = _listValue(map['symbols'])
              .map((value) => '$value'.trim())
              .where((value) => value.isNotEmpty)
              .toList(growable: false);
          if (symbols.length < 2) continue;
          candidates.add({
            'strategyId': id,
            'name': _textValue(map['name'], id),
            'symbols': symbols.join('/'),
          });
        }
      } catch (_) {
        continue;
      }
      if (candidates.isNotEmpty) return candidates;
    }
    return candidates;
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

  bool _isMonitorReviewState(FinanceWorkflowState? state) {
    return state?.workflowKind == FinanceWorkflowKind.monitorReview;
  }

  @override
  List<ToolUse> rewriteToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  }) {
    final workflowState = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
    if (_isMonitorReviewState(workflowState)) {
      toolCalls = _rewriteMonitorReviewToolCalls(toolCalls);
    }
    final macroConditionPreviewReadback =
        _macroConditionWatchlistPreviewReadbackCalls(
          messages,
          turnStartIndex,
          toolCalls,
        );
    if (macroConditionPreviewReadback != null) {
      return macroConditionPreviewReadback;
    }
    final macroConditionReadback = _macroConditionWatchlistReadbackCalls(
      messages,
      turnStartIndex,
      toolCalls,
    );
    if (macroConditionReadback != null) {
      return macroConditionReadback;
    }
    toolCalls =
        _completeMacroEvidenceToolCalls(
          messages: messages,
          proposedToolCalls: toolCalls,
        ) ??
        toolCalls;
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

  List<ToolUse> _rewriteMonitorReviewToolCalls(List<ToolUse> toolCalls) {
    var changed = false;
    final rewritten = <ToolUse>[];
    final seenMonitorCreateKeys = <String>{};
    for (final call in toolCalls) {
      if (_isMonitorReviewBlockedTool(call.name)) {
        changed = true;
        continue;
      }
      if (call.name == 'MonitorCreate') {
        final key = _monitorCreateKey(call.input);
        if (!seenMonitorCreateKeys.add(key)) {
          changed = true;
          continue;
        }
      }
      rewritten.add(call);
    }
    return changed ? rewritten : toolCalls;
  }

  bool _isMonitorReviewBlockedTool(String name) {
    return name == 'Read' ||
        name == 'Grep' ||
        name == 'Glob' ||
        name == 'LS' ||
        name == 'Write' ||
        name == 'FileWrite' ||
        name == 'Edit' ||
        name == 'EnterPlanMode' ||
        name == 'ExitPlanMode';
  }

  String _monitorCreateKey(Map<String, dynamic> input) {
    final template = _textValue(input['template'], '');
    final strategyId = _textValue(input['strategyId'], '');
    final name = _textValue(input['name'], '');
    if (template.isNotEmpty || strategyId.isNotEmpty) {
      return '$template::$strategyId::$name';
    }
    return name;
  }

  @override
  DomainToolInterception? interceptToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  }) {
    final macroExternalFallback = _macroExternalFallbackAnswer(
      messages: messages,
      turnStartIndex: turnStartIndex,
      proposedToolCalls: toolCalls,
    );
    if (macroExternalFallback != null) {
      return DomainToolInterception(
        answer: macroExternalFallback,
        skippedReason:
            'Skipped: governed macro evidence exists; first-pass macro workflow must answer before generic search or web fetch fallback.',
      );
    }

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

    final monitorCreateSummary = _monitorCreateOverrunSummary(
      messages: messages,
      turnStartIndex: turnStartIndex,
      proposedToolCalls: toolCalls,
    );
    if (monitorCreateSummary != null) {
      return DomainToolInterception(
        answer: monitorCreateSummary,
        skippedReason:
            'Skipped: monitor evidence already has successful MonitorCreate/readback in this turn; no repeated MonitorCreate, file, or indicator drift is needed.',
      );
    }

    final monitorStrategyReadback = _monitorStrategyReadbackBoundary(
      messages: messages,
      turnStartIndex: turnStartIndex,
      proposedToolCalls: toolCalls,
    );
    if (monitorStrategyReadback != null) {
      return DomainToolInterception(
        answer: monitorStrategyReadback,
        skippedReason:
            'Skipped: requested strategyId is a monitor artifact from MonitorList, not a saved custom StrategySpec; use monitor readback evidence instead of custom_strategy_read.',
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

  List<ToolUse>? _macroConditionWatchlistReadbackCalls(
    List<Message> messages,
    int turnStartIndex,
    List<ToolUse> proposedToolCalls,
  ) {
    final turnMessages = messages.sublist(turnStartIndex);
    final proposedMacroWrites = proposedToolCalls
        .where(
          (call) =>
              call.name == 'Watchlist' &&
              call.input['action'] == 'add' &&
              call.input['type'] == 'macro-condition',
        )
        .toList(growable: false);
    final proposedMacroReadback = proposedToolCalls.any(
      (call) =>
          call.name == 'Watchlist' &&
          call.input['action'] == 'list' &&
          (call.input['type'] == 'macro-condition' ||
              call.input['groupType'] == 'macro-condition'),
    );
    if (proposedMacroWrites.isNotEmpty && !proposedMacroReadback) {
      return [...proposedMacroWrites, _macroConditionWatchlistReadbackCall()];
    }
    final executedIds = _executedToolUseIds(turnMessages);
    final hasMacroConditionWrite = turnMessages.any((message) {
      final uses = message.toolUses;
      if (uses == null) return false;
      return uses.any((call) {
        if (call.name != 'Watchlist' || !executedIds.contains(call.id)) {
          return false;
        }
        return call.input['action'] == 'add' &&
            call.input['type'] == 'macro-condition';
      });
    });
    if (!hasMacroConditionWrite) return null;
    final priorCalls = turnMessages.expand((message) => message.toolUses ?? []);
    final hasMacroConditionReadback = [...priorCalls, ...proposedToolCalls].any(
      (call) =>
          call.name == 'Watchlist' &&
          call.input['action'] == 'list' &&
          (call.input['type'] == 'macro-condition' ||
              call.input['groupType'] == 'macro-condition'),
    );
    if (hasMacroConditionReadback) return null;
    return [_macroConditionWatchlistReadbackCall()];
  }

  List<ToolUse>? _macroConditionWatchlistPreviewReadbackCalls(
    List<Message> messages,
    int turnStartIndex,
    List<ToolUse> proposedToolCalls,
  ) {
    final state = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
    if (!_isMacroConditionWatchlistWorkflow(state) ||
        state?.executionMode != FinanceExecutionMode.previewOnly) {
      return null;
    }
    final hasWatchlistMutation = proposedToolCalls.any((call) {
      if (call.name != 'Watchlist') return false;
      final action = '${call.input['action'] ?? ''}';
      return action != 'list' &&
          action != 'help' &&
          action != 'summary' &&
          action != 'list_groups';
    });
    if (!hasWatchlistMutation) return null;
    return [_macroConditionWatchlistReadbackCall()];
  }

  List<ToolUse>? _buildMacroConditionWatchlistPreflightToolCalls(
    List<Message> messages,
  ) {
    final start = _lastUserIndex(messages);
    if (start < 0) return null;
    final state = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: start,
    );
    if (!_isMacroConditionWatchlistWorkflow(state)) return null;
    final macroEvidenceReadbacks = _requiredMacroEvidenceReadbackCalls(
      messages.sublist(start),
      'MarketData',
    );
    if (macroEvidenceReadbacks.isNotEmpty) return macroEvidenceReadbacks;
    if (!_hasPendingMacroConditionWatchlistWorkflow(
      messages.sublist(start),
      state,
    )) {
      return null;
    }
    return [_macroConditionWatchlistReadbackCall()];
  }

  ToolUse _macroConditionWatchlistReadbackCall() {
    return ToolUse(
      id: 'auto_macro_condition_watchlist_readback_${DateTime.now().microsecondsSinceEpoch}',
      name: 'Watchlist',
      input: {
        'action': 'list',
        'type': 'macro-condition',
        'status': 'watching',
      },
    );
  }

  bool _hasPendingMacroConditionWatchlistWorkflow(
    List<Message> turnMessages,
    FinanceWorkflowState? state,
  ) {
    if (!_isMacroConditionWatchlistWorkflow(state)) return false;
    final executedIds = _executedToolUseIds(turnMessages);
    final hasMacroConditionReadback = turnMessages.any((message) {
      final uses = message.toolUses;
      if (uses == null) return false;
      return uses.any((call) {
        if (call.name != 'Watchlist' || !executedIds.contains(call.id)) {
          return false;
        }
        return call.input['action'] == 'list' &&
            (call.input['type'] == 'macro-condition' ||
                call.input['groupType'] == 'macro-condition');
      });
    });
    return !hasMacroConditionReadback;
  }

  bool _isMacroConditionWatchlistWorkflow(FinanceWorkflowState? state) {
    return state?.workflowKind == FinanceWorkflowKind.monitorReview &&
        state?.intentMode == FinanceIntentMode.observe &&
        state?.evidenceRefs.contains('macro-condition-watchlist') == true;
  }

  List<ToolUse> _requiredMacroEvidenceReadbackCalls(
    List<Message> turnMessages,
    String toolName,
  ) {
    final actions = _executedToolCalls(turnMessages)
        .where((call) => call.name == 'MarketData' || call.name == 'DataStore')
        .map((call) => '${call.input['action'] ?? ''}')
        .toSet();
    const target = 'A-shares';
    return [
      if (!actions.contains('query_macro_factors'))
        ToolUse(
          id: 'auto_macro_condition_factors_${DateTime.now().microsecondsSinceEpoch}',
          name: toolName,
          input: {
            'action': 'query_macro_factors',
            'target': target,
            'limit': 10,
          },
        ),
      if (!actions.contains('query_macro_attribution'))
        ToolUse(
          id: 'auto_macro_condition_attribution_${DateTime.now().microsecondsSinceEpoch}',
          name: toolName,
          input: {
            'action': 'query_macro_attribution',
            'target': target,
            'limit': 10,
          },
        ),
      if (!actions.contains('query_finance_news'))
        ToolUse(
          id: 'auto_macro_condition_news_${DateTime.now().microsecondsSinceEpoch}',
          name: toolName,
          input: {'action': 'query_finance_news', 'query': target, 'limit': 10},
        ),
    ];
  }

  String? _macroExternalFallbackAnswer({
    required List<Message> messages,
    required int turnStartIndex,
    required List<ToolUse> proposedToolCalls,
  }) {
    final wantsGenericExternalFallback = proposedToolCalls.any(
      (call) => call.name == 'Research' || call.name == 'WebFetch',
    );
    if (!wantsGenericExternalFallback) return null;
    return _macroEvidenceSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary:
          '模型尝试追加通用 Research/WebFetch，但本轮已经有受治理宏观 evidence/readback；first-pass attribution 必须先基于这些证据完成。',
      suffix:
          '如果用户明确要求更新来源或验证网页可达性，再进入 macro_research_sources / macro_research_extract / source validation workflow。',
    );
  }

  List<ToolUse>? _completeMacroEvidenceToolCalls({
    required List<Message> messages,
    required List<ToolUse> proposedToolCalls,
  }) {
    final macroCalls = proposedToolCalls
        .where(
          (call) =>
              (call.name == 'MarketData' || call.name == 'DataStore') &&
              _textValue(call.input['action'], '').contains('macro'),
        )
        .toList(growable: false);
    final priorCalls = _executedToolCalls(messages)
        .where((call) => call.name == 'MarketData' || call.name == 'DataStore')
        .toList(growable: false);
    final priorMacroCalls = priorCalls
        .where((call) => _textValue(call.input['action'], '').contains('macro'))
        .toList(growable: false);
    if (macroCalls.isEmpty && priorMacroCalls.isEmpty) return null;
    final combinedCalls = [...priorCalls, ...proposedToolCalls];
    bool hasAction(String action) => combinedCalls.any(
      (call) =>
          (call.name == 'MarketData' || call.name == 'DataStore') &&
          call.input['action'] == action,
    );
    final hasMacroSourceCatalog = combinedCalls.any(
      (call) =>
          (call.name == 'MarketData' || call.name == 'DataStore') &&
          call.input['action'] == 'macro_research_sources',
    );
    final proposedFinanceNewsRefresh = proposedToolCalls.any(
      (call) =>
          (call.name == 'MarketData' || call.name == 'DataStore') &&
          call.input['action'] == 'finance_news',
    );
    final priorFinanceNewsRefreshFailed = _hasFailedFinanceNewsRefresh(
      messages,
    );
    final attributionBaseCalls = macroCalls.isNotEmpty
        ? macroCalls
        : priorMacroCalls;
    final target = attributionBaseCalls
        .map(
          (call) => _textValue(call.input['target'] ?? call.input['query'], ''),
        )
        .firstWhere((value) => value.isNotEmpty, orElse: () => 'A-shares');
    final toolName = attributionBaseCalls.first.name;
    final additions = <ToolUse>[];
    if (!hasAction('query_macro_factors')) {
      additions.add(
        ToolUse(
          id: 'auto_macro_factors_${DateTime.now().microsecondsSinceEpoch}',
          name: toolName,
          input: {
            'action': 'query_macro_factors',
            'target': target,
            'limit': 10,
          },
        ),
      );
    }
    if (!hasAction('query_macro_attribution')) {
      additions.add(
        ToolUse(
          id: 'auto_macro_attribution_${DateTime.now().microsecondsSinceEpoch}',
          name: toolName,
          input: {
            'action': 'query_macro_attribution',
            'target': target,
            'limit': 10,
          },
        ),
      );
    }
    if (hasMacroSourceCatalog && !hasAction('query_macro_research_evidence')) {
      additions.add(
        ToolUse(
          id: 'auto_macro_research_evidence_${DateTime.now().microsecondsSinceEpoch}',
          name: toolName,
          input: {
            'action': 'query_macro_research_evidence',
            'target': target,
            'limit': 10,
          },
        ),
      );
    }
    if (!hasAction('query_finance_news') ||
        proposedFinanceNewsRefresh ||
        priorFinanceNewsRefreshFailed) {
      additions.add(
        ToolUse(
          id: 'auto_macro_finance_news_${DateTime.now().microsecondsSinceEpoch}',
          name: toolName,
          input: {'action': 'query_finance_news', 'query': target, 'limit': 10},
        ),
      );
    }
    if (additions.isEmpty) return null;
    final shouldSuppressGenericExternal = proposedToolCalls.any(
      (call) => call.name == 'Research' || call.name == 'WebFetch',
    );
    final hasAddedNewsRefresh = additions.any(
      (call) => call.input['action'] == 'finance_news',
    );
    final sanitizedProposedToolCalls = proposedToolCalls
        .where(
          (call) =>
              !_isKnownInvalidCodeRequiredReadback(call) &&
              call.input['action'] != 'finance_news',
        )
        .toList(growable: false);
    final retainedCalls = shouldSuppressGenericExternal
        ? const <ToolUse>[]
        : hasAddedNewsRefresh
        ? sanitizedProposedToolCalls
              .where((call) => call.input['action'] != 'query_finance_news')
              .toList(growable: false)
        : sanitizedProposedToolCalls;
    final deferredReadbacks = shouldSuppressGenericExternal
        ? const <ToolUse>[]
        : hasAddedNewsRefresh
        ? sanitizedProposedToolCalls
              .where((call) => call.input['action'] == 'query_finance_news')
              .toList(growable: false)
        : const <ToolUse>[];
    return [
      ..._cloneInterceptedToolCalls(retainedCalls),
      ...additions,
      ..._cloneInterceptedToolCalls(deferredReadbacks),
    ];
  }

  bool _hasFailedFinanceNewsRefresh(List<Message> messages) {
    final start = _lastUserIndex(messages);
    final turnMessages = start >= 0 ? messages.sublist(start) : messages;
    final failedIds = <String>{};
    for (final message in turnMessages) {
      final result = message.toolResult;
      if (result != null && result.isError) failedIds.add(result.toolUseId);
    }
    var hasError = false;
    for (final message in turnMessages) {
      final result = message.toolResult;
      if (result == null || !result.isError) continue;
      hasError = true;
      final content = result.content.toLowerCase();
      if (content.contains('finance_news failed') ||
          content.contains(
            'all finance news feed interface providers failed',
          ) ||
          content.contains('source-health:empty-result')) {
        return true;
      }
    }
    if (!hasError) return false;
    for (final message in turnMessages) {
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        if (failedIds.contains(call.id) &&
            (call.name == 'MarketData' || call.name == 'DataStore') &&
            call.input['action'] == 'finance_news') {
          return true;
        }
      }
    }
    return false;
  }

  bool _isKnownInvalidCodeRequiredReadback(ToolUse call) {
    if (call.name != 'MarketData' && call.name != 'DataStore') return false;
    final action = _textValue(call.input['action'], '');
    final symbol = _textValue(
      call.input['code'] ??
          call.input['symbol'] ??
          call.input['indexCode'] ??
          call.input['fundCode'] ??
          _firstString(call.input['codes']) ??
          _firstString(call.input['symbols']),
      '',
    );
    return symbol.isEmpty && _symbolRequiredReadbackActions.contains(action);
  }

  static const Set<String> _symbolRequiredReadbackActions = {
    'query_fundamental',
    'query_index_fundamentals',
    'query_kline',
    'query_quote',
    'query_stock_fundamentals',
  };

  String? _firstString(Object? value) {
    if (value is List && value.isNotEmpty) {
      final first = value.first;
      if (first is String && first.trim().isNotEmpty) return first.trim();
    }
    return null;
  }

  List<ToolUse> _cloneInterceptedToolCalls(List<ToolUse> calls) {
    return [
      for (var index = 0; index < calls.length; index++)
        ToolUse(
          id: 'auto_retained_${DateTime.now().microsecondsSinceEpoch}_${index}_${calls[index].id}',
          name: calls[index].name,
          input: Map<String, dynamic>.from(calls[index].input),
        ),
    ];
  }

  String? _monitorStrategyReadbackBoundary({
    required List<Message> messages,
    required int turnStartIndex,
    required List<ToolUse> proposedToolCalls,
  }) {
    final strategyIds = proposedToolCalls
        .where(
          (call) =>
              call.name == 'MarketData' &&
              call.input['action'] == 'custom_strategy_read',
        )
        .map((call) => '${call.input['strategyId'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    if (strategyIds.isEmpty) return null;
    for (final strategyId in strategyIds) {
      final monitor = _latestPortfolioMonitorRecord(
        messages,
        turnStartIndex,
        strategyId,
      );
      if (monitor == null) continue;
      final evidence = _mapValue(monitor['portfolioEvidence']);
      final draft = _mapValue(monitor['rebalanceDraft']);
      final positions = _listValue(draft?['positions']);
      final symbols = positions
          .whereType<Map>()
          .map((row) => _textValue(row['symbol'], ''))
          .where((symbol) => symbol.isNotEmpty)
          .toList(growable: false);
      final weights = positions
          .whereType<Map>()
          .map((row) {
            final symbol = _textValue(row['symbol'], '-');
            final weight = _textValue(row['targetWeight'], '-');
            return '- $symbol：目标权重 $weight';
          })
          .join('\n');
      return [
        '已从 `MonitorList` 读回组合再平衡监控；`$strategyId` 是 monitor artifact 的 strategyId，不是已保存 `custom_strategy_read` StrategySpec，因此已停止错误的 `custom_strategy_read` 调用。',
        '',
        '## 监控读回',
        '',
        '- monitorId：${_textValue(monitor['id'], '-')}。',
        '- 名称：${_textValue(monitor['name'], '-')}。',
        '- 模板：portfolio_rebalance_monitor。',
        '- 状态：${monitor['enabled'] == true ? 'enabled' : 'disabled'}。',
        '- 周期：${_textValue(monitor['intervalMinutes'], '-')} 分钟。',
        '- strategyId：$strategyId。',
        if (symbols.isNotEmpty) '- 标的：${symbols.join('、')}。',
        '- 组合证据：mode=${_textValue(evidence?['mode'] ?? evidence?['tradeBoundary'], 'monitor-readback')}；selectedCount=${_textValue(evidence?['selectedCount'], '-')}。',
        '- 再平衡草案：mode=${_textValue(draft?['mode'] ?? draft?['tradeBoundary'], 'review_only')}；rebalanceInterval=${_textValue(draft?['rebalanceInterval'], '-')}；maxPositionWeight=${_textValue(draft?['maxPositionWeight'], '-')}。',
        if (weights.isNotEmpty) '',
        if (weights.isNotEmpty) '## 目标权重草案',
        if (weights.isNotEmpty) '',
        if (weights.isNotEmpty) weights,
        '',
        '## 复核边界',
        '',
        '- 本轮只确认已有 portfolio_rebalance_monitor 的规则与复核数据。',
        '- 未执行 Portfolio / XueqiuTrade / broker 下单。',
        '- 若需要新建或重算组合，应先通过 `custom_strategy_rank` 生成新的 `portfolioEvidence` 和 `rebalanceDraft`，再调用 `MonitorCreate(template:"portfolio_rebalance_monitor")`。',
      ].join('\n');
    }
    return null;
  }

  Map<String, dynamic>? _latestPortfolioMonitorRecord(
    List<Message> messages,
    int turnStartIndex,
    String strategyId,
  ) {
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final marker = result.content.lastIndexOf('monitorList:');
      if (marker < 0) continue;
      final payload = result.content.substring(marker + 'monitorList:'.length);
      try {
        final decoded = jsonDecode(payload);
        if (decoded is! Map<String, dynamic>) continue;
        final monitors = decoded['monitors'];
        if (monitors is! List) continue;
        for (final item in monitors) {
          if (item is! Map) continue;
          final record = Map<String, dynamic>.from(item);
          if (_textValue(record['strategyId'], '') != strategyId) continue;
          final template = _textValue(record['template'], '');
          if (template == 'portfolio_rebalance_monitor' ||
              record['portfolioEvidence'] is Map ||
              record['rebalanceDraft'] is Map) {
            return record;
          }
        }
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  Map<String, dynamic>? _mapValue(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  List<dynamic> _listValue(Object? value) {
    return value is List ? value : const [];
  }

  String? _monitorCreateOverrunSummary({
    required List<Message> messages,
    required int turnStartIndex,
    required List<ToolUse> proposedToolCalls,
  }) {
    if (!proposedToolCalls.any(
      (call) =>
          call.name == 'MonitorCreate' ||
          call.name == 'Read' ||
          call.name == 'Grep' ||
          call.name == 'Glob' ||
          call.name == 'LS' ||
          call.name == 'DataProcess',
    )) {
      return null;
    }
    final created = _successfulMonitorCreateResults(messages, turnStartIndex);
    if (created.isEmpty) return null;
    final first = created.first;
    return [
      '已创建监控并停止后续重复创建、文件读取或指标漂移调用。本回答只基于本轮 `MonitorCreate` / monitor readback 证据。',
      '',
      '## 创建结果',
      '',
      '- ${first.split('\n').first}',
      if (created.length > 1)
        '- 本轮已有 ${created.length} 条 MonitorCreate 成功记录；后续重复创建已停止。',
      '',
      '## 边界',
      '',
      '- 监控用于观察/复核，不自动调仓。',
      '- 未执行 Portfolio 交易、XueqiuTrade、broker order 或转账。',
      '- 后续如需修改规则，应基于已有 monitorId 或 `MonitorList` readback 做显式更新，不重复创建同类监控。',
    ].join('\n');
  }

  List<String> _successfulMonitorCreateResults(
    List<Message> messages,
    int turnStartIndex,
  ) {
    final createIds = <String>{};
    for (final message in messages.skip(turnStartIndex)) {
      for (final use in message.toolUses ?? const <ToolUse>[]) {
        if (use.name == 'MonitorCreate') createIds.add(use.id);
      }
    }
    final results = <String>[];
    for (final message in messages.skip(turnStartIndex)) {
      final result = message.toolResult;
      if (result == null ||
          result.isError ||
          !createIds.contains(result.toolUseId)) {
        continue;
      }
      results.add(result.content.trim());
    }
    return results;
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
    final quoteLines = quotes
        .take(6)
        .map((row) {
          final code = _textValue(row['code'] ?? row['symbol'], '-');
          final name = _textValue(row['name'], code);
          final price = _textValue(row['price'], '-');
          final pct = _textValue(row['changePct'] ?? row['pct_chg'], '-');
          return '| $code | $name | $price | $pct |';
        })
        .join('\n');
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

  List<ToolUse> _executedToolCalls(List<Message> messages) {
    final executedIds = _executedToolUseIds(messages);
    return messages
        .expand((message) => message.toolUses ?? const <ToolUse>[])
        .where((call) => executedIds.contains(call.id))
        .toList(growable: false);
  }

  Set<String> _executedToolUseIds(List<Message> messages) {
    final ids = <String>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      if (result.content.trimLeft().startsWith('Skipped:')) continue;
      ids.add(result.toolUseId);
    }
    return ids;
  }

  bool _hasPendingWatchlistStateWorkflow(List<Message> turnMessages) {
    final loadedWatchlistSkill = turnMessages.any((message) {
      final uses = message.toolUses;
      if (uses == null) return false;
      return uses.any(
        (call) =>
            call.name == 'Skill' &&
            '${call.input['skill'] ?? ''}' == 'watchlist',
      );
    });
    final inspectedWatchlistHelp = turnMessages.any((message) {
      final uses = message.toolUses;
      if (uses == null) return false;
      return uses.any(
        (call) => call.name == 'Watchlist' && call.input['action'] == 'help',
      );
    });
    if (!loadedWatchlistSkill && !inspectedWatchlistHelp) return false;
    final executedIds = _executedToolUseIds(turnMessages);
    final hasMacroConditionWrite = turnMessages.any((message) {
      final uses = message.toolUses;
      if (uses == null) return false;
      return uses.any((call) {
        if (call.name != 'Watchlist' || !executedIds.contains(call.id)) {
          return false;
        }
        return call.input['action'] == 'add' &&
            call.input['type'] == 'macro-condition';
      });
    });
    final hasMacroConditionReadback = turnMessages.any((message) {
      final uses = message.toolUses;
      if (uses == null) return false;
      return uses.any((call) {
        if (call.name != 'Watchlist' || !executedIds.contains(call.id)) {
          return false;
        }
        return call.input['action'] == 'list' &&
            (call.input['type'] == 'macro-condition' ||
                call.input['groupType'] == 'macro-condition');
      });
    });
    if (hasMacroConditionWrite && !hasMacroConditionReadback) return true;
    final hasWatchlistStateCall = turnMessages.any((message) {
      final uses = message.toolUses;
      if (uses == null) return false;
      return uses.any((call) {
        if (call.name != 'Watchlist' || !executedIds.contains(call.id)) {
          return false;
        }
        final action = '${call.input['action'] ?? ''}';
        return action == 'add' || action == 'update' || action == 'list';
      });
    });
    return !hasWatchlistStateCall;
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
            .where(
              (row) => _isEtfCode(_textValue(row['code'] ?? row['symbol'], '')),
            )
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

  int _lastUserIndex(List<Message> messages) {
    for (var index = messages.length - 1; index >= 0; index--) {
      if (messages[index].role == Role.user) return index;
    }
    return -1;
  }

  bool _requiresMacroStockQuoteRecovery(List<Message> messages) {
    final searchTerm = _latestMacroStockSubject(messages);
    return searchTerm != null &&
        !_hasMacroStockQuoteEvidence(messages, searchTerm) &&
        !_hasStockIdentitySearch(messages, searchTerm);
  }

  String? _latestMacroStockSubject(List<Message> messages) {
    final state = FinanceWorkflowState.latestFromMessages(messages);
    if (state?.workflowKind == FinanceWorkflowKind.macroFactorLookup &&
        state?.assetClass == FinanceAssetClass.stock) {
      final subject = _normalizeStockSubject(state?.subject);
      if (subject != null) return subject;
      for (final candidate in state?.subjects ?? const <String>[]) {
        final normalized = _normalizeStockSubject(candidate);
        if (normalized != null) return normalized;
      }
    }
    for (var index = messages.length - 1; index >= 0; index--) {
      final uses = messages[index].toolUses ?? const <ToolUse>[];
      for (var useIndex = uses.length - 1; useIndex >= 0; useIndex--) {
        final call = uses[useIndex];
        final action = _textValue(call.input['action'], '');
        if ((call.name == 'MarketData' || call.name == 'DataStore') &&
            action.contains('macro')) {
          for (final key in const [
            'code',
            'symbol',
            'stockCode',
            'stockName',
            'subject',
          ]) {
            final subject = _normalizeStockSubject(call.input[key]);
            if (subject != null) return subject;
          }
        }
      }
    }
    return null;
  }

  String? _normalizeStockSubject(Object? value) {
    final subject = '${value ?? ''}'.trim();
    if (subject.isEmpty) return null;
    final qualifiedCode = RegExp(
      r'^(\d{6})\.(?:SH|SZ)$',
      caseSensitive: false,
    ).firstMatch(subject);
    return qualifiedCode?.group(1) ?? subject;
  }

  bool _hasMacroStockQuoteEvidence(List<Message> messages, String searchTerm) {
    final identity = _latestStockIdentityFromToolResults(messages, searchTerm);
    final successfulIds = messages
        .map((message) => message.toolResult)
        .where((result) => result != null && !result.isError)
        .map((result) => result!.toolUseId)
        .toSet();
    for (final message in messages) {
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        if (!successfulIds.contains(call.id)) continue;
        final action = call.input['action'];
        if ((call.name != 'DataStore' && call.name != 'MarketData') ||
            (action != 'query_quote' && action != 'quote')) {
          continue;
        }
        final code = _textValue(
          call.input['code'] ?? call.input['symbol'],
          '',
        );
        if (code.isNotEmpty && code == (identity?['code'] ?? searchTerm)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _hasStockIdentitySearch(List<Message> messages, String searchTerm) {
    for (final message in messages) {
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        if ((call.name == 'DataStore' || call.name == 'MarketData') &&
            call.input['action'] == 'query_stock_list' &&
            '${call.input['query'] ?? call.input['keyword'] ?? ''}' ==
                searchTerm) {
          return true;
        }
      }
    }
    return false;
  }

  Map<String, String>? _latestStockIdentityFromToolResults(
    List<Message> messages,
    String searchTerm,
  ) {
    final callsById = <String, ToolUse>{};
    for (final message in messages) {
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        callsById[call.id] = call;
      }
    }
    for (var index = messages.length - 1; index >= 0; index--) {
      final result = messages[index].toolResult;
      if (result == null || result.isError) continue;
      final call = callsById[result.toolUseId];
      if (call == null ||
          call.input['action'] != 'query_stock_list' ||
          '${call.input['keyword'] ?? call.input['query'] ?? ''}' !=
              searchTerm) {
        continue;
      }
      final decoded = _decodeMap(result.content);
      if (decoded?['action'] != 'query_stock_list') continue;
      final data = decoded?['data'];
      if (data is List) {
        for (final row in data.whereType<Map>()) {
          final code = _textValue(row['code'] ?? row['symbol'], '');
          final name = _textValue(row['name'], '');
          if (code.isNotEmpty && name.isNotEmpty) {
            return {'code': code, 'name': name};
          }
        }
      }
    }
    return null;
  }

  String? _toolResultAction(String content) {
    return _decodeMap(content)?['action']?.toString();
  }

  Map<String, dynamic>? _decodeMap(String content) {
    final text = content.trim();
    if (!text.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
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
    final presetBacktestEvidence = _presetBacktestEvidenceSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
    );
    if (saveEvidence != null) return saveEvidence;
    if (presetBacktestEvidence != null) {
      return '$answer\n\n$presetBacktestEvidence';
    }
    return null;
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
    final workflowState = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
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
    final macroEvidence = _macroEvidenceSummary.build(
      messages: messages,
      turnStartIndex: turnStartIndex,
      failureSummary: failureSummary,
    );
    if (macroEvidence != null &&
        !_requiresMacroStockQuoteRecovery(messages.sublist(turnStartIndex)) &&
        !_hasPendingMacroConditionWatchlistWorkflow(
          messages.sublist(turnStartIndex),
          workflowState,
        ) &&
        !_hasPendingWatchlistStateWorkflow(messages.sublist(turnStartIndex))) {
      return macroEvidence;
    }
    final macroFallback = _macroWorkflowBudgetFallback(
      messages.sublist(turnStartIndex),
      failureSummary,
    );
    if (macroFallback != null) return macroFallback;
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

  String? _macroWorkflowBudgetFallback(
    List<Message> turnMessages,
    String failureSummary,
  ) {
    final actions = <String>{};
    for (final message in turnMessages) {
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        if (call.name != 'MarketData' && call.name != 'DataStore') continue;
        final action = _textValue(call.input['action'], '');
        if (action.contains('macro') ||
            action == 'finance_news' ||
            action == 'query_finance_news') {
          actions.add(action);
        }
      }
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final action = _toolResultAction(result.content) ?? '';
      if (action.contains('macro') ||
          action == 'finance_news' ||
          action == 'query_finance_news') {
        actions.add(action);
      }
    }
    if (actions.isEmpty) return null;
    final attemptedRefresh =
        actions.contains('finance_news') ||
        actions.contains('macro_research_provenance') ||
        actions.contains('macro_research_extract');
    final attemptedReadback =
        actions.any((action) => action.startsWith('query_')) ||
        actions.contains('macro_research_sources');
    return [
      '已达到本轮受控数据调用预算，下面直接给出宏观来源/新闻工作流状态；未继续调用更多 provider、文件、脚本或交易工具。',
      '',
      '## 宏观来源与新闻证据状态',
      '',
      '- 刷新：${attemptedRefresh ? '已通过受治理 MarketData 路径尝试刷新新闻或宏观研究来源。' : '本轮没有完成新的 provider 刷新，只能使用本地读回。'}',
      '- 读回：${attemptedReadback ? '已请求本地宏观因子、宏观研究证据或财经新闻读回。' : '未取得可摘要的本地读回结果。'}',
      '- 来源：以工具结果中的 interface/provider/canonical schema 为准；新闻只作为线索，不能替代官方事实或内容级研究证据。',
      '- 获取时间：以 `query_finance_news`、`query_macro_*` 或 `macro_research_*` 工具结果中的 `fetchedAt` / source time 字段为准；若结果缺失，应视为证据缺口。',
      '',
      '## 本轮限制',
      '',
      '- $failureSummary',
    ].join('\n');
  }

  @override
  Future<String?> buildRecovery({
    required String? prompt,
    required List<Message> messages,
    required Tool? Function(String name) toolByName,
    required DomainRecoveryToolCall callTool,
  }) async {
    final macroStockQuote = await _buildMacroStockQuoteRecovery(
      messages: messages,
      toolByName: toolByName,
      callTool: callTool,
    );
    if (macroStockQuote != null) return macroStockQuote;
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

  Future<String?> _buildMacroStockQuoteRecovery({
    required List<Message> messages,
    required Tool? Function(String name) toolByName,
    required DomainRecoveryToolCall callTool,
  }) async {
    final turnStartIndex = _lastUserIndex(messages);
    if (turnStartIndex < 0) return null;
    final turnMessages = messages.sublist(turnStartIndex);
    final searchTerm = _latestMacroStockSubject(turnMessages);
    if (searchTerm == null ||
        _hasMacroStockQuoteEvidence(turnMessages, searchTerm)) {
      return null;
    }
    final identity = _latestStockIdentityFromToolResults(
      turnMessages,
      searchTerm,
    );
    final directCode = RegExp(r'^\d{6}$').hasMatch(searchTerm)
        ? searchTerm
        : null;
    final code = identity?['code'] ?? directCode;
    if (code == null) return null;
    final tool = toolByName('MarketData') ?? toolByName('DataStore');
    if (tool == null) return null;
    await callTool(
      tool,
      'auto_macro_stock_quote_${DateTime.now().microsecondsSinceEpoch}',
      {'action': 'query_quote', 'code': code, 'limit': 1},
    );
    return buildBudgetStopText(
      messages: messages,
      turnStartIndex: turnStartIndex,
      prompt: null,
      failureSummary:
          '本轮已使用结构化宏观 readback、新闻线索和个股行情证据；如需刷新来源，应进入显式 macro source update / extraction workflow。',
    );
  }
}
