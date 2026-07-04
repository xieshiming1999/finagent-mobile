import 'dart:convert';

import '../../../agent/ask_user_question_contract.dart';
import '../../../agent/message.dart';
import 'finance_workflow_state.dart';

enum _TradeAskDecision { none, stop, allowPreview }

class FinanceTradeSizingPreflight {
  final Set<String>? availableToolNames;

  const FinanceTradeSizingPreflight({this.availableToolNames});

  List<ToolUse>? buildToolCalls(List<Message> messages) {
    final start = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (start < 0) return null;
    final workflowState = FinanceWorkflowState.latestTradePrepFromMessages(
      messages,
      turnStartIndex: start,
    );
    if (!_isTradeSizingWorkflow(workflowState)) return null;

    final turnMessages = messages.skip(start + 1).toList();
    final calls = _collectToolCalls(turnMessages);
    final results = _successfulToolResults(turnMessages);
    final failures = _failedToolResults(turnMessages);
    final blockedTools = _blockedToolNames(workflowState);
    final xueqiuAvailable =
        availableToolNames == null ||
        availableToolNames!.contains('XueqiuTrade');
    final xueqiuForbidden =
        blockedTools.contains('XueqiuTrade') || !xueqiuAvailable;
    final hasXueqiuReadFailure = calls.any(
      (call) =>
          call.name == 'XueqiuTrade' &&
          (call.input['action'] == 'portfolios' ||
              call.input['action'] == 'balance') &&
          failures.contains(call.id),
    );
    final hasXueqiuBalance = calls.any(
      (call) =>
          call.name == 'XueqiuTrade' &&
          call.input['action'] == 'balance' &&
          results.contains(call.id),
    );
    final hasPortfolioSnapshot = calls.any(
      (call) =>
          call.name == 'Portfolio' &&
          call.input['action'] == 'snapshot' &&
          results.contains(call.id),
    );
    final hasQuote = calls.any(
      (call) =>
          call.name == 'MarketData' &&
          call.input['action'] == 'query_quote' &&
          results.contains(call.id),
    );
    final hasAskUserQuestion = calls.any(
      (call) => call.name == 'AskUserQuestion' && results.contains(call.id),
    );
    final confirmationDecision = _latestAskUserDecision(turnMessages);
    final wantsPreview = confirmationDecision == _TradeAskDecision.allowPreview;
    if (confirmationDecision != _TradeAskDecision.none && !wantsPreview) {
      return null;
    }
    if (wantsPreview && !_hasTradePreview(calls, results)) {
      final preview = _buildPreviewToolCalls(
        messages: messages,
        turnMessages: turnMessages,
        xueqiuForbidden: xueqiuForbidden || hasXueqiuReadFailure,
      );
      if (preview.isNotEmpty) return preview;
    }
    final sizingSymbol = _latestStrategySymbol(messages);
    if (!hasQuote && sizingSymbol != null) {
      return [
        ToolUse(
          id: 'trade_sizing_quote_${DateTime.now().microsecondsSinceEpoch}',
          name: 'MarketData',
          input: {
            'action': 'query_quote',
            'symbols': [sizingSymbol],
            'limit': 1,
          },
        ),
      ];
    }
    if ((xueqiuForbidden || hasXueqiuBalance || hasXueqiuReadFailure) &&
        hasPortfolioSnapshot) {
      if (hasAskUserQuestion) return null;
      return [
        ToolUse(
          id: 'trade_sizing_confirmation_${DateTime.now().microsecondsSinceEpoch}',
          name: 'AskUserQuestion',
          input: {
            'questions': [
              {
                'question': '策略信号触发后，是否允许进入雪球模拟盘或本地模拟盘执行？',
                'header': '交易确认',
                'multiSelect': false,
                'options': [
                  {'label': '触发时再确认', 'description': '现在只保留计算和监控结果，真正买入前再次询问。'},
                  {'label': '只计算不下单', 'description': '本轮不进入任何模拟交易执行流程。'},
                  {'label': '允许模拟执行', 'description': '后续仍需使用已确认的组合、价格和股数参数。'},
                ],
              },
            ],
          },
        ),
      ];
    }

    final toolCalls = <ToolUse>[];
    if (!xueqiuForbidden &&
        !hasXueqiuReadFailure &&
        !calls.any(
          (call) =>
              call.name == 'XueqiuTrade' &&
              call.input['action'] == 'portfolios',
        )) {
      toolCalls.add(
        ToolUse(
          id: 'trade_sizing_xueqiu_portfolios_${DateTime.now().microsecondsSinceEpoch}',
          name: 'XueqiuTrade',
          input: {'action': 'portfolios'},
        ),
      );
    }
    if (!xueqiuForbidden && !hasXueqiuReadFailure && !hasXueqiuBalance) {
      toolCalls.add(
        ToolUse(
          id: 'trade_sizing_xueqiu_balance_${DateTime.now().microsecondsSinceEpoch}',
          name: 'XueqiuTrade',
          input: {'action': 'balance'},
        ),
      );
    }
    if (!hasPortfolioSnapshot) {
      toolCalls.add(
        ToolUse(
          id: 'trade_sizing_portfolio_snapshot_${DateTime.now().microsecondsSinceEpoch}',
          name: 'Portfolio',
          input: {'action': 'snapshot', 'market': 'cn'},
        ),
      );
    }
    return toolCalls.isEmpty ? null : toolCalls;
  }

  bool _isTradeSizingWorkflow(FinanceWorkflowState? state) {
    return state?.workflowKind == FinanceWorkflowKind.tradePrep &&
        (state?.intentMode == FinanceIntentMode.size ||
            state?.intentMode == FinanceIntentMode.confirm);
  }

  Set<String> _blockedToolNames(FinanceWorkflowState? state) {
    if (state == null) return const {};
    return state.blockedTools.map((tool) => tool.trim()).where((tool) {
      return tool.isNotEmpty;
    }).toSet();
  }

  List<ToolUse> _collectToolCalls(List<Message> messages) {
    final calls = <ToolUse>[];
    for (final message in messages) {
      final uses = message.toolUses;
      if (uses != null) calls.addAll(uses);
    }
    return calls;
  }

  Set<String> _successfulToolResults(List<Message> messages) {
    final ids = <String>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (result != null && !result.isError) ids.add(result.toolUseId);
    }
    return ids;
  }

  Set<String> _failedToolResults(List<Message> messages) {
    final ids = <String>{};
    for (final message in messages) {
      final result = message.toolResult;
      if (result != null && result.isError) ids.add(result.toolUseId);
    }
    return ids;
  }

  _TradeAskDecision _latestAskUserDecision(List<Message> messages) {
    final askIds = <String>{};
    for (final message in messages) {
      final uses = message.toolUses;
      if (uses == null) continue;
      for (final use in uses) {
        if (use.name == 'AskUserQuestion') askIds.add(use.id);
      }
    }
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      if (!askIds.contains(result.toolUseId)) continue;
      return _extractAskUserDecision(result.content);
    }
    return _TradeAskDecision.none;
  }

  _TradeAskDecision _extractAskUserDecision(String content) {
    final decoded = latestAskUserQuestionStructuredAnswer(content);
    if (decoded != null) {
      final explicit = '${decoded['decision'] ?? decoded['action'] ?? ''}'
          .trim()
          .toLowerCase();
      if (const {
        'allow_preview',
        'preview',
        'allow_simulation_preview',
        'simulate_preview',
      }.contains(explicit)) {
        return _TradeAskDecision.allowPreview;
      }
      if (const {
        'deny',
        'denied',
        'no',
        'cancel',
        'defer',
        'later',
      }.contains(explicit)) {
        return _TradeAskDecision.stop;
      }
      final index = decoded['selectedOptionIndex'] ?? decoded['optionIndex'];
      if (index == 3 || index == '3') return _TradeAskDecision.allowPreview;
      if (index == 1 || index == 2 || index == '1' || index == '2') {
        return _TradeAskDecision.stop;
      }
    }
    // Boundary normalization only: free-form AskUserQuestion text is not a
    // workflow authorization contract. Only structured decision/action or a
    // structured option index can allow preview.
    return content.trim().isEmpty
        ? _TradeAskDecision.none
        : _TradeAskDecision.stop;
  }

  bool _hasTradePreview(List<ToolUse> calls, Set<String> results) {
    return calls.any(
      (call) =>
          results.contains(call.id) &&
          ((call.name == 'Portfolio' &&
                  call.input['action'] == 'preview_trade') ||
              (call.name == 'XueqiuTrade' &&
                  call.input['action'] == 'preview_order')),
    );
  }

  List<ToolUse> _buildPreviewToolCalls({
    required List<Message> messages,
    required List<Message> turnMessages,
    required bool xueqiuForbidden,
  }) {
    final symbol = _latestStrategySymbol(messages);
    final price = _latestReferencePrice(messages);
    final cash = _latestCash(turnMessages);
    if (symbol == null || price == null || price <= 0) return const [];
    final budget = cash == null || cash <= 0 ? price * 100 : cash * 0.2;
    final portfolioShares = ((budget / price) / 100).floor() * 100;
    final xueqiuShares = (budget / price).floor();
    final now = DateTime.now().microsecondsSinceEpoch;
    final calls = <ToolUse>[];
    if (portfolioShares > 0) {
      calls.add(ToolUse(
        id: 'trade_sizing_portfolio_preview_$now',
        name: 'Portfolio',
        input: {
          'action': 'preview_trade',
          'market': 'cn',
          'symbol': symbol,
          'side': 'buy',
          'shares': portfolioShares,
          'price': price,
        },
      ));
    }
    if (!xueqiuForbidden && xueqiuShares > 0) {
      calls.add(
        ToolUse(
          id: 'trade_sizing_xueqiu_preview_$now',
          name: 'XueqiuTrade',
          input: {
            'action': 'preview_order',
            'side': 'buy',
            'symbol': symbol,
            'shares': xueqiuShares,
            'price': price,
          },
        ),
      );
    }
    return calls;
  }

  double? _latestReferencePrice(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeMap(result.content);
      if (decoded == null) continue;
      for (final value in [
        decoded['price'],
        decoded['value'],
        _firstMap(decoded['data'])?['price'],
        _firstMap(decoded['rows'])?['price'],
        _firstMap(decoded['data'])?['close'],
        _firstMap(decoded['rows'])?['close'],
      ]) {
        final parsed = _numValue(value);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    for (final message in messages.reversed) {
      if (message.role != Role.user) continue;
      final decoded = _decodeUserDataPayload(message.content);
      if (decoded == null) continue;
      for (final value in [
        decoded['price'],
        decoded['value'],
        decoded['referencePrice'],
      ]) {
        final parsed = _numValue(value);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return null;
  }

  double? _latestCash(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeMap(result.content);
      if (decoded == null) continue;
      final performance = _firstMap(decoded['performances']);
      final parsed = _numValue(performance?['cash']);
      if (parsed != null && parsed > 0) return parsed;
    }
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeMap(result.content);
      if (decoded == null) continue;
      for (final value in [
        decoded['cash'],
        decoded['initialCash'],
        decoded['initial_cash'],
      ]) {
        final parsed = _numValue(value);
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return null;
  }

  Map<String, dynamic>? _firstMap(Object? value) {
    if (value is List) {
      for (final item in value) {
        if (item is Map) return Map<String, dynamic>.from(item);
      }
    }
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  double? _numValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.replaceAll(',', ''));
    return null;
  }

  String? _latestStrategySymbol(List<Message> messages) {
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final decoded = _decodeMap(result.content);
      if (decoded == null) continue;
      final symbol = _strategySymbolFromMap(decoded);
      if (symbol != null) return symbol;
    }
    for (final message in messages.reversed) {
      if (message.role != Role.user) continue;
      final decoded = _decodeUserDataPayload(message.content);
      if (decoded == null) continue;
      final symbol = _strategySymbolFromMap(decoded);
      if (symbol != null) return symbol;
    }
    return null;
  }

  Map<String, dynamic>? _decodeUserDataPayload(String content) {
    final marker = content.lastIndexOf('data:');
    if (marker < 0) return null;
    return _decodeMap(content.substring(marker + 'data:'.length));
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

  String? _strategySymbolFromMap(Map<String, dynamic> decoded) {
    for (final key in const ['symbol', 'code']) {
      final value = _normalizeSymbol(decoded[key]);
      if (value != null) return value;
    }
    final validation = decoded['validation'];
    if (validation is Map) {
      final value = _strategySymbolFromMap(
        Map<String, dynamic>.from(validation),
      );
      if (value != null) return value;
    }
    final spec = decoded['spec'] ?? decoded['strategySpec'];
    if (spec is Map) {
      final value = _strategySymbolFromMap(Map<String, dynamic>.from(spec));
      if (value != null) return value;
    }
    final symbols = decoded['symbols'];
    if (symbols is List && symbols.isNotEmpty) {
      return _normalizeSymbol(symbols.first);
    }
    return null;
  }

  String? _normalizeSymbol(Object? value) {
    final text = value?.toString().trim().toUpperCase() ?? '';
    if (text.isEmpty) return null;
    final clean = text.replaceAll(
      RegExp(r'\.(SH|SZ|BJ|OF)$', caseSensitive: false),
      '',
    );
    if (RegExp(r'^\d{6}$').hasMatch(clean)) return clean;
    if (RegExp(r'^(SH|SZ|BJ)\d{6}$').hasMatch(text)) {
      return text.substring(2);
    }
    return null;
  }
}
