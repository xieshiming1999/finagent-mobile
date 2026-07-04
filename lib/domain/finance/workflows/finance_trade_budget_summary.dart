import 'dart:convert';

import '../../../agent/message.dart';
import '../execution/trade_prep_contract.dart';
import 'finance_workflow_state.dart';

/// Finance-owned trade sizing summary for budget-stop turns.
class FinanceTradeBudgetSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
  }) {
    final workflowState = FinanceWorkflowState.latestTradePrepFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
    if (!_isTradeSizingWorkflow(workflowState)) return null;

    Map<String, dynamic>? balance;
    Map<String, dynamic>? localPortfolio;
    Map<String, dynamic>? quote;
    Map<String, dynamic>? rebalanceDraft;
    Map<String, dynamic>? portfolioEvidence;
    Map<String, dynamic>? portfolioPreview;
    Map<String, dynamic>? xueqiuPreview;
    final monitorSignal = _latestMonitorStrategySignal(messages);
    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final content = result.content.trim();
      final decoded = _decodeMap(content);
      if (decoded != null) {
        rebalanceDraft ??= _findRebalanceDraft(decoded);
        portfolioEvidence ??= _findPortfolioEvidence(decoded);
        if (portfolioPreview == null && decoded['action'] == 'preview_trade') {
          portfolioPreview = decoded;
        } else if (xueqiuPreview == null &&
            decoded['action'] == 'preview_order') {
          xueqiuPreview = decoded;
        } else if (balance == null && decoded.containsKey('performances')) {
          balance = decoded;
        } else if (localPortfolio == null && _isPortfolioPayload(decoded)) {
          localPortfolio = decoded;
        } else if (quote == null && _isQuotePayload(decoded)) {
          quote = decoded;
        }
      } else {
        quote ??= _quotePreview(content);
        localPortfolio ??= _portfolioPreview(content);
      }
    }
    if (balance == null &&
        localPortfolio == null &&
        quote == null &&
        portfolioPreview == null &&
        xueqiuPreview == null) {
      return null;
    }
    final confirmation = _latestAskUserQuestionAnswer(
      messages.skip(turnStartIndex).toList(),
    );
    if (_allowsSimulationPreview(confirmation) &&
        portfolioPreview == null &&
        xueqiuPreview == null) {
      return null;
    }

    final performance = _firstMap(balance?['performances']);
    final portfolio = _mapValue(balance?['portfolio']);
    final quoteRow = _firstMap(quote?['data']) ?? _firstMap(quote?['rows']);
    final cash = _firstFinite([
      _numValue(performance?['cash']),
      _numValue(localPortfolio?['cash']),
      _numValue(localPortfolio?['initialCash']),
      _numValue(localPortfolio?['initial_cash']),
    ]);
    final assets = _firstFinite([
      _numValue(performance?['assets']),
      _numValue(localPortfolio?['assets']),
      _numValue(localPortfolio?['totalAssets']),
      _numValue(localPortfolio?['initialCash']),
      _numValue(localPortfolio?['initial_cash']),
    ]);
    final price = _firstFinite([
      _numValue(quoteRow?['price']),
      _numValue(quoteRow?['latestPrice']),
      _numValue(quoteRow?['currentPrice']),
      _numValue(quoteRow?['close']),
      _numValue(monitorSignal?['price']),
      _numValue(monitorSignal?['value']),
    ]);
    final symbol = _textValue(
      quote?['symbol'] ?? quoteRow?['code'] ?? monitorSignal?['code'],
      '-',
    );
    final strategyId = _textValue(monitorSignal?['strategyId'], '-');
    final signal = _textValue(monitorSignal?['signal'], '-');
    final signalSource = _textValue(monitorSignal?['template'], '-');
    final source = _textValue(quote?['source'], '-');
    final provider = _textValue(quoteRow?['source'], '-');
    final dataTime = _textValue(quoteRow?['timestamp'], '-');
    final fetchedAt = _textValue(quoteRow?['fetchedAt'], '-');
    final budget = cash.isFinite ? cash * 0.2 : double.nan;
    final lotSize = balance != null ? 1 : 100;
    final shares = _sharesFromBudget(budget, price, lotSize);
    final amount = shares > 0 && price.isFinite ? shares * price : double.nan;

    return [
      '已达到本轮受控数据调用预算，下面直接使用已经取得的模拟盘与行情证据计算，不继续调用 provider、文件、脚本或交易工具。',
      '',
      '## 模拟盘买入测算',
      '',
      '- 组合：${_textValue(portfolio?['name'], 'finasimu')}。',
      '- 可用现金：${_money(cash)}；总资产：${_money(assets)}。',
      '- 标的：$symbol；参考价：${_money(price)}。',
      if (monitorSignal != null)
        '- 策略信号：strategyId=$strategyId；signal=$signal；source=$signalSource。',
      '- 20% 现金预算：${_money(budget)}。',
      '- 按当前执行通道估算：$shares 股，预计占用 ${_money(amount)}；lotSize=$lotSize。',
      if (portfolioPreview != null || xueqiuPreview != null) ...[
        '',
        '## 非写入预览',
        '',
        ..._previewLines(portfolioPreview, xueqiuPreview),
      ],
      if (rebalanceDraft != null) ...[
        '',
        '## 组合再平衡草案',
        '',
        ..._rebalanceDraftLines(rebalanceDraft, portfolioEvidence, cash),
      ],
      '',
      '## 数据来源',
      '',
      '- 模拟盘：${_balanceSource(balance, localPortfolio)}，未调用 buy/sell/transfer。',
      '- 行情：${_textValue(quote?['readbackAction'] ?? quote?['action'], 'query_quote')}；source=$source；provider=$provider；数据时间=$dataTime；获取时间=$fetchedAt。',
      '',
      '## 交易边界',
      '',
      portfolioPreview != null || xueqiuPreview != null
          ? '- 本轮只完成非写入预览，不直接交易。'
          : '- 本轮只计算，不直接交易。',
      if (rebalanceDraft != null)
        '- 组合再平衡草案只作为 StrategySpec ranking evidence 的仓位参考，不会自动调仓。',
      '- 不会调用 XueqiuTrade(buy)、XueqiuTrade(sell)、XueqiuTrade(transfer) 或 Portfolio(trade)。',
      '- 若策略实际触发并准备下单，必须重新确认组合、价格、股数、金额、费用假设和止损边界。',
      '- 本轮失败/跳过：$failureSummary',
      'tradePrep:${jsonEncode(_tradePrep(strategyId: strategyId, signal: signal, symbol: symbol, cash: cash, assets: assets, budget: budget, referencePrice: price, lotSize: lotSize, shares: shares, amount: amount, balance: balance, localPortfolio: localPortfolio, quote: quote, portfolioPreview: portfolioPreview, xueqiuPreview: xueqiuPreview, confirmation: confirmation))}',
    ].join('\n');
  }

  Map<String, dynamic> _tradePrep({
    required String strategyId,
    required String signal,
    required String symbol,
    required double cash,
    required double assets,
    required double budget,
    required double referencePrice,
    required int lotSize,
    required int shares,
    required double amount,
    required Map<String, dynamic>? balance,
    required Map<String, dynamic>? localPortfolio,
    required Map<String, dynamic>? quote,
    required Map<String, dynamic>? portfolioPreview,
    required Map<String, dynamic>? xueqiuPreview,
    required String? confirmation,
  }) {
    return TradePrepContract(
      prepKind: 'strategy_signal_position_sizing',
      strategyId: strategyId,
      signal: signal,
      symbol: symbol,
      sizing: {
        'cash': _jsonNumber(cash),
        'assets': _jsonNumber(assets),
        'budget': _jsonNumber(budget),
        'budgetRule': '20pct_cash',
        'referencePrice': _jsonNumber(referencePrice),
        'lotSize': lotSize,
        'shares': shares,
        'amount': _jsonNumber(amount),
      },
      evidence: {
        'xueqiuBalance': balance != null,
        'portfolioSnapshot': localPortfolio != null,
        'quote': quote != null,
      },
      previews: {
        'portfolioPreview': portfolioPreview != null,
        'xueqiuPreview': xueqiuPreview != null,
      },
      boundaries: const [
        'prep_only',
        'no_order_write',
        'no_portfolio_trade',
        'requires_explicit_confirmation_before_execution',
      ],
      confirmation: confirmation ?? '',
    ).toJson();
  }

  double? _jsonNumber(double value) => value.isFinite ? value : null;

  int _sharesFromBudget(double budget, double price, int lotSize) {
    if (!budget.isFinite || !price.isFinite || price <= 0) return 0;
    final normalizedLotSize = lotSize > 0 ? lotSize : 1;
    return (budget / price / normalizedLotSize).floor() * normalizedLotSize;
  }

  List<String> _previewLines(
    Map<String, dynamic>? portfolioPreview,
    Map<String, dynamic>? xueqiuPreview,
  ) {
    final lines = <String>[];
    if (portfolioPreview != null) {
      final order = _mapValue(portfolioPreview['order']);
      final estimated = _mapValue(portfolioPreview['estimated']);
      lines.add(
        '- Portfolio(action:"preview_trade")：sideEffect=${_textValue(portfolioPreview['sideEffect'], 'false')}；executionAllowed=${_textValue(portfolioPreview['executionAllowed'], '-')}；${_orderText(order)}；预计现金变化 ${_money(_numValue(estimated?['cashBefore']))} -> ${_money(_numValue(estimated?['cashAfter']))}。',
      );
    }
    if (xueqiuPreview != null) {
      final order = _mapValue(xueqiuPreview['order']);
      final readback = _mapValue(xueqiuPreview['readbackEvidence']);
      lines.add(
        '- XueqiuTrade(action:"preview_order")：sideEffect=${_textValue(xueqiuPreview['sideEffect'], 'false')}；${_orderText(order)}；readback=${readback == null ? '-' : readback.keys.join(', ')}。',
      );
    }
    lines.add('- 预览结果不代表已下单，也不写入本地 Portfolio trade。');
    return lines;
  }

  String _orderText(Map<String, dynamic>? order) {
    if (order == null) return 'order=-';
    return 'order=${_textValue(order['side'], '-')} ${_textValue(order['symbol'], '-')} ${_textValue(order['shares'], '-')} @ ${_textValue(order['price'], '-')}';
  }

  String? _latestAskUserQuestionAnswer(List<Message> messages) {
    final askIds = <String>{};
    for (final message in messages) {
      for (final call in message.toolUses ?? const <ToolUse>[]) {
        if (call.name == 'AskUserQuestion') askIds.add(call.id);
      }
    }
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null ||
          result.isError ||
          !askIds.contains(result.toolUseId)) {
        continue;
      }
      final answer = result.content.trim();
      if (answer.isNotEmpty) return answer;
    }
    return null;
  }

  bool _allowsSimulationPreview(String? answer) {
    final decoded = _decodeMap(answer ?? '');
    if (decoded == null) return false;
    final explicit = '${decoded['decision'] ?? decoded['action'] ?? ''}'
        .trim()
        .toLowerCase();
    if (const {
      'allow_preview',
      'preview',
      'allow_simulation_preview',
      'simulate_preview',
    }.contains(explicit)) {
      return true;
    }
    final index = decoded['selectedOptionIndex'] ?? decoded['optionIndex'];
    return index == 3 || index == '3';
  }

  bool _isTradeSizingWorkflow(FinanceWorkflowState? state) {
    return state?.workflowKind == FinanceWorkflowKind.tradePrep &&
        (state?.intentMode == FinanceIntentMode.size ||
            state?.intentMode == FinanceIntentMode.confirm);
  }

  Map<String, dynamic>? _decodeMap(String content) {
    if (!content.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _latestMonitorStrategySignal(List<Message> messages) {
    for (final message in messages.reversed) {
      if (message.role != Role.user) continue;
      final markerIndex = message.content.lastIndexOf('data:');
      if (markerIndex < 0) continue;
      final decoded = _decodeMap(
        message.content.substring(markerIndex + 5).trim(),
      );
      if (decoded == null || decoded['template'] != 'strategy_signal') {
        continue;
      }
      return decoded;
    }
    return null;
  }

  bool _isQuotePayload(Map<String, dynamic> decoded) {
    final action = decoded['action'];
    return action == 'query_quote' ||
        action == 'quote' ||
        decoded['readbackAction'] == 'query_quote' ||
        decoded['canonicalSchema'] == 'quote_snapshot';
  }

  bool _isPortfolioPayload(Map<String, dynamic> decoded) {
    final action = decoded['action'];
    return action == 'snapshot' ||
        action == 'portfolio_snapshot' ||
        decoded.containsKey('initialCash') ||
        decoded.containsKey('initial_cash') ||
        decoded.containsKey('positions');
  }

  Map<String, dynamic>? _findRebalanceDraft(Map<String, dynamic> decoded) {
    final direct = _mapValue(decoded['rebalanceDraft']);
    if (direct != null) return direct;
    final items = decoded['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final itemMap = Map<String, dynamic>.from(item);
        final fromItem = _mapValue(itemMap['rebalanceDraft']);
        if (fromItem != null) return fromItem;
        final rules = _mapValue(itemMap['strategyRules']);
        final fromRules = _mapValue(rules?['rebalanceDraft']);
        if (fromRules != null) return fromRules;
      }
    }
    final rules = _mapValue(decoded['strategyRules']);
    return _mapValue(rules?['rebalanceDraft']);
  }

  Map<String, dynamic>? _findPortfolioEvidence(Map<String, dynamic> decoded) {
    final direct = _mapValue(decoded['portfolioEvidence']);
    if (direct != null) return direct;
    final items = decoded['items'];
    if (items is List) {
      for (final item in items) {
        if (item is! Map) continue;
        final itemMap = Map<String, dynamic>.from(item);
        final fromItem = _mapValue(itemMap['portfolioEvidence']);
        if (fromItem != null) return fromItem;
        final rules = _mapValue(itemMap['strategyRules']);
        final fromRules = _mapValue(rules?['portfolioEvidence']);
        if (fromRules != null) return fromRules;
      }
    }
    final rules = _mapValue(decoded['strategyRules']);
    return _mapValue(rules?['portfolioEvidence']);
  }

  List<String> _rebalanceDraftLines(
    Map<String, dynamic>? draft,
    Map<String, dynamic>? evidence,
    double cash,
  ) {
    final positions = draft?['positions'];
    final lines = <String>[
      '- 来源：custom_strategy_rank / Watchlist readback；mode=${_textValue(draft?['mode'], 'equal_weight_top_n')}；rebalanceInterval=${_textValue(draft?['rebalanceInterval'], '-')}。',
    ];
    final aggregate =
        _mapValue(draft?['aggregateMetrics']) ??
        _mapValue(evidence?['aggregateMetrics']);
    if (aggregate != null) {
      lines.add(
        '- 组合证据：expectedReturn=${_textValue(aggregate['expectedReturnPct'], '-')}%；portfolioMaxDrawdown=${_textValue(aggregate['portfolioMaxDrawdownPct'], '-')}%；selected=${_textValue(aggregate['selectedSymbols'], '-')}。',
      );
    }
    if (positions is List && positions.isNotEmpty) {
      for (final position in positions.take(5)) {
        if (position is! Map) continue;
        final symbol = _textValue(position['symbol'], '-');
        final weight = _numValue(position['targetWeight']);
        final amount = cash.isFinite && weight.isFinite
            ? cash * weight
            : double.nan;
        lines.add(
          '- $symbol：目标权重 ${weight.isFinite ? (weight * 100).toStringAsFixed(1) : '-'}%；按当前现金估算金额 ${_money(amount)}；weightCapped=${_textValue(position['weightCapped'], 'false')}。',
        );
      }
    }
    lines.add(
      '- 边界：${_textValue(draft?['tradeBoundary'], 'evidence only; confirmation required before any order')}',
    );
    return lines;
  }

  Map<String, dynamic>? _quotePreview(String content) {
    final decoded = _decodeMap(content);
    if (decoded == null || decoded['action'] != 'query_quote') return null;
    final rows = decoded['data'];
    final first = rows is List && rows.isNotEmpty && rows.first is Map
        ? Map<String, dynamic>.from(rows.first as Map)
        : const <String, dynamic>{};
    final price = _numValue(first['price'] ?? decoded['price']);
    if (!price.isFinite) return null;
    return {
      'action': 'query_quote',
      'symbol': _textValue(
        decoded['symbol'] ?? decoded['code'] ?? first['code'],
        '',
      ),
      'source': _textValue(decoded['source'] ?? first['source'], ''),
      'data': [
        {
          'code': _textValue(first['code'] ?? decoded['code'], ''),
          'price': price,
          'timestamp': _textValue(
            first['timestamp'] ?? decoded['timestamp'],
            '',
          ),
          'fetchedAt': _textValue(
            first['fetchedAt'] ?? decoded['fetchedAt'],
            '',
          ),
          'source': _textValue(first['source'] ?? decoded['source'], ''),
        },
      ],
    };
  }

  Map<String, dynamic>? _portfolioPreview(String content) {
    final initialCash = RegExp(
      r'Initial cash[:：]\s*([0-9]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(content);
    final cash = RegExp(
      r'(?:cash|现金)[:：]\s*([0-9]+(?:\.[0-9]+)?)',
      caseSensitive: false,
    ).firstMatch(content);
    final value = initialCash?.group(1) ?? cash?.group(1);
    if (value == null) return null;
    return {
      'action': 'snapshot',
      'source': 'Portfolio(snapshot)',
      'initialCash': num.tryParse(value),
      'cash': num.tryParse(value),
      'assets': num.tryParse(value),
    };
  }

  Map<String, dynamic>? _firstMap(Object? value) {
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return null;
  }

  Map<String, dynamic>? _mapValue(Object? value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  double _numValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? double.nan;
  }

  double _firstFinite(List<double> values) {
    for (final value in values) {
      if (value.isFinite) return value;
    }
    return double.nan;
  }

  String _textValue(Object? value, String fallback) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  String _money(double value) {
    if (!value.isFinite) return '-';
    return value.toStringAsFixed(2);
  }

  String _balanceSource(
    Map<String, dynamic>? balance,
    Map<String, dynamic>? localPortfolio,
  ) {
    if (balance != null) return 'XueqiuTrade(balance)';
    if (localPortfolio != null) return 'Portfolio(snapshot) local fallback';
    return 'unavailable';
  }
}
