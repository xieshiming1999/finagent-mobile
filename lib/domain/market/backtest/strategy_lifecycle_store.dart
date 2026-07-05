import 'dart:convert';
import 'dart:io';

import '../../../agent/tool_context.dart';
import 'strategy_artifact_contract.dart';

class StrategyLifecycleStore {
  const StrategyLifecycleStore();

  Map<String, dynamic> save(
    ToolContext context,
    Map<String, dynamic> validation, {
    Object? evidence,
  }) {
    final existingRows = readRows(context);
    final existing = existingRows
        .where((row) => row['strategyId'] == validation['strategyId'])
        .cast<Map<String, dynamic>?>()
        .firstWhere((row) => row != null, orElse: () => null);
    final rows = existingRows
        .where((row) => row['strategyId'] != validation['strategyId'])
        .toList();
    final spec = _mapOf(validation['spec']) ?? const <String, dynamic>{};
    final incomingStatus = _statusForEvidence(evidence);
    final existingStatus = '${existing?['status'] ?? ''}';
    final status = _strongerStatus(existingStatus, incomingStatus);
    final effectiveEvidence = evidence ?? existing?['evidence'];
    final updatedAt = DateTime.now().toUtc().toIso8601String();
    final createdAt = _createdAtOf(existing) ?? updatedAt;
    final dataAndAssumptionSummary = _dataAndAssumptionSummary(
      spec,
      validation,
      effectiveEvidence,
    );
    final evidencePayload = _mapOf(effectiveEvidence);
    final record = {
      'action': 'custom_strategy_save',
      'strategyId': validation['strategyId'],
      'version': validation['version'],
      'status': status,
      'spec': spec,
      'validation': validation,
      'evidence': effectiveEvidence,
      'strategySpec': spec,
      'validationReport': validation,
      'validationSummary':
          evidencePayload?['validationSummary'] ??
          validation['validationSummary'],
      'validationIssues':
          evidencePayload?['validationIssues'] ??
          validation['validationIssues'] ??
          const [],
      'repairPlan':
          evidencePayload?['repairPlan'] ??
          validation['repairPlan'] ??
          const [],
      'unsupportedDetails':
          evidencePayload?['unsupportedDetails'] ??
          validation['unsupportedDetails'] ??
          const [],
      'dataRequirements':
          evidencePayload?['dataRequirements'] ??
          validation['dataRequirements'],
      'backtestEvidence':
          _backtestEvidenceFor(effectiveEvidence) ??
          existing?['backtestEvidence'],
      'dataAndAssumptionSummary': dataAndAssumptionSummary,
      'lifecycle': {
        'status': status,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
        'runnable': status == 'backtested',
        'nextActions': _nextActionsForStatus(status),
      },
      'updatedAt': updatedAt,
    };
    rows.add(record);
    writeRows(context, rows);
    return {
      'artifactContract': strategyArtifactContract,
      'paths': strategyArtifactPaths(context.basePath).toJson(),
      'itemPath': strategyItemPath(
        context.basePath,
        '${validation['strategyId']}',
      ),
      ...record,
    };
  }

  String _strongerStatus(String existing, String incoming) {
    if (_statusRank(incoming) >= _statusRank(existing)) return incoming;
    return existing;
  }

  int _statusRank(String status) => switch (status) {
    'backtested' => 4,
    'ranked' || 'observed' => 3,
    'evidence_attached' => 2,
    'validated' => 1,
    _ => 0,
  };

  Map<String, dynamic> list(ToolContext context) {
    final rows = readRows(context);
    return {
      'action': 'custom_strategy_list',
      'count': rows.length,
      'artifactContract': strategyArtifactContract,
      'paths': strategyArtifactPaths(context.basePath).toJson(),
      'strategies': rows.map((row) {
        final spec = _strategySpecOf(row) ?? const <String, dynamic>{};
        final evidence =
            _mapOf(row['backtestEvidence']) ??
            _mapOf(row['evidence']) ??
            const <String, dynamic>{};
        return {
          'strategyId': row['strategyId'],
          'version': row['version'],
          'status': row['status'],
          'updatedAt': row['updatedAt'],
          'name': spec['name'],
          'assetClass': spec['assetClass'] ?? spec['market'] ?? 'stock',
          'symbols': _symbolsOf(spec),
          'evidenceAction': evidence['action'],
          'validationSummary':
              row['validationSummary'] ??
              _mapOf(row['validationReport'])?['validationSummary'] ??
              _mapOf(evidence)?['validationSummary'],
          'validationIssues':
              row['validationIssues'] ??
              _mapOf(row['validationReport'])?['validationIssues'] ??
              _mapOf(evidence)?['validationIssues'] ??
              const [],
          'repairPlan':
              row['repairPlan'] ??
              _mapOf(row['validationReport'])?['repairPlan'] ??
              _mapOf(evidence)?['repairPlan'] ??
              const [],
          'unsupportedDetails':
              row['unsupportedDetails'] ??
              _mapOf(row['validationReport'])?['unsupportedDetails'] ??
              _mapOf(evidence)?['unsupportedDetails'] ??
              const [],
          'dataRequirements':
              row['dataRequirements'] ??
              _mapOf(row['validationReport'])?['dataRequirements'] ??
              _mapOf(evidence)?['dataRequirements'],
          'dataAndAssumptionSummary':
              row['dataAndAssumptionSummary'] ?? const <String, dynamic>{},
          'lifecycle': row['lifecycle'] ?? const <String, dynamic>{},
          'itemPath': strategyItemPath(
            context.basePath,
            '${row['strategyId']}',
          ),
        };
      }).toList(),
    };
  }

  Map<String, dynamic> compare(
    ToolContext context, {
    List<String> strategyIds = const [],
  }) {
    final requested = strategyIds
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();
    final rows = readRows(context)
        .where(
          (row) =>
              requested.isEmpty || requested.contains('${row['strategyId']}'),
        )
        .map(_comparisonRow)
        .toList(growable: false);
    final missing = requested
        .where((id) => rows.every((row) => row['strategyId'] != id))
        .toList(growable: false);
    return {
      'action': 'custom_strategy_compare',
      'artifactContract': strategyArtifactContract,
      'paths': strategyArtifactPaths(context.basePath).toJson(),
      'requestedStrategyIds': requested.toList(growable: false),
      'count': rows.length,
      'missingStrategyIds': missing,
      'strategies': rows,
      'bestBy': _bestBy(rows),
      'comparisonNotes': const [
        'Comparison uses saved artifact evidence only; it does not rerun backtests or fetch new data.',
        'Trade preparation still requires explicit confirmation and post-action readback.',
      ],
    };
  }

  Map<String, dynamic> load(ToolContext context, String strategyId) {
    final row = find(context, strategyId);
    if (row == null) {
      throw ArgumentError('custom strategy not found: $strategyId');
    }
    return row;
  }

  Map<String, dynamic> loadRunnable(ToolContext context, String strategyId) {
    final row = load(context, strategyId);
    if (row['status'] != 'backtested') {
      throw ArgumentError(
        'custom strategy $strategyId is not runnable; status=${row['status']}. Run custom_strategy_backtest and save backtested evidence first.',
      );
    }
    return row;
  }

  String? savedSymbol(ToolContext context, String strategyId) {
    final spec = _strategySpecOf(find(context, strategyId));
    final symbol = '${spec?['symbol'] ?? ''}'.trim();
    if (symbol.isNotEmpty) return symbol;
    final code = '${spec?['code'] ?? ''}'.trim();
    if (code.isNotEmpty) return code;
    final fundCode = '${spec?['fundCode'] ?? ''}'.trim();
    if (fundCode.isNotEmpty) return fundCode;
    final symbols = spec?['symbols'];
    if (symbols is List && symbols.isNotEmpty) return '${symbols.first}'.trim();
    final codes = spec?['codes'];
    if (codes is List && codes.isNotEmpty) return '${codes.first}'.trim();
    final universe = spec?['universe'];
    if (universe is List && universe.isNotEmpty) {
      return '${universe.first}'.trim();
    }
    if (universe is Map) {
      final universeSymbols = universe['symbols'];
      if (universeSymbols is List && universeSymbols.isNotEmpty) {
        return '${universeSymbols.first}'.trim();
      }
    }
    return null;
  }

  Map<String, dynamic>? find(ToolContext context, String strategyId) {
    for (final row in readRows(context)) {
      if (row['strategyId'] == strategyId ||
          _strategySpecOf(row)?['id'] == strategyId) {
        return row;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> readRows(ToolContext context) {
    final file = File(_storePath(context));
    if (!file.existsSync()) return [];
    final decoded = jsonDecode(file.readAsStringSync());
    return (decoded as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void writeRows(ToolContext context, List<Map<String, dynamic>> rows) {
    final paths = ensureStrategyArtifactDirs(context);
    final file = File(paths.libraryPath);
    file.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(rows));
    for (final row in rows) {
      final strategyId = '${row['strategyId'] ?? ''}';
      File(
        strategyItemPath(context.basePath, strategyId),
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(row));
    }
  }

  String _storePath(ToolContext context) =>
      readableStrategyLibraryPath(context.basePath);

  Map<String, dynamic>? _mapOf(Object? raw) {
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(raw);
  }

  Map<String, dynamic>? _strategySpecOf(Map<String, dynamic>? row) {
    return _mapOf(row?['strategySpec']) ?? _mapOf(row?['spec']);
  }

  String? _createdAtOf(Map<String, dynamic>? row) {
    final lifecycle = _mapOf(row?['lifecycle']);
    final createdAt = '${lifecycle?['createdAt'] ?? ''}'.trim();
    if (createdAt.isNotEmpty) return createdAt;
    final updatedAt = '${row?['updatedAt'] ?? ''}'.trim();
    return updatedAt.isNotEmpty ? updatedAt : null;
  }

  Object? _backtestEvidenceFor(Object? evidence) {
    final payload = _mapOf(evidence);
    final action = '${payload?['action'] ?? ''}';
    final status = '${payload?['status'] ?? ''}';
    return action == 'custom_strategy_backtest' ||
            action == 'custom_strategy_run' ||
            status == 'backtested'
        ? evidence
        : null;
  }

  Map<String, dynamic> _dataAndAssumptionSummary(
    Map<String, dynamic> spec,
    Map<String, dynamic> validation,
    Object? evidence,
  ) {
    final payload = _mapOf(evidence);
    final dataEvidence = _mapOf(payload?['dataEvidence']);
    final dataCoverage = _mapOf(payload?['dataCoverage']);
    final fundRiskEvidence = _mapOf(payload?['fundRiskEvidence']);
    final fundCoverageEvidence = _mapOf(payload?['fundCoverageEvidence']);
    final fundCategoryEvidence = _mapOf(payload?['fundCategoryEvidence']);
    final fundPeriodEvidence = _mapOf(payload?['periodEvidence']);
    final fundRuleEvidence = _mapOf(payload?['ruleEvidence']);
    final riskRewardEvidence = _mapOf(payload?['riskRewardEvidence']);
    final portfolioEvidence = _mapOf(payload?['portfolioEvidence']);
    final rebalanceDraft = _mapOf(payload?['rebalanceDraft']);
    final portfolioValidation = _mapOf(payload?['portfolioValidation']);
    final portfolioBacktestEvidence = _mapOf(
      payload?['portfolioBacktestEvidence'],
    );
    final portfolioScoringEvidence = _mapOf(
      payload?['portfolioScoringEvidence'],
    );
    final portfolioDrawdownBudgetEvidence = _mapOf(
      payload?['portfolioDrawdownBudgetEvidence'],
    );
    final portfolioReturnQualityEvidence = _mapOf(
      payload?['portfolioReturnQualityEvidence'],
    );
    final concentrationEvidence = _mapOf(payload?['concentrationEvidence']);
    final portfolioStabilityEvidence = _mapOf(
      payload?['portfolioStabilityEvidence'],
    );
    final portfolioRebalanceSimulation = _mapOf(
      payload?['portfolioRebalanceSimulation'],
    );
    final candidateFailureEvidence = _mapOf(
      payload?['candidateFailureEvidence'],
    );
    final cost = _mapOf(spec['cost']);
    final risk = _mapOf(spec['risk']);
    final positionSizing = _mapOf(spec['positionSizing']);
    return {
      'assetClass': spec['assetClass'] ?? spec['market'] ?? 'stock',
      'symbols': _symbolsOf(spec),
      'dataRequirements':
          spec['dataRequirements'] ?? validation['dataRequirements'],
      'dataEvidence': dataEvidence ?? const <String, dynamic>{},
      'dataCoverage': dataCoverage ?? const <String, dynamic>{},
      'fundCategoryEvidence': ?fundCategoryEvidence,
      'fundCoverageEvidence': ?fundCoverageEvidence,
      'fundRiskEvidence': ?fundRiskEvidence,
      'riskRewardEvidence': ?riskRewardEvidence,
      'periodEvidence': ?fundPeriodEvidence,
      'ruleEvidence': ?fundRuleEvidence,
      'portfolioEvidence': ?portfolioEvidence,
      'rebalanceDraft': ?rebalanceDraft,
      'portfolioValidation': ?portfolioValidation,
      'portfolioBacktestEvidence': ?portfolioBacktestEvidence,
      'portfolioScoringEvidence': ?portfolioScoringEvidence,
      'portfolioDrawdownBudgetEvidence': ?portfolioDrawdownBudgetEvidence,
      'portfolioReturnQualityEvidence': ?portfolioReturnQualityEvidence,
      'concentrationEvidence': ?concentrationEvidence,
      'portfolioStabilityEvidence': ?portfolioStabilityEvidence,
      'portfolioRebalanceSimulation': ?portfolioRebalanceSimulation,
      'candidateFailureEvidence': ?candidateFailureEvidence,
      if (payload != null && payload['ranked'] is List)
        'rankedRowsEvidence': _rankedRowsEvidence(payload['ranked'] as List),
      'feesAndSlippage': {
        'commissionPct': cost?['commissionPct'] ?? cost?['commission_pct'],
        'slippagePct': cost?['slippagePct'] ?? cost?['slippage_pct'],
      },
      'risk': risk ?? const <String, dynamic>{},
      'positionSizing': positionSizing ?? const <String, dynamic>{},
      'tradeBoundary':
          'saved strategy artifact only; trade execution requires explicit confirmation and post-action readback',
    };
  }

  List<Map<String, dynamic>> _rankedRowsEvidence(List rows) {
    return rows
        .whereType<Map>()
        .take(5)
        .map((row) {
          final source = Map<String, dynamic>.from(row);
          return {
            'symbol': source['symbol'],
            'rank': source['rank'],
            'score': source['score'],
            'rankingMetric': source['rankingMetric'],
            'metrics': source['metrics'],
            'signals': source['signals'],
            'benchmarkEvidence': source['benchmarkEvidence'],
            'riskEvidence': source['riskEvidence'],
            'riskRewardEvidence': source['riskRewardEvidence'],
            'selectionEvidence': source['selectionEvidence'],
            'weightEvidence': source['weightEvidence'],
            'dataCoverage': source['dataCoverage'],
            'dataEvidence': source['dataEvidence'],
          };
        })
        .toList(growable: false);
  }

  List<String> _symbolsOf(Map<String, dynamic> spec) {
    final out = <String>[];
    for (final key in ['symbol', 'code', 'fundCode']) {
      final value = '${spec[key] ?? ''}'.trim();
      if (value.isNotEmpty) out.add(value);
    }
    for (final key in ['symbols', 'codes']) {
      final value = spec[key];
      if (value is List) {
        out.addAll(
          value.map((item) => '$item'.trim()).where((item) => item.isNotEmpty),
        );
      }
    }
    final universe = spec['universe'];
    if (universe is List) {
      out.addAll(
        universe.map((item) => '$item'.trim()).where((item) => item.isNotEmpty),
      );
    }
    if (universe is Map && universe['symbols'] is List) {
      out.addAll(
        (universe['symbols'] as List)
            .map((item) => '$item'.trim())
            .where((item) => item.isNotEmpty),
      );
    }
    return out.toSet().toList(growable: false);
  }

  Map<String, dynamic> _comparisonRow(Map<String, dynamic> row) {
    final spec = _strategySpecOf(row) ?? const <String, dynamic>{};
    final lifecycle = _mapOf(row['lifecycle']) ?? const <String, dynamic>{};
    final summary =
        _mapOf(row['dataAndAssumptionSummary']) ?? const <String, dynamic>{};
    final evidence =
        _mapOf(row['backtestEvidence']) ??
        _mapOf(row['evidence']) ??
        const <String, dynamic>{};
    final metrics = _mapOf(evidence['metrics']) ?? const <String, dynamic>{};
    final riskReward =
        _mapOf(summary['riskRewardEvidence']) ??
        _mapOf(evidence['riskRewardEvidence']) ??
        const <String, dynamic>{};
    final portfolioEvidence =
        _mapOf(summary['portfolioEvidence']) ??
        _mapOf(evidence['portfolioEvidence']);
    final portfolioMetrics =
        _mapOf(portfolioEvidence?['aggregateMetrics']) ??
        _mapOf(evidence['portfolioEvidence']) ??
        const <String, dynamic>{};
    final concentrationEvidence =
        _mapOf(summary['concentrationEvidence']) ??
        _mapOf(portfolioEvidence?['concentrationEvidence']) ??
        _mapOf(evidence['concentrationEvidence']) ??
        const <String, dynamic>{};
    final portfolioReturnQualityEvidence =
        _mapOf(summary['portfolioReturnQualityEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioReturnQualityEvidence']) ??
        _mapOf(evidence['portfolioReturnQualityEvidence']) ??
        const <String, dynamic>{};
    final portfolioScoringEvidence =
        _mapOf(summary['portfolioScoringEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioScoringEvidence']) ??
        _mapOf(evidence['portfolioScoringEvidence']) ??
        const <String, dynamic>{};
    final portfolioDrawdownBudgetEvidence =
        _mapOf(summary['portfolioDrawdownBudgetEvidence']) ??
        _mapOf(portfolioEvidence?['portfolioDrawdownBudgetEvidence']) ??
        _mapOf(evidence['portfolioDrawdownBudgetEvidence']) ??
        const <String, dynamic>{};
    final dataCoverage =
        _mapOf(summary['dataCoverage']) ??
        _mapOf(evidence['dataCoverage']) ??
        const <String, dynamic>{};
    final evidenceAction = '${evidence['action'] ?? ''}'.trim();
    final status = '${row['status'] ?? ''}';
    final strategyType = _strategyTypeOf(
      status: status,
      spec: spec,
      evidenceAction: evidenceAction,
      summary: summary,
    );
    return {
      'strategyId': row['strategyId'],
      'name': spec['name'],
      'status': status,
      'strategyType': strategyType,
      'assetClass': spec['assetClass'] ?? spec['market'] ?? 'stock',
      'symbols': _symbolsOf(spec),
      'runnable': lifecycle['runnable'] == true,
      'updatedAt': row['updatedAt'],
      'evidenceAction': evidenceAction.isEmpty ? null : evidenceAction,
      'validationIssueCount': _listLength(row['validationIssues']),
      'repairStepCount': _listLength(row['repairPlan']),
      'unsupportedCount': _listLength(row['unsupportedDetails']),
      'metrics': {
        'totalReturnPct': metrics['totalReturnPct'],
        'sharpeRatio': metrics['sharpeRatio'],
        'maxDrawdownPct': metrics['maxDrawdownPct'],
        'tradeCount': metrics['tradeCount'],
        'profitFactor': metrics['profitFactor'] ?? riskReward['profitFactor'],
        'expectancyPct':
            metrics['expectancyPct'] ?? riskReward['expectancyPct'],
      },
      'portfolioMetrics': {
        'selectedSymbols': portfolioMetrics['selectedSymbols'],
        'portfolioReturnPct': portfolioMetrics['portfolioReturnPct'],
        'portfolioMaxDrawdownPct': portfolioMetrics['portfolioMaxDrawdownPct'],
        'averageSharpeRatio': portfolioMetrics['averageSharpeRatio'],
        'completedTradeCount': portfolioMetrics['completedTradeCount'],
      },
      'concentrationEvidence': {
        'status': concentrationEvidence['status'],
        'effectivePositionCount':
            concentrationEvidence['effectivePositionCount'],
        'herfindahlIndex': concentrationEvidence['herfindahlIndex'],
        'residualCashWeight': concentrationEvidence['residualCashWeight'],
        'maxSinglePositionWeight':
            concentrationEvidence['maxSinglePositionWeight'],
      },
      'portfolioReturnQualityEvidence': {
        'status': portfolioReturnQualityEvidence['status'],
        'annualizedReturnPct':
            portfolioReturnQualityEvidence['annualizedReturnPct'],
        'annualizedVolatilityPct':
            portfolioReturnQualityEvidence['annualizedVolatilityPct'],
        'sharpeRatio': portfolioReturnQualityEvidence['sharpeRatio'],
        'sortinoRatio': portfolioReturnQualityEvidence['sortinoRatio'],
        'calmarRatio': portfolioReturnQualityEvidence['calmarRatio'],
        'gainToPainRatio': portfolioReturnQualityEvidence['gainToPainRatio'],
      },
      'portfolioScoringEvidence': {
        'status': portfolioScoringEvidence['status'],
        'scoringMethod': portfolioScoringEvidence['scoringMethod'],
        'riskAdjustedScore': portfolioScoringEvidence['riskAdjustedScore'],
        'tradeCount': portfolioScoringEvidence['tradeCount'],
        'positionCapStatus': portfolioScoringEvidence['positionCapStatus'],
        'disqualificationReasons':
            portfolioScoringEvidence['disqualificationReasons'],
      },
      'portfolioDrawdownBudgetEvidence': {
        'status': portfolioDrawdownBudgetEvidence['status'],
        'allowedDrawdownPct':
            portfolioDrawdownBudgetEvidence['allowedDrawdownPct'],
        'observedDrawdownPct':
            portfolioDrawdownBudgetEvidence['observedDrawdownPct'],
        'excessDrawdownPct':
            portfolioDrawdownBudgetEvidence['excessDrawdownPct'],
        'policySource': portfolioDrawdownBudgetEvidence['policySource'],
      },
      'dataCoverage': {
        'rows': dataCoverage['rows'],
        'requiredBars': dataCoverage['requiredBars'],
        'sufficient': dataCoverage['sufficient'],
        'source': dataCoverage['source'],
        'cacheStatus': dataCoverage['cacheStatus'],
        'actualStartDate': dataCoverage['actualStartDate'],
        'actualEndDate': dataCoverage['actualEndDate'],
      },
      'score': _comparisonScore(metrics, riskReward, portfolioMetrics),
      'tradeBoundary':
          'Saved strategy comparison is evidence-only; it does not authorize simulated or real order placement.',
    };
  }

  String _strategyTypeOf({
    required String status,
    required Map<String, dynamic> spec,
    required String evidenceAction,
    required Map<String, dynamic> summary,
  }) {
    final assetClass = '${spec['assetClass'] ?? spec['market'] ?? ''}'
        .toLowerCase();
    if (status == 'ranked' ||
        evidenceAction == 'custom_strategy_rank' ||
        summary['portfolioEvidence'] != null) {
      return 'portfolio_strategy';
    }
    if (assetClass == 'fund' ||
        evidenceAction == 'custom_strategy_observe' ||
        evidenceAction == 'custom_strategy_fund_backtest') {
      return 'fund_strategy';
    }
    return 'stock_strategy';
  }

  Map<String, dynamic> _bestBy(List<Map<String, dynamic>> rows) {
    return {
      'score': _bestRow(rows, 'score', higherIsBetter: true),
      'totalReturnPct': _bestMetric(rows, 'metrics', 'totalReturnPct'),
      'sharpeRatio': _bestMetric(rows, 'metrics', 'sharpeRatio'),
      'maxDrawdownPct': _bestMetric(
        rows,
        'metrics',
        'maxDrawdownPct',
        higherIsBetter: false,
      ),
      'portfolioReturnPct': _bestMetric(
        rows,
        'portfolioMetrics',
        'portfolioReturnPct',
      ),
      'portfolioRiskAdjustedScore': _bestMetric(
        rows,
        'portfolioScoringEvidence',
        'riskAdjustedScore',
      ),
    };
  }

  Map<String, dynamic>? _bestMetric(
    List<Map<String, dynamic>> rows,
    String group,
    String key, {
    bool higherIsBetter = true,
  }) {
    final enriched = rows
        .map((row) {
          final value = _num(_mapOf(row[group])?[key]);
          return value == null
              ? null
              : {'strategyId': row['strategyId'], 'value': value};
        })
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    if (enriched.isEmpty) return null;
    enriched.sort((left, right) {
      final result = (_num(left['value']) ?? 0).compareTo(
        _num(right['value']) ?? 0,
      );
      return higherIsBetter ? -result : result;
    });
    return enriched.first;
  }

  Map<String, dynamic>? _bestRow(
    List<Map<String, dynamic>> rows,
    String key, {
    bool higherIsBetter = true,
  }) {
    final enriched = rows
        .where((row) => _num(row[key]) != null)
        .map(
          (row) => {'strategyId': row['strategyId'], 'value': _num(row[key])},
        )
        .toList(growable: false);
    if (enriched.isEmpty) return null;
    enriched.sort((left, right) {
      final result = (_num(left['value']) ?? 0).compareTo(
        _num(right['value']) ?? 0,
      );
      return higherIsBetter ? -result : result;
    });
    return enriched.first;
  }

  double? _comparisonScore(
    Map<String, dynamic> metrics,
    Map<String, dynamic> riskReward,
    Map<String, dynamic> portfolioMetrics,
  ) {
    final portfolioReturn = _num(portfolioMetrics['portfolioReturnPct']);
    final portfolioDrawdown = _num(portfolioMetrics['portfolioMaxDrawdownPct']);
    if (portfolioReturn != null || portfolioDrawdown != null) {
      return _round((portfolioReturn ?? 0) - (portfolioDrawdown ?? 0) * 0.5);
    }
    final totalReturn = _num(metrics['totalReturnPct']);
    final sharpe = _num(metrics['sharpeRatio']);
    final drawdown = _num(metrics['maxDrawdownPct']);
    final expectancy =
        _num(metrics['expectancyPct']) ?? _num(riskReward['expectancyPct']);
    if (totalReturn == null &&
        sharpe == null &&
        drawdown == null &&
        expectancy == null) {
      return null;
    }
    return _round(
      (totalReturn ?? 0) +
          (sharpe ?? 0) * 5 -
          (drawdown ?? 0) * 0.5 +
          (expectancy ?? 0),
    );
  }

  int _listLength(Object? value) => value is List ? value.length : 0;

  double? _num(Object? value) {
    if (value is num && value.isFinite) return value.toDouble();
    return null;
  }

  double _round(num value) => double.parse(value.toStringAsFixed(4));

  List<String> _nextActionsForStatus(String status) {
    switch (status) {
      case 'backtested':
        return const [
          'custom_strategy_run',
          'custom_strategy_observe',
          'create_monitor',
        ];
      case 'observed':
      case 'ranked':
      case 'evidence_attached':
        return const ['read_evidence', 'create_monitor'];
      default:
        return const ['custom_strategy_backtest', 'custom_strategy_observe'];
    }
  }

  String _statusForEvidence(Object? evidence) {
    if (evidence == null) return 'validated';
    final payload = _mapOf(evidence);
    final action = '${payload?['action'] ?? ''}';
    final status = '${payload?['status'] ?? ''}';
    if (status == 'backtested') return 'backtested';
    if (status == 'observed') return 'observed';
    if (status == 'ranked') return 'ranked';
    switch (action) {
      case 'custom_strategy_backtest':
      case 'custom_strategy_run':
        return 'backtested';
      case 'custom_strategy_observe':
      case 'custom_strategy_fund_backtest':
        return 'observed';
      case 'custom_strategy_rank':
        return 'ranked';
    }
    if ('${payload?['signal'] ?? ''}'.trim().isNotEmpty ||
        payload?['fundDrawdown20'] is num ||
        payload?['navTrend20'] is num) {
      return 'observed';
    }
    if (payload?['rankedCount'] is num ||
        payload?['portfolioEvidence'] != null) {
      return 'ranked';
    }
    return 'evidence_attached';
  }
}
