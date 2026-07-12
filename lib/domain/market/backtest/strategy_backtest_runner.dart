import 'dart:math';

import 'backtest_core.dart';
import 'strategy_indicator_calculators.dart';

Map<String, dynamic> runStrategySpecBacktest({
  required Map<String, dynamic> validation,
  required Map<String, dynamic> spec,
  required List<Candle> candles,
  required String symbol,
  double? outOfSampleRatio,
  int? walkForwardFolds,
}) {
  final result = _runStrategySpecBacktestCore(
    validation: validation,
    spec: spec,
    candles: candles,
    symbol: symbol,
  );
  if (outOfSampleRatio != null) {
    result['outOfSample'] = _outOfSampleEvidence(
      validation: validation,
      spec: spec,
      candles: candles,
      symbol: symbol,
      ratio: outOfSampleRatio,
    );
  }
  if (walkForwardFolds != null) {
    result['walkForward'] = _walkForwardEvidence(
      validation: validation,
      spec: spec,
      candles: candles,
      symbol: symbol,
      requestedFolds: walkForwardFolds,
    );
  }
  return result;
}

Map<String, dynamic> _runStrategySpecBacktestCore({
  required Map<String, dynamic> validation,
  required Map<String, dynamic> spec,
  required List<Candle> candles,
  required String symbol,
}) {
  final dataRequirements = _mapOf(spec['dataRequirements']);
  final minBars =
      (dataRequirements?['minBars'] is num
              ? dataRequirements!['minBars'] as num
              : null)
          ?.toInt() ??
      120;
  if (candles.length < minBars) {
    throw ArgumentError(
      'insufficient data for custom strategy: got ${candles.length} bars, need $minBars',
    );
  }

  final values = computeStrategyIndicators(spec, candles);
  final atrStopValues = _hasExitType(spec['exit'], 'atr_stop_loss')
      ? _atrValues(candles, _atrStopPeriod(spec['exit']))
      : const <double?>[];
  const capital = 100000.0;
  var cash = capital;
  var shares = 0;
  var entryPrice = 0.0;
  var entryDate = '';
  var entryIndex = -1;
  double? entryAtrStopDistance;
  var highWaterPrice = 0.0;
  var peakEquity = capital;
  var maxDrawdown = 0.0;
  final returns = <double>[];
  final trades = <Map<String, dynamic>>[];
  var entrySignalCount = 0;
  var exitSignalCount = 0;
  var stopExitCount = 0;
  final cost = Map<String, dynamic>.from(_mapOf(spec['cost']) ?? const {});
  final commissionPct =
      ((cost['commissionPct'] as num?)?.toDouble() ?? 0.1) / 100;
  final slippagePct = ((cost['slippagePct'] as num?)?.toDouble() ?? 0.05) / 100;
  final sizing = Map<String, dynamic>.from(
    _mapOf(spec['positionSizing']) ?? const {'type': 'full_capital'},
  );

  for (var i = 1; i < candles.length; i++) {
    final price = candles[i].close;
    final entrySignal = _evaluateRuleGroup(spec['entry'], values, i);
    if (shares == 0 && entrySignal) {
      entrySignalCount++;
      final budget = _entryBudget(cash, sizing, returns);
      shares = (budget / price / 100).floor() * 100;
      if (shares > 0) {
        entryPrice = price;
        entryDate = candles[i].date;
        entryIndex = i;
        entryAtrStopDistance = _atrStopDistance(spec['exit'], atrStopValues, i);
        highWaterPrice = price;
        cash -= shares * price * (1 + commissionPct + slippagePct);
      }
    } else if (shares > 0) {
      highWaterPrice = max(highWaterPrice, price);
      final stop = _stopExit(
        spec['exit'],
        entryPrice,
        price,
        highWaterPrice,
        entryIndex >= 0 ? i - entryIndex : 0,
        entryAtrStopDistance,
      );
      final exitSignal = _evaluateRuleGroup(spec['exit'], values, i);
      if (stop != null || exitSignal) {
        if (stop != null) {
          stopExitCount++;
        } else {
          exitSignalCount++;
        }
        cash += shares * price * (1 - commissionPct - slippagePct);
        final returnPct = (price - entryPrice) / entryPrice;
        returns.add(returnPct);
        trades.add({
          'entryDate': entryDate,
          'entryPrice': entryPrice,
          'exitDate': candles[i].date,
          'exitPrice': price,
          'shares': shares,
          'returnPct': _round(returnPct * 100),
          'reason': stop ?? 'rule_exit',
        });
        shares = 0;
        entryIndex = -1;
        entryAtrStopDistance = null;
        highWaterPrice = 0.0;
      }
    }
    final equity = cash + shares * price;
    peakEquity = max(peakEquity, equity);
    maxDrawdown = max(
      maxDrawdown,
      peakEquity > 0 ? (peakEquity - equity) / peakEquity : 0,
    );
  }

  final finalEquity = cash + shares * candles.last.close;
  final totalReturn = (finalEquity - capital) / capital;
  final wins = returns.where((value) => value > 0).length;
  final mean = returns.isEmpty
      ? 0.0
      : returns.reduce((a, b) => a + b) / returns.length;
  final variance = returns.length <= 1
      ? 0.0
      : returns
                .map((value) => pow(value - mean, 2).toDouble())
                .reduce((a, b) => a + b) /
            (returns.length - 1);
  final std = sqrt(variance);
  final riskRewardEvidence = _riskRewardEvidence(returns);
  final metrics = {
    'totalReturnPct': _round(totalReturn * 100),
    'maxDrawdownPct': _round(maxDrawdown * 100),
    'winRatePct': returns.isEmpty ? 0 : _round(wins / returns.length * 100),
    'sharpeRatio': std > 0 ? _round(mean / std * sqrt(252)) : 0,
    'tradeCount': trades.length,
    'profitFactor': riskRewardEvidence['profitFactor'],
    'payoffRatio': riskRewardEvidence['payoffRatio'],
    'expectancyPct': riskRewardEvidence['expectancyPct'],
  };
  final benchmarkEvidence = _benchmarkEvidence(
    candles: candles,
    strategyReturnPct: metrics['totalReturnPct'] as double,
  );
  final signals = {
    'entrySignalCount': entrySignalCount,
    'exitSignalCount': exitSignalCount,
    'stopExitCount': stopExitCount,
    'completedTradeCount': trades.length,
    'openPosition': shares > 0,
    'openPositionShares': shares,
    'noSignalReason': _noSignalReason(
      entrySignalCount: entrySignalCount,
      exitSignalCount: exitSignalCount,
      stopExitCount: stopExitCount,
      tradeCount: trades.length,
      openPosition: shares > 0,
    ),
  };

  return {
    'action': 'custom_strategy_backtest',
    'symbol': symbol,
    'strategyId': validation['strategyId'],
    'version': validation['version'],
    'status': 'backtested',
    'actualStartDate': candles.first.date,
    'actualEndDate': candles.last.date,
    'bars': candles.length,
    'validationSummary': validation['validationSummary'],
    'validationIssues': validation['validationIssues'] ?? const [],
    'unsupportedDetails': validation['unsupportedDetails'] ?? const [],
    'dataRequirements': validation['dataRequirements'],
    'assumptions': {
      'commissionPct': cost['commissionPct'] ?? 0.1,
      'slippagePct': cost['slippagePct'] ?? 0.05,
      'positionSizing': sizing,
    },
    'validation': validation,
    'metrics': metrics,
    'benchmarkEvidence': benchmarkEvidence,
    'signals': signals,
    'lifecycleAdvice': _backtestLifecycleAdvice(
      metrics: metrics,
      signals: signals,
    ),
    'riskEvidence': _riskEvidence(
      metrics: metrics,
      signals: signals,
      riskRewardEvidence: riskRewardEvidence,
      assumptions: {
        'commissionPct': cost['commissionPct'] ?? 0.1,
        'slippagePct': cost['slippagePct'] ?? 0.05,
        'positionSizing': sizing,
      },
    ),
    'riskRewardEvidence': riskRewardEvidence,
    'recentTrades': trades.length <= 5
        ? trades
        : trades.sublist(trades.length - 5),
  };
}

Map<String, dynamic> _backtestLifecycleAdvice({
  required Map<String, dynamic> metrics,
  required Map<String, dynamic> signals,
}) {
  final tradeCount = ((metrics['tradeCount'] as num?) ?? 0).toInt();
  return {
    'status': 'saveable_backtest_evidence',
    'saveable': true,
    'runnableAfterSave': true,
    'evidenceStatus': 'backtested',
    'nextActions': ['custom_strategy_save', 'custom_strategy_run'],
    'zeroTradeStillSaveable': tradeCount == 0,
    'boundary': tradeCount == 0
        ? 'Zero completed trades is a backtest result, not a validation failure. Save/rerun is valid when the user requested lifecycle verification; report zero trades as an evidence boundary.'
        : 'Backtested evidence can be saved and rerun by strategyId when the user requested lifecycle verification.',
    'signals': signals,
  };
}

Map<String, dynamic> _benchmarkEvidence({
  required List<Candle> candles,
  required double strategyReturnPct,
}) {
  final startPrice = candles.first.close;
  final endPrice = candles.last.close;
  final benchmarkReturnPct = startPrice > 0
      ? _round(((endPrice - startPrice) / startPrice) * 100)
      : 0.0;
  return {
    'mode': 'buy_and_hold_close_to_close',
    'startDate': candles.first.date,
    'endDate': candles.last.date,
    'startPrice': _round(startPrice),
    'endPrice': _round(endPrice),
    'benchmarkReturnPct': benchmarkReturnPct,
    'strategyReturnPct': strategyReturnPct,
    'excessReturnPct': _round(strategyReturnPct - benchmarkReturnPct),
    'assumption':
        'Benchmark uses first/last close over the same data window; it is reference evidence, not an investable execution simulation.',
  };
}

Map<String, dynamic> _riskEvidence({
  required Map<String, dynamic> metrics,
  required Map<String, dynamic> signals,
  required Map<String, dynamic> riskRewardEvidence,
  required Map<String, dynamic> assumptions,
}) {
  final maxDrawdown = ((metrics['maxDrawdownPct'] as num?) ?? 0).toDouble();
  final tradeCount = ((metrics['tradeCount'] as num?) ?? 0).toInt();
  final stopExitCount = ((signals['stopExitCount'] as num?) ?? 0).toInt();
  final openPosition = signals['openPosition'] == true;
  final noSignalReason = signals['noSignalReason'];
  return {
    'status': 'evaluated',
    'maxDrawdownPct': metrics['maxDrawdownPct'],
    'riskLevel': _riskLevel(maxDrawdown),
    'tradeCount': tradeCount,
    'stopExitCount': stopExitCount,
    'openPosition': openPosition,
    'noSignalReason': noSignalReason,
    'feesAndSlippage': {
      'commissionPct': assumptions['commissionPct'],
      'slippagePct': assumptions['slippagePct'],
      'applied': true,
    },
    'positionSizing': assumptions['positionSizing'],
    'riskRewardEvidence': riskRewardEvidence,
    'warnings': [
      if (tradeCount == 0)
        'no completed trades; do not infer strategy profitability',
      if (tradeCount > 0 && riskRewardEvidence['payoffRatio'] == null)
        'no losing trades in this window; payoff ratio is undefined and should not be treated as guaranteed risk/reward',
      if (tradeCount > 0 &&
          (riskRewardEvidence['expectancyPct'] as num? ?? 0) <= 0)
        'average trade expectancy is non-positive in this backtest window',
      if (openPosition)
        'backtest ended with an open position; final risk is mark-to-market only',
      if (maxDrawdown >= 20)
        'historical drawdown is high; require stronger risk controls before trade preparation',
    ],
    'tradeBoundary':
        'Risk evidence is backtest-only. Trade sizing or simulated orders require explicit user confirmation and post-action readback.',
  };
}

String _riskLevel(double maxDrawdownPct) {
  if (maxDrawdownPct >= 20) return 'high';
  if (maxDrawdownPct >= 10) return 'medium';
  return 'low';
}

Map<String, dynamic> _riskRewardEvidence(List<double> returns) {
  final wins = returns.where((value) => value > 0).toList();
  final losses = returns.where((value) => value < 0).toList();
  final grossWin = wins.fold<double>(0, (sum, value) => sum + value);
  final grossLoss = losses.fold<double>(0, (sum, value) => sum + value.abs());
  final avgWin = wins.isEmpty ? null : grossWin / wins.length;
  final avgLoss = losses.isEmpty ? null : grossLoss / losses.length;
  final expectancy = returns.isEmpty
      ? 0.0
      : returns.reduce((a, b) => a + b) / returns.length;
  return {
    'status': returns.isEmpty ? 'no_completed_trades' : 'evaluated',
    'tradeCount': returns.length,
    'winningTradeCount': wins.length,
    'losingTradeCount': losses.length,
    'grossWinPct': _round(grossWin * 100),
    'grossLossPct': _round(grossLoss * 100),
    'averageWinPct': avgWin == null ? null : _round(avgWin * 100),
    'averageLossPct': avgLoss == null ? null : _round(avgLoss * 100),
    'payoffRatio': avgWin != null && avgLoss != null && avgLoss > 0
        ? _round(avgWin / avgLoss)
        : null,
    'profitFactor': grossLoss > 0 ? _round(grossWin / grossLoss) : null,
    'expectancyPct': _round(expectancy * 100),
    'bestTradePct': returns.isEmpty ? null : _round(returns.reduce(max) * 100),
    'worstTradePct': returns.isEmpty ? null : _round(returns.reduce(min) * 100),
    'interpretation':
        'Risk/reward evidence is computed from completed backtest trades only; it excludes open-position future outcomes and is not a trade guarantee.',
  };
}

Map<String, dynamic> _outOfSampleEvidence({
  required Map<String, dynamic> validation,
  required Map<String, dynamic> spec,
  required List<Candle> candles,
  required String symbol,
  required double ratio,
}) {
  final holdoutRatio = ratio.clamp(0.1, 0.5).toDouble();
  final splitIndex = (candles.length * (1 - holdoutRatio)).floor();
  final minBars =
      ((_mapOf(spec['dataRequirements'])?['minBars'] as num?)?.toInt() ?? 120);
  final minHoldoutBars = minBars;
  if (splitIndex < minBars || candles.length - splitIndex < minHoldoutBars) {
    return {
      'mode': 'chronological_holdout',
      'status': 'skipped',
      'requestedRatio': _round(ratio),
      'effectiveRatio': _round(holdoutRatio),
      'bars': candles.length,
      'minTrainBars': minBars,
      'minHoldoutBars': minHoldoutBars,
      'warning':
          'insufficient bars for chronological out-of-sample validation; keep the single-window backtest as in-sample evidence only',
    };
  }
  final trainCandles = candles.sublist(0, splitIndex);
  final testCandles = candles.sublist(splitIndex);
  final train = _runStrategySpecBacktestCore(
    validation: validation,
    spec: spec,
    candles: trainCandles,
    symbol: symbol,
  );
  final test = _runStrategySpecBacktestCore(
    validation: validation,
    spec: spec,
    candles: testCandles,
    symbol: symbol,
  );
  return {
    'mode': 'chronological_holdout',
    'status': 'evaluated',
    'requestedRatio': _round(ratio),
    'effectiveRatio': _round(holdoutRatio),
    'train': _sliceSummary(train),
    'test': _sliceSummary(test),
    'warning':
        'out-of-sample evidence reuses the same StrategySpec on a later chronological holdout; it is not a guarantee of future performance',
  };
}

Map<String, dynamic> _walkForwardEvidence({
  required Map<String, dynamic> validation,
  required Map<String, dynamic> spec,
  required List<Candle> candles,
  required String symbol,
  required int requestedFolds,
}) {
  final folds = requestedFolds.clamp(2, 8).toInt();
  final minBars =
      ((_mapOf(spec['dataRequirements'])?['minBars'] as num?)?.toInt() ?? 120);
  final foldSize = (candles.length / folds).floor();
  if (foldSize < minBars) {
    return {
      'mode': 'chronological_walk_forward',
      'status': 'skipped',
      'requestedFolds': requestedFolds,
      'effectiveFolds': folds,
      'bars': candles.length,
      'minBarsPerFold': minBars,
      'warning':
          'insufficient bars for walk-forward evidence; each chronological fold must satisfy the StrategySpec minBars requirement',
    };
  }

  final foldResults = <Map<String, dynamic>>[];
  for (var index = 0; index < folds; index++) {
    final start = index * foldSize;
    final end = index == folds - 1 ? candles.length : start + foldSize;
    final slice = candles.sublist(start, end);
    final result = _runStrategySpecBacktestCore(
      validation: validation,
      spec: spec,
      candles: slice,
      symbol: symbol,
    );
    foldResults.add({'fold': index + 1, ..._sliceSummary(result)});
  }
  final returns = foldResults
      .map(
        (fold) => (((fold['metrics'] as Map?)?['totalReturnPct'] as num?) ?? 0)
            .toDouble(),
      )
      .toList();
  final drawdowns = foldResults
      .map(
        (fold) => (((fold['metrics'] as Map?)?['maxDrawdownPct'] as num?) ?? 0)
            .toDouble(),
      )
      .toList();
  final tradeCounts = foldResults
      .map(
        (fold) =>
            (((fold['metrics'] as Map?)?['tradeCount'] as num?) ?? 0).toInt(),
      )
      .toList();
  final averageReturn = returns.reduce((a, b) => a + b) / returns.length;
  final returnVariance = returns.length <= 1
      ? 0.0
      : returns
                .map((value) => pow(value - averageReturn, 2).toDouble())
                .reduce((a, b) => a + b) /
            (returns.length - 1);
  return {
    'mode': 'chronological_walk_forward',
    'status': 'evaluated',
    'requestedFolds': requestedFolds,
    'effectiveFolds': folds,
    'folds': foldResults,
    'stability': {
      'positiveReturnFoldCount': returns.where((value) => value > 0).length,
      'averageReturnPct': _round(averageReturn),
      'returnStdDevPct': _round(sqrt(returnVariance)),
      'worstFoldDrawdownPct': _round(drawdowns.reduce(max)),
      'completedTradeCount': tradeCounts.fold<int>(0, (a, b) => a + b),
    },
    'warning':
        'walk-forward evidence reruns the same StrategySpec on sequential historical folds; it checks stability, not future profitability',
  };
}

Map<String, dynamic> _sliceSummary(Map<String, dynamic> result) => {
  'actualStartDate': result['actualStartDate'],
  'actualEndDate': result['actualEndDate'],
  'bars': result['bars'],
  'metrics': result['metrics'],
  'signals': result['signals'],
};

bool _evaluateRuleGroup(
  Object? raw,
  Map<String, List<double?>> values,
  int index,
) {
  if (raw is! Map) return false;
  final anyMode = raw.containsKey('any');
  final rules = (_listOf(raw['all']) ?? _listOf(raw['any']) ?? const [])
      .whereType<Map>()
      .where((rule) => !rule.containsKey('type'))
      .map(
        (rule) => _evaluateRule(Map<String, dynamic>.from(rule), values, index),
      )
      .toList();
  return anyMode
      ? rules.any((v) => v)
      : rules.isNotEmpty && rules.every((v) => v);
}

bool _evaluateRule(
  Map<String, dynamic> rule,
  Map<String, List<double?>> values,
  int index,
) {
  final left = _valueOf('${rule['left']}', values, index);
  final right = _resolveRight(rule['right'], values, index);
  if (left == null || right == null) return false;
  final prevLeft = _valueOf('${rule['left']}', values, index - 1);
  final prevRight = _resolveRight(rule['right'], values, index - 1);
  switch ('${rule['op']}') {
    case '>':
      return left > right;
    case '>=':
      return left >= right;
    case '<':
      return left < right;
    case '<=':
      return left <= right;
    case '==':
      return left == right;
    case '!=':
      return left != right;
    case 'crosses_above':
      return prevLeft != null &&
          prevRight != null &&
          prevLeft <= prevRight &&
          left > right;
    case 'crosses_below':
      return prevLeft != null &&
          prevRight != null &&
          prevLeft >= prevRight &&
          left < right;
  }
  return false;
}

double? _valueOf(String key, Map<String, List<double?>> values, int index) {
  if (index < 0) return null;
  return values[key] != null && index < values[key]!.length
      ? values[key]![index]
      : null;
}

double? _resolveRight(
  Object? raw,
  Map<String, List<double?>> values,
  int index,
) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return _valueOf(raw, values, index);
  if (raw is Map && raw['mul'] is List) {
    final parts = raw['mul'] as List;
    if (parts.length != 2) return null;
    final left = parts[0] is String
        ? _valueOf(parts[0] as String, values, index) ?? _numOf(parts[0])
        : _numOf(parts[0]);
    final right = parts[1] is String
        ? _valueOf(parts[1] as String, values, index) ?? _numOf(parts[1])
        : _numOf(parts[1]);
    return left == null || right == null ? null : left * right;
  }
  return null;
}

String? _stopExit(
  Object? raw,
  double entryPrice,
  double price,
  double highWaterPrice,
  int barsSinceEntry,
  double? entryAtrStopDistance,
) {
  if (raw is! Map) return null;
  final rules = [
    ...(_listOf(raw['all']) ?? const []),
    ...(_listOf(raw['any']) ?? const []),
  ].whereType<Map>();
  for (final item in rules) {
    final rule = Map<String, dynamic>.from(item);
    final type = '${rule['type']}';
    final value = _numOf(rule['value']);
    if (value == null) continue;
    if (type == 'stop_loss_pct' && price <= entryPrice * (1 - value / 100)) {
      return 'stop_loss_pct';
    }
    if (type == 'take_profit_pct' && price >= entryPrice * (1 + value / 100)) {
      return 'take_profit_pct';
    }
    if (type == 'trailing_stop_pct' &&
        highWaterPrice > 0 &&
        price <= highWaterPrice * (1 - value / 100)) {
      return 'trailing_stop_pct';
    }
    if (type == 'max_drawdown_stop_pct' &&
        highWaterPrice > 0 &&
        price <= highWaterPrice * (1 - value / 100)) {
      return 'max_drawdown_stop_pct';
    }
    if (type == 'atr_stop_loss' &&
        entryAtrStopDistance != null &&
        price <= entryPrice - entryAtrStopDistance) {
      return 'atr_stop_loss';
    }
    if (type == 'time_stop_bars' && barsSinceEntry >= value.ceil()) {
      return 'time_stop_bars';
    }
  }
  return null;
}

bool _hasExitType(Object? raw, String type) {
  if (raw is! Map) return false;
  final rules = [
    ...(_listOf(raw['all']) ?? const []),
    ...(_listOf(raw['any']) ?? const []),
  ].whereType<Map>();
  return rules.any((rule) => '${rule['type']}' == type);
}

int _atrStopPeriod(Object? raw) {
  if (raw is! Map) return 14;
  final rules = [
    ...(_listOf(raw['all']) ?? const []),
    ...(_listOf(raw['any']) ?? const []),
  ].whereType<Map>();
  for (final rule in rules) {
    if ('${rule['type']}' != 'atr_stop_loss') continue;
    final period = _numOf(rule['period']);
    if (period != null && period >= 1) return period.round();
  }
  return 14;
}

double? _atrStopDistance(Object? raw, List<double?> atrValues, int index) {
  if (raw is! Map || index < 0 || index >= atrValues.length) return null;
  final atr = atrValues[index];
  if (atr == null || atr <= 0) return null;
  final rules = [
    ...(_listOf(raw['all']) ?? const []),
    ...(_listOf(raw['any']) ?? const []),
  ].whereType<Map>();
  for (final rule in rules) {
    if ('${rule['type']}' != 'atr_stop_loss') continue;
    final multiplier = _numOf(rule['value']);
    if (multiplier == null || multiplier <= 0) continue;
    return atr * multiplier;
  }
  return null;
}

List<double?> _atrValues(List<Candle> candles, int period) {
  final trueRanges = <double>[];
  for (var i = 0; i < candles.length; i++) {
    final current = candles[i];
    if (i == 0) {
      trueRanges.add(current.high - current.low);
      continue;
    }
    final previousClose = candles[i - 1].close;
    trueRanges.add(
      max(
        current.high - current.low,
        max(
          (current.high - previousClose).abs(),
          (current.low - previousClose).abs(),
        ),
      ),
    );
  }
  return List<double?>.generate(candles.length, (index) {
    if (index + 1 < period) return null;
    final window = trueRanges.sublist(index + 1 - period, index + 1);
    return window.reduce((a, b) => a + b) / period;
  });
}

String? _noSignalReason({
  required int entrySignalCount,
  required int exitSignalCount,
  required int stopExitCount,
  required int tradeCount,
  required bool openPosition,
}) {
  if (tradeCount > 0) return null;
  if (entrySignalCount == 0) {
    return 'entry rules never triggered in the tested data window';
  }
  if (openPosition) {
    return 'entry triggered but no exit or stop condition completed before the end of the tested data window';
  }
  if (exitSignalCount == 0 && stopExitCount == 0) {
    return 'entry rules triggered but no completed trade was produced by the executable exit rules';
  }
  return 'no completed trade was produced in the tested data window';
}

double _round(double value) => double.parse(value.toStringAsFixed(4));

double? _numOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

double _entryBudget(
  double cash,
  Map<String, dynamic> sizing,
  List<double> completedReturns,
) {
  final type = '${sizing['type'] ?? 'full_capital'}';
  if (type == 'fixed_fraction') {
    final fraction =
        (((sizing['value'] as num?)?.toDouble() ?? 0.1).clamp(0.01, 1.0) as num)
            .toDouble();
    return cash * fraction;
  }
  if (type == 'risk_per_trade') {
    final riskPct = _numOf(sizing['riskPct']) ?? 0.01;
    final stopLossPct = _numOf(sizing['stopLossPct']) ?? 8;
    final maxPositionPct = _numOf(sizing['maxPositionPct']) ?? 1.0;
    final riskBudget = cash * riskPct;
    final positionBudget = stopLossPct > 0
        ? riskBudget / (stopLossPct / 100)
        : cash;
    return min(cash * maxPositionPct, positionBudget);
  }
  if (type == 'kelly_fraction') {
    final initialFraction = (_numOf(sizing['initialFraction']) ?? 0.1).clamp(
      0.01,
      1.0,
    );
    final maxPositionPct = (_numOf(sizing['maxPositionPct']) ?? 0.25).clamp(
      0.01,
      1.0,
    );
    final minTrades = max(1, (_numOf(sizing['minTrades']) ?? 5).round());
    final kellyScale = (_numOf(sizing['kellyScale']) ?? 0.5).clamp(0.01, 1.0);
    if (completedReturns.length < minTrades) {
      return cash * min(initialFraction, maxPositionPct);
    }
    final fraction = _kellyFraction(completedReturns) * kellyScale;
    return cash * min(max(0.0, fraction), maxPositionPct);
  }
  return cash;
}

double _kellyFraction(List<double> returns) {
  final wins = returns.where((value) => value > 0).toList();
  final losses = returns.where((value) => value < 0).toList();
  if (wins.isEmpty || losses.isEmpty) return 0.0;
  final winRate = wins.length / returns.length;
  final lossRate = 1 - winRate;
  final avgWin = wins.reduce((a, b) => a + b) / wins.length;
  final avgLoss =
      losses.map((value) => value.abs()).reduce((a, b) => a + b) /
      losses.length;
  if (avgLoss <= 0) return 0.0;
  final payoffRatio = avgWin / avgLoss;
  if (payoffRatio <= 0) return 0.0;
  return winRate - (lossRate / payoffRatio);
}

Map<String, dynamic>? _mapOf(Object? raw) {
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

List? _listOf(Object? raw) => raw is List ? raw : null;
