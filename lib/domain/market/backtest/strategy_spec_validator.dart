import 'strategy_method_registry.dart';

const strategyAllowedOperators = {
  '>',
  '>=',
  '<',
  '<=',
  'crosses_above',
  'crosses_below',
};

const strategySupportedExitTypes = [
  'stop_loss_pct',
  'take_profit_pct',
  'trailing_stop_pct',
  'max_drawdown_stop_pct',
  'atr_stop_loss',
  'time_stop_bars',
];

Map<String, dynamic> rejectedStrategySpec(
  String strategyId,
  Map<String, dynamic> raw,
  List<String> errors,
) {
  final validationIssues = errors
      .map(
        (error) => _validationIssue(
          category: 'schema',
          path: 'strategySpec',
          field: 'strategySpec',
          value: '${raw['id'] ?? raw['name'] ?? 'invalid'}',
          message: error,
          suggestion:
              'Provide strategySpec as a JSON object with name, indicators, entry, and exit fields.',
        ),
      )
      .toList();
  return {
    'action': 'custom_strategy_validate',
    'status': 'rejected',
    'strategyId': strategyId,
    'version': raw['version'] ?? 1,
    'spec': raw,
    'accepted': const [],
    'warnings': const [],
    'errors': errors,
    'unsupported': errors,
    'validationIssues': validationIssues,
    'repairPlan': _repairPlan(validationIssues, const []),
    'validationSummary': _validationSummary(
      status: 'rejected',
      accepted: const [],
      warnings: const [],
      errors: errors,
      unsupported: errors,
      backtestable: false,
      assetClass: '${raw['assetClass'] ?? raw['market'] ?? 'stock'}',
    ),
    'workflowAdvice':
        'This validation failed. Ask for or construct a corrected StrategySpec; do not backtest or save this rejected spec.',
  };
}

Map<String, dynamic> validateStockStrategySpec(Map<String, dynamic> spec) {
  final accepted = <String>[];
  final warnings = <String>[];
  final errors = <String>[];
  final unsupported = <String>[];
  final unsupportedDetails = <Map<String, Object>>[];
  final validationIssues = <Map<String, Object>>[];
  final indicatorRequirements = <String, dynamic>{};
  final allowedRuleRefs = <String>{'close', 'volume', 'turnover_rate'};
  var requiredLookbackBars = 0;
  validateProxyStrategyApproval(
    spec,
    errors,
    unsupported,
    unsupportedDetails,
    validationIssues,
  );
  _validateConditionDslIssues(
    spec,
    errors,
    unsupported,
    unsupportedDetails,
    validationIssues,
  );

  if ('${spec['name']}'.trim().isEmpty) {
    const message = 'name is required';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'schema',
        path: 'name',
        field: 'name',
        value: '${spec['name'] ?? ''}',
        message: message,
        suggestion: 'Provide a non-empty StrategySpec name.',
      ),
    );
  }
  final indicators = (spec['indicators'] as List?) ?? const [];
  if (indicators.isEmpty) {
    const message = 'at least one indicator is required';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'schema',
        path: 'indicators',
        field: 'indicators',
        value: '[]',
        message: message,
        suggestion: 'Declare at least one supported indicator.',
      ),
    );
  }
  for (var i = 0; i < indicators.length; i++) {
    final item = indicators[i];
    if (item is! Map) continue;
    final indicator = Map<String, dynamic>.from(item);
    final id = '${indicator['id'] ?? ''}'.trim();
    final type = '${indicator['type'] ?? ''}'.trim();
    if (id.isEmpty) {
      const message = 'indicator.id is required';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'schema',
          path: 'indicators[$i].id',
          field: 'id',
          value: '${indicator['id'] ?? ''}',
          message: message,
          suggestion:
              'Set a stable indicator id and reference that id from entry/exit rules.',
        ),
      );
    }
    if (!allowedStrategyIndicators.contains(type)) {
      final message = 'unsupported indicator "$type"';
      errors.add(message);
      unsupported.add(message);
      unsupportedDetails.add(
        _unsupportedDetail(
          category: 'indicator',
          path: id.isEmpty ? 'indicators.$type' : 'indicators.$id',
          field: 'type',
          value: type,
          message: message,
        ),
      );
    } else {
      accepted.add('indicator:$id:$type');
      if (id.isNotEmpty) allowedRuleRefs.add(id);
      final definition = strategyIndicatorDefinition(type);
      if (definition != null) {
        final parameterSchema = definition.toHelpJson()['parameterSchema'];
        if (definition.lookbackBars > requiredLookbackBars) {
          requiredLookbackBars = definition.lookbackBars;
        }
        indicatorRequirements[id.isEmpty ? type : id] = {
          'type': type,
          'category': definition.category,
          'requiredFields': definition.requiredFields,
          'defaultPeriod': definition.defaultPeriod,
          'lookbackBars': definition.lookbackBars,
          'parameterSchema': parameterSchema,
        };
        validateIndicatorParameters(
          id.isEmpty ? type : id,
          type,
          _mapOf(indicator['params']),
          parameterSchema is List ? parameterSchema : const [],
          errors,
          validationIssues,
        );
      }
    }
    if (!executableStrategyIndicators.contains(type)) {
      final message =
          'indicator "$type" is known but not executable in v1 custom backtest';
      warnings.add(message);
      errors.add(message);
      unsupported.add(message);
      unsupportedDetails.add(
        _unsupportedDetail(
          category: 'indicator',
          path: id.isEmpty ? 'indicators.$type' : 'indicators.$id',
          field: 'type',
          value: type,
          message: message,
        ),
      );
    }
  }
  validateStrategyRuleGroup(
    spec['entry'],
    'entry',
    errors,
    warnings,
    accepted,
    unsupported,
    unsupportedDetails,
    validationIssues,
    allowedRuleRefs,
  );
  validateStrategyRuleGroup(
    spec['exit'],
    'exit',
    errors,
    warnings,
    accepted,
    unsupported,
    unsupportedDetails,
    validationIssues,
    allowedRuleRefs,
  );

  final sizing = (_mapOf(spec['positionSizing'])?['type'] ?? 'full_capital')
      .toString();
  if (!{
    'full_capital',
    'fixed_fraction',
    'risk_per_trade',
    'kelly_fraction',
  }.contains(sizing)) {
    final message = 'unsupported positionSizing.type "$sizing"';
    errors.add(message);
    unsupported.add(message);
    unsupportedDetails.add(
      _unsupportedDetail(
        category: 'positionSizing',
        path: 'positionSizing.type',
        field: 'type',
        value: sizing,
        message: message,
      ),
    );
  }
  if (sizing == 'full_capital') accepted.add('positionSizing:full_capital');
  if (sizing == 'fixed_fraction') {
    final sizingMap = _mapOf(spec['positionSizing']);
    final value = _numOf(sizingMap?['value']);
    if (sizingMap?.containsKey('value') == true &&
        (value == null || value <= 0 || value > 1)) {
      final message = 'positionSizing.value must be > 0 and <= 1';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.value',
          field: 'value',
          value: '${sizingMap?['value']}',
          message: message,
          suggestion: 'Set fixed_fraction positionSizing.value within (0, 1].',
        ),
      );
    }
    accepted.add('positionSizing:fixed_fraction');
  }
  if (sizing == 'risk_per_trade') {
    final sizingMap = _mapOf(spec['positionSizing']);
    final riskPct = _numOf(sizingMap?['riskPct']);
    final stopLossPct = _numOf(sizingMap?['stopLossPct']);
    final maxPositionPct = _numOf(sizingMap?['maxPositionPct']);
    if (riskPct == null || riskPct <= 0 || riskPct > 0.05) {
      final message = 'positionSizing.riskPct must be > 0 and <= 0.05';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.riskPct',
          field: 'riskPct',
          value: '${sizingMap?['riskPct']}',
          message: message,
          suggestion: 'Set riskPct to a decimal value within (0, 0.05].',
        ),
      );
    }
    if (stopLossPct == null || stopLossPct <= 0 || stopLossPct > 100) {
      final message = 'positionSizing.stopLossPct must be > 0 and <= 100';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.stopLossPct',
          field: 'stopLossPct',
          value: '${sizingMap?['stopLossPct']}',
          message: message,
          suggestion: 'Set stopLossPct within (0, 100].',
        ),
      );
    }
    if (maxPositionPct != null && (maxPositionPct <= 0 || maxPositionPct > 1)) {
      final message = 'positionSizing.maxPositionPct must be > 0 and <= 1';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.maxPositionPct',
          field: 'maxPositionPct',
          value: '${sizingMap?['maxPositionPct']}',
          message: message,
          suggestion: 'Set maxPositionPct within (0, 1].',
        ),
      );
    }
    accepted.add('positionSizing:risk_per_trade');
  }
  if (sizing == 'kelly_fraction') {
    final sizingMap = _mapOf(spec['positionSizing']);
    final initialFraction = _numOf(sizingMap?['initialFraction']);
    final maxPositionPct = _numOf(sizingMap?['maxPositionPct']);
    final minTrades = _numOf(sizingMap?['minTrades']);
    final kellyScale = _numOf(sizingMap?['kellyScale']);
    if (initialFraction != null &&
        (initialFraction <= 0 || initialFraction > 1)) {
      const message = 'positionSizing.initialFraction must be > 0 and <= 1';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.initialFraction',
          field: 'initialFraction',
          value: '${sizingMap?['initialFraction']}',
          message: message,
          suggestion: 'Set initialFraction within (0, 1].',
        ),
      );
    }
    if (maxPositionPct != null && (maxPositionPct <= 0 || maxPositionPct > 1)) {
      const message = 'positionSizing.maxPositionPct must be > 0 and <= 1';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.maxPositionPct',
          field: 'maxPositionPct',
          value: '${sizingMap?['maxPositionPct']}',
          message: message,
          suggestion: 'Set maxPositionPct within (0, 1].',
        ),
      );
    }
    if (minTrades != null && (minTrades < 1 || minTrades > 1000)) {
      const message = 'positionSizing.minTrades must be >= 1 and <= 1000';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.minTrades',
          field: 'minTrades',
          value: '${sizingMap?['minTrades']}',
          message: message,
          suggestion: 'Set minTrades to a bounded positive integer.',
        ),
      );
    }
    if (kellyScale != null && (kellyScale <= 0 || kellyScale > 1)) {
      const message = 'positionSizing.kellyScale must be > 0 and <= 1';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'positionSizing',
          path: 'positionSizing.kellyScale',
          field: 'kellyScale',
          value: '${sizingMap?['kellyScale']}',
          message: message,
          suggestion:
              'Use a fractional Kelly scale within (0, 1], for example 0.5.',
        ),
      );
    }
    accepted.add('positionSizing:kelly_fraction');
  }
  validateStrategyRisk(_mapOf(spec['risk']), errors, validationIssues);
  validateStrategyExitValues(spec['exit'], errors, validationIssues);
  final dataRequirements = _mapOf(spec['dataRequirements']);
  final minBars =
      (dataRequirements?['minBars'] is num
              ? dataRequirements!['minBars'] as num
              : null)
          ?.toInt() ??
      120;
  if (minBars < 30) {
    final message = 'dataRequirements.minBars must be >= 30';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'dataRequirements',
        path: 'dataRequirements.minBars',
        field: 'minBars',
        value: '$minBars',
        message: message,
        suggestion: 'Set dataRequirements.minBars to at least 30.',
        metadata: {'currentMinBars': minBars, 'requiredMinBars': 30},
      ),
    );
  }
  if (requiredLookbackBars > 0 && minBars < requiredLookbackBars) {
    final message =
        'dataRequirements.minBars must be >= required indicator lookbackBars $requiredLookbackBars';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'dataRequirements',
        path: 'dataRequirements.minBars',
        field: 'minBars',
        value: '$minBars',
        message: message,
        suggestion:
            'Increase dataRequirements.minBars to at least $requiredLookbackBars, or remove indicators that require a longer lookback window.',
        metadata: {
          'currentMinBars': minBars,
          'requiredMinBars': requiredLookbackBars,
          'requiredLookbackBars': requiredLookbackBars,
        },
      ),
    );
  }
  final suggestedActions = errors.isEmpty
      ? [
          {
            'action': 'custom_strategy_backtest',
            'symbols': _strategySpecSymbols(spec),
            'strategySpec': spec,
            'boundary':
                'Use this full strategySpec for an unsaved strategy. strategyId alone is valid only after custom_strategy_save or custom_strategy_run readback.',
          },
        ]
      : const [];

  return {
    'action': 'custom_strategy_validate',
    'status': errors.isEmpty ? 'validated' : 'rejected',
    'strategyId': spec['id'],
    'version': spec['version'],
    'spec': spec,
    'accepted': accepted,
    'warnings': warnings,
    'errors': errors,
    'unsupported': unsupported,
    'unsupportedDetails': unsupportedDetails,
    'validationIssues': validationIssues,
    'repairPlan': _repairPlan(validationIssues, unsupportedDetails),
    'validationSummary': _validationSummary(
      status: errors.isEmpty ? 'validated' : 'rejected',
      accepted: accepted,
      warnings: warnings,
      errors: errors,
      unsupported: unsupported,
      backtestable: errors.isEmpty,
      assetClass: 'stock',
    ),
    'dataRequirements': {
      'indicators': indicatorRequirements,
      'minBars': minBars,
      'requiredLookbackBars': requiredLookbackBars,
    },
    'suggestedActions': suggestedActions,
    'workflowAdvice': errors.isEmpty
        ? 'If the user asked to validate only or not save, answer now from this validation result. Do not call custom_strategy_backtest, custom_strategy_save, query_kline, query_technical_indicator, Script, or other tools unless the user explicitly asks for backtest, save, or extra market evidence.'
        : 'This validation failed. Report the unsupported executable parts directly. Do not replace them with proxy indicators, and do not call custom_strategy_backtest or custom_strategy_save unless the user explicitly asks for a separate proxy redesign.',
  };
}

void _validateConditionDslIssues(
  Map<String, dynamic> spec,
  List<String> errors,
  List<String> unsupported,
  List<Map<String, Object>> unsupportedDetails,
  List<Map<String, Object>> validationIssues,
) {
  final issues = spec['conditionDslIssues'];
  if (issues is! List) return;
  for (final raw in issues.whereType<Map>()) {
    final index = raw['index'] is num ? (raw['index'] as num).toInt() : 0;
    final field = '${raw['field'] ?? 'condition'}';
    final value = '${raw['value'] ?? ''}';
    final message = '${raw['message'] ?? 'invalid conditionDslV1 rule'}';
    errors.add(message);
    unsupported.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'condition_dsl',
        path: 'rules[$index].$field',
        field: field,
        value: value,
        message: message,
        suggestion:
            'Use canonical entry/exit groups, or request custom_strategy_help detail:"catalog" fields:["executableV1.conditionDslV1"] and revise rules[] to the supported mini-contract.',
        metadata: const {
          'allowedActions': ['entry', 'exit', 'buy', 'sell', 'long', 'close'],
          'grammar':
              '<series-or-indicator-id> (< | <= | > | >= | crosses_above | crosses_below) (<series-or-indicator-id> | number)',
        },
      ),
    );
    unsupportedDetails.add(
      _unsupportedDetail(
        category: 'condition_dsl',
        path: 'rules[$index].$field',
        field: field,
        value: value,
        message: message,
      ),
    );
  }
}

List<String> _strategySpecSymbols(Map<String, dynamic> spec) {
  final direct = '${spec['symbol'] ?? spec['code'] ?? ''}'.trim();
  if (direct.isNotEmpty) return [direct];
  final symbols = spec['symbols'];
  if (symbols is List) {
    final out = symbols
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (out.isNotEmpty) return out;
  }
  final universe = _mapOf(spec['universe']);
  final universeSymbols = universe?['symbols'];
  if (universeSymbols is List) {
    final out = universeSymbols
        .map((item) => '$item'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
    if (out.isNotEmpty) return out;
  }
  return const [];
}

Map<String, dynamic> validateFundStrategySpec(Map<String, dynamic> spec) {
  final accepted = <String>[];
  final warnings = <String>[];
  final errors = <String>[];
  final unsupported = <String>[];
  final unsupportedDetails = <Map<String, Object>>[];
  final validationIssues = <Map<String, Object>>[];
  final allowedRuleRefs = <String>{'nav', 'money_yield', 'seven_day_yield'};
  validateProxyStrategyApproval(
    spec,
    errors,
    unsupported,
    unsupportedDetails,
    validationIssues,
  );
  if ('${spec['name']}'.trim().isEmpty) {
    const message = 'name is required';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'schema',
        path: 'name',
        field: 'name',
        value: '${spec['name'] ?? ''}',
        message: message,
        suggestion: 'Provide a non-empty fund StrategySpec name.',
      ),
    );
  }
  final indicators = (spec['indicators'] as List?) ?? const [];
  if (indicators.isEmpty) {
    const message = 'at least one fund indicator is required';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'schema',
        path: 'indicators',
        field: 'indicators',
        value: '[]',
        message: message,
        suggestion:
            'Declare at least one fund-specific indicator from custom_strategy_help.fundObservationV1.indicatorCatalog, such as nav_trend, rolling_return, fund_drawdown, fund_ulcer_index, fund_drawdown_duration_bars, fund_sharpe, fund_gain_to_pain, fund_momentum_acceleration, fund_return_skewness, fund_value_at_risk, money_yield, or seven_day_yield.',
      ),
    );
  }
  for (var i = 0; i < indicators.length; i++) {
    final item = indicators[i];
    if (item is! Map) continue;
    final indicator = Map<String, dynamic>.from(item);
    final id = '${indicator['id'] ?? ''}'.trim();
    final type = '${indicator['type'] ?? ''}'.trim();
    if (id.isEmpty) {
      const message = 'indicator.id is required';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'schema',
          path: 'indicators[$i].id',
          field: 'id',
          value: '${indicator['id'] ?? ''}',
          message: message,
          suggestion:
              'Set a stable fund indicator id and reference that id from entry/exit rules.',
        ),
      );
    }
    if (!fundStrategyIndicators.contains(type)) {
      final message =
          'unsupported fund indicator "$type"; use fund-specific indicators from custom_strategy_help.fundObservationV1.indicatorCatalog, such as nav_trend, rolling_return, fund_drawdown, fund_ulcer_index, fund_drawdown_duration_bars, fund_volatility, fund_sharpe, fund_sortino, fund_calmar, fund_gain_to_pain, fund_momentum_acceleration, fund_omega, fund_tail_ratio, fund_positive_period_ratio, fund_negative_period_ratio, fund_return_skewness, fund_return_kurtosis, fund_value_at_risk, fund_conditional_value_at_risk, money_yield, seven_day_yield, or dca_interval';
      errors.add(message);
      unsupported.add(message);
      unsupportedDetails.add(
        _unsupportedDetail(
          category: 'fund_indicator',
          path: id.isEmpty ? 'indicators.$type' : 'indicators.$id',
          field: 'type',
          value: type,
          message: message,
        ),
      );
    } else {
      accepted.add('fund_indicator:$id:$type');
      if (id.isNotEmpty) allowedRuleRefs.add(id);
    }
  }
  validateStrategyRuleGroup(
    spec['entry'],
    'entry',
    errors,
    warnings,
    accepted,
    unsupported,
    unsupportedDetails,
    validationIssues,
    allowedRuleRefs,
  );
  validateStrategyRuleGroup(
    spec['exit'],
    'exit',
    errors,
    warnings,
    accepted,
    unsupported,
    unsupportedDetails,
    validationIssues,
    allowedRuleRefs,
  );
  final dataRequirements = _mapOf(spec['dataRequirements']);
  final dataClass =
      '${dataRequirements?['dataClass'] ?? spec['dataClass'] ?? ''}'.trim();
  if (dataClass.isEmpty) {
    warnings.add(
      'fund dataRequirements.dataClass should declare ordinary_fund_nav, money_fund_yield, etf_nav, or listed_fund_quote',
    );
  }
  final fundCategory = _normalizeFundCategoryValue(
    spec['fundCategory'] ??
        spec['fundType'] ??
        dataRequirements?['fundCategory'] ??
        dataRequirements?['fundType'],
  );
  final indicatorTypes = indicators
      .whereType<Map>()
      .map((item) => '${item['type'] ?? ''}')
      .toSet();
  final indicatorRequirements = indicators
      .whereType<Map>()
      .map((item) => _fundIndicatorRequirement(Map<String, dynamic>.from(item)))
      .whereType<Map<String, dynamic>>()
      .toList();
  if ((fundCategory == 'money' || dataClass == 'money_fund_yield') &&
      !indicatorTypes.contains('money_yield') &&
      !indicatorTypes.contains('seven_day_yield')) {
    errors.add(
      'money fund StrategySpec must use money_yield or seven_day_yield, not ordinary NAV-only indicators',
    );
  }
  if (fundCategory != 'money' &&
      (indicatorTypes.contains('money_yield') ||
          indicatorTypes.contains('seven_day_yield')) &&
      dataClass != 'money_fund_yield') {
    warnings.add(
      'money_yield/seven_day_yield require money-fund yield evidence; ordinary fund NAV evidence is not enough',
    );
  }
  return {
    'action': 'custom_strategy_validate',
    'status': errors.isEmpty ? 'validated' : 'rejected',
    'strategyId': spec['id'],
    'version': spec['version'],
    'assetClass': 'fund',
    'backtestable': false,
    'spec': spec,
    'accepted': accepted,
    'warnings': warnings,
    'errors': errors,
    'unsupported': unsupported,
    'unsupportedDetails': unsupportedDetails,
    'validationIssues': validationIssues,
    'repairPlan': _repairPlan(validationIssues, unsupportedDetails),
    'validationSummary': _validationSummary(
      status: errors.isEmpty ? 'validated' : 'rejected',
      accepted: accepted,
      warnings: warnings,
      errors: errors,
      unsupported: unsupported,
      backtestable: false,
      assetClass: 'fund',
    ),
    'dataRequirements': {
      'indicators': indicatorRequirements,
      'ordinaryFund': ['query_fund_nav', 'query_fund_performance'],
      'moneyFund': ['query_fund_money_yield'],
      'holdings': ['query_fund_holding'],
    },
    'workflowAdvice': errors.isEmpty
        ? 'This fund StrategySpec is validated as observation/research contract only. Do not call custom_strategy_backtest. Gather fund-specific evidence with query_fund_nav, query_fund_money_yield, query_fund_performance, or query_fund_holding before monitoring or trade preparation.'
        : 'This fund StrategySpec validation failed. Report the fund-specific unsupported parts directly; do not replace fund rules with stock K-line, RSI, volume, or price indicators.',
  };
}

Map<String, dynamic>? _fundIndicatorRequirement(
  Map<String, dynamic> indicator,
) {
  final type = '${indicator['type'] ?? ''}'.trim();
  final definition = fundStrategyIndicatorDefinition(type);
  if (definition == null) return null;
  final id = '${indicator['id'] ?? type}'.trim();
  return {
    'id': id.isEmpty ? type : id,
    'type': type,
    'category': definition.category,
    'source': definition.source,
    'requiredFields': definition.requiredFields,
    'scoreDirection': definition.scoreDirection,
    'parameterSchema': definition.toHelpJson()['parameterSchema'],
    'readbacks': _fundReadbacksForDefinition(definition),
  };
}

List<String> _fundReadbacksForDefinition(
  FundStrategyIndicatorDefinition definition,
) {
  if (definition.category == 'money_fund_yield') {
    return ['query_fund_money_yield'];
  }
  if (definition.source == 'nav') {
    return ['query_fund_nav'];
  }
  return ['query_fund_nav', 'query_fund_money_yield'];
}

String _normalizeFundCategoryValue(Object? raw) {
  final value = '${raw ?? ''}'.trim().toLowerCase();
  if (value.isEmpty) return '';
  if (value == 'money' ||
      value.contains('货币') ||
      value.contains('money') ||
      value.contains('monetary') ||
      value.contains('现金')) {
    return 'money';
  }
  if (value == 'etf' || value.contains('etf')) return 'etf';
  if (value == 'backend' || value.contains('后端')) return 'backend';
  if (value == 'bond' || value.contains('债')) return 'bond';
  if (value == 'index' || value.contains('指数')) return 'index';
  return value;
}

bool isFundStrategySpec(Map<String, dynamic> spec) {
  final market = '${spec['market'] ?? ''}'.toLowerCase();
  final assetClass =
      '${spec['assetClass'] ?? spec['asset_class'] ?? spec['type'] ?? ''}'
          .toLowerCase();
  final universe = _mapOf(spec['universe']);
  final universeType = '${universe?['type'] ?? ''}'.toLowerCase();
  return market == 'fund' ||
      market == 'funds' ||
      assetClass == 'fund' ||
      assetClass == 'funds' ||
      universeType == 'fund' ||
      universeType == 'funds';
}

Map<String, Object> _validationSummary({
  required String status,
  required List<String> accepted,
  required List<String> warnings,
  required List<String> errors,
  required List<String> unsupported,
  required bool backtestable,
  required String assetClass,
}) {
  final acceptedCount = accepted.length;
  final warningCount = warnings.length;
  final errorCount = errors.length;
  final unsupportedCount = unsupported.length;
  final normalizedAssetClass = assetClass.trim().isEmpty ? 'stock' : assetClass;
  final nextAction = _validationNextAction(
    status: status,
    backtestable: backtestable,
    assetClass: normalizedAssetClass,
    errorCount: errorCount,
    unsupportedCount: unsupportedCount,
  );
  return {
    'acceptedCount': acceptedCount,
    'warningCount': warningCount,
    'errorCount': errorCount,
    'unsupportedCount': unsupportedCount,
    'canBacktest': backtestable && errorCount == 0,
    'assetClass': normalizedAssetClass,
    'nextAction': nextAction,
  };
}

String _validationNextAction({
  required String status,
  required bool backtestable,
  required String assetClass,
  required int errorCount,
  required int unsupportedCount,
}) {
  if (status != 'validated' || errorCount > 0 || unsupportedCount > 0) {
    return 'revise_strategy_spec';
  }
  if (assetClass == 'fund') {
    return 'gather_fund_evidence_or_observe';
  }
  if (backtestable) {
    return 'custom_strategy_backtest_or_answer_validation_only';
  }
  return 'answer_validation_only';
}

void validateStrategyRisk(
  Map<String, dynamic>? risk,
  List<String> errors,
  List<Map<String, Object>> validationIssues,
) {
  if (risk == null) return;
  for (final key in [
    'maxPositionPct',
    'maxExposurePct',
    'maxLossPerTradePct',
  ]) {
    if (!risk.containsKey(key)) continue;
    final value = _numOf(risk[key]);
    if (value == null || value <= 0 || value > 1) {
      final message = 'risk.$key must be > 0 and <= 1';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'risk',
          path: 'risk.$key',
          field: key,
          value: '${risk[key]}',
          message: message,
          suggestion: 'Set risk.$key to a decimal value within (0, 1].',
        ),
      );
    }
  }
}

void validateProxyStrategyApproval(
  Map<String, dynamic> spec,
  List<String> errors,
  List<String> unsupported,
  List<Map<String, Object>> unsupportedDetails,
  List<Map<String, Object>> validationIssues,
) {
  if (!_declaresProxyStrategy(spec)) return;
  if (_hasExplicitProxyApproval(spec['proxyApproval'])) return;
  const message =
      'proxy StrategySpec requires explicit structured user approval before validation/backtest/save';
  errors.add(message);
  unsupported.add(message);
  unsupportedDetails.add(
    _unsupportedDetail(
      category: 'proxy_strategy',
      path: 'proxyApproval',
      field: 'proxyApproval',
      value: '${spec['proxyApproval'] ?? ''}',
      message: message,
    ),
  );
  validationIssues.add(
    _validationIssue(
      category: 'proxy_strategy',
      path: 'proxyApproval',
      field: 'proxyApproval',
      value: '${spec['proxyApproval'] ?? ''}',
      message: message,
      suggestion:
          'First report the unsupported original signals and ask the user to approve a separate proxy redesign. If approved, include proxyFor, unsupportedOriginalSignals, and proxyApproval:{approved:true}.',
    ),
  );
}

bool _declaresProxyStrategy(Map<String, dynamic> spec) =>
    spec.containsKey('proxyFor') ||
    spec.containsKey('originalSignals') ||
    spec.containsKey('unsupportedOriginalSignals') ||
    spec.containsKey('proxyApproval');

bool _hasExplicitProxyApproval(Object? raw) {
  if (raw == true) return true;
  if (raw is! Map) return false;
  return raw['approved'] == true ||
      raw['status'] == 'approved' ||
      raw['confirmationState'] == 'accepted';
}

void validateIndicatorParameters(
  String id,
  String type,
  Map<String, dynamic>? params,
  List<dynamic> schema,
  List<String> errors,
  List<Map<String, Object>> validationIssues,
) {
  final input = params ?? const <String, dynamic>{};
  final allowed = schema
      .whereType<Map>()
      .map((item) => '${item['name'] ?? ''}')
      .where((name) => name.isNotEmpty)
      .toSet();
  for (final key in input.keys) {
    if (allowed.isNotEmpty && !allowed.contains(key)) {
      final message = 'indicator.$id params.$key is not supported for $type';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'indicator_params',
          path: 'indicators.$id.params.$key',
          field: key,
          value: '${input[key]}',
          message: message,
          suggestion:
              'Remove this parameter or replace it with a parameter declared in dataRequirements.indicators.$id.parameterSchema.',
        ),
      );
    }
  }
  for (final raw in schema.whereType<Map>()) {
    final name = '${raw['name'] ?? ''}';
    if (name.isEmpty || !input.containsKey(name)) continue;
    final number = _numOf(input[name]);
    final kind = '${raw['type'] ?? 'number'}';
    if (number == null) {
      final message = 'indicator.$id params.$name must be $kind';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'indicator_params',
          path: 'indicators.$id.params.$name',
          field: name,
          value: '${input[name]}',
          message: message,
          suggestion: 'Use a numeric $kind value for this parameter.',
        ),
      );
      continue;
    }
    if (kind == 'integer' && number != number.roundToDouble()) {
      final message = 'indicator.$id params.$name must be integer';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'indicator_params',
          path: 'indicators.$id.params.$name',
          field: name,
          value: '${input[name]}',
          message: message,
          suggestion: 'Use an integer value for this parameter.',
        ),
      );
    }
    final minValue = _numOf(raw['min']);
    if (minValue != null && number < minValue) {
      final message = 'indicator.$id params.$name must be >= $minValue';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'indicator_params',
          path: 'indicators.$id.params.$name',
          field: name,
          value: '${input[name]}',
          message: message,
          suggestion: 'Set this parameter to at least $minValue.',
        ),
      );
    }
    final maxValue = _numOf(raw['max']);
    if (maxValue != null && number > maxValue) {
      final message = 'indicator.$id params.$name must be <= $maxValue';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'indicator_params',
          path: 'indicators.$id.params.$name',
          field: name,
          value: '${input[name]}',
          message: message,
          suggestion: 'Set this parameter to no more than $maxValue.',
        ),
      );
    }
  }
}

void validateStrategyExitValues(
  Object? raw,
  List<String> errors,
  List<Map<String, Object>> validationIssues,
) {
  if (raw is! Map) return;
  final rules = [
    ...(_listOf(raw['all']) ?? const []),
    ...(_listOf(raw['any']) ?? const []),
  ];
  for (final item in rules.whereType<Map>()) {
    final type = '${item['type'] ?? ''}';
    if (!{
      'stop_loss_pct',
      'take_profit_pct',
      'trailing_stop_pct',
      'max_drawdown_stop_pct',
      'atr_stop_loss',
      'time_stop_bars',
    }.contains(type)) {
      continue;
    }
    final value = _numOf(item['value']);
    if (type == 'time_stop_bars') {
      if (value == null || value <= 0 || value > 1000) {
        final message = '$type value must be > 0 and <= 1000';
        errors.add(message);
        validationIssues.add(
          _validationIssue(
            category: 'exit_value',
            path: 'exit.$type.value',
            field: 'value',
            value: '${item['value']}',
            message: message,
            suggestion: 'Set $type value within (0, 1000].',
          ),
        );
      }
      continue;
    }
    if (value == null || value <= 0 || value > 100) {
      final message = '$type value must be > 0 and <= 100';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'exit_value',
          path: 'exit.$type.value',
          field: 'value',
          value: '${item['value']}',
          message: message,
          suggestion: 'Set $type value within (0, 100].',
        ),
      );
    }
  }
}

void validateStrategyRuleGroup(
  Object? raw,
  String label,
  List<String> errors,
  List<String> warnings,
  List<String> accepted,
  List<String> unsupported,
  List<Map<String, Object>> unsupportedDetails,
  List<Map<String, Object>> validationIssues,
  Set<String> allowedRuleRefs,
) {
  if (raw is! Map) {
    final message = '$label rule group is required';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'rule_shape',
        path: label,
        field: label,
        value: '${raw ?? 'null'}',
        message: message,
        suggestion:
            'Provide a $label rule group with all[] or any[] executable rules.',
      ),
    );
    return;
  }
  final rules = _listOf(raw['all']) ?? _listOf(raw['any']) ?? const [];
  if (rules.isEmpty) {
    final message = '$label rule group must contain all[] or any[] rules';
    errors.add(message);
    validationIssues.add(
      _validationIssue(
        category: 'rule_shape',
        path: label,
        field: 'rules',
        value: '[]',
        message: message,
        suggestion:
            'Add at least one comparison rule to $label.all[] or $label.any[].',
      ),
    );
    return;
  }
  for (final item in rules.whereType<Map>()) {
    final rule = Map<String, dynamic>.from(item);
    if (rule.containsKey('type')) {
      final type = '${rule['type']}';
      if (!strategySupportedExitTypes.contains(type)) {
        final message = 'unsupported $label exit type "$type"';
        errors.add(message);
        unsupported.add(message);
        unsupportedDetails.add(
          _unsupportedDetail(
            category: 'exit_type',
            path: '$label.type',
            field: 'type',
            value: type,
            message: message,
          ),
        );
      } else {
        accepted.add('$label:$type');
      }
      continue;
    }
    final op = '${rule['op']}';
    final left = '${rule['left']}';
    if (left.trim().isEmpty) {
      final message = '$label rule.left is required';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'rule_shape',
          path: '$label.left',
          field: 'left',
          value: '${rule['left'] ?? ''}',
          message: message,
          suggestion:
              'Set rule.left to an indicator id or built-in series declared in StrategySpec.',
        ),
      );
    } else if (!isAllowedRuleRef(left, allowedRuleRefs)) {
      final message =
          '$label rule source "$left" is not declared in StrategySpec indicators or built-in series';
      errors.add(message);
      unsupported.add(message);
      unsupportedDetails.add(
        _unsupportedDetail(
          category: 'rule_source',
          path: '$label.left',
          field: 'left',
          value: left,
          message: message,
        ),
      );
    }
    if (!strategyAllowedOperators.contains(op)) {
      final message = 'unsupported $label operator "$op"';
      errors.add(message);
      unsupported.add(message);
      unsupportedDetails.add(
        _unsupportedDetail(
          category: 'operator',
          path: '$label.op',
          field: 'op',
          value: op,
          message: message,
        ),
      );
    } else {
      accepted.add('$label:$left:$op');
    }
    if (rule['right'] == null) {
      final message = '$label rule "$left" has no executable right-hand value';
      errors.add(message);
      validationIssues.add(
        _validationIssue(
          category: 'rule_shape',
          path: '$label.right',
          field: 'right',
          value: 'null',
          message: message,
          suggestion:
              'Set rule.right to a number or declared indicator/source reference.',
          metadata: {
            'allowedRightKinds': [
              'number',
              'declared_indicator',
              'builtin_series',
            ],
            'declaredRuleRefs': allowedRuleRefs.toList()..sort(),
            'exampleNumericRight': 50,
            'exampleReferenceRight': 'close',
          },
        ),
      );
    } else {
      validateRuleRightReferences(
        rule['right'],
        label,
        left,
        errors,
        unsupported,
        unsupportedDetails,
        allowedRuleRefs,
      );
    }
    if (left.contains('news') ||
        left.contains('sentiment') ||
        left.contains('盘口') ||
        left.contains('资金')) {
      warnings.add(
        '$label rule "$left" is not executable in v1 custom backtest',
      );
      final message = 'unsupported executable rule source "$left"';
      errors.add(message);
      unsupported.add(message);
      unsupportedDetails.add(
        _unsupportedDetail(
          category: 'rule_source',
          path: '$label.left',
          field: 'left',
          value: left,
          message: message,
        ),
      );
    }
  }
}

void validateRuleRightReferences(
  Object? raw,
  String label,
  String left,
  List<String> errors,
  List<String> unsupported,
  List<Map<String, Object>> unsupportedDetails,
  Set<String> allowedRuleRefs,
) {
  if (raw is num) return;
  if (raw is String) {
    if (double.tryParse(raw) != null) return;
    if (!isAllowedRuleRef(raw, allowedRuleRefs)) {
      final message =
          '$label rule "$left" right source "$raw" is not declared in StrategySpec indicators or built-in series';
      errors.add(message);
      unsupported.add(message);
      unsupportedDetails.add(
        _unsupportedDetail(
          category: 'rule_source',
          path: '$label.right',
          field: 'right',
          value: raw,
          message: message,
        ),
      );
    }
    return;
  }
  if (raw is Map) {
    final mul = raw['mul'];
    if (mul is List && mul.isNotEmpty) {
      final source = '${mul.first}';
      if (double.tryParse(source) != null) return;
      if (!isAllowedRuleRef(source, allowedRuleRefs)) {
        final message =
            '$label rule "$left" right source "$source" is not declared in StrategySpec indicators or built-in series';
        errors.add(message);
        unsupported.add(message);
        unsupportedDetails.add(
          _unsupportedDetail(
            category: 'rule_source',
            path: '$label.right',
            field: 'right',
            value: source,
            message: message,
          ),
        );
      }
    }
  }
}

Map<String, Object> _unsupportedDetail({
  required String category,
  required String path,
  required String field,
  required String value,
  required String message,
}) => {
  'category': category,
  'path': path,
  'field': field,
  'value': value,
  'message': message,
  'suggestion': _unsupportedSuggestion(category),
  if (category == 'indicator')
    'candidateTypes': _candidateStrategyIndicatorTypes(value),
  if (category == 'fund_indicator')
    'candidateTypes': _candidateFundIndicatorTypes(value),
  if (category == 'exit_type') 'candidateExitTypes': strategySupportedExitTypes,
  if (category == 'exit_type') 'candidateExitCatalog': _candidateExitCatalog(),
};

Map<String, Object> _validationIssue({
  required String category,
  required String path,
  required String field,
  required String value,
  required String message,
  required String suggestion,
  Map<String, Object>? metadata,
}) => {
  'category': category,
  'path': path,
  'field': field,
  'value': value,
  'message': message,
  'suggestion': suggestion,
  ...?metadata,
};

List<Map<String, Object>> _repairPlan(
  List<Map<String, Object>> validationIssues,
  List<Map<String, Object>> unsupportedDetails,
) {
  final steps = <Map<String, Object>>[];
  void addStep(Map<String, Object> item, String source) {
    final category = '${item['category'] ?? ''}';
    final path = '${item['path'] ?? ''}';
    final field = '${item['field'] ?? ''}';
    final key = '$source|$category|$path|$field|${item['value'] ?? ''}';
    if (steps.any((step) => step['dedupeKey'] == key)) return;
    steps.add({
      'dedupeKey': key,
      'source': source,
      'category': category,
      'path': path,
      'field': field,
      'value': '${item['value'] ?? ''}',
      'message': '${item['message'] ?? ''}',
      'repairAction': _repairActionForCategory(category),
      'target': _repairTargetForCategory(category),
      'patchHint': _repairPatchHintForItem(category, item),
      'blocking': true,
      'suggestion': '${item['suggestion'] ?? _unsupportedSuggestion(category)}',
    });
  }

  for (final issue in validationIssues) {
    addStep(issue, 'validationIssues');
  }
  for (final detail in unsupportedDetails) {
    addStep(detail, 'unsupportedDetails');
  }
  for (final step in steps) {
    step.remove('dedupeKey');
  }
  return steps;
}

String _repairActionForCategory(String category) {
  switch (category) {
    case 'indicator':
    case 'fund_indicator':
      return 'replace_with_supported_indicator';
    case 'rule_source':
      return 'declare_source_or_use_builtin_series';
    case 'operator':
      return 'use_supported_operator';
    case 'exit_type':
      return 'use_supported_exit_type';
    case 'positionSizing':
      return 'use_supported_position_sizing';
    case 'proxy_strategy':
      return 'request_explicit_proxy_approval';
    case 'indicator_params':
      return 'fix_indicator_parameter';
    case 'rule_shape':
      return 'fix_rule_shape';
    case 'condition_dsl':
      return 'fix_condition_dsl';
    case 'dataRequirements':
      return 'fix_data_requirements';
    case 'risk':
      return 'fix_risk_constraint';
    case 'exit_value':
      return 'fix_exit_value';
    case 'schema':
      return 'fix_strategy_schema';
    default:
      return 'revise_strategy_spec_field';
  }
}

String _repairTargetForCategory(String category) {
  switch (category) {
    case 'indicator':
    case 'fund_indicator':
    case 'indicator_params':
      return 'strategySpec.indicators';
    case 'rule_source':
    case 'operator':
    case 'rule_shape':
    case 'condition_dsl':
      return 'strategySpec.entry_or_exit';
    case 'exit_type':
    case 'exit_value':
      return 'strategySpec.exit';
    case 'positionSizing':
      return 'strategySpec.positionSizing';
    case 'proxy_strategy':
      return 'strategySpec.proxyApproval';
    case 'dataRequirements':
      return 'strategySpec.dataRequirements';
    case 'risk':
      return 'strategySpec.risk';
    case 'schema':
      return 'strategySpec';
    default:
      return 'strategySpec';
  }
}

Map<String, Object> _repairPatchHintForCategory(String category) {
  switch (category) {
    case 'indicator':
      return const {
        'operation': 'replace_indicator_type',
        'catalog': 'custom_strategy_help.executableV1.indicatorCatalog',
      };
    case 'fund_indicator':
      return const {
        'operation': 'replace_fund_indicator_type',
        'catalog': 'custom_strategy_help.fundObservationV1.indicatorCatalog',
      };
    case 'rule_source':
      return const {
        'operation': 'declare_indicator_or_use_builtin_series',
        'builtInSeries': ['close', 'volume', 'turnover_rate'],
      };
    case 'operator':
      return const {
        'operation': 'replace_operator',
        'allowed': ['>', '>=', '<', '<=', 'crosses_above', 'crosses_below'],
      };
    case 'exit_type':
      return const {
        'operation': 'replace_exit_type',
        'allowed': [
          'stop_loss_pct',
          'take_profit_pct',
          'trailing_stop_pct',
          'max_drawdown_stop_pct',
          'atr_stop_loss',
          'time_stop_bars',
        ],
      };
    case 'positionSizing':
      return const {
        'operation': 'replace_position_sizing_type',
        'allowed': [
          'full_capital',
          'fixed_fraction',
          'risk_per_trade',
          'kelly_fraction',
        ],
      };
    case 'proxy_strategy':
      return const {
        'operation': 'request_explicit_user_approval',
        'requiredField': 'proxyApproval.approved',
        'requiredValue': true,
      };
    case 'indicator_params':
      return const {
        'operation': 'conform_params_to_parameter_schema',
        'schemaSource': 'dataRequirements.indicators.<id>.parameterSchema',
      };
    case 'rule_shape':
      return const {
        'operation': 'provide_rule_group',
        'allowedGroups': ['all', 'any'],
      };
    case 'condition_dsl':
      return const {
        'operation': 'revise_condition_dsl_or_use_canonical_rule_group',
        'catalog': 'custom_strategy_help.executableV1.conditionDslV1',
        'allowedActions': ['entry', 'exit', 'buy', 'sell', 'long', 'close'],
        'grammar':
            '<series-or-indicator-id> (< | <= | > | >= | crosses_above | crosses_below) (<series-or-indicator-id> | number)',
      };
    case 'dataRequirements':
      return const {
        'operation': 'adjust_data_requirements',
        'fields': ['minBars', 'requiredFields', 'adjust'],
      };
    case 'risk':
      return const {'operation': 'adjust_risk_bounds', 'range': '(0, 1]'};
    case 'exit_value':
      return const {
        'operation': 'adjust_exit_value',
        'range': '(0, 100] or time_stop_bars (0, 1000]',
      };
    case 'schema':
      return const {
        'operation': 'provide_strategy_spec_object',
        'requiredFields': ['name', 'indicators', 'entry', 'exit'],
      };
    default:
      return const {'operation': 'revise_field'};
  }
}

Map<String, Object> _repairPatchHintForItem(
  String category,
  Map<String, Object> item,
) {
  final base = Map<String, Object>.from(_repairPatchHintForCategory(category));
  final path = '${item['path'] ?? ''}';
  final field = '${item['field'] ?? ''}';
  final value = '${item['value'] ?? ''}';
  if (path.isNotEmpty) base['path'] = path;
  if (field.isNotEmpty) base['field'] = field;
  if (value.isNotEmpty) base['currentValue'] = value;
  if (category == 'rule_shape' && field == 'right') {
    final allowed = item['allowedRightKinds'];
    final refs = item['declaredRuleRefs'];
    if (allowed is List) base['allowedRightKinds'] = allowed;
    if (refs is List) base['declaredRuleRefs'] = refs;
    base['operation'] = 'set_rule_right';
    base['valueExamples'] = [
      item['exampleNumericRight'] ?? 50,
      item['exampleReferenceRight'] ?? 'close',
    ];
  }
  if (category == 'indicator') {
    final candidates = _candidateStrategyIndicatorTypes(value);
    base['candidateTypes'] = candidates;
    base['candidateCatalog'] = _candidateStrategyIndicatorCatalog(candidates);
  }
  if (category == 'fund_indicator') {
    final candidates = _candidateFundIndicatorTypes(value);
    base['candidateTypes'] = candidates;
    base['candidateCatalog'] = _candidateFundIndicatorCatalog(candidates);
  }
  if (category == 'exit_type') {
    base['candidateExitTypes'] = strategySupportedExitTypes;
    base['candidateExitCatalog'] = _candidateExitCatalog();
  }
  if (category == 'indicator_params') {
    final match = RegExp(
      r'^indicators\.([^.]+)\.params\.([^.]+)$',
    ).firstMatch(path);
    if (match != null) {
      final indicatorId = match.group(1)!;
      final parameterName = match.group(2)!;
      base['indicatorId'] = indicatorId;
      base['parameterName'] = parameterName;
      base['schemaSource'] =
          'dataRequirements.indicators.$indicatorId.parameterSchema';
    }
  }
  if (category == 'dataRequirements' && field == 'minBars') {
    final current = item['currentMinBars'];
    final required = item['requiredMinBars'];
    base['operation'] = 'set_min_bars';
    if (current is num) base['currentMinBars'] = current;
    if (required is num) {
      base['requiredMinBars'] = required;
      base['targetValue'] = required;
    }
    final lookback = item['requiredLookbackBars'];
    if (lookback is num) base['requiredLookbackBars'] = lookback;
  }
  return base;
}

List<String> _candidateStrategyIndicatorTypes(String value) {
  final scored = <MapEntry<String, int>>[];
  for (final definition in strategyIndicatorRegistry) {
    final score = _candidateScore(value, [
      definition.type,
      ...definition.aliases,
      definition.category,
    ]);
    if (score > 0) scored.add(MapEntry(definition.type, score));
  }
  scored.sort((a, b) {
    final score = b.value.compareTo(a.value);
    if (score != 0) return score;
    return a.key.compareTo(b.key);
  });
  final result = <String>[];
  for (final entry in scored) {
    if (!result.contains(entry.key)) result.add(entry.key);
    if (result.length >= 5) break;
  }
  return result.isNotEmpty ? result : ['sma', 'ema', 'rsi', 'macd', 'atr'];
}

List<String> _candidateFundIndicatorTypes(String value) {
  final scored = <MapEntry<String, int>>[];
  for (final definition in fundStrategyIndicatorRegistry) {
    final score = _candidateScore(value, [
      definition.type,
      definition.category,
      definition.source,
    ]);
    if (score > 0) scored.add(MapEntry(definition.type, score));
  }
  scored.sort((a, b) {
    final score = b.value.compareTo(a.value);
    if (score != 0) return score;
    return a.key.compareTo(b.key);
  });
  final result = <String>[];
  for (final entry in scored) {
    if (!result.contains(entry.key)) result.add(entry.key);
    if (result.length >= 5) break;
  }
  return result.isNotEmpty
      ? result
      : ['nav_trend', 'rolling_return', 'fund_drawdown', 'fund_sharpe'];
}

List<Map<String, dynamic>> _candidateStrategyIndicatorCatalog(
  List<String> candidates,
) => candidates
    .map(strategyIndicatorDefinition)
    .whereType<StrategyIndicatorDefinition>()
    .map((definition) => definition.toHelpJson())
    .toList();

List<Map<String, dynamic>> _candidateFundIndicatorCatalog(
  List<String> candidates,
) => candidates
    .map(fundStrategyIndicatorDefinition)
    .whereType<FundStrategyIndicatorDefinition>()
    .map((definition) => definition.toHelpJson())
    .toList();

List<Map<String, Object>> _candidateExitCatalog() => const [
  {
    'type': 'stop_loss_pct',
    'valueField': 'value',
    'valueUnit': 'percent',
    'description':
        'Exit when price falls by the configured percent from entry.',
  },
  {
    'type': 'take_profit_pct',
    'valueField': 'value',
    'valueUnit': 'percent',
    'description':
        'Exit when price rises by the configured percent from entry.',
  },
  {
    'type': 'trailing_stop_pct',
    'valueField': 'value',
    'valueUnit': 'percent',
    'description':
        'Exit when price retreats from the high-water mark by the configured percent.',
  },
  {
    'type': 'max_drawdown_stop_pct',
    'valueField': 'value',
    'valueUnit': 'percent',
    'description':
        'Exit when open-position drawdown reaches the configured percent.',
  },
  {
    'type': 'atr_stop_loss',
    'valueField': 'value',
    'valueUnit': 'atr_multiple',
    'optionalFields': ['period'],
    'description':
        'Exit when price falls by the configured ATR multiple from entry.',
  },
  {
    'type': 'time_stop_bars',
    'valueField': 'value',
    'valueUnit': 'bars',
    'description': 'Exit after the configured maximum holding bars.',
  },
];

int _candidateScore(String raw, Iterable<String> candidates) {
  final text = _candidateToken(raw);
  if (text.isEmpty) return 0;
  var best = 0;
  for (final candidate in candidates) {
    final normalized = _candidateToken(candidate);
    if (normalized.isEmpty) continue;
    if (normalized == text) best = best < 100 ? 100 : best;
    if (normalized.contains(text) || text.contains(normalized)) {
      best = best < 80 ? 80 : best;
    }
    for (final part in text.split('_')) {
      if (part.length < 3) continue;
      if (normalized.contains(part)) best = best < 30 ? 30 : best;
    }
  }
  return best;
}

String _candidateToken(String raw) => raw.trim().toLowerCase().replaceAll(
  RegExp(r'[^a-z0-9_\u4e00-\u9fff]+'),
  '_',
);

String _unsupportedSuggestion(String category) {
  switch (category) {
    case 'indicator':
      return 'Replace with an executable StrategySpec indicator from custom_strategy_help, or keep the signal outside executable backtest evidence.';
    case 'fund_indicator':
      return 'Use a fund-specific indicator from custom_strategy_help.fundObservationV1.indicatorCatalog.';
    case 'rule_source':
      return 'Declare the referenced source as a StrategySpec indicator or use a built-in series such as close, volume, or turnover_rate.';
    case 'operator':
      return 'Use one of >, >=, <, <=, crosses_above, or crosses_below.';
    case 'exit_type':
      return 'Use stop_loss_pct, take_profit_pct, trailing_stop_pct, max_drawdown_stop_pct, atr_stop_loss, or time_stop_bars.';
    case 'positionSizing':
      return 'Use full_capital, fixed_fraction, risk_per_trade, or kelly_fraction.';
    case 'proxy_strategy':
      return 'A proxy StrategySpec is a separate strategy. Validate/backtest/save it only after explicit structured approval.';
    case 'condition_dsl':
      return 'Use canonical entry/exit rule groups, or request custom_strategy_help detail:"catalog" fields:["executableV1.conditionDslV1"] and revise the structured DSL fields.';
    default:
      return 'Revise this StrategySpec field according to custom_strategy_help before validating again.';
  }
}

bool isAllowedRuleRef(String value, Set<String> declaredRefs) {
  final text = value.trim();
  if (text.isEmpty) return false;
  if (declaredRefs.contains(text)) return true;
  if (RegExp(r'^close(?:_?\d+)?$').hasMatch(text)) return true;
  if (text == 'volume' || text == 'turnover_rate') return true;
  final registered = parseRegisteredStrategyIndicator(text);
  return registered != null;
}

Map<String, dynamic>? _mapOf(Object? raw) {
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

List? _listOf(Object? raw) => raw is List ? raw : null;

double? _numOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}
