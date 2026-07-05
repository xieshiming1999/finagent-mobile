import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class TdxMarketDataQueryService {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  TdxMarketDataQueryService({DataManager? dataManager})
    : _dataManager = dataManager ?? DataManager();

  ReusableDataStore? _storeForContext(ToolContext context) {
    final basePath = context.basePath;
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  Map<String, dynamic> queryAction(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    switch (action) {
      case 'query_ex_categories':
        return _queryExCategories(input, context);
      case 'query_tdx_count':
        return _queryTdxCount(input, context);
      case 'query_tdx_sampling':
        return _queryTdxSampling(symbols, input, context);
      case 'query_ex_table':
        return _queryExTable(input, context);
      case 'query_tick_chart':
        return _queryTickChart(symbols.first, input, context);
      case 'query_transactions':
        return _queryTransactions(symbols.first, input, context);
      case 'query_volume_profile':
        return _queryVolumeProfile(symbols.first, input, context);
      case 'query_xdxr':
        return _queryXdxr(symbols.first, input, context);
      case 'query_auction':
        return _queryAuction(symbols.first, input, context);
      case 'query_momentum':
        return _queryMomentum(symbols.first, input, context);
      case 'query_top_board':
        return _queryTopBoard(symbols, input, context);
      case 'query_tdx_block_member':
        return _queryTdxBlockMembers(symbols, input, context);
      case 'query_stock_company_info':
      case 'query_company_info':
      case 'query_fund_company_info':
      case 'query_fund_investor_holders':
      case 'query_index_profile':
        return _queryCompanyInfo(symbols.first, input, context);
      default:
        throw ArgumentError('Unsupported TDX query action: $action');
    }
  }

  Map<String, dynamic> _queryExCategories(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(
          context,
        )?.queryExCategories(limit: _inputLimit(input, 100)) ??
        _dataManager.queryExCategories(limit: _inputLimit(input, 100));
    return {
      'action': 'query_ex_categories',
      ..._localReadback(
        rows,
        interfaceId: 'provider.table_metadata',
        canonicalSchema: 'provider_table_metadata',
        canonicalTable: 'ex_category',
      ),
      'count': rows.length,
      'source': 'local ex_category',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryTdxCount(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryTdxSecurityCounts(
          scope: input['scope'] as String?,
          market: input['market']?.toString(),
          limit: _inputLimit(input, 20),
        ) ??
        _dataManager.queryTdxSecurityCounts(
          scope: input['scope'] as String?,
          market: input['market']?.toString(),
          limit: _inputLimit(input, 20),
        );
    return {
      'action': 'query_tdx_count',
      if (input['scope'] != null) 'scope': input['scope'],
      if (input['market'] != null) 'market': '${input['market']}',
      ..._localReadback(
        rows,
        interfaceId: 'provider.coverage',
        canonicalSchema: 'provider_coverage',
        canonicalTable: 'tdx_security_count',
      ),
      'count': rows.length,
      'source': 'local tdx_security_count',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryTdxSampling(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryTdxChartSampling(
          scope: input['scope'] as String?,
          code: symbols.isNotEmpty ? symbols.first : input['code'] as String?,
          market: input['market']?.toString(),
          category: input['category']?.toString(),
          limit: _inputLimit(input, 120),
        ) ??
        _dataManager.queryTdxChartSampling(
          scope: input['scope'] as String?,
          code: symbols.isNotEmpty ? symbols.first : input['code'] as String?,
          market: input['market']?.toString(),
          category: input['category']?.toString(),
          limit: _inputLimit(input, 120),
        );
    return {
      'action': 'query_tdx_sampling',
      if (input['scope'] != null) 'scope': input['scope'],
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      if (input['code'] != null) 'code': input['code'],
      if (input['market'] != null) 'market': '${input['market']}',
      if (input['category'] != null) 'category': '${input['category']}',
      ..._localReadback(
        rows,
        interfaceId: 'provider.coverage',
        canonicalSchema: 'provider_coverage',
        canonicalTable: 'tdx_chart_sampling',
      ),
      'count': rows.length,
      'source': 'local tdx_chart_sampling',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryExTable(
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryExTableEntries(
          code: input['code'] as String?,
          category: input['category']?.toString(),
          limit: _inputLimit(input, 100),
        ) ??
        _dataManager.queryExTableEntries(
          code: input['code'] as String?,
          category: input['category']?.toString(),
          limit: _inputLimit(input, 100),
        );
    return {
      'action': 'query_ex_table',
      if (input['code'] != null) 'code': input['code'],
      if (input['category'] != null) 'category': '${input['category']}',
      ..._localReadback(
        rows,
        interfaceId: 'provider.table_metadata',
        canonicalSchema: 'provider_table_metadata',
        canonicalTable: 'ex_table_entry',
      ),
      'count': rows.length,
      'source': 'local ex_table_entry',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryTickChart(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryTickChart(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 240),
        ) ??
        _dataManager.queryTickChart(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 240),
        );
    return {
      'action': 'query_tick_chart',
      'symbol': symbol,
      ..._localReadback(
        rows,
        interfaceId: 'stock.tick_chart_intraday',
        canonicalSchema: 'tick_chart_intraday',
        canonicalTable: 'tick_chart_intraday',
      ),
      'count': rows.length,
      'source': 'local tick_chart_intraday',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryTransactions(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryTransactions(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 100),
        ) ??
        _dataManager.queryTransactions(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 100),
        );
    return {
      'action': 'query_transactions',
      'symbol': symbol,
      ..._localReadback(
        rows,
        interfaceId: _transactionsInterfaceId(symbol, input),
        canonicalSchema: 'transactions',
        canonicalTable: 'transactions',
      ),
      'count': rows.length,
      'source': 'local transactions',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryVolumeProfile(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryVolumeProfile(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 200),
        ) ??
        _dataManager.queryVolumeProfile(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 200),
        );
    return {
      'action': 'query_volume_profile',
      'symbol': symbol,
      ..._localReadback(
        rows,
        interfaceId: 'stock.volume_profile',
        canonicalSchema: 'volume_profile',
        canonicalTable: 'volume_profile',
      ),
      'count': rows.length,
      'source': 'local volume_profile',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryXdxr(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(
          context,
        )?.queryXdxrEvents(symbol, limit: _inputLimit(input, 50)) ??
        _dataManager.queryXdxrEvents(symbol, limit: _inputLimit(input, 50));
    final sourceDataTime = _latestValue(rows, const ['event_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_xdxr',
      'symbol': symbol,
      'interfaceId': 'stock.xdxr_events',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no xdxr_event rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable xdxr_event rows',
      'canonicalSchema': 'xdxr_event',
      'canonicalTable': 'xdxr_event',
      ..._optionalStringEntry('sourceDataTime', sourceDataTime),
      ..._optionalStringEntry('fetchedAt', fetchedAt),
      'count': rows.length,
      'source': 'local xdxr_event',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryAuction(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryAuction(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 100),
        ) ??
        _dataManager.queryAuction(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 100),
        );
    return {
      'action': 'query_auction',
      'symbol': symbol,
      ..._localReadback(
        rows,
        interfaceId: 'stock.auction_snapshot',
        canonicalSchema: 'auction_snapshot',
        canonicalTable: 'auction_snapshot',
      ),
      'count': rows.length,
      'source': 'local auction_snapshot',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryMomentum(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryIndexMomentum(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 200),
        ) ??
        _dataManager.queryIndexMomentum(
          symbol,
          tradeDate: _inputDate(input),
          limit: _inputLimit(input, 200),
        );
    final sourceDataTime = _latestValue(rows, const ['trade_date']);
    final fetchedAt = _latestValue(rows, const ['fetched_at']);
    return {
      'action': 'query_momentum',
      'symbol': symbol,
      'interfaceId': 'index.momentum',
      'provider': 'local',
      'capabilityId': 'local.cache',
      'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      'cacheMode': 'cache-first',
      'cachePolicyMode': 'cacheFirst',
      'cacheDecision': rows.isEmpty
          ? 'cacheFirst read reusable local data; no tdx_index_momentum rows matched the requirement'
          : 'cacheFirst read reusable local data before provider routing; cache reader returned usable tdx_index_momentum rows',
      'canonicalSchema': 'tdx_index_momentum',
      'canonicalTable': 'tdx_index_momentum',
      ..._optionalStringEntry('sourceDataTime', sourceDataTime),
      ..._optionalStringEntry('fetchedAt', fetchedAt),
      'count': rows.length,
      'source': 'local tdx_index_momentum',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryTopBoard(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final rows =
        _storeForContext(context)?.queryTopBoard(
          code: symbols.isEmpty ? null : symbols.first,
          category: input['category']?.toString(),
          side: input['side'] as String?,
          boardDate: _inputDate(input),
          limit: _inputLimit(input, 100),
        ) ??
        _dataManager.queryTopBoard(
          code: symbols.isEmpty ? null : symbols.first,
          category: input['category']?.toString(),
          side: input['side'] as String?,
          boardDate: _inputDate(input),
          limit: _inputLimit(input, 100),
        );
    return {
      'action': 'query_top_board',
      if (symbols.isNotEmpty) 'symbol': symbols.first,
      ..._localReadback(
        rows,
        interfaceId: 'market.tdx_top_board',
        canonicalSchema: 'tdx_top_board',
        canonicalTable: 'tdx_top_board',
      ),
      'count': rows.length,
      'source': 'local tdx_top_board',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryCompanyInfo(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final action = input['_queryAction'] as String? ?? 'query_company_info';
    final defaultInfoType = switch (action) {
      'query_fund_company_info' => 'get_fund_company_info',
      'query_fund_investor_holders' => 'get_fund_holders',
      'query_index_profile' => 'get_index_basicinfo',
      _ => null,
    };
    final infoType = input['infoType'] as String? ?? defaultInfoType;
    final providerConstraint = _ReadbackProviderConstraint.fromInput(input);
    final rows = _queryMapsWithProviderConstraint(
      providerConstraint,
      (provider) =>
          (_storeForContext(context)?.queryCompanyInfo(
                    symbol,
                    infoType: infoType,
                    limit: _inputLimit(input, 20),
                  ) ??
                  _dataManager.queryCompanyInfo(
                    symbol,
                    infoType: infoType,
                    limit: _inputLimit(input, 20),
                  ))
              .where(
                (row) =>
                    provider == null || row['source']?.toString() == provider,
              )
              .toList(),
    );
    final interfaceId = switch (action) {
      'query_stock_company_info' => 'stock.company_info',
      'query_fund_company_info' => 'fund.company_info',
      'query_fund_investor_holders' => 'fund.investor_holders',
      'query_index_profile' => 'index.profile',
      _ => 'stock.company_info',
    };
    return {
      'action': action,
      'symbol': symbol,
      ..._optionalStringEntry('infoType', infoType),
      ..._optionalStringEntry(
        'providerFilter',
        providerConstraint.requestedProvider,
      ),
      ..._optionalStringEntry('providerMode', providerConstraint.providerMode),
      ..._optionalStringEntry(
        'cacheSourceFilter',
        providerConstraint.effectiveProvider,
      ),
      ..._localReadback(
        rows,
        interfaceId: interfaceId,
        canonicalSchema: 'stock_company_info',
        canonicalTable: 'stock_company_info',
      ),
      'count': rows.length,
      'source': 'local stock_company_info',
      'data': rows,
    };
  }

  Map<String, dynamic> _queryTdxBlockMembers(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) {
    final blockCodeInput = input['blockCode']?.toString();
    final filename = input['filename']?.toString();
    final blockName = input['blockName']?.toString();
    final effectiveBlockCode =
        blockCodeInput ??
        ((filename != null &&
                filename.isNotEmpty &&
                blockName != null &&
                blockName.isNotEmpty)
            ? '$filename:$blockName'
            : null);
    final rows =
        _storeForContext(context)?.queryTdxBlockMembers(
          code: symbols.isEmpty ? null : symbols.first,
          blockCode: effectiveBlockCode,
          limit: _inputLimit(input, 100),
        ) ??
        _dataManager.queryTdxBlockMembers(
          code: symbols.isEmpty ? null : symbols.first,
          blockCode: effectiveBlockCode,
          limit: _inputLimit(input, 100),
        );
    return {
      'action': 'query_tdx_block_member',
      ..._optionalStringEntry('symbol', symbols.isEmpty ? null : symbols.first),
      'blockCode': effectiveBlockCode,
      ..._localReadback(
        rows,
        interfaceId: 'market.tdx_block_member',
        canonicalSchema: 'tdx_block_member',
        canonicalTable: 'tdx_block_member',
      ),
      'count': rows.length,
      'source': 'local tdx_block_member',
      'data': rows,
    };
  }
}

Map<String, dynamic> _localReadback(
  List<Map<String, dynamic>> rows, {
  required String interfaceId,
  required String canonicalSchema,
  required String canonicalTable,
  List<String> sourceDataKeys = const [
    'trade_date',
    'board_date',
    'event_date',
    'updated_at',
    'time',
  ],
}) {
  final sourceDataTime = _latestValue(rows, sourceDataKeys);
  final fetchedAt = _latestValue(rows, const ['fetched_at', 'updated_at']);
  return {
    'interfaceId': interfaceId,
    'provider': 'local',
    'capabilityId': 'local.cache',
    'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
    'cacheMode': 'cache-first',
    'cachePolicyMode': 'cacheFirst',
    'canonicalSchema': canonicalSchema,
    'canonicalTable': canonicalTable,
    ..._optionalStringEntry('sourceDataTime', sourceDataTime),
    ..._optionalStringEntry('fetchedAt', fetchedAt),
  };
}

Map<String, String> _optionalStringEntry(String key, String? value) {
  if (value == null) return const {};
  return {key: value};
}

int _inputLimit(Map<String, dynamic> input, int fallback) {
  final value = input['limit'];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return fallback;
}

String? _inputDate(Map<String, dynamic> input) {
  final value = input['date'] ?? input['startDate'];
  if (value == null) return null;
  final text = '$value'.replaceAll('/', '-');
  if (text.length == 8 && !text.contains('-')) {
    return '${text.substring(0, 4)}-${text.substring(4, 6)}-${text.substring(6, 8)}';
  }
  return text.isEmpty ? null : text;
}

String _transactionsInterfaceId(String symbol, Map<String, dynamic> input) {
  final instrumentType =
      '${input['instrumentType'] ?? input['assetType'] ?? ''}'
          .trim()
          .toLowerCase();
  if (instrumentType == 'etf') return 'fund.etf_transactions';
  final clean = symbol
      .replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '')
      .trim();
  return RegExp(r'^(15|16|50|51|52|56|58)\d{4}$').hasMatch(clean)
      ? 'fund.etf_transactions'
      : 'stock.transactions';
}

List<Map<String, dynamic>> _queryMapsWithProviderConstraint(
  _ReadbackProviderConstraint constraint,
  List<Map<String, dynamic>> Function(String? provider) query,
) {
  if (!constraint.isStrict) return query(constraint.requestedProvider);
  for (final provider in constraint.providerAliases) {
    final rows = query(provider);
    if (rows.isNotEmpty) {
      constraint.effectiveProvider = provider;
      return rows;
    }
  }
  return const [];
}

class _ReadbackProviderConstraint {
  final String? requestedProvider;
  final String? providerMode;
  final List<String> providerAliases;
  String? effectiveProvider;

  _ReadbackProviderConstraint({
    required this.requestedProvider,
    required this.providerMode,
    required this.providerAliases,
  });

  factory _ReadbackProviderConstraint.fromInput(Map<String, dynamic> input) {
    final requested = input['provider']?.toString().trim();
    final providerMode = input['providerMode']?.toString().trim();
    final strict =
        requested != null &&
        requested.isNotEmpty &&
        providerMode?.toLowerCase() == 'strict';
    return _ReadbackProviderConstraint(
      requestedProvider: requested == null || requested.isEmpty
          ? null
          : requested,
      providerMode: providerMode == null || providerMode.isEmpty
          ? null
          : providerMode,
      providerAliases: strict ? _providerAliases(requested) : const <String>[],
    );
  }

  bool get isStrict =>
      requestedProvider != null &&
      providerMode?.toLowerCase() == 'strict' &&
      providerAliases.isNotEmpty;

  static List<String> _providerAliases(String provider) {
    switch (provider.trim().toLowerCase()) {
      case 'tdx':
      case 'gotdx':
      case 'tongdaxin':
      case '通达信':
        return const ['tdx', 'gotdx', '通达信'];
      case 'eastmoney':
      case 'em':
      case '东方财富':
        return const ['eastmoney', 'eastmoneyDirect', '东方财富'];
      case 'wind':
      case '万得':
        return const ['wind', 'Wind', '万得'];
      default:
        return [provider];
    }
  }
}

String? _latestValue(List<Map<String, dynamic>> rows, List<String> keys) {
  for (final key in keys) {
    String? latest;
    for (final row in rows) {
      final value = row[key];
      if (value == null) continue;
      final text = '$value'.trim();
      if (text.isEmpty) continue;
      if (latest == null || text.compareTo(latest) > 0) latest = text;
    }
    if (latest != null) return latest;
  }
  return null;
}
