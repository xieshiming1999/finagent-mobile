import 'dart:math';

import 'backtest_core.dart';
import 'backtest_strategies.dart';
import 'backtest_strategy_set.dart';

enum PositionSizing { fullCapital, fixedFraction, kelly, atrBased }

Map<String, dynamic> backtestEnhanced(
  List<Candle> candles,
  List<Trade> Function(List<Candle>) strategyFn, {
  double initialCapital = 100000,
  PositionSizing sizing = PositionSizing.fullCapital,
  double fixedFraction = 0.1,
  double stopLossPct = 0,
  double takeProfitPct = 0,
  double trailingStopPct = 0,
  double commissionPct = 0.1,
  double slippagePct = 0.05,
}) {
  final rawTrades = strategyFn(candles);
  final trades = <Map<String, dynamic>>[];
  var capital = initialCapital;
  var peakCapital = initialCapital;
  var maxDrawdown = 0.0;

  for (final trade in rawTrades) {
    double positionSize;
    switch (sizing) {
      case PositionSizing.fixedFraction:
        positionSize = capital * fixedFraction;
      case PositionSizing.kelly:
        final wins = trades.where((t) => (t['returnPct'] as double) > 0).length;
        final total = trades.length;
        final winRate = total > 0 ? wins / total : 0.5;
        final kellyFraction = min(max(winRate * 2 - 1, 0.01), 0.25);
        positionSize = capital * kellyFraction;
      case PositionSizing.atrBased:
        positionSize = capital * 0.02;
      default:
        positionSize = capital;
    }
    if (positionSize <= 0) continue;

    final shares = (positionSize / trade.entryPrice).floor();
    if (shares <= 0) continue;

    var exitPrice = trade.exitPrice;
    var stoppedOut = false;
    if (stopLossPct > 0 || takeProfitPct > 0 || trailingStopPct > 0) {
      var highWaterMark = trade.entryPrice;
      final entryIndex = candles.indexWhere((c) => c.date == trade.entryDate);
      final exitIndex = candles.indexWhere((c) => c.date == trade.exitDate);
      if (entryIndex >= 0 && exitIndex > entryIndex) {
        for (var i = entryIndex + 1; i <= exitIndex; i++) {
          if (candles[i].high > highWaterMark) highWaterMark = candles[i].high;
          if (stopLossPct > 0 &&
              candles[i].low <= trade.entryPrice * (1 - stopLossPct / 100)) {
            exitPrice = trade.entryPrice * (1 - stopLossPct / 100);
            stoppedOut = true;
            break;
          }
          if (takeProfitPct > 0 &&
              candles[i].high >= trade.entryPrice * (1 + takeProfitPct / 100)) {
            exitPrice = trade.entryPrice * (1 + takeProfitPct / 100);
            stoppedOut = true;
            break;
          }
          if (trailingStopPct > 0 &&
              candles[i].low <= highWaterMark * (1 - trailingStopPct / 100)) {
            exitPrice = highWaterMark * (1 - trailingStopPct / 100);
            stoppedOut = true;
            break;
          }
        }
      }
    }

    final grossReturn = (exitPrice - trade.entryPrice) / trade.entryPrice * 100;
    final commission =
        (trade.entryPrice + exitPrice) * shares * commissionPct / 100;
    final slippage =
        (trade.entryPrice + exitPrice) * shares * slippagePct / 100;
    final netPnl =
        (exitPrice - trade.entryPrice) * shares - commission - slippage;
    final netReturnPct = capital > 0 ? netPnl / capital * 100 : 0;

    capital += netPnl;
    if (capital > peakCapital) peakCapital = capital;
    final drawdown = peakCapital > 0
        ? (peakCapital - capital) / peakCapital * 100
        : 0.0;
    if (drawdown > maxDrawdown) maxDrawdown = drawdown;

    trades.add({
      'entry': '${trade.entryDate} @ ${trade.entryPrice.toStringAsFixed(2)}',
      'exit': '${trade.exitDate} @ ${exitPrice.toStringAsFixed(2)}',
      'shares': shares,
      'grossReturn': double.parse(grossReturn.toStringAsFixed(2)),
      'netPnl': double.parse(netPnl.toStringAsFixed(2)),
      'returnPct': double.parse(netReturnPct.toStringAsFixed(2)),
      if (stoppedOut) 'stoppedOut': true,
    });
  }

  final totalReturn = (capital - initialCapital) / initialCapital * 100;
  final winTrades = trades.where((t) => (t['returnPct'] as double) > 0);
  final annualFactor = candles.isNotEmpty ? 252 / candles.length : 1;
  final negativeReturns = trades
      .map((t) => t['returnPct'] as double)
      .where((r) => r < 0)
      .toList();
  final downsideDeviation = negativeReturns.isNotEmpty
      ? sqrt(
          negativeReturns.map((r) => r * r).reduce((a, b) => a + b) /
              negativeReturns.length,
        )
      : 1;
  final sortino = downsideDeviation > 0
      ? totalReturn * annualFactor / downsideDeviation
      : 0;

  return {
    'initialCapital': initialCapital,
    'finalCapital': double.parse(capital.toStringAsFixed(2)),
    'totalReturn': double.parse(totalReturn.toStringAsFixed(2)),
    'annualizedReturn': double.parse(
      (totalReturn * annualFactor).toStringAsFixed(2),
    ),
    'totalTrades': trades.length,
    'winRate': trades.isNotEmpty
        ? double.parse(
            (winTrades.length / trades.length * 100).toStringAsFixed(1),
          )
        : 0,
    'maxDrawdown': double.parse(maxDrawdown.toStringAsFixed(2)),
    'sortino': double.parse(sortino.toStringAsFixed(2)),
    'positionSizing': sizing.name,
    if (stopLossPct > 0) 'stopLoss': stopLossPct,
    if (takeProfitPct > 0) 'takeProfit': takeProfitPct,
    if (trailingStopPct > 0) 'trailingStop': trailingStopPct,
    'recentTrades': trades.reversed.take(5).toList(),
  };
}

Map<String, dynamic> optimizeStrategy(
  List<Candle> candles,
  String strategyName,
  Map<String, List<dynamic>> paramGrid,
) {
  final results = <Map<String, dynamic>>[];
  final paramNames = paramGrid.keys.toList();
  final combinations = _cartesianProduct(paramGrid.values.toList());

  for (final combo in combinations) {
    final params = <String, dynamic>{};
    for (var i = 0; i < paramNames.length; i++) {
      params[paramNames[i]] = combo[i];
    }

    final strategyFn = _getParameterizedStrategy(strategyName, params);
    if (strategyFn == null) continue;

    final trades = strategyFn(candles);
    final metrics = calcMetrics(trades);
    results.add({
      'params': params,
      'totalReturn': metrics['total_return_pct'] ?? 0,
      'winRate': metrics['win_rate_pct'] ?? 0,
      'sharpe': metrics['sharpe_ratio'] ?? 0,
      'maxDrawdown': metrics['max_drawdown_pct'] ?? 0,
      'trades': metrics['total_trades'] ?? 0,
    });
  }

  results.sort(
    (a, b) => ((b['totalReturn'] as num?) ?? 0).compareTo(
      (a['totalReturn'] as num?) ?? 0,
    ),
  );

  return {
    'strategy': strategyName,
    'combinations': combinations.length,
    'top5': results.take(5).toList(),
  };
}

Map<String, dynamic> monteCarloValidation(
  List<double> dailyReturns, {
  int simulations = 1000,
}) {
  if (dailyReturns.length < 20) return {'error': 'need 20+ daily returns'};

  final rng = Random(42);
  double calcSharpe(List<double> returns) {
    final mean = returns.reduce((a, b) => a + b) / returns.length;
    final variance =
        returns.map((r) => (r - mean) * (r - mean)).reduce((a, b) => a + b) /
        returns.length;
    final std = sqrt(variance);
    return std > 0 ? mean / std * sqrt(252) : 0;
  }

  final observedSharpe = calcSharpe(dailyReturns);
  var betterCount = 0;
  for (var i = 0; i < simulations; i++) {
    final shuffled = List<double>.from(dailyReturns)..shuffle(rng);
    final sharpe = calcSharpe(shuffled);
    if (sharpe >= observedSharpe) betterCount++;
  }

  final pValue = betterCount / simulations;
  return {
    'observedSharpe': double.parse(observedSharpe.toStringAsFixed(3)),
    'pValue': double.parse(pValue.toStringAsFixed(3)),
    'significant': pValue < 0.05,
    'interpretation': pValue < 0.05
        ? '策略显著优于随机(p<0.05),存在真实alpha'
        : '策略未显著优于随机(p>=0.05),可能是运气',
  };
}

List<Trade> Function(List<Candle>)? _getParameterizedStrategy(
  String name,
  Map<String, dynamic> params,
) {
  return switch (name) {
    'rsi' => (candles) => strategyRSI(
      candles,
      period: params['period'] ?? 14,
      oversold: (params['oversold'] as num?)?.toDouble() ?? 40,
      overbought: (params['overbought'] as num?)?.toDouble() ?? 60,
    ),
    'bollinger' => (candles) => strategyBollinger(
      candles,
      period: params['period'] ?? 20,
      stdMult: (params['stdMult'] as num?)?.toDouble() ?? 2,
    ),
    'macd' => (candles) => strategyMACD(
      candles,
      fast: params['fast'] ?? 12,
      slow: params['slow'] ?? 26,
      signal: params['signal'] ?? 9,
    ),
    'ema_cross' => (candles) => strategyEMACross(
      candles,
      fastPeriod: params['fast'] ?? 20,
      slowPeriod: params['slow'] ?? 50,
    ),
    'ma_golden_cross' => (candles) => strategyMAGoldenCross(
      candles,
      shortPeriod: params['short'] ?? 5,
      longPeriod: params['long'] ?? 20,
    ),
    _ => null,
  };
}

List<List<dynamic>> _cartesianProduct(List<List<dynamic>> lists) {
  if (lists.isEmpty) return [[]];
  final result = <List<dynamic>>[];
  final first = lists.first;
  final rest = _cartesianProduct(lists.sublist(1));
  for (final item in first) {
    for (final combo in rest) {
      result.add([item, ...combo]);
    }
  }
  return result;
}
