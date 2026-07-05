import 'dart:math';

import 'custom_strategy_engine.dart';
import 'backtest_core.dart';

class StrategyPortfolioCandidate {
  final String symbol;
  final List<Candle> candles;
  final Map<String, dynamic> dataEvidence;

  const StrategyPortfolioCandidate({
    required this.symbol,
    required this.candles,
    required this.dataEvidence,
  });
}

class _CorrelationSelection {
  final List<Map<String, dynamic>> selected;
  final List<Map<String, dynamic>> skipped;

  const _CorrelationSelection({required this.selected, required this.skipped});
}

Map<String, dynamic> rankCustomStrategyPortfolio({
  required CustomStrategyEngine engine,
  required Object? strategySpec,
  required List<StrategyPortfolioCandidate> candidates,
  int topN = 3,
  String rankingMetric = 'score',
  String rebalanceInterval = 'single_period_draft',
  double? maxPositionWeight,
  double? minScore,
  double? maxPairwiseCorrelation,
}) {
  if (candidates.length < 2) {
    throw ArgumentError(
      'custom_strategy_rank requires at least two symbols for comparison',
    );
  }

  final validation = engine.validate(strategySpec);
  if (validation['status'] != 'validated') {
    throw ArgumentError(
      'custom strategy validation failed: ${(validation['errors'] as List).join('; ')}',
    );
  }
  final spec = Map<String, dynamic>.from(validation['spec'] as Map);
  if ('${spec['assetType'] ?? spec['market'] ?? ''}'.toLowerCase() == 'fund') {
    throw ArgumentError(
      'custom_strategy_rank currently supports stock StrategySpec only; use custom_strategy_observe for fund observation evidence',
    );
  }

  final rows = <Map<String, dynamic>>[];
  for (final candidate in candidates.take(20)) {
    try {
      final result = engine.backtest(
        spec,
        candidate.candles,
        symbol: candidate.symbol,
      );
      final metrics = Map<String, dynamic>.from(result['metrics'] as Map);
      final relativeStrength = _relativeStrength(candidate.candles);
      final dataCoverage = _candidateDataCoverage(
        spec,
        candidate.dataEvidence,
        candidate.symbol,
      );
      rows.add({
        'symbol': candidate.symbol,
        'status': 'ranked',
        'score': _score(metrics, rankingMetric, relativeStrength),
        'rankingMetric': rankingMetric,
        'relativeStrength': relativeStrength,
        'returnSeries': _returnSeries(candidate.candles),
        'metrics': metrics,
        'signals': result['signals'],
        'benchmarkEvidence': result['benchmarkEvidence'],
        'riskEvidence': result['riskEvidence'],
        'dataCoverage': dataCoverage,
        'assumptions': result['assumptions'],
        'dataEvidence': candidate.dataEvidence,
      });
    } catch (error) {
      rows.add({
        'symbol': candidate.symbol,
        'status': 'failed',
        'error': '$error',
        'dataEvidence': candidate.dataEvidence,
      });
    }
  }

  rows.sort(
    (a, b) => ((b['score'] as num?) ?? double.negativeInfinity).compareTo(
      (a['score'] as num?) ?? double.negativeInfinity,
    ),
  );
  var rank = 1;
  final rankedRows = rows.where((row) => row['status'] == 'ranked').toList();
  final excludedRows = rows.where((row) => row['status'] != 'ranked').toList();
  for (final row in rankedRows) {
    row['rank'] = rank++;
    final relativeStrength = _mapOf(row['relativeStrength']);
    if (relativeStrength != null) {
      relativeStrength['rank'] = row['rank'];
      relativeStrength['percentile'] = _relativeStrengthPercentile(
        row['rank'] as int,
        rankedRows.length,
      );
      row['relativeStrength'] = relativeStrength;
    }
  }
  final scoreThreshold = _scoreThreshold(minScore);
  final eligibleRows = rankedRows
      .where((row) => _passesScoreThreshold(row, scoreThreshold))
      .toList();
  final correlationCap = _correlationCap(maxPairwiseCorrelation);
  final correlationSelection = _selectWithCorrelationCap(
    eligibleRows,
    topN.clamp(1, 10),
    correlationCap,
  );
  final selected = correlationSelection.selected;
  final positionCap = _positionCap(maxPositionWeight);
  final weight = selected.isEmpty
      ? 0.0
      : _round(min(1 / selected.length, positionCap));
  final selectionEvidence = _selectionEvidence(
    rankedRows: rankedRows,
    selected: selected,
    topN: topN.clamp(1, 10),
    rankingMetric: rankingMetric,
    weight: weight,
    positionCap: positionCap,
    minScore: scoreThreshold,
    maxPairwiseCorrelation: correlationCap,
    correlationSkipped: correlationSelection.skipped,
  );
  final portfolioRiskEvidence = _portfolioRiskEvidence(selected, weight);
  final portfolioReturnQualityEvidence = _portfolioReturnQualityEvidence(
    selected,
    weight,
  );
  final concentrationEvidence = _portfolioConcentrationEvidence(
    selected,
    weight,
    positionCap,
  );
  final portfolioMetrics = _portfolioMetrics(selected, portfolioRiskEvidence);
  final correlationEvidence = _correlationEvidence(selected);
  final portfolioStabilityEvidence = _portfolioStabilityEvidence(
    selected,
    weight,
  );
  final interval = _rebalanceInterval(rebalanceInterval);
  final costModel = _portfolioCostModel(spec);
  final portfolioRebalanceSimulation = _portfolioRebalanceSimulation(
    selected: selected,
    weight: weight,
    interval: interval,
    costModel: costModel,
  );
  final portfolioBacktestEvidence = _portfolioBacktestEvidence(
    selected: selected,
    weight: weight,
    interval: interval,
    positionCap: positionCap,
    costModel: costModel,
    portfolioRiskEvidence: portfolioRiskEvidence,
    portfolioReturnQualityEvidence: portfolioReturnQualityEvidence,
    correlationEvidence: correlationEvidence,
  );
  final portfolioScoringEvidence = _portfolioScoringEvidence(
    spec: spec,
    selected: selected,
    weight: weight,
    positionCap: positionCap,
    portfolioRiskEvidence: portfolioRiskEvidence,
    portfolioReturnQualityEvidence: portfolioReturnQualityEvidence,
    concentrationEvidence: concentrationEvidence,
    portfolioBacktestEvidence: portfolioBacktestEvidence,
  );
  final portfolioDrawdownBudgetEvidence = _portfolioDrawdownBudgetEvidence(
    spec: spec,
    selected: selected,
    portfolioRiskEvidence: portfolioRiskEvidence,
  );
  final portfolioValidation = _portfolioValidationEvidence(
    requestedCount: candidates.length,
    evaluatedCount: rows.length,
    rankedCount: rankedRows.length,
    failedCount: excludedRows.length,
    selected: selected,
    topN: topN.clamp(1, 10),
    rankingMetric: rankingMetric,
    minScore: scoreThreshold,
    eligibleCount: eligibleRows.length,
    correlationEligibleCount:
        eligibleRows.length - correlationSelection.skipped.length,
    interval: interval,
    positionCap: positionCap,
    maxPairwiseCorrelation: correlationCap,
    weight: weight,
    portfolioRiskEvidence: portfolioRiskEvidence,
    concentrationEvidence: concentrationEvidence,
    correlationEvidence: correlationEvidence,
    portfolioBacktestEvidence: portfolioBacktestEvidence,
    portfolioDrawdownBudgetEvidence: portfolioDrawdownBudgetEvidence,
  );
  final candidateFailureEvidence = _candidateFailureEvidence(excludedRows);
  final positionContributionEvidence = _positionContributionEvidence(
    selected,
    weight,
  );

  return {
    'action': 'custom_strategy_rank',
    'status': selected.isEmpty ? 'no_ranked_symbols' : 'ranked',
    'strategyId': validation['strategyId'],
    'version': validation['version'],
    'validationSummary': validation['validationSummary'],
    'validationIssues': validation['validationIssues'] ?? const [],
    'unsupportedDetails': validation['unsupportedDetails'] ?? const [],
    'dataRequirements': validation['dataRequirements'],
    'rankingMetric': rankingMetric,
    'candidateCount': candidates.length,
    'rankedCount': rankedRows.length,
    'failedCount': excludedRows.length,
    'ranked': rankedRows,
    'excluded': excludedRows,
    'candidateFailureEvidence': candidateFailureEvidence,
    'allCandidates': rows,
    'portfolioEvidence': {
      'mode': 'equal_weight_selected_metrics',
      'selectedCount': selected.length,
      'aggregateMetrics': portfolioMetrics,
      'correlationEvidence': correlationEvidence,
      'portfolioRiskEvidence': portfolioRiskEvidence,
      'portfolioReturnQualityEvidence': portfolioReturnQualityEvidence,
      'concentrationEvidence': concentrationEvidence,
      'portfolioStabilityEvidence': portfolioStabilityEvidence,
      'portfolioRebalanceSimulation': portfolioRebalanceSimulation,
      'portfolioBacktestEvidence': portfolioBacktestEvidence,
      'portfolioScoringEvidence': portfolioScoringEvidence,
      'portfolioDrawdownBudgetEvidence': portfolioDrawdownBudgetEvidence,
      'portfolioValidation': portfolioValidation,
      'candidateFailureEvidence': candidateFailureEvidence,
      'selectionEvidence': selectionEvidence,
      'positionContributionEvidence': positionContributionEvidence,
      'assumptions': {
        'weighting': 'equal_weight',
        'rebalanceInterval': interval,
        'maxPositionWeight': positionCap,
        'minScore': scoreThreshold,
        'maxPairwiseCorrelation': correlationCap,
        'maxDrawdownPct': portfolioDrawdownBudgetEvidence['allowedDrawdownPct'],
        'rankingMetric': rankingMetric,
        'correlationModel': correlationEvidence['mode'],
        'costModel': costModel,
        'execution': 'not_executed',
      },
      'riskNotes': [
        'Portfolio evidence is derived from selected single-symbol backtests; it is not an execution ledger.',
        'Transaction cost is estimated from StrategySpec cost assumptions; tax, liquidity impact, order fill, and live order state are not modelled in this draft.',
      ],
    },
    'rebalanceDraft': {
      'mode': 'equal_weight_top_n',
      'topN': selected.length,
      'rebalanceInterval': interval,
      'maxPositionWeight': positionCap,
      'minScore': scoreThreshold,
      'maxPairwiseCorrelation': correlationCap,
      'aggregateMetrics': portfolioMetrics,
      'correlationEvidence': correlationEvidence,
      'portfolioRiskEvidence': portfolioRiskEvidence,
      'portfolioReturnQualityEvidence': portfolioReturnQualityEvidence,
      'concentrationEvidence': concentrationEvidence,
      'portfolioStabilityEvidence': portfolioStabilityEvidence,
      'portfolioRebalanceSimulation': portfolioRebalanceSimulation,
      'portfolioBacktestEvidence': portfolioBacktestEvidence,
      'portfolioScoringEvidence': portfolioScoringEvidence,
      'portfolioDrawdownBudgetEvidence': portfolioDrawdownBudgetEvidence,
      'portfolioValidation': portfolioValidation,
      'candidateFailureEvidence': candidateFailureEvidence,
      'selectionEvidence': selectionEvidence,
      'positionContributionEvidence': positionContributionEvidence,
      'positions': [
        for (final row in selected)
          {
            'symbol': row['symbol'],
            'targetWeight': weight,
            'weightCapped':
                selected.isNotEmpty && positionCap < 1 / selected.length,
            'basis': '${row['rankingMetric']}=${row['score']}',
            'selectionEvidence': row['selectionEvidence'],
            'weightEvidence': row['weightEvidence'],
            'contributionEvidence': _positionContribution(row, weight),
          },
      ],
      'tradeBoundary':
          'Ranking evidence only. Do not place simulated or real orders without explicit confirmation.',
    },
    'portfolioValidation': portfolioValidation,
    'portfolioBacktestEvidence': portfolioBacktestEvidence,
    'portfolioScoringEvidence': portfolioScoringEvidence,
    'portfolioDrawdownBudgetEvidence': portfolioDrawdownBudgetEvidence,
    'portfolioReturnQualityEvidence': portfolioReturnQualityEvidence,
    'concentrationEvidence': concentrationEvidence,
    'portfolioStabilityEvidence': portfolioStabilityEvidence,
    'portfolioRebalanceSimulation': portfolioRebalanceSimulation,
    'selectionEvidence': selectionEvidence,
    'validation': validation,
    'workflowAdvice':
        'Use this as portfolio/ranking evidence. Save or monitor only after the user accepts the StrategySpec; trade preparation still requires separate sizing and confirmation.',
  };
}

Map<String, dynamic> _selectionEvidence({
  required List<Map<String, dynamic>> rankedRows,
  required List<Map<String, dynamic>> selected,
  required int topN,
  required String rankingMetric,
  required double weight,
  required double positionCap,
  required double? minScore,
  required double? maxPairwiseCorrelation,
  required List<Map<String, dynamic>> correlationSkipped,
}) {
  final selectedSymbols = selected.map((row) => '${row['symbol']}').toSet();
  final skippedBySymbol = {
    for (final row in correlationSkipped) '${row['symbol']}': row,
  };
  for (final row in rankedRows) {
    final selectedForDraft = selectedSymbols.contains('${row['symbol']}');
    final belowThreshold = minScore != null && _num(row['score']) < minScore;
    final correlationSkip = skippedBySymbol['${row['symbol']}'];
    row['selectionEvidence'] = {
      'mode': 'portfolio_rank_selection_v1',
      'rankingMetric': rankingMetric,
      'rank': row['rank'],
      'score': row['score'],
      'minScore': minScore,
      'maxPairwiseCorrelation': maxPairwiseCorrelation,
      'topN': topN,
      'selectedForDraft': selectedForDraft,
      'selectionRule':
          'rank <= topN after successful StrategySpec backtest, score threshold, and optional pairwise correlation cap',
      'exclusionReason': selectedForDraft
          ? null
          : belowThreshold
          ? 'score below minScore threshold'
          : correlationSkip != null
          ? 'pairwise correlation above maxPairwiseCorrelation'
          : 'rank below selected topN',
      'correlationConstraintEvidence': correlationSkip == null
          ? null
          : {
              'mode': 'portfolio_correlation_constraint_v1',
              'maxPairwiseCorrelation': maxPairwiseCorrelation,
              'maxObservedCorrelation':
                  correlationSkip['maxObservedCorrelation'],
              'matchedSymbol': correlationSkip['matchedSymbol'],
            },
    };
    row['weightEvidence'] = selectedForDraft
        ? _positionWeightEvidence(row, weight)
        : {
            'mode': 'portfolio_equal_weight_v1',
            'targetWeight': 0.0,
            'selectedForDraft': false,
            'reason': 'not selected for the rebalance draft',
          };
  }
  return {
    'mode': 'portfolio_rank_selection_v1',
    'rankingMetric': rankingMetric,
    'topN': topN,
    'minScore': minScore,
    'maxPairwiseCorrelation': maxPairwiseCorrelation,
    'selectedSymbols': selected.map((row) => row['symbol']).toList(),
    'selectedCount': selected.length,
    'eligibleCount': rankedRows
        .where((row) => _passesScoreThreshold(row, minScore))
        .length,
    'correlationEligibleCount':
        rankedRows.where((row) => _passesScoreThreshold(row, minScore)).length -
        correlationSkipped.length,
    'correlationSkipped': correlationSkipped,
    'weighting': 'equal_weight_with_position_cap',
    'targetWeight': weight,
    'maxPositionWeight': positionCap,
    'tradeBoundary':
        'Selection evidence is ranking/readback evidence only; it does not authorize simulated or real orders.',
  };
}

Map<String, dynamic> _positionContributionEvidence(
  List<Map<String, dynamic>> selected,
  double weight,
) {
  return {
    'mode': 'position_contribution_evidence_v1',
    'weighting': 'equal_weight',
    'targetWeight': weight,
    'selectedCount': selected.length,
    'positions': [
      for (final row in selected) _positionContribution(row, weight),
    ],
    'tradeBoundary':
        'Position contribution evidence explains ranking and weight basis only; it does not authorize order placement.',
  };
}

Map<String, dynamic> _positionContribution(
  Map<String, dynamic> row,
  double weight,
) {
  final metrics = _mapOf(row['metrics']) ?? const <String, dynamic>{};
  final relativeStrength =
      _mapOf(row['relativeStrength']) ?? const <String, dynamic>{};
  final dataCoverage = _mapOf(row['dataCoverage']) ?? const <String, dynamic>{};
  return {
    'symbol': row['symbol'],
    'rank': row['rank'],
    'targetWeight': weight,
    'rankingMetric': row['rankingMetric'],
    'score': row['score'],
    'selectionEvidence': row['selectionEvidence'],
    'weightEvidence':
        row['weightEvidence'] ?? _positionWeightEvidence(row, weight),
    'weightedReturnContributionPct': _round(
      _num(metrics['totalReturnPct']) * weight,
    ),
    'weightedDrawdownContributionPct': _round(
      _num(metrics['maxDrawdownPct']) * weight,
    ),
    'relativeStrengthPercentile': relativeStrength['percentile'],
    'relativeStrengthReturnPct': relativeStrength['returnPct'],
    'tradeCount': metrics['tradeCount'],
    'sharpeRatio': metrics['sharpeRatio'],
    'dataCoverage': {
      'source': dataCoverage['source'],
      'cacheStatus': dataCoverage['cacheStatus'],
      'rows': dataCoverage['rows'],
      'requiredBars': dataCoverage['requiredBars'],
      'sufficient': dataCoverage['sufficient'],
      'actualStartDate': dataCoverage['actualStartDate'],
      'actualEndDate': dataCoverage['actualEndDate'],
    },
  };
}

Map<String, dynamic> _positionWeightEvidence(
  Map<String, dynamic> row,
  double weight,
) {
  return {
    'mode': 'portfolio_equal_weight_v1',
    'rankingMetric': row['rankingMetric'],
    'score': row['score'],
    'rank': row['rank'],
    'targetWeight': weight,
    'reason': 'equal weight among selected ranked symbols after position cap',
  };
}

Map<String, dynamic> _candidateDataCoverage(
  Map<String, dynamic> spec,
  Map<String, dynamic> evidence,
  String symbol,
) {
  final dataRequirements = spec['dataRequirements'] is Map
      ? Map<String, dynamic>.from(spec['dataRequirements'] as Map)
      : const <String, dynamic>{};
  final rows = evidence['rows'] is num ? (evidence['rows'] as num).toInt() : 0;
  final requiredBars = dataRequirements['minBars'] is num
      ? (dataRequirements['minBars'] as num).toInt()
      : 120;
  return {
    'mode': 'strategy_backtest_kline_coverage',
    'symbol': symbol,
    'source': evidence['source'],
    'cacheStatus': evidence['cacheStatus'],
    'rows': rows,
    'requiredBars': requiredBars,
    'sufficient': rows >= requiredBars,
    'actualStartDate': evidence['startDate'],
    'actualEndDate': evidence['endDate'],
    'dataRequirements': dataRequirements,
  };
}

Map<String, dynamic> _portfolioValidationEvidence({
  required int requestedCount,
  required int evaluatedCount,
  required int rankedCount,
  required int failedCount,
  required List<Map<String, dynamic>> selected,
  required int topN,
  required String rankingMetric,
  required double? minScore,
  required int eligibleCount,
  required int correlationEligibleCount,
  required String interval,
  required double positionCap,
  required double? maxPairwiseCorrelation,
  required double weight,
  required Map<String, dynamic> portfolioRiskEvidence,
  required Map<String, dynamic> concentrationEvidence,
  required Map<String, dynamic> correlationEvidence,
  required Map<String, dynamic> portfolioBacktestEvidence,
  required Map<String, dynamic> portfolioDrawdownBudgetEvidence,
}) {
  final warnings = <String>[];
  if (selected.isEmpty) {
    warnings.add(
      'No ranked symbol was selected; portfolio evidence is not reusable.',
    );
  }
  if (rankedCount < 2) {
    warnings.add('Fewer than two symbols produced ranked evidence.');
  }
  if (minScore != null && selected.length < topN) {
    warnings.add(
      'Score threshold excluded ${rankedCount - eligibleCount} ranked candidate(s) from the rebalance draft.',
    );
  }
  if (maxPairwiseCorrelation != null &&
      correlationEligibleCount < eligibleCount) {
    warnings.add(
      'Pairwise correlation cap excluded ${eligibleCount - correlationEligibleCount} eligible candidate(s) from the rebalance draft.',
    );
  }
  if (failedCount > 0) {
    warnings.add(
      '$failedCount candidate(s) failed validation/backtest and were excluded.',
    );
  }
  if (_num(portfolioRiskEvidence['residualCashWeight']) > 0) {
    warnings.add(
      'Position cap leaves residual cash in the equal-weight draft.',
    );
  }
  if (concentrationEvidence['status'] == 'concentrated') {
    warnings.add(
      'Selected draft is concentrated; review effective position count and max position weight before trade preparation.',
    );
  }
  if (correlationEvidence['mode'] != 'close_return_pairwise_correlation') {
    warnings.add('Pairwise correlation evidence is incomplete.');
  }
  if (portfolioDrawdownBudgetEvidence['status'] == 'violated') {
    warnings.add(
      'Portfolio drawdown budget is violated; review StrategySpec.risk.maxDrawdownPct before trade preparation.',
    );
  }
  final bars = selected
      .map((row) => _num(_mapOf(row['relativeStrength'])?['lookbackBars']))
      .where((value) => value > 0)
      .toList(growable: false);
  return {
    'mode': 'portfolio_rank_validation_v1',
    'status': selected.isEmpty
        ? 'rejected'
        : warnings.isEmpty
        ? 'accepted'
        : 'accepted_with_warnings',
    'minSymbolsRequired': 2,
    'requestedCount': requestedCount,
    'evaluatedCount': evaluatedCount,
    'rankedCount': rankedCount,
    'failedCount': failedCount,
    'selectedCount': selected.length,
    'eligibleCount': eligibleCount,
    'correlationEligibleCount': correlationEligibleCount,
    'topN': topN,
    'rankingMetric': rankingMetric,
    'minScore': minScore,
    'maxPairwiseCorrelation': maxPairwiseCorrelation,
    'rebalanceInterval': interval,
    'maxPositionWeight': positionCap,
    'targetWeight': weight,
    'warnings': warnings,
    'dataCoverage': {
      'mode': 'selected_symbol_coverage',
      'minBars': bars.isEmpty ? 0 : bars.reduce(min).round(),
      'maxBars': bars.isEmpty ? 0 : bars.reduce(max).round(),
      'symbols': [
        for (final row in selected)
          {
            'symbol': row['symbol'],
            'rank': row['rank'],
            'score': row['score'],
            'lookbackBars': _mapOf(row['relativeStrength'])?['lookbackBars'],
            'start': _mapOf(row['relativeStrength'])?['start'],
            'end': _mapOf(row['relativeStrength'])?['end'],
            'dataEvidence': row['dataEvidence'],
          },
      ],
    },
    'portfolioBacktestStatus': portfolioBacktestEvidence['status'],
    'concentrationStatus': concentrationEvidence['status'],
    'drawdownBudgetStatus': portfolioDrawdownBudgetEvidence['status'],
    'drawdownBudgetEvidence': portfolioDrawdownBudgetEvidence,
    'tradeBoundary':
        'Portfolio validation is evidence-only. It does not authorize simulated or real order placement.',
  };
}

Map<String, dynamic> _candidateFailureEvidence(
  List<Map<String, dynamic>> excludedRows,
) {
  final failures = [
    for (final row in excludedRows)
      {
        'symbol': row['symbol'],
        'status': row['status'],
        'error': row['error'],
        'dataEvidence': row['dataEvidence'],
      },
  ];
  return {
    'mode': 'candidate_failure_evidence',
    'failedCount': failures.length,
    'failures': failures,
    'nextAction': failures.isEmpty
        ? 'none'
        : 'Inspect failed symbols and their dataEvidence; rerun only after data coverage or StrategySpec requirements are corrected.',
  };
}

String _rebalanceInterval(String value) {
  final normalized = value.trim().toLowerCase().replaceAll('_', '-');
  const allowed = {'single-period-draft', 'weekly', 'monthly', 'quarterly'};
  if (allowed.contains(normalized)) return normalized;
  return 'single-period-draft';
}

double _positionCap(double? value) {
  if (value == null || value <= 0 || value.isNaN) return 1.0;
  return _round(value.clamp(0.01, 1.0).toDouble());
}

double? _correlationCap(double? value) {
  if (value == null || value.isNaN || value.isInfinite) return null;
  return _round(value.clamp(0.0, 1.0).toDouble());
}

double? _scoreThreshold(double? value) {
  if (value == null || value.isNaN || value.isInfinite) return null;
  return _round(value);
}

bool _passesScoreThreshold(Map<String, dynamic> row, double? minScore) {
  if (minScore == null) return true;
  return _num(row['score']) >= minScore;
}

_CorrelationSelection _selectWithCorrelationCap(
  List<Map<String, dynamic>> eligibleRows,
  int topN,
  double? maxPairwiseCorrelation,
) {
  final selected = <Map<String, dynamic>>[];
  final skipped = <Map<String, dynamic>>[];
  for (final candidate in eligibleRows) {
    if (selected.length >= topN) break;
    final violation = _correlationViolation(
      candidate,
      selected,
      maxPairwiseCorrelation,
    );
    if (violation != null) {
      skipped.add({'symbol': candidate['symbol'], ...violation});
      continue;
    }
    selected.add(candidate);
  }
  return _CorrelationSelection(selected: selected, skipped: skipped);
}

Map<String, dynamic>? _correlationViolation(
  Map<String, dynamic> candidate,
  List<Map<String, dynamic>> selected,
  double? maxPairwiseCorrelation,
) {
  if (maxPairwiseCorrelation == null || selected.isEmpty) return null;
  final candidateSeries = (candidate['returnSeries'] as List?)
      ?.whereType<double>()
      .toList();
  if (candidateSeries == null || candidateSeries.length < 2) return null;
  for (final row in selected) {
    final selectedSeries = (row['returnSeries'] as List?)
        ?.whereType<double>()
        .toList();
    if (selectedSeries == null || selectedSeries.length < 2) continue;
    final value = _correlation(candidateSeries, selectedSeries);
    if (value == null) continue;
    final absolute = value.abs();
    if (absolute > maxPairwiseCorrelation) {
      return {
        'mode': 'portfolio_correlation_constraint_v1',
        'maxPairwiseCorrelation': maxPairwiseCorrelation,
        'maxObservedCorrelation': _round(absolute),
        'rawCorrelation': _round(value),
        'matchedSymbol': row['symbol'],
      };
    }
  }
  return null;
}

List<double> _returnSeries(List<Candle> candles) {
  final out = <double>[];
  for (var index = 1; index < candles.length; index++) {
    final previous = candles[index - 1].close;
    if (previous == 0) continue;
    out.add((candles[index].close - previous) / previous);
  }
  return out;
}

Map<String, dynamic> _correlationEvidence(List<Map<String, dynamic>> selected) {
  final series = selected
      .map(
        (row) => (row['returnSeries'] as List?)?.whereType<double>().toList(),
      )
      .whereType<List<double>>()
      .where((values) => values.length >= 2)
      .toList();
  if (series.length < 2) {
    return {
      'mode': 'not_enough_series',
      'pairCount': 0,
      'averagePairwiseCorrelation': null,
    };
  }
  final pairs = <double>[];
  for (var left = 0; left < series.length; left++) {
    for (var right = left + 1; right < series.length; right++) {
      final correlation = _correlation(series[left], series[right]);
      if (correlation != null) pairs.add(correlation);
    }
  }
  if (pairs.isEmpty) {
    return {
      'mode': 'insufficient_variance',
      'pairCount': 0,
      'averagePairwiseCorrelation': null,
    };
  }
  return {
    'mode': 'close_return_pairwise_correlation',
    'pairCount': pairs.length,
    'averagePairwiseCorrelation': _round(
      pairs.reduce((a, b) => a + b) / pairs.length,
    ),
  };
}

Map<String, dynamic> _portfolioRiskEvidence(
  List<Map<String, dynamic>> selected,
  double weight,
) {
  final aligned = _alignedPortfolioReturnSeries(selected, weight);
  final returns = aligned['series'] as List<double>;
  if (returns.isEmpty || weight <= 0) {
    return {
      'mode': 'not_enough_series',
      'portfolioReturnPct': 0,
      'portfolioMaxDrawdownPct': 0,
      'bars': 0,
      'residualCashWeight': 1,
    };
  }
  if (returns.length < 2) {
    return {
      'mode': 'not_enough_series',
      'portfolioReturnPct': 0,
      'portfolioMaxDrawdownPct': 0,
      'bars': returns.length,
      'residualCashWeight': aligned['residualCashWeight'],
    };
  }
  var equity = 1.0;
  var peak = 1.0;
  var maxDrawdown = 0.0;
  for (final periodReturn in returns) {
    equity *= 1 + periodReturn;
    peak = max(peak, equity);
    maxDrawdown = max(maxDrawdown, peak > 0 ? (peak - equity) / peak : 0);
  }
  return {
    'mode': 'equal_weight_return_series',
    'portfolioReturnPct': _round((equity - 1) * 100),
    'portfolioMaxDrawdownPct': _round(maxDrawdown * 100),
    'bars': returns.length,
    'residualCashWeight': aligned['residualCashWeight'],
  };
}

Map<String, dynamic> _portfolioDrawdownBudgetEvidence({
  required Map<String, dynamic> spec,
  required List<Map<String, dynamic>> selected,
  required Map<String, dynamic> portfolioRiskEvidence,
}) {
  final risk = _mapOf(spec['risk']) ?? const <String, dynamic>{};
  final configured = _positiveNum(risk['maxDrawdownPct']);
  final allowedDrawdownPct = configured ?? 20.0;
  final observedDrawdownPct = _num(
    portfolioRiskEvidence['portfolioMaxDrawdownPct'],
  );
  final excessDrawdownPct = max(0.0, observedDrawdownPct - allowedDrawdownPct);
  final status = selected.isEmpty
      ? 'insufficient_data'
      : excessDrawdownPct > 0
      ? 'violated'
      : 'within_budget';
  return {
    'mode': 'portfolio_drawdown_budget_v1',
    'status': status,
    'selectedCount': selected.length,
    'allowedDrawdownPct': _round(allowedDrawdownPct),
    'observedDrawdownPct': _round(observedDrawdownPct),
    'excessDrawdownPct': _round(excessDrawdownPct),
    'policySource': configured == null
        ? 'default:20'
        : 'StrategySpec.risk.maxDrawdownPct',
    'sourceEvidence': {
      'portfolioRiskEvidence': 'portfolioMaxDrawdownPct',
      'riskPolicy': 'StrategySpec.risk.maxDrawdownPct or default 20',
    },
    'tradeBoundary':
        'Drawdown budget evidence is portfolio-risk evidence only; it does not authorize simulated or real orders.',
  };
}

Map<String, dynamic> _alignedPortfolioReturnSeries(
  List<Map<String, dynamic>> selected,
  double weight,
) {
  final series = selected
      .map(
        (row) => (row['returnSeries'] as List?)?.whereType<double>().toList(),
      )
      .whereType<List<double>>()
      .where((values) => values.isNotEmpty)
      .toList();
  if (series.isEmpty || weight <= 0) {
    return {'bars': 0, 'series': const <double>[], 'residualCashWeight': 1.0};
  }
  final length = series.map((values) => values.length).reduce(min);
  final returns = <double>[];
  for (var index = 0; index < length; index++) {
    var periodReturn = 0.0;
    for (final values in series) {
      periodReturn += values[values.length - length + index] * weight;
    }
    returns.add(periodReturn);
  }
  return {
    'bars': length,
    'series': returns,
    'residualCashWeight': _round(1 - min(1, weight * series.length)),
  };
}

Map<String, dynamic> _portfolioReturnQualityEvidence(
  List<Map<String, dynamic>> selected,
  double weight,
) {
  final aligned = _alignedPortfolioReturnSeries(selected, weight);
  final returns = aligned['series'] as List<double>;
  if (returns.length < 2) {
    return {
      'mode': 'portfolio_return_quality_v1',
      'status': 'insufficient_data',
      'bars': returns.length,
      'residualCashWeight': aligned['residualCashWeight'],
      'warnings': [
        'At least two aligned portfolio return bars are required for return-quality evidence.',
      ],
      'tradeBoundary':
          'Portfolio return-quality evidence is analytical only; it does not authorize simulated or real orders.',
    };
  }
  final mean = returns.reduce((a, b) => a + b) / returns.length;
  final variance =
      returns
          .map((value) => pow(value - mean, 2).toDouble())
          .reduce((a, b) => a + b) /
      returns.length;
  final downside = returns
      .where((value) => value < 0)
      .map((value) => value * value)
      .toList(growable: false);
  final downsideDeviation = downside.isEmpty
      ? 0.0
      : sqrt(downside.reduce((a, b) => a + b) / returns.length);
  final grossGain = returns
      .where((value) => value > 0)
      .fold<double>(0, (sum, value) => sum + value);
  final grossLoss = returns
      .where((value) => value < 0)
      .fold<double>(0, (sum, value) => sum + value.abs());
  var equity = 1.0;
  var peak = 1.0;
  var maxDrawdown = 0.0;
  for (final value in returns) {
    equity *= 1 + value;
    peak = max(peak, equity);
    maxDrawdown = max(maxDrawdown, peak > 0 ? (peak - equity) / peak : 0);
  }
  final annualFactor = 252.0;
  final annualizedReturn = pow(equity, annualFactor / returns.length) - 1;
  final annualizedVolatility = sqrt(variance) * sqrt(annualFactor);
  final warnings = <String>[];
  if (grossLoss == 0) {
    warnings.add(
      'No losing portfolio periods; gain-to-pain is reported as null.',
    );
  }
  if (downsideDeviation == 0) {
    warnings.add('No downside deviation; Sortino ratio is reported as null.');
  }
  if (maxDrawdown == 0) {
    warnings.add('No portfolio drawdown; Calmar ratio is reported as null.');
  }
  return {
    'mode': 'portfolio_return_quality_v1',
    'status': warnings.isEmpty ? 'complete' : 'complete_with_warnings',
    'bars': returns.length,
    'annualizedReturnPct': _round(annualizedReturn * 100),
    'annualizedVolatilityPct': _round(annualizedVolatility * 100),
    'sharpeRatio': annualizedVolatility == 0
        ? null
        : _round(annualizedReturn / annualizedVolatility),
    'sortinoRatio': downsideDeviation == 0
        ? null
        : _round(annualizedReturn / (downsideDeviation * sqrt(annualFactor))),
    'calmarRatio': maxDrawdown == 0
        ? null
        : _round(annualizedReturn / maxDrawdown),
    'gainToPainRatio': grossLoss == 0 ? null : _round(grossGain / grossLoss),
    'positivePeriodCount': returns.where((value) => value > 0).length,
    'negativePeriodCount': returns.where((value) => value < 0).length,
    'residualCashWeight': aligned['residualCashWeight'],
    'warnings': warnings,
    'tradeBoundary':
        'Portfolio return-quality evidence is analytical only; it does not authorize simulated or real orders.',
  };
}

Map<String, dynamic> _portfolioScoringEvidence({
  required Map<String, dynamic> spec,
  required List<Map<String, dynamic>> selected,
  required double weight,
  required double positionCap,
  required Map<String, dynamic> portfolioRiskEvidence,
  required Map<String, dynamic> portfolioReturnQualityEvidence,
  required Map<String, dynamic> concentrationEvidence,
  required Map<String, dynamic> portfolioBacktestEvidence,
}) {
  final risk = _mapOf(spec['risk']) ?? const <String, dynamic>{};
  final returnPct = _num(portfolioRiskEvidence['portfolioReturnPct']);
  final drawdownPct = _num(portfolioRiskEvidence['portfolioMaxDrawdownPct']);
  final allowedDrawdownPct = _positiveNum(risk['maxDrawdownPct']) ?? 20.0;
  final drawdownPenaltyPct = max(0.0, drawdownPct - allowedDrawdownPct);
  final maxObservedPositionWeight = selected.isEmpty ? 0.0 : weight;
  final tradeCount = selected.fold<int>(
    0,
    (sum, row) => sum + _num(_mapOf(row['metrics'])?['tradeCount']).round(),
  );
  final disqualificationReasons = <String>[];
  if (maxObservedPositionWeight > positionCap + 0.000001) {
    disqualificationReasons.add('max_position_weight_exceeded');
  }
  if (drawdownPct > allowedDrawdownPct) {
    disqualificationReasons.add('max_drawdown_exceeded');
  }
  final warnings = <String>[];
  if (selected.isEmpty) {
    warnings.add(
      'No selected symbols; portfolio scoring cannot rank an empty draft.',
    );
  }
  if (tradeCount == 0) {
    warnings.add('No completed trades across selected candidate backtests.');
  }
  if (_num(concentrationEvidence['residualCashWeight']) > 0) {
    warnings.add('Position cap leaves residual cash outside selected symbols.');
  }
  final qualityStatus = '${portfolioReturnQualityEvidence['status'] ?? ''}';
  if (qualityStatus.isNotEmpty && qualityStatus != 'complete') {
    warnings.add('Return-quality evidence status is $qualityStatus.');
  }
  final status =
      selected.isEmpty ||
          '${portfolioBacktestEvidence['status'] ?? ''}' ==
              'no_selected_symbols'
      ? 'insufficient_data'
      : disqualificationReasons.isNotEmpty
      ? 'disqualified'
      : warnings.isEmpty
      ? 'accepted'
      : 'accepted_with_warnings';
  return {
    'mode': 'portfolio_risk_adjusted_scoring_v1',
    'status': status,
    'scoringMethod': 'return_minus_drawdown_penalty',
    'selectedCount': selected.length,
    'tradeCount': tradeCount,
    'returnPct': _round(returnPct),
    'maxDrawdownPct': _round(drawdownPct),
    'allowedDrawdownPct': _round(allowedDrawdownPct),
    'drawdownPenaltyPct': _round(drawdownPenaltyPct),
    'riskAdjustedScore': selected.isEmpty
        ? null
        : _round(returnPct - drawdownPenaltyPct),
    'maxPositionWeight': positionCap,
    'maxObservedPositionWeight': _round(maxObservedPositionWeight),
    'positionCapStatus': maxObservedPositionWeight <= positionCap + 0.000001
        ? 'within_cap'
        : 'violated',
    'disqualificationReasons': disqualificationReasons,
    'warnings': warnings,
    'sourceEvidence': {
      'portfolioRiskEvidence': 'portfolioReturnPct/portfolioMaxDrawdownPct',
      'portfolioReturnQualityEvidence': qualityStatus,
      'portfolioBacktestEvidence': portfolioBacktestEvidence['status'],
      'riskPolicy': 'StrategySpec.risk.maxDrawdownPct or default 20',
    },
    'tradeBoundary':
        'Portfolio scoring evidence is analytical only; it does not authorize simulated or real orders.',
  };
}

Map<String, dynamic> _portfolioConcentrationEvidence(
  List<Map<String, dynamic>> selected,
  double weight,
  double positionCap,
) {
  if (selected.isEmpty || weight <= 0) {
    return {
      'mode': 'portfolio_concentration_v1',
      'status': 'insufficient_data',
      'selectedCount': selected.length,
      'maxPositionWeight': positionCap,
      'targetWeight': weight,
      'effectivePositionCount': 0,
      'herfindahlIndex': null,
      'residualCashWeight': 1,
      'warnings': [
        'No selected positions are available for concentration evidence.',
      ],
      'tradeBoundary':
          'Concentration evidence is portfolio-risk evidence only; it does not authorize order placement.',
    };
  }
  final investedWeight = min(1.0, weight * selected.length);
  final residualCashWeight = _round(1 - investedWeight);
  final weights = <double>[
    for (var i = 0; i < selected.length; i++) weight,
    if (residualCashWeight > 0) residualCashWeight,
  ];
  final herfindahl = weights.fold<double>(0, (sum, item) => sum + item * item);
  final effectivePositions = herfindahl <= 0 ? 0.0 : 1.0 / herfindahl;
  final warnings = <String>[];
  if (selected.length < 3) {
    warnings.add('Selected draft has fewer than three symbols.');
  }
  if (weight >= 0.5) {
    warnings.add('Single-symbol target weight is at least 50%.');
  }
  if (residualCashWeight > 0) {
    warnings.add('Position cap leaves residual cash outside selected symbols.');
  }
  return {
    'mode': 'portfolio_concentration_v1',
    'status': warnings.isEmpty ? 'diversified_evidence' : 'concentrated',
    'selectedCount': selected.length,
    'selectedSymbols': selected.map((row) => row['symbol']).toList(),
    'targetWeight': weight,
    'maxPositionWeight': positionCap,
    'investedWeight': _round(investedWeight),
    'residualCashWeight': residualCashWeight,
    'herfindahlIndex': _round(herfindahl),
    'effectivePositionCount': _round(effectivePositions),
    'maxSinglePositionWeight': _round(weight),
    'warnings': warnings,
    'tradeBoundary':
        'Concentration evidence is portfolio-risk evidence only; it does not authorize order placement.',
  };
}

Map<String, dynamic> _portfolioStabilityEvidence(
  List<Map<String, dynamic>> selected,
  double weight,
) {
  final series = selected
      .map(
        (row) => (row['returnSeries'] as List?)?.whereType<double>().toList(),
      )
      .whereType<List<double>>()
      .where((values) => values.isNotEmpty)
      .toList();
  if (series.isEmpty || weight <= 0) {
    return {
      'mode': 'portfolio_cross_window_stability_v1',
      'status': 'insufficient_data',
      'windows': const <Map<String, dynamic>>[],
      'warnings': ['No selected return series available for stability check.'],
      'tradeBoundary':
          'Portfolio stability is evidence-only and does not authorize rebalance or order placement.',
    };
  }
  final length = series.map((values) => values.length).reduce(min);
  if (length < 4) {
    return {
      'mode': 'portfolio_cross_window_stability_v1',
      'status': 'insufficient_data',
      'bars': length,
      'windows': const <Map<String, dynamic>>[],
      'warnings': [
        'At least four aligned return bars are required for cross-window stability evidence.',
      ],
      'tradeBoundary':
          'Portfolio stability is evidence-only and does not authorize rebalance or order placement.',
    };
  }
  final aligned = series
      .map((values) => values.sublist(values.length - length))
      .toList(growable: false);
  final split = length ~/ 2;
  final first = _portfolioWindowMetrics(
    aligned,
    weight,
    0,
    split,
    'first_half',
  );
  final second = _portfolioWindowMetrics(
    aligned,
    weight,
    split,
    length,
    'second_half',
  );
  final full = _portfolioWindowMetrics(aligned, weight, 0, length, 'full');
  final returnDegradation = _round(
    _num(second['returnPct']) - _num(first['returnPct']),
  );
  final drawdownIncrease = _round(
    _num(second['maxDrawdownPct']) - _num(first['maxDrawdownPct']),
  );
  final warnings = <String>[];
  if (returnDegradation < -10) {
    warnings.add(
      'Second-window return is more than 10 percentage points below the first window.',
    );
  }
  if (drawdownIncrease > 5) {
    warnings.add(
      'Second-window drawdown is more than 5 percentage points higher than the first window.',
    );
  }
  if (selected.length < 3) {
    warnings.add(
      'Stability evidence is based on fewer than three selected symbols.',
    );
  }
  return {
    'mode': 'portfolio_cross_window_stability_v1',
    'status': warnings.isEmpty ? 'stable_evidence' : 'unstable_evidence',
    'bars': length,
    'split': {
      'method': 'chronological_half_split',
      'firstWindowBars': split,
      'secondWindowBars': length - split,
    },
    'windows': [first, second, full],
    'returnDegradationPct': returnDegradation,
    'drawdownIncreasePct': drawdownIncrease,
    'warnings': warnings,
    'tradeBoundary':
        'Portfolio stability is evidence-only and does not authorize rebalance or order placement.',
  };
}

Map<String, dynamic> _portfolioRebalanceSimulation({
  required List<Map<String, dynamic>> selected,
  required double weight,
  required String interval,
  required Map<String, dynamic> costModel,
}) {
  final series = selected
      .map(
        (row) => (row['returnSeries'] as List?)?.whereType<double>().toList(),
      )
      .whereType<List<double>>()
      .where((values) => values.isNotEmpty)
      .toList();
  final symbols = selected
      .map((row) => '${row['symbol'] ?? ''}'.trim())
      .where((symbol) => symbol.isNotEmpty)
      .toList(growable: false);
  if (series.isEmpty || symbols.isEmpty || weight <= 0) {
    return {
      'mode': 'portfolio_rebalance_simulation_v1',
      'status': 'insufficient_data',
      'selectedSymbols': symbols,
      'warnings': [
        'No selected return series available for portfolio rebalance simulation.',
      ],
      'tradeBoundary':
          'Rebalance simulation is evidence-only and does not authorize portfolio writes or orders.',
    };
  }
  final length = series.map((values) => values.length).reduce(min);
  if (length < 2) {
    return {
      'mode': 'portfolio_rebalance_simulation_v1',
      'status': 'insufficient_data',
      'selectedSymbols': symbols,
      'bars': length,
      'warnings': [
        'At least two aligned return bars are required for portfolio rebalance simulation.',
      ],
      'tradeBoundary':
          'Rebalance simulation is evidence-only and does not authorize portfolio writes or orders.',
    };
  }
  final aligned = series
      .map((values) => values.sublist(values.length - length))
      .toList(growable: false);
  final intervalBars = _rebalanceIntervalBars(interval);
  final residualCashWeight = (1 - min(1, weight * aligned.length)).toDouble();
  final positions = List<double>.filled(aligned.length, weight);
  var cash = residualCashWeight;
  var total = 1.0;
  var peak = 1.0;
  var maxDrawdown = 0.0;
  var rebalanceCount = 0;
  var turnover = 0.0;
  var oneWayTurnoverTotal = min(1.0, weight * aligned.length);
  for (var index = 0; index < length; index++) {
    for (
      var positionIndex = 0;
      positionIndex < positions.length;
      positionIndex++
    ) {
      positions[positionIndex] *= 1 + aligned[positionIndex][index];
    }
    total = cash + positions.reduce((a, b) => a + b);
    peak = max(peak, total);
    maxDrawdown = max(maxDrawdown, peak > 0 ? (peak - total) / peak : 0);
    final shouldRebalance =
        intervalBars > 0 &&
        index < length - 1 &&
        (index + 1) % intervalBars == 0;
    if (!shouldRebalance) continue;
    var oneWayTurnover = 0.0;
    for (
      var positionIndex = 0;
      positionIndex < positions.length;
      positionIndex++
    ) {
      final target = total * weight;
      oneWayTurnover += (target - positions[positionIndex]).abs();
      positions[positionIndex] = target;
    }
    cash = total * residualCashWeight;
    if (total > 0) {
      final turnoverRatio = oneWayTurnover / total;
      turnover += turnoverRatio / 2;
      oneWayTurnoverTotal += turnoverRatio;
    }
    rebalanceCount++;
  }
  final costRatePct = _num(costModel['totalCostRatePct']);
  final estimatedCostPct = _round(oneWayTurnoverTotal * costRatePct);
  final grossReturnPct = _round((total - 1) * 100);
  final warnings = <String>[];
  if (intervalBars == 0) {
    warnings.add(
      'No periodic rebalance was simulated for single-period draft.',
    );
  }
  if (residualCashWeight > 0) {
    warnings.add('Position cap leaves residual cash outside selected symbols.');
  }
  return {
    'mode': 'portfolio_rebalance_simulation_v1',
    'status': 'evidence_only',
    'selectedSymbols': symbols,
    'rebalanceInterval': interval,
    'intervalBars': intervalBars,
    'bars': length,
    'targetWeight': weight,
    'residualCashWeight': _round(residualCashWeight),
    'rebalanceCount': rebalanceCount,
    'averageTurnoverPct': rebalanceCount == 0
        ? 0
        : _round(turnover / rebalanceCount * 100),
    'grossSimulatedReturnPct': grossReturnPct,
    'estimatedTransactionCostPct': estimatedCostPct,
    'simulatedReturnPct': _round(grossReturnPct - estimatedCostPct),
    'simulatedMaxDrawdownPct': _round(maxDrawdown * 100),
    'transactionCostEvidence': {
      'mode': 'portfolio_turnover_cost_estimate_v1',
      'costModel': costModel,
      'initialInvestedWeight': _round(min(1.0, weight * aligned.length)),
      'oneWayTurnoverTotal': _round(oneWayTurnoverTotal),
      'estimatedCostPct': estimatedCostPct,
      'grossReturnPct': grossReturnPct,
      'netReturnPct': _round(grossReturnPct - estimatedCostPct),
    },
    'warnings': warnings,
    'assumptions': [
      'Static selected-symbol set from custom_strategy_rank.',
      'Equal target weight with residual cash from position cap.',
      'Transaction cost is estimated from StrategySpec commissionPct and slippagePct; tax, liquidity impact, order fill, and external portfolio state are not modelled.',
    ],
    'tradeBoundary':
        'Rebalance simulation is evidence-only and does not authorize portfolio writes or orders.',
  };
}

int _rebalanceIntervalBars(String interval) {
  switch (interval) {
    case 'weekly':
      return 5;
    case 'monthly':
      return 21;
    case 'quarterly':
      return 63;
    case 'single-period-draft':
    default:
      return 0;
  }
}

Map<String, dynamic> _portfolioWindowMetrics(
  List<List<double>> aligned,
  double weight,
  int start,
  int end,
  String label,
) {
  var equity = 1.0;
  var peak = 1.0;
  var maxDrawdown = 0.0;
  for (var index = start; index < end; index++) {
    var periodReturn = 0.0;
    for (final values in aligned) {
      periodReturn += values[index] * weight;
    }
    equity *= 1 + periodReturn;
    peak = max(peak, equity);
    maxDrawdown = max(maxDrawdown, peak > 0 ? (peak - equity) / peak : 0);
  }
  return {
    'label': label,
    'bars': end - start,
    'returnPct': _round((equity - 1) * 100),
    'maxDrawdownPct': _round(maxDrawdown * 100),
  };
}

Map<String, dynamic> _portfolioBacktestEvidence({
  required List<Map<String, dynamic>> selected,
  required double weight,
  required String interval,
  required double positionCap,
  required Map<String, dynamic> costModel,
  required Map<String, dynamic> portfolioRiskEvidence,
  required Map<String, dynamic> portfolioReturnQualityEvidence,
  required Map<String, dynamic> correlationEvidence,
}) {
  final symbols = selected
      .map((row) => '${row['symbol'] ?? ''}'.trim())
      .where((symbol) => symbol.isNotEmpty)
      .toList(growable: false);
  final relativeStrengthRows = selected
      .map(_mapOfRelativeStrength)
      .whereType<Map<String, dynamic>>()
      .toList(growable: false);
  final starts = relativeStrengthRows
      .map((row) => '${row['start'] ?? ''}'.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  final ends = relativeStrengthRows
      .map((row) => '${row['end'] ?? ''}'.trim())
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
  return {
    'mode': 'equal_weight_selected_portfolio_backtest',
    'status': symbols.isEmpty ? 'no_selected_symbols' : 'evidence_only',
    'selectedSymbols': symbols,
    'selectedCount': symbols.length,
    'weighting': 'equal_weight',
    'targetWeight': weight,
    'maxPositionWeight': positionCap,
    'rebalanceInterval': interval,
    'start': starts.isEmpty
        ? null
        : starts.reduce((a, b) => a.compareTo(b) > 0 ? a : b),
    'end': ends.isEmpty
        ? null
        : ends.reduce((a, b) => a.compareTo(b) < 0 ? a : b),
    'portfolioReturnPct': portfolioRiskEvidence['portfolioReturnPct'],
    'portfolioMaxDrawdownPct': portfolioRiskEvidence['portfolioMaxDrawdownPct'],
    'portfolioReturnQualityEvidence': portfolioReturnQualityEvidence,
    'bars': portfolioRiskEvidence['bars'],
    'residualCashWeight': portfolioRiskEvidence['residualCashWeight'],
    'transactionCostEvidence': {
      'mode': 'portfolio_static_allocation_cost_estimate_v1',
      'costModel': costModel,
      'initialInvestedWeight': _round(min(1.0, weight * symbols.length)),
      'estimatedInitialCostPct': _round(
        min(1.0, weight * symbols.length) * _num(costModel['totalCostRatePct']),
      ),
      'boundary':
          'Static portfolio evidence estimates initial allocation cost only; interval rebalance cost is reported in portfolioRebalanceSimulation.',
    },
    'correlationEvidence': correlationEvidence,
    'dataEvidence': [
      for (final row in selected)
        {'symbol': row['symbol'], 'dataEvidence': row['dataEvidence']},
    ],
    'assumptions': [
      'Selected-symbol equal-weight return series only.',
      'Transaction cost is estimated from StrategySpec cost assumptions; tax, liquidity impact, order fill, and external portfolio state are not modelled.',
      'Use for watchlist/monitor/trade-preparation evidence; do not treat as execution or rebalance approval.',
    ],
    'tradeBoundary':
        'Evidence only. Simulated or real portfolio changes require separate sizing, user confirmation, execution, and readback.',
  };
}

Map<String, dynamic>? _mapOfRelativeStrength(Map<String, dynamic> row) {
  final value = row['relativeStrength'];
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

Map<String, dynamic> _portfolioCostModel(Map<String, dynamic> spec) {
  final cost = _mapOf(spec['cost']) ?? const <String, dynamic>{};
  final commissionPct = _num(cost['commissionPct']);
  final slippagePct = _num(cost['slippagePct']);
  return {
    'mode': 'strategy_spec_cost_assumption',
    'commissionPct': _round(commissionPct),
    'slippagePct': _round(slippagePct),
    'totalCostRatePct': _round(commissionPct + slippagePct),
    'source': 'strategySpec.cost',
    'taxPct': null,
    'liquidityImpact': 'not_modelled',
  };
}

double? _correlation(List<double> left, List<double> right) {
  final length = left.length < right.length ? left.length : right.length;
  if (length < 2) return null;
  final leftTail = left.sublist(left.length - length);
  final rightTail = right.sublist(right.length - length);
  final leftMean = leftTail.reduce((a, b) => a + b) / length;
  final rightMean = rightTail.reduce((a, b) => a + b) / length;
  var covariance = 0.0;
  var leftVariance = 0.0;
  var rightVariance = 0.0;
  for (var index = 0; index < length; index++) {
    final leftDiff = leftTail[index] - leftMean;
    final rightDiff = rightTail[index] - rightMean;
    covariance += leftDiff * rightDiff;
    leftVariance += leftDiff * leftDiff;
    rightVariance += rightDiff * rightDiff;
  }
  if (leftVariance == 0 || rightVariance == 0) return null;
  return covariance / sqrt(leftVariance * rightVariance);
}

double _score(
  Map<String, dynamic> metrics,
  String rankingMetric,
  Map<String, dynamic> relativeStrength,
) {
  final totalReturn = _num(metrics['totalReturnPct']);
  final sharpe = _num(metrics['sharpeRatio']);
  final drawdown = _num(metrics['maxDrawdownPct']);
  final trades = _num(metrics['tradeCount']);
  final relativeReturn = _num(relativeStrength['returnPct']);
  switch (rankingMetric) {
    case 'relative_strength_pct':
    case 'rps':
      return _round(relativeReturn);
    case 'total_return_pct':
      return _round(totalReturn);
    case 'sharpe_ratio':
      return _round(sharpe);
    case 'max_drawdown_pct':
      return _round(-drawdown);
    case 'trade_count':
      return _round(trades);
    case 'score':
    default:
      return _round(totalReturn + sharpe * 5 - drawdown * 0.5);
  }
}

Map<String, dynamic> _relativeStrength(List<Candle> candles) {
  if (candles.length < 2 || candles.first.close == 0) {
    return {
      'mode': 'candidate_return_rank',
      'lookbackBars': candles.length,
      'returnPct': null,
    };
  }
  final first = candles.first.close;
  final last = candles.last.close;
  return {
    'mode': 'candidate_return_rank',
    'lookbackBars': candles.length,
    'start': candles.first.date,
    'end': candles.last.date,
    'returnPct': _round((last - first) / first * 100),
  };
}

double _relativeStrengthPercentile(int rank, int count) {
  if (count <= 1) return 100;
  return _round((count - rank) / (count - 1) * 100);
}

Map<String, dynamic> _portfolioMetrics(
  List<Map<String, dynamic>> selected,
  Map<String, dynamic> portfolioRiskEvidence,
) {
  if (selected.isEmpty) {
    return {
      'selectedSymbols': <String>[],
      'expectedReturnPct': 0,
      'worstSingleDrawdownPct': 0,
      'averageSharpeRatio': 0,
      'completedTradeCount': 0,
      'portfolioReturnPct': 0,
      'portfolioMaxDrawdownPct': 0,
    };
  }
  final metrics = selected
      .map((row) => _mapOf(row['metrics']) ?? const <String, dynamic>{})
      .toList();
  final totalReturn = metrics
      .map((item) => _num(item['totalReturnPct']))
      .reduce((a, b) => a + b);
  final drawdown = metrics
      .map((item) => _num(item['maxDrawdownPct']))
      .reduce((a, b) => a > b ? a : b);
  final sharpe = metrics
      .map((item) => _num(item['sharpeRatio']))
      .reduce((a, b) => a + b);
  final tradeCount = metrics
      .map((item) => _num(item['tradeCount']))
      .reduce((a, b) => a + b);
  return {
    'selectedSymbols': selected.map((row) => row['symbol']).toList(),
    'expectedReturnPct': _round(totalReturn / selected.length),
    'worstSingleDrawdownPct': _round(drawdown),
    'averageSharpeRatio': _round(sharpe / selected.length),
    'completedTradeCount': tradeCount.toInt(),
    'portfolioReturnPct': portfolioRiskEvidence['portfolioReturnPct'],
    'portfolioMaxDrawdownPct': portfolioRiskEvidence['portfolioMaxDrawdownPct'],
  };
}

Map<String, dynamic>? _mapOf(Object? value) {
  if (value is! Map) return null;
  return Map<String, dynamic>.from(value);
}

double _num(Object? value) => value is num ? value.toDouble() : 0;

double? _positiveNum(Object? value) {
  if (value is! num || !value.isFinite || value <= 0) return null;
  return value.toDouble();
}

double _round(double value) => double.parse(value.toStringAsFixed(4));
