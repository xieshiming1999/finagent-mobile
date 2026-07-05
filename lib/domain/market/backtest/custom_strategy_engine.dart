import '../../../agent/tool_context.dart';
import 'backtest_core.dart';
import 'strategy_backtest_runner.dart';
import 'strategy_fund_observer.dart';
import 'strategy_lifecycle_store.dart';
import 'strategy_method_registry.dart';
import 'strategy_portfolio_ranker.dart';
import 'strategy_spec_normalizer.dart';
import 'strategy_spec_validator.dart';

class CustomStrategyEngine {
  final StrategyLifecycleStore _store;

  CustomStrategyEngine({StrategyLifecycleStore? store})
    : _store = store ?? const StrategyLifecycleStore();

  Map<String, dynamic> help() => {
    'action': 'custom_strategy_help',
    'supportedActions': [
      'custom_strategy_validate',
      'custom_strategy_backtest',
      'custom_strategy_observe',
      'custom_strategy_fund_backtest',
      'custom_strategy_rank',
      'custom_strategy_save',
      'custom_strategy_list',
      'custom_strategy_compare',
      'custom_strategy_run',
    ],
    'executableV1': {
      'indicators': executableStrategyIndicators.toList()..sort(),
      'indicatorCatalog': strategyIndicatorHelpCatalog,
      'indicatorCategories': strategyIndicatorCatalogByCategory().keys.toList()
        ..sort(),
      'indicatorCatalogByCategory': strategyIndicatorCatalogByCategory(),
      'stockExample': {
        'name': 'low_risk_pullback',
        'market': 'cn',
        'universe': {
          'type': 'single',
          'symbols': ['600519'],
        },
        'dataRequirements': {
          'minBars': 120,
          'adjust': 'none',
          'requiredFields': ['open', 'high', 'low', 'close', 'volume'],
        },
        'indicators': [
          {
            'id': 'ema20',
            'type': 'ema',
            'source': 'close',
            'params': {'period': 20},
          },
          {
            'id': 'ema60',
            'type': 'ema',
            'source': 'close',
            'params': {'period': 60},
          },
          {
            'id': 'rsi14',
            'type': 'rsi',
            'source': 'close',
            'params': {'period': 14},
          },
          {
            'id': 'atrPct14',
            'type': 'atr_pct',
            'source': 'close',
            'params': {'period': 14},
          },
        ],
        'entry': {
          'all': [
            {
              'left': 'ema20',
              'op': '>',
              'right': {
                'mul': ['ema60', 1],
              },
            },
            {'left': 'rsi14', 'op': '<=', 'right': 60},
            {'left': 'atrPct14', 'op': '<=', 'right': 3},
          ],
        },
        'exit': {
          'any': [
            {'type': 'stop_loss_pct', 'value': 6},
            {'type': 'take_profit_pct', 'value': 12},
            {'type': 'atr_stop_loss', 'value': 2, 'period': 14},
            {'type': 'trailing_stop_pct', 'value': 8},
          ],
        },
        'positionSizing': {'type': 'fixed_fraction', 'value': 0.2},
      },
      'operators': strategyAllowedOperators.toList(),
      'exits': [
        'stop_loss_pct',
        'take_profit_pct',
        'trailing_stop_pct',
        'max_drawdown_stop_pct',
        'atr_stop_loss',
        'time_stop_bars',
      ],
      'positionSizing': [
        'full_capital',
        'fixed_fraction',
        'risk_per_trade',
        'kelly_fraction',
      ],
      'rankingMetrics': [
        'score',
        'total_return_pct',
        'sharpe_ratio',
        'max_drawdown_pct',
        'trade_count',
        'relative_strength_pct',
        'rps',
      ],
      'rebalanceIntervals': ['weekly', 'monthly', 'quarterly'],
      'portfolioDraftControls': [
        'rebalanceInterval',
        'maxPositionWeight',
        'minScore',
        'maxPairwiseCorrelation',
      ],
    },
    'fundObservationV1': {
      'requires': ['assetClass:fund', 'market:fund', 'fundRows'],
      'actions': ['custom_strategy_observe', 'custom_strategy_fund_backtest'],
      'indicators': fundStrategyIndicatorCatalog,
      'indicatorCatalog': fundStrategyIndicatorHelpCatalog,
      'indicatorCategories': fundStrategyIndicatorCatalogByCategory().keys
          .toList(),
      'indicatorCatalogByCategory': fundStrategyIndicatorCatalogByCategory(),
      'ordinaryFundExample': {
        'name': 'fund_nav_dca',
        'assetClass': 'fund',
        'market': 'fund',
        'dataRequirements': {
          'dataClass': 'ordinary_fund_nav',
          'requiredFields': ['date', 'nav'],
          'minBars': 60,
        },
        'indicators': [
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
        ],
        'entry': {
          'all': [
            {'left': 'fundDrawdown20', 'op': '>=', 'right': 8},
            {'left': 'fundDrawdown20', 'op': '<', 'right': 15},
          ],
        },
        'exit': {
          'any': [
            {'left': 'fundDrawdown20', 'op': '>=', 'right': 15},
          ],
        },
      },
      'moneyFundExample': {
        'name': 'money_yield_watch',
        'assetClass': 'fund',
        'market': 'fund',
        'fundType': 'money',
        'dataRequirements': {
          'dataClass': 'money_fund_yield',
          'requiredFields': ['date', 'moneyYield', 'sevenDayYield'],
          'minBars': 30,
        },
        'indicators': [
          {
            'id': 'sevenDayYield',
            'type': 'seven_day_yield',
            'source': 'yield',
            'params': {'period': 7},
          },
          {
            'id': 'moneyYield',
            'type': 'money_yield',
            'source': 'yield',
            'params': {'period': 7},
          },
        ],
        'entry': {
          'all': [
            {'left': 'sevenDayYield', 'op': '>', 'right': 0.85},
          ],
        },
        'exit': {
          'any': [
            {'left': 'sevenDayYield', 'op': '<', 'right': 0.8},
          ],
        },
      },
      'boundary':
          'Fund StrategySpec is observation/period-evidence only. Do not call custom_strategy_backtest for fund specs.',
    },
    'inputContracts': {
      'custom_strategy_validate': {
        'requiredFields': ['strategySpec'],
        'optionalFields': [
          {
            'name': 'proxyApproval',
            'type': 'object',
            'default': null,
            'purpose':
                'explicit approval object required only when validating a proxy StrategySpec for unsupported original signals',
          },
        ],
        'boundary':
            'Validation is read-only. Use structured status, validationSummary, repairPlan, validationIssues, unsupported, and unsupportedDetails to revise or stop.',
      },
      'custom_strategy_backtest': {
        'requiredFields': ['strategySpec'],
        'symbolFields': ['code', 'symbol', 'symbols[0]', 'strategySpec.universe.symbols[0]'],
        'optionalFields': [
          {
            'name': 'period',
            'type': 'string',
            'default': '1y',
            'purpose': 'historical K-line window requested from governed data',
          },
          {
            'name': 'outOfSampleRatio',
            'type': 'number',
            'aliases': ['validationSplit', 'holdoutRatio'],
            'default': null,
            'min': 0,
            'max': 0.8,
            'purpose': 'chronological holdout ratio for out-of-sample evidence',
          },
          {
            'name': 'walkForwardFolds',
            'type': 'integer',
            'aliases': ['walkForward_folds', 'stabilityFolds'],
            'default': null,
            'min': 2,
            'purpose': 'number of walk-forward stability folds',
          },
        ],
        'boundary':
            'Backtest is stock StrategySpec only. Fund specs use custom_strategy_observe or custom_strategy_fund_backtest.',
      },
      'custom_strategy_observe': {
        'requiredFields': ['strategySpec', 'fundRows'],
        'optionalFields': [
          {
            'name': 'code',
            'type': 'string',
            'default': null,
            'purpose':
                'fund code used to resolve local NAV or money-yield rows when fundRows is omitted by the tool caller',
          },
        ],
        'boundary':
            'Fund observation is evidence-only and cannot execute subscription, redemption, stock backtest, or trade actions.',
      },
      'custom_strategy_fund_backtest': {
        'requiredFields': ['strategySpec', 'fundRows'],
        'optionalFields': [
          {
            'name': 'code',
            'type': 'string',
            'default': null,
            'purpose':
                'fund code used to resolve local NAV or money-yield rows when fundRows is omitted by the tool caller',
          },
        ],
        'boundary':
            'Fund period evidence uses NAV/yield rows and does not become stock K-line backtest evidence.',
      },
      'custom_strategy_rank': {
        'requiredFields': ['strategySpec', 'symbols'],
        'optionalFields': [
          {
            'name': 'topN',
            'type': 'integer',
            'default': 3,
            'min': 1,
            'max': 10,
            'purpose': 'number of ranked candidates allowed into the draft',
          },
          {
            'name': 'rankingMetric',
            'type': 'enum',
            'default': 'score',
            'values': [
              'score',
              'total_return_pct',
              'sharpe_ratio',
              'max_drawdown_pct',
              'trade_count',
              'relative_strength_pct',
              'rps',
            ],
            'purpose': 'candidate ordering metric',
          },
          {
            'name': 'rebalanceInterval',
            'type': 'enum',
            'default': 'single_period_draft',
            'values': ['single_period_draft', 'weekly', 'monthly', 'quarterly'],
            'purpose': 'evidence-only rebalance simulation cadence',
          },
          {
            'name': 'maxPositionWeight',
            'type': 'number',
            'default': 1,
            'min': 0.01,
            'max': 1,
            'purpose': 'position cap for the equal-weight draft',
          },
          {
            'name': 'minScore',
            'type': 'number',
            'default': null,
            'purpose': 'minimum score required to enter the draft',
          },
          {
            'name': 'maxPairwiseCorrelation',
            'type': 'number',
            'default': null,
            'min': 0,
            'max': 1,
            'purpose':
                'absolute close-return correlation cap for selected candidates',
          },
        ],
        'selectionEvidenceFields': [
          'selectedForDraft',
          'exclusionReason',
          'minScore',
          'maxPairwiseCorrelation',
          'correlationConstraintEvidence',
        ],
        'boundary':
            'custom_strategy_rank input controls only shape evidence and rebalance drafts; they do not authorize watchlist writes, simulated trades, or real orders.',
      },
      'custom_strategy_save': {
        'requiredFields': ['strategySpec'],
        'optionalFields': [
          {
            'name': 'evidence',
            'type': 'object',
            'default': null,
            'purpose':
                'validated/backtested/observed/ranked evidence returned by a prior custom strategy action',
          },
        ],
        'boundary':
            'Save stores a strategy artifact only. It must not create watchlist entries, monitor jobs, simulated trades, or real orders.',
      },
      'custom_strategy_run': {
        'requiredFields': ['strategyId'],
        'symbolFields': ['code', 'symbol', 'symbols[0]', 'saved strategy symbol'],
        'optionalFields': [
          {
            'name': 'period',
            'type': 'string',
            'default': '1y',
            'purpose': 'historical K-line window for rerun evidence',
          },
        ],
        'boundary':
            'Run only reuses a saved runnable stock strategy artifact. Non-runnable artifacts return readback_only lifecycle evidence.',
      },
    },
    'outputContracts': {
      'custom_strategy_validate': {
        'coreFields': [
          'status',
          'validationSummary',
          'validationIssues',
          'repairPlan',
          'unsupported',
          'unsupportedDetails',
          'dataRequirements',
        ],
        'repairPlanFields': [
          'category',
          'path',
          'field',
          'repairAction',
          'target',
          'patchHint',
          'blocking',
        ],
        'nextAction':
            'Use validationSummary.nextAction, repairPlan, validationIssues, and unsupportedDetails to revise or stop; do not parse prose errors.',
      },
      'custom_strategy_backtest': {
        'coreFields': [
          'metrics',
          'signals',
          'trades',
          'lifecycleAdvice',
          'validationSummary',
          'validationIssues',
          'unsupportedDetails',
          'dataRequirements',
          'benchmarkEvidence',
          'riskEvidence',
          'riskRewardEvidence',
          'dataEvidence',
          'dataCoverage',
          'assumptions',
          'outOfSample',
          'walkForward',
        ],
        'lifecycleAdvice':
            'If saveable is true and the user requested save/rerun lifecycle verification, call custom_strategy_save with this backtest evidence, then custom_strategy_run by strategyId. Zero completed trades is an evidence boundary, not a validation failure.',
        'dataCoverage': [
          'symbol',
          'source',
          'cacheStatus',
          'rows',
          'requiredBars',
          'sufficient',
          'actualStartDate',
          'actualEndDate',
          'dataRequirements',
        ],
      },
      'custom_strategy_rank': {
        'coreFields': [
          'ranked',
          'portfolioEvidence',
          'rebalanceDraft',
          'validationSummary',
          'validationIssues',
          'unsupportedDetails',
          'dataRequirements',
          'portfolioBacktestEvidence',
          'portfolioScoringEvidence',
          'portfolioDrawdownBudgetEvidence',
          'portfolioReturnQualityEvidence',
          'concentrationEvidence',
          'portfolioStabilityEvidence',
          'portfolioValidation',
          'candidateFailureEvidence',
          'selectionEvidence',
          'positionContributionEvidence',
          'transactionCostEvidence',
        ],
        'portfolioRebalanceSimulationFields': [
          'grossSimulatedReturnPct',
          'estimatedTransactionCostPct',
          'simulatedReturnPct',
          'transactionCostEvidence',
        ],
        'portfolioBacktestEvidenceFields': ['transactionCostEvidence'],
        'rankedRowFields': [
          'symbol',
          'rank',
          'score',
          'metrics',
          'signals',
          'benchmarkEvidence',
          'riskEvidence',
          'selectionEvidence',
          'weightEvidence',
          'dataCoverage',
          'assumptions',
          'dataEvidence',
        ],
        'boundary':
            'Ranking and rebalance evidence are evidence-only; they do not place orders.',
      },
      'custom_strategy_observe': {
        'coreFields': [
          'observation',
          'dcaObservation',
          'monitorDraft',
          'comparisonEvidence',
          'fundRiskEvidence',
          'fundCoverageEvidence',
        ],
        'boundary':
            'Fund observation evidence is not stock backtest evidence and does not execute subscription, redemption, or trade actions.',
      },
      'custom_strategy_fund_backtest': {
        'coreFields': [
          'periodEvidence',
          'fundRiskEvidence',
          'fundCoverageEvidence',
          'ruleEvidence',
          'tradeBoundary',
        ],
        'boundary':
            'Fund period evidence uses NAV/yield rows, not stock K-line signals.',
      },
      'custom_strategy_save': {
        'coreFields': [
          'artifactContract',
          'paths',
          'itemPath',
          'strategyId',
          'status',
          'strategySpec',
          'validationReport',
          'validationSummary',
          'validationIssues',
          'repairPlan',
          'unsupportedDetails',
          'dataRequirements',
          'backtestEvidence',
          'dataAndAssumptionSummary',
          'lifecycle',
        ],
        'dataAndAssumptionSummaryFields': [
          'dataEvidence',
          'dataCoverage',
          'fundCategoryEvidence',
          'fundCoverageEvidence',
          'fundRiskEvidence',
          'periodEvidence',
          'ruleEvidence',
          'portfolioEvidence',
          'rebalanceDraft',
          'portfolioValidation',
          'portfolioBacktestEvidence',
          'portfolioScoringEvidence',
          'portfolioDrawdownBudgetEvidence',
          'portfolioReturnQualityEvidence',
          'portfolioStabilityEvidence',
          'portfolioRebalanceSimulation',
          'concentrationEvidence',
          'candidateFailureEvidence',
          'rankedRowsEvidence',
        ],
        'boundary':
            'Saved strategy artifacts are reusable evidence; trade execution still requires explicit confirmation.',
      },
      'custom_strategy_list': {
        'topFields': ['artifactContract', 'paths', 'count', 'strategies'],
        'rowFields': [
          'itemPath',
          'strategyId',
          'status',
          'assetClass',
          'symbols',
          'evidenceAction',
          'validationSummary',
          'validationIssues',
          'repairPlan',
          'unsupportedDetails',
          'dataRequirements',
          'dataAndAssumptionSummary',
          'lifecycle',
        ],
        'dataAndAssumptionSummaryFields': [
          'dataEvidence',
          'dataCoverage',
          'fundCategoryEvidence',
          'fundCoverageEvidence',
          'fundRiskEvidence',
          'periodEvidence',
          'ruleEvidence',
          'portfolioEvidence',
          'rebalanceDraft',
          'portfolioValidation',
          'portfolioBacktestEvidence',
          'portfolioScoringEvidence',
          'portfolioDrawdownBudgetEvidence',
          'portfolioReturnQualityEvidence',
          'portfolioStabilityEvidence',
          'portfolioRebalanceSimulation',
          'concentrationEvidence',
          'candidateFailureEvidence',
          'rankedRowsEvidence',
        ],
      },
      'custom_strategy_compare': {
        'topFields': [
          'artifactContract',
          'paths',
          'count',
          'requestedStrategyIds',
          'missingStrategyIds',
          'strategies',
          'bestBy',
          'comparisonNotes',
        ],
        'rowFields': [
          'strategyId',
          'name',
          'status',
          'strategyType',
          'assetClass',
          'symbols',
          'runnable',
          'evidenceAction',
          'validationIssueCount',
          'repairStepCount',
          'unsupportedCount',
          'metrics',
          'portfolioMetrics',
          'portfolioScoringEvidence',
          'portfolioDrawdownBudgetEvidence',
          'dataCoverage',
          'score',
          'tradeBoundary',
        ],
        'boundary':
            'Comparison reads saved artifacts only; it does not rerun, fetch data, or authorize trades.',
      },
      'custom_strategy_run': {
        'runnableBacktestedFields': [
          'metrics',
          'signals',
          'validationSummary',
          'validationIssues',
          'repairPlan',
          'unsupportedDetails',
          'dataRequirements',
          'benchmarkEvidence',
          'dataCoverage',
          'lifecycle',
        ],
        'readbackOnlyFields': [
          'lifecycleIssue',
          'validationIssues',
          'repairPlan',
          'evidenceAction',
          'dataAndAssumptionSummary',
          'portfolioEvidence',
          'rebalanceDraft',
          'portfolioValidation',
          'portfolioBacktestEvidence',
          'portfolioScoringEvidence',
          'portfolioDrawdownBudgetEvidence',
          'portfolioReturnQualityEvidence',
          'portfolioStabilityEvidence',
          'portfolioRebalanceSimulation',
          'concentrationEvidence',
          'lifecycle',
        ],
      },
    },
    'unsupportedV1': [
      'arbitrary code',
      'news sentiment as executable signal',
      'main-fund intraday tape as executable signal',
      'multi-leg/options strategies',
      'broker execution',
    ],
    'proxyContract': {
      'markerFields': [
        'proxyFor',
        'originalSignals',
        'unsupportedOriginalSignals',
        'proxyApproval',
      ],
      'approvalRequired': true,
      'approvalShape': {
        'proxyApproval': {'approved': true},
      },
      'boundary':
          'A proxy StrategySpec is a separate redesigned strategy. Do not validate, backtest, or save it as the original unsupported strategy without explicit user approval.',
    },
  };

  Map<String, dynamic> validate(Object? raw) {
    if (raw is! Map) {
      return rejectedStrategySpec(
        'custom_invalid',
        {'id': 'custom_invalid', 'name': 'invalid'},
        ['strategySpec object is required'],
      );
    }
    final spec = normalizeStrategySpec(Map<String, dynamic>.from(raw));
    if (isFundStrategySpec(spec)) return validateFundStrategySpec(spec);
    return validateStockStrategySpec(spec);
  }

  Map<String, dynamic> backtest(
    Object? raw,
    List<Candle> candles, {
    required String symbol,
    double? outOfSampleRatio,
    int? walkForwardFolds,
  }) {
    final validation = validate(raw);
    if (validation['status'] != 'validated') {
      throw ArgumentError(
        'custom strategy validation failed: ${(validation['errors'] as List).join('; ')}',
      );
    }
    final spec = Map<String, dynamic>.from(validation['spec'] as Map);
    if (isFundStrategySpec(spec)) {
      throw ArgumentError(
        'custom fund StrategySpec is validation/observation-only in this runtime; use query_fund_nav, query_fund_money_yield, query_fund_performance, and fund-specific evidence before a fund backtest engine is available.',
      );
    }
    return runStrategySpecBacktest(
      validation: validation,
      spec: spec,
      candles: candles,
      symbol: symbol,
      outOfSampleRatio: outOfSampleRatio,
      walkForwardFolds: walkForwardFolds,
    );
  }

  Map<String, dynamic> observe(Object? raw, Object? fundRows) {
    final validation = validate(raw);
    if (validation['status'] != 'validated') {
      throw ArgumentError(
        'custom strategy validation failed: ${(validation['errors'] as List).join('; ')}',
      );
    }
    final spec = Map<String, dynamic>.from(validation['spec'] as Map);
    if (!isFundStrategySpec(spec)) {
      throw ArgumentError(
        'custom_strategy_observe is fund-only. Correct the StrategySpec by setting assetClass:"fund" or market:"fund" and using fund indicators such as nav_trend, rolling_return, fund_drawdown, fund_volatility, fund_sharpe, fund_sortino, fund_calmar, money_yield, seven_day_yield, or dca_interval; use custom_strategy_backtest only for stock StrategySpec.',
      );
    }
    final rows = (fundRows as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return observeFundStrategySpec(
      validation: validation,
      spec: spec,
      rows: rows,
    );
  }

  Map<String, dynamic> fundBacktest(Object? raw, Object? fundRows) {
    final validation = validate(raw);
    if (validation['status'] != 'validated') {
      throw ArgumentError(
        'custom strategy validation failed: ${(validation['errors'] as List).join('; ')}',
      );
    }
    final spec = Map<String, dynamic>.from(validation['spec'] as Map);
    if (!isFundStrategySpec(spec)) {
      throw ArgumentError(
        'custom_strategy_fund_backtest is fund-only. Correct the StrategySpec by setting assetClass:"fund" or market:"fund" and using fund indicators such as nav_trend, rolling_return, fund_drawdown, fund_volatility, fund_sharpe, fund_sortino, fund_calmar, money_yield, seven_day_yield, or dca_interval; use custom_strategy_backtest only for stock StrategySpec.',
      );
    }
    final rows = (fundRows as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return backtestFundStrategySpec(
      validation: validation,
      spec: spec,
      rows: rows,
    );
  }

  Map<String, dynamic> rank(
    Object? raw,
    List<StrategyPortfolioCandidate> candidates, {
    int topN = 3,
    String rankingMetric = 'score',
    String rebalanceInterval = 'single_period_draft',
    double? maxPositionWeight,
    double? minScore,
    double? maxPairwiseCorrelation,
  }) {
    return rankCustomStrategyPortfolio(
      engine: this,
      strategySpec: raw,
      candidates: candidates,
      topN: topN,
      rankingMetric: rankingMetric,
      rebalanceInterval: rebalanceInterval,
      maxPositionWeight: maxPositionWeight,
      minScore: minScore,
      maxPairwiseCorrelation: maxPairwiseCorrelation,
    );
  }

  Map<String, dynamic> save(
    ToolContext context,
    Object? raw, {
    Object? evidence,
  }) {
    final validation = validate(raw);
    if (validation['status'] != 'validated') {
      throw ArgumentError(
        'custom strategy validation failed: ${(validation['errors'] as List).join('; ')}',
      );
    }
    return _store.save(context, validation, evidence: evidence);
  }

  Map<String, dynamic> list(ToolContext context) => _store.list(context);

  Map<String, dynamic> compare(
    ToolContext context, {
    List<String> strategyIds = const [],
  }) => _store.compare(context, strategyIds: strategyIds);

  Map<String, dynamic> readSaved(ToolContext context, String strategyId) =>
      _store.load(context, strategyId);

  String? savedSymbol(ToolContext context, String strategyId) =>
      _store.savedSymbol(context, strategyId);

  Map<String, dynamic> runSaved(
    ToolContext context,
    String strategyId,
    List<Candle> candles, {
    required String symbol,
  }) {
    final row = _store.loadRunnable(context, strategyId);
    final result = backtest(row['spec'], candles, symbol: symbol);
    return {
      ...result,
      'action': 'custom_strategy_run',
      'savedStrategyStatus': row['status'],
      'savedStrategyUpdatedAt': row['updatedAt'],
      'repairPlan': row['repairPlan'] ?? const [],
    };
  }
}
