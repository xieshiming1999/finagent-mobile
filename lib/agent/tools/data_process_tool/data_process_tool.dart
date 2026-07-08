// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:io';

import '../../data_fetcher/data_manager.dart';
import '../../data_fetcher/models.dart';
import '../../data_fetcher/reusable_data_store.dart';
import '../../data_processor/advanced_indicators.dart';
import '../../data_processor/ai_backtest.dart';
import '../../data_processor/alpha_factors.dart';
import '../../strategy.dart';
import '../../strategy_executor.dart';
import '../../watchlist.dart';
import '../../data_processor/fundamental_scorer.dart';
import '../../data_processor/fund_screener.dart';
import '../../data_processor/indicators.dart';
import '../../data_processor/signals.dart';
import '../../data_processor/portfolio_optimizer.dart';
import '../../data_processor/trend_analysis.dart';
import '../../data_processor/patterns.dart';
import '../../data_processor/statistics.dart';
import '../../data_processor/screener.dart';
import '../../data_processor/signal_journal.dart';
import '../../data_processor/market_snapshot.dart';
import '../../data_processor/trading_calendar.dart';
import '../../../domain/market/services/market_data_resolve_service.dart';
import '../../../domain/market/services/market_data_query_action_service.dart';
import '../../../domain/market/services/cache_policy.dart';
import '../../../domain/market/market_index_universe.dart';
import '../../../domain/market/analysis/analysis_evidence_contract.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';

class _WatchSignalEvidence {
  final String symbol;
  final String type;
  final String metricName;
  final double? metricValue;
  final String sourceDataTime;
  final String provider;
  final String fetchedAt;
  final String interfaceId;
  final String canonicalTable;

  const _WatchSignalEvidence({
    required this.symbol,
    required this.type,
    required this.metricName,
    required this.metricValue,
    required this.sourceDataTime,
    required this.provider,
    required this.fetchedAt,
    required this.interfaceId,
    required this.canonicalTable,
  });

  _WatchSignalEvidence copyWith({String? type}) {
    return _WatchSignalEvidence(
      symbol: symbol,
      type: type ?? this.type,
      metricName: metricName,
      metricValue: metricValue,
      sourceDataTime: sourceDataTime,
      provider: provider,
      fetchedAt: fetchedAt,
      interfaceId: interfaceId,
      canonicalTable: canonicalTable,
    );
  }
}

class DataProcessTool extends Tool {
  final MarketDataResolveService _resolveService;
  final MarketDataQueryActionService _queryService;
  final WatchlistStore? _watchlistStore;

  DataProcessTool({
    DataManager? dataManager,
    MarketDataResolveService? resolveService,
    WatchlistStore? watchlistStore,
  }) : this._(dataManager ?? DataManager(), resolveService, watchlistStore);

  DataProcessTool._(
    DataManager dataManager,
    MarketDataResolveService? resolveService,
    WatchlistStore? watchlistStore,
  ) : _watchlistStore = watchlistStore,
      _queryService = MarketDataQueryActionService(dataManager: dataManager),
      _resolveService =
          resolveService ?? MarketDataResolveService(dataManager: dataManager);

  @override
  String get name => 'DataProcess';

  @override
  String get description =>
      'Analyze financial data: technical indicators, statistics, summary, and preset strategy execution. For user-created/custom strategies, use MarketData custom_strategy_* actions instead.';

  @override
  String get prompt =>
      '''Process and analyze financial data. Use action="help" to discover all capabilities.

Key actions:
- **indicators** — Technical indicators (MA/RSI/MACD/BOLL/KDJ/ATR)
- **trend** — Trend detection + MA alignment + bias analysis
- **pattern** — K-line pattern recognition (锤子线/吞没/十字星/三连阳/一阳穿三阴等)
- **pattern_summary** — One-call K-line pattern synthesis with trend and indicators
- **support** — Support/resistance levels
- **support_summary** — One-call support/resistance synthesis with pivots and indicators
- **volume** — Volume analysis + price-volume divergence
- **stats** — Return statistics (volatility/Sharpe/maxDD/percentile)
- **screen** — Condition-based stock screening (requires codes)
- **fund_screen** — Fund screening (4433 rule / custom / manager)
- **fair_value** — Fair value estimation (PE median method). symbol required
- **signal_log** — Record or query trade signals
- **market_snapshot** — Get aggregated market regime snapshot
- **summary** — Complete analysis with signals and risks
- **ai_record** — Record analysis for later validation
- **ai_validate** — Validate past analyses against actual prices
- **strategy_execute** — Execute a preset strategy workflow with full reasoning chain; use symbols for bounded batch validation
- **strategy_list** — List available preset strategies. Do not use this to create or validate a user-authored custom StrategySpec; use MarketData(action:"custom_strategy_validate")
- **factors** — Alpha158 quantitative factors (vnpy/Qlib). symbol: "600519"
- **signals** — Multi-source signal aggregation. symbol: "600519"
- **watch_signal_check** — Evaluate structured watchlist signal rules from runtime watchlist state + canonical data rows
- **optimize** — Portfolio optimization. symbols (via MarketData kline first)
- **calendar** — Trading calendar
- **help** — List all actions''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': [
          'indicators',
          'advanced',
          'ichimoku',
          'pivot',
          'rsrs',
          'hurst',
          'golden',
          'trend',
          'pattern',
          'pattern_summary',
          'support',
          'support_summary',
          'volume',
          'stats',
          'screen',
          'fund_screen',
          'fair_value',
          'signal_log',
          'market_snapshot',
          'summary',
          'factors',
          'signals',
          'watch_signal_check',
          'score',
          'score_technical',
          'market_rules',
          'optimize',
          'ai_record',
          'ai_validate',
          'strategy_execute',
          'strategy_backtest',
          'strategy_list',
          'calendar',
          'help',
        ],
      },
      'symbol': {'type': 'string'},
      'period': {'type': 'string'},
      'startDate': {'type': 'string'},
      'endDate': {'type': 'string'},
      'conditions': {
        'type': 'array',
        'items': {'type': 'object'},
        'description': '(screen) [{field, op, value}]',
      },
      'codes': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '(screen) Stock codes to filter',
      },
      'weights': {
        'type': 'object',
        'description': '(screen) Scoring weights {factor: weight}',
      },
      'mode': {
        'type': 'string',
        'description': '(fund_screen) 4433/custom/manager',
      },
      'fund_type': {
        'type': 'string',
        'description': '(fund_screen) 股票型/混合型/债券型',
      },
      'signal': {'type': 'string', 'description': '(signal_log) buy/sell/hold'},
      'sortBy': {
        'type': 'string',
        'description':
            '(screen) Sort field: changePct/volume/amount/pe/pb/marketCap/turnoverRate',
      },
      'limit': {'type': 'integer'},
      'direction': {
        'type': 'string',
        'description': '(ai_record) bullish/bearish/neutral',
      },
      'priceAtAnalysis': {
        'type': 'number',
        'description': '(ai_record) Price when analysis was made',
      },
      'strategy': {
        'type': 'string',
        'description': '(ai_record) Strategy name or ID',
      },
      'strategyId': {
        'type': 'string',
        'description':
            '(strategy_execute/strategy_backtest) Strategy ID from strategy_list',
      },
      'pe': {'type': 'number', 'description': '(score) PE ratio'},
      'pb': {'type': 'number', 'description': '(score) PB ratio'},
      'roe': {'type': 'number', 'description': '(score) ROE %'},
      'market': {'type': 'string', 'description': '(market_rules) cn/hk/us'},
      'type': {
        'type': 'string',
        'description': '(watch_signal_check) stock/fund/etf; default fund',
      },
      'status': {
        'type': 'string',
        'description':
            '(watch_signal_check) watchlist status; default watching',
      },
      'symbols': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '(optimize/strategy_execute batch) Stock symbols list',
      },
      'method': {
        'type': 'string',
        'description':
            '(optimize) equalWeight/riskParity/maxSharpe/minVariance',
      },
      'maxWeight': {
        'type': 'number',
        'description': '(optimize) Max weight per asset (0-1, default 0.3)',
      },
      'persist': {
        'type': 'boolean',
        'description':
            '(indicators/factors) Default true. Set false for inspect-only local computation without canonical persistence.',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => true;
  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    final symbol = input['symbol'] as String?;

    try {
      return switch (action) {
        'help' => _help(toolUseId),
        'calendar' => _calendar(toolUseId),
        'indicators' => _requireSymbol(
          toolUseId,
          symbol,
          'indicators',
          () => _indicators(toolUseId, symbol!, input, context),
        ),
        'advanced' => _requireSymbol(
          toolUseId,
          symbol,
          'advanced',
          () => _advanced(toolUseId, symbol!, input),
        ),
        'ichimoku' => _requireSymbol(
          toolUseId,
          symbol,
          'ichimoku',
          () => _ichimoku(toolUseId, symbol!, input),
        ),
        'pivot' => _requireSymbol(
          toolUseId,
          symbol,
          'pivot',
          () => _pivot(toolUseId, symbol!, input),
        ),
        'rsrs' => _requireSymbol(
          toolUseId,
          symbol,
          'rsrs',
          () => _rsrs(toolUseId, symbol!, input),
        ),
        'hurst' => _requireSymbol(
          toolUseId,
          symbol,
          'hurst',
          () => _hurstAction(toolUseId, symbol!, input),
        ),
        'golden' => _requireSymbol(
          toolUseId,
          symbol,
          'golden',
          () => _golden(toolUseId, symbol!, input),
        ),
        'trend' => _requireSymbol(
          toolUseId,
          symbol,
          'trend',
          () => _trend(toolUseId, symbol!, input),
        ),
        'pattern' => _requireSymbol(
          toolUseId,
          symbol,
          'pattern',
          () => _pattern(toolUseId, symbol!, input),
        ),
        'pattern_summary' => _requireSymbol(
          toolUseId,
          symbol,
          'pattern_summary',
          () => _patternSummary(toolUseId, symbol!, input),
        ),
        'support' => _requireSymbol(
          toolUseId,
          symbol,
          'support',
          () => _support(toolUseId, symbol!, input),
        ),
        'support_summary' => _requireSymbol(
          toolUseId,
          symbol,
          'support_summary',
          () => _supportSummary(toolUseId, symbol!, input),
        ),
        'volume' => _requireSymbol(
          toolUseId,
          symbol,
          'volume',
          () => _volume(toolUseId, symbol!, input),
        ),
        'stats' => _requireSymbol(
          toolUseId,
          symbol,
          'stats',
          () => _stats(toolUseId, symbol!, input),
        ),
        'screen' => _screen(toolUseId, input, context),
        'fund_screen' => _fundScreen(toolUseId, input, context),
        'fair_value' => _fairValue(toolUseId, input),
        'signal_log' => _signalLog(toolUseId, input, context),
        'market_snapshot' => _marketSnapshotAction(toolUseId, context),
        'summary' => _requireSymbol(
          toolUseId,
          symbol,
          'summary',
          () => _summary(toolUseId, symbol!, input),
        ),
        'factors' => _requireSymbol(
          toolUseId,
          symbol,
          'factors',
          () => _factors(toolUseId, symbol!, input, context),
        ),
        'signals' => _requireSymbol(
          toolUseId,
          symbol,
          'signals',
          () => _signals(toolUseId, symbol!, input, context),
        ),
        'watch_signal_check' => _watchSignalCheck(toolUseId, input, context),
        'score' => _score(toolUseId, input),
        'score_technical' => _requireSymbol(
          toolUseId,
          symbol,
          'score_technical',
          () => _scoreTechnical(toolUseId, symbol!, input),
        ),
        'market_rules' => _marketRules(toolUseId, input),
        'optimize' => await _optimizePortfolio(toolUseId, input),
        'ai_record' => _requireSymbol(
          toolUseId,
          symbol,
          'ai_record',
          () => _aiRecord(toolUseId, symbol!, input, context),
        ),
        'ai_validate' => _aiValidate(toolUseId, context),
        'strategy_execute' => _strategyExecuteOrBatch(
          toolUseId,
          symbol,
          input,
          context,
        ),
        'strategy_backtest' => _requireSymbol(
          toolUseId,
          symbol,
          'strategy_backtest',
          () => _strategyBacktest(toolUseId, symbol!, input, context),
        ),
        'strategy_list' => _strategyList(toolUseId, context),
        _ => ToolResult(
          toolUseId: toolUseId,
          content: 'Unknown action "$action". Use action="help".',
          isError: true,
        ),
      };
    } catch (e) {
      return ToolResult(toolUseId: toolUseId, content: '$e', isError: true);
    }
  }

  Future<ToolResult> _requireSymbol(
    String id,
    String? symbol,
    String action,
    Future<ToolResult> Function() fn,
  ) {
    if (symbol == null || symbol.isEmpty) {
      final hint = action.startsWith('strategy')
          ? ' strategy_execute accepts symbol for one stock or symbols for a bounded batch after candidate discovery.'
          : '';
      return Future.value(
        ToolResult(
          toolUseId: id,
          content:
              'symbol required for $action. Example: DataProcess(action: "$action", symbol: "600519").$hint',
          isError: true,
        ),
      );
    }
    return fn();
  }

  ToolResult _help(String toolUseId) {
    return ToolResult(
      toolUseId: toolUseId,
      content: '''DataProcess actions:

TECHNICAL ANALYSIS (basic):
  indicators — MA/EMA/RSI/MACD/BOLL/KDJ/ATR. symbol: "600519"
  trend      — MA alignment, bias, trend direction
  pattern    — K-line patterns: 锤子/吞没/十字星/三连阳/早晨星/孕线/双顶底
  support    — Support/resistance levels
  volume     — Volume ratio, divergence, pattern

ADVANCED INDICATORS:
  advanced  — All indicators in one call (basic + CCI/MFI/ADX/SAR/OBV/VWAP/Stoch + TSI/Vortex/Hurst)
  ichimoku  — Ichimoku Cloud (转换线/基准线/云带/先行/迟行). symbol: "600519"
  pivot     — Pivot Points (Standard/Fibonacci/Demark 三种). symbol: "600519"
  rsrs      — RSRS 择时指标 (阻力支撑相对强度, A股特色). symbol: "600519"
  hurst     — Hurst 指数 (趋势/均值回归/随机 判断). symbol: "600519"
  golden    — 黄金分割价位 (0.236/0.382/0.5/0.618/0.786). symbol: "600519"

QUANTITATIVE:
  factors   — Alpha158 量化因子 (158+因子, 来自vnpy/Qlib). symbol: "600519"
  signals   — 多源信号聚合 (RSI/MACD/KDJ/MA/Volume/ADX). symbol: "600519"
  watch_signal_check — 观察池信号检查. Uses runtime WatchlistStore plus canonical fund NAV / money-yield rows. type:"fund"
  stats     — 收益统计: 波动率/Sharpe/最大回撤/百分位

FUNDAMENTAL:
  score        — 基本面评分 (PE/PB/ROE→买入/观望/回避). pe:15, pb:2
  market_rules — 市场规则 (A股/港股/美股交易制度). market: "cn"

SCREENING:
  screen — 条件选股. conditions: [{"field":"changePct","op":">","value":5}]
  fund_screen — 基金筛选. Uses cached fund_performance_metrics when available. mode:"4433", limit:3-20

PORTFOLIO:
  optimize — 组合优化 (等权/风险平价/最大夏普/最小方差). symbols:["600519","000858"], method:"riskParity"

COMPREHENSIVE:
  summary — 完整分析摘要 (指标+趋势+形态+量价+信号/风险)

AI VALIDATION:
  ai_record   — 记录分析预测 (事后验证). symbol, direction, priceAtAnalysis
  ai_validate — 验证历史预测准确率

STRATEGY:
  strategy_list     — 列出所有策略
  strategy_execute  — 执行预设策略(产出完整推理链). symbol, strategyId
  strategy_backtest — 预设策略历史回测. symbol, strategyId, limit(天数)
  custom strategies — 用户自定义策略创建/验证/回测请用 MarketData(action:"custom_strategy_validate"|"custom_strategy_backtest")，不要用 DataProcess 预设策略动作

UTILITY:
  calendar — 交易日历 (是否开市/最近交易日)
  help     — 本帮助''',
    );
  }

  ToolResult _calendar(String toolUseId) {
    final now = DateTime.now();
    final isOpen = TradingCalendar.isMarketOpen();
    final isTrading = TradingCalendar.isTradingDay(now);
    final lastDays = TradingCalendar.lastTradingDays(now, 5)
        .map(
          (d) =>
              '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}',
        )
        .toList();
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'now': now.toIso8601String(),
        'isTradingDay': isTrading,
        'isMarketOpen': isOpen,
        'last5TradingDays': lastDays,
      }),
    );
  }

  Future<List<KlineBar>> _getBars(
    String symbol,
    Map<String, dynamic> input, {
    ToolContext? context,
  }) async {
    _validateDateInput(input, 'startDate');
    _validateDateInput(input, 'endDate');
    final r = await _resolveService.resolveKline(
      symbol,
      context: context,
      period: input['period'] as String? ?? 'daily',
      startDate: input['startDate'] as String? ?? _sixMonthsAgo(),
      endDate: input['endDate'] as String? ?? '',
    );
    return r.bars;
  }

  Future<({List<KlineBar> bars, String source})> _resolveBars(
    String symbol,
    Map<String, dynamic> input,
  ) async {
    _validateDateInput(input, 'startDate');
    _validateDateInput(input, 'endDate');
    return _resolveService.resolveKline(
      symbol,
      period: input['period'] as String? ?? 'daily',
      startDate: input['startDate'] as String? ?? _sixMonthsAgo(),
      endDate: input['endDate'] as String? ?? '',
    );
  }

  void _validateDateInput(Map<String, dynamic> input, String key) {
    final value = input[key];
    if (value == null) return;
    if (value is! String) {
      throw ArgumentError('$key must be a YYYY-MM-DD string');
    }
    if (value.isEmpty) return;
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw ArgumentError(
        '$key must be a clean YYYY-MM-DD value, got "$value". Remove commentary or hidden text from the argument and retry.',
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || parsed.toIso8601String().substring(0, 10) != value) {
      throw ArgumentError('$key is not a valid calendar date: "$value"');
    }
  }

  Future<ToolResult> _trend(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    final trend = TrendAnalysis.trendDetection(bars);
    final bias = TrendAnalysis.biasAnalysis(bars);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'bars': bars.length,
        ...trend,
        'bias': bias,
      }),
    );
  }

  Future<ToolResult> _pattern(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    final patterns = PatternRecognition.detect(bars);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'patterns': patterns,
        'note': patterns.isEmpty
            ? 'No significant patterns detected in recent bars'
            : '${patterns.length} pattern(s) detected',
      }),
    );
  }

  Future<ToolResult> _patternSummary(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final resolved = await _resolveBars(symbol, input);
    final bars = resolved.bars;
    if (bars.length < 5) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Need 5+ bars for pattern_summary',
        isError: true,
      );
    }
    final patterns = PatternRecognition.detect(bars);
    final indicators = Indicators.summary(bars);
    final trend = TrendAnalysis.trendDetection(bars);
    final bias = TrendAnalysis.biasAnalysis(bars);
    final recent = bars.length > 5 ? bars.sublist(bars.length - 5) : bars;
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'bars': bars.length,
        'source': resolved.source,
        'range': '${bars.first.date} ~ ${bars.last.date}',
        'latestDate': bars.last.date,
        'latestOhlc': bars.last.toJson(),
        'recent5': recent.map((row) => row.toJson()).toList(),
        'patterns': patterns,
        'patternCount': patterns.length,
        'note': patterns.isEmpty
            ? 'No significant K-line pattern detected in the latest bars. Do not invent patterns; explain the limitation.'
            : '${patterns.length} pattern(s) detected by code-owned pattern recognition.',
        'trend': trend,
        'bias': bias,
        'indicators': indicators,
        'usage':
            'Use this as the bounded evidence set for K-line pattern answers before adding separate pattern, trend, indicators, support, or live fetch calls.',
      }),
    );
  }

  Future<ToolResult> _support(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    final sr = TrendAnalysis.supportResistance(bars);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert({'symbol': symbol, ...sr}),
    );
  }

  Future<ToolResult> _supportSummary(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final resolved = await _resolveBars(symbol, input);
    final bars = resolved.bars;
    if (bars.length < 2) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Need 2+ bars for support_summary',
        isError: true,
      );
    }
    final support = TrendAnalysis.supportResistance(bars);
    final indicators = Indicators.summary(bars);
    final previous = bars[bars.length - 2];
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'bars': bars.length,
        'source': resolved.source,
        'range': '${bars.first.date} ~ ${bars.last.date}',
        'latestDate': bars.last.date,
        'latestClose': bars.last.close,
        'supportResistance': support,
        'pivot': {
          'standard': AdvancedIndicators.pivotPoints(previous),
          'fibonacci': AdvancedIndicators.fibonacciPivot(previous),
          'demark': AdvancedIndicators.demarkPivot(previous),
        },
        'indicators': indicators,
        'analysisEvidence': _supportSummaryAnalysisEvidence(
          symbol: symbol,
          bars: bars,
          source: resolved.source,
          support: support,
        ),
        'usage':
            'Use this as the bounded evidence set for support/resistance answers before adding separate indicators, pivot, or volume calls.',
      }),
    );
  }

  Map<String, dynamic> _supportSummaryAnalysisEvidence({
    required String symbol,
    required List<KlineBar> bars,
    required String source,
    required Map<String, dynamic> support,
  }) {
    final cacheHit = source.startsWith('local ');
    final nearestSupport = support['nearestSupport'];
    final nearestResistance = support['nearestResistance'];
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.stock,
      subjectType: AnalysisSubjectType.stock,
      subjectId: symbol,
      observedFacts: [
        'bars=${bars.length}',
        'latestDate=${bars.last.date}',
        'latestClose=${bars.last.close}',
        'source=$source',
        if (nearestSupport != null) 'nearestSupport=$nearestSupport',
        if (nearestResistance != null) 'nearestResistance=$nearestResistance',
      ],
      interpretations: [
        'support_resistance:bounded_summary',
        nearestSupport == null
            ? 'support:missing_nearest'
            : 'support:nearest_available',
        nearestResistance == null
            ? 'resistance:missing_nearest'
            : 'resistance:nearest_available',
      ],
      missingEvidence: const [
        'fundamental_valuation',
        'money_flow',
        'news_context',
        'strategy_validation',
      ],
      confidence: bars.length >= 60
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [source],
        interfaceId: 'stock.daily_kline',
        capabilityId: cacheHit ? 'local.cache' : '$source.stock.daily_kline',
        canonicalSchema: 'kline_daily',
        canonicalTable: 'kline_daily',
        readbackAction: 'query_kline',
        sourceDataTime: bars.last.date,
        cacheStatus: cacheHit ? 'cache-hit' : 'provider-hit',
        coverageStatus: bars.length >= 60
            ? AnalysisCoverageStatus.sufficientForTechnical
            : AnalysisCoverageStatus.partial,
      ),
    ).toJson();
  }

  Future<ToolResult> _volume(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final resolved = await _resolveBars(symbol, input);
    final bars = resolved.bars;
    final vol = TrendAnalysis.volumeAnalysis(bars);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'volume',
        'symbol': symbol,
        'bars': bars.length,
        'source': resolved.source,
        'range': '${bars.first.date} ~ ${bars.last.date}',
        'latestDate': bars.last.date,
        ...vol,
        'analysisEvidence': _volumeAnalysisEvidence(
          symbol: symbol,
          bars: bars,
          source: resolved.source,
          volume: vol,
        ),
        'usage':
            'Use this as volume/price-volume analysis evidence only. Do not treat it as a validated strategy, watchlist rule, or trade instruction.',
      }),
    );
  }

  Map<String, dynamic> _volumeAnalysisEvidence({
    required String symbol,
    required List<KlineBar> bars,
    required String source,
    required Map<String, dynamic> volume,
  }) {
    final cacheHit = source.startsWith('local ');
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.stock,
      subjectType: AnalysisSubjectType.stock,
      subjectId: symbol,
      observedFacts: [
        'bars=${bars.length}',
        'latestDate=${bars.last.date}',
        'latestVolume=${bars.last.volume}',
        'source=$source',
        ...volume.entries.take(6).map((entry) => '${entry.key}=${entry.value}'),
      ],
      interpretations: [
        'volume:bounded_analysis',
        'price_volume:requires_price_context',
      ],
      missingEvidence: const [
        'fundamental_valuation',
        'money_flow',
        'news_context',
        'strategy_validation',
      ],
      confidence: bars.length >= 60
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [source],
        interfaceId: 'stock.daily_kline',
        capabilityId: cacheHit ? 'local.cache' : '$source.stock.daily_kline',
        canonicalSchema: 'kline_daily',
        canonicalTable: 'kline_daily',
        readbackAction: 'query_kline',
        sourceDataTime: bars.last.date,
        cacheStatus: cacheHit ? 'cache-hit' : 'provider-hit',
        coverageStatus: bars.length >= 60
            ? AnalysisCoverageStatus.sufficientForTechnical
            : AnalysisCoverageStatus.partial,
      ),
    ).toJson();
  }

  Future<ToolResult> _stats(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    final stats = Statistics.returnStats(bars);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert({'symbol': symbol, ...stats}),
    );
  }

  Future<ToolResult> _screen(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final conditionsJson = input['conditions'] as List<dynamic>? ?? [];
    final conditions = conditionsJson
        .map((c) => ScreenCondition.fromJson(c as Map<String, dynamic>))
        .toList();
    final sortBy = input['sortBy'] as String?;
    final limit = (input['limit'] as num?)?.toInt() ?? 20;
    final weightsJson = input['weights'] as Map<String, dynamic>?;
    final codesInput = input['codes'] as List<dynamic>?;

    if (codesInput == null || codesInput.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'codes required for screen action. First get codes from a sector or provide specific stocks.\n'
            'Example: DataProcess(action:"screen", codes:["600519","000858","601318"], conditions:[{"field":"pe","op":"<","value":30}])\n'
            'Tip: Use MarketData(action:"sector") to get sector stocks first, then screen them.',
        isError: true,
      );
    }
    final codeList = codesInput.map((c) => c.toString()).toList();

    final r = await _resolveService.resolveQuotes(
      codeList,
      context: context,
      policy: const CachePolicy(
        mode: CachePolicyMode.cacheOnly,
        quoteMaxAge: Duration(days: 7),
      ),
    );
    final quotes = r.data;
    if (quotes.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Failed to fetch market data. Check network connection.',
        isError: true,
      );
    }

    List<Map<String, dynamic>> results;

    if (weightsJson != null) {
      // Scoring mode
      final weights = weightsJson.map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );
      final scored = StockScreener.screenWithScore(
        quotes,
        conditions,
        weights: weights,
        sortBy: sortBy,
        limit: limit,
      );
      results = scored.map((d) {
        final m = <String, dynamic>{
          'code': d.quote.code,
          'name': d.quote.name,
          'price': d.quote.price,
          'changePct': d.quote.changePct,
        };
        if (d.quote.pe != null) m['pe'] = d.quote.pe;
        if (d.quote.pb != null) m['pb'] = d.quote.pb;
        if (d.quote.marketCap != null)
          m['marketCap'] = (d.quote.marketCap! / 1e8).toStringAsFixed(1);
        if (d.compositeScore != null) m['score'] = d.compositeScore;
        return m;
      }).toList();
    } else {
      // Simple filter mode
      final filtered = StockScreener.screen(
        quotes,
        conditions,
        sortBy: sortBy,
        limit: limit,
      );
      results = filtered.map((q) {
        final m = <String, dynamic>{
          'code': q.code,
          'name': q.name,
          'price': q.price,
          'changePct': q.changePct,
        };
        if (q.pe != null) m['pe'] = q.pe;
        if (q.pb != null) m['pb'] = q.pb;
        if (q.marketCap != null)
          m['marketCap'] = (q.marketCap! / 1e8).toStringAsFixed(1);
        if (q.turnoverRate != null) m['turnoverRate'] = q.turnoverRate;
        return m;
      }).toList();
    }

    if (results.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'No stocks match the given conditions (from ${quotes.length} stocks).',
      );
    }

    final buf = StringBuffer(
      'Screened ${results.length} from ${quotes.length} stocks:\n',
    );
    for (final r in results) {
      buf.write('${r['code']} ${r['name']} ¥${r['price']}');
      if (r.containsKey('score')) buf.write(' score:${r['score']}');
      if (r.containsKey('pe')) buf.write(' PE:${r['pe']}');
      if (r.containsKey('changePct')) buf.write(' ${r['changePct']}%');
      buf.writeln();
    }
    final payload = {
      'action': 'screen',
      'mode': weightsJson != null ? 'scored' : 'filtered',
      'requested': codeList,
      'evaluated': quotes.length,
      'count': results.length,
      'conditions': conditionsJson,
      'results': results,
      'summary': buf.toString().trim(),
      'analysisEvidence': _screenAnalysisEvidence(
        requested: codeList,
        evaluated: quotes.length,
        results: results,
        source: r.source,
        weighted: weightsJson != null,
      ),
      'usage':
          'Use results and analysisEvidence as candidate-research evidence only. Do not treat screen output as a validated strategy, watchlist mutation, or trade instruction.',
    };
    if (sortBy != null) payload['sortBy'] = sortBy;
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Map<String, dynamic> _screenAnalysisEvidence({
    required List<String> requested,
    required int evaluated,
    required List<Map<String, dynamic>> results,
    required String source,
    required bool weighted,
  }) {
    final top = results.take(3).map((row) => '${row['code']}').join(',');
    final cacheHit = source.startsWith('local ');
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.candidateResearch,
      subjectType: AnalysisSubjectType.candidateSet,
      subjectId: 'stock_screen:${requested.take(8).join(",")}',
      subjectName: 'stock screen candidate set',
      observedFacts: [
        'requested=${requested.length}',
        'evaluated=$evaluated',
        'matched=${results.length}',
        'mode=${weighted ? 'scored' : 'filtered'}',
        if (top.isNotEmpty) 'top=$top',
      ],
      interpretations: [
        results.isEmpty ? 'screen:no_matches' : 'screen:candidates_returned',
        weighted ? 'screen:weighted_score' : 'screen:condition_filter',
      ],
      missingEvidence: const [
        'fundamental_valuation_if_not_in_quote',
        'money_flow',
        'news_context',
        'strategy_validation',
      ],
      confidence: results.isEmpty
          ? AnalysisConfidence.low
          : evaluated >= requested.length
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.candidate,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [source],
        interfaceId: 'stock.quote',
        capabilityId: cacheHit ? 'local.cache' : '$source.stock.quote',
        canonicalSchema: 'quote_snapshot',
        canonicalTable: 'quote_snapshot',
        readbackAction: 'query_quote',
        cacheStatus: cacheHit ? 'cache-hit' : 'provider-hit',
        coverageStatus: evaluated >= requested.length
            ? AnalysisCoverageStatus.sufficientForAnalysis
            : AnalysisCoverageStatus.partial,
      ),
    ).toJson();
  }

  Future<ToolResult> _fairValue(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final symbol = input['symbol'] as String? ?? '';
    if (symbol.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'symbol required for fair_value',
        isError: true,
      );
    }

    // Get historical kline for PE distribution
    final klineResult = await _resolveService.resolveKline(
      symbol,
      startDate: _yearsAgo(5),
    );
    final bars = klineResult.bars;
    if (bars.length < 100) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Not enough historical data for fair value (${bars.length} bars)',
        isError: true,
      );
    }

    final currentPrice = bars.last.close;
    // Estimate EPS from PE and price (PE = price / EPS → EPS = price / PE)
    final quoteResult = await _resolveService.resolveQuotes([symbol]);
    final pe = quoteResult.data.isNotEmpty ? quoteResult.data.first.pe : null;
    if (pe == null || pe <= 0) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'PE data unavailable for $symbol, cannot estimate fair value',
        isError: true,
      );
    }

    final eps = currentPrice / pe;
    final growthRate = 0.1; // default 10% — ideally from fundamentals

    // Build PE history from price series
    final peHistory = <double>[];
    for (
      var i = 0;
      i < bars.length;
      i += (bars.length ~/ 200).clamp(1, 10).toInt()
    ) {
      final historicalPe = bars[i].close / eps;
      if (historicalPe > 0 && historicalPe < 200) peHistory.add(historicalPe);
    }

    final result = StockScreener.fairValue(
      currentPrice: currentPrice,
      eps: eps,
      growthRate: growthRate,
      peHistory: peHistory,
    );

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(result),
    );
  }

  Future<ToolResult> _fundScreen(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final mode = input['mode'] as String? ?? '4433';
    final limit = (input['limit'] as num?)?.toInt().clamp(1, 50) ?? 20;
    final store = ReusableDataStore(context.basePath);
    final rows = store
        .queryFundPerformanceMetrics(limit: 30000)
        .map(_fundPerformanceScreenRow)
        .where(_isUsableFundPerformanceRow)
        .toList(growable: false);
    if (rows.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: const JsonEncoder.withIndent('  ').convert({
          'action': 'fund_screen',
          'mode': '4433',
          'interfaceId': 'fund.performance_metrics',
          'provider': 'local',
          'cacheStatus': 'miss',
          'canonicalSchema': 'fund_performance_metrics',
          'candidates': [],
          'nextAction':
              'Run MarketData(action:"fund_performance") once, then retry DataProcess(action:"fund_screen").',
        }),
      );
    }

    final screened = mode == 'custom'
        ? FundScreener.screenCustom(
            rows,
            (input['conditions'] as List?)
                    ?.whereType<Map>()
                    .map((row) => Map<String, dynamic>.from(row))
                    .toList(growable: false) ??
                const [],
            sortBy: input['sortBy'] as String?,
            limit: limit,
          )
        : FundScreener.screen4433(rows, limit: limit);

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'fund_screen',
        'mode': mode,
        'interfaceId': 'fund.performance_metrics',
        'provider': 'local',
        'capabilityId': 'local.cache',
        'cacheStatus': 'cache-hit',
        'canonicalSchema': 'fund_performance_metrics',
        'canonicalTable': 'fund_performance_metrics',
        'sourceDataTime': rows.first['metric_date'],
        'fetchedAt': rows.first['fetched_at'],
        'source': 'local fund_performance_metrics',
        'rowsConsidered': rows.length,
        'count': screened.length,
        'candidates': screened.take(limit).toList(growable: false),
        'limitations': [
          '4433 screening uses available return_1y/return_2y/return_3y/return_ytd/return_6m/return_3m fields.',
          'Fund scale, fee, drawdown, manager tenure, and holdings must be checked before buy or定投 decisions.',
          'Money funds should use fund_money_yield rather than ordinary NAV/performance screening.',
        ],
      }),
    );
  }

  Map<String, dynamic> _fundPerformanceScreenRow(Map<String, dynamic> row) {
    final raw = row['raw_json'];
    Map<String, dynamic> rawMap = const {};
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) rawMap = decoded;
      } catch (_) {
        rawMap = const {};
      }
    }
    return {
      ...row,
      'code': '${row['code'] ?? rawMap['code'] ?? ''}',
      'name': '${row['name'] ?? rawMap['name'] ?? ''}',
      'return_1y': _screenNum(row['return_1y'] ?? rawMap['return_1y']),
      'return_2y': _screenNum(row['return_2y'] ?? rawMap['return_2y']),
      'return_3y': _screenNum(row['return_3y'] ?? rawMap['return_3y']),
      'return_5y': _screenNum(row['return_5y'] ?? rawMap['return_5y']),
      'return_ytd': _screenNum(row['return_ytd'] ?? rawMap['return_ytd']),
      'return_6m': _screenNum(row['return_6m'] ?? rawMap['return_6m']),
      'return_3m': _screenNum(row['return_3m'] ?? rawMap['return_3m']),
      'nav': _screenNum(row['nav'] ?? rawMap['nav']),
    };
  }

  bool _isUsableFundPerformanceRow(Map<String, dynamic> row) {
    final code = '${row['code'] ?? ''}'.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;
    final hasName = '${row['name'] ?? ''}'.trim().isNotEmpty;
    final hasReturn = [
      row['return_1y'],
      row['return_2y'],
      row['return_3y'],
      row['return_ytd'],
      row['return_6m'],
      row['return_3m'],
    ].any((value) => value is num);
    return hasName && hasReturn;
  }

  double? _screenNum(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty || text == '-' || text.toLowerCase() == 'null') {
      return null;
    }
    return double.tryParse(text.replaceAll('%', ''));
  }

  Future<ToolResult> _signalLog(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final journal = SignalJournal(context.basePath);
    final subAction = input['signal'] as String?;

    if (subAction == 'stats') {
      final s = journal.stats();
      return ToolResult(
        toolUseId: toolUseId,
        content: const JsonEncoder.withIndent('  ').convert(s),
      );
    }

    if (subAction == 'recent' || subAction == null) {
      final code = input['symbol'] as String?;
      final recent = journal.recent(limit: 20, code: code);
      if (recent.isEmpty) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'No signals recorded yet.',
        );
      }
      final buf = StringBuffer('Recent signals:\n');
      for (final s in recent) {
        buf.writeln(
          '${s['date']} ${s['code']} ${s['signal']} @${s['price']} [${s['strategy']}] ${s['reason'] ?? ''}',
        );
        if (s['outcome'] != null) {
          buf.writeln('  → outcome: ${s['outcome']['return_pct']}%');
        }
      }
      return ToolResult(toolUseId: toolUseId, content: buf.toString());
    }

    final code = input['symbol'] as String? ?? '';
    final price = (input['priceAtAnalysis'] as num?)?.toDouble() ?? 0;
    if (code.isEmpty || price <= 0) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'To record signal: signal_log with symbol, signal (buy/sell), priceAtAnalysis, strategy',
        isError: true,
      );
    }

    journal.record(
      code: code,
      name: input['name'] as String? ?? code,
      signal: subAction,
      strategy: input['strategy'] as String? ?? 'manual',
      price: price,
      reason: input['reason'] as String?,
    );
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Signal recorded: $subAction $code @$price',
    );
  }

  Future<ToolResult> _marketSnapshotAction(
    String toolUseId,
    ToolContext context,
  ) async {
    final snapshot = MarketSnapshot(context.basePath);
    final existing = snapshot.load();
    if (existing != null) {
      final ts = existing['timestamp'] as String? ?? '';
      final today = DateTime.now().toIso8601String().substring(0, 10);
      if (ts.startsWith(today)) {
        final enriched = snapshot.withAnalysisEvidence(existing);
        return ToolResult(
          toolUseId: toolUseId,
          content: const JsonEncoder.withIndent('  ').convert({
            'action': 'market_snapshot',
            'status': 'loaded',
            'snapshot': enriched,
            'analysisEvidence': enriched['analysisEvidence'],
            'usage':
                'Use this as market-analysis evidence only. Do not treat it as a validated strategy, monitor rule, or trade instruction.',
          }),
        );
      }
    }

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'No recent market snapshot. To build one, use MarketData to get sector/limit_up/limit_down/northbound data, '
          'then I can aggregate it into a snapshot.\n'
          'Or ask: "市场现在什么状况？" — I will gather the data automatically.',
    );
  }

  Future<ToolResult> _advanced(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    if (bars.length < 30)
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Need 30+ bars',
        isError: true,
      );
    final result = Indicators.extendedSummary(bars);
    result['symbol'] = symbol;
    result['bars'] = bars.length;
    // Add advanced indicators
    final h = AdvancedIndicators.hurst(bars);
    if (h != null) result['hurst'] = double.parse(h.toStringAsFixed(3));
    result['shift_distance'] = double.parse(
      AdvancedIndicators.shiftDistance(bars).toStringAsFixed(3),
    );
    final tsiVals = AdvancedIndicators.tsi(bars);
    final last = bars.length - 1;
    if (tsiVals[last] != null)
      result['tsi'] = double.parse(tsiVals[last]!.toStringAsFixed(2));
    final vortex = AdvancedIndicators.vortex(bars);
    if (vortex.vip[last] != null) {
      result['vortex_plus'] = double.parse(
        vortex.vip[last]!.toStringAsFixed(3),
      );
      result['vortex_minus'] = double.parse(
        vortex.vim[last]!.toStringAsFixed(3),
      );
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(result),
    );
  }

  Future<ToolResult> _ichimoku(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    final ich = AdvancedIndicators.ichimoku(bars);
    final last = bars.length - 1;
    final price = bars[last].close;
    final cloudTop = [ich.spanA[last], ich.spanB[last]]
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null ? b : (a > b ? a : b));
    final cloudBottom = [ich.spanA[last], ich.spanB[last]]
        .whereType<double>()
        .fold<double?>(null, (a, b) => a == null ? b : (a < b ? a : b));
    String? position;
    if (cloudTop != null && cloudBottom != null) {
      position = price > cloudTop
          ? 'above_cloud'
          : price < cloudBottom
          ? 'below_cloud'
          : 'in_cloud';
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'tenkan': ich.tenkan[last],
        'kijun': ich.kijun[last],
        'spanA': ich.spanA[last],
        'spanB': ich.spanB[last],
        'chikou': ich.chikou[last],
        'cloudTop': cloudTop,
        'cloudBottom': cloudBottom,
        'position': position,
      }),
    );
  }

  Future<ToolResult> _pivot(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    if (bars.length < 2)
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Need 2+ bars',
        isError: true,
      );
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'standard': AdvancedIndicators.pivotPoints(bars[bars.length - 2]),
        'fibonacci': AdvancedIndicators.fibonacciPivot(bars[bars.length - 2]),
        'demark': AdvancedIndicators.demarkPivot(bars[bars.length - 2]),
      }),
    );
  }

  Future<ToolResult> _rsrs(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final r = await _resolveService.resolveKline(
      symbol,
      startDate: _yearsAgo(3),
    );
    final bars = r.bars;
    final rsrs = AdvancedIndicators.rsrs(bars);
    final last = bars.length - 1;
    String? signal;
    if (rsrs.score[last] != null) {
      if (rsrs.score[last]! > 0.7) {
        signal = 'bullish';
      } else if (rsrs.score[last]! < -1.4)
        signal = 'bearish';
      else
        signal = 'neutral';
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'bars': bars.length,
        'score': rsrs.score[last],
        'slope': rsrs.slope[last],
        'rsq': rsrs.rsq[last],
        'signal': signal,
      }),
    );
  }

  Future<ToolResult> _hurstAction(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    final h = AdvancedIndicators.hurst(bars);
    String? regime;
    if (h != null) {
      regime = h < 0.5
          ? 'mean_reverting'
          : h > 0.5
          ? 'trending'
          : 'random_walk';
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'hurst': h,
        'regime': regime,
        'note': 'H<0.5=均值回归(用反转策略), H=0.5=随机游走, H>0.5=趋势(用趋势跟踪策略)',
      }),
    );
  }

  Future<ToolResult> _golden(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    final levels = AdvancedIndicators.goldenLevels(bars);
    levels['currentPrice'] = bars.last.close;
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert({'symbol': symbol, ...levels}),
    );
  }

  String _yearsAgo(int years) {
    final d = DateTime.now().subtract(Duration(days: 365 * years));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  ToolResult _score(String toolUseId, Map<String, dynamic> input) {
    final pe = (input['pe'] as num?)?.toDouble();
    final pb = (input['pb'] as num?)?.toDouble();
    if (pe == null || pb == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'pe and pb required. Example: DataProcess(action:"score", pe:15.5, pb:2.1, roe:18.5)',
        isError: true,
      );
    }
    final result = FundamentalScorer.score(
      pe: pe,
      pb: pb,
      roe: (input['roe'] as num?)?.toDouble(),
      netMargin: (input['netMargin'] as num?)?.toDouble(),
      debtRatio: (input['debtRatio'] as num?)?.toDouble(),
      revenueGrowth: (input['revenueGrowth'] as num?)?.toDouble(),
      industry: input['industry'] as String?,
      board: input['board'] as String?,
    );
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(result),
    );
  }

  Future<ToolResult> _scoreTechnical(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final bars = await _getBars(symbol, input);
    if (bars.length < 30)
      return ToolResult(
        toolUseId: toolUseId,
        content: 'need 30+ bars',
        isError: true,
      );
    final result = Indicators.technicalScore(bars);
    result['symbol'] = symbol;
    result['bars'] = bars.length;
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(result),
    );
  }

  ToolResult _marketRules(String toolUseId, Map<String, dynamic> input) {
    final market = input['market'] as String? ?? 'cn';
    final rules = FundamentalScorer.getMarketRules(market);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(rules),
    );
  }

  Future<ToolResult> _factors(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final bars = await _getBars(symbol, input);
    if (bars.length < 61) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'need 61+ bars for Alpha158 factors (got ${bars.length})',
        isError: true,
      );
    }
    final factors = AlphaFactors.summary(bars);
    final persisted = input['persist'] == false
        ? null
        : _persistAlphaFactors(context, symbol, bars, factors, input);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'symbol': symbol,
        'bars': bars.length,
        ...factors,
        'interfaceId': 'stock.alpha_factors',
        'canonicalSchema': 'alpha_factor',
        'canonicalTable': 'alpha_factor',
        'provider': 'local',
        'capabilityId': 'local.stock.alpha_factors',
        'cacheStatus': 'provider-hit',
        'persistencePolicy': input['persist'] == false
            ? 'inspect-only'
            : 'canonical',
        // ignore: use_null_aware_elements
        if (persisted != null) 'ingestion': persisted,
        'sourceDataTime': bars.last.date,
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );
  }

  Map<String, dynamic>? _persistAlphaFactors(
    ToolContext context,
    String symbol,
    List<KlineBar> bars,
    Map<String, dynamic> summary,
    Map<String, dynamic> input,
  ) {
    if (context.basePath.isEmpty) return null;
    final factorMap = summary['factors'];
    if (factorMap is! Map) return null;
    final sourceDate = bars.last.date;
    final params = {'period': input['period'] ?? 'daily', 'bars': bars.length};
    final rows = <Map<String, dynamic>>[];
    for (final entry in factorMap.entries) {
      rows.add({
        'provider': 'local',
        'capability_id': 'local.stock.alpha_factors',
        'source_action': 'DataProcess.factors',
        'symbol': symbol,
        'factor_name': '${entry.key}',
        'source_date': sourceDate,
        'value': entry.value,
        'bars': bars.length,
        'params': params,
      });
    }
    return ReusableDataStore(
      context.basePath,
    ).saveAlphaFactors(rows, source: 'local');
  }

  Future<ToolResult> _signals(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    if (_isStockOnlySignalActionForFund(context, symbol)) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'DataProcess(action:"signals") is stock/K-line analysis, but $symbol is a known fund code in fund_list. For fund watchlist signal checks use DataProcess(action:"watch_signal_check", type:"fund", status:"watching"). For fund analysis use query_fund_nav, query_fund_money_yield, query_fund_performance, or query_fund_holding.',
        isError: true,
      );
    }
    final bars = await _getBars(symbol, input, context: context);
    final signals = SignalGenerator.fromIndicators(symbol, bars);
    final aggregated = SignalGenerator.aggregate(signals);
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent(
        '  ',
      ).convert({'symbol': symbol, 'bars': bars.length, ...aggregated}),
    );
  }

  bool _isStockOnlySignalActionForFund(ToolContext context, String rawCode) {
    final normalized = rawCode.trim().toUpperCase();
    final hasFundMarker =
        normalized.endsWith('.OF') || normalized.startsWith('FUND:');
    final match = RegExp(r'\d{6}').firstMatch(rawCode);
    if (match == null) return false;
    final code = match.group(0)!;
    if (!hasFundMarker && coreCnMarketIndexCodeSet.contains(code)) {
      return false;
    }
    try {
      final store = ReusableDataStore(context.basePath);
      final isKnownFund = store
          .queryFundList(codes: [code], limit: 1)
          .isNotEmpty;
      if (!isKnownFund) return false;
      if (hasFundMarker) return true;
      return store.queryKline(code, limit: 1).isEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<ToolResult> _watchSignalCheck(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final requestedType = (input['type'] as String? ?? 'fund').toLowerCase();
    final status = input['status'] as String? ?? 'watching';
    final limit = ((input['limit'] as num?)?.toInt() ?? 20).clamp(1, 100);
    final watchlistStore = _watchlistStore;
    if (watchlistStore == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'WatchlistStore is not attached to DataProcess; watch_signal_check cannot evaluate runtime watchlist state.',
        isError: true,
      );
    }
    final items = watchlistStore.items
        .where((item) => item.type.toLowerCase() == requestedType)
        .where((item) => item.status == status)
        .take(limit)
        .toList();
    if (items.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'No $requestedType watchlist items with status $status. Use Watchlist(action:"list", type:"$requestedType", status:"$status") to inspect current watch state.',
        isError: true,
      );
    }

    final store = ReusableDataStore(context.basePath);
    final results = <Map<String, dynamic>>[];
    final gaps = <String>[];
    for (final item in items) {
      final symbol = _normalizeWatchSymbol(item.symbol);
      if (symbol.isEmpty) {
        gaps.add('${item.id}: symbol missing');
        continue;
      }
      final type = item.type.toLowerCase();
      if (type == 'fund' || type == 'etf') {
        final evidence = _fundWatchSignalEvidence(symbol, store, context);
        results.add(_evaluateWatchItem(item, evidence.copyWith(type: type)));
      } else {
        results.add({
          'itemId': item.id,
          'symbol': symbol,
          'name': item.name.isEmpty ? symbol : item.name,
          'type': type,
          'status': 'unsupported',
          'triggered': false,
          'unsupportedRules': ['unsupported watchlist type $type'],
        });
      }
    }
    final analysisEvidence = _watchSignalAnalysisEvidence(
      requestedType: requestedType,
      status: status,
      results: results,
      gaps: gaps,
    );
    final payload = {
      'action': 'watch_signal_check',
      'type': requestedType,
      'status': status,
      'count': results.length,
      'results': results,
      'gaps': gaps,
      'usage':
          'Use this structured result for watchlist signal answers. Do not run Script or parse entryCondition text to invent unsupported rule execution.',
    };
    if (analysisEvidence != null) {
      payload['analysisEvidence'] = analysisEvidence;
    }
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(payload),
    );
  }

  Map<String, dynamic>? _watchSignalAnalysisEvidence({
    required String requestedType,
    required String status,
    required List<Map<String, dynamic>> results,
    required List<String> gaps,
  }) {
    if (requestedType != 'fund' && requestedType != 'etf') return null;
    final triggeredCount = results
        .where((row) => row['triggered'] == true)
        .length;
    final noEvidenceCount = results
        .where((row) => row['status'] == 'no_evidence')
        .length;
    final unsupportedCount = results.where((row) {
      final unsupported = row['unsupportedRules'];
      return unsupported is List && unsupported.isNotEmpty;
    }).length;
    final provenance = _firstWatchSignalProvenance(results);
    final table = '${provenance?['canonicalTable'] ?? ''}';
    final interfaceId =
        '${provenance?['interfaceId'] ?? (table == 'fund_money_yield' ? 'fund.money_yield_history' : 'fund.nav_history')}';
    final readbackAction = interfaceId == 'fund.money_yield_history'
        ? 'query_fund_money_yield'
        : 'query_fund_nav';
    final provider = '${provenance?['provider'] ?? 'local'}';
    final hasAnyEvidence = results.any((row) => row['status'] != 'no_evidence');
    final subjectType = requestedType == 'etf'
        ? AnalysisSubjectType.etf
        : AnalysisSubjectType.fund;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.fund,
      subjectType: subjectType,
      subjectId: 'watch_signal_check:$requestedType:$status',
      subjectName: '$requestedType watch signal check',
      observedFacts: [
        'items=${results.length}',
        'triggered=$triggeredCount',
        'noEvidence=$noEvidenceCount',
        'unsupportedRules=$unsupportedCount',
        if (gaps.isNotEmpty) 'gaps=${gaps.length}',
      ],
      interpretations: [
        triggeredCount > 0
            ? 'signal:triggered_count=$triggeredCount'
            : 'signal:no_triggered_items',
        unsupportedCount > 0
            ? 'unsupported_rules_present'
            : 'structured_numeric_rules_checked',
      ],
      missingEvidence: [
        if (noEvidenceCount > 0) 'fund_nav_or_money_yield',
        if (unsupportedCount > 0) 'structured_numeric_watch_conditions',
        if (gaps.isNotEmpty) 'watchlist_symbol_gaps',
      ],
      confidence: !hasAnyEvidence
          ? AnalysisConfidence.low
          : noEvidenceCount > 0 || unsupportedCount > 0
          ? AnalysisConfidence.medium
          : AnalysisConfidence.high,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [provider],
        interfaceId: interfaceId,
        capabilityId: provider == 'local'
            ? 'local.cache'
            : '$provider.$interfaceId',
        canonicalSchema: table.isEmpty ? 'fund_nav' : table,
        canonicalTable: table.isEmpty ? 'fund_nav' : table,
        readbackAction: readbackAction,
        sourceDataTime: '${provenance?['sourceDataTime'] ?? ''}',
        fetchedAt: '${provenance?['fetchedAt'] ?? ''}',
        cacheStatus: '${provenance?['cacheStatus'] ?? 'local-hit'}',
        coverageStatus: !hasAnyEvidence
            ? AnalysisCoverageStatus.none
            : noEvidenceCount > 0
            ? AnalysisCoverageStatus.partial
            : AnalysisCoverageStatus.sufficientForAnalysis,
      ),
    ).toJson();
  }

  Map<String, dynamic>? _firstWatchSignalProvenance(
    List<Map<String, dynamic>> results,
  ) {
    for (final result in results) {
      final provenance = result['provenance'];
      if (provenance is Map) {
        return Map<String, dynamic>.from(provenance);
      }
    }
    return null;
  }

  _WatchSignalEvidence _fundWatchSignalEvidence(
    String symbol,
    ReusableDataStore store,
    ToolContext context,
  ) {
    try {
      final navPayload = _queryService.query(
        'query_fund_nav',
        [symbol],
        {
          'symbols': [symbol],
          'limit': 2,
        },
        context,
      );
      final navRows =
          (navPayload['data'] as List?)
              ?.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList() ??
          const <Map<String, dynamic>>[];
      if (navRows.isNotEmpty) {
        final row = navRows.last;
        return _WatchSignalEvidence(
          symbol: symbol,
          type: 'fund',
          metricName: 'nav',
          metricValue: _numOrNull(row['nav']),
          sourceDataTime:
              '${row['date'] ?? navPayload['sourceDataTime'] ?? ''}',
          provider: '${row['source'] ?? navPayload['provider'] ?? 'local'}',
          fetchedAt: '${row['fetched_at'] ?? navPayload['fetchedAt'] ?? ''}',
          interfaceId: '${navPayload['interfaceId'] ?? 'fund.nav_history'}',
          canonicalTable: '${navPayload['canonicalTable'] ?? 'fund_nav'}',
        );
      }
    } catch (_) {
      // Fall through to direct store compatibility path below.
    }

    final navRows = store.queryFundNav(symbol, limit: 2);
    if (navRows.isNotEmpty) {
      final row = navRows.last;
      return _WatchSignalEvidence(
        symbol: symbol,
        type: 'fund',
        metricName: 'nav',
        metricValue: _numOrNull(row['nav']),
        sourceDataTime: '${row['date'] ?? ''}',
        provider: '${row['source'] ?? 'local'}',
        fetchedAt: '${row['fetched_at'] ?? ''}',
        interfaceId: 'fund.nav_history',
        canonicalTable: 'fund_nav',
      );
    }

    final moneyRows = store.queryFundMoneyYield(symbol, limit: 2);
    final row = moneyRows.isNotEmpty ? moneyRows.last : null;
    return _WatchSignalEvidence(
      symbol: symbol,
      type: 'fund',
      metricName: 'million_copies_income',
      metricValue: _numOrNull(row?['million_copies_income']),
      sourceDataTime: '${row?['date'] ?? ''}',
      provider: '${row?['source'] ?? 'local'}',
      fetchedAt: '${row?['fetched_at'] ?? ''}',
      interfaceId: 'fund.money_yield_history',
      canonicalTable: 'fund_money_yield',
    );
  }

  Map<String, dynamic> _evaluateWatchItem(
    WatchlistItem item,
    _WatchSignalEvidence evidence,
  ) {
    final unsupportedRules = <String>[];
    final checks = <Map<String, dynamic>>[];
    var triggered = false;
    final value = evidence.metricValue;
    final conditions = item.conditions;
    if (value != null) {
      for (final condition in conditions) {
        final field = condition.field;
        final op = condition.op;
        final threshold = condition.value;
        if (!(field == 'price' ||
                field == 'nav' ||
                field == evidence.metricName) ||
            !const ['>', '<', '>=', '<=', '=='].contains(op)) {
          unsupportedRules.add(
            'unsupported structured condition ${jsonEncode(condition.toJson())}',
          );
          continue;
        }
        final ok = _compareNumber(value, op, threshold);
        if (ok) triggered = true;
        checks.add({
          'field': field,
          'op': op,
          'threshold': threshold,
          'actual': value,
          'triggered': ok,
          'source': 'conditions',
        });
      }
      final targetEntry = item.targetEntryPrice ?? item.priceAtAdd;
      if (targetEntry > 0) {
        final ok = value <= targetEntry;
        if (ok) triggered = true;
        checks.add({
          'field': evidence.metricName,
          'op': '<=',
          'threshold': targetEntry,
          'actual': value,
          'triggered': ok,
          'source': 'targetEntryPrice',
        });
      }
      final stopLoss = item.stopLoss;
      if (stopLoss != null && stopLoss > 0) {
        final ok = value <= stopLoss;
        if (ok) triggered = true;
        checks.add({
          'field': evidence.metricName,
          'op': '<=',
          'threshold': stopLoss,
          'actual': value,
          'triggered': ok,
          'source': 'stopLoss',
          'riskAction': 'pause_or_stop',
        });
      }
    }
    final entryCondition = (item.entryCondition ?? '').trim();
    if (entryCondition.isNotEmpty && checks.isEmpty) {
      unsupportedRules.add(
        'entryCondition is text-only; rewrite it as conditions[] or numeric targetEntryPrice/stopLoss before automatic execution',
      );
    } else if (entryCondition.isNotEmpty && conditions.isEmpty) {
      unsupportedRules.add(
        'entryCondition text was preserved as explanation only; executable checks used structured numeric fields',
      );
    }
    final resultStatus = value == null
        ? 'no_evidence'
        : triggered
        ? 'triggered'
        : unsupportedRules.isNotEmpty && checks.isEmpty
        ? 'unsupported_rules'
        : 'not_triggered';
    return {
      'itemId': item.id,
      'symbol': evidence.symbol,
      'name': item.name.isEmpty ? evidence.symbol : item.name,
      'type': evidence.type,
      'watchStatus': item.status,
      'status': resultStatus,
      'triggered': triggered,
      'metric': {'name': evidence.metricName, 'value': value},
      'checks': checks,
      'unsupportedRules': unsupportedRules,
      'entryCondition': entryCondition.isEmpty ? null : entryCondition,
      'provenance': {
        'interfaceId': evidence.interfaceId,
        'provider': evidence.provider,
        'cacheStatus': 'local-hit',
        'sourceDataTime': evidence.sourceDataTime.isEmpty
            ? null
            : evidence.sourceDataTime,
        'fetchedAt': evidence.fetchedAt.isEmpty ? null : evidence.fetchedAt,
        'canonicalTable': evidence.canonicalTable,
      },
    };
  }

  String _normalizeWatchSymbol(String value) {
    final trimmed = value.trim().toUpperCase();
    if (trimmed.isEmpty) return '';
    final match = RegExp(r'\d{6}').firstMatch(trimmed);
    return match?.group(0) ?? trimmed;
  }

  double? _numOrNull(Object? value) {
    if (value == null || value == '') return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  bool _compareNumber(double actual, String op, double expected) {
    return switch (op) {
      '>' => actual > expected,
      '<' => actual < expected,
      '>=' => actual >= expected,
      '<=' => actual <= expected,
      '==' => (actual - expected).abs() < 0.000001,
      _ => false,
    };
  }

  Future<ToolResult> _aiRecord(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final direction = input['direction'] as String?;
    final price = (input['priceAtAnalysis'] as num?)?.toDouble();
    if (direction == null || price == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'direction and priceAtAnalysis required. Example: DataProcess(action: "ai_record", symbol: "600519", direction: "bullish", priceAtAnalysis: 1650)',
        isError: true,
      );
    }

    var strategyName = input['strategy'] as String?;
    final strategyId = input['strategyId'] as String?;
    if (strategyId != null) {
      final s = context.strategyStore.get(strategyId);
      if (s != null) strategyName = s.name;
    }

    final validator = AIBacktestValidator(_resolveService, context.basePath);
    validator.recordAnalysis(
      symbol: symbol,
      direction: direction,
      priceAtAnalysis: price,
      strategy: strategyName,
    );
    final summary = validator.getSummary();
    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Recorded: $symbol $direction @ $price${strategyName != null ? " (策略:$strategyName)" : ""}. Stats: ${jsonEncode(summary)}',
    );
  }

  Future<ToolResult> _aiValidate(String toolUseId, ToolContext context) async {
    final validator = AIBacktestValidator(_resolveService, context.basePath);
    final store = context.strategyStore;
    final result = await validator.validate(
      onValidated: (strategy, isCorrect, actualReturn, reflection) {
        final s = store.getByName(strategy);
        if (s != null) {
          store.recordValidation(
            s.id,
            correct: isCorrect,
            actualReturn: actualReturn,
            reflection: reflection,
          );
        }
      },
    );

    final reflections = result['reflections'] as List<String>?;
    if (reflections != null && reflections.isNotEmpty) {
      final file = File('${context.basePath}/memory/ai_reflections.md');
      file.parent.createSync(recursive: true);
      final lines = reflections.take(10).map((r) => '- $r').join('\n');
      file.writeAsStringSync(
        '# AI 分析反思 (最近10条验证经验)\n\n$lines\n\n> 分析时参考这些经验教训,避免重复犯错。\n',
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(result),
    );
  }

  Future<ToolResult> _optimizePortfolio(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final symbols = (input['symbols'] as List?)?.cast<String>() ?? [];
    if (symbols.length < 2) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'need 2+ symbols. Example: DataProcess(action:"optimize", symbols:["600519","000858","601318"], method:"riskParity")',
        isError: true,
      );
    }
    final method = input['method'] as String? ?? 'riskParity';
    final maxWeight = (input['maxWeight'] as num?)?.toDouble() ?? 0.3;

    final barsBySymbol = <String, List<KlineBar>>{};
    for (final s in symbols) {
      final r = await _resolveService.resolveKline(
        s,
        startDate: _sixMonthsAgo(),
      );
      barsBySymbol[s] = r.bars;
    }

    final Map<String, double> weights;
    switch (method) {
      case 'equalWeight':
        weights = PortfolioOptimizer.equalWeight(symbols);
      case 'riskParity':
        weights = PortfolioOptimizer.riskParity(
          barsBySymbol,
          maxWeight: maxWeight,
        );
      case 'maxSharpe':
        weights = PortfolioOptimizer.maxSharpe(
          barsBySymbol,
          maxWeight: maxWeight,
        );
      case 'minVariance':
        weights = PortfolioOptimizer.minVariance(
          barsBySymbol,
          maxWeight: maxWeight,
        );
      default:
        return ToolResult(
          toolUseId: toolUseId,
          content:
              'unknown method "$method". Use: equalWeight/riskParity/maxSharpe/minVariance',
          isError: true,
        );
    }

    final riskMetrics = <String, Map<String, dynamic>>{};
    for (final entry in barsBySymbol.entries) {
      if (entry.value.length < 10) continue;
      final stats = Statistics.returnStats(entry.value);
      riskMetrics[entry.key] = {
        'weight': weights[entry.key],
        'volatility': stats['annualizedVolatility'],
        'sharpe': stats['sharpe'],
        'maxDrawdown': stats['maxDrawdown'],
        'var95': double.parse(
          PortfolioOptimizer.valueAtRisk(entry.value).toStringAsFixed(2),
        ),
      };
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'optimize',
        'method': method,
        'symbols': symbols,
        'weights': weights,
        'assets': riskMetrics,
      }),
    );
  }

  Future<ToolResult> _indicators(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final period = input['period'] as String? ?? 'daily';
    final startDate = input['startDate'] as String? ?? _sixMonthsAgo();

    final r = await _resolveService.resolveKline(
      symbol,
      period: period,
      startDate: startDate,
    );
    final bars = r.bars;
    if (bars.length < 30) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'insufficient data (${bars.length} bars, need 30+)',
        isError: true,
      );
    }

    final result = Indicators.summary(bars);
    final persisted = input['persist'] == false
        ? null
        : _persistTechnicalIndicatorSeries(context, symbol, bars, period);
    result['symbol'] = symbol;
    result['source'] = r.source;
    result['bars'] = bars.length;
    result['range'] = '${bars.first.date} ~ ${bars.last.date}';
    result['interfaceId'] = 'technical.indicator_series';
    result['canonicalSchema'] = 'technical_indicator_series';
    result['canonicalTable'] = 'technical_indicator_series';
    result['provider'] = 'local';
    result['capabilityId'] = 'local.technical.indicator_series';
    result['cacheStatus'] = 'provider-hit';
    result['persistencePolicy'] = input['persist'] == false
        ? 'inspect-only'
        : 'canonical';
    result['sourceDataTime'] = bars.last.date;
    result['fetchedAt'] = DateTime.now().toUtc().toIso8601String();
    if (persisted != null) result['ingestion'] = persisted;

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(result),
    );
  }

  Map<String, dynamic>? _persistTechnicalIndicatorSeries(
    ToolContext context,
    String symbol,
    List<KlineBar> bars,
    String period,
  ) {
    if (context.basePath.isEmpty || bars.isEmpty) return null;
    final rows = <Map<String, dynamic>>[];
    final params = {'period': period, 'bars': bars.length};
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final series = <String, List<double?>>{
      'SMA_5': Indicators.sma(bars, 5),
      'SMA_10': Indicators.sma(bars, 10),
      'SMA_20': Indicators.sma(bars, 20),
      'SMA_60': Indicators.sma(bars, 60),
      'EMA_12': Indicators.ema(bars, 12),
      'EMA_26': Indicators.ema(bars, 26),
      'RSI_14': Indicators.rsi(bars),
      'ATR_14': Indicators.atr(bars),
    };
    final macd = Indicators.macd(bars);
    series['MACD_DIF'] = macd.dif;
    series['MACD_DEA'] = macd.dea;
    series['MACD_HIST'] = macd.hist;
    final boll = Indicators.boll(bars);
    series['BOLL_UPPER'] = boll.upper;
    series['BOLL_MID'] = boll.mid;
    series['BOLL_LOWER'] = boll.lower;
    final kdj = Indicators.kdj(bars);
    series['KDJ_K'] = kdj.k;
    series['KDJ_D'] = kdj.d;
    series['KDJ_J'] = kdj.j;

    for (var index = 0; index < bars.length; index++) {
      final bar = bars[index];
      for (final entry in series.entries) {
        final value = entry.value[index];
        if (value == null) continue;
        final fieldName = entry.key;
        rows.add({
          'provider': 'local',
          'capability_id': 'local.technical.indicator_series',
          'source_action': 'DataProcess.indicators',
          'symbol': symbol,
          'indicator': _indicatorGroup(fieldName),
          'field_name': fieldName,
          'source_date': bar.date,
          'value': double.parse(value.toStringAsFixed(6)),
          'fetched_at': fetchedAt,
          'params': params,
          'raw_json': jsonEncode({
            'date': bar.date,
            'field': fieldName,
            'value': value,
            'period': period,
          }),
        });
      }
    }
    return ReusableDataStore(
      context.basePath,
    ).saveTechnicalIndicatorSeries(rows, source: 'local');
  }

  String _indicatorGroup(String fieldName) {
    if (fieldName.startsWith('SMA_')) return 'sma';
    if (fieldName.startsWith('EMA_')) return 'ema';
    if (fieldName.startsWith('RSI_')) return 'rsi';
    if (fieldName.startsWith('MACD_')) return 'macd';
    if (fieldName.startsWith('BOLL_')) return 'boll';
    if (fieldName.startsWith('KDJ_')) return 'kdj';
    if (fieldName.startsWith('ATR_')) return 'atr';
    return fieldName.toLowerCase();
  }

  Future<ToolResult> _summary(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
  ) async {
    final r = await _resolveService.resolveKline(
      symbol,
      startDate: _sixMonthsAgo(),
    );
    final bars = r.bars;
    if (bars.length < 30) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'insufficient data',
        isError: true,
      );
    }

    final quoteResult = await _resolveService.resolveQuotes([symbol]);
    final quote = quoteResult.data.isNotEmpty ? quoteResult.data.first : null;

    final ind = Indicators.summary(bars);
    final signals = <String>[];
    final risks = <String>[];

    // Technical signals
    if (ind['macd_cross'] == 'golden_cross') signals.add('MACD金叉');
    if (ind['macd_cross'] == 'death_cross') risks.add('MACD死叉');
    if (ind['price_vs_ma20'] == 'above') signals.add('站上20日均线');
    if (ind['price_vs_ma20'] == 'below') risks.add('跌破20日均线');
    if (ind['rsi'] != null) {
      if ((ind['rsi'] as double) > 70) risks.add('RSI超买(${ind['rsi']})');
      if ((ind['rsi'] as double) < 30) signals.add('RSI超卖(${ind['rsi']})');
    }
    if (ind['kdj_j'] != null && (ind['kdj_j'] as double) > 100)
      risks.add('KDJ超买');
    if (ind['kdj_j'] != null && (ind['kdj_j'] as double) < 0)
      signals.add('KDJ超卖');

    // Volume analysis
    final recentVol =
        bars
            .sublist(bars.length - 5)
            .map((b) => b.volume)
            .reduce((a, b) => a + b) /
        5;
    final prevVol = bars.length > 25
        ? bars
                  .sublist(bars.length - 25, bars.length - 5)
                  .map((b) => b.volume)
                  .reduce((a, b) => a + b) /
              20
        : recentVol;
    final volRatio = prevVol > 0 ? recentVol / prevVol : 1.0;
    if (volRatio > 1.5)
      signals.add('放量(${(volRatio * 100).toStringAsFixed(0)}%)');
    if (volRatio < 0.5)
      risks.add('缩量(${(volRatio * 100).toStringAsFixed(0)}%)');

    // Price position
    final prices = bars.map((b) => b.close).toList()..sort();
    final percentile = prices.indexOf(bars.last.close) / prices.length * 100;
    final klineCacheHit = r.source.startsWith('local ');

    final summary = {
      'symbol': symbol,
      if (quote != null) 'name': quote.name,
      'price': {
        'current': bars.last.close,
        if (quote != null)
          'change':
              '${quote.changePct > 0 ? "+" : ""}${quote.changePct.toStringAsFixed(2)}%',
        'position': '近${bars.length}日 ${percentile.toStringAsFixed(0)}%分位',
        '6m_high': prices.last,
        '6m_low': prices.first,
      },
      'indicators': ind,
      'volume': {
        'recent5d_avg': recentVol.toStringAsFixed(0),
        'vs_20d':
            '${volRatio > 1 ? "+" : ""}${((volRatio - 1) * 100).toStringAsFixed(0)}%',
      },
      if (signals.isNotEmpty) 'signals': signals,
      if (risks.isNotEmpty) 'risks': risks,
      'analysisEvidence': AnalysisEvidencePackage(
        kind: AnalysisEvidenceKind.stock,
        subjectType: AnalysisSubjectType.stock,
        subjectId: symbol,
        subjectName: quote?.name ?? '',
        observedFacts: [
          'bars=${bars.length}',
          'latestDate=${bars.last.date}',
          'latestClose=${bars.last.close}',
          'source=${r.source}',
        ],
        interpretations: [
          ...signals.map((item) => 'signal:$item'),
          ...risks.map((item) => 'risk:$item'),
          'pricePosition=${percentile.toStringAsFixed(0)}pctile',
        ],
        missingEvidence: const [
          'fundamental_valuation',
          'money_flow',
          'news_context',
        ],
        confidence: bars.length >= 120
            ? AnalysisConfidence.medium
            : AnalysisConfidence.low,
        strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
        sourceCoverage: AnalysisSourceCoverage(
          sources: [r.source, if (quote != null) quoteResult.source],
          interfaceId: 'stock.daily_kline',
          capabilityId: klineCacheHit
              ? 'local.cache'
              : '${r.source}.stock.daily_kline',
          canonicalSchema: 'kline_daily',
          canonicalTable: 'kline_daily',
          readbackAction: 'query_kline',
          sourceDataTime: bars.last.date,
          cacheStatus: klineCacheHit ? 'cache-hit' : 'provider-hit',
          coverageStatus: quote == null
              ? AnalysisCoverageStatus.partial
              : AnalysisCoverageStatus.sufficientForTechnical,
        ),
      ).toJson(),
    };

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(summary),
    );
  }

  String _sixMonthsAgo() {
    final d = DateTime.now().subtract(const Duration(days: 180));
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  // ─── Strategy Actions ─────────────────────────────────────────────────────

  Future<ToolResult> _strategyExecuteOrBatch(
    String toolUseId,
    String? symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final symbols = _symbolsFromInput(input);
    if ((symbol == null || symbol.isEmpty) && symbols.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'symbol or symbols required for strategy_execute. Example: DataProcess(action: "strategy_execute", symbol: "600519") or DataProcess(action: "strategy_execute", symbols: ["600519","000858"], strategyId: "preset_03").',
        isError: true,
      );
    }
    if (symbols.isEmpty) {
      return _strategyExecute(toolUseId, symbol!, input, context);
    }
    return _strategyExecuteBatch(toolUseId, symbols, input, context);
  }

  List<String> _symbolsFromInput(Map<String, dynamic> input) {
    final raw = input['symbols'];
    if (raw is! List) return const [];
    return raw
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(8)
        .toList();
  }

  Future<ToolResult> _strategyExecuteBatch(
    String toolUseId,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final store = context.strategyStore;
    final strategyId = input['strategyId'] as String?;
    final strategyName = input['strategy'] as String?;

    Strategy? strategy;
    if (strategyId != null) strategy = store.get(strategyId);
    if (strategy == null && strategyName != null) {
      strategy = store.getByIdOrName(strategyName);
    }
    if (strategy == null) {
      final available = store.strategies
          .map((s) => '${s.id}: ${s.name}')
          .join(', ');
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'strategy not found. Available: $available\nUse strategy_list to see all.',
        isError: true,
      );
    }

    final executor = StrategyExecutor(_resolveService);
    final results = <Map<String, dynamic>>[];
    for (final code in symbols) {
      try {
        final decision = await executor.execute(strategy, code);
        store.recordExecution(strategy.id, decision.execution);
        results.add({
          'symbol': code,
          'ok': true,
          'decision': decision.decision,
          'score': decision.score,
          'suggestedEntry': decision.suggestedEntry,
          'stopLoss': decision.stopLoss,
          'targetPrice': decision.targetPrice,
          'positionPct': decision.positionPct,
          'reasoning': decision.reasoning,
          'steps': decision.execution.stepResults
              .map((s) => s.toJson())
              .toList(),
        });
      } catch (e) {
        results.add({'symbol': code, 'ok': false, 'error': e.toString()});
      }
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'strategy_execute',
        'mode': 'batch',
        'strategyId': strategy.id,
        'strategyName': strategy.name,
        'requested': symbols.length,
        'passed': results.where((row) => row['ok'] == true).length,
        'failed': results.where((row) => row['ok'] != true).length,
        'results': results,
        'note':
            'Batch strategy_execute is bounded to 8 symbols. Use candidate discovery first, then validate only the strongest candidates.',
      }),
    );
  }

  Future<ToolResult> _strategyExecute(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final store = context.strategyStore;
    final strategyId = input['strategyId'] as String?;
    final strategyName = input['strategy'] as String?;

    Strategy? strategy;
    if (strategyId != null) strategy = store.get(strategyId);
    if (strategy == null && strategyName != null)
      strategy = store.getByIdOrName(strategyName);
    if (strategy == null) {
      final available = store.strategies
          .map((s) => '${s.id}: ${s.name}')
          .join(', ');
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'strategy not found. Available: $available\nUse strategy_list to see all.',
        isError: true,
      );
    }

    final executor = StrategyExecutor(_resolveService);
    final decision = await executor.execute(strategy, symbol);
    store.recordExecution(strategy.id, decision.execution);

    // Return both structured JSON and readable reasoning
    final output = <String, dynamic>{
      ...decision.toJson(),
      'steps': decision.execution.stepResults.map((s) => s.toJson()).toList(),
    };
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(output),
    );
  }

  Future<ToolResult> _strategyBacktest(
    String toolUseId,
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final store = context.strategyStore;
    final strategyId = input['strategyId'] as String?;
    final strategyName = input['strategy'] as String?;

    Strategy? strategy;
    if (strategyId != null) strategy = store.get(strategyId);
    if (strategy == null && strategyName != null)
      strategy = store.getByIdOrName(strategyName);
    if (strategy == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'strategy not found. Use strategy_list.',
        isError: true,
      );
    }

    final days = (input['limit'] as num?)?.toInt() ?? 250;
    final executor = StrategyExecutor(_resolveService);
    final result = await executor.backtest(strategy, symbol, days: days);

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert(result),
    );
  }

  ToolResult _strategyList(String toolUseId, ToolContext context) {
    final store = context.strategyStore;
    if (store.strategies.isEmpty) {
      return ToolResult(toolUseId: toolUseId, content: '无策略。策略会在首次使用时自动从预设加载。');
    }
    final buf = StringBuffer('策略列表 (${store.strategies.length}):\n\n');
    for (final s in store.strategies) {
      final wr = s.timesUsed > 0
          ? '${(s.winRate * 100).toStringAsFixed(0)}%'
          : '未验证';
      buf.writeln('- **${s.name}** (${s.id}) [${s.type.name}]');
      buf.writeln('  ${s.description}');
      buf.writeln('  步骤: ${s.steps.map((st) => st.description).join(' → ')}');
      buf.writeln('  胜率: $wr | 使用: ${s.timesUsed}次 | 来源: ${s.source}');
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln('创建新策略时可用的 step action + checkLogic:');
    buf.writeln(
      '  indicators: price_vs_ma20==above, price_vs_ma10==above, rsi<30, rsi<70, macd_histogram>0, close>=high_20d, close>=high_40d',
    );
    buf.writeln(
      '  volume: volume_ratio>1.5, volume_trend==decreasing, net_inflow>0',
    );
    buf.writeln('  support: nearest_support_distance_pct<3');
    buf.writeln('  factors: pe>0, pe<30, pb<5, roe>12, turnoverRate>5 (&&组合)');
    buf.writeln('  score_technical: score>=60');
    return ToolResult(toolUseId: toolUseId, content: buf.toString());
  }
}
