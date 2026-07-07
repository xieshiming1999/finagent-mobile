import 'dart:math';

import 'backtest_core.dart';

typedef StrategyIndicatorCalculator =
    List<double?> Function(
      List<Candle> candles,
      List<double> values,
      int period,
      Map<String, dynamic>? params,
    );

Map<String, List<double?>> computeStrategyIndicators(
  Map<String, dynamic> spec,
  List<Candle> candles,
) {
  final out = <String, List<double?>>{
    'close': candles.map((c) => c.close).toList(),
    'volume': candles.map((c) => c.volume).toList(),
    'turnover_rate': candles.map((c) => c.turnoverRate).toList(),
  };
  for (final item
      in ((spec['indicators'] as List?) ?? const []).whereType<Map>()) {
    final indicator = Map<String, dynamic>.from(item);
    final id = '${indicator['id']}';
    final source = '${indicator['source'] ?? 'close'}';
    final period =
        (_mapOf(indicator['params'])?['period'] is num
                ? _mapOf(indicator['params'])!['period'] as num
                : null)
            ?.toInt() ??
        14;
    final values = candles
        .map((c) => source == 'volume' ? c.volume : c.close)
        .toList();
    final calculator =
        _indicatorCalculators['${indicator['type']}'] ?? _smaCalculator;
    out[id] = calculator(candles, values, period, _mapOf(indicator['params']));
  }
  return out;
}

final Map<String, StrategyIndicatorCalculator> _indicatorCalculators = {
  'sma': _smaCalculator,
  'volume_sma': (candles, _, period, _) =>
      _sma(candles.map((c) => c.volume).toList(), period),
  'rsi': (_, values, period, _) => _rsi(values, period),
  'stochastic_rsi': (_, values, _, params) => _stochasticRsi(values, params),
  'ema': (_, values, period, _) => _ema(values, period),
  'price_change_pct': (_, values, period, _) => _priceChangePct(values, period),
  'momentum_acceleration_pct': (_, values, _, params) =>
      _momentumAccelerationPct(values, params),
  'efficiency_ratio': (_, values, period, _) =>
      _efficiencyRatio(values, period),
  'momentum_rank': (_, values, _, params) => _momentumRank(values, params),
  'chande_momentum_oscillator': (_, values, period, _) =>
      _chandeMomentumOscillator(values, period),
  'aroon_oscillator': (candles, _, period, _) =>
      _aroonOscillator(candles, period),
  'aroon_up': (candles, _, period, _) => _aroonComponent(candles, period, 'up'),
  'aroon_down': (candles, _, period, _) =>
      _aroonComponent(candles, period, 'down'),
  'vortex_spread': (candles, _, period, _) => _vortexSpread(candles, period),
  'rolling_volatility': (_, values, period, _) =>
      _rollingVolatility(values, period),
  'donchian_width_pct': (candles, _, period, _) =>
      _donchianWidthPct(candles, period),
  'range_compression_ratio': (candles, _, _, params) =>
      _rangeCompressionRatio(candles, params),
  'donchian_position_pct': (candles, _, period, _) =>
      _donchianPositionPct(candles, period),
  'keltner_width_pct': (candles, _, _, params) =>
      _keltnerWidthPct(candles, params),
  'downside_volatility_pct': (_, values, period, _) =>
      _downsideVolatilityPct(values, period),
  'sortino_ratio': (_, values, period, _) => _sortinoRatio(values, period),
  'sharpe_ratio': (_, values, period, _) => _sharpeRatio(values, period),
  'calmar_ratio': (_, values, period, _) => _calmarRatio(values, period),
  'ulcer_index': (_, values, period, _) => _ulcerIndex(values, period),
  'gain_to_pain_ratio': (_, values, period, _) =>
      _gainToPainRatio(values, period),
  'positive_period_ratio': (_, values, period, _) =>
      _positivePeriodRatio(values, period),
  'negative_period_ratio': (_, values, period, _) =>
      _negativePeriodRatio(values, period),
  'max_consecutive_down_bars': (_, values, period, _) =>
      _maxConsecutiveBars(values, period, rising: false),
  'max_consecutive_up_bars': (_, values, period, _) =>
      _maxConsecutiveBars(values, period, rising: true),
  'return_skewness': (_, values, period, _) => _returnSkewness(values, period),
  'return_kurtosis': (_, values, period, _) => _returnKurtosis(values, period),
  'omega_ratio': (_, values, _, params) => _omegaRatio(values, params),
  'tail_ratio': (_, values, _, params) => _tailRatio(values, params),
  'value_at_risk_pct': (_, values, _, params) =>
      _valueAtRiskPct(values, params),
  'conditional_value_at_risk_pct': (_, values, _, params) =>
      _conditionalValueAtRiskPct(values, params),
  'volatility_regime': (_, values, _, params) =>
      _volatilityRegime(values, params),
  'volatility_percentile': (_, values, _, params) =>
      _volatilityPercentile(values, params),
  'ema_slope': (_, values, period, _) => _emaSlope(values, period),
  'moving_average_regime': (_, values, _, params) =>
      _movingAverageRegime(values, params),
  'kama_distance_pct': (_, values, _, params) =>
      _kamaDistancePct(values, params),
  'kama_slope_pct': (_, values, _, params) => _kamaSlopePct(values, params),
  'linear_regression_slope_pct': (_, values, period, _) =>
      _linearRegressionSlopePct(values, period),
  'linear_regression_r2': (_, values, period, _) =>
      _linearRegressionR2(values, period),
  'ma_distance_pct': (_, values, period, _) => _maDistancePct(values, period),
  'price_zscore': (_, values, period, _) => _priceZScore(values, period),
  'bollinger_bandwidth': (_, values, period, _) =>
      _bollingerBandwidth(values, period),
  'bollinger_percent_b': (_, values, _, params) =>
      _bollingerPercentB(values, params),
  'bollinger_band_distance_pct': (_, values, _, params) =>
      _bollingerBandDistancePct(values, params),
  'kdj': (candles, _, period, _) => _kdjK(candles, period),
  'stochastic_d': (candles, _, period, _) => _kdjComponents(candles, period).d,
  'stochastic_j': (candles, _, period, _) => _kdjComponents(candles, period).j,
  'adx': (candles, _, period, _) => _adx(candles, period),
  'dmi_plus': (candles, _, period, _) =>
      _directionalMovement(candles, period, 'plus'),
  'dmi_minus': (candles, _, period, _) =>
      _directionalMovement(candles, period, 'minus'),
  'dmi_spread': (candles, _, period, _) =>
      _directionalMovement(candles, period, 'spread'),
  'turnover_rate': (candles, _, _, _) => _turnoverRate(candles),
  'liquidity_ratio': (candles, _, period, _) =>
      _liquidityRatio(candles, period),
  'volume_zscore': (candles, _, period, _) => _volumeZScore(candles, period),
  'volume_breakout': (candles, _, period, _) =>
      _volumeBreakout(candles, period),
  'volume_oscillator_pct': (candles, _, _, params) =>
      _volumeOscillatorPct(candles, params),
  'volume_rate_of_change_pct': (candles, _, period, _) =>
      _volumeRateOfChangePct(candles, period),
  'volume_percentile': (candles, _, period, _) =>
      _volumePercentile(candles, period),
  'rolling_vwap': (candles, _, period, _) => _rollingVwap(candles, period),
  'money_flow_index': (candles, _, period, _) =>
      _moneyFlowIndex(candles, period),
  'on_balance_volume': (candles, _, _, _) => _onBalanceVolume(candles),
  'volume_price_trend': (candles, _, _, _) => _volumePriceTrend(candles),
  'positive_volume_index': (candles, _, _, _) =>
      _volumeIndex(candles, useIncreasingVolume: true),
  'negative_volume_index': (candles, _, _, _) =>
      _volumeIndex(candles, useIncreasingVolume: false),
  'accumulation_distribution_line': (candles, _, _, _) =>
      _accumulationDistributionLine(candles),
  'chaikin_money_flow': (candles, _, period, _) =>
      _chaikinMoneyFlow(candles, period),
  'force_index': (candles, _, _, params) => _forceIndex(candles, params),
  'ease_of_movement': (candles, _, _, params) =>
      _easeOfMovement(candles, params),
  'vwap_distance_pct': (candles, _, period, _) =>
      _vwapDistancePct(candles, period),
  'ichimoku_cloud_position': (candles, _, _, params) =>
      _ichimokuCloudPosition(candles, params),
  'parabolic_sar_direction': (candles, _, _, params) =>
      _parabolicSarDirection(candles, params),
  'commodity_channel_index': (candles, _, period, _) =>
      _commodityChannelIndex(candles, period),
  'williams_r': (candles, _, period, _) => _williamsR(candles, period),
  'drawdown_pct': (_, values, period, _) => _drawdownPct(values, period),
  'rolling_max_drawdown_pct': (_, values, period, _) =>
      _rollingMaxDrawdownPct(values, period),
  'drawdown_duration_bars': (_, values, period, _) =>
      _drawdownDurationBars(values, period),
  'distance_to_high_pct': (_, values, period, _) =>
      _distanceToHighPct(values, period),
  'distance_to_low_pct': (_, values, period, _) =>
      _distanceToLowPct(values, period),
  'breakout_pct': (_, values, period, _) => _breakoutPct(values, period),
  'breakdown_pct': (_, values, period, _) => _breakdownPct(values, period),
  'atr_pct': (candles, _, period, _) => _atrPct(candles, period),
  'atr_stop_distance_pct': (candles, _, _, params) =>
      _atrStopDistancePct(candles, params),
  'risk_reward_ratio': (candles, _, _, params) =>
      _riskRewardRatio(candles, params),
  'intraday_range_pct': (candles, _, _, _) => _intradayRangePct(candles),
  'gap_pct': (candles, _, _, _) => _gapPct(candles),
  'close_location_pct': (candles, _, _, _) => _closeLocationPct(candles),
  'body_return_pct': (candles, _, _, _) => _bodyReturnPct(candles),
  'upper_shadow_pct': (candles, _, _, _) => _upperShadowPct(candles),
  'lower_shadow_pct': (candles, _, _, _) => _lowerShadowPct(candles),
  'shadow_balance_pct': (candles, _, _, _) => _shadowBalancePct(candles),
  'body_to_range_pct': (candles, _, _, _) => _bodyToRangePct(candles),
  'macd': (_, values, _, params) => _macdHistogram(values, params),
  'ppo': (_, values, _, params) => _ppoHistogram(values, params),
  'trix': (_, values, period, _) => _trix(values, period),
  'true_strength_index': (_, values, _, params) =>
      _trueStrengthIndex(values, params),
  'bollinger': (_, values, period, _) => _bollingerZScore(values, period),
  'atr': (candles, _, period, _) => _atr(candles, period),
  'supertrend_direction': (candles, _, _, params) =>
      _supertrendComponents(candles, params).direction,
  'supertrend_distance_pct': (candles, _, _, params) =>
      _supertrendComponents(candles, params).distancePct,
  'chandelier_stop_distance_pct': (candles, _, _, params) =>
      _chandelierStopDistancePct(candles, params),
  'highest': (_, values, period, _) => _rollingExtreme(values, period, max),
  'lowest': (_, values, period, _) => _rollingExtreme(values, period, min),
};

Set<String> get strategyIndicatorCalculatorTypes =>
    Set.unmodifiable(_indicatorCalculators.keys);

List<double?> _smaCalculator(
  List<Candle> candles,
  List<double> values,
  int period,
  Map<String, dynamic>? params,
) => _sma(values, period);

List<double?> _turnoverRate(List<Candle> candles) =>
    candles.map((c) => c.turnoverRate).toList();

List<double?> _liquidityRatio(List<Candle> candles, int period) {
  final volumes = candles.map((c) => c.volume).toList();
  final average = _sma(volumes, period);
  return List<double?>.generate(candles.length, (index) {
    final base = average[index];
    if (base == null || base == 0) return null;
    return candles[index].volume / base;
  });
}

List<double?> _volumeZScore(List<Candle> candles, int period) {
  final volumes = candles.map((c) => c.volume).toList();
  return _zScore(volumes, period);
}

List<double?> _volumeBreakout(List<Candle> candles, int period) {
  final volumes = candles.map((c) => c.volume).toList();
  final average = _sma(volumes, period);
  return List<double?>.generate(candles.length, (index) {
    final base = average[index];
    if (base == null || base == 0) return null;
    return candles[index].volume / base;
  });
}

List<double?> _volumeOscillatorPct(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final fastPeriod = _intOf(params?['fastPeriod'], fallback: 12)!;
  final slowPeriod = _intOf(params?['slowPeriod'], fallback: 26)!;
  final safeFast = max(1, fastPeriod);
  final safeSlow = max(safeFast + 1, slowPeriod);
  final volumes = candles.map((c) => c.volume).toList();
  final fast = _ema(volumes, safeFast);
  final slow = _ema(volumes, safeSlow);
  return List<double?>.generate(candles.length, (index) {
    final fastValue = fast[index];
    final slowValue = slow[index];
    if (fastValue == null || slowValue == null || slowValue == 0) return null;
    return ((fastValue - slowValue) / slowValue) * 100;
  });
}

List<double?> _volumeRateOfChangePct(List<Candle> candles, int period) {
  final volumes = candles.map((c) => c.volume).toList();
  final safePeriod = max(1, period);
  return List<double?>.generate(candles.length, (index) {
    if (index < safePeriod) return null;
    final previous = volumes[index - safePeriod];
    if (previous == 0) return null;
    return (volumes[index] - previous) / previous.abs() * 100;
  });
}

List<double?> _volumePercentile(List<Candle> candles, int period) {
  final volumes = candles.map((c) => c.volume).toList();
  final safePeriod = max(2, period);
  return List<double?>.generate(candles.length, (index) {
    if (index + 1 < safePeriod) return null;
    final window = volumes.sublist(index + 1 - safePeriod, index + 1);
    final current = volumes[index];
    final below = window.where((value) => value < current).length;
    final equal = window.where((value) => value == current).length;
    if (window.length <= 1) return null;
    return (below + (equal - 1) / 2) / (window.length - 1) * 100;
  });
}

List<double?> _rollingVwap(List<Candle> candles, int period) =>
    List<double?>.generate(candles.length, (index) {
      if (index + 1 < period) return null;
      var volumeSum = 0.0;
      var weightedPriceSum = 0.0;
      for (var i = index + 1 - period; i <= index; i++) {
        final typicalPrice =
            (candles[i].high + candles[i].low + candles[i].close) / 3;
        volumeSum += candles[i].volume;
        weightedPriceSum += typicalPrice * candles[i].volume;
      }
      if (volumeSum == 0) return null;
      return weightedPriceSum / volumeSum;
    });

List<double?> _moneyFlowIndex(List<Candle> candles, int period) {
  final typicalPrices = candles
      .map((c) => (c.high + c.low + c.close) / 3)
      .toList();
  final rawFlows = List<double>.generate(
    candles.length,
    (index) => typicalPrices[index] * candles[index].volume,
  );
  return List<double?>.generate(candles.length, (index) {
    if (index < period) return null;
    var positive = 0.0;
    var negative = 0.0;
    for (var i = index - period + 1; i <= index; i++) {
      if (typicalPrices[i] > typicalPrices[i - 1]) {
        positive += rawFlows[i];
      } else if (typicalPrices[i] < typicalPrices[i - 1]) {
        negative += rawFlows[i];
      }
    }
    if (positive == 0 && negative == 0) return 50.0;
    if (negative == 0) return 100.0;
    final ratio = positive / negative;
    return 100 - (100 / (1 + ratio));
  });
}

List<double?> _onBalanceVolume(List<Candle> candles) {
  var running = 0.0;
  return List<double?>.generate(candles.length, (index) {
    if (index == 0) return running;
    if (candles[index].close > candles[index - 1].close) {
      running += candles[index].volume;
    } else if (candles[index].close < candles[index - 1].close) {
      running -= candles[index].volume;
    }
    return running;
  });
}

List<double?> _volumePriceTrend(List<Candle> candles) {
  var running = 0.0;
  return List<double?>.generate(candles.length, (index) {
    if (index == 0) return running;
    final previousClose = candles[index - 1].close;
    if (previousClose == 0) return running;
    running +=
        candles[index].volume *
        ((candles[index].close - previousClose) / previousClose);
    return running;
  });
}

List<double?> _volumeIndex(
  List<Candle> candles, {
  required bool useIncreasingVolume,
}) {
  var running = 1000.0;
  return List<double?>.generate(candles.length, (index) {
    if (index == 0) return running;
    final previousClose = candles[index - 1].close;
    if (previousClose == 0) return running;
    final volumeChanged = useIncreasingVolume
        ? candles[index].volume > candles[index - 1].volume
        : candles[index].volume < candles[index - 1].volume;
    if (volumeChanged) {
      running +=
          running * ((candles[index].close - previousClose) / previousClose);
    }
    return running;
  });
}

List<double?> _accumulationDistributionLine(List<Candle> candles) {
  var running = 0.0;
  return List<double?>.generate(candles.length, (index) {
    final range = candles[index].high - candles[index].low;
    if (range == 0) return running;
    final multiplier =
        ((candles[index].close - candles[index].low) -
            (candles[index].high - candles[index].close)) /
        range;
    running += multiplier * candles[index].volume;
    return running;
  });
}

List<double?> _chaikinMoneyFlow(List<Candle> candles, int period) {
  final moneyFlowVolumes = List<double>.generate(candles.length, (index) {
    final range = candles[index].high - candles[index].low;
    if (range == 0) return 0.0;
    final multiplier =
        ((candles[index].close - candles[index].low) -
            (candles[index].high - candles[index].close)) /
        range;
    return multiplier * candles[index].volume;
  });
  final volumes = candles.map((c) => c.volume).toList();
  return List<double?>.generate(candles.length, (index) {
    if (index + 1 < period) return null;
    final start = index + 1 - period;
    final volumeSum = volumes.sublist(start, index + 1).reduce((a, b) => a + b);
    if (volumeSum == 0) return null;
    final flowSum = moneyFlowVolumes
        .sublist(start, index + 1)
        .reduce((a, b) => a + b);
    return flowSum / volumeSum;
  });
}

List<double?> _forceIndex(List<Candle> candles, Map<String, dynamic>? params) {
  final smoothingPeriod = _intOf(
    params?['smoothingPeriod'] ?? params?['period'],
    fallback: 13,
  )!;
  final raw = List<double>.generate(candles.length, (index) {
    if (index == 0) return 0.0;
    return (candles[index].close - candles[index - 1].close) *
        candles[index].volume;
  });
  return _ema(raw, max(1, smoothingPeriod));
}

List<double?> _easeOfMovement(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final period = _intOf(params?['period'], fallback: 14)!;
  final volumeDivisor =
      _numOf(params?['volumeDivisor'])?.toDouble() ?? 1000000.0;
  final raw = List<double?>.generate(candles.length, (index) {
    if (index == 0) return null;
    final currentMidpoint = (candles[index].high + candles[index].low) / 2;
    final previousMidpoint =
        (candles[index - 1].high + candles[index - 1].low) / 2;
    final boxRatio =
        candles[index].volume /
        max(1.0, volumeDivisor) /
        (candles[index].high - candles[index].low);
    if (!boxRatio.isFinite || boxRatio == 0) return null;
    return (currentMidpoint - previousMidpoint) / boxRatio;
  });
  return _smaNullable(raw, max(1, period));
}

List<double?> _vwapDistancePct(List<Candle> candles, int period) =>
    List<double?>.generate(candles.length, (index) {
      if (index + 1 < period) return null;
      var volumeSum = 0.0;
      var weightedPriceSum = 0.0;
      for (var i = index + 1 - period; i <= index; i++) {
        final typicalPrice =
            (candles[i].high + candles[i].low + candles[i].close) / 3;
        volumeSum += candles[i].volume;
        weightedPriceSum += typicalPrice * candles[i].volume;
      }
      if (volumeSum == 0) return null;
      final vwap = weightedPriceSum / volumeSum;
      if (vwap == 0) return null;
      return (candles[index].close - vwap) / vwap * 100;
    });

List<double?> _ichimokuCloudPosition(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final conversionPeriod = _intOf(params?['conversionPeriod'], fallback: 9)!;
  final basePeriod = _intOf(params?['basePeriod'], fallback: 26)!;
  final spanBPeriod = _intOf(params?['spanBPeriod'], fallback: 52)!;
  final safeConversion = max(1, conversionPeriod);
  final safeBase = max(2, basePeriod);
  final safeSpanB = max(3, spanBPeriod);
  final required = max(max(safeConversion, safeBase), safeSpanB);
  return List<double?>.generate(candles.length, (index) {
    if (index + 1 < required) return null;
    final conversion = _highLowMidpoint(candles, index, safeConversion);
    final base = _highLowMidpoint(candles, index, safeBase);
    final spanB = _highLowMidpoint(candles, index, safeSpanB);
    if (conversion == null || base == null || spanB == null) return null;
    final spanA = (conversion + base) / 2;
    final cloudTop = max(spanA, spanB);
    final cloudBottom = min(spanA, spanB);
    final close = candles[index].close;
    if (close > cloudTop) return 1.0;
    if (close < cloudBottom) return -1.0;
    return 0.0;
  });
}

double? _highLowMidpoint(List<Candle> candles, int index, int period) {
  if (index + 1 < period) return null;
  final window = candles.sublist(index + 1 - period, index + 1);
  final high = window.map((c) => c.high).reduce(max);
  final low = window.map((c) => c.low).reduce(min);
  return (high + low) / 2;
}

List<double?> _parabolicSarDirection(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  if (candles.isEmpty) return const [];
  final step = max(0.001, _numOf(params?['acceleration'])?.toDouble() ?? 0.02);
  final maxStep = max(
    step,
    _numOf(params?['maxAcceleration'])?.toDouble() ?? 0.2,
  );
  final out = List<double?>.filled(candles.length, null);
  if (candles.length == 1) return out;

  var uptrend = candles[1].close >= candles[0].close;
  var sar = uptrend ? candles[0].low : candles[0].high;
  var extreme = uptrend
      ? max(candles[0].high, candles[1].high)
      : min(candles[0].low, candles[1].low);
  var acceleration = step;
  out[1] = candles[1].close >= sar ? 1.0 : -1.0;

  for (var index = 2; index < candles.length; index++) {
    sar = sar + acceleration * (extreme - sar);
    if (uptrend) {
      sar = min(sar, min(candles[index - 1].low, candles[index - 2].low));
      if (candles[index].low < sar) {
        uptrend = false;
        sar = extreme;
        extreme = candles[index].low;
        acceleration = step;
      } else if (candles[index].high > extreme) {
        extreme = candles[index].high;
        acceleration = min(maxStep, acceleration + step);
      }
    } else {
      sar = max(sar, max(candles[index - 1].high, candles[index - 2].high));
      if (candles[index].high > sar) {
        uptrend = true;
        sar = extreme;
        extreme = candles[index].high;
        acceleration = step;
      } else if (candles[index].low < extreme) {
        extreme = candles[index].low;
        acceleration = min(maxStep, acceleration + step);
      }
    }
    out[index] = candles[index].close >= sar ? 1.0 : -1.0;
  }
  return out;
}

List<double?> _commodityChannelIndex(List<Candle> candles, int period) {
  final typicalPrices = candles
      .map((c) => (c.high + c.low + c.close) / 3)
      .toList();
  return List<double?>.generate(candles.length, (index) {
    if (index + 1 < period) return null;
    final window = typicalPrices.sublist(index + 1 - period, index + 1);
    final average = window.reduce((a, b) => a + b) / period;
    final meanDeviation =
        window.map((value) => (value - average).abs()).reduce((a, b) => a + b) /
        period;
    if (meanDeviation == 0) return 0.0;
    return (typicalPrices[index] - average) / (0.015 * meanDeviation);
  });
}

List<double?> _williamsR(List<Candle> candles, int period) =>
    List<double?>.generate(candles.length, (index) {
      if (index + 1 < period) return null;
      final window = candles.sublist(index + 1 - period, index + 1);
      final highestHigh = window.map((c) => c.high).reduce(max);
      final lowestLow = window.map((c) => c.low).reduce(min);
      final range = highestHigh - lowestLow;
      if (range == 0) return 0.0;
      return ((highestHigh - candles[index].close) / range) * -100;
    });

List<double?> _sma(List<double> values, int period) => List.generate(
  values.length,
  (index) => index + 1 < period
      ? null
      : values.sublist(index + 1 - period, index + 1).reduce((a, b) => a + b) /
            period,
);

List<double?> _smaNullable(List<double?> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final window = values
          .sublist(index + 1 - period, index + 1)
          .whereType<double>()
          .toList(growable: false);
      if (window.length < period) return null;
      return window.reduce((a, b) => a + b) / period;
    });

List<double?> _ema(List<double> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0) return out;
  final multiplier = 2 / (period + 1);
  double? previous;
  for (var index = 0; index < values.length; index++) {
    if (index + 1 < period) continue;
    if (previous == null) {
      previous =
          values
              .sublist(index + 1 - period, index + 1)
              .reduce((a, b) => a + b) /
          period;
    } else {
      previous = values[index] * multiplier + previous * (1 - multiplier);
    }
    out[index] = previous;
  }
  return out;
}

List<double?> _priceChangePct(List<double> values, int period) => List.generate(
  values.length,
  (index) {
    if (index < period || values[index - period] == 0) return null;
    return ((values[index] - values[index - period]) / values[index - period]) *
        100;
  },
);

List<double?> _momentumAccelerationPct(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final period = max(1, _intOf(params?['period'], fallback: 20)!);
  final lagPeriod = max(1, _intOf(params?['lagPeriod'], fallback: period)!);
  final returns = _priceChangePct(values, period);
  return List<double?>.generate(values.length, (index) {
    final current = returns[index];
    final previousIndex = index - lagPeriod;
    if (current == null || previousIndex < 0) return null;
    final previous = returns[previousIndex];
    if (previous == null) return null;
    return current - previous;
  });
}

List<double?> _efficiencyRatio(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final start = index + 1 - period;
      final netChange = (values[index] - values[start]).abs();
      var totalMovement = 0.0;
      for (var i = start + 1; i <= index; i++) {
        totalMovement += (values[i] - values[i - 1]).abs();
      }
      if (totalMovement == 0) return 0.0;
      return netChange / totalMovement;
    });

List<double?> _chandeMomentumOscillator(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      var gains = 0.0;
      var losses = 0.0;
      for (var i = index - period + 1; i <= index; i++) {
        final change = values[i] - values[i - 1];
        if (change > 0) {
          gains += change;
        } else {
          losses += change.abs();
        }
      }
      final total = gains + losses;
      if (total == 0) return 0.0;
      return 100 * (gains - losses) / total;
    });

List<double?> _aroonOscillator(List<Candle> candles, int period) {
  final up = _aroonComponent(candles, period, 'up');
  final down = _aroonComponent(candles, period, 'down');
  return List<double?>.generate(candles.length, (index) {
    final upValue = up[index];
    final downValue = down[index];
    if (upValue == null || downValue == null) return null;
    return upValue - downValue;
  });
}

List<double?> _aroonComponent(
  List<Candle> candles,
  int period,
  String component,
) => List.generate(candles.length, (index) {
  if (index + 1 < period) return null;
  final start = index + 1 - period;
  var highestIndex = start;
  var lowestIndex = start;
  for (var i = start + 1; i <= index; i++) {
    if (candles[i].high >= candles[highestIndex].high) highestIndex = i;
    if (candles[i].low <= candles[lowestIndex].low) lowestIndex = i;
  }
  final periodsSinceHigh = index - highestIndex;
  final periodsSinceLow = index - lowestIndex;
  final aroonUp = 100 * (period - periodsSinceHigh) / period;
  final aroonDown = 100 * (period - periodsSinceLow) / period;
  return component == 'down' ? aroonDown : aroonUp;
});

List<double?> _vortexSpread(List<Candle> candles, int period) =>
    List.generate(candles.length, (index) {
      if (index < period || period <= 0) return null;
      var plusMovement = 0.0;
      var minusMovement = 0.0;
      var trueRange = 0.0;
      for (var i = index - period + 1; i <= index; i++) {
        final current = candles[i];
        final previous = candles[i - 1];
        plusMovement += (current.high - previous.low).abs();
        minusMovement += (current.low - previous.high).abs();
        trueRange += max(
          current.high - current.low,
          max(
            (current.high - previous.close).abs(),
            (current.low - previous.close).abs(),
          ),
        );
      }
      if (trueRange == 0) return 0.0;
      return plusMovement / trueRange - minusMovement / trueRange;
    });

List<double?> _donchianWidthPct(List<Candle> candles, int period) =>
    List.generate(candles.length, (index) {
      if (index + 1 < period) return null;
      final window = candles.sublist(index + 1 - period, index + 1);
      final highestHigh = window.map((c) => c.high).reduce(max);
      final lowestLow = window.map((c) => c.low).reduce(min);
      if (candles[index].close == 0) return null;
      return ((highestHigh - lowestLow) / candles[index].close) * 100;
    });

List<double?> _rangeCompressionRatio(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final period = max(1, _intOf(params?['period'], fallback: 20)!);
  final baselinePeriod = max(
    period,
    _intOf(params?['baselinePeriod'], fallback: 60)!,
  );
  final current = _donchianWidthPct(candles, period);
  final baseline = _donchianWidthPct(candles, baselinePeriod);
  return List<double?>.generate(candles.length, (index) {
    final currentValue = current[index];
    final baselineValue = baseline[index];
    if (currentValue == null || baselineValue == null || baselineValue == 0) {
      return null;
    }
    return currentValue / baselineValue;
  });
}

List<double?> _donchianPositionPct(List<Candle> candles, int period) =>
    List.generate(candles.length, (index) {
      if (index + 1 < period) return null;
      final window = candles.sublist(index + 1 - period, index + 1);
      final highestHigh = window.map((c) => c.high).reduce(max);
      final lowestLow = window.map((c) => c.low).reduce(min);
      final range = highestHigh - lowestLow;
      if (range == 0) return null;
      return ((candles[index].close - lowestLow) / range) * 100;
    });

List<double?> _keltnerWidthPct(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final period = _intOf(params?['period'], fallback: 20)!;
  final atrPeriod = _intOf(params?['atrPeriod'], fallback: period)!;
  final multiplier = _numOf(params?['atrMultiplier'])?.toDouble() ?? 2.0;
  final closes = candles.map((c) => c.close).toList();
  final centerline = _ema(closes, max(1, period));
  final atrValues = _atr(candles, max(1, atrPeriod));
  return List<double?>.generate(candles.length, (index) {
    final center = centerline[index];
    final atrValue = atrValues[index];
    if (center == null || atrValue == null || center == 0) return null;
    return (2 * multiplier * atrValue / center) * 100;
  });
}

List<double?> _stochasticRsi(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final rsiPeriod = _intOf(
    params?['rsiPeriod'] ?? params?['period'],
    fallback: 14,
  )!;
  final stochasticPeriod = _intOf(
    params?['stochasticPeriod'] ??
        params?['lookbackPeriod'] ??
        params?['period'],
    fallback: 14,
  )!;
  final rsiValues = _rsi(values, max(1, rsiPeriod));
  return List<double?>.generate(values.length, (index) {
    if (index + 1 < stochasticPeriod) return null;
    final window = rsiValues
        .sublist(max(0, index + 1 - stochasticPeriod), index + 1)
        .whereType<double>()
        .toList(growable: false);
    if (window.length < stochasticPeriod || rsiValues[index] == null) {
      return null;
    }
    final low = window.reduce(min);
    final high = window.reduce(max);
    final range = high - low;
    if (range == 0) return 50.0;
    return (rsiValues[index]! - low) / range * 100;
  });
}

List<double?> _momentumRank(List<double> values, Map<String, dynamic>? params) {
  final momentumPeriod = _intOf(params?['period'], fallback: 20)!;
  final rankPeriod = _intOf(params?['rankPeriod'], fallback: 60)!;
  final returns = _priceChangePct(values, momentumPeriod);
  return List<double?>.generate(values.length, (index) {
    final current = returns[index];
    if (current == null || index + 1 < rankPeriod) return null;
    final window = returns
        .sublist(max(0, index + 1 - rankPeriod), index + 1)
        .whereType<double>()
        .toList(growable: false);
    if (window.length < max(2, rankPeriod - momentumPeriod)) return null;
    final belowOrEqual = window.where((item) => item <= current).length;
    return belowOrEqual / window.length * 100;
  });
}

List<double?> _rollingVolatility(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      final returns = <double>[];
      for (var i = index - period + 1; i <= index; i++) {
        if (values[i - 1] == 0) return null;
        returns.add((values[i] - values[i - 1]) / values[i - 1]);
      }
      final mean = returns.reduce((a, b) => a + b) / returns.length;
      final variance =
          returns
              .map((item) => pow(item - mean, 2).toDouble())
              .reduce((a, b) => a + b) /
          returns.length;
      return sqrt(variance) * sqrt(252) * 100;
    });

List<double?> _downsideVolatilityPct(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      final downsideReturns = <double>[];
      for (var i = index - period + 1; i <= index; i++) {
        if (values[i - 1] == 0) return null;
        final dailyReturn = (values[i] - values[i - 1]) / values[i - 1];
        downsideReturns.add(min(0, dailyReturn));
      }
      final downsideVariance =
          downsideReturns
              .map((item) => pow(item, 2).toDouble())
              .reduce((a, b) => a + b) /
          downsideReturns.length;
      return sqrt(downsideVariance) * sqrt(252) * 100;
    });

List<double?> _sortinoRatio(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      final returns = <double>[];
      final downsideReturns = <double>[];
      for (var i = index - period + 1; i <= index; i++) {
        if (values[i - 1] == 0) return null;
        final dailyReturn = (values[i] - values[i - 1]) / values[i - 1];
        returns.add(dailyReturn);
        downsideReturns.add(min(0, dailyReturn));
      }
      final mean = returns.reduce((a, b) => a + b) / returns.length;
      final downsideVariance =
          downsideReturns
              .map((item) => pow(item, 2).toDouble())
              .reduce((a, b) => a + b) /
          downsideReturns.length;
      if (downsideVariance == 0) return 0.0;
      return mean / sqrt(downsideVariance) * sqrt(252);
    });

List<double?> _sharpeRatio(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      final returns = <double>[];
      for (var i = index - period + 1; i <= index; i++) {
        if (values[i - 1] == 0) return null;
        returns.add((values[i] - values[i - 1]) / values[i - 1]);
      }
      final mean = returns.reduce((a, b) => a + b) / returns.length;
      final variance =
          returns
              .map((item) => pow(item - mean, 2).toDouble())
              .reduce((a, b) => a + b) /
          returns.length;
      if (variance == 0) return 0.0;
      return mean / sqrt(variance) * sqrt(252);
    });

List<double?> _calmarRatio(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final window = values.sublist(index + 1 - period, index + 1);
      final start = window.first;
      if (start == 0) return null;
      final periodReturnPct = (window.last - start) / start * 100;
      var high = window.first;
      var maxDrawdownPct = 0.0;
      for (final value in window) {
        high = max(high, value);
        if (high == 0) return null;
        maxDrawdownPct = min(maxDrawdownPct, (value - high) / high * 100);
      }
      if (maxDrawdownPct == 0) return 0.0;
      return periodReturnPct / maxDrawdownPct.abs();
    });

List<double?> _ulcerIndex(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final window = values.sublist(index + 1 - period, index + 1);
      var high = window.first;
      var squaredDrawdownSum = 0.0;
      for (final value in window) {
        high = max(high, value);
        if (high == 0) return null;
        final drawdownPct = min(0.0, (value - high) / high * 100);
        squaredDrawdownSum += drawdownPct * drawdownPct;
      }
      return sqrt(squaredDrawdownSum / window.length);
    });

List<double?> _gainToPainRatio(List<double> values, int period) =>
    List.generate(values.length, (index) {
      final returns = _windowReturns(values, period, index);
      if (returns == null) return null;
      final gains = returns
          .where((item) => item > 0)
          .fold(0.0, (sum, item) => sum + item);
      final pain = returns
          .where((item) => item < 0)
          .fold(0.0, (sum, item) => sum + item.abs());
      if (pain == 0) return gains == 0 ? 0.0 : gains;
      return gains / pain;
    });

List<double?> _positivePeriodRatio(List<double> values, int period) =>
    List.generate(values.length, (index) {
      final returns = _windowReturns(values, period, index);
      if (returns == null) return null;
      final positives = returns.where((item) => item > 0).length;
      return positives / returns.length * 100.0;
    });

List<double?> _negativePeriodRatio(List<double> values, int period) =>
    List.generate(values.length, (index) {
      final returns = _windowReturns(values, period, index);
      if (returns == null) return null;
      final negatives = returns.where((item) => item < 0).length;
      return negatives / returns.length * 100.0;
    });

List<double?> _maxConsecutiveBars(
  List<double> values,
  int period, {
  required bool rising,
}) => List.generate(values.length, (index) {
  if (index < period) return null;
  var currentStreak = 0;
  var maxStreak = 0;
  for (var i = index - period + 1; i <= index; i++) {
    final inStreak = rising
        ? values[i] > values[i - 1]
        : values[i] < values[i - 1];
    if (inStreak) {
      currentStreak += 1;
      maxStreak = max(maxStreak, currentStreak);
    } else {
      currentStreak = 0;
    }
  }
  return maxStreak.toDouble();
});

List<double?> _returnSkewness(List<double> values, int period) =>
    List.generate(values.length, (index) {
      final returns = _windowReturns(values, period, index);
      if (returns == null || returns.length < 3) return null;
      final mean = returns.reduce((a, b) => a + b) / returns.length;
      final variance =
          returns.fold(0.0, (sum, item) => sum + pow(item - mean, 2)) /
          returns.length;
      if (variance == 0) return 0.0;
      final stdev = sqrt(variance);
      final skew = returns.fold(
        0.0,
        (sum, item) => sum + pow((item - mean) / stdev, 3),
      );
      return skew / returns.length;
    });

List<double?> _returnKurtosis(List<double> values, int period) =>
    List.generate(values.length, (index) {
      final returns = _windowReturns(values, period, index);
      if (returns == null || returns.length < 4) return null;
      final mean = returns.reduce((a, b) => a + b) / returns.length;
      final variance =
          returns.fold(0.0, (sum, item) => sum + pow(item - mean, 2)) /
          returns.length;
      if (variance == 0) return 0.0;
      final stdev = sqrt(variance);
      final kurtosis = returns.fold(
        0.0,
        (sum, item) => sum + pow((item - mean) / stdev, 4),
      );
      return kurtosis / returns.length - 3.0;
    });

List<double?> _omegaRatio(List<double> values, Map<String, dynamic>? params) {
  final period = _intOf(params?['period'], fallback: 20)!;
  final threshold =
      (_numOf(params?['thresholdReturn'])?.toDouble() ?? 0.0) / 100.0;
  return List.generate(values.length, (index) {
    final returns = _windowReturns(values, period, index);
    if (returns == null) return null;
    var gains = 0.0;
    var shortfall = 0.0;
    for (final item in returns) {
      final excess = item - threshold;
      if (excess >= 0) {
        gains += excess;
      } else {
        shortfall += excess.abs();
      }
    }
    if (shortfall == 0) return gains == 0 ? 0.0 : gains;
    return gains / shortfall;
  });
}

List<double?> _tailRatio(List<double> values, Map<String, dynamic>? params) {
  final period = _intOf(params?['period'], fallback: 60)!;
  final upper = (_numOf(params?['upperPercentile'])?.toDouble() ?? 95.0).clamp(
    50.0,
    100.0,
  );
  final lower = (_numOf(params?['lowerPercentile'])?.toDouble() ?? 5.0).clamp(
    0.0,
    50.0,
  );
  return List.generate(values.length, (index) {
    final returns = _windowReturns(values, period, index);
    if (returns == null) return null;
    final upperTail = _percentile(returns, upper);
    final lowerTail = _percentile(returns, lower);
    if (upperTail == null || lowerTail == null || lowerTail == 0) return null;
    return upperTail / lowerTail.abs();
  });
}

List<double?> _valueAtRiskPct(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final period = _intOf(params?['period'], fallback: 60)!;
  final confidence = (_numOf(params?['confidence'])?.toDouble() ?? 95.0).clamp(
    50.0,
    99.9,
  );
  return List.generate(values.length, (index) {
    final returns = _windowReturns(values, period, index);
    if (returns == null) return null;
    final cutoff = _percentile(returns, 100.0 - confidence);
    if (cutoff == null) return null;
    return max(0.0, -cutoff * 100.0);
  });
}

List<double?> _conditionalValueAtRiskPct(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final period = _intOf(params?['period'], fallback: 60)!;
  final confidence = (_numOf(params?['confidence'])?.toDouble() ?? 95.0).clamp(
    50.0,
    99.9,
  );
  return List.generate(values.length, (index) {
    final returns = _windowReturns(values, period, index);
    if (returns == null) return null;
    final cutoff = _percentile(returns, 100.0 - confidence);
    if (cutoff == null) return null;
    final losses = returns.where((item) => item <= cutoff).toList();
    if (losses.isEmpty) return max(0.0, -cutoff * 100.0);
    final meanTail = losses.reduce((a, b) => a + b) / losses.length;
    return max(0.0, -meanTail * 100.0);
  });
}

List<double?> _volatilityRegime(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final shortPeriod = _intOf(
    params?['shortPeriod'] ?? params?['period'],
    fallback: 20,
  )!;
  final baselinePeriod = _intOf(
    params?['baselinePeriod'] ?? params?['longPeriod'],
    fallback: max(shortPeriod * 3, shortPeriod + 1),
  )!;
  final shortVol = _rollingVolatility(values, max(2, shortPeriod));
  final baselineVol = _rollingVolatility(
    values,
    max(max(3, baselinePeriod), shortPeriod + 1),
  );
  return List<double?>.generate(values.length, (index) {
    final current = shortVol[index];
    final baseline = baselineVol[index];
    if (current == null || baseline == null || baseline == 0) return null;
    if (current >= baseline * 1.2) return 1.0;
    if (current <= baseline * 0.8) return -1.0;
    return 0.0;
  });
}

List<double?> _volatilityPercentile(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final period = _intOf(params?['period'], fallback: 20)!;
  final baselinePeriod = _intOf(params?['baselinePeriod'], fallback: 60)!;
  final safePeriod = max(2, period);
  final safeBaseline = max(max(3, baselinePeriod), safePeriod + 1);
  final volatility = _rollingVolatility(values, safePeriod);
  return List<double?>.generate(values.length, (index) {
    final current = volatility[index];
    if (current == null || index + 1 < safeBaseline) return null;
    final window = volatility
        .sublist(index + 1 - safeBaseline, index + 1)
        .whereType<double>()
        .toList(growable: false);
    if (window.length < safeBaseline) return null;
    final belowOrEqual = window.where((item) => item <= current).length;
    return belowOrEqual / window.length * 100;
  });
}

List<double?> _emaSlope(List<double> values, int period) {
  final emaValues = _ema(values, period);
  return List<double?>.generate(values.length, (index) {
    if (index == 0 ||
        emaValues[index] == null ||
        emaValues[index - 1] == null) {
      return null;
    }
    final previous = emaValues[index - 1]!;
    if (previous == 0) return null;
    return (emaValues[index]! - previous) / previous * 100;
  });
}

List<double?> _movingAverageRegime(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final fast = _intOf(params?['fastPeriod'] ?? params?['fast'], fallback: 20)!;
  final slow = _intOf(params?['slowPeriod'] ?? params?['slow'], fallback: 50)!;
  final fastMa = _sma(values, min(fast, slow));
  final slowMa = _sma(values, max(fast, slow));
  return List<double?>.generate(values.length, (index) {
    final fastValue = fastMa[index];
    final slowValue = slowMa[index];
    if (fastValue == null || slowValue == null) return null;
    final close = values[index];
    if (close > fastValue && fastValue > slowValue) return 1.0;
    if (close < fastValue && fastValue < slowValue) return -1.0;
    return 0.0;
  });
}

List<double?> _kamaDistancePct(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final kama = _kama(values, params);
  return List<double?>.generate(values.length, (index) {
    final base = kama[index];
    if (base == null || base == 0) return null;
    return (values[index] - base) / base * 100;
  });
}

List<double?> _kamaSlopePct(List<double> values, Map<String, dynamic>? params) {
  final kama = _kama(values, params);
  return List<double?>.generate(values.length, (index) {
    if (index == 0 || kama[index] == null || kama[index - 1] == null) {
      return null;
    }
    final previous = kama[index - 1]!;
    if (previous == 0) return null;
    return (kama[index]! - previous) / previous * 100;
  });
}

List<double?> _kama(List<double> values, Map<String, dynamic>? params) {
  final erPeriod = max(
    2,
    _intOf(params?['erPeriod'] ?? params?['period'], fallback: 10)!,
  );
  final fastPeriod = max(
    1,
    _intOf(params?['fastPeriod'] ?? params?['fast'], fallback: 2)!,
  );
  final slowPeriod = max(
    fastPeriod + 1,
    _intOf(params?['slowPeriod'] ?? params?['slow'], fallback: 30)!,
  );
  final fastSc = 2 / (fastPeriod + 1);
  final slowSc = 2 / (slowPeriod + 1);
  final out = List<double?>.filled(values.length, null);
  double? previous;
  for (var index = 0; index < values.length; index++) {
    if (index < erPeriod) continue;
    if (previous == null) {
      previous =
          values.sublist(index - erPeriod, index + 1).reduce((a, b) => a + b) /
          (erPeriod + 1);
    } else {
      final change = (values[index] - values[index - erPeriod]).abs();
      var volatility = 0.0;
      for (var i = index - erPeriod + 1; i <= index; i++) {
        volatility += (values[i] - values[i - 1]).abs();
      }
      final efficiency = volatility == 0 ? 0.0 : change / volatility;
      final smoothing = pow(
        efficiency * (fastSc - slowSc) + slowSc,
        2,
      ).toDouble();
      previous = previous + smoothing * (values[index] - previous);
    }
    out[index] = previous;
  }
  return out;
}

List<double?> _linearRegressionSlopePct(List<double> values, int period) =>
    List<double?>.generate(values.length, (index) {
      final stats = _linearRegressionStats(values, index, period);
      if (stats == null) return null;
      final fittedStart = stats.intercept;
      if (fittedStart == 0) return null;
      return stats.slope / fittedStart * 100;
    });

List<double?> _linearRegressionR2(List<double> values, int period) =>
    List<double?>.generate(
      values.length,
      (index) => _linearRegressionStats(values, index, period)?.rSquared,
    );

_LinearRegressionStats? _linearRegressionStats(
  List<double> values,
  int index,
  int period,
) {
  if (period < 2 || index + 1 < period) return null;
  final start = index + 1 - period;
  final meanX = (period - 1) / 2;
  var meanY = 0.0;
  for (var i = 0; i < period; i++) {
    meanY += values[start + i];
  }
  meanY /= period;

  var sumXX = 0.0;
  var sumXY = 0.0;
  var totalSS = 0.0;
  for (var i = 0; i < period; i++) {
    final x = i.toDouble();
    final y = values[start + i];
    final dx = x - meanX;
    final dy = y - meanY;
    sumXX += dx * dx;
    sumXY += dx * dy;
    totalSS += dy * dy;
  }
  if (sumXX == 0) return null;
  final slope = sumXY / sumXX;
  final intercept = meanY - slope * meanX;
  var residualSS = 0.0;
  for (var i = 0; i < period; i++) {
    final fitted = intercept + slope * i;
    final residual = values[start + i] - fitted;
    residualSS += residual * residual;
  }
  final rSquared = totalSS == 0 ? 1.0 : max(0.0, 1 - residualSS / totalSS);
  return _LinearRegressionStats(slope, intercept, min(1.0, rSquared));
}

class _LinearRegressionStats {
  const _LinearRegressionStats(this.slope, this.intercept, this.rSquared);

  final double slope;
  final double intercept;
  final double rSquared;
}

List<double?> _maDistancePct(List<double> values, int period) {
  final average = _sma(values, period);
  return List<double?>.generate(values.length, (index) {
    final base = average[index];
    if (base == null || base == 0) return null;
    return (values[index] - base) / base * 100;
  });
}

List<double?> _priceZScore(List<double> values, int period) =>
    _zScore(values, period);

List<double?> _zScore(List<double> values, int period) =>
    List<double?>.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final window = values.sublist(index + 1 - period, index + 1);
      final mean = window.reduce((a, b) => a + b) / period;
      final variance =
          window
              .map((item) => pow(item - mean, 2).toDouble())
              .reduce((a, b) => a + b) /
          period;
      final std = sqrt(variance);
      if (std == 0) return 0;
      return (values[index] - mean) / std;
    });

List<double?> _bollingerBandwidth(List<double> values, int period) =>
    _bollingerBandValue(values, {'period': period}, (value, bands) {
      if (bands.middle == 0) return null;
      return (bands.upper - bands.lower) / bands.middle * 100;
    });

List<double?> _bollingerPercentB(
  List<double> values,
  Map<String, dynamic>? params,
) => _bollingerBandValue(values, params, (value, bands) {
  final width = bands.upper - bands.lower;
  if (width == 0) return 50.0;
  return (value - bands.lower) / width * 100;
});

List<double?> _bollingerBandDistancePct(
  List<double> values,
  Map<String, dynamic>? params,
) => _bollingerBandValue(values, params, (value, bands) {
  if (value == 0) return null;
  if (value > bands.upper) return (value - bands.upper) / value * 100;
  if (value < bands.lower) return (value - bands.lower) / value * 100;
  return 0.0;
});

List<double?> _bollingerBandValue(
  List<double> values,
  Map<String, dynamic>? params,
  double? Function(double value, _BollingerBands bands) compute,
) {
  final period = _intOf(params?['period'], fallback: 20)!;
  final multiplier =
      _numOf(params?['stdDevMultiplier'] ?? params?['stdDev'])?.toDouble() ??
      2.0;
  final safePeriod = max(1, period);
  final safeMultiplier = max(0.0, multiplier);
  return List<double?>.generate(values.length, (index) {
    final bands = _bollingerBandsAt(values, index, safePeriod, safeMultiplier);
    if (bands == null) return null;
    return compute(values[index], bands);
  });
}

_BollingerBands? _bollingerBandsAt(
  List<double> values,
  int index,
  int period,
  double multiplier,
) {
  if (index + 1 < period) return null;
  final window = values.sublist(index + 1 - period, index + 1);
  final mean = window.reduce((a, b) => a + b) / period;
  final variance =
      window
          .map((item) => pow(item - mean, 2).toDouble())
          .reduce((a, b) => a + b) /
      period;
  final std = sqrt(variance);
  return _BollingerBands(
    middle: mean,
    upper: mean + multiplier * std,
    lower: mean - multiplier * std,
  );
}

class _BollingerBands {
  const _BollingerBands({
    required this.middle,
    required this.upper,
    required this.lower,
  });

  final double middle;
  final double upper;
  final double lower;
}

List<double?> _kdjK(List<Candle> candles, int period) {
  return _kdjComponents(candles, period).k;
}

({List<double?> k, List<double?> d, List<double?> j}) _kdjComponents(
  List<Candle> candles,
  int period,
) {
  final out = List<double?>.filled(candles.length, null);
  final dValues = List<double?>.filled(candles.length, null);
  final jValues = List<double?>.filled(candles.length, null);
  var k = 50.0;
  var d = 50.0;
  for (var index = 0; index < candles.length; index++) {
    if (index + 1 < period) continue;
    final window = candles.sublist(index + 1 - period, index + 1);
    final highestHigh = window.map((c) => c.high).reduce(max);
    final lowestLow = window.map((c) => c.low).reduce(min);
    final rsv = highestHigh == lowestLow
        ? 50.0
        : (candles[index].close - lowestLow) / (highestHigh - lowestLow) * 100;
    k = (2 / 3) * k + (1 / 3) * rsv;
    d = (2 / 3) * d + (1 / 3) * k;
    out[index] = k;
    dValues[index] = d;
    jValues[index] = 3 * k - 2 * d;
  }
  return (k: out, d: dValues, j: jValues);
}

List<double?> _adx(List<Candle> candles, int period) {
  final plusDi = _directionalMovement(candles, period, 'plus');
  final minusDi = _directionalMovement(candles, period, 'minus');
  final dx = List<double?>.generate(candles.length, (index) {
    final plus = plusDi[index];
    final minus = minusDi[index];
    if (plus == null || minus == null) return null;
    final sum = plus + minus;
    if (sum == 0) return null;
    return ((plus - minus).abs() / sum) * 100;
  });
  return _smaNullable(dx, period);
}

List<double?> _directionalMovement(
  List<Candle> candles,
  int period,
  String mode,
) {
  final plusDm = List<double>.filled(candles.length, 0);
  final minusDm = List<double>.filled(candles.length, 0);
  final trueRange = List<double>.filled(candles.length, 0);
  for (var index = 1; index < candles.length; index++) {
    final upMove = candles[index].high - candles[index - 1].high;
    final downMove = candles[index - 1].low - candles[index].low;
    plusDm[index] = upMove > downMove && upMove > 0 ? upMove : 0;
    minusDm[index] = downMove > upMove && downMove > 0 ? downMove : 0;
    trueRange[index] = [
      candles[index].high - candles[index].low,
      (candles[index].high - candles[index - 1].close).abs(),
      (candles[index].low - candles[index - 1].close).abs(),
    ].reduce(max);
  }
  final smoothedPlus = _sma(plusDm, period);
  final smoothedMinus = _sma(minusDm, period);
  final smoothedTr = _sma(trueRange, period);
  return List<double?>.generate(candles.length, (index) {
    final tr = smoothedTr[index];
    if (tr == null || tr == 0) return null;
    final plusDi = ((smoothedPlus[index] ?? 0) / tr) * 100;
    final minusDi = ((smoothedMinus[index] ?? 0) / tr) * 100;
    switch (mode) {
      case 'minus':
        return minusDi;
      case 'spread':
        return plusDi - minusDi;
      case 'plus':
      default:
        return plusDi;
    }
  });
}

List<double?> _macdHistogram(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final fast = _intOf(params?['fastPeriod'] ?? params?['fast'], fallback: 12)!;
  final slow = _intOf(params?['slowPeriod'] ?? params?['slow'], fallback: 26)!;
  final signal = _intOf(
    params?['signalPeriod'] ?? params?['signal'],
    fallback: 9,
  )!;
  final fastEma = _ema(values, fast);
  final slowEma = _ema(values, slow);
  final macdLine = List<double?>.generate(values.length, (index) {
    final fastValue = fastEma[index];
    final slowValue = slowEma[index];
    return fastValue == null || slowValue == null
        ? null
        : fastValue - slowValue;
  });
  final signalLine = _emaNullable(macdLine, signal);
  return List<double?>.generate(values.length, (index) {
    final value = macdLine[index];
    final signalValue = signalLine[index];
    return value == null || signalValue == null ? null : value - signalValue;
  });
}

List<double?> _ppoHistogram(List<double> values, Map<String, dynamic>? params) {
  final fast = _intOf(params?['fastPeriod'] ?? params?['fast'], fallback: 12)!;
  final slow = _intOf(params?['slowPeriod'] ?? params?['slow'], fallback: 26)!;
  final signal = _intOf(
    params?['signalPeriod'] ?? params?['signal'],
    fallback: 9,
  )!;
  final fastEma = _ema(values, fast);
  final slowEma = _ema(values, slow);
  final ppoLine = List<double?>.generate(values.length, (index) {
    final fastValue = fastEma[index];
    final slowValue = slowEma[index];
    if (fastValue == null || slowValue == null || slowValue == 0) {
      return null;
    }
    return ((fastValue - slowValue) / slowValue) * 100;
  });
  final signalLine = _emaNullable(ppoLine, signal);
  return List<double?>.generate(values.length, (index) {
    final value = ppoLine[index];
    final signalValue = signalLine[index];
    return value == null || signalValue == null ? null : value - signalValue;
  });
}

List<double?> _trix(List<double> values, int period) {
  final first = _ema(values, period);
  final second = _emaNullable(first, period);
  final third = _emaNullable(second, period);
  return List<double?>.generate(values.length, (index) {
    if (index == 0 || third[index] == null || third[index - 1] == null) {
      return null;
    }
    final previous = third[index - 1]!;
    if (previous == 0) return null;
    return ((third[index]! - previous) / previous) * 100;
  });
}

List<double?> _trueStrengthIndex(
  List<double> values,
  Map<String, dynamic>? params,
) {
  final longPeriod = _intOf(
    params?['longPeriod'] ?? params?['long'],
    fallback: 25,
  )!;
  final shortPeriod = _intOf(
    params?['shortPeriod'] ?? params?['short'],
    fallback: 13,
  )!;
  final momentum = List<double?>.generate(
    values.length,
    (index) => index == 0 ? null : values[index] - values[index - 1],
  );
  final absMomentum = momentum.map((value) => value?.abs()).toList();
  final smoothedMomentum = _emaNullable(
    _emaNullable(momentum, longPeriod),
    shortPeriod,
  );
  final smoothedAbsMomentum = _emaNullable(
    _emaNullable(absMomentum, longPeriod),
    shortPeriod,
  );
  return List<double?>.generate(values.length, (index) {
    final numerator = smoothedMomentum[index];
    final denominator = smoothedAbsMomentum[index];
    if (numerator == null || denominator == null || denominator == 0) {
      return null;
    }
    return (numerator / denominator) * 100;
  });
}

List<double?> _bollingerZScore(List<double> values, int period) =>
    List.generate(values.length, (index) {
      final bands = _bollingerBandsAt(values, index, max(1, period), 1);
      if (bands == null) return null;
      final std = bands.upper - bands.middle;
      return std > 0 ? (values[index] - bands.middle) / std : 0;
    });

List<double?> _atr(List<Candle> candles, int period) {
  final trueRanges = List<double>.generate(candles.length, (index) {
    final candle = candles[index];
    final previousClose = index > 0 ? candles[index - 1].close : candle.close;
    return [
      candle.high - candle.low,
      (candle.high - previousClose).abs(),
      (candle.low - previousClose).abs(),
    ].reduce(max);
  });
  return _sma(trueRanges, period);
}

List<double?> _rollingExtreme(
  List<double> values,
  int period,
  double Function(double, double) fn,
) => List.generate(values.length, (index) {
  if (index + 1 < period) return null;
  return values.sublist(index + 1 - period, index + 1).reduce(fn);
});

List<double?> _drawdownPct(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final high = values.sublist(index + 1 - period, index + 1).reduce(max);
      if (high == 0) return null;
      return ((values[index] - high) / high) * 100;
    });

List<double?> _rollingMaxDrawdownPct(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final window = values.sublist(index + 1 - period, index + 1);
      var high = window.first;
      var maxDrawdown = 0.0;
      for (final value in window) {
        high = max(high, value);
        if (high == 0) return null;
        maxDrawdown = min(maxDrawdown, (value - high) / high * 100);
      }
      return maxDrawdown;
    });

List<double?> _drawdownDurationBars(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final start = index + 1 - period;
      var highIndex = start;
      var high = values[start];
      for (var i = start + 1; i <= index; i++) {
        if (values[i] >= high) {
          high = values[i];
          highIndex = i;
        }
      }
      return (index - highIndex).toDouble();
    });

List<double?> _distanceToHighPct(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final high = values.sublist(index + 1 - period, index + 1).reduce(max);
      if (high == 0) return null;
      return ((high - values[index]) / high) * 100;
    });

List<double?> _distanceToLowPct(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index + 1 < period) return null;
      final low = values.sublist(index + 1 - period, index + 1).reduce(min);
      if (low == 0) return null;
      return ((values[index] - low) / low.abs()) * 100;
    });

List<double?> _breakoutPct(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      final previousHigh = values.sublist(index - period, index).reduce(max);
      if (previousHigh == 0) return null;
      return ((values[index] - previousHigh) / previousHigh) * 100;
    });

List<double?> _breakdownPct(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      final previousLow = values.sublist(index - period, index).reduce(min);
      if (previousLow == 0) return null;
      return ((previousLow - values[index]) / previousLow.abs()) * 100;
    });

List<double?> _atrPct(List<Candle> candles, int period) {
  final atrValues = _atr(candles, period);
  return List<double?>.generate(candles.length, (index) {
    final atrValue = atrValues[index];
    final close = candles[index].close;
    if (atrValue == null || close == 0) return null;
    return atrValue / close * 100;
  });
}

List<double?> _atrStopDistancePct(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final period = max(1, _intOf(params?['period'], fallback: 14)!);
  final multiplier = (_numOf(params?['atrMultiplier']) ?? 2).toDouble();
  final atrValues = _atr(candles, period);
  return List<double?>.generate(candles.length, (index) {
    final atrValue = atrValues[index];
    final close = candles[index].close;
    if (atrValue == null || close == 0) return null;
    return atrValue * multiplier / close * 100;
  });
}

List<double?> _riskRewardRatio(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final targetPeriod = max(1, _intOf(params?['targetPeriod'], fallback: 20)!);
  final atrPeriod = max(1, _intOf(params?['atrPeriod'], fallback: 14)!);
  final multiplier = max(
    0.0,
    (_numOf(params?['atrMultiplier']) ?? 2).toDouble(),
  );
  final atrValues = _atr(candles, atrPeriod);
  return List<double?>.generate(candles.length, (index) {
    if (index + 1 < targetPeriod) return null;
    final atrValue = atrValues[index];
    if (atrValue == null || atrValue == 0 || multiplier == 0) return null;
    final window = candles.sublist(index + 1 - targetPeriod, index + 1);
    final targetHigh = window.map((candle) => candle.high).reduce(max);
    final reward = max(0.0, targetHigh - candles[index].close);
    final risk = atrValue * multiplier;
    return risk == 0 ? null : reward / risk;
  });
}

List<double?> _chandelierStopDistancePct(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final period = max(1, _intOf(params?['period'], fallback: 22)!);
  final atrPeriod = max(1, _intOf(params?['atrPeriod'], fallback: period)!);
  final multiplier = (_numOf(params?['atrMultiplier']) ?? 3).toDouble();
  final atrValues = _atr(candles, atrPeriod);
  return List<double?>.generate(candles.length, (index) {
    if (index + 1 < period) return null;
    final atrValue = atrValues[index];
    final close = candles[index].close;
    if (atrValue == null || close == 0) return null;
    final window = candles.sublist(index + 1 - period, index + 1);
    final highestHigh = window.map((candle) => candle.high).reduce(max);
    final stop = highestHigh - multiplier * atrValue;
    return (close - stop) / close * 100;
  });
}

({List<double?> direction, List<double?> distancePct}) _supertrendComponents(
  List<Candle> candles,
  Map<String, dynamic>? params,
) {
  final period = max(1, _intOf(params?['period'], fallback: 10)!);
  final multiplier = (_numOf(params?['atrMultiplier']) ?? 3).toDouble();
  final atrValues = _atr(candles, period);
  final direction = List<double?>.filled(candles.length, null);
  final distancePct = List<double?>.filled(candles.length, null);
  double? upperBand;
  double? lowerBand;
  double? trendLine;
  var trend = 1;
  for (var index = 0; index < candles.length; index++) {
    final atrValue = atrValues[index];
    if (atrValue == null) continue;
    final candle = candles[index];
    final midpoint = (candle.high + candle.low) / 2;
    final basicUpper = midpoint + multiplier * atrValue;
    final basicLower = midpoint - multiplier * atrValue;
    if (upperBand == null || lowerBand == null || index == 0) {
      upperBand = basicUpper;
      lowerBand = basicLower;
    } else {
      final previousClose = candles[index - 1].close;
      upperBand = basicUpper < upperBand || previousClose > upperBand
          ? basicUpper
          : upperBand;
      lowerBand = basicLower > lowerBand || previousClose < lowerBand
          ? basicLower
          : lowerBand;
    }
    if (trendLine == null) {
      trend = candle.close >= lowerBand ? 1 : -1;
    } else if (trendLine == upperBand) {
      trend = candle.close > upperBand ? 1 : -1;
    } else {
      trend = candle.close < lowerBand ? -1 : 1;
    }
    trendLine = trend == 1 ? lowerBand : upperBand;
    direction[index] = trend.toDouble();
    final close = candle.close;
    distancePct[index] = close == 0 ? null : (close - trendLine) / close * 100;
  }
  return (direction: direction, distancePct: distancePct);
}

List<double?> _intradayRangePct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      final close = candles[index].close;
      if (close == 0) return null;
      return (candles[index].high - candles[index].low) / close * 100;
    });

List<double?> _gapPct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      if (index == 0) return null;
      final previousClose = candles[index - 1].close;
      if (previousClose == 0) return null;
      return (candles[index].open - previousClose) / previousClose * 100;
    });

List<double?> _closeLocationPct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      final range = candles[index].high - candles[index].low;
      if (range == 0) return null;
      return (candles[index].close - candles[index].low) / range * 100;
    });

List<double?> _bodyReturnPct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      final open = candles[index].open;
      if (open == 0) return null;
      return (candles[index].close - open) / open * 100;
    });

List<double?> _upperShadowPct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      final close = candles[index].close;
      if (close == 0) return null;
      final bodyTop = max(candles[index].open, candles[index].close);
      return (candles[index].high - bodyTop) / close * 100;
    });

List<double?> _lowerShadowPct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      final close = candles[index].close;
      if (close == 0) return null;
      final bodyBottom = min(candles[index].open, candles[index].close);
      return (bodyBottom - candles[index].low) / close * 100;
    });

List<double?> _shadowBalancePct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      final close = candles[index].close;
      if (close == 0) return null;
      final bodyTop = max(candles[index].open, candles[index].close);
      final bodyBottom = min(candles[index].open, candles[index].close);
      final upper = candles[index].high - bodyTop;
      final lower = bodyBottom - candles[index].low;
      return (lower - upper) / close * 100;
    });

List<double?> _bodyToRangePct(List<Candle> candles) =>
    List<double?>.generate(candles.length, (index) {
      final range = candles[index].high - candles[index].low;
      if (range == 0) return null;
      return (candles[index].close - candles[index].open).abs() / range * 100;
    });

List<double?> _emaNullable(List<double?> values, int period) {
  final out = List<double?>.filled(values.length, null);
  if (period <= 0) return out;
  final multiplier = 2 / (period + 1);
  double? previous;
  final seeded = <double>[];
  for (var index = 0; index < values.length; index++) {
    final value = values[index];
    if (value == null) continue;
    if (previous == null) {
      seeded.add(value);
      if (seeded.length < period) continue;
      previous =
          seeded.sublist(seeded.length - period).reduce((a, b) => a + b) /
          period;
    } else {
      previous = value * multiplier + previous * (1 - multiplier);
    }
    out[index] = previous;
  }
  return out;
}

List<double?> _rsi(List<double> values, int period) =>
    List.generate(values.length, (index) {
      if (index < period) return null;
      var gains = 0.0;
      var losses = 0.0;
      for (var i = index - period + 1; i <= index; i++) {
        final change = values[i] - values[i - 1];
        if (change >= 0) {
          gains += change;
        } else {
          losses -= change;
        }
      }
      if (losses == 0) return 100.0;
      final rs = gains / losses;
      return 100 - 100 / (1 + rs);
    });

int? _intOf(Object? raw, {int? fallback}) {
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match != null) return int.tryParse(match.group(0)!);
  }
  return fallback;
}

num? _numOf(Object? raw, {num? fallback}) {
  if (raw is num) return raw;
  if (raw is String) return num.tryParse(raw) ?? fallback;
  return fallback;
}

List<double>? _windowReturns(List<double> values, int period, int index) {
  if (period < 1 || index < period) return null;
  final returns = <double>[];
  for (var i = index - period + 1; i <= index; i++) {
    if (values[i - 1] == 0) return null;
    returns.add((values[i] - values[i - 1]) / values[i - 1]);
  }
  return returns;
}

double? _percentile(List<double> values, double percentile) {
  if (values.isEmpty) return null;
  final sorted = [...values]..sort();
  if (sorted.length == 1) return sorted.first;
  final position = percentile.clamp(0.0, 100.0) / 100.0 * (sorted.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sorted[lower];
  final fraction = position - lower;
  return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction;
}

Map<String, dynamic>? _mapOf(Object? raw) {
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}
