class StrategyIndicatorRef {
  const StrategyIndicatorRef(this.type, this.period);

  final String type;
  final int period;

  String get id {
    if (type == 'close') return 'close';
    if (type == 'volume_sma') return 'vol$period';
    if (type.contains('news') ||
        type.contains('sentiment') ||
        type.contains('盘口') ||
        type.contains('资金')) {
      return type;
    }
    return '$type$period';
  }
}

class StrategyIndicatorDefinition {
  const StrategyIndicatorDefinition(
    this.type,
    this.defaultPeriod,
    this.aliases, {
    this.executable = true,
    this.category = 'technical',
    this.requiredFields = const ['close'],
    this.description = '',
    this.usesPeriodParameter = true,
    this.parameterSchema = const [],
    this.lookbackBarsOverride,
  });

  final String type;
  final int defaultPeriod;
  final List<String> aliases;
  final bool executable;
  final String category;
  final List<String> requiredFields;
  final String description;
  final bool usesPeriodParameter;
  final List<Map<String, Object>> parameterSchema;
  final int? lookbackBarsOverride;

  int get lookbackBars {
    if (lookbackBarsOverride != null) return lookbackBarsOverride!;
    if (parameterSchema.isEmpty) return usesPeriodParameter ? defaultPeriod : 1;
    var maxDefault = usesPeriodParameter ? defaultPeriod : 1;
    for (final entry in parameterSchema) {
      if (entry['lookback'] == false) continue;
      final value = entry['default'];
      if (value is num && value.isFinite) {
        maxDefault = value.toInt() > maxDefault ? value.toInt() : maxDefault;
      }
    }
    return maxDefault;
  }

  Map<String, dynamic> toHelpJson() => {
    'type': type,
    'category': category,
    'defaultPeriod': defaultPeriod,
    'lookbackBars': lookbackBars,
    'requiredFields': requiredFields,
    'executable': executable,
    'parameterSchema': parameterSchema.isNotEmpty
        ? parameterSchema
        : [
            if (usesPeriodParameter)
              {
                'name': 'period',
                'type': 'integer',
                'default': defaultPeriod,
                'min': 1,
              },
          ],
    if (description.isNotEmpty) 'description': description,
  };

  StrategyIndicatorRef? parse(String text) {
    for (final alias in aliases) {
      final match = RegExp('^(?:$alias)_?(\\d+)?\$').firstMatch(text);
      if (match == null) continue;
      return StrategyIndicatorRef(
        type,
        int.tryParse(match.group(1) ?? '') ?? defaultPeriod,
      );
    }
    return null;
  }
}

class FundStrategyIndicatorDefinition {
  const FundStrategyIndicatorDefinition(
    this.type, {
    required this.category,
    required this.source,
    required this.requiredFields,
    this.defaultPeriod = 20,
    this.description = '',
    this.parameterSchema = const [],
    this.scoreDirection = 1,
  });

  final String type;
  final String category;
  final String source;
  final List<String> requiredFields;
  final int defaultPeriod;
  final String description;
  final List<Map<String, Object>> parameterSchema;
  final int scoreDirection;

  Map<String, dynamic> toHelpJson() => {
    'type': type,
    'category': category,
    'source': source,
    'defaultPeriod': defaultPeriod,
    'requiredFields': requiredFields,
    'scoreDirection': scoreDirection,
    'executable': true,
    'parameterSchema': parameterSchema.isNotEmpty
        ? parameterSchema
        : [
            {
              'name': 'period',
              'type': 'integer',
              'default': defaultPeriod,
              'min': 1,
            },
          ],
    if (description.isNotEmpty) 'description': description,
  };
}

const strategyIndicatorRegistry = [
  StrategyIndicatorDefinition('sma', 20, [r'sma'], category: 'trend'),
  StrategyIndicatorDefinition('ema', 20, [r'ema'], category: 'trend'),
  StrategyIndicatorDefinition('rsi', 14, [r'rsi'], category: 'momentum'),
  StrategyIndicatorDefinition(
    'stochastic_rsi',
    14,
    [r'stoch_rsi', r'stochastic_rsi', r'stochrsi'],
    category: 'momentum',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 14, 'min': 1},
      {'name': 'rsiPeriod', 'type': 'integer', 'default': 14, 'min': 1},
      {'name': 'stochasticPeriod', 'type': 'integer', 'default': 14, 'min': 1},
      {'name': 'lookbackPeriod', 'type': 'integer', 'default': 28, 'min': 2},
    ],
    description:
        'Stochastic RSI oscillator scaled 0-100 using RSI values over a rolling stochastic window.',
  ),
  StrategyIndicatorDefinition(
    'macd',
    12,
    [r'macd(?:_?hist)?'],
    category: 'momentum',
    parameterSchema: [
      {'name': 'fastPeriod', 'type': 'integer', 'default': 12, 'min': 1},
      {'name': 'slowPeriod', 'type': 'integer', 'default': 26, 'min': 2},
      {'name': 'signalPeriod', 'type': 'integer', 'default': 9, 'min': 1},
    ],
  ),
  StrategyIndicatorDefinition(
    'ppo',
    12,
    [r'ppo', r'percentage_price_oscillator'],
    category: 'momentum',
    parameterSchema: [
      {'name': 'fastPeriod', 'type': 'integer', 'default': 12, 'min': 1},
      {'name': 'slowPeriod', 'type': 'integer', 'default': 26, 'min': 2},
      {'name': 'signalPeriod', 'type': 'integer', 'default': 9, 'min': 1},
    ],
    description:
        'Percentage Price Oscillator histogram: MACD-style EMA spread normalized by slow EMA.',
  ),
  StrategyIndicatorDefinition(
    'trix',
    15,
    [r'trix', r'triple_ema_roc', r'triple_ema_rate_of_change'],
    category: 'momentum',
    description:
        'TRIX oscillator: one-period rate of change of a triple EMA, expressed as a percentage.',
  ),
  StrategyIndicatorDefinition(
    'true_strength_index',
    25,
    [r'tsi', r'true_strength_index', r'truestrengthindex'],
    category: 'momentum',
    parameterSchema: [
      {'name': 'longPeriod', 'type': 'integer', 'default': 25, 'min': 2},
      {'name': 'shortPeriod', 'type': 'integer', 'default': 13, 'min': 1},
    ],
    description:
        'True Strength Index oscillator: double-smoothed momentum divided by double-smoothed absolute momentum, scaled -100 to 100.',
  ),
  StrategyIndicatorDefinition('bollinger', 20, [
    r'boll',
    r'bollinger',
  ], category: 'volatility'),
  StrategyIndicatorDefinition(
    'atr',
    14,
    [r'atr'],
    category: 'volatility',
    requiredFields: ['high', 'low', 'close'],
  ),
  StrategyIndicatorDefinition(
    'supertrend_direction',
    10,
    [r'supertrend', r'super_trend', r'supertrend_direction'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 10, 'min': 1},
      {
        'name': 'atrMultiplier',
        'type': 'number',
        'default': 3,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'Supertrend direction: 1 for close above the ATR trend line, -1 for close below it.',
  ),
  StrategyIndicatorDefinition(
    'supertrend_distance_pct',
    10,
    [
      r'supertrend_distance',
      r'supertrend_distance_pct',
      r'super_trend_distance',
    ],
    category: 'risk',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 10, 'min': 1},
      {
        'name': 'atrMultiplier',
        'type': 'number',
        'default': 3,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'Signed close distance from the Supertrend line as a percentage of close; positive above the line, negative below it.',
  ),
  StrategyIndicatorDefinition(
    'chandelier_stop_distance_pct',
    22,
    [
      r'chandelier_stop_distance',
      r'chandelier_stop_distance_pct',
      r'chandelier_exit_distance',
      r'chandelier_exit_distance_pct',
    ],
    category: 'risk',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 22, 'min': 1},
      {'name': 'atrPeriod', 'type': 'integer', 'default': 22, 'min': 1},
      {
        'name': 'atrMultiplier',
        'type': 'number',
        'default': 3,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'Signed close distance from a long Chandelier stop, rolling high minus ATR multiple, as a percentage of close; positive means close is above the stop.',
  ),
  StrategyIndicatorDefinition('highest', 20, [
    r'highest',
  ], category: 'breakout'),
  StrategyIndicatorDefinition('lowest', 20, [r'lowest'], category: 'breakout'),
  StrategyIndicatorDefinition(
    'volume_sma',
    20,
    [r'vol', r'volume_sma', r'vol_sma'],
    category: 'volume',
    requiredFields: ['volume'],
  ),
  StrategyIndicatorDefinition('price_change_pct', 20, [
    r'roc',
    r'price_change_pct',
    r'return',
  ], category: 'momentum'),
  StrategyIndicatorDefinition(
    'momentum_acceleration_pct',
    20,
    [
      r'momentum_acceleration',
      r'momentum_acceleration_pct',
      r'roc_acceleration',
      r'return_acceleration',
    ],
    category: 'momentum',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'lagPeriod', 'type': 'integer', 'default': 20, 'min': 1},
    ],
    lookbackBarsOverride: 40,
    description:
        'Momentum acceleration: current period return minus the previous lagged period return, expressed in percentage points.',
  ),
  StrategyIndicatorDefinition(
    'efficiency_ratio',
    20,
    [r'er', r'efficiency_ratio', r'kaufman_efficiency_ratio'],
    category: 'trend',
    description:
        'Kaufman-style trend efficiency ratio: absolute period change divided by cumulative absolute bar-to-bar movement.',
  ),
  StrategyIndicatorDefinition(
    'momentum_rank',
    20,
    [r'momentum_rank', r'momentum_percentile', r'rolling_momentum_rank'],
    category: 'momentum',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'rankPeriod', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Rolling percentile rank of period return within a longer rank window, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'chande_momentum_oscillator',
    14,
    [r'cmo', r'chande_momentum', r'chande_momentum_oscillator'],
    category: 'momentum',
    description:
        'Chande Momentum Oscillator scaled -100 to 100 using rolling positive and negative close-to-close changes.',
  ),
  StrategyIndicatorDefinition(
    'aroon_oscillator',
    25,
    [r'aroon', r'aroon_oscillator', r'aroonoscillator'],
    category: 'trend',
    requiredFields: ['high', 'low'],
    description:
        'Aroon oscillator: Aroon Up minus Aroon Down over a rolling high-low window, scaled -100 to 100.',
  ),
  StrategyIndicatorDefinition(
    'aroon_up',
    25,
    [r'aroon_up', r'aroonup'],
    category: 'trend',
    requiredFields: ['high', 'low'],
    description:
        'Aroon Up component: recency of the rolling high over the configured high-low window, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'aroon_down',
    25,
    [r'aroon_down', r'aroondown'],
    category: 'trend',
    requiredFields: ['high', 'low'],
    description:
        'Aroon Down component: recency of the rolling low over the configured high-low window, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'vortex_spread',
    14,
    [r'vortex', r'vortex_spread', r'vortex_indicator', r'vi_spread'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Vortex Indicator spread: VI+ minus VI- over the rolling window; positive values indicate stronger upward trend pressure.',
  ),
  StrategyIndicatorDefinition('rolling_volatility', 20, [
    r'volatility',
    r'rolling_volatility',
    r'return_volatility',
  ], category: 'volatility'),
  StrategyIndicatorDefinition(
    'donchian_width_pct',
    20,
    [r'donchian_width', r'donchian_width_pct', r'channel_width_pct'],
    category: 'volatility',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Donchian channel width as a percentage of close: rolling high-low range divided by close.',
  ),
  StrategyIndicatorDefinition(
    'range_compression_ratio',
    20,
    [
      r'range_compression',
      r'range_compression_ratio',
      r'range_contraction_ratio',
      r'volatility_contraction_ratio',
    ],
    category: 'volatility',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'baselinePeriod', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Range compression ratio: current Donchian range percent divided by a longer baseline range percent; values below 1 indicate range contraction.',
  ),
  StrategyIndicatorDefinition(
    'donchian_position_pct',
    20,
    [r'donchian_position', r'donchian_position_pct', r'channel_position_pct'],
    category: 'breakout',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Donchian channel position: close location inside the rolling high-low channel, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'keltner_width_pct',
    20,
    [r'keltner_width', r'keltner_width_pct', r'keltner_channel_width'],
    category: 'volatility',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'atrPeriod', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'atrMultiplier', 'type': 'number', 'default': 2, 'min': 0},
    ],
    description:
        'Keltner channel width as a percentage of EMA centerline, using ATR-based upper and lower bands.',
  ),
  StrategyIndicatorDefinition(
    'downside_volatility_pct',
    20,
    [r'downside_volatility', r'downside_volatility_pct', r'downside_risk'],
    category: 'risk',
    description:
        'Annualized downside-only volatility of negative returns over the rolling period, expressed as a percentage.',
  ),
  StrategyIndicatorDefinition(
    'sortino_ratio',
    20,
    [r'sortino', r'sortino_ratio', r'rolling_sortino'],
    category: 'risk',
    description:
        'Rolling annualized Sortino-style return divided by downside deviation, using close-to-close returns.',
  ),
  StrategyIndicatorDefinition(
    'sharpe_ratio',
    20,
    [r'sharpe', r'sharpe_ratio', r'rolling_sharpe'],
    category: 'risk',
    description:
        'Rolling annualized mean return divided by total return volatility, using close-to-close returns.',
  ),
  StrategyIndicatorDefinition(
    'calmar_ratio',
    60,
    [r'calmar', r'calmar_ratio', r'rolling_calmar'],
    category: 'risk',
    description:
        'Rolling period return divided by absolute maximum drawdown in the same window.',
  ),
  StrategyIndicatorDefinition(
    'ulcer_index',
    20,
    [r'ulcer', r'ulcer_index', r'rolling_ulcer_index'],
    category: 'risk',
    description:
        'Rolling root mean square percentage drawdown from the window high-water mark.',
  ),
  StrategyIndicatorDefinition(
    'gain_to_pain_ratio',
    20,
    [r'gain_to_pain', r'gain_to_pain_ratio', r'gtp_ratio'],
    category: 'risk',
    description:
        'Rolling sum of positive returns divided by absolute sum of negative returns.',
  ),
  StrategyIndicatorDefinition(
    'positive_period_ratio',
    20,
    [
      r'positive_period_ratio',
      r'positive_return_ratio',
      r'positive_periods',
      r'win_period_ratio',
    ],
    category: 'risk',
    description:
        'Share of close-to-close returns above zero in the rolling window, scaled 0-100 as return consistency evidence.',
  ),
  StrategyIndicatorDefinition(
    'negative_period_ratio',
    20,
    [
      r'negative_period_ratio',
      r'negative_return_ratio',
      r'negative_periods',
      r'loss_period_ratio',
    ],
    category: 'risk',
    description:
        'Share of close-to-close returns below zero in the rolling window, scaled 0-100 as downside frequency evidence.',
  ),
  StrategyIndicatorDefinition(
    'max_consecutive_down_bars',
    20,
    [
      r'max_consecutive_down_bars',
      r'max_down_streak',
      r'losing_streak_bars',
      r'down_streak_bars',
    ],
    category: 'risk',
    description:
        'Maximum consecutive close-to-close down bars inside the rolling window, useful as losing-streak persistence evidence.',
  ),
  StrategyIndicatorDefinition(
    'max_consecutive_up_bars',
    20,
    [
      r'max_consecutive_up_bars',
      r'max_up_streak',
      r'winning_streak_bars',
      r'up_streak_bars',
    ],
    category: 'risk',
    description:
        'Maximum consecutive close-to-close up bars inside the rolling window, useful as winning-streak persistence evidence.',
  ),
  StrategyIndicatorDefinition(
    'return_skewness',
    60,
    [r'return_skewness', r'rolling_skewness', r'skewness', r'return_skew'],
    category: 'risk',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
    ],
    description:
        'Rolling close-to-close return skewness; positive values indicate right-tailed returns and negative values indicate downside asymmetry.',
  ),
  StrategyIndicatorDefinition(
    'return_kurtosis',
    60,
    [r'return_kurtosis', r'rolling_kurtosis', r'kurtosis', r'excess_kurtosis'],
    category: 'risk',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
    ],
    description:
        'Rolling close-to-close excess kurtosis; higher values indicate fatter-tailed return distribution risk.',
  ),
  StrategyIndicatorDefinition(
    'omega_ratio',
    20,
    [r'omega', r'omega_ratio', r'rolling_omega'],
    category: 'risk',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 2},
      {
        'name': 'thresholdReturn',
        'type': 'number',
        'default': 0,
        'lookback': false,
      },
    ],
    description:
        'Rolling Omega ratio: return gains above threshold divided by shortfall below threshold.',
  ),
  StrategyIndicatorDefinition(
    'tail_ratio',
    60,
    [r'tail_ratio', r'rolling_tail_ratio', r'upside_downside_tail_ratio'],
    category: 'risk',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
      {
        'name': 'upperPercentile',
        'type': 'number',
        'default': 95,
        'min': 50,
        'max': 100,
        'lookback': false,
      },
      {
        'name': 'lowerPercentile',
        'type': 'number',
        'default': 5,
        'min': 0,
        'max': 50,
        'lookback': false,
      },
    ],
    description:
        'Rolling upside/downside tail ratio using upper and lower return percentiles.',
  ),
  StrategyIndicatorDefinition(
    'value_at_risk_pct',
    60,
    [r'value_at_risk', r'value_at_risk_pct', r'var', r'var_pct'],
    category: 'risk',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
      {
        'name': 'confidence',
        'type': 'number',
        'default': 95,
        'min': 50,
        'max': 99.9,
        'lookback': false,
      },
    ],
    description:
        'Rolling historical Value at Risk based on close-to-close returns, expressed as a positive loss percentage at the configured confidence level.',
  ),
  StrategyIndicatorDefinition(
    'conditional_value_at_risk_pct',
    60,
    [
      r'conditional_value_at_risk',
      r'conditional_value_at_risk_pct',
      r'cvar',
      r'cvar_pct',
      r'expected_shortfall',
    ],
    category: 'risk',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
      {
        'name': 'confidence',
        'type': 'number',
        'default': 95,
        'min': 50,
        'max': 99.9,
        'lookback': false,
      },
    ],
    description:
        'Rolling Conditional Value at Risk / expected shortfall based on tail close-to-close losses, expressed as a positive loss percentage.',
  ),
  StrategyIndicatorDefinition(
    'volatility_regime',
    20,
    [r'volatility_regime', r'vol_regime', r'volatility_state'],
    category: 'volatility',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 2},
      {'name': 'shortPeriod', 'type': 'integer', 'default': 20, 'min': 2},
      {'name': 'baselinePeriod', 'type': 'integer', 'default': 60, 'min': 3},
    ],
    description:
        'Volatility regime score: 1 when short-window volatility is above its baseline, -1 when materially below baseline, otherwise 0.',
  ),
  StrategyIndicatorDefinition(
    'volatility_percentile',
    20,
    [r'volatility_percentile', r'vol_percentile', r'volatility_rank'],
    category: 'volatility',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 2},
      {'name': 'baselinePeriod', 'type': 'integer', 'default': 60, 'min': 3},
    ],
    description:
        'Rolling volatility percentile: current realized volatility percentile within its own baseline window, scaled 0-100.',
  ),
  StrategyIndicatorDefinition('ema_slope', 20, [
    r'ema_slope',
    r'emaslope',
  ], category: 'trend'),
  StrategyIndicatorDefinition(
    'moving_average_regime',
    50,
    [r'ma_regime', r'moving_average_regime', r'ma_trend_regime'],
    category: 'trend',
    parameterSchema: [
      {'name': 'fastPeriod', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'slowPeriod', 'type': 'integer', 'default': 50, 'min': 2},
    ],
    description:
        'Trend regime score: 1 when close > fast MA > slow MA, -1 when close < fast MA < slow MA, otherwise 0.',
  ),
  StrategyIndicatorDefinition(
    'kama_distance_pct',
    10,
    [
      r'kama_distance',
      r'kama_distance_pct',
      r'adaptive_ma_distance',
      r'adaptive_ma_distance_pct',
    ],
    category: 'trend',
    parameterSchema: [
      {'name': 'erPeriod', 'type': 'integer', 'default': 10, 'min': 2},
      {'name': 'fastPeriod', 'type': 'integer', 'default': 2, 'min': 1},
      {'name': 'slowPeriod', 'type': 'integer', 'default': 30, 'min': 2},
    ],
    description:
        'Close distance from Kaufman Adaptive Moving Average as a percentage of KAMA.',
  ),
  StrategyIndicatorDefinition(
    'kama_slope_pct',
    10,
    [
      r'kama_slope',
      r'kama_slope_pct',
      r'adaptive_ma_slope',
      r'adaptive_ma_slope_pct',
    ],
    category: 'trend',
    parameterSchema: [
      {'name': 'erPeriod', 'type': 'integer', 'default': 10, 'min': 2},
      {'name': 'fastPeriod', 'type': 'integer', 'default': 2, 'min': 1},
      {'name': 'slowPeriod', 'type': 'integer', 'default': 30, 'min': 2},
    ],
    description: 'One-bar percentage slope of Kaufman Adaptive Moving Average.',
  ),
  StrategyIndicatorDefinition(
    'linear_regression_slope_pct',
    20,
    [
      r'linear_regression_slope',
      r'linear_regression_slope_pct',
      r'linreg_slope',
      r'regression_slope',
    ],
    category: 'trend',
    description:
        'Rolling least-squares trend slope expressed as percentage of the fitted start price over the window.',
  ),
  StrategyIndicatorDefinition(
    'linear_regression_r2',
    20,
    [r'linear_regression_r2', r'linreg_r2', r'regression_r2', r'trend_r2'],
    category: 'trend',
    description:
        'Rolling coefficient of determination for close-price linear regression, scaled 0-1 as trend quality evidence.',
  ),
  StrategyIndicatorDefinition(
    'ma_distance_pct',
    20,
    [r'ma_distance', r'ma_distance_pct', r'distance_to_ma', r'ma_gap_pct'],
    category: 'trend',
    description:
        'Percentage distance between close and a moving average: positive above MA, negative below MA.',
  ),
  StrategyIndicatorDefinition(
    'price_zscore',
    20,
    [r'price_zscore', r'zscore', r'close_zscore'],
    category: 'mean_reversion',
    description:
        'Rolling price z-score: positive when close is above its rolling mean, negative when below.',
  ),
  StrategyIndicatorDefinition(
    'bollinger_bandwidth',
    20,
    [r'bollinger_bandwidth', r'boll_bandwidth', r'bb_width'],
    category: 'volatility',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {
        'name': 'stdDevMultiplier',
        'type': 'number',
        'default': 2,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'Bollinger Bandwidth: upper-lower band width divided by middle band, expressed as a percentage.',
  ),
  StrategyIndicatorDefinition(
    'bollinger_percent_b',
    20,
    [r'bollinger_percent_b', r'boll_percent_b', r'bb_percent_b', r'percent_b'],
    category: 'mean_reversion',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {
        'name': 'stdDevMultiplier',
        'type': 'number',
        'default': 2,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'Bollinger %B: close position inside the lower-to-upper band range, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'bollinger_band_distance_pct',
    20,
    [
      r'bollinger_band_distance',
      r'bollinger_band_distance_pct',
      r'bb_band_distance',
      r'bb_distance_pct',
    ],
    category: 'mean_reversion',
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {
        'name': 'stdDevMultiplier',
        'type': 'number',
        'default': 2,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'Signed close distance from the nearest Bollinger band as a percentage of close; positive above the upper band, negative below the lower band, zero inside bands.',
  ),
  StrategyIndicatorDefinition(
    'kdj',
    9,
    [r'kdj', r'stochastic'],
    category: 'momentum',
    requiredFields: ['high', 'low', 'close'],
  ),
  StrategyIndicatorDefinition(
    'stochastic_d',
    9,
    [r'stochastic_d', r'kdj_d', r'kd_d'],
    category: 'momentum',
    requiredFields: ['high', 'low', 'close'],
    description:
        'KDJ D line: smoothed stochastic K value over the high-low-close window.',
  ),
  StrategyIndicatorDefinition(
    'stochastic_j',
    9,
    [r'stochastic_j', r'kdj_j', r'kd_j'],
    category: 'momentum',
    requiredFields: ['high', 'low', 'close'],
    description:
        'KDJ J line: 3*K - 2*D, useful as a faster stochastic momentum component.',
  ),
  StrategyIndicatorDefinition(
    'adx',
    14,
    [r'adx'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
  ),
  StrategyIndicatorDefinition(
    'dmi_plus',
    14,
    [r'dmi_plus', r'plus_di', r'pdi'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Positive Directional Indicator (+DI): upward directional movement divided by true range, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'dmi_minus',
    14,
    [r'dmi_minus', r'minus_di', r'mdi'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Negative Directional Indicator (-DI): downward directional movement divided by true range, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'dmi_spread',
    14,
    [r'dmi_spread', r'di_spread', r'directional_spread'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Directional Movement spread: +DI minus -DI, positive for upward directional pressure and negative for downward pressure.',
  ),
  StrategyIndicatorDefinition(
    'turnover_rate',
    1,
    [r'turnover', r'turnover_rate', r'turnoverRate'],
    category: 'liquidity',
    requiredFields: ['turnoverRate'],
    usesPeriodParameter: false,
  ),
  StrategyIndicatorDefinition(
    'liquidity_ratio',
    20,
    [r'liquidity_ratio', r'volume_ratio', r'vol_ratio'],
    category: 'liquidity',
    requiredFields: ['volume'],
    description:
        'Relative volume / liquidity ratio: current volume divided by rolling average volume over the configured period.',
  ),
  StrategyIndicatorDefinition(
    'volume_zscore',
    20,
    [r'volume_zscore', r'vol_zscore', r'volume_anomaly'],
    category: 'volume',
    requiredFields: ['volume'],
    description:
        'Rolling volume z-score: positive when volume is above its rolling mean, negative when below.',
  ),
  StrategyIndicatorDefinition(
    'volume_breakout',
    20,
    [r'volume_breakout', r'vol_breakout', r'volume_expansion'],
    category: 'volume',
    requiredFields: ['volume'],
    description:
        'Volume breakout ratio: current volume divided by rolling average volume over period.',
  ),
  StrategyIndicatorDefinition(
    'volume_oscillator_pct',
    12,
    [r'pvo', r'volume_oscillator', r'volume_oscillator_pct'],
    category: 'volume',
    requiredFields: ['volume'],
    parameterSchema: [
      {'name': 'fastPeriod', 'type': 'integer', 'default': 12, 'min': 1},
      {'name': 'slowPeriod', 'type': 'integer', 'default': 26, 'min': 2},
    ],
    description:
        'Percentage Volume Oscillator: fast volume EMA minus slow volume EMA, divided by slow volume EMA.',
  ),
  StrategyIndicatorDefinition(
    'volume_rate_of_change_pct',
    20,
    [r'vroc', r'volume_roc', r'volume_rate_of_change_pct'],
    category: 'volume',
    requiredFields: ['volume'],
    description:
        'Volume rate of change: percentage change from volume N bars ago to current volume.',
  ),
  StrategyIndicatorDefinition(
    'volume_percentile',
    60,
    [r'volume_percentile', r'volume_rank', r'volume_percentile_rank'],
    category: 'volume',
    requiredFields: ['volume'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Rolling percentile rank of current volume within the configured volume window, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'rolling_vwap',
    20,
    [r'rolling_vwap', r'vwap', r'vwap_price'],
    category: 'volume',
    requiredFields: ['high', 'low', 'close', 'volume'],
    description:
        'Rolling VWAP price using typical price weighted by volume over the configured period.',
  ),
  StrategyIndicatorDefinition(
    'money_flow_index',
    14,
    [r'mfi', r'money_flow_index', r'moneyflowindex'],
    category: 'volume',
    requiredFields: ['high', 'low', 'close', 'volume'],
    description:
        'Money Flow Index oscillator using typical price and volume, scaled 0-100.',
  ),
  StrategyIndicatorDefinition(
    'on_balance_volume',
    1,
    [r'obv', r'on_balance_volume', r'onbalancevolume'],
    category: 'volume',
    requiredFields: ['close', 'volume'],
    usesPeriodParameter: false,
    description:
        'Cumulative On-Balance Volume: adds volume on up closes and subtracts it on down closes.',
  ),
  StrategyIndicatorDefinition(
    'volume_price_trend',
    1,
    [r'vpt', r'volume_price_trend', r'volumepricetrend'],
    category: 'volume',
    requiredFields: ['close', 'volume'],
    usesPeriodParameter: false,
    description:
        'Cumulative Volume Price Trend: adds volume weighted by close-to-close percentage change.',
  ),
  StrategyIndicatorDefinition(
    'positive_volume_index',
    1,
    [r'pvi', r'positive_volume_index', r'positivevolumeindex'],
    category: 'volume',
    requiredFields: ['close', 'volume'],
    usesPeriodParameter: false,
    description:
        'Positive Volume Index: cumulative close return only on bars where volume increases from the prior bar.',
  ),
  StrategyIndicatorDefinition(
    'negative_volume_index',
    1,
    [r'nvi', r'negative_volume_index', r'negativevolumeindex'],
    category: 'volume',
    requiredFields: ['close', 'volume'],
    usesPeriodParameter: false,
    description:
        'Negative Volume Index: cumulative close return only on bars where volume decreases from the prior bar.',
  ),
  StrategyIndicatorDefinition(
    'accumulation_distribution_line',
    1,
    [
      r'adl',
      r'accumulation_distribution',
      r'accumulation_distribution_line',
      r'accdist',
    ],
    category: 'volume',
    requiredFields: ['high', 'low', 'close', 'volume'],
    usesPeriodParameter: false,
    description:
        'Cumulative Accumulation/Distribution Line using close location value weighted by volume.',
  ),
  StrategyIndicatorDefinition(
    'chaikin_money_flow',
    20,
    [r'cmf', r'chaikin_money_flow', r'chaikinmoneyflow'],
    category: 'volume',
    requiredFields: ['high', 'low', 'close', 'volume'],
    description:
        'Chaikin Money Flow using close location value weighted by rolling volume.',
  ),
  StrategyIndicatorDefinition(
    'force_index',
    13,
    [r'force_index', r'elder_force_index', r'efi'],
    category: 'volume',
    requiredFields: ['close', 'volume'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 13, 'min': 1},
      {'name': 'smoothingPeriod', 'type': 'integer', 'default': 13, 'min': 1},
    ],
    description:
        'Elder Force Index: close-to-close price change multiplied by volume, smoothed with EMA.',
  ),
  StrategyIndicatorDefinition(
    'ease_of_movement',
    14,
    [r'ease_of_movement', r'eom', r'easeofmovement'],
    category: 'volume',
    requiredFields: ['high', 'low', 'volume'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 14, 'min': 1},
      {
        'name': 'volumeDivisor',
        'type': 'number',
        'default': 1000000,
        'min': 1,
        'lookback': false,
      },
    ],
    description:
        'Ease of Movement: midpoint movement scaled by high-low range and volume, smoothed over period.',
  ),
  StrategyIndicatorDefinition(
    'vwap_distance_pct',
    20,
    [r'vwap_distance', r'vwap_distance_pct', r'rolling_vwap_distance'],
    category: 'volume',
    requiredFields: ['high', 'low', 'close', 'volume'],
    description:
        'Close distance from rolling VWAP, expressed as a percentage of VWAP.',
  ),
  StrategyIndicatorDefinition(
    'ichimoku_cloud_position',
    52,
    [r'ichimoku', r'ichimoku_cloud', r'ichimoku_cloud_position'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'conversionPeriod', 'type': 'integer', 'default': 9, 'min': 1},
      {'name': 'basePeriod', 'type': 'integer', 'default': 26, 'min': 2},
      {'name': 'spanBPeriod', 'type': 'integer', 'default': 52, 'min': 3},
    ],
    description:
        'Ichimoku cloud position: 1 above cloud, -1 below cloud, 0 inside cloud, using historical windows only.',
  ),
  StrategyIndicatorDefinition(
    'parabolic_sar_direction',
    2,
    [r'psar', r'parabolic_sar', r'parabolic_sar_direction'],
    category: 'trend',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {
        'name': 'acceleration',
        'type': 'number',
        'default': 0.02,
        'min': 0.001,
        'lookback': false,
      },
      {
        'name': 'maxAcceleration',
        'type': 'number',
        'default': 0.2,
        'min': 0.01,
        'lookback': false,
      },
    ],
    description:
        'Parabolic SAR trend direction: 1 when close is above SAR, -1 when close is below SAR.',
  ),
  StrategyIndicatorDefinition(
    'commodity_channel_index',
    20,
    [r'cci', r'commodity_channel_index', r'commoditychannelindex'],
    category: 'momentum',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Commodity Channel Index using typical price deviation from its moving average.',
  ),
  StrategyIndicatorDefinition(
    'williams_r',
    14,
    [r'williams_r', r'williamsr', r'willr', r'wr'],
    category: 'momentum',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Williams %R oscillator over the high-low range, scaled from -100 to 0.',
  ),
  StrategyIndicatorDefinition(
    'drawdown_pct',
    20,
    [r'drawdown', r'drawdown_pct', r'rolling_drawdown'],
    category: 'risk',
    description: 'Percentage drawdown from the rolling high over period.',
  ),
  StrategyIndicatorDefinition(
    'rolling_max_drawdown_pct',
    20,
    [
      r'rolling_max_drawdown',
      r'rolling_max_drawdown_pct',
      r'window_max_drawdown',
      r'window_max_drawdown_pct',
    ],
    category: 'risk',
    description:
        'Worst peak-to-trough percentage drawdown observed inside the rolling window.',
  ),
  StrategyIndicatorDefinition(
    'drawdown_duration_bars',
    20,
    [
      r'drawdown_duration',
      r'drawdown_duration_bars',
      r'underwater_bars',
      r'recovery_duration',
    ],
    category: 'risk',
    description:
        'Number of bars since the latest rolling high-water mark; zero when price is at the rolling high.',
  ),
  StrategyIndicatorDefinition(
    'distance_to_high_pct',
    20,
    [r'distance_to_high', r'distance_to_high_pct', r'high_distance'],
    category: 'breakout',
    description: 'Percentage distance from the rolling high over period.',
  ),
  StrategyIndicatorDefinition(
    'distance_to_low_pct',
    20,
    [r'distance_to_low', r'distance_to_low_pct', r'low_distance'],
    category: 'risk',
    description:
        'Percentage distance above the rolling low over period, useful as support-distance evidence.',
  ),
  StrategyIndicatorDefinition(
    'breakout_pct',
    20,
    [r'breakout', r'breakout_pct', r'new_high_breakout'],
    category: 'breakout',
    description:
        'Percentage breakout above the previous rolling high over period; positive only when close exceeds the prior high.',
  ),
  StrategyIndicatorDefinition(
    'breakdown_pct',
    20,
    [r'breakdown', r'breakdown_pct', r'new_low_breakdown'],
    category: 'risk',
    description:
        'Percentage breakdown below the previous rolling low over period; positive only when close falls below prior support.',
  ),
  StrategyIndicatorDefinition(
    'atr_pct',
    14,
    [r'atr_pct', r'atr_percent', r'normalized_atr'],
    category: 'risk',
    requiredFields: ['high', 'low', 'close'],
    description: 'ATR as a percentage of close price.',
  ),
  StrategyIndicatorDefinition(
    'atr_stop_distance_pct',
    14,
    [r'atr_stop_distance', r'atr_stop_distance_pct', r'atr_risk_distance'],
    category: 'risk',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 14, 'min': 1},
      {
        'name': 'atrMultiplier',
        'type': 'number',
        'default': 2,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'ATR stop distance as a percentage of close: ATR multiplied by the configured stop multiplier.',
  ),
  StrategyIndicatorDefinition(
    'risk_reward_ratio',
    20,
    [r'risk_reward', r'risk_reward_ratio', r'reward_risk_ratio'],
    category: 'risk',
    requiredFields: ['high', 'low', 'close'],
    parameterSchema: [
      {'name': 'targetPeriod', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'atrPeriod', 'type': 'integer', 'default': 14, 'min': 1},
      {
        'name': 'atrMultiplier',
        'type': 'number',
        'default': 2,
        'min': 0,
        'lookback': false,
      },
    ],
    description:
        'Estimated reward-to-risk ratio: upside distance to recent rolling high divided by ATR stop distance.',
  ),
  StrategyIndicatorDefinition(
    'intraday_range_pct',
    1,
    [r'intraday_range', r'intraday_range_pct', r'daily_range_pct'],
    category: 'volatility',
    requiredFields: ['high', 'low', 'close'],
    description: 'Daily high-low range as a percentage of close price.',
  ),
  StrategyIndicatorDefinition(
    'gap_pct',
    1,
    [r'gap', r'gap_pct', r'opening_gap_pct'],
    category: 'price_action',
    requiredFields: ['open', 'close'],
    description:
        'Opening gap percentage from previous close to current open price.',
  ),
  StrategyIndicatorDefinition(
    'close_location_pct',
    1,
    [r'close_location', r'close_location_pct', r'close_position_pct'],
    category: 'price_action',
    requiredFields: ['high', 'low', 'close'],
    description:
        'Close location within the daily high-low range, scaled 0-100 from low to high.',
  ),
  StrategyIndicatorDefinition(
    'body_return_pct',
    1,
    [r'body_return', r'body_return_pct', r'open_close_return_pct'],
    category: 'price_action',
    requiredFields: ['open', 'close'],
    description:
        'Open-to-close candle body return percentage for the current bar.',
  ),
  StrategyIndicatorDefinition(
    'upper_shadow_pct',
    1,
    [r'upper_shadow', r'upper_shadow_pct', r'upper_wick_pct'],
    category: 'price_action',
    requiredFields: ['open', 'high', 'close'],
    description: 'Upper candle shadow length as a percentage of close price.',
  ),
  StrategyIndicatorDefinition(
    'lower_shadow_pct',
    1,
    [r'lower_shadow', r'lower_shadow_pct', r'lower_wick_pct'],
    category: 'price_action',
    requiredFields: ['open', 'low', 'close'],
    description: 'Lower candle shadow length as a percentage of close price.',
  ),
  StrategyIndicatorDefinition(
    'shadow_balance_pct',
    1,
    [r'shadow_balance', r'shadow_balance_pct', r'wick_balance_pct'],
    category: 'price_action',
    requiredFields: ['open', 'high', 'low', 'close'],
    usesPeriodParameter: false,
    description:
        'Signed candle shadow balance as a percentage of close: positive for stronger lower shadow, negative for stronger upper shadow.',
  ),
  StrategyIndicatorDefinition(
    'body_to_range_pct',
    1,
    [r'body_to_range', r'body_to_range_pct', r'candle_body_ratio'],
    category: 'price_action',
    requiredFields: ['open', 'high', 'low', 'close'],
    description:
        'Candle body size as a percentage of the daily high-low range.',
  ),
];

const fundStrategyIndicatorCatalog = [
  'nav_trend',
  'rolling_return',
  'fund_drawdown',
  'fund_rolling_max_drawdown',
  'fund_average_drawdown',
  'fund_ulcer_index',
  'fund_drawdown_duration_bars',
  'fund_volatility',
  'fund_downside_volatility',
  'fund_sharpe',
  'fund_sortino',
  'fund_calmar',
  'fund_recovery_ratio',
  'fund_gain_to_pain',
  'fund_momentum_acceleration',
  'fund_omega',
  'fund_tail_ratio',
  'fund_positive_period_ratio',
  'fund_negative_period_ratio',
  'fund_max_consecutive_down_periods',
  'fund_max_consecutive_up_periods',
  'fund_return_skewness',
  'fund_return_kurtosis',
  'fund_value_at_risk',
  'fund_conditional_value_at_risk',
  'money_yield',
  'seven_day_yield',
  'dca_interval',
];

const fundStrategyIndicatorRegistry = [
  FundStrategyIndicatorDefinition(
    'nav_trend',
    category: 'ordinary_fund_nav',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    description: 'NAV trend over the configured period.',
  ),
  FundStrategyIndicatorDefinition(
    'rolling_return',
    category: 'ordinary_fund_nav',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    description: 'NAV rolling return percentage over the configured period.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_drawdown',
    category: 'fund_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    scoreDirection: -1,
    description: 'Current drawdown from the recent NAV high.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_rolling_max_drawdown',
    category: 'fund_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description: 'Worst peak-to-trough NAV drawdown inside the rolling window.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_average_drawdown',
    category: 'fund_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Average positive NAV drawdown from rolling high-water marks inside the window.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_ulcer_index',
    category: 'fund_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
    ],
    description:
        'Rolling NAV Ulcer index: root mean square drawdown from the period high-water mark.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_drawdown_duration_bars',
    category: 'fund_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Number of NAV rows since the latest high-water mark inside the rolling window; zero means the fund is at a recent high.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_volatility',
    category: 'fund_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    scoreDirection: -1,
    description: 'Annualized NAV return volatility.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_downside_volatility',
    category: 'fund_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Annualized downside-only NAV return volatility over the rolling window.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_sharpe',
    category: 'fund_risk_adjusted',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    description: 'Annualized mean NAV return divided by total volatility.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_sortino',
    category: 'fund_risk_adjusted',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    description: 'Annualized mean NAV return divided by downside volatility.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_calmar',
    category: 'fund_risk_adjusted',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    description: 'Period NAV return divided by maximum drawdown.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_recovery_ratio',
    category: 'fund_risk_adjusted',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Period NAV return divided by average drawdown, expressing recovery efficiency relative to typical drawdown depth.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_gain_to_pain',
    category: 'fund_return_quality',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    description:
        'NAV return-quality ratio: positive return sum divided by absolute negative return sum.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_momentum_acceleration',
    category: 'fund_return_quality',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 20,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 20, 'min': 1},
      {'name': 'lagPeriod', 'type': 'integer', 'default': 20, 'min': 1},
    ],
    description:
        'NAV momentum acceleration: current period return minus the previous lagged period return.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_omega',
    category: 'fund_return_quality',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
      {
        'name': 'thresholdReturn',
        'type': 'number',
        'default': 0,
        'lookback': false,
      },
    ],
    description:
        'NAV Omega-style ratio: gains above threshold divided by shortfall below threshold.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_tail_ratio',
    category: 'fund_return_quality',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
      {
        'name': 'upperPercentile',
        'type': 'number',
        'default': 95,
        'min': 50,
        'max': 100,
        'lookback': false,
      },
      {
        'name': 'lowerPercentile',
        'type': 'number',
        'default': 5,
        'min': 0,
        'max': 50,
        'lookback': false,
      },
    ],
    description:
        'NAV upside/downside tail ratio using rolling return percentiles.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_positive_period_ratio',
    category: 'fund_return_consistency',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Share of rolling NAV return periods above zero, scaled 0-100 as return consistency evidence.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_negative_period_ratio',
    category: 'fund_return_consistency',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Share of rolling NAV return periods below zero, scaled 0-100 as downside frequency evidence.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_max_consecutive_down_periods',
    category: 'fund_return_consistency',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Maximum consecutive negative NAV return periods inside the rolling window.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_max_consecutive_up_periods',
    category: 'fund_return_consistency',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 2},
    ],
    description:
        'Maximum consecutive positive NAV return periods inside the rolling window.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_return_skewness',
    category: 'fund_return_distribution',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
    ],
    description:
        'Rolling NAV return skewness; positive values indicate right-tailed fund returns and negative values indicate downside asymmetry.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_return_kurtosis',
    category: 'fund_return_distribution',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
    ],
    description:
        'Rolling NAV return excess kurtosis; higher values indicate fatter-tailed fund return risk.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_value_at_risk',
    category: 'fund_tail_loss_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
      {
        'name': 'confidence',
        'type': 'number',
        'default': 95,
        'min': 50,
        'max': 99.9,
        'lookback': false,
      },
    ],
    description:
        'NAV historical Value at Risk based on rolling fund returns, expressed as a positive loss percentage.',
  ),
  FundStrategyIndicatorDefinition(
    'fund_conditional_value_at_risk',
    category: 'fund_tail_loss_risk',
    source: 'nav',
    requiredFields: ['date', 'nav'],
    defaultPeriod: 60,
    scoreDirection: -1,
    parameterSchema: [
      {'name': 'period', 'type': 'integer', 'default': 60, 'min': 5},
      {
        'name': 'confidence',
        'type': 'number',
        'default': 95,
        'min': 50,
        'max': 99.9,
        'lookback': false,
      },
    ],
    description:
        'NAV Conditional Value at Risk / expected shortfall based on tail fund return losses.',
  ),
  FundStrategyIndicatorDefinition(
    'money_yield',
    category: 'money_fund_yield',
    source: 'yield',
    requiredFields: ['date', 'moneyYield'],
    defaultPeriod: 7,
    description: 'Latest money-fund per-10k income evidence.',
  ),
  FundStrategyIndicatorDefinition(
    'seven_day_yield',
    category: 'money_fund_yield',
    source: 'yield',
    requiredFields: ['date', 'sevenDayYield'],
    defaultPeriod: 7,
    description: 'Latest money-fund seven-day annualized yield evidence.',
  ),
  FundStrategyIndicatorDefinition(
    'dca_interval',
    category: 'fund_observation',
    source: 'schedule',
    requiredFields: ['date'],
    defaultPeriod: 30,
    scoreDirection: 0,
    description: 'DCA observation cadence in days.',
  ),
];

final fundStrategyIndicators = fundStrategyIndicatorCatalog.toSet();

final fundStrategyIndicatorHelpCatalog = fundStrategyIndicatorRegistry
    .map((definition) => definition.toHelpJson())
    .toList();

Map<String, List<Map<String, dynamic>>>
fundStrategyIndicatorCatalogByCategory() {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final definition in fundStrategyIndicatorRegistry) {
    grouped
        .putIfAbsent(definition.category, () => <Map<String, dynamic>>[])
        .add(definition.toHelpJson());
  }
  return grouped;
}

FundStrategyIndicatorDefinition? fundStrategyIndicatorDefinition(String type) {
  for (final definition in fundStrategyIndicatorRegistry) {
    if (definition.type == type) return definition;
  }
  return null;
}

final allowedStrategyIndicators = strategyIndicatorRegistry
    .map((definition) => definition.type)
    .toSet();

final executableStrategyIndicators = strategyIndicatorRegistry
    .where((definition) => definition.executable)
    .map((definition) => definition.type)
    .toSet();

final strategyIndicatorHelpCatalog = strategyIndicatorRegistry
    .map((definition) => definition.toHelpJson())
    .toList();

Map<String, List<Map<String, dynamic>>> strategyIndicatorCatalogByCategory() {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final definition in strategyIndicatorRegistry) {
    grouped
        .putIfAbsent(definition.category, () => <Map<String, dynamic>>[])
        .add(definition.toHelpJson());
  }
  return grouped;
}

StrategyIndicatorDefinition? strategyIndicatorDefinition(String type) {
  for (final definition in strategyIndicatorRegistry) {
    if (definition.type == type) return definition;
  }
  return null;
}

StrategyIndicatorRef parseStrategyIndicatorRef(String raw) {
  final text = raw.trim();
  if (RegExp(r'^close(?:_?\d+)?$').hasMatch(text)) {
    return const StrategyIndicatorRef('close', 0);
  }
  final registered = parseRegisteredStrategyIndicator(text);
  if (registered != null) return registered;
  if (text == 'volume') return const StrategyIndicatorRef('volume', 20);
  return StrategyIndicatorRef(text, text == 'volume_sma' ? 20 : 14);
}

StrategyIndicatorRef? parseRegisteredStrategyIndicator(String text) {
  for (final definition in strategyIndicatorRegistry) {
    final parsed = definition.parse(text);
    if (parsed != null) return parsed;
  }
  return null;
}
