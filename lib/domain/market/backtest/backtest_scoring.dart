import 'dart:math';

import 'backtest_core.dart';
import 'backtest_execution.dart';
import 'backtest_strategies.dart';
import 'backtest_strategy_set.dart';

Map<String, dynamic> scoreBacktest(
  List<Candle> candles,
  List<Trade> trades,
  Map<String, dynamic> metrics, {
  String strategy = '',
}) {
  if (trades.isEmpty) {
    return {
      'score': 0,
      'grade': 'D',
      'components': {},
      'warnings': ['No trades generated'],
    };
  }

  final totalReturn = (metrics['total_return_pct'] as num?)?.toDouble() ?? 0;
  final maxDrawdown = ((metrics['max_drawdown_pct'] as num?)?.toDouble() ?? 0)
      .abs();
  final sharpe = (metrics['sharpe_ratio'] as num?)?.toDouble() ?? 0;
  final returnsScore = min(max(totalReturn / 30.0, 0.0), 1.0) * 100;
  final riskScore = max(0.0, 1.0 - maxDrawdown / 20.0) * 100;

  final halfIndex = candles.length ~/ 2;
  var stabilityScore = 50.0;
  String? overfitWarning;
  if (halfIndex > 30 && trades.length >= 4) {
    final firstHalfTrades = trades.where((trade) {
      final index = candles.indexWhere((c) => c.date == trade.entryDate);
      return index >= 0 && index < halfIndex;
    }).toList();
    final secondHalfTrades = trades.where((trade) {
      final index = candles.indexWhere((c) => c.date == trade.entryDate);
      return index >= halfIndex;
    }).toList();

    if (firstHalfTrades.isNotEmpty && secondHalfTrades.isNotEmpty) {
      final firstReturn = _compoundReturn(firstHalfTrades);
      final secondReturn = _compoundReturn(secondHalfTrades);
      final sameSign =
          (firstReturn >= 0 && secondReturn >= 0) ||
          (firstReturn < 0 && secondReturn < 0);
      if (!sameSign) {
        stabilityScore = 20.0;
        overfitWarning =
            '前半段${firstReturn >= 0 ? "盈利" : "亏损"}后半段${secondReturn >= 0 ? "盈利" : "亏损"},一致性差';
      } else if (firstReturn > 0 && secondReturn > 0) {
        final ratio = firstReturn > secondReturn
            ? secondReturn / firstReturn
            : firstReturn / secondReturn;
        stabilityScore = min(ratio * 100, 100.0);
        if (firstReturn > secondReturn * 2.5) {
          overfitWarning =
              '前半段收益(${firstReturn.toStringAsFixed(1)}%)远高于后半段(${secondReturn.toStringAsFixed(1)}%),存在过拟合风险';
          stabilityScore = min(stabilityScore, 30.0);
        }
      } else {
        stabilityScore = 60.0;
      }
    }
  }

  final efficiencyScore = min(max(sharpe / 2.0, 0.0), 1.0) * 100;
  var significanceScore = 50.0;
  if (trades.length >= 10) {
    final dailyReturns = trades.map((trade) => trade.returnPct / 100).toList();
    final monteCarlo = monteCarloValidation(dailyReturns, simulations: 500);
    final pValue = (monteCarlo['pValue'] as num?)?.toDouble() ?? 0.5;
    significanceScore = min((1.0 - pValue) * 100, 100.0);
  }

  final score =
      returnsScore * 0.25 +
      riskScore * 0.25 +
      stabilityScore * 0.20 +
      efficiencyScore * 0.15 +
      significanceScore * 0.15;
  final turnover = trades.length / max(candles.length / 252.0, 0.1);
  final fitness = sharpe * sqrt(totalReturn.abs() / max(turnover, 0.1));
  final grade = score >= 80
      ? 'A'
      : score >= 60
      ? 'B'
      : score >= 40
      ? 'C'
      : 'D';

  final warnings = <String>[];
  if (overfitWarning != null) warnings.add(overfitWarning);
  if (trades.length < 5) warnings.add('交易次数过少(${trades.length}次),统计意义有限');
  if (maxDrawdown > 30) {
    warnings.add('最大回撤${maxDrawdown.toStringAsFixed(1)}%较大,注意风险控制');
  }

  final recommendation = score >= 80
      ? '策略表现优秀,可信度高,建议实盘使用(配合止损)'
      : score >= 60
      ? '策略表现中等偏上,建议优化参数或配合其他条件使用'
      : score >= 40
      ? '策略一般,建议更换策略或调整参数'
      : '策略表现差,不建议使用';

  double round1(double value) => double.parse(value.toStringAsFixed(1));
  return {
    'score': round1(score),
    'grade': grade,
    'fitness': double.parse(fitness.toStringAsFixed(2)),
    'components': {
      'returns': round1(returnsScore),
      'risk': round1(riskScore),
      'stability': round1(stabilityScore),
      'efficiency': round1(efficiencyScore),
      'significance': round1(significanceScore),
    },
    'warnings': warnings,
    'recommendation': recommendation,
    'overfit_risk': stabilityScore < 30
        ? 'high'
        : stabilityScore < 60
        ? 'medium'
        : 'low',
  };
}

Map<String, dynamic> detectCurrentSignal(
  List<Candle> candles,
  String strategy,
) {
  if (candles.length < 30) {
    return {'status': 'insufficient_data', 'suggestion': '数据不足,无法判断当前信号'};
  }

  final closes = candles.map((c) => c.close).toList();
  final lastIndex = candles.length - 1;
  switch (strategy) {
    case 'rsi':
      final rsi = calcRSI(closes);
      final value = rsi[lastIndex];
      if (value == null) return _noSignal();
      if (value < 40) {
        return _signal(
          'triggered',
          'RSI',
          value,
          40,
          'RSI=${value.toStringAsFixed(1)}<40 已进入超卖区,满足入场条件',
        );
      }
      if (value < 50) {
        return _signal(
          'approaching',
          'RSI',
          value,
          40,
          'RSI=${value.toStringAsFixed(1)} 接近超卖区(40),可设Monitor等待',
        );
      }
      return _signal(
        'far',
        'RSI',
        value,
        40,
        'RSI=${value.toStringAsFixed(1)} 距离超卖区较远,暂无入场信号',
      );
    case 'bollinger':
      final bollinger = calcBollinger(closes);
      final lower = bollinger.lower[lastIndex];
      final middle = bollinger.middle[lastIndex];
      if (lower == null || middle == null) return _noSignal();
      final price = closes[lastIndex];
      final distance = (price - lower) / (middle - lower);
      if (price < lower) {
        return _signal(
          'triggered',
          'BOLL',
          price,
          lower,
          '价格(${price.toStringAsFixed(2)})已跌破布林下轨(${lower.toStringAsFixed(2)}),满足入场',
        );
      }
      if (distance < 0.2) {
        return _signal(
          'approaching',
          'BOLL',
          price,
          lower,
          '价格接近布林下轨(距离${(distance * 100).toStringAsFixed(0)}%),可关注',
        );
      }
      return _signal('far', 'BOLL', price, lower, '价格距布林下轨较远,暂无入场信号');
    case 'macd':
      final macd = calcMACD(closes);
      final value = macd.macd[lastIndex];
      final signal = macd.signal[lastIndex];
      final prevValue = lastIndex > 0 ? macd.macd[lastIndex - 1] : null;
      final prevSignal = lastIndex > 0 ? macd.signal[lastIndex - 1] : null;
      if (value == null || signal == null || prevValue == null || prevSignal == null) {
        return _noSignal();
      }
      if (prevValue < prevSignal && value >= signal) {
        return _signal('triggered', 'MACD', value, signal, 'MACD金叉已出现,满足入场条件');
      }
      final diff = value - signal;
      if (diff < 0 && diff.abs() < signal.abs() * 0.1) {
        return _signal('approaching', 'MACD', value, signal, 'MACD接近信号线,金叉即将形成');
      }
      return _signal('far', 'MACD', value, signal, 'MACD距离金叉较远,暂无入场信号');
    case 'ema_cross':
      final emaFast = calcEMA(closes, 20);
      final emaSlow = calcEMA(closes, 50);
      final fast = emaFast[lastIndex];
      final slow = emaSlow[lastIndex];
      final prevFast = lastIndex > 0 ? emaFast[lastIndex - 1] : null;
      final prevSlow = lastIndex > 0 ? emaSlow[lastIndex - 1] : null;
      if (fast == null || slow == null || prevFast == null || prevSlow == null) {
        return _noSignal();
      }
      if (prevFast < prevSlow && fast >= slow) {
        return _signal('triggered', 'EMA', fast, slow, 'EMA20上穿EMA50金叉,满足入场条件');
      }
      final gap = (fast - slow) / slow * 100;
      if (gap > -1 && gap < 0) {
        return _signal(
          'approaching',
          'EMA',
          fast,
          slow,
          'EMA20接近EMA50(差距${gap.toStringAsFixed(2)}%),金叉即将形成',
        );
      }
      if (fast > slow) {
        return _signal('holding', 'EMA', fast, slow, 'EMA多头排列中(EMA20>EMA50),趋势延续');
      }
      return _signal(
        'far',
        'EMA',
        fast,
        slow,
        'EMA20在EMA50下方(差距${gap.toStringAsFixed(1)}%),尚无金叉信号',
      );
    case 'supertrend':
      final highs = candles.map((c) => c.high).toList();
      final lows = candles.map((c) => c.low).toList();
      final direction = calcSupertrend(highs, lows, closes);
      final current = direction[lastIndex];
      final previous = lastIndex > 0 ? direction[lastIndex - 1] : null;
      if (current == null || previous == null) return _noSignal();
      if (previous == -1 && current == 1) {
        return _signal('triggered', 'Supertrend', current.toDouble(), 1, 'Supertrend翻多,满足入场条件');
      }
      if (current == 1) {
        return _signal('holding', 'Supertrend', current.toDouble(), 1, 'Supertrend处于多头状态,趋势延续');
      }
      return _signal('far', 'Supertrend', current.toDouble(), 1, 'Supertrend处于空头状态,暂无入场信号');
    case 'donchian':
      final highs = candles.map((c) => c.high).toList();
      final lows = candles.map((c) => c.low).toList();
      final donchian = calcDonchian(highs, lows);
      final upper = donchian.upper[lastIndex];
      if (upper == null) return _noSignal();
      final price = closes[lastIndex];
      final previousHigh = highs[lastIndex - 1];
      if (previousHigh > upper) {
        return _signal('triggered', 'Donchian', price, upper, '突破唐奇安通道上轨(${upper.toStringAsFixed(2)}),满足入场');
      }
      final distance = (upper - price) / price * 100;
      if (distance < 2) {
        return _signal('approaching', 'Donchian', price, upper, '价格距上轨仅${distance.toStringAsFixed(1)}%,接近突破');
      }
      return _signal('far', 'Donchian', price, upper, '价格距上轨${distance.toStringAsFixed(1)}%,暂无突破信号');
    default:
      return {'status': 'unsupported', 'suggestion': '不支持检测 $strategy 的当前信号'};
  }
}

Map<String, dynamic> strategyComposite(
  List<Candle> candles,
  List<String> strategyNames, {
  String mode = 'majority',
}) {
  if (strategyNames.isEmpty) return {'error': 'No strategies specified'};

  final strategies = <String, Function>{};
  for (final name in strategyNames) {
    final strategyFn = strategyMap[name];
    if (strategyFn != null) strategies[name] = strategyFn;
  }
  if (strategies.isEmpty) return {'error': 'No valid strategies found'};

  final entryBars = <String, Set<int>>{};
  final exitBars = <String, Set<int>>{};
  for (final entry in strategies.entries) {
    final trades = entry.value(candles) as List<Trade>;
    final entries = <int>{};
    final exits = <int>{};
    for (final trade in trades) {
      final entryIndex = candles.indexWhere((c) => c.date == trade.entryDate);
      final exitIndex = candles.indexWhere((c) => c.date == trade.exitDate);
      if (entryIndex >= 0) entries.add(entryIndex);
      if (exitIndex >= 0) exits.add(exitIndex);
    }
    entryBars[entry.key] = entries;
    exitBars[entry.key] = exits;
  }

  final threshold = switch (mode) {
    'all_agree' => strategies.length,
    'any_trigger' => 1,
    _ => (strategies.length / 2).ceil(),
  };

  final compositeTrades = <Trade>[];
  var inPosition = false;
  var entryIndex = 0;
  for (var i = 0; i < candles.length; i++) {
    if (!inPosition) {
      var entryCount = 0;
      for (final bars in entryBars.values) {
        if (bars.contains(i)) entryCount++;
      }
      if (entryCount >= threshold) {
        inPosition = true;
        entryIndex = i;
      }
    } else {
      var exitCount = 0;
      for (final bars in exitBars.values) {
        if (bars.contains(i)) exitCount++;
      }
      if (exitCount >= threshold) {
        compositeTrades.add(
          Trade(
            entryDate: candles[entryIndex].date,
            entryPrice: candles[entryIndex].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          ),
        );
        inPosition = false;
      }
    }
  }
  if (inPosition) {
    compositeTrades.add(
      Trade(
        entryDate: candles[entryIndex].date,
        entryPrice: candles[entryIndex].close,
        exitDate: candles.last.date,
        exitPrice: candles.last.close,
      ),
    );
  }

  final metrics = calcMetrics(compositeTrades);
  final score = scoreBacktest(
    candles,
    compositeTrades,
    metrics,
    strategy: 'composite_$mode',
  );
  final individualScores = <Map<String, dynamic>>[];
  for (final entry in strategies.entries) {
    final trades = entry.value(candles) as List<Trade>;
    final metrics = calcMetrics(trades);
    final individualScore = scoreBacktest(
      candles,
      trades,
      metrics,
      strategy: entry.key,
    );
    individualScores.add({
      'strategy': entry.key,
      'score': individualScore['score'],
      'grade': individualScore['grade'],
      'total_return_pct': metrics['total_return_pct'],
    });
  }

  return {
    'mode': mode,
    'strategies': strategyNames.where(strategies.containsKey).toList(),
    'threshold': '$threshold/${strategies.length}',
    'metrics': metrics,
    'score': score,
    'total_trades': compositeTrades.length,
    'individual': individualScores,
    'improvement': _calcImprovement(score, individualScores),
  };
}

double _compoundReturn(List<Trade> trades) {
  var capital = 1.0;
  for (final trade in trades) {
    capital *= (1 + trade.returnPct / 100);
  }
  return (capital - 1.0) * 100;
}

Map<String, dynamic> _signal(
  String status,
  String indicator,
  double current,
  double threshold,
  String suggestion,
) => {
  'status': status,
  'indicator': indicator,
  'currentValue': double.parse(current.toStringAsFixed(2)),
  'threshold': double.parse(threshold.toStringAsFixed(2)),
  'suggestion': suggestion,
};

Map<String, dynamic> _noSignal() => {
  'status': 'insufficient_data',
  'suggestion': '指标数据不足',
};

Map<String, dynamic> _calcImprovement(
  Map<String, dynamic> compositeScore,
  List<Map<String, dynamic>> individuals,
) {
  final compositeValue = (compositeScore['score'] as num?)?.toDouble() ?? 0;
  final averageIndividual = individuals.isEmpty
      ? 0.0
      : individuals
                .map((score) => (score['score'] as num?)?.toDouble() ?? 0)
                .reduce((a, b) => a + b) /
            individuals.length;
  final bestIndividual = individuals.isEmpty
      ? 0.0
      : individuals
            .map((score) => (score['score'] as num?)?.toDouble() ?? 0)
            .reduce(max);
  return {
    'vs_average': double.parse((compositeValue - averageIndividual).toStringAsFixed(1)),
    'vs_best': double.parse((compositeValue - bestIndividual).toStringAsFixed(1)),
    'conclusion': compositeValue > bestIndividual
        ? '组合优于单一最佳策略(+${(compositeValue - bestIndividual).toStringAsFixed(1)}分)'
        : compositeValue > averageIndividual
        ? '组合优于平均但不如最佳单一策略'
        : '组合未带来改善,建议使用单一最佳策略',
  };
}
