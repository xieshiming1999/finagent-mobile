import 'dart:math';

import 'strategy_method_registry.dart';

Map<String, dynamic> normalizeStrategySpec(Map<String, dynamic> input) {
  final fundObservation = _normalizeFundObservationSpec(input);
  if (fundObservation != null) return fundObservation;

  final name = '${input['name'] ?? 'custom strategy'}'.trim();
  final version = _intOf(input['version'], fallback: 1);
  final id = input['id'] ?? 'custom_${_slug(name)}_v$version';
  final conditionDslIssues = _collectConditionDslIssues(input);
  final rawIndicators = input['indicators'] ?? input['observation'] ?? input['signals'];
  final indicatorList = rawIndicators is List
      ? rawIndicators
      : rawIndicators is Map
      ? rawIndicators.entries
            .where((entry) => entry.value is Map)
            .map(
              (entry) => {
                'id': entry.key,
                ...Map<String, dynamic>.from(entry.value as Map),
              },
            )
            .toList()
      : const [];
  final indicators = indicatorList.whereType<Map>().map((item) {
    final indicator = Map<String, dynamic>.from(item);
    final rawType =
        '${indicator['type'] ?? indicator['indicator'] ?? indicator['name'] ?? indicator['id']}';
    final ref = parseStrategyIndicatorRef(rawType);
    final params = {
      ...(_mapOf(indicator['params']) ?? <String, dynamic>{}),
      if (indicator['length'] != null || indicator['period'] != null)
        'period': _intOf(
          indicator['period'] ?? indicator['length'],
          fallback: ref.period,
        ),
    };
    final period = _intOf(params['period'], fallback: ref.period) ?? ref.period;
    final rawName = '${indicator['name'] ?? ''}'.trim();
    final explicitNameId = rawName.isNotEmpty &&
            parseRegisteredStrategyIndicator(rawName) == null
        ? rawName
        : null;
    final id =
        '${indicator['id'] ?? indicator['output'] ?? indicator['alias'] ?? explicitNameId ?? StrategyIndicatorRef(ref.type, period).id}';
    if (ref.type == 'bollinger') {
      params.remove('stdDev');
      params.remove('std_dev');
      params.remove('standardDeviation');
    } else if (_isBollingerBandComponentType(ref.type)) {
      final stdDevMultiplier =
          params['stdDevMultiplier'] ??
          params['stdDev'] ??
          params['std_dev'] ??
          params['standardDeviation'];
      if (params['stdDevMultiplier'] == null && stdDevMultiplier != null) {
        params['stdDevMultiplier'] = _numOf(stdDevMultiplier)?.toDouble();
      }
      params.remove('stdDev');
      params.remove('std_dev');
      params.remove('standardDeviation');
    }
    if (_isSupertrendComponentType(ref.type)) {
      final atrMultiplier =
          params['atrMultiplier'] ??
          params['multiplier'] ??
          params['factor'] ??
          params['atr_factor'];
      if (params['atrMultiplier'] == null && atrMultiplier != null) {
        params['atrMultiplier'] = _numOf(atrMultiplier)?.toDouble();
      }
      params.remove('multiplier');
      params.remove('factor');
      params.remove('atr_factor');
    }
    if (ref.type == 'ma_distance_pct') {
      final maPeriod =
          params['maPeriod'] ??
          params['ma_period'] ??
          params['movingAveragePeriod'];
      if (params['period'] == null && maPeriod != null) {
        params['period'] = _intOf(maPeriod, fallback: ref.period);
      }
      params.remove('maPeriod');
      params.remove('ma_period');
      params.remove('movingAveragePeriod');
    }
    return {
      ...indicator,
      'id': id,
      'type': ref.type,
      'source':
          indicator['source'] ??
          (ref.type == 'volume_sma' ? 'volume' : 'close'),
      'params': params,
    };
  }).toList();
  if (indicators.isEmpty) {
    indicators.addAll(_indicatorsFromRules(input));
  }
  final indicatorIds = indicators.map((item) => '${item['id']}').toSet();
  return {
    ...input,
    'id': id,
    'name': name,
    'version': version,
    'timeframe': input['timeframe'] ?? '1d',
    'dataRequirements': {
      'minBars':
          _intOf(
            _mapOf(input['dataRequirements'])?['minBars'],
            fallback: 120,
          ) ??
          120,
      'adjust': _mapOf(input['dataRequirements'])?['adjust'] ?? 'none',
      'requiredFields':
          _mapOf(input['dataRequirements'])?['requiredFields'] ??
          ['open', 'high', 'low', 'close', 'volume'],
    },
    'indicators': indicators,
    'entry': _normalizeRuleGroup(
      _entrySource(input),
      indicatorIds: indicatorIds,
    ),
    'exit': _normalizeRuleGroup(
      _exitSource(input),
      indicatorIds: indicatorIds,
      extraStops: const [
        'stop_loss_pct',
        'take_profit_pct',
        'trailing_stop_pct',
        'max_drawdown_stop_pct',
        'atr_stop_loss',
        'time_stop_bars',
      ],
    ),
    'positionSizing': _normalizeSizing(_sizingSource(input)),
    'cost': input['cost'] ?? {'commissionPct': 0.1, 'slippagePct': 0.05},
    'notes': input['notes'] ?? [],
    if (conditionDslIssues.isNotEmpty) 'conditionDslIssues': conditionDslIssues,
  };
}

bool _isBollingerBandComponentType(String type) =>
    type == 'bollinger_bandwidth' ||
    type == 'bollinger_percent_b' ||
    type == 'bollinger_band_distance_pct';

bool _isSupertrendComponentType(String type) =>
    type == 'supertrend_direction' || type == 'supertrend_distance_pct';

Map<String, dynamic>? _normalizeFundObservationSpec(
  Map<String, dynamic> input,
) {
  final observation = _mapOf(input['observation']);
  final market = '${input['market'] ?? ''}'.toLowerCase();
  final assetClass =
      '${input['assetClass'] ?? input['asset_class'] ?? input['type'] ?? ''}'
          .toLowerCase();
  final universe = _mapOf(input['universe']);
  final universeType = '${universe?['type'] ?? ''}'.toLowerCase();
  final isFund =
      assetClass.contains('fund') ||
      market.contains('fund') ||
      universeType.contains('fund') ||
      observation != null;
  if (!isFund) return null;

  final name = '${input['name'] ?? 'fund observation strategy'}'.trim();
  final version = _intOf(input['version'], fallback: 1);
  final id = input['id'] ?? 'custom_${_slug(name)}_v$version';
  final indicators = _normalizeFundIndicators(
    input['indicators'] ?? observation?['indicators'] ?? input['signals'],
  );
  final indicatorIds = indicators.map((item) => '${item['id']}').toSet();
  final observationRules = [
    ..._conditionRulesFromObservationList(input['signals']),
    ..._conditionRulesFromObservationList(observation?['entries']),
    ..._conditionRulesFromObservationList(observation?['signals']),
    ..._conditionRulesFromObservationList(observation?['rules']),
  ];
  final entrySource =
      input['entry'] ??
      input['entryRule'] ??
      input['entryConditions'] ??
      _fundEntrySource(observationRules);
  final exitSource =
      input['exit'] ??
      input['exitRule'] ??
      input['exitConditions'] ??
      _fundExitSource(observationRules, indicators);
  final existingRequirements = _mapOf(input['dataRequirements']);
  return {
    ...input,
    'id': id,
    'name': name,
    'version': version,
    'assetClass': 'fund',
    'market': input['market'] ?? 'fund',
    'timeframe': input['timeframe'] ?? '1d',
    'dataRequirements': {
      'minBars': _intOf(existingRequirements?['minBars'], fallback: 60) ?? 60,
      'adjust': existingRequirements?['adjust'] ?? 'none',
      'requiredFields':
          existingRequirements?['requiredFields'] ?? ['date', 'nav'],
      ...?existingRequirements,
      'dataClass': existingRequirements?['dataClass'] ?? 'ordinary_fund_nav',
    },
    'indicators': indicators,
    'entry': _normalizeRuleGroup(entrySource, indicatorIds: indicatorIds),
    'exit': _normalizeRuleGroup(exitSource, indicatorIds: indicatorIds),
    'positionSizing': _normalizeSizing(input['positionSizing']),
    'cost': input['cost'] ?? {'commissionPct': 0, 'slippagePct': 0},
    'notes': input['notes'] ?? [],
  };
}

List<Map<String, dynamic>> _normalizeFundIndicators(Object? raw) {
  final rawList = raw is List
      ? raw
      : raw is Map
      ? raw.entries
            .where((entry) => entry.value is Map)
            .map(
              (entry) => {
                'id': entry.key,
                ...Map<String, dynamic>.from(entry.value as Map),
              },
            )
            .toList()
      : const [];
  final out = <Map<String, dynamic>>[];
  final seen = <String>{};
  for (final item in rawList.whereType<Map>()) {
    final mapped = _fundIndicatorFromSource(Map<String, dynamic>.from(item));
    if (mapped == null || !seen.add('${mapped['id']}')) continue;
    out.add(mapped);
  }
  if (out.isEmpty) {
    out.addAll([
      {
        'id': 'navTrend20',
        'type': 'nav_trend',
        'source': 'nav',
        'params': {'period': 20},
      },
      {
        'id': 'fundDrawdown20',
        'type': 'fund_drawdown',
        'source': 'nav',
        'params': {'period': 20},
      },
    ]);
  }
  return out;
}

Map<String, dynamic>? _fundIndicatorFromSource(Map<String, dynamic> source) {
  final rawType =
      '${source['type'] ?? source['indicator'] ?? source['name'] ?? source['id'] ?? ''}'
          .trim();
  final rawSource = '${source['source'] ?? ''}'.trim().toLowerCase();
  final params = _mapOf(source['params']);
  final period =
      _intOf(
        source['period'] ?? source['length'] ?? params?['period'],
        fallback: 20,
      ) ??
      20;
  var type = rawType;
  var remapped = false;
  if (type == 'drawdown_pct' ||
      type == 'drawdown' ||
      type == 'rolling_drawdown') {
    type = 'fund_drawdown';
    remapped = true;
  }
  if ((type == 'sma' || type == 'ma' || type == 'moving_average') &&
      (rawSource.isEmpty || rawSource == 'nav')) {
    type = 'nav_trend';
    remapped = true;
  }
  if (type == 'nav' || type == 'nav_sma') {
    type = 'nav_trend';
    remapped = true;
  }
  if (!fundStrategyIndicators.contains(type)) return null;
  final camel = type.replaceAllMapped(
    RegExp(r'_([a-z])'),
    (match) => (match.group(1) ?? '').toUpperCase(),
  );
  final defaultId = type == 'fund_drawdown'
      ? 'fundDrawdown$period'
      : type == 'nav_trend'
      ? 'navTrend$period'
      : '$camel$period';
  final explicitId = source['id'] ?? source['output'] ?? source['alias'];
  return {
    ...source,
    'id': '${remapped ? defaultId : explicitId ?? defaultId}',
    'type': type,
    'source':
        source['source'] ??
        (type == 'money_yield' || type == 'seven_day_yield' ? 'yield' : 'nav'),
    'params': {...?params, 'period': period},
  };
}

List<Map<String, dynamic>> _conditionRulesFromObservationList(Object? raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((item) {
    final source = Map<String, dynamic>.from(item);
    final condition = _mapOf(source['condition']);
    return {
      'label': source['label'],
      'action': source['action'],
      'weight': source['weight'],
      ...(condition ?? source),
    };
  }).toList();
}

Map<String, dynamic> _fundEntrySource(List<Map<String, dynamic>> rules) {
  final candidates = rules.where((rule) => !_isFundExitObservation(rule));
  final selected = candidates.isNotEmpty
      ? candidates.toList()
      : rules.take(1).toList();
  return {'all': _normalizeFundObservationRules(selected)};
}

Map<String, dynamic> _fundExitSource(
  List<Map<String, dynamic>> rules,
  List<Map<String, dynamic>> indicators,
) {
  final candidates = rules.where(_isFundExitObservation).toList();
  if (candidates.isNotEmpty) {
    return {'any': _normalizeFundObservationRules(candidates)};
  }
  Map<String, dynamic>? drawdown;
  for (final indicator in indicators) {
    if (indicator['type'] == 'fund_drawdown') {
      drawdown = indicator;
      break;
    }
  }
  return {
    'any': [
      {'left': drawdown?['id'] ?? 'fundDrawdown20', 'op': '>=', 'right': 15},
    ],
  };
}

List<Map<String, dynamic>> _normalizeFundObservationRules(
  List<Map<String, dynamic>> rules,
) {
  return rules.expand((rule) {
    final all = _listOf(rule['all']);
    if (all != null) {
      return all.whereType<Map>().map(
        (item) => _normalizeFundObservationRule(Map.from(item)),
      );
    }
    final any = _listOf(rule['any']);
    if (any != null) {
      return any.whereType<Map>().map(
        (item) => _normalizeFundObservationRule(Map.from(item)),
      );
    }
    return [_normalizeFundObservationRule(rule)];
  }).toList();
}

Map<String, dynamic> _normalizeFundObservationRule(Map<String, dynamic> rule) {
  final left = _fundRuleSide(rule['left'] ?? rule['indicator'] ?? rule['type']);
  final period =
      _intOf(
        rule['period'] ?? _mapOf(rule['params'])?['period'],
        fallback: 20,
      ) ??
      20;
  final normalizedLeft = _normalizeFundRuleLeft(left, period: period);
  final rawRight = rule['right'] ?? rule['threshold'] ?? rule['value'];
  final right = _normalizeFundRuleRight(
    normalizedLeft,
    rawRight,
    rawLeft: left,
  );
  if (left == 'nav' && '$right'.toLowerCase().startsWith('sma')) {
    return {
      'left': 'navTrend20',
      'op': '${rule['op'] ?? rule['operator'] ?? '>'}'.trim(),
      'right': 0,
    };
  }
  return {
    'left': normalizedLeft,
    'op': _normalizeFundRuleOp(
      normalizedLeft,
      '${rule['op'] ?? rule['operator'] ?? ''}'.trim(),
    ),
    'right': right is String && right.toLowerCase().startsWith('sma')
        ? 0
        : right,
  };
}

String _normalizeFundRuleOp(String left, String raw) {
  final op = raw.isEmpty ? '>=' : raw;
  return left.startsWith('fundDrawdown') && (op == '<' || op == '<=')
      ? '>='
      : op;
}

String _fundRuleSide(Object? raw) {
  final source = _mapOf(raw);
  if (source != null) {
    return '${source['indicator'] ?? source['id'] ?? source['source'] ?? source['field'] ?? ''}'
        .trim();
  }
  return '${raw ?? ''}'.trim();
}

Object? _normalizeFundRuleRight(
  String left,
  Object? raw, {
  String rawLeft = '',
}) {
  final source = _mapOf(raw);
  final valueSource = source?['value'] ?? source?['threshold'] ?? raw;
  final isDrawdown =
      left.startsWith('fundDrawdown') ||
      RegExp(r'(^|_)dd($|_)|drawdown', caseSensitive: false).hasMatch(rawLeft);
  if (!isDrawdown) return valueSource;
  final value = _numOf(valueSource);
  if (value == null) return raw;
  final absolute = value.abs();
  return absolute > 0 && absolute <= 1 ? absolute * 100 : absolute;
}

String _normalizeFundRuleLeft(String raw, {int period = 20}) {
  if (RegExp(r'^[a-z][a-z0-9_]*_\d+$', caseSensitive: false).hasMatch(raw)) {
    return raw;
  }
  if (RegExp('drawdown', caseSensitive: false).hasMatch(raw)) {
    return 'fundDrawdown$period';
  }
  if (RegExp('navtrend|trend|sma|ma', caseSensitive: false).hasMatch(raw)) {
    return 'navTrend$period';
  }
  if (fundStrategyIndicators.contains(raw)) {
    final camel = raw.replaceAllMapped(
      RegExp(r'_([a-z])'),
      (match) => (match.group(1) ?? '').toUpperCase(),
    );
    return '$camel$period';
  }
  return raw.isEmpty ? 'navTrend20' : raw;
}

bool _isFundExitObservation(Map<String, dynamic> rule) {
  final text = '${rule['label'] ?? ''} ${rule['action'] ?? ''}'.toLowerCase();
  return RegExp(r'pause|stop|exit|redeem|risk|暂停|赎回|退出|风控|止损').hasMatch(text);
}

List<Map<String, dynamic>> _indicatorsFromRules(Map<String, dynamic> input) {
  final seen = <String>{};
  final indicators = <Map<String, dynamic>>[];
  for (final group in [_entrySource(input), _exitSource(input)]) {
    final rules = _looseConditionList(group);
    for (final raw in rules.whereType<Map>()) {
      final rule = Map<String, dynamic>.from(raw);
      for (final ref in _indicatorRefs(rule)) {
        final type = ref.type;
        if (!allowedStrategyIndicators.contains(type) || !seen.add(ref.id)) {
          continue;
        }
        indicators.add({
          'id': ref.id,
          'type': type,
          'source': type == 'volume_sma' ? 'volume' : 'close',
          'params': {'period': ref.period},
        });
      }
    }
  }
  return indicators;
}

Map<String, dynamic>? _normalizeRuleGroup(
  Object? raw, {
  Set<String> indicatorIds = const {},
  List<String> extraStops = const [],
}) {
  if (raw is List) raw = <String, dynamic>{'all': raw};
  if (raw is! Map) return null;
  final source = Map<String, dynamic>.from(raw);
  final rules = <Map<String, dynamic>>[];
  final explicit =
      _listOf(source['all']) ??
      _listOf(source['any']) ??
      _listOf(source['and']) ??
      _listOf(source['or']);
  if (explicit != null) {
    rules.addAll(
      explicit.whereType<Map>().map(
        (item) => _normalizeExplicitRule(
          Map<String, dynamic>.from(item),
          indicatorIds: indicatorIds,
        ),
      ),
    );
  } else {
    for (final item in _looseConditionList(source).whereType<Map>()) {
      final condition = Map<String, dynamic>.from(item);
      final leftRef = _leftRef(condition);
      final indicator = leftRef.type;
      final op = _operatorFromRule(condition);
      if (indicator.isEmpty || op.isEmpty) continue;
      rules.add({
        'left': _normalizedRuleLeft(condition, leftRef, indicatorIds),
        'op': op,
        'right': indicator == 'volume_sma'
            ? _volumeComparisonRight(
                leftRef,
                condition,
                indicatorIds: indicatorIds,
              )
            : _rightValue(condition, indicatorIds: indicatorIds),
      });
    }
  }
  for (final type in extraStops) {
    final value = _numOf(source[type]);
    if (value != null) rules.add({'type': type, 'value': value});
  }
  if (rules.isEmpty) return source;
  return _isAnyRuleGroup(source) ? {'any': rules} : {'all': rules};
}

Object? _entrySource(Map<String, dynamic> input) =>
    input['entry'] ??
    (_mapOf(input['signals'])?['entry']) ??
    input['entrySignals'] ??
    input['entryRules'] ??
    input['entryRule'] ??
    input['entryConditions'] ??
    _rulesDslSource(input, 'entry');

Object? _rulesDslSource(Map<String, dynamic> input, String mode) {
  final rules = _listOf(input['rules']);
  if (rules == null) return null;
  final selected = <Map<String, dynamic>>[];
  var hasAny = false;
  for (final item in rules.whereType<Map>()) {
    final rule = Map<String, dynamic>.from(item);
    if (_ruleActionMode(rule) != mode) continue;
    final parsed = _conditionRulesFromDsl('${rule['condition'] ?? rule['expression'] ?? ''}');
    if (parsed.isEmpty) continue;
    selected.addAll(parsed);
  }
  if (selected.isEmpty) return null;
  for (final rule in selected) {
    if (rule.remove('_logic') == 'or') hasAny = true;
  }
  final firstRule = rules.whereType<Map>().isNotEmpty
      ? Map<String, dynamic>.from(rules.whereType<Map>().first)
      : const <String, dynamic>{};
  final rawLogic = '${firstRule['logic'] ?? ''}'.toLowerCase();
  if (mode == 'exit' || rawLogic == 'or' || rawLogic == 'any') hasAny = true;
  return hasAny ? {'any': selected} : {'all': selected};
}

List<Map<String, dynamic>> _collectConditionDslIssues(Map<String, dynamic> input) {
  final rules = _listOf(input['rules']);
  if (rules == null) return const [];
  final issues = <Map<String, dynamic>>[];
  for (var index = 0; index < rules.length; index++) {
    final raw = rules[index];
    if (raw is! Map) {
      issues.add({
        'index': index,
        'field': 'rules',
        'message': 'conditionDslV1 rule must be an object.',
      });
      continue;
    }
    final rule = Map<String, dynamic>.from(raw);
    if (_ruleActionMode(rule).isEmpty) {
      issues.add({
        'index': index,
        'field': 'action',
        'value': rule['action'] ?? rule['side'] ?? rule['type'],
        'message':
            'conditionDslV1 action must be one of entry, exit, buy, sell, long, or close.',
      });
    }
    final condition = '${rule['condition'] ?? rule['expression'] ?? ''}';
    if (condition.trim().isEmpty) {
      issues.add({
        'index': index,
        'field': 'condition',
        'value': condition,
        'message': 'conditionDslV1 condition is required.',
      });
      continue;
    }
    if (_conditionRulesFromDsl(condition).isEmpty) {
      issues.add({
        'index': index,
        'field': 'condition',
        'value': condition,
        'message':
            'conditionDslV1 condition must be simple comparisons joined only by and/or.',
      });
    }
  }
  return issues;
}

String _ruleActionMode(Map<String, dynamic> rule) {
  final action = '${rule['action'] ?? rule['side'] ?? rule['type'] ?? ''}'
      .trim()
      .toLowerCase();
  if (action == 'entry' || action == 'exit') return action;
  if (action == 'buy' || action == 'long') return 'entry';
  if (action == 'sell' || action == 'close') return 'exit';
  return '';
}

List<Map<String, dynamic>> _conditionRulesFromDsl(String raw) {
  if (raw.trim().isEmpty) return const [];
  final tokens = raw
      .split(RegExp(r'\s+(and|or|&&|\|\|)\s+', caseSensitive: false))
      .where((part) => part.trim().isNotEmpty);
  final out = <Map<String, dynamic>>[];
  var nextLogic = 'and';
  for (final part in tokens) {
    final token = part.trim();
    if (RegExp(r'^(and|&&)$', caseSensitive: false).hasMatch(token)) {
      nextLogic = 'and';
      continue;
    }
    if (RegExp(r'^(or|\|\|)$', caseSensitive: false).hasMatch(token)) {
      nextLogic = 'or';
      continue;
    }
    final parsed = _parseDslComparison(token);
    if (parsed == null) return const [];
    out.add({...parsed, '_logic': nextLogic});
  }
  return out;
}

Map<String, dynamic>? _parseDslComparison(String raw) {
  final match = RegExp(
    r'^([a-zA-Z_][a-zA-Z0-9_]*|close|volume)\s*(crosses_above|crosses_below|>=|<=|==|!=|>|<)\s*([a-zA-Z_][a-zA-Z0-9_]*|[0-9]+(?:\.[0-9]+)?)$',
  ).firstMatch(raw.trim());
  if (match == null) return null;
  final right = match.group(3)!;
  return {
    'left': match.group(1)!,
    'operator': match.group(2)!,
    'value': _numOf(right) ?? right,
  };
}

bool _isAnyRuleGroup(Map<String, dynamic> source) {
  if (source.containsKey('any') || source.containsKey('or')) return true;
  final op = '${source['operator'] ?? source['op'] ?? source['logic'] ?? ''}'
      .trim()
      .toLowerCase();
  return op == 'or' || op == 'any' || op == '||' || op == '任一';
}

Map<String, dynamic> _normalizeExplicitRule(
  Map<String, dynamic> rule, {
  Set<String> indicatorIds = const {},
}) {
  if (_isStopRuleType(rule['type'])) return rule;
  for (final key in [
    'stop_loss_pct',
    'take_profit_pct',
    'trailing_stop_pct',
    'max_drawdown_stop_pct',
    'atr_stop_loss',
    'time_stop_bars',
  ]) {
    final value = _numOf(rule[key]);
    if (value != null) return {'type': key, 'value': value};
  }
  final leftRef = _leftRef(rule);
  final indicator = leftRef.type;
  final op = _operatorFromRule(rule);
  final comparisonRule = {...rule};
  comparisonRule.remove('type');
  return {
    ...comparisonRule,
    'left': _normalizedRuleLeft(rule, leftRef, indicatorIds),
    'op': op,
    'right': indicator == 'volume_sma'
        ? _volumeComparisonRight(leftRef, rule, indicatorIds: indicatorIds)
        : _rightValue(rule, indicatorIds: indicatorIds),
  };
}

String _operatorFromRule(Map<String, dynamic> rule) {
  final typeOperator = _isStopRuleType(rule['type']) ? null : rule['type'];
  final direct = '${rule['operator'] ?? rule['op'] ?? typeOperator ?? ''}'.trim();
  if (direct.isNotEmpty) return direct;
  for (final key in rule.keys) {
    final normalized = _normalizeOperatorKey(key);
    if (normalized.isNotEmpty) return normalized;
  }
  return '';
}

bool _isStopRuleType(Object? raw) => const {
  'stop_loss_pct',
  'take_profit_pct',
  'trailing_stop_pct',
  'max_drawdown_stop_pct',
  'atr_stop_loss',
  'time_stop_bars',
}.contains('$raw');

String _normalizeOperatorKey(String raw) {
  final compact = raw.replaceAll(RegExp(r'[,\s，]'), '');
  if (const {'>', '>=', '<', '<=', '==', '!='}.contains(compact)) {
    return compact;
  }
  final lower = raw.trim().toLowerCase().replaceAll(RegExp(r'[_\s-]+'), '_');
  if (lower == 'crosses_up' ||
      lower == 'cross_up' ||
      lower == 'crosses_above') {
    return 'crosses_above';
  }
  if (lower == 'crosses_down' ||
      lower == 'cross_down' ||
      lower == 'crosses_below') {
    return 'crosses_below';
  }
  return '';
}

String _normalizedRuleLeft(
  Map<String, dynamic> rule,
  StrategyIndicatorRef leftRef,
  Set<String> indicatorIds,
) {
  if (rule['left'] is Map) {
    if (leftRef.type == 'volume' || leftRef.type == 'volume_sma') {
      return 'volume';
    }
    return leftRef.id;
  }
  final rawLeft = '${rule['left'] ?? rule['lhs'] ?? rule['indicator'] ?? ''}'.trim();
  if (indicatorIds.contains(rawLeft)) return rawLeft;
  if (leftRef.type == 'volume' || leftRef.type == 'volume_sma') {
    return 'volume';
  }
  if (RegExp(r'^close_?\d*$', caseSensitive: false).hasMatch(rawLeft)) {
    return 'close';
  }
  if (rawLeft.isNotEmpty &&
      rawLeft != 'close' &&
      parseRegisteredStrategyIndicator(rawLeft) == null) {
    return rawLeft;
  }
  return leftRef.id;
}

List _looseConditionList(Object? raw) {
  if (raw is List) return raw;
  if (raw is! Map) return const [];
  final out = <dynamic>[];
  if (raw.containsKey('left') || raw.containsKey('indicator')) out.add(raw);
  for (final key in ['conditions', 'rules', 'all', 'any', 'and', 'or']) {
    final value = raw[key];
    if (value is List) out.addAll(value);
  }
  return out;
}

Map<String, dynamic> _normalizeSizing(Object? raw) {
  if (raw is String) return {'type': _normalizeSizingType(raw)};
  if (raw is! Map) return {'type': 'full_capital'};
  final input = Map<String, dynamic>.from(raw);
  final type = _normalizeSizingType(
    '${input['type'] ?? input['method'] ?? 'full_capital'}',
  );
  final value = _numOf(input['value']) ?? _numOf(input['fraction']);
  final normalized = {...input, 'type': type};
  if (value != null) normalized['value'] = value;
  final riskPct =
      _numOf(input['riskPct']) ??
      _numOf(input['risk_per_trade_pct']) ??
      _numOf(input['riskPerTradePct']);
  if (riskPct != null) normalized['riskPct'] = riskPct;
  final stopLossPct =
      _numOf(input['stopLossPct']) ?? _numOf(input['stop_loss_pct']);
  if (stopLossPct != null) normalized['stopLossPct'] = stopLossPct;
  final maxPositionPct =
      _numOf(input['maxPositionPct']) ?? _numOf(input['max_position_pct']);
  if (maxPositionPct != null) normalized['maxPositionPct'] = maxPositionPct;
  final initialFraction =
      _numOf(input['initialFraction']) ??
      _numOf(input['initial_fraction']) ??
      _numOf(input['fallbackFraction']) ??
      _numOf(input['fallback_fraction']);
  if (initialFraction != null) normalized['initialFraction'] = initialFraction;
  final minTrades = _numOf(input['minTrades']) ?? _numOf(input['min_trades']);
  if (minTrades != null) normalized['minTrades'] = minTrades;
  final kellyScale =
      _numOf(input['kellyScale']) ?? _numOf(input['kelly_scale']);
  if (kellyScale != null) normalized['kellyScale'] = kellyScale;
  return normalized;
}

Iterable<StrategyIndicatorRef> _indicatorRefs(Map<String, dynamic> rule) sync* {
  yield _leftRef(rule);
  if (rule['indicator2'] != null ||
      rule['params2'] != null ||
      rule['period2'] != null) {
    yield _refFromObject({
      'indicator': rule['indicator2'],
      'params': rule['params2'],
      'period': rule['period2'],
      'length': rule['length2'],
    });
  }
  final reference = rule['reference'];
  if (reference is Map) yield _refFromObject(reference);
  if (rule['referenceIndicator'] != null || rule['referencePeriod'] != null) {
    yield _refFromObject({
      'indicator': rule['referenceIndicator'] ?? rule['reference'],
      'period': rule['referencePeriod'] ?? rule['period'],
    });
  }
  final value = rule['value'];
  if (value is Map) yield* _refsFromRightObject(value);
  final right = rule['right'];
  if (right is Map) yield* _refsFromRightObject(right);
  final expressionObject = rule['expression'];
  if (expressionObject is Map) {
    yield* _indicatorRefs(Map<String, dynamic>.from(expressionObject));
  }
  final expression =
      '${rule['valueExpression'] ?? ''} ${rule['expression'] ?? ''}';
  final valueExpression = '${rule['value'] ?? ''}';
  final match = RegExp(
    r'volume_sma(?:[_ ]?|\()?(\d+)?\)?',
  ).firstMatch('$expression $valueExpression');
  if (match != null) {
    yield StrategyIndicatorRef(
      'volume_sma',
      int.tryParse(match.group(1) ?? '') ?? 20,
    );
  }
}

StrategyIndicatorRef _leftRef(Map<String, dynamic> rule) {
  final left = rule['left'];
  if (left is Map) return _refFromObject(left);
  final parsed = parseStrategyIndicatorRef(
    '${rule['indicator'] ?? left ?? rule['lhs'] ?? rule['ref'] ?? ''}',
  );
  final params = _mapOf(rule['params']);
  final period =
      _intOf(
        rule['period'] ?? rule['length'] ?? params?['period'],
        fallback: parsed.period,
      ) ??
      parsed.period;
  return StrategyIndicatorRef(parsed.type, period);
}

StrategyIndicatorRef _refFromObject(Map raw) {
  final ref = Map<String, dynamic>.from(raw);
  final parsed = parseStrategyIndicatorRef(
    '${ref['indicator'] ?? ref['type'] ?? ref['left'] ?? ref['field'] ?? ref['ref'] ?? ref['name'] ?? ref['id'] ?? ''}',
  );
  final params = _mapOf(ref['params']);
  final period =
      _intOf(
        ref['period'] ?? ref['length'] ?? params?['period'],
        fallback: parsed.period,
      ) ??
      parsed.period;
  return StrategyIndicatorRef(parsed.type, period);
}

Iterable<StrategyIndicatorRef> _refsFromRightObject(Map raw) sync* {
  final input = Map<String, dynamic>.from(raw);
  final mul = input['mul'];
  if (mul is List) {
    final left = mul.isNotEmpty ? mul.first : null;
    if (left is String) yield parseStrategyIndicatorRef(left);
    return;
  }
  yield _refFromObject(input);
}

Object? _rightValue(
  Map<String, dynamic> condition, {
  Set<String> indicatorIds = const {},
}) {
  final rhs = condition['rhs'];
  if (rhs is String) {
    if (indicatorIds.contains(rhs)) return rhs;
    final ref = parseStrategyIndicatorRef(rhs);
    if (allowedStrategyIndicators.contains(ref.type) ||
        indicatorIds.contains(ref.id)) {
      return ref.id;
    }
  }
  if (condition['indicator2'] != null ||
      condition['params2'] != null ||
      condition['period2'] != null) {
    return _refFromObject({
      'indicator': condition['indicator2'],
      'params': condition['params2'],
      'period': condition['period2'],
      'length': condition['length2'],
    }).id;
  }
  final reference = condition['reference'];
  if (reference is Map) {
    final ref = _refFromObject(reference);
    return {
      'mul': [
        ref.id,
        _numOf(condition['scale']) ?? _numOf(condition['multiplier']) ?? 1,
      ],
    };
  }
  if (condition['referenceIndicator'] != null ||
      condition['referencePeriod'] != null) {
    final ref = _refFromObject({
      'indicator': condition['referenceIndicator'] ?? condition['reference'],
      'period': condition['referencePeriod'] ?? condition['period'],
    });
    return {
      'mul': [
        ref.id,
        _numOf(condition['scale']) ?? _numOf(condition['multiplier']) ?? 1,
      ],
    };
  }
  final value = condition['value'];
  if (value is Map) {
    if (value['mul'] is List) {
      return _normalizeMulRight(value, indicatorIds: indicatorIds);
    }
    final ref = _refFromObject(value);
    return {
      'mul': [
        ref.id,
        _numOf(value['scale']) ??
            _numOf(value['multiplier']) ??
            _numOf(value['factor']) ??
            _numOf(condition['scale']) ??
            _numOf(condition['multiplier']) ??
            _numOf(condition['factor']) ??
            1,
      ],
    };
  }
  if (value is String) {
    final ref = parseStrategyIndicatorRef(value);
    if (ref.type == 'volume_sma') {
      return {
        'mul': [
          ref.id,
          _numOf(condition['scale']) ??
              _numOf(condition['multiplier']) ??
              _numOf(condition['factor']) ??
              1,
        ],
      };
    }
    if (allowedStrategyIndicators.contains(ref.type) ||
        indicatorIds.contains(ref.id)) {
      return ref.id;
    }
  }
  final right = condition['right'];
  if (right is Map) {
    if (right['mul'] is List) {
      return _normalizeMulRight(right, indicatorIds: indicatorIds);
    }
    final op = '${right['op'] ?? right['operator'] ?? ''}'.trim();
    if (op == '*') {
      final left = right['left'] ?? right['indicator'] ?? right['type'];
      final ref = left is String
          ? parseStrategyIndicatorRef(left)
          : _refFromObject(right);
      return {
        'mul': [
          indicatorIds.contains(left) ? left : ref.id,
          _numOf(right['right']) ??
              _numOf(right['value']) ??
              _numOf(right['scale']) ??
              _numOf(right['multiplier']) ??
              _numOf(right['factor']) ??
              1,
        ],
      };
    }
    final ref = _refFromObject(right);
    return {
      'mul': [
        ref.id,
        _numOf(right['scale']) ??
            _numOf(right['multiplier']) ??
            _numOf(right['factor']) ??
            _numOf(right['value']) ??
            1,
      ],
    };
  }
  final expressionObject = condition['expression'];
  if (expressionObject is Map) {
    return _rightValue(
      Map<String, dynamic>.from(expressionObject),
      indicatorIds: indicatorIds,
    );
  }
  final expression =
      '${condition['valueExpression'] ?? ''} ${condition['expression'] ?? ''}';
  final match = RegExp(
    r'volume_sma(?:[_ ]?|\()?(\d+)?\)?\s*\*\s*([0-9.]+)',
  ).firstMatch(expression);
  if (match != null) {
    final period = int.tryParse(match.group(1) ?? '') ?? 20;
    return {
      'mul': ['vol$period', double.tryParse(match.group(2)!) ?? 1],
    };
  }
  final valueExpression = '${condition['value'] ?? ''}';
  final valueFirst = RegExp(
    r'([0-9.]+)\s*\*\s*volume_sma(?:[_ ]?|\()?(\d+)?\)?',
  ).firstMatch(valueExpression);
  if (valueFirst != null) {
    final period = int.tryParse(valueFirst.group(2) ?? '') ?? 20;
    return {
      'mul': ['vol$period', double.tryParse(valueFirst.group(1)!) ?? 1],
    };
  }
  final smaOnly = RegExp(
    r'^volume_sma(?:[_ ]?|\()?(\d+)?\)?$',
  ).firstMatch(valueExpression.trim());
  if (smaOnly != null) {
    final period = int.tryParse(smaOnly.group(1) ?? '') ?? 20;
    return {
      'mul': ['vol$period', 1],
    };
  }
  return _numOf(condition['value']) ?? right;
}

Object? _normalizeMulRight(Map raw, {Set<String> indicatorIds = const {}}) {
  final mul = raw['mul'];
  if (mul is! List) return raw;
  final left = mul.isNotEmpty ? mul[0] : null;
  final right = mul.length > 1 ? mul[1] : null;
  final normalizedLeft = left is String
      ? indicatorIds.contains(left)
            ? left
            : parseStrategyIndicatorRef(left).id
      : left;
  return {
    'mul': [normalizedLeft, _numOf(right) ?? right],
  };
}

Object? _volumeComparisonRight(
  StrategyIndicatorRef leftRef,
  Map<String, dynamic> condition, {
  Set<String> indicatorIds = const {},
}) {
  if (condition['reference'] is Map ||
      condition['referenceIndicator'] != null ||
      condition['referencePeriod'] != null ||
      condition['value'] is Map ||
      condition['right'] is Map ||
      condition['expression'] is Map ||
      '${condition['valueExpression'] ?? ''} ${condition['expression'] ?? ''}'
          .trim()
          .isNotEmpty) {
    return _rightValue(condition, indicatorIds: indicatorIds);
  }
  return {
    'mul': [leftRef.id, _numOf(condition['value']) ?? 1],
  };
}

Object? _exitSource(Map<String, dynamic> input) {
  final rawExitBase =
      input['exit'] ??
      input['exits'] ??
      input['exitSignals'] ??
      input['exitRules'] ??
      input['exitRule'] ??
      input['exitConditions'];
  final rawExitDsl = _rulesDslSource(input, 'exit');
  final rawExit =
      rawExitBase == null && rawExitDsl != null
      ? rawExitDsl
      : rawExitBase is Map && rawExitDsl is Map
      ? {...Map<String, dynamic>.from(rawExitDsl), ...Map<String, dynamic>.from(rawExitBase)}
      : rawExitBase;
  final exit = rawExit is List
      ? <String, dynamic>{'any': rawExit}
      : _mapOf(rawExit) ?? <String, dynamic>{};
  if (input.containsKey('stopLossPct') && !exit.containsKey('stop_loss_pct')) {
    exit['stop_loss_pct'] = input['stopLossPct'];
  }
  if (input.containsKey('takeProfitPct') &&
      !exit.containsKey('take_profit_pct')) {
    exit['take_profit_pct'] = input['takeProfitPct'];
  }
  if (input.containsKey('trailingStopPct') &&
      !exit.containsKey('trailing_stop_pct')) {
    exit['trailing_stop_pct'] = input['trailingStopPct'];
  }
  if (input.containsKey('maxDrawdownStopPct') &&
      !exit.containsKey('max_drawdown_stop_pct')) {
    exit['max_drawdown_stop_pct'] = input['maxDrawdownStopPct'];
  }
  if (input.containsKey('atrStopLoss') && !exit.containsKey('atr_stop_loss')) {
    exit['atr_stop_loss'] = input['atrStopLoss'];
  }
  if (input.containsKey('atrStopLossMultiplier') &&
      !exit.containsKey('atr_stop_loss')) {
    exit['atr_stop_loss'] = input['atrStopLossMultiplier'];
  }
  if (input.containsKey('timeStopBars') &&
      !exit.containsKey('time_stop_bars')) {
    exit['time_stop_bars'] = input['timeStopBars'];
  }
  for (final key in [
    'stop_loss_pct',
    'take_profit_pct',
    'trailing_stop_pct',
    'max_drawdown_stop_pct',
    'atr_stop_loss',
    'time_stop_bars',
  ]) {
    if (input.containsKey(key) && !exit.containsKey(key)) {
      exit[key] = input[key];
    }
  }
  if ((exit.containsKey('stop_loss_pct') ||
          exit.containsKey('take_profit_pct') ||
          exit.containsKey('trailing_stop_pct') ||
          exit.containsKey('max_drawdown_stop_pct') ||
          exit.containsKey('atr_stop_loss') ||
          exit.containsKey('time_stop_bars')) &&
      !exit.containsKey('operator') &&
      !exit.containsKey('op') &&
      !exit.containsKey('logic') &&
      !exit.containsKey('all') &&
      !exit.containsKey('any') &&
      !exit.containsKey('or')) {
    exit['operator'] = 'or';
  }
  return exit.isEmpty ? input['exit'] : exit;
}

Object? _sizingSource(Map<String, dynamic> input) {
  if (input.containsKey('positionSizing')) {
    final positionSizing = input['positionSizing'];
    if (positionSizing is String) {
      final fixedFraction =
          _numOf(input['fixedFraction']) ??
          _numOf(input['fixed_fraction']) ??
          _numOf(input['positionFraction']) ??
          _numOf(input['position_fraction']);
      if (fixedFraction != null) {
        return {'type': positionSizing, 'value': fixedFraction};
      }
    }
    return positionSizing;
  }
  final fixedFraction =
      _numOf(input['fixedFraction']) ??
      _numOf(input['fixed_fraction']) ??
      _numOf(input['positionFraction']) ??
      _numOf(input['position_fraction']);
  if (fixedFraction != null) {
    return {'type': 'fixed_fraction', 'value': fixedFraction};
  }
  return null;
}

String _normalizeSizingType(String raw) => raw
    .replaceAll('fullCapital', 'full_capital')
    .replaceAll('fixedFraction', 'fixed_fraction')
    .replaceAll('riskPerTrade', 'risk_per_trade')
    .replaceAll('kellyFraction', 'kelly_fraction');

String _slug(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (slug.isEmpty) return 'strategy';
  return slug.substring(0, min(40, slug.length));
}

int? _intOf(Object? raw, {int? fallback}) {
  if (raw is num) return raw.toInt();
  if (raw is String) {
    final match = RegExp(r'\d+').firstMatch(raw);
    if (match != null) return int.tryParse(match.group(0)!);
  }
  return fallback;
}

double? _numOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

Map<String, dynamic>? _mapOf(Object? raw) {
  if (raw is! Map) return null;
  return Map<String, dynamic>.from(raw);
}

List? _listOf(Object? raw) => raw is List ? raw : null;
