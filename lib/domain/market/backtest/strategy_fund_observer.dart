import 'dart:math';

import 'strategy_method_registry.dart';

Map<String, dynamic> observeFundStrategySpec({
  required Map<String, dynamic> validation,
  required Map<String, dynamic> spec,
  required List<Map<String, dynamic>> rows,
}) {
  if (rows.isEmpty) {
    return _fundRowsNeededResult(
      action: 'custom_strategy_observe',
      validation: validation,
      spec: spec,
    );
  }
  final normalizedRows = rows.map(_normalizeFundRow).toList()
    ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  final categoryEvidence = _fundCategoryEvidence(spec, normalizedRows);
  final coverageEvidence = _fundCoverageEvidence(
    spec,
    normalizedRows,
    categoryEvidence,
  );
  final indicators = _computeFundIndicators(spec, normalizedRows);
  final comparisonEvidence = _fundComparisonEvidence(spec, normalizedRows);
  final entry = _evaluateRuleGroup(spec['entry'], indicators);
  final exit = _evaluateRuleGroup(spec['exit'], indicators);
  final signal = {
    'entrySatisfied': entry['satisfied'],
    'exitSatisfied': exit['satisfied'],
    'suggestion': exit['satisfied'] == true
        ? 'review_or_pause'
        : entry['satisfied'] == true
        ? 'observe_or_prepare'
        : 'wait',
  };
  final result = {
    'action': 'custom_strategy_observe',
    'status': 'observed',
    'assetClass': 'fund',
    'backtestable': false,
    'strategyId': validation['strategyId'],
    'version': validation['version'],
    'spec': spec,
    'rows': normalizedRows.length,
    'sourceDataTime': normalizedRows.last['date'],
    'fundCategoryEvidence': categoryEvidence,
    'fundCoverageEvidence': coverageEvidence,
    'indicators': indicators,
    'entry': entry,
    'exit': exit,
    'signal': signal,
    'dcaObservation': _dcaObservation(spec, indicators, signal),
    'monitorDraft': _monitorDraft(spec, entry, exit, signal),
    'workflowAdvice':
        'This is fund observation evidence, not a stock K-line backtest. Use it for fund-specific monitoring or trade preparation; do not report stock trades, Sharpe, or K-line signals from this result.',
  };
  if (comparisonEvidence != null) {
    result['comparisonEvidence'] = comparisonEvidence;
  }
  return result;
}

Map<String, dynamic> backtestFundStrategySpec({
  required Map<String, dynamic> validation,
  required Map<String, dynamic> spec,
  required List<Map<String, dynamic>> rows,
}) {
  if (rows.isEmpty) {
    return _fundRowsNeededResult(
      action: 'custom_strategy_fund_backtest',
      validation: validation,
      spec: spec,
    );
  }
  final normalizedRows = rows.map(_normalizeFundRow).toList()
    ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
  final categoryEvidence = _fundCategoryEvidence(spec, normalizedRows);
  final coverageEvidence = _fundCoverageEvidence(
    spec,
    normalizedRows,
    categoryEvidence,
  );
  final groups = <String, List<Map<String, dynamic>>>{};
  final names = <String, String>{};
  for (final row in normalizedRows) {
    final code = '${row['code'] ?? ''}'.trim();
    final key = code.isEmpty ? 'fund' : code;
    groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
    final name = '${row['name'] ?? ''}'.trim();
    if (name.isNotEmpty) names[key] = name;
  }
  final fundResults = groups.entries.map((entry) {
    final sorted = entry.value
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final indicators = _computeFundIndicators(spec, sorted);
    final entryEval = _evaluateRuleGroup(spec['entry'], indicators);
    final exitEval = _evaluateRuleGroup(spec['exit'], indicators);
    final metrics = _fundPeriodMetrics(sorted);
    final resultCategoryEvidence = _fundCategoryEvidence(spec, sorted);
    final resultCoverageEvidence = _fundCoverageEvidence(
      spec,
      sorted,
      resultCategoryEvidence,
    );
    final resultRiskEvidence = _fundRiskEvidence(
      metrics: metrics,
      categoryEvidence: resultCategoryEvidence,
      coverageEvidence: resultCoverageEvidence,
    );
    return {
      'code': entry.key,
      if ((names[entry.key] ?? '').isNotEmpty) 'name': names[entry.key],
      'actualStartDate': sorted.first['date'],
      'actualEndDate': sorted.last['date'],
      'rows': sorted.length,
      'fundCategoryEvidence': resultCategoryEvidence,
      'fundCoverageEvidence': resultCoverageEvidence,
      'fundRiskEvidence': resultRiskEvidence,
      'metrics': metrics,
      'indicators': indicators,
      'entry': entryEval,
      'exit': exitEval,
      'signal': {
        'entrySatisfied': entryEval['satisfied'],
        'exitSatisfied': exitEval['satisfied'],
        'suggestion': exitEval['satisfied'] == true
            ? 'review_or_pause'
            : entryEval['satisfied'] == true
            ? 'observe_or_prepare'
            : 'wait',
      },
    };
  }).toList();
  fundResults.sort(
    (a, b) => ((((b['metrics'] as Map?)?['periodReturnPct'] as num?) ?? 0))
        .compareTo((((a['metrics'] as Map?)?['periodReturnPct'] as num?) ?? 0)),
  );
  for (var i = 0; i < fundResults.length; i++) {
    fundResults[i]['rank'] = i + 1;
  }
  final aggregateRiskEvidence = _aggregateFundRiskEvidence(
    fundResults,
    categoryEvidence,
    coverageEvidence,
  );
  final periodEvidence = _aggregateFundPeriodEvidence(
    fundResults,
    categoryEvidence,
    coverageEvidence,
  );
  final ruleEvidence = _aggregateFundRuleEvidence(fundResults);
  return {
    'action': 'custom_strategy_fund_backtest',
    'status': 'fund_backtested',
    'assetClass': 'fund',
    'mode': 'fund_period_evidence',
    'stockBacktestable': false,
    'strategyId': validation['strategyId'],
    'version': validation['version'],
    'spec': spec,
    'fundCount': fundResults.length,
    'rows': normalizedRows.length,
    'sourceDataTime': normalizedRows.last['date'],
    'fundCategoryEvidence': categoryEvidence,
    'fundCoverageEvidence': coverageEvidence,
    'fundRiskEvidence': aggregateRiskEvidence,
    'periodEvidence': periodEvidence,
    'ruleEvidence': ruleEvidence,
    'fundResults': fundResults,
    'tradeBoundary':
        'Fund backtest evidence is research/observation only. Do not subscribe, redeem, rebalance, or create simulated trades without explicit user confirmation.',
    'workflowAdvice':
        'Use this evidence for fund-specific strategy validation. It is not a stock K-line backtest and does not produce executable stock trades, Sharpe, or broker orders.',
  };
}

Map<String, dynamic> _aggregateFundPeriodEvidence(
  List<Map<String, dynamic>> fundResults,
  Map<String, dynamic> categoryEvidence,
  Map<String, dynamic> coverageEvidence,
) {
  final returns = fundResults
      .map((row) => _numOf((row['metrics'] as Map?)?['periodReturnPct']))
      .whereType<double>()
      .toList();
  final sortedReturns = [...returns]..sort();
  final best = returns.isEmpty ? null : returns.reduce(max);
  final worst = returns.isEmpty ? null : returns.reduce(min);
  return {
    'mode': 'fund_period_evidence',
    'assetClass': 'fund',
    'status': coverageEvidence['status'],
    'fundCount': fundResults.length,
    'pricingBasis': categoryEvidence['pricingBasis'],
    'actualStartDate': coverageEvidence['actualStartDate'],
    'actualEndDate': coverageEvidence['actualEndDate'],
    'rows': coverageEvidence['actualRows'],
    'bestPeriodReturnPct': best == null ? null : _round(best),
    'worstPeriodReturnPct': worst == null ? null : _round(worst),
    'medianPeriodReturnPct': sortedReturns.isEmpty
        ? null
        : _round(sortedReturns[sortedReturns.length ~/ 2]),
    'perFund': fundResults
        .map(
          (row) => {
            'code': row['code'],
            if (row['name'] != null) 'name': row['name'],
            'rank': row['rank'],
            'actualStartDate': row['actualStartDate'],
            'actualEndDate': row['actualEndDate'],
            'rows': row['rows'],
            'metrics': row['metrics'],
            'coverageStatus': (row['fundCoverageEvidence'] as Map?)?['status'],
          },
        )
        .toList(),
    'boundary':
        'Fund period evidence is NAV/yield period evidence, not an executable stock backtest or broker order.',
  };
}

Map<String, dynamic> _aggregateFundRuleEvidence(
  List<Map<String, dynamic>> fundResults,
) {
  final entrySatisfied = fundResults
      .where((row) => (row['entry'] as Map?)?['satisfied'] == true)
      .length;
  final exitSatisfied = fundResults
      .where((row) => (row['exit'] as Map?)?['satisfied'] == true)
      .length;
  return {
    'mode': 'fund_rule_evidence',
    'assetClass': 'fund',
    'fundCount': fundResults.length,
    'entrySatisfiedCount': entrySatisfied,
    'exitSatisfiedCount': exitSatisfied,
    'entryUnsatisfiedCount': fundResults.length - entrySatisfied,
    'exitUnsatisfiedCount': fundResults.length - exitSatisfied,
    'perFund': fundResults
        .map(
          (row) => {
            'code': row['code'],
            if (row['name'] != null) 'name': row['name'],
            'rank': row['rank'],
            'entry': row['entry'],
            'exit': row['exit'],
            'signal': row['signal'],
          },
        )
        .toList(),
    'tradeBoundary':
        'Fund rule evidence can guide observation or preparation only. It does not authorize subscription, redemption, rebalance, or simulated trading.',
  };
}

Map<String, dynamic> _fundRowsNeededResult({
  required String action,
  required Map<String, dynamic> validation,
  required Map<String, dynamic> spec,
}) {
  return {
    'action': action,
    'status': 'needs_data',
    'assetClass': 'fund',
    'strategyId': validation['strategyId'],
    'version': validation['version'],
    'spec': spec,
    'missing': ['fundRows'],
    'requiredReadbacks': ['query_fund_nav', 'query_fund_money_yield'],
    'workflowAdvice':
        'No structured fundRows were supplied. Read governed fund NAV or money-yield rows for a selected fund code, then call this action again with code/fundCode/symbol or structured fundRows. This is not executable evidence yet.',
  };
}

Map<String, dynamic> _normalizeFundRow(Map<String, dynamic> row) {
  final date = '${row['date'] ?? row['navDate'] ?? row['tradeDate'] ?? ''}'
      .trim();
  return {
    'code': '${row['code'] ?? row['symbol'] ?? row['fundCode'] ?? ''}'.trim(),
    'name': '${row['name'] ?? row['fundName'] ?? ''}'.trim(),
    'date': date,
    'nav': _numOf(row['nav'] ?? row['unitNav'] ?? row['netValue']),
    'fundType': '${row['fundType'] ?? row['type'] ?? row['category'] ?? ''}'
        .trim(),
    'dataClass': '${row['dataClass'] ?? row['canonicalSchema'] ?? ''}'.trim(),
    'listedPrice': _numOf(
      row['listedPrice'] ??
          row['marketPrice'] ??
          row['price'] ??
          row['close'] ??
          row['quotePrice'],
    ),
    'underlyingIndex': '${row['underlyingIndex'] ?? row['indexCode'] ?? ''}'
        .trim(),
    'moneyYield': _numOf(
      row['moneyYield'] ??
          row['millionCopiesIncome'] ??
          row['per10kIncome'] ??
          row['万份收益'],
    ),
    'sevenDayYield': _numOf(
      row['sevenDayYield'] ?? row['sevenDayAnnualized'] ?? row['七日年化'],
    ),
  };
}

Map<String, dynamic> _fundCategoryEvidence(
  Map<String, dynamic> spec,
  List<Map<String, dynamic>> rows,
) {
  final dataRequirements = spec['dataRequirements'];
  final dataClass = dataRequirements is Map
      ? '${dataRequirements['dataClass'] ?? ''}'.trim().toLowerCase()
      : '';
  final specFundCategory = _normalizeFundCategoryValue(
    spec['fundCategory'] ?? spec['fundType'],
  );
  final rowCategories = rows
      .map(
        (row) => _normalizeFundCategoryValue(
          row['fundCategory'] ?? row['fund_category'],
        ),
      )
      .toList();
  final rowDataClasses = rows
      .map((row) => '${row['dataClass'] ?? ''}'.trim().toLowerCase())
      .toList();
  final hasNav = rows.any((row) => row['nav'] is double);
  final hasListedPrice = rows.any((row) => row['listedPrice'] is double);
  final hasUnderlyingIndex = rows.any(
    (row) => '${row['underlyingIndex'] ?? ''}'.trim().isNotEmpty,
  );
  final hasMoneyYield = rows.any(
    (row) => row['moneyYield'] is double || row['sevenDayYield'] is double,
  );
  final isMoney =
      specFundCategory == 'money' ||
      dataClass == 'money_fund_yield' ||
      rowCategories.contains('money') ||
      rowDataClasses.contains('money_fund_yield');
  final isEtf =
      specFundCategory == 'etf' ||
      dataClass == 'etf_nav' ||
      dataClass == 'etf_fund_nav' ||
      rowCategories.contains('etf') ||
      rowDataClasses.contains('etf_nav') ||
      rowDataClasses.contains('etf_fund_nav');
  final pricingBasis = isMoney
      ? 'money_yield'
      : dataClass.contains('listed_fund_quote') || hasListedPrice
      ? 'listed_market_price'
      : dataClass.contains('underlying_index') || hasUnderlyingIndex
      ? 'underlying_index'
      : isEtf
      ? hasNav
            ? 'fund_nav'
            : 'fund_nav_or_listed_quote_required'
      : hasNav
      ? 'fund_nav'
      : hasMoneyYield
      ? 'money_yield'
      : 'unknown';
  final requiredReadbacks = isMoney
      ? ['query_fund_money_yield']
      : isEtf
      ? ['query_fund_nav', 'query_quote', 'query_index_quote']
      : ['query_fund_nav'];
  final observedPricingBases = <String>[
    if (hasNav) 'fund_nav',
    if (hasListedPrice || dataClass.contains('listed_fund_quote'))
      'listed_market_price',
    if (hasUnderlyingIndex || dataClass.contains('underlying_index'))
      'underlying_index',
    if (hasMoneyYield) 'money_yield',
  ];
  const etfAllowedPricingBases = [
    'fund_nav',
    'listed_market_price',
    'underlying_index',
  ];
  final warnings = <String>[
    if (isMoney && hasNav)
      'money fund evidence should prioritize money_yield/seven_day_yield over ordinary NAV.',
    if (isEtf && !observedPricingBases.any(etfAllowedPricingBases.contains))
      'ETF evidence must disclose whether it uses fund NAV, listed market price, or underlying index data.',
    if (!hasNav && !hasMoneyYield)
      'fund rows do not contain NAV or money-yield values.',
  ];
  return {
    'category': isMoney
        ? 'money_fund'
        : isEtf
        ? 'etf_or_etf_link'
        : 'ordinary_fund',
    'pricingBasis': pricingBasis,
    'dataClass': dataClass.isEmpty ? null : dataClass,
    'fundCategory': specFundCategory.isEmpty ? null : specFundCategory,
    'hasNav': hasNav,
    'hasListedPrice': hasListedPrice,
    'hasUnderlyingIndex': hasUnderlyingIndex,
    'hasMoneyYield': hasMoneyYield,
    'requiredReadbacks': requiredReadbacks,
    if (isEtf)
      'etfPricingEvidence': {
        'allowedPricingBases': etfAllowedPricingBases,
        'observedPricingBases': observedPricingBases
            .where(etfAllowedPricingBases.contains)
            .toList(),
        'missingPricingBases': etfAllowedPricingBases
            .where((basis) => !observedPricingBases.contains(basis))
            .toList(),
      },
    'warnings': warnings,
  };
}

Map<String, dynamic> _fundCoverageEvidence(
  Map<String, dynamic> spec,
  List<Map<String, dynamic>> rows,
  Map<String, dynamic> categoryEvidence,
) {
  final dataRequirements = spec['dataRequirements'];
  final requirements = dataRequirements is Map
      ? Map<String, dynamic>.from(dataRequirements)
      : const <String, dynamic>{};
  final minBars = _numOf(requirements['minBars'])?.toInt() ?? 1;
  final explicitFields = ((requirements['requiredFields'] as List?) ?? const [])
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  final requiredFields = explicitFields.isNotEmpty
      ? explicitFields
      : _defaultFundRequiredFields(categoryEvidence);
  final missingFields = requiredFields
      .where((field) => !_hasUsableFundField(rows, field))
      .toList();
  final enoughRows = rows.length >= minBars;
  return {
    'status': enoughRows && missingFields.isEmpty
        ? 'sufficient'
        : 'insufficient',
    'requestedMinRows': minBars,
    'actualRows': rows.length,
    'requiredFields': requiredFields,
    'missingFields': missingFields,
    'actualStartDate': rows.isEmpty ? null : rows.first['date'],
    'actualEndDate': rows.isEmpty ? null : rows.last['date'],
    'pricingBasis': categoryEvidence['pricingBasis'],
    'dataClass': categoryEvidence['dataClass'],
    'warnings': [
      if (!enoughRows)
        'fund rows below requested minBars; period evidence is partial.',
      if (missingFields.isNotEmpty)
        'fund rows are missing required fields: ${missingFields.join(', ')}.',
    ],
  };
}

List<String> _defaultFundRequiredFields(Map<String, dynamic> categoryEvidence) {
  final pricingBasis = '${categoryEvidence['pricingBasis'] ?? ''}';
  if (pricingBasis == 'money_yield') return ['date', 'moneyYield'];
  if (pricingBasis == 'listed_market_price') return ['date', 'listedPrice'];
  if (pricingBasis == 'underlying_index') return ['date', 'underlyingIndex'];
  return ['date', 'nav'];
}

bool _hasUsableFundField(List<Map<String, dynamic>> rows, String field) {
  return rows.any((row) {
    final value = row[field];
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  });
}

Map<String, dynamic> _fundPeriodMetrics(List<Map<String, dynamic>> rows) {
  final navs = rows.map((row) => row['nav']).whereType<double>().toList();
  final moneyYields = rows
      .map((row) => row['moneyYield'])
      .whereType<double>()
      .toList();
  final sevenDayYields = rows
      .map((row) => row['sevenDayYield'])
      .whereType<double>()
      .toList();
  final navReturn = navs.length >= 2 && navs.first != 0
      ? (navs.last - navs.first) / navs.first * 100
      : null;
  final hasNav = navs.length >= 2;
  final riskPeriod = hasNav ? min(60, navs.length - 1) : 0;
  return {
    'periodReturnPct': navReturn == null ? null : _round(navReturn),
    'maxDrawdownPct': hasNav ? _round(_drawdown(navs, navs.length) ?? 0) : null,
    'averageDrawdownPct': hasNav
        ? _round(_averageDrawdown(navs, riskPeriod) ?? 0)
        : null,
    'ulcerIndex': hasNav ? _round(_ulcerIndex(navs, riskPeriod) ?? 0) : null,
    'drawdownDurationBars': hasNav
        ? _drawdownDurationBars(navs, riskPeriod) ?? 0
        : null,
    'volatilityPct': hasNav
        ? _round(_volatility(navs, min(20, navs.length - 1)) ?? 0)
        : null,
    'gainToPainRatio': hasNav
        ? _round(_gainToPain(navs, riskPeriod) ?? 0)
        : null,
    'recoveryRatio': hasNav
        ? _round(_recoveryRatio(navs, riskPeriod) ?? 0)
        : null,
    'omegaRatio': hasNav
        ? _round(_omega(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'tailRatio': hasNav
        ? _round(_tailRatio(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'positivePeriodRatioPct': hasNav
        ? _round(_positivePeriodRatio(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'negativePeriodRatioPct': hasNav
        ? _round(_negativePeriodRatio(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'returnSkewness': hasNav
        ? _round(_returnSkewness(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'returnKurtosis': hasNav
        ? _round(_returnKurtosis(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'valueAtRiskPct': hasNav
        ? _round(_valueAtRisk(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'conditionalValueAtRiskPct': hasNav
        ? _round(_conditionalValueAtRisk(navs, {'period': riskPeriod}) ?? 0)
        : null,
    'moneyYieldTotal': moneyYields.isEmpty
        ? null
        : _round(moneyYields.reduce((a, b) => a + b)),
    'averageSevenDayYield': sevenDayYields.isEmpty
        ? null
        : _round(
            sevenDayYields.reduce((a, b) => a + b) / sevenDayYields.length,
          ),
    'dataClass': navs.length >= 2
        ? 'ordinary_fund_nav'
        : moneyYields.isNotEmpty || sevenDayYields.isNotEmpty
        ? 'money_fund_yield'
        : 'unknown_fund_rows',
  };
}

Map<String, dynamic> _fundRiskEvidence({
  required Map<String, dynamic> metrics,
  required Map<String, dynamic> categoryEvidence,
  required Map<String, dynamic> coverageEvidence,
}) {
  final drawdown = _numOf(metrics['maxDrawdownPct']);
  final averageDrawdown = _numOf(metrics['averageDrawdownPct']);
  final ulcerIndex = _numOf(metrics['ulcerIndex']);
  final drawdownDurationBars = _numOf(metrics['drawdownDurationBars']);
  final volatility = _numOf(metrics['volatilityPct']);
  final gainToPain = _numOf(metrics['gainToPainRatio']);
  final recoveryRatio = _numOf(metrics['recoveryRatio']);
  final omega = _numOf(metrics['omegaRatio']);
  final tailRatio = _numOf(metrics['tailRatio']);
  final positivePeriodRatio = _numOf(metrics['positivePeriodRatioPct']);
  final negativePeriodRatio = _numOf(metrics['negativePeriodRatioPct']);
  final returnSkewness = _numOf(metrics['returnSkewness']);
  final returnKurtosis = _numOf(metrics['returnKurtosis']);
  final valueAtRisk = _numOf(metrics['valueAtRiskPct']);
  final conditionalValueAtRisk = _numOf(metrics['conditionalValueAtRiskPct']);
  final averageSevenDayYield = _numOf(metrics['averageSevenDayYield']);
  final pricingBasis = '${categoryEvidence['pricingBasis'] ?? ''}';
  final coverageStatus = '${coverageEvidence['status'] ?? ''}';
  final warnings = <String>[
    if (coverageStatus != 'sufficient')
      'fund risk evidence is partial because fund data coverage is insufficient.',
    if (drawdown != null && drawdown >= 20)
      'fund historical drawdown is high for this period.',
    if (volatility != null && volatility >= 25)
      'fund historical volatility is high for this period.',
    if (pricingBasis == 'money_yield' && averageSevenDayYield == null)
      'money-fund risk evidence is missing average seven-day yield.',
    ...((categoryEvidence['warnings'] as List?) ?? const [])
        .map((item) => '$item')
        .where((item) => item.isNotEmpty),
    ...((coverageEvidence['warnings'] as List?) ?? const [])
        .map((item) => '$item')
        .where((item) => item.isNotEmpty),
  ];
  final riskLevel = coverageStatus != 'sufficient'
      ? 'unknown'
      : drawdown != null && drawdown >= 20
      ? 'high'
      : volatility != null && volatility >= 25
      ? 'high'
      : drawdown != null && drawdown >= 10
      ? 'medium'
      : pricingBasis == 'money_yield'
      ? 'income_stability'
      : 'low';
  return {
    'assetClass': 'fund',
    'status': coverageStatus == 'sufficient' ? 'evaluated' : 'partial',
    'riskLevel': riskLevel,
    'coverageStatus': coverageStatus,
    'pricingBasis': pricingBasis,
    'maxDrawdownPct': drawdown,
    'averageDrawdownPct': averageDrawdown,
    'ulcerIndex': ulcerIndex,
    'drawdownDurationBars': drawdownDurationBars,
    'volatilityPct': volatility,
    'gainToPainRatio': gainToPain,
    'recoveryRatio': recoveryRatio,
    'omegaRatio': omega,
    'tailRatio': tailRatio,
    'positivePeriodRatioPct': positivePeriodRatio,
    'negativePeriodRatioPct': negativePeriodRatio,
    'returnSkewness': returnSkewness,
    'returnKurtosis': returnKurtosis,
    'valueAtRiskPct': valueAtRisk,
    'conditionalValueAtRiskPct': conditionalValueAtRisk,
    'averageSevenDayYield': averageSevenDayYield,
    'moneyYieldTotal': metrics['moneyYieldTotal'],
    'warnings': warnings.toSet().toList(),
    'tradeBoundary':
        'Fund risk evidence is research-only. Explicit user confirmation is required before subscription, redemption, rebalance, or simulated trading.',
  };
}

Map<String, dynamic> _aggregateFundRiskEvidence(
  List<Map<String, dynamic>> fundResults,
  Map<String, dynamic> categoryEvidence,
  Map<String, dynamic> coverageEvidence,
) {
  final perFund = fundResults
      .map((row) => row['fundRiskEvidence'])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  final drawdowns = perFund
      .map((item) => _numOf(item['maxDrawdownPct']))
      .whereType<double>()
      .toList();
  final averageDrawdowns = perFund
      .map((item) => _numOf(item['averageDrawdownPct']))
      .whereType<double>()
      .toList();
  final volatilities = perFund
      .map((item) => _numOf(item['volatilityPct']))
      .whereType<double>()
      .toList();
  final ulcerIndexes = perFund
      .map((item) => _numOf(item['ulcerIndex']))
      .whereType<double>()
      .toList();
  final drawdownDurations = perFund
      .map((item) => _numOf(item['drawdownDurationBars']))
      .whereType<double>()
      .toList();
  final yields = perFund
      .map((item) => _numOf(item['averageSevenDayYield']))
      .whereType<double>()
      .toList();
  final gainToPains = perFund
      .map((item) => _numOf(item['gainToPainRatio']))
      .whereType<double>()
      .toList();
  final recoveryRatios = perFund
      .map((item) => _numOf(item['recoveryRatio']))
      .whereType<double>()
      .toList();
  final omegas = perFund
      .map((item) => _numOf(item['omegaRatio']))
      .whereType<double>()
      .toList();
  final tailRatios = perFund
      .map((item) => _numOf(item['tailRatio']))
      .whereType<double>()
      .toList();
  final positivePeriodRatios = perFund
      .map((item) => _numOf(item['positivePeriodRatioPct']))
      .whereType<double>()
      .toList();
  final negativePeriodRatios = perFund
      .map((item) => _numOf(item['negativePeriodRatioPct']))
      .whereType<double>()
      .toList();
  final returnSkewnesses = perFund
      .map((item) => _numOf(item['returnSkewness']))
      .whereType<double>()
      .toList();
  final returnKurtoses = perFund
      .map((item) => _numOf(item['returnKurtosis']))
      .whereType<double>()
      .toList();
  final valueAtRisks = perFund
      .map((item) => _numOf(item['valueAtRiskPct']))
      .whereType<double>()
      .toList();
  final conditionalValueAtRisks = perFund
      .map((item) => _numOf(item['conditionalValueAtRiskPct']))
      .whereType<double>()
      .toList();
  final warnings = <String>[
    ...perFund.expand(
      (item) =>
          ((item['warnings'] as List?) ?? const []).map((entry) => '$entry'),
    ),
  ].where((item) => item.isNotEmpty).toSet().toList();
  final coverageStatus = '${coverageEvidence['status'] ?? ''}';
  final worstDrawdown = drawdowns.isEmpty ? null : drawdowns.reduce(max);
  final maxVolatility = volatilities.isEmpty ? null : volatilities.reduce(max);
  final worstValueAtRisk = valueAtRisks.isEmpty
      ? null
      : valueAtRisks.reduce(max);
  final worstConditionalValueAtRisk = conditionalValueAtRisks.isEmpty
      ? null
      : conditionalValueAtRisks.reduce(max);
  return {
    'assetClass': 'fund',
    'status': coverageStatus == 'sufficient' ? 'evaluated' : 'partial',
    'fundCount': fundResults.length,
    'coverageStatus': coverageStatus,
    'pricingBasis': categoryEvidence['pricingBasis'],
    'worstDrawdownPct': worstDrawdown == null ? null : _round(worstDrawdown),
    'averageDrawdownPct': averageDrawdowns.isEmpty
        ? null
        : _round(
            averageDrawdowns.reduce((a, b) => a + b) / averageDrawdowns.length,
          ),
    'maxVolatilityPct': maxVolatility == null ? null : _round(maxVolatility),
    'averageUlcerIndex': ulcerIndexes.isEmpty
        ? null
        : _round(ulcerIndexes.reduce((a, b) => a + b) / ulcerIndexes.length),
    'maxDrawdownDurationBars': drawdownDurations.isEmpty
        ? null
        : drawdownDurations.reduce(max).toInt(),
    'averageDrawdownDurationBars': drawdownDurations.isEmpty
        ? null
        : _round(
            drawdownDurations.reduce((a, b) => a + b) /
                drawdownDurations.length,
          ),
    'averageSevenDayYield': yields.isEmpty
        ? null
        : _round(yields.reduce((a, b) => a + b) / yields.length),
    'averageGainToPainRatio': gainToPains.isEmpty
        ? null
        : _round(gainToPains.reduce((a, b) => a + b) / gainToPains.length),
    'averageRecoveryRatio': recoveryRatios.isEmpty
        ? null
        : _round(
            recoveryRatios.reduce((a, b) => a + b) / recoveryRatios.length,
          ),
    'averageOmegaRatio': omegas.isEmpty
        ? null
        : _round(omegas.reduce((a, b) => a + b) / omegas.length),
    'averageTailRatio': tailRatios.isEmpty
        ? null
        : _round(tailRatios.reduce((a, b) => a + b) / tailRatios.length),
    'averagePositivePeriodRatioPct': positivePeriodRatios.isEmpty
        ? null
        : _round(
            positivePeriodRatios.reduce((a, b) => a + b) /
                positivePeriodRatios.length,
          ),
    'averageNegativePeriodRatioPct': negativePeriodRatios.isEmpty
        ? null
        : _round(
            negativePeriodRatios.reduce((a, b) => a + b) /
                negativePeriodRatios.length,
          ),
    'averageReturnSkewness': returnSkewnesses.isEmpty
        ? null
        : _round(
            returnSkewnesses.reduce((a, b) => a + b) / returnSkewnesses.length,
          ),
    'averageReturnKurtosis': returnKurtoses.isEmpty
        ? null
        : _round(
            returnKurtoses.reduce((a, b) => a + b) / returnKurtoses.length,
          ),
    'worstValueAtRiskPct': worstValueAtRisk == null
        ? null
        : _round(worstValueAtRisk),
    'worstConditionalValueAtRiskPct': worstConditionalValueAtRisk == null
        ? null
        : _round(worstConditionalValueAtRisk),
    'averageValueAtRiskPct': valueAtRisks.isEmpty
        ? null
        : _round(valueAtRisks.reduce((a, b) => a + b) / valueAtRisks.length),
    'averageConditionalValueAtRiskPct': conditionalValueAtRisks.isEmpty
        ? null
        : _round(
            conditionalValueAtRisks.reduce((a, b) => a + b) /
                conditionalValueAtRisks.length,
          ),
    'warnings': warnings,
    'tradeBoundary':
        'Aggregate fund risk evidence is research-only. It cannot trigger subscription, redemption, rebalance, or simulated trading without explicit user confirmation.',
  };
}

Map<String, dynamic>? _fundComparisonEvidence(
  Map<String, dynamic> spec,
  List<Map<String, dynamic>> rows,
) {
  final groups = <String, List<Map<String, dynamic>>>{};
  final names = <String, String>{};
  for (final row in rows) {
    final code = '${row['code'] ?? ''}'.trim();
    if (code.isEmpty) continue;
    groups.putIfAbsent(code, () => <Map<String, dynamic>>[]).add(row);
    final name = '${row['name'] ?? ''}'.trim();
    if (name.isNotEmpty) names[code] = name;
  }
  if (groups.length < 2) return null;
  final rowsOut = <Map<String, dynamic>>[];
  for (final entry in groups.entries) {
    final sorted = entry.value
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final indicators = _computeFundIndicators(spec, sorted);
    rowsOut.add({
      'code': entry.key,
      if ((names[entry.key] ?? '').isNotEmpty) 'name': names[entry.key],
      'rows': sorted.length,
      'sourceDataTime': sorted.last['date'],
      'indicators': indicators,
      'score': _fundComparisonScore(spec, indicators),
    });
  }
  rowsOut.sort(
    (a, b) => ((b['score'] as num?) ?? 0).compareTo((a['score'] as num?) ?? 0),
  );
  for (var i = 0; i < rowsOut.length; i++) {
    rowsOut[i]['rank'] = i + 1;
  }
  return {
    'mode': 'fund_indicator_comparison',
    'status': 'compared',
    'fundCount': rowsOut.length,
    'rankingRule':
        'Higher rolling return / NAV trend and money yield are better; lower drawdown and volatility are better.',
    'rows': rowsOut,
    'tradeBoundary':
        'Fund comparison evidence is observation/research only. Do not subscribe, redeem, or create simulated trades without explicit user confirmation.',
  };
}

double _fundComparisonScore(
  Map<String, dynamic> spec,
  Map<String, dynamic> indicators,
) {
  var score = 0.0;
  final scoreDirections = _fundIndicatorScoreDirectionsById(spec);
  indicators.forEach((key, value) {
    if (value is! num) return;
    final direction = scoreDirections[key] ?? 1;
    if (direction == 0) return;
    score += value.toDouble() * direction;
  });
  return double.parse(score.toStringAsFixed(4));
}

Map<String, int> _fundIndicatorScoreDirectionsById(Map<String, dynamic> spec) {
  final directions = <String, int>{};
  for (final item
      in ((spec['indicators'] as List?) ?? const []).whereType<Map>()) {
    final indicator = Map<String, dynamic>.from(item);
    final id = '${indicator['id'] ?? indicator['type']}';
    if (id.isEmpty) continue;
    final type = '${indicator['type'] ?? ''}';
    final definition = fundStrategyIndicatorDefinition(type);
    if (definition != null) directions[id] = definition.scoreDirection;
  }
  return directions;
}

double _round(double value) => double.parse(value.toStringAsFixed(4));

Map<String, dynamic> _computeFundIndicators(
  Map<String, dynamic> spec,
  List<Map<String, dynamic>> rows,
) {
  final values = <String, dynamic>{};
  final navs = rows.map((row) => row['nav']).whereType<double>().toList();
  final moneyYields = rows
      .map((row) => row['moneyYield'])
      .whereType<double>()
      .toList();
  final sevenDayYields = rows
      .map((row) => row['sevenDayYield'])
      .whereType<double>()
      .toList();
  for (final item
      in ((spec['indicators'] as List?) ?? const []).whereType<Map>()) {
    final indicator = Map<String, dynamic>.from(item);
    final id = '${indicator['id'] ?? indicator['type']}';
    final type = '${indicator['type'] ?? ''}';
    final period = _periodOf(indicator['params'], fallback: 20);
    switch (type) {
      case 'nav_trend':
      case 'rolling_return':
        values[id] = _rollingReturn(navs, period);
        break;
      case 'fund_drawdown':
        values[id] = _drawdown(navs, period);
        break;
      case 'fund_rolling_max_drawdown':
        values[id] = _maxDrawdown(navs, period);
        break;
      case 'fund_average_drawdown':
        values[id] = _averageDrawdown(navs, period);
        break;
      case 'fund_ulcer_index':
        values[id] = _ulcerIndex(navs, period);
        break;
      case 'fund_drawdown_duration_bars':
        values[id] = _drawdownDurationBars(navs, period)?.toDouble();
        break;
      case 'fund_volatility':
        values[id] = _volatility(navs, period);
        break;
      case 'fund_downside_volatility':
        values[id] = _downsideVolatility(navs, period);
        break;
      case 'fund_sharpe':
        values[id] = _sharpe(navs, period);
        break;
      case 'fund_sortino':
        values[id] = _sortino(navs, period);
        break;
      case 'fund_calmar':
        values[id] = _calmar(navs, period);
        break;
      case 'fund_recovery_ratio':
        values[id] = _recoveryRatio(navs, period);
        break;
      case 'fund_gain_to_pain':
        values[id] = _gainToPain(navs, period);
        break;
      case 'fund_momentum_acceleration':
        values[id] = _momentumAcceleration(navs, indicator['params']);
        break;
      case 'fund_omega':
        values[id] = _omega(navs, indicator['params']);
        break;
      case 'fund_tail_ratio':
        values[id] = _tailRatio(navs, indicator['params']);
        break;
      case 'fund_positive_period_ratio':
        values[id] = _positivePeriodRatio(navs, indicator['params']);
        break;
      case 'fund_negative_period_ratio':
        values[id] = _negativePeriodRatio(navs, indicator['params']);
        break;
      case 'fund_max_consecutive_down_periods':
        values[id] = _maxConsecutivePeriods(
          navs,
          indicator['params'],
          positive: false,
        )?.toDouble();
        break;
      case 'fund_max_consecutive_up_periods':
        values[id] = _maxConsecutivePeriods(
          navs,
          indicator['params'],
          positive: true,
        )?.toDouble();
        break;
      case 'fund_return_skewness':
        values[id] = _returnSkewness(navs, indicator['params']);
        break;
      case 'fund_return_kurtosis':
        values[id] = _returnKurtosis(navs, indicator['params']);
        break;
      case 'fund_value_at_risk':
        values[id] = _valueAtRisk(navs, indicator['params']);
        break;
      case 'fund_conditional_value_at_risk':
        values[id] = _conditionalValueAtRisk(navs, indicator['params']);
        break;
      case 'money_yield':
        values[id] = moneyYields.isEmpty ? null : moneyYields.last;
        break;
      case 'seven_day_yield':
        values[id] = sevenDayYields.isEmpty ? null : sevenDayYields.last;
        break;
      case 'dca_interval':
        values[id] = period.toDouble();
        break;
    }
  }
  return values;
}

Map<String, dynamic> _evaluateRuleGroup(
  Object? raw,
  Map<String, dynamic> data,
) {
  if (raw is! Map) return {'satisfied': false, 'rules': const []};
  final mode = raw['all'] is List ? 'all' : 'any';
  final rules = (raw[mode] as List?) ?? const [];
  final evaluated = rules.whereType<Map>().map((item) {
    final rule = Map<String, dynamic>.from(item);
    final left = '${rule['left'] ?? ''}';
    final op = '${rule['op'] ?? ''}';
    final leftValue = _numOf(data[left]);
    final rightValue = _numOf(rule['right']);
    final passed = _compare(leftValue, op, rightValue);
    return {
      'left': left,
      'op': op,
      'right': rule['right'],
      'leftValue': leftValue,
      'satisfied': passed,
    };
  }).toList();
  final satisfied = mode == 'all'
      ? evaluated.isNotEmpty &&
            evaluated.every((item) => item['satisfied'] == true)
      : evaluated.any((item) => item['satisfied'] == true);
  return {'mode': mode, 'satisfied': satisfied, 'rules': evaluated};
}

Map<String, dynamic> _dcaObservation(
  Map<String, dynamic> spec,
  Map<String, dynamic> indicators,
  Map<String, dynamic> signal,
) {
  final interval = _dcaIntervalValue(spec, indicators);
  return {
    'mode': 'fund_observation_only',
    'strategyId': spec['id'],
    'cadenceDays': interval is num ? interval.toInt() : null,
    'suggestion': signal['suggestion'],
    'triggerState': {
      'entrySatisfied': signal['entrySatisfied'],
      'exitSatisfied': signal['exitSatisfied'],
    },
    'tradeBoundary':
        'Observation only. Do not subscribe, redeem, or create simulated trades without explicit user confirmation.',
  };
}

num? _dcaIntervalValue(
  Map<String, dynamic> spec,
  Map<String, dynamic> indicators,
) {
  for (final item
      in ((spec['indicators'] as List?) ?? const []).whereType<Map>()) {
    final indicator = Map<String, dynamic>.from(item);
    final type = '${indicator['type'] ?? ''}';
    final definition = fundStrategyIndicatorDefinition(type);
    if (definition?.category != 'fund_observation') continue;
    final id = '${indicator['id'] ?? indicator['type']}';
    final value = indicators[id];
    if (value is num) return value;
  }
  return null;
}

Map<String, dynamic> _monitorDraft(
  Map<String, dynamic> spec,
  Map<String, dynamic> entry,
  Map<String, dynamic> exit,
  Map<String, dynamic> signal,
) {
  return {
    'mode': 'fund_rule_monitor',
    'strategyId': spec['id'],
    'assetClass': 'fund',
    'status': signal['suggestion'],
    'entryRules': entry['rules'] ?? const [],
    'exitRules': exit['rules'] ?? const [],
    'nextAction': signal['suggestion'] == 'review_or_pause'
        ? 'review fund risk or pause DCA after user confirmation'
        : signal['suggestion'] == 'observe_or_prepare'
        ? 'prepare DCA observation; confirmation required before any trade'
        : 'wait for fund-specific rules to become satisfied',
    'unsupportedExecution':
        'This monitor draft is not a stock backtest, watchlist mutation, subscription order, or redemption order.',
  };
}

bool _compare(double? left, String op, double? right) {
  if (left == null || right == null) return false;
  return switch (op) {
    '>' => left > right,
    '>=' => left >= right,
    '<' => left < right,
    '<=' => left <= right,
    _ => false,
  };
}

double? _rollingReturn(List<double> values, int period) {
  if (values.length <= period || values[values.length - period - 1] == 0) {
    return null;
  }
  final previous = values[values.length - period - 1];
  return (values.last - previous) / previous * 100;
}

double? _momentumAcceleration(List<double> values, Object? params) {
  final period = _periodOf(params, fallback: 20);
  final lagPeriod = _paramInt(params, 'lagPeriod', fallback: period);
  if (values.length <= period + lagPeriod) return null;
  final currentBase = values[values.length - period - 1];
  final previousIndex = values.length - lagPeriod - 1;
  final previousBaseIndex = previousIndex - period;
  if (currentBase == 0 || previousBaseIndex < 0) return null;
  final previousClose = values[previousIndex];
  final previousBase = values[previousBaseIndex];
  if (previousBase == 0) return null;
  final currentReturn = (values.last - currentBase) / currentBase * 100;
  final previousReturn = (previousClose - previousBase) / previousBase * 100;
  return currentReturn - previousReturn;
}

double? _drawdown(List<double> values, int period) {
  if (values.isEmpty) return null;
  final window = values.length < period
      ? values
      : values.sublist(values.length - period);
  final high = window.reduce((a, b) => a > b ? a : b);
  if (high == 0) return null;
  return (high - values.last) / high * 100;
}

double? _ulcerIndex(List<double> values, int period) {
  if (values.isEmpty) return null;
  final window = values.length < period
      ? values
      : values.sublist(values.length - period);
  var high = window.first;
  var squaredDrawdownSum = 0.0;
  for (final value in window) {
    high = max(high, value);
    if (high == 0) return null;
    final drawdownPct = min(0.0, (value - high) / high * 100);
    squaredDrawdownSum += drawdownPct * drawdownPct;
  }
  return sqrt(squaredDrawdownSum / window.length);
}

int? _drawdownDurationBars(List<double> values, int period) {
  if (values.isEmpty || period <= 0) return null;
  final window = values.length < period
      ? values
      : values.sublist(values.length - period);
  var high = window.first;
  var duration = 0;
  for (final value in window) {
    if (value >= high) {
      high = value;
      duration = 0;
    } else {
      duration += 1;
    }
  }
  return duration;
}

double? _averageDrawdown(List<double> values, int period) {
  if (values.isEmpty || period <= 0) return null;
  final window = values.length < period
      ? values
      : values.sublist(values.length - period);
  var high = window.first;
  final drawdowns = <double>[];
  for (final value in window) {
    high = max(high, value);
    if (high == 0) continue;
    final drawdownPct = (high - value) / high * 100;
    if (drawdownPct > 0) drawdowns.add(drawdownPct);
  }
  if (drawdowns.isEmpty) return 0;
  return drawdowns.reduce((a, b) => a + b) / drawdowns.length;
}

double? _volatility(List<double> values, int period) {
  if (values.length <= period) return null;
  final window = values.sublist(values.length - period - 1);
  final returns = <double>[];
  for (var index = 1; index < window.length; index++) {
    if (window[index - 1] == 0) return null;
    returns.add((window[index] - window[index - 1]) / window[index - 1]);
  }
  if (returns.isEmpty) return null;
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final variance =
      returns
          .map((value) => (value - mean) * (value - mean))
          .reduce((a, b) => a + b) /
      returns.length;
  return sqrt(variance) * sqrt(252) * 100;
}

double? _sharpe(List<double> values, int period) {
  final returns = _windowReturns(values, period);
  if (returns.isEmpty) return null;
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final variance =
      returns
          .map((value) => (value - mean) * (value - mean))
          .reduce((a, b) => a + b) /
      returns.length;
  final stdev = sqrt(variance);
  if (stdev == 0) return null;
  return mean / stdev * sqrt(252);
}

double? _sortino(List<double> values, int period) {
  final returns = _windowReturns(values, period);
  if (returns.isEmpty) return null;
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final downsideDeviation = _downsideDeviation(returns);
  if (downsideDeviation == null) return null;
  if (downsideDeviation == 0) return null;
  return mean / downsideDeviation * sqrt(252);
}

double? _downsideVolatility(List<double> values, int period) {
  final returns = _windowReturns(values, period);
  final downsideDeviation = _downsideDeviation(returns);
  return downsideDeviation == null ? null : downsideDeviation * sqrt(252) * 100;
}

double? _downsideDeviation(List<double> returns) {
  final downside = returns.where((value) => value < 0).toList();
  if (downside.isEmpty) return null;
  return sqrt(
    downside.map((value) => value * value).reduce((a, b) => a + b) /
        downside.length,
  );
}

double? _calmar(List<double> values, int period) {
  final periodReturn = _rollingReturn(values, period);
  final maxDrawdown = _maxDrawdown(values, period);
  if (periodReturn == null || maxDrawdown == null || maxDrawdown == 0) {
    return null;
  }
  return periodReturn / maxDrawdown.abs();
}

double? _recoveryRatio(List<double> values, int period) {
  final periodReturn = _rollingReturn(values, period);
  final averageDrawdown = _averageDrawdown(values, period);
  if (periodReturn == null || averageDrawdown == null || averageDrawdown == 0) {
    return null;
  }
  return periodReturn / averageDrawdown.abs();
}

double? _gainToPain(List<double> values, int period) {
  final returns = _windowReturns(values, period);
  if (returns.isEmpty) return null;
  final gains = returns
      .where((value) => value > 0)
      .fold(0.0, (sum, value) => sum + value);
  final pains = returns
      .where((value) => value < 0)
      .fold(0.0, (sum, value) => sum + value.abs());
  if (pains == 0) return null;
  return gains / pains;
}

double? _omega(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final threshold = _numOf(params['thresholdReturn']) ?? 0;
  final returns = _windowReturns(values, period);
  if (returns.isEmpty) return null;
  var gains = 0.0;
  var shortfalls = 0.0;
  for (final value in returns) {
    final excess = value - threshold;
    if (excess >= 0) {
      gains += excess;
    } else {
      shortfalls += excess.abs();
    }
  }
  if (shortfalls == 0) return null;
  return gains / shortfalls;
}

double? _tailRatio(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final upperPercentile = _numOf(params['upperPercentile']) ?? 95;
  final lowerPercentile = _numOf(params['lowerPercentile']) ?? 5;
  final returns = _windowReturns(values, period);
  if (returns.length < 5) return null;
  final sorted = [...returns]..sort();
  final upper = _percentile(sorted, upperPercentile);
  final lower = _percentile(sorted, lowerPercentile);
  if (upper == null || lower == null || lower == 0) return null;
  return upper / lower.abs();
}

double? _positivePeriodRatio(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final returns = _windowReturns(values, period);
  if (returns.isEmpty) return null;
  final positives = returns.where((value) => value > 0).length;
  return positives / returns.length * 100;
}

double? _negativePeriodRatio(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final returns = _windowReturns(values, period);
  if (returns.isEmpty) return null;
  final negatives = returns.where((value) => value < 0).length;
  return negatives / returns.length * 100;
}

int? _maxConsecutivePeriods(
  List<double> values,
  Object? rawParams, {
  required bool positive,
}) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final returns = _windowReturns(values, period);
  if (returns.isEmpty) return null;
  var currentStreak = 0;
  var maxStreak = 0;
  for (final item in returns) {
    final inStreak = positive ? item > 0 : item < 0;
    if (inStreak) {
      currentStreak += 1;
      maxStreak = max(maxStreak, currentStreak);
    } else {
      currentStreak = 0;
    }
  }
  return maxStreak;
}

double? _returnSkewness(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final returns = _windowReturns(values, period);
  if (returns.length < 3) return null;
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final variance =
      returns.fold(0.0, (sum, value) => sum + pow(value - mean, 2)) /
      returns.length;
  if (variance == 0) return 0.0;
  final stdev = sqrt(variance);
  final skew = returns.fold(
    0.0,
    (sum, value) => sum + pow((value - mean) / stdev, 3),
  );
  return skew / returns.length;
}

double? _returnKurtosis(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final returns = _windowReturns(values, period);
  if (returns.length < 4) return null;
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final variance =
      returns.fold(0.0, (sum, value) => sum + pow(value - mean, 2)) /
      returns.length;
  if (variance == 0) return 0.0;
  final stdev = sqrt(variance);
  final kurtosis = returns.fold(
    0.0,
    (sum, value) => sum + pow((value - mean) / stdev, 4),
  );
  return kurtosis / returns.length - 3.0;
}

double? _valueAtRisk(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final confidence = (_numOf(params['confidence']) ?? 95)
      .clamp(50, 99.9)
      .toDouble();
  final returns = _windowReturns(values, period);
  if (returns.length < 5) return null;
  final sorted = [...returns]..sort();
  final cutoff = _percentile(sorted, 100 - confidence);
  if (cutoff == null) return null;
  return max(0.0, -cutoff * 100);
}

double? _conditionalValueAtRisk(List<double> values, Object? rawParams) {
  final params = rawParams is Map ? rawParams : const {};
  final period = _periodOf(params, fallback: 60);
  final confidence = (_numOf(params['confidence']) ?? 95)
      .clamp(50, 99.9)
      .toDouble();
  final returns = _windowReturns(values, period);
  if (returns.length < 5) return null;
  final sorted = [...returns]..sort();
  final cutoff = _percentile(sorted, 100 - confidence);
  if (cutoff == null) return null;
  final losses = returns.where((item) => item <= cutoff).toList();
  if (losses.isEmpty) return max(0.0, -cutoff * 100);
  final meanTail = losses.reduce((a, b) => a + b) / losses.length;
  return max(0.0, -meanTail * 100);
}

List<double> _windowReturns(List<double> values, int period) {
  if (values.length <= period) return const [];
  final window = values.sublist(values.length - period - 1);
  final returns = <double>[];
  for (var index = 1; index < window.length; index++) {
    if (window[index - 1] == 0) return const [];
    returns.add((window[index] - window[index - 1]) / window[index - 1]);
  }
  return returns;
}

double? _percentile(List<double> sortedValues, double percentile) {
  if (sortedValues.isEmpty) return null;
  final bounded = percentile.clamp(0, 100);
  final position = (bounded / 100) * (sortedValues.length - 1);
  final lower = position.floor();
  final upper = position.ceil();
  if (lower == upper) return sortedValues[lower];
  final weight = position - lower;
  return (sortedValues[lower] * (1 - weight) + sortedValues[upper] * weight)
      .toDouble();
}

double? _maxDrawdown(List<double> values, int period) {
  if (values.isEmpty) return null;
  final window = values.length < period
      ? values
      : values.sublist(values.length - period);
  var peak = window.first;
  var worst = 0.0;
  for (final value in window) {
    if (value > peak) peak = value;
    if (peak == 0) continue;
    final drawdown = (peak - value) / peak * 100;
    if (drawdown > worst) worst = drawdown;
  }
  return worst;
}

int _periodOf(Object? raw, {required int fallback}) {
  if (raw is Map && raw['period'] is num) return (raw['period'] as num).toInt();
  return fallback;
}

int _paramInt(Object? raw, String key, {required int fallback}) {
  if (raw is Map && raw[key] is num) return (raw[key] as num).toInt();
  return fallback;
}

double? _numOf(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw.replaceAll('%', ''));
  return null;
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
