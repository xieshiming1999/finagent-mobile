part of 'market_data_query_action_service.dart';

extension _MarketDataQueryActionLocalReadbacks on MarketDataQueryActionService {
  Map<String, dynamic> _queryIndexQuoteOverview(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final limit = _inputLimit(input, coreCnMarketIndexCodes.length);
    return _queryIndexQuoteRows(
      coreCnMarketIndexCodes.take(limit).toList(),
      input,
      context,
      action: 'query_index_quote',
      emptyDecision:
          'cacheFirst strict index quote read found no reusable quote_snapshot rows for common index symbols',
    );
  }

  Map<String, dynamic> _queryIndexQuoteBasket(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final limit = _inputLimit(input, symbols.length);
    return _queryIndexQuoteRows(
      symbols.map(_cleanQuoteCode).take(limit).toList(),
      input,
      context,
      action: 'query_quote',
      emptyDecision:
          'cacheFirst strict index quote read found no reusable quote_snapshot rows for the requested index basket',
    );
  }

  Map<String, dynamic> _queryIndexQuoteRows(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context, {
    required String action,
    required String emptyDecision,
  }) {
    final providerConstraint = _indexQuoteCacheConstraint(input);
    final rows = <StockQuote>[];
    final seen = <String>{};
    for (final symbol in symbols) {
      final matches = _queryPersistedQuotesWithConstraint(
        this,
        context,
        symbol,
        limit: 1,
        constraint: providerConstraint,
      );
      for (final row in matches) {
        if (!_hasIndexQuoteIdentity(row)) continue;
        if (!coreCnMarketIndexHasPlausiblePrice(row.code, row.price)) continue;
        if (seen.add(row.code)) rows.add(row);
      }
    }
    final sourceProviders = _quoteSourceProviders(rows);
    return {
      'action': action,
      'symbols': symbols,
      'interfaceId': 'index.quote',
      'provider': 'local',
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (sourceProviders.isNotEmpty) 'sourceProviders': sourceProviders,
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? emptyDecision
          : 'cacheFirst read reusable local index.quote rows before provider routing',
      'canonicalSchema': 'quote_snapshot',
      'canonicalTable': 'quote_snapshot',
      'count': rows.length,
      'source': 'local quote_snapshot',
      'data': rows.map((row) => row.toJson()).toList(),
    };
  }

  Map<String, dynamic> _queryQuoteBatch(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final providerConstraint = _providerCacheConstraint(input);
    final perSymbolLimit = _inputLimit(input, 1);
    final rows = <StockQuote>[];
    final seen = <String>{};
    for (final symbol in symbols) {
      final matches = _queryPersistedQuotesWithConstraint(
        this,
        context,
        symbol,
        limit: perSymbolLimit,
        constraint: providerConstraint,
      );
      for (final row in matches) {
        final key = [row.code, row.timestamp ?? '', row.source].join('|');
        if (seen.add(key)) rows.add(row);
      }
    }
    final sourceProviders = _quoteSourceProviders(rows);
    return {
      'action': action,
      'symbols': symbols,
      'interfaceId': 'stock.quote',
      'provider': 'local',
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      if (sourceProviders.isNotEmpty) 'sourceProviders': sourceProviders,
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no quote_snapshot rows matched the requested symbols'
                : 'cacheFirst read reusable local data; no quote_snapshot rows matched the requested symbols'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable quote_snapshot rows for requested symbols',
      'canonicalSchema': 'quote_snapshot',
      'canonicalTable': 'quote_snapshot',
      'count': rows.length,
      'source': 'local quote_snapshot',
      'data': rows.map((row) => row.toJson()).toList(),
    };
  }

  Map<String, dynamic> _queryQuote(
    String action,
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final providerConstraint = action == 'query_index_quote'
        ? _indexQuoteCacheConstraint(input)
        : _providerCacheConstraint(input);
    final rows = _queryPersistedQuotesWithConstraint(
      this,
      context,
      symbol,
      limit: _inputLimit(input, 20),
      constraint: providerConstraint,
    );
    final sourceProviders = _quoteSourceProviders(rows);
    final identity =
        store?.queryStockIdentity(symbol) ??
        _dataManager?.queryStockIdentity(symbol);
    final resolved = _resolveQuoteReadback(
      action,
      identity: identity,
      rows: rows,
    );
    return {
      'action': action,
      'symbol': symbol,
      'interfaceId': resolved,
      'provider': 'local',
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      if (sourceProviders.isNotEmpty) 'sourceProviders': sourceProviders,
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no quote_snapshot rows matched the requirement'
                : 'cacheFirst read reusable local data; no quote_snapshot rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable quote_snapshot rows',
      'canonicalSchema': 'quote_snapshot',
      'canonicalTable': 'quote_snapshot',
      'count': rows.length,
      'source': 'local quote_snapshot',
      'data': rows.map((row) => row.toJson()).toList(),
    };
  }

  String _resolveQuoteReadback(
    String action, {
    Map<String, dynamic>? identity,
    required List<StockQuote> rows,
  }) {
    if (action == 'query_index_quote') return 'index.quote';
    if (action == 'query_etf_quote') return 'fund.etf_quote';
    if (action == 'query_listed_fund_quote') return 'fund.listed_fund_quote';
    if (action == 'query_bond_quote') return 'bond.convertible_quote';
    final stockType = '${identity?['stock_type'] ?? ''}'.trim().toLowerCase();
    final market = '${identity?['market'] ?? ''}'.trim().toUpperCase();
    final latest = rows.isEmpty ? null : rows.first;
    final source = latest?.source.toLowerCase() ?? '';
    final name = latest?.name ?? identity?['name']?.toString() ?? '';
    if (stockType == 'etf' || market == 'ETF') return 'fund.etf_quote';
    if (stockType == 'listed_fund' || market == 'LISTED_FUND') {
      return 'fund.listed_fund_quote';
    }
    if (stockType == 'convertible_bond' ||
        market == 'CONVERTIBLE_BOND' ||
        RegExp(
          r'^(11|12)\d{4}$',
        ).hasMatch(symbolFromRowsOrIdentity(rows, identity))) {
      return 'bond.convertible_quote';
    }
    if (stockType == 'index' ||
        source.contains('index_quote') ||
        name.contains('指数')) {
      return 'index.quote';
    }
    return 'stock.quote';
  }

  String symbolFromRowsOrIdentity(
    List<StockQuote> rows,
    Map<String, dynamic>? identity,
  ) {
    if (rows.isNotEmpty) return rows.first.code;
    return identity?['code']?.toString() ?? '';
  }

  Map<String, dynamic> _queryFundList(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final requestedCodes = _inputFundCodes(symbols, input);
    final limit = _inputLimit(input, requestedCodes.isEmpty ? 50 : 200);
    final rows =
        _storeForContext(context)?.queryFundList(
          fundType: input['fundType'] as String?,
          company: input['company'] as String?,
          codes: requestedCodes,
          limit: limit,
        ) ??
        _dataManager?.queryFundList(
          fundType: input['fundType'] as String?,
          company: input['company'] as String?,
          codes: requestedCodes,
          limit: limit,
        ) ??
        const <Map<String, dynamic>>[];
    final filtered = rows;
    final fetchedAt = _latestValue(filtered, const ['updated_at']);
    return {
      'action': 'query_fund_list',
      if (requestedCodes.isNotEmpty) 'fundCodes': requestedCodes,
      if (input['fundType'] != null) 'fundType': input['fundType'],
      if (input['company'] != null) 'company': input['company'],
      'interfaceId': 'fund.identity_list',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': filtered.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': filtered.isEmpty
          ? 'cacheFirst read reusable local data; no fund_list rows matched the requested fund identity requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_list rows for the requested fund identity requirement',
      'canonicalSchema': 'fund_list',
      'canonicalTable': 'fund_list',
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': filtered.length,
      'source': 'local fund_list',
      'data': filtered,
    };
  }

  Map<String, dynamic> _queryFundNav(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final fundCodes = _inputFundCodes(symbols, input);
    final providerConstraint = _providerCacheConstraint(input);
    final startDate = input['startDate'] as String? ?? '';
    final endDate = input['endDate'] as String? ?? '';
    final requestedLimit = (input['limit'] as num?)?.toInt();
    final perCodeLimit = requestedLimit == null || fundCodes.isEmpty
        ? 120
        : (requestedLimit / fundCodes.length).ceil().clamp(1, 500).toInt();
    final fundClassHints = _fundClassHintsForCodes(context, fundCodes);
    final knownMoneyFundCodes = fundClassHints
        .where((row) => supportsMoneyFundYieldCategory(row['fundCategory']))
        .map((row) => '${row['code'] ?? ''}')
        .where((code) => code.isNotEmpty)
        .toList();
    final ordinaryFundCodes = fundCodes
        .where((code) => !knownMoneyFundCodes.contains(_cleanFundCode(code)))
        .toList(growable: false);
    final rows = <Map<String, dynamic>>[];
    if (fundCodes.isEmpty) {
      rows.addAll(
        _queryMapsWithProviderConstraint(
          constraint: providerConstraint,
          query: (provider) => _queryFundNavRows(
            context,
            startDate,
            endDate,
            provider,
            requestedLimit ?? 100,
          ),
        ),
      );
    } else {
      for (final code in ordinaryFundCodes) {
        rows.addAll(
          _queryMapsWithProviderConstraint(
            constraint: providerConstraint,
            query: (provider) => _queryFundNavCode(
              context,
              code,
              startDate,
              endDate,
              provider,
              perCodeLimit,
            ),
          ),
        );
      }
    }
    final deduped = _stripProviderPayloadColumns(
      _dedupeMapRows(rows, const ['code', 'date', 'source']),
    );
    final seriesSummary = _fundNavSeriesSummary(deduped);
    final sourceDataTime = _latestValue(deduped, const ['date']);
    final fetchedAt = _latestValue(deduped, const ['fetched_at']);
    final requestedSymbol = symbols.length == 1 ? symbols.first : null;
    return {
      'action': 'query_fund_nav',
      if (fundCodes.isNotEmpty) 'fundCodes': fundCodes,
      if (fundCodes.length == 1) 'symbol': requestedSymbol ?? fundCodes.first,
      if (knownMoneyFundCodes.isNotEmpty)
        'knownMoneyFundCodes': knownMoneyFundCodes,
      if (fundClassHints.isNotEmpty) 'fundClassHints': fundClassHints,
      'interfaceId': 'fund.nav_history',
      'provider': 'local',
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'capabilityId': 'local.cache',
      'cacheStatus': deduped.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': deduped.isEmpty
          ? fundCodes.isEmpty
                ? 'cacheFirst read reusable local data; no fund_nav rows matched the bounded local query'
                : knownMoneyFundCodes.isNotEmpty
                ? 'cacheFirst read reusable local data; no ordinary fund_nav rows matched because ${knownMoneyFundCodes.join(',')} is a known money fund. Use query_fund_money_yield / fund_money_yield for per-10k income and 7-day annualized yield; do not fetch ordinary fund_nav for this fund class.'
                : providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no fund_nav rows matched the requested fund codes'
                : 'cacheFirst read reusable local data; no fund_nav rows matched the requested fund codes'
          : knownMoneyFundCodes.isNotEmpty
          ? 'cacheFirst read reusable ordinary fund_nav rows and excluded known money fund code(s) ${knownMoneyFundCodes.join(',')} from ordinary NAV semantics; use query_fund_money_yield for those codes.'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_nav rows for requested fund codes',
      'canonicalSchema': 'fund_nav',
      'canonicalTable': 'fund_nav',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': deduped.length,
      if (seriesSummary.isNotEmpty) 'seriesSummary': seriesSummary,
      'source': 'local fund_nav',
      'data': deduped,
    };
  }

  List<Map<String, dynamic>> _stripProviderPayloadColumns(
    List<Map<String, dynamic>> rows,
  ) {
    return rows
        .map((row) {
          final clean = Map<String, dynamic>.from(row);
          clean.remove('raw_json');
          return clean;
        })
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _fundClassHintsForCodes(
    ToolContext context,
    List<String> fundCodes,
  ) {
    if (fundCodes.isEmpty) return const <Map<String, dynamic>>[];
    final rows =
        _storeForContext(
          context,
        )?.queryFundList(codes: fundCodes, limit: 200) ??
        _dataManager?.queryFundList(codes: fundCodes, limit: 200) ??
        const <Map<String, dynamic>>[];
    return rows
        .map(
          (row) => {
            'code': row['code'],
            'name': row['name'],
            'fundType': row['fund_type'] ?? row['fundType'],
            'fundCategory': row['fund_category'] ?? row['fundCategory'],
          },
        )
        .toList();
  }

  List<Map<String, dynamic>> _fundNavSeriesSummary(
    List<Map<String, dynamic>> rows,
  ) {
    final byCode = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final code = _cleanFundCode('${row['code'] ?? ''}');
      if (code.isEmpty) continue;
      byCode.putIfAbsent(code, () => <Map<String, dynamic>>[]).add(row);
    }
    final summaries = <Map<String, dynamic>>[];
    for (final entry in byCode.entries) {
      final series = [...entry.value]
        ..sort((a, b) => '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}'));
      if (series.isEmpty) continue;
      final first = series.first;
      final last = series.last;
      final firstNav = _toDouble(first['nav']);
      final lastNav = _toDouble(last['nav']);
      double? cumulativeReturnPct;
      if (firstNav != null && firstNav != 0 && lastNav != null) {
        cumulativeReturnPct = (lastNav / firstNav - 1) * 100;
      }
      double? peak;
      double? maxDrawdownPct;
      for (final row in series) {
        final nav = _toDouble(row['nav']);
        if (nav == null) continue;
        peak = peak == null || nav > peak ? nav : peak;
        if (peak == 0) continue;
        final drawdown = (nav / peak - 1) * 100;
        maxDrawdownPct = maxDrawdownPct == null || drawdown < maxDrawdownPct
            ? drawdown
            : maxDrawdownPct;
      }
      summaries.add({
        'code': entry.key,
        'rows': series.length,
        'startDate': first['date'],
        'endDate': last['date'],
        'startNav': firstNav,
        'endNav': lastNav,
        if (cumulativeReturnPct != null)
          'cumulativeReturnPct': double.parse(
            cumulativeReturnPct.toStringAsFixed(4),
          ),
        if (maxDrawdownPct != null)
          'maxDrawdownPct': double.parse(maxDrawdownPct.toStringAsFixed(4)),
        'source': last['source'],
        'fetchedAt': last['fetched_at'],
      });
    }
    return summaries;
  }

  double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  List<Map<String, dynamic>> _queryFundNavRows(
    ToolContext context,
    String startDate,
    String endDate,
    String? provider,
    int limit,
  ) {
    return _storeForContext(context)?.queryFundNavRows(
          startDate: startDate,
          endDate: endDate,
          source: provider,
          limit: limit,
        ) ??
        _dataManager?.queryFundNavRows(
          startDate: startDate,
          endDate: endDate,
          source: provider,
          limit: limit,
        ) ??
        const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _queryFundNavCode(
    ToolContext context,
    String code,
    String startDate,
    String endDate,
    String? source,
    int? limit,
  ) {
    final variants = [code, '$code.OF'];
    final rows = <Map<String, dynamic>>[];
    for (final variant in variants) {
      final queried =
          _storeForContext(context)?.queryFundNav(
            variant,
            startDate: startDate,
            endDate: endDate,
            source: source,
            limit: limit,
          ) ??
          _dataManager?.queryFundNav(
            variant,
            startDate: startDate,
            endDate: endDate,
            source: source,
            limit: limit,
          ) ??
          const <Map<String, dynamic>>[];
      rows.addAll(
        queried.map((row) {
          final normalized = Map<String, dynamic>.from(row);
          normalized['code'] ??= normalized['fund_code'] ?? variant;
          return normalized;
        }),
      );
    }
    return rows;
  }

  Map<String, dynamic> _queryFundPerformance(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final fundCodes = _inputFundCodes(symbols, input);
    final providerConstraint = _providerCacheConstraint(input);
    final metricDate =
        input['metricDate'] as String? ?? input['date'] as String?;
    final limit = _inputLimit(input, 100);
    final rows = <Map<String, dynamic>>[];
    if (fundCodes.isEmpty) {
      rows.addAll(
        _queryMapsWithProviderConstraint(
          constraint: providerConstraint,
          query: (provider) => _queryFundPerformanceRows(
            context,
            code: null,
            provider: provider,
            metricDate: metricDate,
            limit: limit,
          ),
        ),
      );
    } else {
      for (final code in fundCodes) {
        rows.addAll(
          _queryMapsWithProviderConstraint(
            constraint: providerConstraint,
            query: (provider) => _queryFundPerformanceRows(
              context,
              code: code,
              provider: provider,
              metricDate: metricDate,
              limit: limit,
            ),
          ),
        );
      }
    }
    final deduped = _dedupeMapRows(rows, const [
      'code',
      'metric_date',
      'provider',
      'source_action',
    ]);
    final sourceDataTime = _latestValue(deduped, const ['metric_date']);
    final fetchedAt = _latestValue(deduped, const ['fetched_at']);
    final effectiveSource = providerConstraint.effectiveSource;
    return {
      'action': 'query_fund_performance',
      if (fundCodes.isNotEmpty) 'fundCodes': fundCodes,
      if (metricDate != null) 'metricDate': metricDate,
      'interfaceId': 'fund.performance_metrics',
      'provider': 'local',
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (effectiveSource != null) 'cacheSourceFilter': effectiveSource,
      'capabilityId': 'local.cache',
      'cacheStatus': deduped.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': deduped.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no fund_performance_metrics rows matched the requested fund codes'
                : 'cacheFirst read reusable local data; no fund_performance_metrics rows matched the requested fund codes'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_performance_metrics rows for requested fund codes',
      'canonicalSchema': 'fund_performance_metrics',
      'canonicalTable': 'fund_performance_metrics',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': deduped.length,
      'source': 'local fund_performance_metrics',
      'data': deduped,
    };
  }

  List<Map<String, dynamic>> _queryFundPerformanceRows(
    ToolContext context, {
    required String? code,
    required String? provider,
    required String? metricDate,
    required int limit,
  }) {
    return _storeForContext(context)?.queryFundPerformanceMetrics(
          code: code,
          provider: provider,
          metricDate: metricDate,
          limit: limit,
        ) ??
        _dataManager?.queryFundPerformanceMetrics(
          code: code,
          provider: provider,
          metricDate: metricDate,
          limit: limit,
        ) ??
        const <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _queryFundHolding(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final fundCodes = _inputFundCodes(symbols, input);
    final stockCode = input['stockCode'] as String?;
    final reportDate = input['reportDate'] as String?;
    final limit = _inputLimit(input, 100);
    final rows = <Map<String, dynamic>>[];
    if (fundCodes.isEmpty) {
      rows.addAll(
        store?.queryFundHolding(
              stockCode: stockCode,
              reportDate: reportDate,
              limit: limit,
            ) ??
            _dataManager?.queryFundHolding(
              stockCode: stockCode,
              reportDate: reportDate,
              limit: limit,
            ) ??
            const <Map<String, dynamic>>[],
      );
    } else {
      for (final code in fundCodes) {
        rows.addAll(
          store?.queryFundHolding(
                fundCode: code,
                stockCode: stockCode,
                reportDate: reportDate,
                limit: limit,
              ) ??
              _dataManager?.queryFundHolding(
                fundCode: code,
                stockCode: stockCode,
                reportDate: reportDate,
                limit: limit,
              ) ??
              const <Map<String, dynamic>>[],
        );
      }
    }
    final deduped = _dedupeMapRows(rows, const [
      'fund_code',
      'stock_code',
      'report_date',
      'source',
    ]);
    final sourceDataTime = _latestValue(rows, const ['report_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_fund_holding',
      if (fundCodes.isNotEmpty) 'fundCodes': fundCodes,
      if (input['stockCode'] != null) 'stockCode': input['stockCode'],
      if (input['reportDate'] != null) 'reportDate': input['reportDate'],
      'interfaceId': 'fund.holding',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': deduped.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': deduped.isEmpty
          ? 'cacheFirst read reusable local data; no fund_holding rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_holding rows',
      'canonicalSchema': 'fund_holding',
      'canonicalTable': 'fund_holding',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': deduped.length,
      'source': 'local fund_holding',
      'data': deduped,
    };
  }

  Map<String, dynamic> _queryFundManager(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final fundCode =
        input['fundCode'] as String? ??
        input['code'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    final rows =
        store?.queryFundManager(
          company: input['company'] as String?,
          manager: input['manager'] as String?,
          fundCode: fundCode,
          limit: _inputLimit(input, 100),
        ) ??
        _dataManager?.queryFundManager(
          company: input['company'] as String?,
          manager: input['manager'] as String?,
          fundCode: fundCode,
          limit: _inputLimit(input, 100),
        ) ??
        const <Map<String, dynamic>>[];
    final fetchedAt = _latestValue(rows, const ['updated_at']);
    return {
      'action': 'query_fund_manager',
      if (fundCode != null) 'fundCode': fundCode,
      if (input['company'] != null) 'company': input['company'],
      if (input['manager'] != null) 'manager': input['manager'],
      'interfaceId': 'fund.manager',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no fund_manager rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable fund_manager rows',
      'canonicalSchema': 'fund_manager',
      'canonicalTable': 'fund_manager',
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local fund_manager',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryIndexConstituents(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final providerConstraint = _providerCacheConstraint(input);
    final indexCode =
        input['indexCode'] as String? ??
        input['code'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    final asOfDate = input['asOfDate'] as String? ?? input['date'] as String?;
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      query: (provider) =>
          store?.queryIndexConstituents(
            indexCode: indexCode,
            stockCode: input['stockCode'] as String?,
            asOfDate: asOfDate,
            provider: provider,
            limit: _inputLimit(input, 300),
          ) ??
          _dataManager?.queryIndexConstituents(
            indexCode: indexCode,
            stockCode: input['stockCode'] as String?,
            asOfDate: asOfDate,
            provider: provider,
            limit: _inputLimit(input, 300),
          ) ??
          const <Map<String, dynamic>>[],
    );
    final sourceDataTime = _latestValue(rows, const ['as_of_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_index_constituents',
      if (indexCode != null) 'indexCode': indexCode,
      if (input['stockCode'] != null) 'stockCode': input['stockCode'],
      if (asOfDate != null) 'asOfDate': asOfDate,
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'interfaceId': 'index.constituents',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no index_constituent rows matched the requirement'
                : 'cacheFirst read reusable local data; no index_constituent rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable index_constituent rows',
      'canonicalSchema': 'index_constituent',
      'canonicalTable': 'index_constituent',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local index_constituent',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryFinanceNews(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final providerConstraint = _providerCacheConstraint(input);
    final source = input['source'] as String?;
    final keyword = input['keyword'] as String? ?? input['query'] as String?;
    var rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      fallbackProvider: source,
      query: (provider) =>
          _storeForContext(context)?.queryFinanceNews(
            keyword: keyword,
            source: provider,
            limit: _inputLimit(input, 50),
          ) ??
          _dataManager?.queryFinanceNews(
            keyword: keyword,
            source: provider,
            limit: _inputLimit(input, 50),
          ) ??
          const <Map<String, dynamic>>[],
    );
    final queryMiss = rows.isEmpty && keyword != null && keyword.trim().isNotEmpty;
    if (queryMiss) {
      rows = _queryMapsWithProviderConstraint(
        constraint: providerConstraint,
        fallbackProvider: source,
        query: (provider) =>
            _storeForContext(context)?.queryFinanceNews(
              source: provider,
              limit: _inputLimit(input, 50),
            ) ??
            _dataManager?.queryFinanceNews(
              source: provider,
              limit: _inputLimit(input, 50),
            ) ??
            const <Map<String, dynamic>>[],
      );
    }
    final sourceDataTime = _latestValue(rows, const ['published_at']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_finance_news',
      if (input['keyword'] != null) 'keyword': input['keyword'],
      if (input['query'] != null) 'query': input['query'],
      if (input['source'] != null) 'sourceFilter': input['source'],
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      'interfaceId': 'news.finance_feed',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no finance_news rows matched the requirement'
                : 'cacheFirst read reusable local data; no finance_news rows matched the requirement'
          : queryMiss
              ? 'cacheFirst target-specific finance_news query returned no rows; reused latest governed finance_news rows as broad macro/news context'
              : 'cacheFirst read reusable local data before provider routing; cache reader returned usable finance_news rows',
      if (queryMiss) 'queryMiss': keyword,
      'canonicalSchema': 'finance_news',
      'canonicalTable': 'finance_news',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local finance_news',
      'data': rows,
      'analysisEvidence': _financeNewsAnalysisEvidence(
        rows: rows,
        sourceDataTime: sourceDataTime,
        fetchedAt: fetchedAt,
        keyword: input['keyword'] as String? ?? input['query'] as String?,
      ),
    };
  }

  Map<String, dynamic> _financeNewsAnalysisEvidence({
    required List<Map<String, dynamic>> rows,
    required String? sourceDataTime,
    required String? fetchedAt,
    required String? keyword,
  }) {
    final top = rows.isEmpty ? null : rows.first;
    final sources = rows
        .map((row) => row['source'])
        .whereType<Object>()
        .map((value) => '$value')
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.news,
      subjectType: AnalysisSubjectType.news,
      subjectId: keyword == null || keyword.trim().isEmpty
          ? 'finance-news'
          : keyword.trim(),
      subjectName: keyword == null || keyword.trim().isEmpty
          ? 'Finance news'
          : keyword.trim(),
      observedFacts: [
        'rows=${rows.length}',
        if (keyword != null && keyword.trim().isNotEmpty)
          'keyword=${keyword.trim()}',
        if (sourceDataTime != null) 'sourceDataTime=$sourceDataTime',
        if (top != null) 'topTitle=${top['title'] ?? '-'}',
      ],
      interpretations: [
        rows.isEmpty ? 'finance_news:missing' : 'finance_news:available',
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
        sources: sources.isEmpty ? const ['local finance_news'] : sources,
        interfaceId: 'news.finance_feed',
        capabilityId: 'local.cache',
        canonicalSchema: 'finance_news',
        canonicalTable: 'finance_news',
        readbackAction: 'query_finance_news',
        sourceDataTime: sourceDataTime ?? '',
        fetchedAt: fetchedAt ?? '',
        cacheStatus: rows.isEmpty ? 'cache-miss' : 'cache-hit',
        coverageStatus: rows.isEmpty
            ? AnalysisCoverageStatus.none
            : AnalysisCoverageStatus.sufficientForAnalysis,
      ),
    ).toJson();
  }

  Map<String, dynamic> _queryStockShareholders(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final store = _storeForContext(context);
    final providerConstraint = _providerCacheConstraint(input);
    final code =
        input['code'] as String? ??
        input['symbol'] as String? ??
        (symbols.isEmpty ? null : symbols.first);
    final holderName =
        input['holderName'] as String? ??
        input['name'] as String? ??
        input['query'] as String?;
    final reportDate =
        input['reportDate'] as String? ?? input['date'] as String?;
    final source = input['source'] as String?;
    final rows = _queryMapsWithProviderConstraint(
      constraint: providerConstraint,
      fallbackProvider: source,
      query: (provider) =>
          store?.queryStockShareholders(
            code: code,
            holderName: holderName,
            reportDate: reportDate,
            source: provider,
            limit: _inputLimit(input, 100),
          ) ??
          _dataManager?.queryStockShareholders(
            code: code,
            holderName: holderName,
            reportDate: reportDate,
            source: provider,
            limit: _inputLimit(input, 100),
          ) ??
          const <Map<String, dynamic>>[],
    );
    final sourceDataTime = _latestValue(rows, const ['report_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_stock_shareholders',
      if (code != null) 'symbol': code,
      if (holderName != null) 'holderName': holderName,
      if (reportDate != null) 'reportDate': reportDate,
      if (providerConstraint.requestedProvider != null)
        'providerFilter': providerConstraint.requestedProvider,
      if (providerConstraint.providerMode != null)
        'providerMode': providerConstraint.providerMode,
      if (providerConstraint.effectiveSource != null)
        'cacheSourceFilter': providerConstraint.effectiveSource,
      if (input['source'] != null) 'sourceFilter': input['source'],
      'interfaceId': 'stock.shareholders',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? providerConstraint.isStrict
                ? 'cacheFirst strict provider read rejected local cache rows that did not match ${providerConstraint.requestedProvider}; no stock_shareholder rows matched the requirement'
                : 'cacheFirst read reusable local data; no stock_shareholder rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable stock_shareholder rows',
      'canonicalSchema': 'stock_shareholder',
      'canonicalTable': 'stock_shareholder',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'count': rows.length,
      'source': 'local stock_shareholder',
      'data': rows,
    };
  }
}
