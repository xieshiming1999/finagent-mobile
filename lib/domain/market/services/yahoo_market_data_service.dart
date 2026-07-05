import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/tool_context.dart';
import '../analysis/analysis_evidence_contract.dart';
import '../providers/data_api_interface_contract.dart';
import '../providers/data_api_interface_router.dart';
import '../repositories/local_market_data_repository.dart';
import 'cache_policy.dart';
import '../repositories/yahoo_market_data_repository.dart';
import 'yahoo_market_data_corporate_fetch.dart';
import 'yahoo_market_data_market_fetch.dart';
import 'yahoo_market_data_option_kline.dart';
import 'yahoo_market_data_support.dart';

class YahooMarketDataService {
  final YahooMarketDataRepository _repository;
  final YahooMarketDataSupport _support;
  final YahooMarketDataMarketFetch _market;
  final YahooMarketDataCorporateFetch _corporate;
  final YahooMarketDataOptionKlineService _optionKline;
  final DataApiInterfaceRouter _router;

  YahooMarketDataService({
    DataManager? dataManager,
    http.Client? httpClient,
    DataApiInterfaceRouter? router,
  }) : this._internal(dataManager ?? DataManager(), httpClient, router);

  YahooMarketDataService._internal(
    DataManager dataManager,
    http.Client? httpClient,
    DataApiInterfaceRouter? router,
  ) : _repository = YahooMarketDataRepository(dataManager),
      _support = const YahooMarketDataSupport(),
      _market = YahooMarketDataMarketFetch(
        repository: YahooMarketDataRepository(dataManager),
        support: const YahooMarketDataSupport(),
        httpClient: httpClient ?? http.Client(),
      ),
      _optionKline = YahooMarketDataOptionKlineService(
        router: _defaultRouter(router, dataManager),
        localRepository: LocalMarketDataRepository(dataManager),
        market: YahooMarketDataMarketFetch(
          repository: YahooMarketDataRepository(dataManager),
          support: const YahooMarketDataSupport(),
          httpClient: httpClient ?? http.Client(),
        ),
      ),
      _corporate = YahooMarketDataCorporateFetch(
        repository: YahooMarketDataRepository(dataManager),
        support: const YahooMarketDataSupport(),
        httpClient: httpClient ?? http.Client(),
      ),
      _router = _defaultRouter(router, dataManager);

  static DataApiInterfaceRouter _defaultRouter(
    DataApiInterfaceRouter? router,
    DataManager dataManager,
  ) {
    return router ??
        DataApiInterfaceRouter(
          runtimeBasePathProvider: () => dataManager.basePath,
        );
  }

  Future<Map<String, dynamic>> price(
    List<String> symbols,
    ToolContext context,
  ) {
    _support.assertGlobalSymbols(symbols);
    return _market.price(symbols, context);
  }

  Future<List<KlineBar>> fetchHistoryBars(
    String symbol,
    String period, {
    ToolContext? context,
  }) {
    _support.assertGlobalSymbol(symbol);
    return _market.fetchHistoryBars(symbol, period, context: context);
  }

  Future<Map<String, dynamic>> history(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    _support.assertGlobalSymbol(symbol);
    return _market.history(symbol, input, context);
  }

  Future<Map<String, dynamic>> news(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    _support.assertGlobalSymbols(symbols);
    if (symbols.length == 1) {
      return _runRouted(
        interfaceId: 'global.finance_news',
        readbackDataset: 'news',
        symbol: symbols.first,
        input: input,
        context: context,
        providerCall: () async => _throwEmptyProviderErrors(
          await _market.news(symbols, input, context),
          'Yahoo news',
        ),
      );
    }
    final result = await _market.news(symbols, input, context);
    return {
      ...result,
      'interfaceId': 'global.finance_news',
      'provider': 'yfinance',
      'providerId': 'yahoo',
      ..._yahooGlobalProvenance(result),
      'canonicalSchema': 'yfinance_news',
      'canonicalTable': 'yfinance_news',
      'cacheStatus': 'provider-hit',
      'cacheDecision':
          'multi-symbol yahoo_news fetch uses provider path; per-symbol cache readback is available through query_yfinance dataset=news',
    };
  }

  Future<Map<String, dynamic>> options(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    _support.assertGlobalSymbol(symbol);
    return _runRouted(
      interfaceId: 'option.chain_snapshot',
      readbackDataset: 'options',
      symbol: symbol,
      input: input,
      context: context,
      providerCall: () => _corporate.options(symbol, input, context),
    );
  }

  Future<Map<String, dynamic>> actions(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    _support.assertGlobalSymbol(symbol);
    return _runRouted(
      interfaceId: 'global.corporate_actions',
      readbackDataset: 'actions',
      symbol: symbol,
      input: input,
      context: context,
      providerCall: () => _corporate.actions(symbol, input, context),
    );
  }

  Future<Map<String, dynamic>> actionsSlice(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context, {
    required String interfaceId,
    required String readbackDataset,
    required String readbackAction,
  }) {
    _support.assertGlobalSymbol(symbol);
    return _runRouted(
      interfaceId: interfaceId,
      readbackDataset: readbackDataset,
      symbol: symbol,
      input: input,
      context: context,
      providerCall: () async {
        await _corporate.actions(symbol, input, context);
        return queryDataset(context, symbol, {
          ...input,
          'dataset': readbackDataset,
          '_queryAction': readbackAction,
        });
      },
    );
  }

  Future<Map<String, dynamic>> optionDailyKline(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    _support.assertGlobalSymbol(symbol);
    return _optionKline.optionDailyKline(
      symbol,
      input,
      context,
      constraintFromInput: _constraintFromInput,
      isUsableResult: _isUsableResult,
      yahooGlobalProvenance: _yahooGlobalProvenance,
    );
  }

  Future<Map<String, dynamic>> earnings(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    _support.assertGlobalSymbol(symbol);
    return _runRouted(
      interfaceId: 'global.company_profile',
      readbackDataset: 'profile',
      symbol: symbol,
      input: input,
      context: context,
      providerCall: () async => _withEarningsRelatedInterfaces(
        context,
        symbol,
        await _corporate.earnings(symbol, context),
      ),
      readCache: () => _readEarningsCache(context, symbol),
    );
  }

  Future<Map<String, dynamic>> earningsSlice(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context, {
    required String interfaceId,
    required String readbackDataset,
    required String readbackAction,
  }) {
    _support.assertGlobalSymbol(symbol);
    return _runRouted(
      interfaceId: interfaceId,
      readbackDataset: readbackDataset,
      symbol: symbol,
      input: input,
      context: context,
      providerCall: () async {
        await _corporate.earnings(symbol, context);
        return queryDataset(context, symbol, {
          ...input,
          'dataset': readbackDataset,
          '_queryAction': readbackAction,
        });
      },
    );
  }

  Map<String, dynamic> queryDataset(
    ToolContext context,
    String symbol,
    Map<String, dynamic> input,
  ) {
    final readbackAction =
        '${input['_queryAction'] ?? 'query_yfinance'}'.trim().isEmpty
        ? 'query_yfinance'
        : '${input['_queryAction'] ?? 'query_yfinance'}';
    final requestedDataset = '${input['dataset'] ?? 'profile'}'.toLowerCase();
    final dataset = _normalizeQueryDataset(requestedDataset);
    final limit = _support.inputLimit(input, dataset == 'profile' ? 100 : 200);
    final providerConstraint = _constraintFromInput(input);
    final providerExtra = _queryDatasetProviderExtra(input, providerConstraint);
    final allowReadback = _allowsYfinanceReadback(providerConstraint);

    if (dataset == 'profile') {
      final rows = allowReadback
          ? _repository.queryProfile(context, symbol, limit: limit)
          : const <Map<String, dynamic>>[];
      return {
        'action': readbackAction,
        'dataset': 'profile',
        'symbol': symbol.toUpperCase(),
        'count': rows.length,
        'source': 'local yfinance_profile_fields',
        ..._queryDatasetProvenance(
          dataset,
          rows,
          readbackAction,
          providerExtra: providerExtra,
        ),
        'data': rows,
      };
    }
    if (dataset == 'statements') {
      final rows = allowReadback
          ? _repository.queryStatements(
              context,
              symbol,
              statementType: input['statementType'] as String?,
              limit: limit,
            )
          : const <Map<String, dynamic>>[];
      return {
        'action': readbackAction,
        'dataset': 'statements',
        'symbol': symbol.toUpperCase(),
        'count': rows.length,
        'source': 'local yfinance_statement_items',
        ..._queryDatasetProvenance(
          dataset,
          rows,
          readbackAction,
          providerExtra: providerExtra,
        ),
        'data': rows,
      };
    }
    const supportedDatasets = {
      'earnings_calendar',
      'earnings_history',
      'earnings_estimates',
      'eps_revisions',
      'eps_trend',
      'income_statement',
      'balance_sheet',
      'cash_flow',
      'quarterly_financial_statements',
      'quarterly_income_statement',
      'quarterly_balance_sheet',
      'quarterly_cash_flow',
      'recommendations',
      'upgrade_downgrade_events',
      'news',
      'options',
      'option_open_interest',
      'option_volume',
      'option_implied_volatility',
      'option_moneyness',
      'option_bid_ask_spread',
      'option_price_change',
      'option_trade_recency',
      'option_expiries',
      'actions',
      'dividends',
      'splits',
      'stock_splits',
      'holders',
      'major_holders',
      'institutional_holders',
      'mutualfund_holders',
      'mutual_fund_holders',
      'fund_holders',
      'insiders',
      'capital_gains',
    };
    if (supportedDatasets.contains(dataset)) {
      final rows = allowReadback
          ? _repository.queryDataset(context, dataset, symbol, limit: limit)
          : const <Map<String, dynamic>>[];
      return {
        'action': readbackAction,
        'dataset': requestedDataset,
        'symbol': symbol.toUpperCase(),
        'count': rows.length,
        'source': 'local yfinance_$dataset',
        ..._queryDatasetProvenance(
          dataset,
          rows,
          readbackAction,
          providerExtra: providerExtra,
        ),
        'data': rows,
        if (dataset == 'news')
          'analysisEvidence': _globalNewsAnalysisEvidence(
            symbol: symbol,
            rows: rows,
            readbackAction: readbackAction,
          ),
      };
    }
    throw ArgumentError(
      'unsupported dataset "$requestedDataset". Use dataset:"profile", "statements", "earnings_calendar", "earnings_history", "earnings_estimates", "eps_revisions", "eps_trend", "quarterly_financial_statements", "recommendations", "upgrade_downgrade_events", "news", "options", "option_expiries" (or "expiries"), "option_open_interest" (or "open_interest"), "option_volume" (or "volume"), "option_implied_volatility" (or "implied_volatility"), "option_moneyness" (or "moneyness"/"in_the_money"), "option_bid_ask_spread" (or "bid_ask_spread"/"spread"), "option_price_change" (or "price_change"/"percent_change"), "option_trade_recency" (or "trade_recency"/"last_trade_date"), "actions", "dividends", "splits" (or "stock_splits"), "holders", "institutional_holders", "mutual_fund_holders", or "insiders".',
    );
  }

  Map<String, dynamic> _globalNewsAnalysisEvidence({
    required String symbol,
    required List<Map<String, dynamic>> rows,
    required String readbackAction,
  }) {
    final sourceDataTime = _latestRowValue(rows, const ['published_at']);
    final fetchedAt = _latestRowValue(rows, const ['updated_at', 'fetched_at']);
    final top = rows.isEmpty ? null : rows.first;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.news,
      subjectType: AnalysisSubjectType.news,
      subjectId: symbol.toUpperCase(),
      subjectName: '${symbol.toUpperCase()} global finance news',
      observedFacts: [
        'rows=${rows.length}',
        'symbol=${symbol.toUpperCase()}',
        if (sourceDataTime != null) 'sourceDataTime=$sourceDataTime',
        if (top != null) 'topTitle=${top['title'] ?? '-'}',
      ],
      interpretations: [
        rows.isEmpty
            ? 'global_finance_news:missing'
            : 'global_finance_news:available',
        'news_context:readback_evidence',
      ],
      missingEvidence: const [
        'sentiment_scoring',
        'price_confirmation',
        'fundamental_confirmation',
        'strategy_validation',
      ],
      confidence: rows.isEmpty
          ? AnalysisConfidence.low
          : AnalysisConfidence.medium,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: const ['local yfinance_news'],
        interfaceId: 'global.finance_news',
        capabilityId: 'yfinance.global.finance_news',
        canonicalSchema: 'yfinance_news',
        canonicalTable: 'yfinance_news',
        readbackAction: readbackAction,
        sourceDataTime: sourceDataTime ?? '',
        fetchedAt: fetchedAt ?? '',
        cacheStatus: rows.isEmpty ? 'local-miss' : 'local-hit',
        coverageStatus: rows.isEmpty
            ? AnalysisCoverageStatus.none
            : AnalysisCoverageStatus.sufficientForAnalysis,
      ),
    ).toJson();
  }

  String? _latestRowValue(List<Map<String, dynamic>> rows, List<String> keys) {
    String? latest;
    for (final row in rows) {
      for (final key in keys) {
        final raw = row[key];
        if (raw == null) continue;
        final value = '$raw';
        if (value.isEmpty) continue;
        if (latest == null || value.compareTo(latest) > 0) {
          latest = value;
        }
      }
    }
    return latest;
  }

  String _normalizeQueryDataset(String requestedDataset) {
    final normalized = requestedDataset.trim().toLowerCase();
    return switch (normalized) {
      'expiries' => 'option_expiries',
      'open_interest' => 'option_open_interest',
      'volume' => 'option_volume',
      'implied_volatility' => 'option_implied_volatility',
      'moneyness' || 'in_the_money' => 'option_moneyness',
      'spread' ||
      'option_spread' ||
      'bid_ask_spread' => 'option_bid_ask_spread',
      'price_change' || 'change' || 'percent_change' => 'option_price_change',
      'trade_recency' ||
      'last_trade' ||
      'last_trade_date' => 'option_trade_recency',
      'earnings_dates' => 'earnings_calendar',
      'earnings_estimate' => 'earnings_estimates',
      'quarterly_financials' ||
      'quarterly_statements' => 'quarterly_financial_statements',
      'income' || 'income_stmt' => 'income_statement',
      'balancesheet' => 'balance_sheet',
      'cashflow' => 'cash_flow',
      'quarterly_income' ||
      'quarterly_income_stmt' => 'quarterly_income_statement',
      'quarterly_balancesheet' => 'quarterly_balance_sheet',
      'quarterly_cashflow' => 'quarterly_cash_flow',
      'upgrades_downgrades' ||
      'upgrades' ||
      'downgrades' => 'upgrade_downgrade_events',
      'stock_splits' => 'splits',
      'capitalgains' => 'capital_gains',
      'institutions' => 'institutional_holders',
      'mutual_fund_holders' || 'fund_holders' => 'mutualfund_holders',
      _ => normalized,
    };
  }

  Map<String, dynamic> _queryDatasetProvenance(
    String dataset,
    List<Map<String, dynamic>> rows,
    String readbackAction, {
    Map<String, dynamic> providerExtra = const {},
  }) {
    final spec = _queryDatasetSpec(dataset, readbackAction);
    return {
      'interfaceId': spec.interfaceId,
      'provider': 'yfinance',
      'providerId': 'yahoo',
      ...providerExtra,
      ..._yahooGlobalProvenance(rows),
      'capabilityId': 'yfinance.${spec.interfaceId}',
      'canonicalSchema': spec.canonicalSchema,
      'canonicalTable': spec.canonicalTable,
      'cacheStatus': rows.isNotEmpty ? 'local-hit' : 'local-miss',
      'cacheDecision': rows.isNotEmpty
          ? 'cacheFirst read reusable local Yahoo/yfinance rows before provider refresh'
          : providerExtra['providerMode'] == 'strict' &&
                providerExtra['providerFilter'] != null
          ? 'strict provider read rejected Yahoo/yfinance cache rows for the requested provider'
          : 'cacheFirst read reusable local Yahoo/yfinance rows; no rows matched the requirement',
      'readbackAction': readbackAction,
    };
  }

  bool _allowsYfinanceReadback(DataApiProviderConstraint constraint) {
    if (constraint.providerMode != DataApiProviderMode.strict) return true;
    final provider = constraint.provider;
    return provider == null || provider == FinanceProvider.yfinance;
  }

  Map<String, dynamic> _queryDatasetProviderExtra(
    Map<String, dynamic> input,
    DataApiProviderConstraint constraint,
  ) {
    final rawProvider = input['provider'] ?? input['source'];
    return {
      if (rawProvider != null && '$rawProvider'.trim().isNotEmpty)
        'providerFilter': '$rawProvider'.trim(),
      'providerMode': constraint.providerMode.name,
      if (constraint.provider == FinanceProvider.yfinance)
        'cacheSourceFilter': 'yahoo',
    };
  }

  ({String interfaceId, String canonicalSchema, String canonicalTable})
  _queryDatasetSpec(String dataset, String readbackAction) {
    if (dataset == 'options') {
      return switch (readbackAction) {
        'query_option_quote' => (
          interfaceId: 'option.quote',
          canonicalSchema: 'yfinance_option_contracts',
          canonicalTable: 'yfinance_option_contracts',
        ),
        'query_option_daily_kline' => (
          interfaceId: 'option.daily_kline',
          canonicalSchema: 'kline_daily',
          canonicalTable: 'kline_daily',
        ),
        'query_option_contract_list' => (
          interfaceId: 'option.contract_list',
          canonicalSchema: 'yfinance_option_contracts',
          canonicalTable: 'yfinance_option_contracts',
        ),
        'query_global_options_chain' => (
          interfaceId: 'global.options_chain',
          canonicalSchema: 'yfinance_options',
          canonicalTable: 'yfinance_option_contracts',
        ),
        _ => (
          interfaceId: 'option.chain_snapshot',
          canonicalSchema: 'yfinance_options',
          canonicalTable: 'yfinance_option_contracts',
        ),
      };
    }
    return switch (dataset) {
      'profile' => (
        interfaceId: 'global.company_profile',
        canonicalSchema: 'yfinance_profile_fields',
        canonicalTable: 'yfinance_profile_fields',
      ),
      'statements' => (
        interfaceId: 'global.financial_statements',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'income_statement' => (
        interfaceId: 'global.income_statement',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'balance_sheet' => (
        interfaceId: 'global.balance_sheet',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'cash_flow' => (
        interfaceId: 'global.cash_flow',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'earnings_calendar' => (
        interfaceId: 'global.earnings_calendar',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'earnings_history' => (
        interfaceId: 'global.earnings_history',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'earnings_estimates' => (
        interfaceId: 'global.earnings_estimates',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'eps_revisions' => (
        interfaceId: 'global.eps_revisions',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'eps_trend' => (
        interfaceId: 'global.eps_trend',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'quarterly_financial_statements' => (
        interfaceId: 'global.quarterly_financial_statements',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'quarterly_income_statement' => (
        interfaceId: 'global.quarterly_income_statement',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'quarterly_balance_sheet' => (
        interfaceId: 'global.quarterly_balance_sheet',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'quarterly_cash_flow' => (
        interfaceId: 'global.quarterly_cash_flow',
        canonicalSchema: 'yfinance_statement_items',
        canonicalTable: 'yfinance_statement_items',
      ),
      'recommendations' => (
        interfaceId: 'global.recommendations',
        canonicalSchema: 'yfinance_recommendations',
        canonicalTable: 'yfinance_recommendations',
      ),
      'upgrade_downgrade_events' => (
        interfaceId: 'global.upgrade_downgrade_events',
        canonicalSchema: 'yfinance_recommendations',
        canonicalTable: 'yfinance_recommendations',
      ),
      'news' => (
        interfaceId: 'global.finance_news',
        canonicalSchema: 'yfinance_news',
        canonicalTable: 'yfinance_news',
      ),
      'options' => (
        interfaceId: 'option.chain_snapshot',
        canonicalSchema: 'yfinance_options',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_open_interest' => (
        interfaceId: 'option.open_interest',
        canonicalSchema: 'yfinance_option_contracts',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_volume' => (
        interfaceId: 'option.volume',
        canonicalSchema: 'yfinance_option_contracts',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_implied_volatility' => (
        interfaceId: 'option.implied_volatility',
        canonicalSchema: 'yfinance_option_contracts',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_moneyness' => (
        interfaceId: 'option.moneyness',
        canonicalSchema: 'yfinance_option_contracts',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_bid_ask_spread' => (
        interfaceId: 'option.bid_ask_spread',
        canonicalSchema: 'yfinance_option_contracts',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_price_change' => (
        interfaceId: 'option.price_change',
        canonicalSchema: 'yfinance_option_contracts',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_trade_recency' => (
        interfaceId: 'option.trade_recency',
        canonicalSchema: 'yfinance_option_contracts',
        canonicalTable: 'yfinance_option_contracts',
      ),
      'option_expiries' => (
        interfaceId: 'option.expiry_calendar',
        canonicalSchema: 'yfinance_option_expiries',
        canonicalTable: 'yfinance_option_expiries',
      ),
      'actions' => (
        interfaceId: 'global.corporate_actions',
        canonicalSchema: 'yfinance_corporate_actions',
        canonicalTable: 'yfinance_corporate_actions',
      ),
      'dividends' => (
        interfaceId: 'global.dividends',
        canonicalSchema: 'yfinance_corporate_actions',
        canonicalTable: 'yfinance_corporate_actions',
      ),
      'splits' => (
        interfaceId: 'global.stock_splits',
        canonicalSchema: 'yfinance_corporate_actions',
        canonicalTable: 'yfinance_corporate_actions',
      ),
      'holders' => (
        interfaceId: 'global.holders',
        canonicalSchema: 'yfinance_holders',
        canonicalTable: 'yfinance_holders',
      ),
      'major_holders' => (
        interfaceId: 'global.major_holders',
        canonicalSchema: 'yfinance_holders',
        canonicalTable: 'yfinance_holders',
      ),
      'institutional_holders' => (
        interfaceId: 'global.institutional_holders',
        canonicalSchema: 'yfinance_holders',
        canonicalTable: 'yfinance_holders',
      ),
      'mutualfund_holders' => (
        interfaceId: 'global.mutual_fund_holders',
        canonicalSchema: 'yfinance_holders',
        canonicalTable: 'yfinance_holders',
      ),
      'insiders' => (
        interfaceId: 'global.insider_transactions',
        canonicalSchema: 'yfinance_insider_transactions',
        canonicalTable: 'yfinance_insider_transactions',
      ),
      'capital_gains' => (
        interfaceId: 'global.capital_gains',
        canonicalSchema: 'yfinance_corporate_actions',
        canonicalTable: 'yfinance_corporate_actions',
      ),
      _ => (
        interfaceId: 'global.company_profile',
        canonicalSchema: 'yfinance_profile_fields',
        canonicalTable: 'yfinance_profile_fields',
      ),
    };
  }

  Future<Map<String, dynamic>> _runRouted({
    required String interfaceId,
    required String readbackDataset,
    required String symbol,
    required Map<String, dynamic> input,
    required ToolContext context,
    required Future<Map<String, dynamic>> Function() providerCall,
    Map<String, dynamic>? Function()? readCache,
  }) async {
    final result = await _router.runCapability<Map<String, dynamic>>(
      interfaceId: interfaceId,
      constraint: _constraintFromInput(input),
      cachePolicy: CachePolicy.fromInput(input),
      readCache: () async {
        final cached = readCache == null
            ? queryDataset(context, symbol, {
                ...input,
                'dataset': readbackDataset,
              })
            : readCache.call();
        return cached != null && _isUsableResult(cached)
            ? DataApiLocalCacheResult(data: cached)
            : null;
      },
      call: (capability) async {
        if (capability.provider != FinanceProvider.yfinance) return null;
        return DataApiProviderExecution(
          data: await providerCall(),
          source: 'yahoo',
          providerName: 'Yahoo Finance',
        );
      },
      isUsable: _isUsableResult,
      emptyMessage: 'returned empty $readbackDataset rows',
      failureMessage: 'All $interfaceId providers failed',
    );
    return {
      ...result.data,
      'source': result.source,
      'interfaceId': result.provenance.interfaceId,
      'capabilityId': result.provenance.capabilityId,
      'provider': result.provenance.provider,
      'providerId': 'yahoo',
      ..._yahooGlobalProvenance(result.data),
      'canonicalSchema': result.provenance.canonicalSchema,
      'canonicalTable': result.provenance.canonicalTable,
      'cacheStatus': result.provenance.cacheStatus,
      'cachePolicyMode': result.provenance.cachePolicyMode,
      'cacheDecision': result.provenance.cacheDecision,
      ...result.provenance.routePolicyJson(),
      'provenance': {...result.provenance.toJson(), 'providerId': 'yahoo'},
    };
  }

  Map<String, dynamic>? _readEarningsCache(ToolContext context, String symbol) {
    final datasets = _readEarningsDatasets(context, symbol);
    if (datasets.values.any((value) => !_isUsableResult(value))) return null;
    return {
      'action': 'yahoo_earnings',
      'symbol': symbol.toUpperCase(),
      'source': 'local yfinance compound datasets',
      'count': _earningsDatasetCount(datasets),
      'datasets': datasets,
      'relatedInterfaces': _earningsRelatedInterfaces(datasets),
      'ingestion': {
        'persisted': true,
        'tables': [
          'yfinance_profile_fields',
          'yfinance_statement_items',
          'yfinance_recommendations',
          'yfinance_holders',
          'yfinance_insider_transactions',
        ],
      },
    };
  }

  Map<String, dynamic> _yahooGlobalProvenance(Object? value) {
    return {
      'providerStatus': 'global-only',
      'marketScope': const ['US', 'HK', 'global'],
      'globalOnly': true,
      'asOf': _latestYahooTimestamp(value, const [
        'timestamp',
        'as_of',
        'asOf',
        'published_at',
        'action_date',
        'last_trade_date',
        'period',
        'reported_date',
        'start_date',
      ]),
      'fetchedAt': _latestYahooTimestamp(value, const [
        'fetched_at',
        'fetchedAt',
        'updated_at',
      ]),
    };
  }

  String? _latestYahooTimestamp(Object? value, List<String> keys) {
    String? latest;
    final seen = <Object>{};

    void visit(Object? node) {
      if (node == null) return;
      if (node is Iterable) {
        for (final item in node) {
          visit(item);
        }
        return;
      }
      if (node is! Map) return;
      if (seen.contains(node)) return;
      seen.add(node);
      for (final key in keys) {
        final raw = node[key];
        if (raw == null) continue;
        final text = '$raw';
        if (text.isEmpty) continue;
        if (latest == null || text.compareTo(latest!) > 0) latest = text;
      }
      for (final child in node.values) {
        visit(child);
      }
    }

    visit(value);
    return latest;
  }

  Map<String, dynamic> _withEarningsRelatedInterfaces(
    ToolContext context,
    String symbol,
    Map<String, dynamic> result,
  ) {
    final datasets = _readEarningsDatasets(context, symbol);
    return {
      ...result,
      'count': _earningsDatasetCount(datasets),
      'datasets': datasets,
      'relatedInterfaces': _earningsRelatedInterfaces(datasets),
    };
  }

  Map<String, dynamic> _throwEmptyProviderErrors(
    Map<String, dynamic> result,
    String label,
  ) {
    final count = result['count'];
    final errors = result['errors'];
    if ((count is num && count == 0) && errors is List && errors.isNotEmpty) {
      throw StateError(
        '$label returned no rows: ${errors.map((item) => '$item').join('; ')}',
      );
    }
    return result;
  }

  Map<String, Map<String, dynamic>> _readEarningsDatasets(
    ToolContext context,
    String symbol,
  ) {
    return {
      'profile': queryDataset(context, symbol, const {'dataset': 'profile'}),
      'statements': queryDataset(context, symbol, const {
        'dataset': 'statements',
      }),
      'earnings_calendar': queryDataset(context, symbol, const {
        'dataset': 'earnings_calendar',
      }),
      'earnings_history': queryDataset(context, symbol, const {
        'dataset': 'earnings_history',
      }),
      'earnings_estimates': queryDataset(context, symbol, const {
        'dataset': 'earnings_estimates',
      }),
      'eps_revisions': queryDataset(context, symbol, const {
        'dataset': 'eps_revisions',
      }),
      'eps_trend': queryDataset(context, symbol, const {
        'dataset': 'eps_trend',
      }),
      'income_statement': queryDataset(context, symbol, const {
        'dataset': 'income_statement',
      }),
      'balance_sheet': queryDataset(context, symbol, const {
        'dataset': 'balance_sheet',
      }),
      'cash_flow': queryDataset(context, symbol, const {
        'dataset': 'cash_flow',
      }),
      'quarterly_financial_statements': queryDataset(context, symbol, const {
        'dataset': 'quarterly_financial_statements',
      }),
      'quarterly_income_statement': queryDataset(context, symbol, const {
        'dataset': 'quarterly_income_statement',
      }),
      'quarterly_balance_sheet': queryDataset(context, symbol, const {
        'dataset': 'quarterly_balance_sheet',
      }),
      'quarterly_cash_flow': queryDataset(context, symbol, const {
        'dataset': 'quarterly_cash_flow',
      }),
      'recommendations': queryDataset(context, symbol, const {
        'dataset': 'recommendations',
      }),
      'upgrade_downgrade_events': queryDataset(context, symbol, const {
        'dataset': 'upgrade_downgrade_events',
      }),
      'holders': queryDataset(context, symbol, const {'dataset': 'holders'}),
      'major_holders': queryDataset(context, symbol, const {
        'dataset': 'major_holders',
      }),
      'institutional_holders': queryDataset(context, symbol, const {
        'dataset': 'institutional_holders',
      }),
      'mutualfund_holders': queryDataset(context, symbol, const {
        'dataset': 'mutual_fund_holders',
      }),
      'insiders': queryDataset(context, symbol, const {'dataset': 'insiders'}),
    };
  }

  int _earningsDatasetCount(Map<String, Map<String, dynamic>> datasets) {
    return datasets.values.fold<int>(
      0,
      (sum, item) => sum + ((item['count'] as num?)?.toInt() ?? 0),
    );
  }

  List<Map<String, Object?>> _earningsRelatedInterfaces(
    Map<String, Map<String, dynamic>> datasets,
  ) {
    const specs = {
      'profile': {
        'interfaceId': 'global.company_profile',
        'canonicalTable': 'yfinance_profile_fields',
      },
      'statements': {
        'interfaceId': 'global.financial_statements',
        'canonicalTable': 'yfinance_statement_items',
      },
      'earnings_calendar': {
        'interfaceId': 'global.earnings_calendar',
        'canonicalTable': 'yfinance_statement_items',
      },
      'earnings_history': {
        'interfaceId': 'global.earnings_history',
        'canonicalTable': 'yfinance_statement_items',
      },
      'earnings_estimates': {
        'interfaceId': 'global.earnings_estimates',
        'canonicalTable': 'yfinance_statement_items',
      },
      'eps_revisions': {
        'interfaceId': 'global.eps_revisions',
        'canonicalTable': 'yfinance_statement_items',
      },
      'eps_trend': {
        'interfaceId': 'global.eps_trend',
        'canonicalTable': 'yfinance_statement_items',
      },
      'income_statement': {
        'interfaceId': 'global.income_statement',
        'canonicalTable': 'yfinance_statement_items',
      },
      'balance_sheet': {
        'interfaceId': 'global.balance_sheet',
        'canonicalTable': 'yfinance_statement_items',
      },
      'cash_flow': {
        'interfaceId': 'global.cash_flow',
        'canonicalTable': 'yfinance_statement_items',
      },
      'quarterly_financial_statements': {
        'interfaceId': 'global.quarterly_financial_statements',
        'canonicalTable': 'yfinance_statement_items',
      },
      'quarterly_income_statement': {
        'interfaceId': 'global.quarterly_income_statement',
        'canonicalTable': 'yfinance_statement_items',
      },
      'quarterly_balance_sheet': {
        'interfaceId': 'global.quarterly_balance_sheet',
        'canonicalTable': 'yfinance_statement_items',
      },
      'quarterly_cash_flow': {
        'interfaceId': 'global.quarterly_cash_flow',
        'canonicalTable': 'yfinance_statement_items',
      },
      'recommendations': {
        'interfaceId': 'global.recommendations',
        'canonicalTable': 'yfinance_recommendations',
      },
      'upgrade_downgrade_events': {
        'interfaceId': 'global.upgrade_downgrade_events',
        'canonicalTable': 'yfinance_recommendations',
      },
      'holders': {
        'interfaceId': 'global.holders',
        'canonicalTable': 'yfinance_holders',
      },
      'major_holders': {
        'interfaceId': 'global.major_holders',
        'canonicalTable': 'yfinance_holders',
      },
      'institutional_holders': {
        'interfaceId': 'global.institutional_holders',
        'canonicalTable': 'yfinance_holders',
      },
      'mutualfund_holders': {
        'interfaceId': 'global.mutual_fund_holders',
        'canonicalTable': 'yfinance_holders',
      },
      'insiders': {
        'interfaceId': 'global.insider_transactions',
        'canonicalTable': 'yfinance_insider_transactions',
      },
    };
    return specs.entries.map((entry) {
      final dataset = datasets[entry.value['sourceDataset'] ?? entry.key];
      return {
        'interfaceId': entry.value['interfaceId'],
        'provider': 'yfinance',
        'source': 'yahoo',
        'canonicalTable': entry.value['canonicalTable'],
        'rowCount': (dataset?['count'] as num?)?.toInt() ?? 0,
      };
    }).toList();
  }

  DataApiProviderConstraint _constraintFromInput(Map<String, dynamic> input) {
    final rawProvider = input['provider'] ?? input['source'];
    final providers = rawProvider == null
        ? const <FinanceProvider>[]
        : const ProviderPolicy().normalizeProviders(rawProvider);
    final provider = providers.isEmpty ? null : providers.first;
    final providerMode = switch ('${input['providerMode'] ?? ''}') {
      'strict' => DataApiProviderMode.strict,
      'preferred' => DataApiProviderMode.preferred,
      _ =>
        provider == null
            ? DataApiProviderMode.auto
            : DataApiProviderMode.strict,
    };
    return DataApiProviderConstraint(
      provider: provider,
      providerMode: providerMode,
      allowFallback: input['allowFallback'] is bool
          ? input['allowFallback'] as bool
          : true,
      allowDegraded: input['allowDegraded'] is bool
          ? input['allowDegraded'] as bool
          : false,
    );
  }

  bool _isUsableResult(Map<String, dynamic> result) {
    final count = result['count'];
    if (count is num) return count > 0;
    final expiryCount = result['expiryCount'];
    final contractCount = result['contractCount'];
    if (expiryCount is num || contractCount is num) {
      return (expiryCount is num ? expiryCount : 0) > 0 ||
          (contractCount is num ? contractCount : 0) > 0;
    }
    final data = result['data'];
    if (data is List) return data.isNotEmpty;
    return result.isNotEmpty && !result.containsKey('error');
  }
}
