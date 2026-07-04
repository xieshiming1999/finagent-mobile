// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';

import '../domain/market/services/market_data_resolve_service.dart';
import 'strategy.dart';
import 'data_fetcher/models.dart';
import 'data_processor/indicators.dart';

/// Executes strategy workflows against live market data.
/// Produces typed StrategyDecision with ATR-based stops and computed position sizing.
class StrategyExecutor {
  final MarketDataResolveService _resolveService;

  StrategyExecutor(this._resolveService);

  /// Execute a strategy against a symbol, returning typed decision.
  Future<StrategyDecision> execute(Strategy strategy, String symbol) async {
    final klineResult = await _resolveService.resolveKline(symbol);
    final bars = klineResult.bars;
    if (bars.isEmpty) {
      final exec = StrategyExecution(
        symbol: symbol,
        decision: 'skip',
        reasoning: '无法获取K线数据',
        score: 0,
      );
      return StrategyDecision(
        symbol: symbol,
        strategyId: strategy.id,
        strategyName: strategy.name,
        decision: 'skip',
        score: 0,
        reasoning: '无法获取K线数据',
        execution: exec,
      );
    }

    // Fetch live quote for fundamental data (PE/PB)
    StockQuote? quote;
    try {
      final quoteResult = await _resolveService.resolveQuotes([symbol]);
      if (quoteResult.data.isNotEmpty) quote = quoteResult.data.first;
    } catch (_) {}

    final stepResults = <StepResult>[];
    var requiredFailed = false;
    var totalScore = 0.0;
    var maxScore = 0.0;

    for (final step in strategy.steps) {
      final weight = step.required ? 30.0 : 20.0;
      maxScore += weight;

      final result = _evaluateStepSync(step, bars, quote: quote);
      stepResults.add(result);

      if (result.passed) {
        totalScore += weight;
      } else if (step.required) {
        requiredFailed = true;
      }
    }

    final score = maxScore > 0
        ? (totalScore / maxScore * 100).roundToDouble()
        : 0.0;
    final decision = requiredFailed
        ? 'skip'
        : (score >= 70
              ? 'buy'
              : score >= 50
              ? 'watch'
              : 'skip');

    // Compute ATR-based stops and position sizing for buy decisions
    final price = bars.last.close;
    double? stopLoss, targetPrice, positionPct;
    if (decision == 'buy') {
      final atrVals = Indicators.atr(bars);
      final atrVal = atrVals.last;
      if (atrVal != null && atrVal > 0) {
        stopLoss = double.parse((price - 2 * atrVal).toStringAsFixed(2));
        targetPrice = double.parse((price + 3 * atrVal).toStringAsFixed(2));
        positionPct = computePositionSize(price, stopLoss);
      } else {
        stopLoss = double.parse((price * 0.92).toStringAsFixed(2));
        targetPrice = double.parse((price * 1.15).toStringAsFixed(2));
        positionPct = 0.10;
      }
    }

    final reasoning = _buildReasoningChain(
      symbol,
      strategy,
      stepResults,
      score,
      decision,
      stopLoss: stopLoss,
      targetPrice: targetPrice,
      positionPct: positionPct,
    );

    final exec = StrategyExecution(
      symbol: symbol,
      stepResults: stepResults,
      decision: decision,
      reasoning: reasoning,
      score: score,
    );

    return StrategyDecision(
      symbol: symbol,
      strategyId: strategy.id,
      strategyName: strategy.name,
      decision: decision,
      score: score,
      suggestedEntry: decision == 'buy' ? price : null,
      stopLoss: stopLoss,
      targetPrice: targetPrice,
      positionPct: positionPct,
      reasoning: reasoning,
      execution: exec,
    );
  }

  /// Risk-based position sizing: risk 2% of capital per trade.
  static double computePositionSize(
    double entryPrice,
    double stopLoss, {
    double riskPct = 0.02,
  }) {
    final stopDistance = (entryPrice - stopLoss).abs() / entryPrice;
    if (stopDistance == 0) return 0.10;
    return double.parse(
      (riskPct / stopDistance).clamp(0.05, 0.30).toStringAsFixed(2),
    );
  }

  /// Backtest a strategy over historical data with ATR-based exit.
  Future<Map<String, dynamic>> backtest(
    Strategy strategy,
    String symbol, {
    int days = 250,
    int windowSize = 60,
  }) async {
    final startDate = DateTime.now().subtract(
      Duration(days: days + windowSize),
    );
    final startStr =
        '${startDate.year}-${startDate.month.toString().padLeft(2, '0')}-${startDate.day.toString().padLeft(2, '0')}';
    final klineR = await _resolveService.resolveKline(
      symbol,
      startDate: startStr,
    );
    final bars = klineR.bars;
    if (bars.length < windowSize + 20) {
      return {'error': 'insufficient_data', 'bars': bars.length};
    }

    const maxHoldDays = 20;
    const costPct =
        0.002; // round-trip cost: buy 0.1% + sell 0.1% (commission + stamp tax)

    var totalSignals = 0;
    var correctSignals = 0;
    final trades = <_BacktestTrade>[];
    var i = windowSize;

    while (i < bars.length - 1) {
      final window = bars.sublist(max(0, i - windowSize), i + 1);
      var requiredFailed = false;
      var totalScore = 0.0;
      var maxScore = 0.0;

      for (final step in strategy.steps) {
        final weight = step.required ? 30.0 : 20.0;
        maxScore += weight;
        final result = _evaluateStepSync(step, window);
        if (result.passed) {
          totalScore += weight;
        } else if (step.required)
          requiredFailed = true;
      }

      final score = maxScore > 0 ? totalScore / maxScore * 100 : 0.0;
      if (requiredFailed || score < 70) {
        i++;
        continue;
      }

      // Signal triggered — simulate entry at next day's open
      totalSignals++;
      final entryIdx = i + 1;
      if (entryIdx >= bars.length) break;
      final entryPrice = bars[entryIdx].open;

      // Compute ATR for stop/target
      final atrVals = Indicators.atr(window);
      final atr = atrVals.isNotEmpty && atrVals.last != null
          ? atrVals.last!
          : entryPrice * 0.03;
      final stopLoss = entryPrice - 2 * atr;
      final targetPrice = entryPrice + 3 * atr;

      // Hold and check daily exit conditions
      var exitIdx = min(entryIdx + maxHoldDays, bars.length - 1);
      var exitPrice = bars[exitIdx].close;
      var exitReason = 'max_hold';

      for (
        var j = entryIdx + 1;
        j < bars.length && j <= entryIdx + maxHoldDays;
        j++
      ) {
        // Check intraday low for stop loss (worst case first)
        if (bars[j].low <= stopLoss) {
          exitIdx = j;
          exitPrice = stopLoss;
          exitReason = 'stop_loss';
          break;
        }
        // Check intraday high for target
        if (bars[j].high >= targetPrice) {
          exitIdx = j;
          exitPrice = targetPrice;
          exitReason = 'target';
          break;
        }
      }

      final grossReturn = (exitPrice - entryPrice) / entryPrice * 100;
      final netReturn = grossReturn - costPct * 100;
      if (netReturn > 0) correctSignals++;

      trades.add(
        _BacktestTrade(
          entryDate: bars[entryIdx].date,
          exitDate: bars[exitIdx].date,
          entryPrice: entryPrice,
          exitPrice: exitPrice,
          holdDays: exitIdx - entryIdx,
          returnPct: netReturn,
          exitReason: exitReason,
        ),
      );

      // Skip ahead past this trade (no overlapping positions)
      i = exitIdx + 1;
    }

    if (totalSignals == 0) {
      return {'signals': 0, 'message': '回测期间无信号触发'};
    }

    final returns = trades.map((t) => t.returnPct).toList();
    final avgReturn = returns.reduce((a, b) => a + b) / returns.length;
    final winRate = correctSignals / totalSignals;
    final maxDD = _maxDrawdown(returns);
    final avgHold =
        trades.map((t) => t.holdDays).reduce((a, b) => a + b) / trades.length;
    final profitFactor = _profitFactor(returns);

    final stopCount = trades.where((t) => t.exitReason == 'stop_loss').length;
    final targetCount = trades.where((t) => t.exitReason == 'target').length;
    final holdCount = trades.where((t) => t.exitReason == 'max_hold').length;

    return {
      'strategy': strategy.name,
      'symbol': symbol,
      'period_days': days,
      'total_signals': totalSignals,
      'total_trades': trades.length,
      'win_rate': double.parse((winRate * 100).toStringAsFixed(1)),
      'avg_return_pct': double.parse(avgReturn.toStringAsFixed(2)),
      'total_return_pct': double.parse(
        returns.reduce((a, b) => a + b).toStringAsFixed(2),
      ),
      'max_drawdown_pct': double.parse(maxDD.toStringAsFixed(2)),
      'avg_hold_days': double.parse(avgHold.toStringAsFixed(1)),
      'profit_factor': double.parse(profitFactor.toStringAsFixed(2)),
      'exit_reasons': {
        'stop_loss': stopCount,
        'target': targetCount,
        'max_hold': holdCount,
      },
      'cost_assumption': '${(costPct * 100).toStringAsFixed(1)}% round-trip',
      'recent_trades': trades.reversed.take(5).map((t) => t.toJson()).toList(),
    };
  }

  StepResult _evaluateStepSync(
    WorkflowStep step,
    List<KlineBar> bars, {
    StockQuote? quote,
  }) {
    if (bars.isEmpty) {
      return StepResult(
        stepDescription: step.description,
        passed: false,
        observation: '无数据',
      );
    }

    try {
      switch (step.action) {
        case 'indicators':
          return _evalIndicators(step, bars);
        case 'score_technical':
          return _evalTechnicalScore(step, bars);
        case 'volume':
          return _evalVolume(step, bars);
        case 'support':
          return _evalSupport(step, bars);
        case 'factors':
          return _evalFactors(step, bars, quote);
        default:
          return StepResult(
            stepDescription: step.description,
            passed: false,
            observation: '未知action: ${step.action}',
          );
      }
    } catch (e) {
      return StepResult(
        stepDescription: step.description,
        passed: false,
        observation: '执行异常: $e',
      );
    }
  }

  StepResult _evalIndicators(WorkflowStep step, List<KlineBar> bars) {
    final summary = Indicators.summary(bars);
    final logic = step.checkLogic;
    final last = bars.length - 1;
    final price = bars[last].close;

    var passed = false;
    var observation = '';

    if (logic.contains('price_vs_ma20')) {
      final ma20 = summary['ma20'] as double?;
      final ma10 = summary['ma10'] as double?;
      final ma5 = summary['ma5'] as double?;
      if (logic.contains('above')) {
        passed = summary['price_vs_ma20'] == 'above';
        observation =
            'MA5(${_f(ma5)}) ${(ma5 ?? 0) > (ma10 ?? 0) ? ">" : "<"} MA10(${_f(ma10)}) ${(ma10 ?? 0) > (ma20 ?? 0) ? ">" : "<"} MA20(${_f(ma20)})';
        if (passed) {
          observation += ', 多头排列确认';
        } else {
          observation += ', 未形成多头排列';
        }
      }
    } else if (logic.contains('rsi')) {
      final rsiVal = summary['rsi'] as double?;
      if (rsiVal != null) {
        if (logic.contains('< 70')) {
          passed = rsiVal < 70;
        } else if (logic.contains('< 30')) {
          passed = rsiVal < 30;
        } else if (logic.contains('> 70')) {
          passed = rsiVal > 70;
        }
        observation =
            'RSI=${rsiVal.toStringAsFixed(0)}${passed ? ", 条件满足" : ", 条件不满足"}';
      } else {
        observation = 'RSI数据不足';
      }
    } else if (logic.contains('macd_histogram')) {
      final hist = summary['macd_hist'] as double?;
      passed = hist != null && hist > 0;
      observation = 'MACD柱线=${_f(hist)}${passed ? ", 动能向上" : ", 动能向下"}';
    } else if (logic.contains('high_20d')) {
      final high20 = bars
          .sublist(max(0, bars.length - 20))
          .map((b) => b.high)
          .reduce(max);
      passed = price >= high20;
      observation =
          '当前价${_f(price)} vs 20日高${_f(high20)}${passed ? ", 创新高" : ", 未突破"}';
    } else if (logic.contains('high_40d')) {
      final high40 = bars
          .sublist(max(0, bars.length - 40))
          .map((b) => b.high)
          .reduce(max);
      final threshold = logic.contains('0.95') ? 0.95 : 1.0;
      passed = price >= high40 * threshold;
      observation =
          '当前价${_f(price)} vs 40日高${_f(high40)}${threshold < 1 ? "(×$threshold)" : ""}${passed ? ", 接近/突破高点" : ", 距高点较远"}';
    } else if (logic.contains('price_vs_ma10')) {
      final ma10 = summary['ma10'] as double?;
      passed = ma10 != null && price > ma10;
      observation =
          '价格${_f(price)} vs MA10(${_f(ma10)})${passed ? " 在上方" : " 在下方"}';
    } else {
      observation = '未识别的指标逻辑: $logic';
    }

    return StepResult(
      stepDescription: step.description,
      passed: passed,
      observation: observation,
    );
  }

  StepResult _evalTechnicalScore(WorkflowStep step, List<KlineBar> bars) {
    final scoreData = Indicators.technicalScore(bars);
    final score = (scoreData['score'] as num?)?.toDouble() ?? 0;
    final signal = scoreData['signal'] as String? ?? 'unknown';

    var threshold = 60.0;
    final match = RegExp(r'score\s*>=?\s*(\d+)').firstMatch(step.checkLogic);
    if (match != null) threshold = double.parse(match.group(1)!);

    final passed = score >= threshold;
    final observation =
        '技术评分${score.toStringAsFixed(0)}/100 ($signal)${passed ? ", ≥$threshold通过" : ", <$threshold未达标"}';
    return StepResult(
      stepDescription: step.description,
      passed: passed,
      observation: observation,
    );
  }

  StepResult _evalVolume(WorkflowStep step, List<KlineBar> bars) {
    if (bars.length < 25) {
      return StepResult(
        stepDescription: step.description,
        passed: false,
        observation: '数据不足',
      );
    }
    final last = bars.length - 1;
    final recent5Vol =
        bars
            .sublist(bars.length - 5)
            .map((b) => b.volume)
            .reduce((a, b) => a + b) /
        5;
    final prev20Vol =
        bars
            .sublist(max(0, bars.length - 25), bars.length - 5)
            .map((b) => b.volume)
            .reduce((a, b) => a + b) /
        20;
    final volRatio = prev20Vol > 0 ? recent5Vol / prev20Vol : 1.0;

    final logic = step.checkLogic;
    var passed = false;
    var observation = '';

    if (logic.contains('volume_trend == decreasing') ||
        logic.contains('shrink')) {
      final v1 = bars[last - 2].volume,
          v2 = bars[last - 1].volume,
          v3 = bars[last].volume;
      passed = v1 > v2 && v2 > v3;
      observation =
          '近3日量: ${_vol(v1)}→${_vol(v2)}→${_vol(v3)}${passed ? ", 递减确认缩量" : ", 未明显缩量"}';
    } else if (logic.contains('volume_ratio')) {
      final match = RegExp(r'volume_ratio\s*>\s*([\d.]+)').firstMatch(logic);
      final threshold = match != null ? double.parse(match.group(1)!) : 1.5;
      passed = volRatio > threshold;
      observation =
          '量比${volRatio.toStringAsFixed(1)} vs 阈值$threshold${passed ? ", 放量确认" : ", 量能不足"}';
    } else if (logic.contains('net_inflow')) {
      passed = volRatio > 1.0 && bars[last].close > bars[last].open;
      observation =
          '量比${volRatio.toStringAsFixed(1)}+阳线=${passed ? "疑似资金流入" : "无明显流入信号"}';
    } else {
      observation = '量比${volRatio.toStringAsFixed(1)}';
      passed = volRatio > 0.8;
    }

    return StepResult(
      stepDescription: step.description,
      passed: passed,
      observation: observation,
    );
  }

  StepResult _evalSupport(WorkflowStep step, List<KlineBar> bars) {
    if (bars.length < 20) {
      return StepResult(
        stepDescription: step.description,
        passed: false,
        observation: '数据不足',
      );
    }
    final price = bars.last.close;
    final ma10 = Indicators.sma(bars, 10).last;
    final ma20 = Indicators.sma(bars, 20).last;

    double nearestDist = double.infinity;
    String nearestMA = '';

    if (ma10 != null) {
      final dist = ((price - ma10) / ma10 * 100).abs();
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestMA = 'MA10(${_f(ma10)})';
      }
    }
    if (ma20 != null) {
      final dist = ((price - ma20) / ma20 * 100).abs();
      if (dist < nearestDist) {
        nearestDist = dist;
        nearestMA = 'MA20(${_f(ma20)})';
      }
    }

    final match = RegExp(
      r'distance_pct\s*<\s*(\d+)',
    ).firstMatch(step.checkLogic);
    final threshold = match != null ? double.parse(match.group(1)!) : 3.0;

    final passed = nearestDist < threshold;
    final observation =
        '距最近支撑$nearestMA偏离${nearestDist.toStringAsFixed(1)}%${passed ? ", 接近支撑位" : ", 偏离过大"}';
    return StepResult(
      stepDescription: step.description,
      passed: passed,
      observation: observation,
    );
  }

  /// Evaluate fundamental factors using live StockQuote data (PE/PB/turnoverRate).
  StepResult _evalFactors(
    WorkflowStep step,
    List<KlineBar> bars,
    StockQuote? quote,
  ) {
    final logic = step.checkLogic;

    if (quote == null) {
      return StepResult(
        stepDescription: step.description,
        passed: true,
        observation: '实时行情未获取，基本面检查跳过',
      );
    }

    final observations = <String>[];
    var allPassed = true;

    // Parse and evaluate each condition in checkLogic
    // Supports: pe, pb, turnoverRate, marketCap (from StockQuote)
    // Soft-pass for: roe, fund_size, max_drawdown, return_3y_rank_pct (not on StockQuote)
    final conditions = logic.split('&&').map((s) => s.trim()).toList();
    for (final cond in conditions) {
      final result = _evalSingleFactor(cond, quote);
      observations.add(result.$2);
      if (!result.$1) allPassed = false;
    }

    return StepResult(
      stepDescription: step.description,
      passed: allPassed,
      observation: observations.join('; '),
    );
  }

  (bool, String) _evalSingleFactor(String condition, StockQuote quote) {
    // Parse: "field op value"
    final match = RegExp(r'(\w+)\s*([><=!]+)\s*([\d.]+)').firstMatch(condition);
    if (match == null) return (true, '无法解析: $condition');

    final field = match.group(1)!;
    final op = match.group(2)!;
    final threshold = double.parse(match.group(3)!);

    double? actual;
    String label;
    switch (field) {
      case 'pe':
        actual = quote.pe;
        label = 'PE';
      case 'pb':
        actual = quote.pb;
        label = 'PB';
      case 'turnoverRate':
        actual = quote.turnoverRate;
        label = '换手率';
      case 'marketCap':
        actual = quote.marketCap != null ? quote.marketCap! / 1e8 : null;
        label = '市值(亿)';
      default:
        return (true, '$field数据不可用(软通过)');
    }

    if (actual == null) return (true, '$label无数据(软通过)');

    final passed = switch (op) {
      '>' => actual > threshold,
      '>=' => actual >= threshold,
      '<' => actual < threshold,
      '<=' => actual <= threshold,
      '==' => (actual - threshold).abs() < 0.01,
      _ => true,
    };

    final actualStr = actual.toStringAsFixed(1);
    return (passed, '$label=$actualStr ${passed ? "✓" : "✗"} ($op$threshold)');
  }

  String _buildReasoningChain(
    String symbol,
    Strategy strategy,
    List<StepResult> results,
    double score,
    String decision, {
    double? stopLoss,
    double? targetPrice,
    double? positionPct,
  }) {
    final buf = StringBuffer();
    buf.writeln('## $symbol — ${strategy.name}');
    buf.writeln();

    for (var i = 0; i < results.length; i++) {
      final r = results[i];
      final step = strategy.steps[i];
      final icon = r.passed ? '✅' : (step.required ? '❌' : '⚠️');
      buf.writeln('${i + 1}. $icon ${step.description}: ${r.observation}');
      if (!r.passed && step.reasoning.isNotEmpty) {
        buf.writeln('   → ${step.reasoning}');
      }
    }

    buf.writeln();
    final decisionCN = decision == 'buy'
        ? '建议入场'
        : decision == 'watch'
        ? '观察等待'
        : '暂不操作';
    buf.writeln('综合评分: ${score.toStringAsFixed(0)}/100 | 决策: $decisionCN');

    if (decision == 'buy' && stopLoss != null && targetPrice != null) {
      buf.writeln(
        '止损: $stopLoss (ATR×2) | 目标: $targetPrice (ATR×3) | 仓位: ${((positionPct ?? 0.1) * 100).toStringAsFixed(0)}%',
      );
    }

    if (strategy.timesUsed >= 3) {
      buf.writeln(
        '历史胜率: ${(strategy.winRate * 100).toStringAsFixed(0)}% (${strategy.timesUsed}次)',
      );
    }

    return buf.toString();
  }

  double _maxDrawdown(List<double> returns) {
    var peak = 0.0, maxDD = 0.0, cumulative = 0.0;
    for (final r in returns) {
      cumulative += r;
      if (cumulative > peak) peak = cumulative;
      final dd = peak - cumulative;
      if (dd > maxDD) maxDD = dd;
    }
    return maxDD;
  }

  double _profitFactor(List<double> returns) {
    var totalProfit = 0.0, totalLoss = 0.0;
    for (final r in returns) {
      if (r > 0) {
        totalProfit += r;
      } else {
        totalLoss += r.abs();
      }
    }
    return totalLoss > 0
        ? totalProfit / totalLoss
        : totalProfit > 0
        ? 999.0
        : 0.0;
  }

  static String _f(double? v) => v == null ? '-' : v.toStringAsFixed(2);
  static String _vol(double v) => v >= 1e8
      ? '${(v / 1e8).toStringAsFixed(1)}亿'
      : '${(v / 1e4).toStringAsFixed(0)}万';
}

class _BacktestTrade {
  final String entryDate;
  final String exitDate;
  final double entryPrice;
  final double exitPrice;
  final int holdDays;
  final double returnPct;
  final String exitReason;

  _BacktestTrade({
    required this.entryDate,
    required this.exitDate,
    required this.entryPrice,
    required this.exitPrice,
    required this.holdDays,
    required this.returnPct,
    required this.exitReason,
  });

  Map<String, dynamic> toJson() => {
    'entry': '$entryDate @${entryPrice.toStringAsFixed(2)}',
    'exit': '$exitDate @${exitPrice.toStringAsFixed(2)}',
    'hold': '${holdDays}d',
    'return': '${returnPct >= 0 ? "+" : ""}${returnPct.toStringAsFixed(2)}%',
    'reason': exitReason,
  };
}
