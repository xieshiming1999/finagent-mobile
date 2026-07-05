import '../../../agent/data_fetcher/api_stats.dart';
import '../../../agent/data_fetcher/cn_fetchers.dart';
import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/tool_context.dart';
import '../providers/data_api_interface_contract.dart';
import '../providers/data_api_interface_router.dart';
import 'cache_policy.dart';
import 'extdx_market_data_service.dart';
import 'tdx_market_data_query_service.dart';
import 'tdx_market_data_service.dart';

class MarketDataTdxActionService {
  final TdxMarketDataService _tdx;
  final ExTdxMarketDataService _exTdx;
  final TdxMarketDataQueryService _query;
  final DataApiInterfaceRouter _router;
  final DataManager _dataManager;
  final SinaFetcher _sinaFetcher;
  final TencentFetcher _tencentFetcher;

  MarketDataTdxActionService({
    DataManager? dataManager,
    TdxMarketDataService? tdx,
    ExTdxMarketDataService? exTdx,
    TdxMarketDataQueryService? query,
    DataApiInterfaceRouter? router,
    SinaFetcher? sinaFetcher,
    TencentFetcher? tencentFetcher,
  }) : this._withManager(
         dataManager ?? DataManager(),
         tdx: tdx,
         exTdx: exTdx,
         query: query,
         router: router,
         sinaFetcher: sinaFetcher,
         tencentFetcher: tencentFetcher,
       );

  MarketDataTdxActionService._withManager(
    DataManager dataManager, {
    TdxMarketDataService? tdx,
    ExTdxMarketDataService? exTdx,
    TdxMarketDataQueryService? query,
    DataApiInterfaceRouter? router,
    SinaFetcher? sinaFetcher,
    TencentFetcher? tencentFetcher,
  }) : _dataManager = dataManager,
       _tdx = tdx ?? TdxMarketDataService(dataManager: dataManager),
       _exTdx = exTdx ?? ExTdxMarketDataService(dataManager: dataManager),
       _query = query ?? TdxMarketDataQueryService(dataManager: dataManager),
       _router =
           router ??
           DataApiInterfaceRouter(
             runtimeBasePathProvider: () => dataManager.basePath,
           ),
       _sinaFetcher = sinaFetcher ?? SinaFetcher(),
       _tencentFetcher = tencentFetcher ?? TencentFetcher();

  Future<dynamic> run(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    try {
      if (_routedTdxActions.containsKey(action)) {
        return await _runRouted(action, symbols, input, context);
      }
      switch (action) {
        case 'tdx_tick_chart':
          return await _tdx.tickChart(_firstSymbol(symbols, _tickChartError));
        case 'tdx_transactions':
          return await _tdx.transactions(
            _firstSymbol(symbols, _transactionsError),
            input,
          );
        case 'tdx_finance':
          return await _tdx.finance(_firstSymbol(symbols, _financeError));
        case 'tdx_xdxr':
          return await _tdx.xdxr(_firstSymbol(symbols, _xdxrError));
        case 'tdx_unusual':
          return await _tdx.unusual(input);
        case 'tdx_index_info':
          return await _tdx.indexInfo(_firstSymbol(symbols, _indexInfoError));
        case 'tdx_count':
          return await _tdx.count(input);
        case 'tdx_sampling':
          return await _tdx.sampling(_firstSymbol(symbols, _samplingError));
        case 'tdx_stock_list':
          return await _tdx.stockList(input);
        case 'tdx_volume_profile':
          return await _tdx.volumeProfile(
            _firstSymbol(symbols, _volumeProfileError),
          );
        case 'tdx_auction':
          return await _tdx.auction(_firstSymbol(symbols, _auctionError));
        case 'tdx_history_tick':
          return await _tdx.historyTick(
            _firstSymbol(symbols, _historyTickError),
            input,
          );
        case 'tdx_momentum':
          return await _tdx.momentum(_firstSymbol(symbols, _momentumError));
        case 'tdx_history_trans':
          return await _tdx.historyTrans(
            _firstSymbol(symbols, _historyTransError),
            input,
          );
        case 'tdx_top_board':
          return await _tdx.topBoard(input);
        case 'tdx_quotes_list':
          return await _tdx.quotesList(input);
        case 'tdx_index_bars':
          return await _tdx.indexBars(
            _firstSymbol(symbols, _indexBarsError),
            input,
          );
        case 'tdx_company_info':
          return await _tdx.companyInfo(
            _firstSymbol(symbols, _companyInfoError),
            input,
          );
        case 'tdx_block':
          return await _tdx.block(symbols, input);
        case 'ex_categories':
          return await _exTdx.categories();
        case 'ex_count':
          return await _exTdx.count();
        case 'ex_sampling':
          return await _exTdx.sampling(input);
        case 'ex_table':
          return await _exTdx.table(input);
        case 'ex_kline':
          return await _exTdx.kline(input);
        case 'ex_quote':
          return await _exTdx.quote(input);
        case 'ex_list':
          return await _exTdx.list(input);
        default:
          throw ArgumentError('Unsupported MarketData TDX action: $action');
      }
    } catch (e) {
      final metadata = _actionMetadata[action];
      if (metadata != null) {
        ApiStats.instance.record(
          source: metadata.source,
          method: 'DIRECT',
          url: metadata.url,
          statusCode: 0,
          durationMs: 0,
          success: false,
          error: '$e',
        );
        throw StateError('${metadata.errorLabel} error: $e');
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _runRouted(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final spec = _routedActionSpec(action, symbols, input);
    _validateRoutedAction(action, symbols, input);
    final result = await _router.runCapability<Map<String, dynamic>>(
      interfaceId: spec.interfaceId,
      constraint: _constraintFromInput(input),
      cachePolicy: CachePolicy.fromInput(
        input,
        task: FinanceDataTask.intradayTick,
      ),
      readCache: () async {
        final cached = _query.queryAction(
          spec.queryAction,
          symbols,
          input,
          context,
        );
        return _isUsableResult(cached)
            ? DataApiLocalCacheResult(data: cached)
            : null;
      },
      call: (capability) async {
        if (action == 'intraday_ohlcv_bars' &&
            capability.provider == FinanceProvider.sina) {
          final symbol = _firstSymbol(symbols, _intradayOhlcvError);
          final intervalMinutes =
              (input['intervalMinutes'] as num?)?.toInt() ??
              (input['scale'] as num?)?.toInt() ??
              5;
          final limit = (input['limit'] as num?)?.toInt() ?? 240;
          final rows = await _sinaFetcher.getIntradayOhlcvBars(
            symbol,
            intervalMinutes: intervalMinutes,
            limit: limit,
          );
          _dataManager.saveIntradayOhlcvBars(
            symbol,
            rows,
            source: '新浪财经:intraday_ohlcv',
            intervalMinutes: intervalMinutes,
          );
          final readbackRows = _dataManager.queryIntradayOhlcvBars(
            symbol,
            startDate: input['startDate'] as String? ?? '',
            endDate: input['endDate'] as String? ?? '',
            intervalMinutes: intervalMinutes,
            limit: limit,
          );
          return DataApiProviderExecution(
            data: {
              'action': 'intraday_ohlcv_bars',
              'source': '新浪财经:intraday_ohlcv',
              'interfaceId': spec.interfaceId,
              'provider': 'local',
              'capabilityId': 'local.cache',
              'cacheStatus': readbackRows.isEmpty ? 'cache-miss' : 'cache-hit',
              'cacheMode': 'cache-first',
              'cachePolicyMode': 'cacheFirst',
              'canonicalSchema': 'intraday_ohlcv_bars',
              'canonicalTable': 'intraday_ohlcv_bars',
              'symbol': symbol,
              'intervalMinutes': intervalMinutes,
              'count': readbackRows.length,
              'data': readbackRows,
            },
            source: '新浪财经:intraday_ohlcv',
            providerName: '新浪财经',
          );
        }
        if (action == 'transactions' &&
            capability.provider == FinanceProvider.sina) {
          final symbol = _firstSymbol(symbols, _transactionsError);
          final rows = await _sinaFetcher.getTransactions(
            symbol,
            limit: (input['limit'] as int?) ?? 60,
            tradeDate: input['date'] as String?,
          );
          _dataManager.saveTransactions(
            symbol,
            rows,
            source: '新浪财经',
            tradeDate: input['date'] as String?,
          );
          return DataApiProviderExecution(
            data: {
              'action': 'transactions',
              'source': '新浪财经',
              'symbol': symbol,
              'count': rows.length,
              'data': rows.take(30).toList(),
            },
            source: '新浪财经',
            providerName: '新浪财经',
          );
        }
        if (action == 'transactions' &&
            capability.provider == FinanceProvider.tencent) {
          final symbol = _firstSymbol(symbols, _transactionsError);
          final isEtf = spec.interfaceId == 'fund.etf_transactions';
          final rows = isEtf
              ? await _tencentFetcher.getEtfTransactions(
                  symbol,
                  limit: (input['limit'] as int?) ?? 70,
                )
              : await _tencentFetcher.getStockTransactions(
                  symbol,
                  limit: (input['limit'] as int?) ?? 70,
                );
          final source = isEtf
              ? '腾讯财经:etf_transactions'
              : '腾讯财经:stock_transactions';
          _dataManager.saveTransactions(
            symbol,
            rows,
            source: source,
            tradeDate: input['date'] as String?,
          );
          final readbackRows = _dataManager.queryTransactions(
            symbol,
            tradeDate: input['date'] as String?,
            limit: (input['limit'] as int?) ?? 100,
          );
          return DataApiProviderExecution(
            data: {
              'action': 'transactions',
              'source': source,
              'interfaceId': spec.interfaceId,
              'provider': 'local',
              'capabilityId': 'local.cache',
              'cacheStatus': readbackRows.isEmpty ? 'cache-miss' : 'cache-hit',
              'cacheMode': 'cache-first',
              'cachePolicyMode': 'cacheFirst',
              'canonicalSchema': 'transactions',
              'canonicalTable': 'transactions',
              'symbol': symbol,
              'count': readbackRows.length,
              'data': readbackRows,
            },
            source: source,
            providerName: '腾讯财经',
          );
        }
        if (capability.provider != FinanceProvider.tdx) return null;
        return DataApiProviderExecution(
          data: await _runDirectProvider(action, symbols, input),
          source: '通达信',
          providerName: '通达信',
        );
      },
      isUsable: _isUsableResult,
      emptyMessage: 'returned no reusable ${spec.canonicalTable} rows',
      failureMessage: 'All ${spec.interfaceId} providers failed',
    );
    return {
      ...result.data,
      'action': action,
      'source': result.source,
      'interfaceId': result.provenance.interfaceId,
      'capabilityId': result.provenance.capabilityId,
      'provider': result.provenance.provider,
      'canonicalSchema': result.provenance.canonicalSchema,
      'canonicalTable': result.provenance.canonicalTable,
      'cacheStatus': result.provenance.cacheStatus,
      'cachePolicyMode': result.provenance.cachePolicyMode,
      'cacheDecision': result.provenance.cacheDecision,
      ...result.provenance.routePolicyJson(),
      'provenance': result.provenance.toJson(),
    };
  }

  Future<Map<String, dynamic>> _runDirectProvider(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
  ) async {
    switch (action) {
      case 'tdx_tick_chart':
        return await _tdx.tickChart(_firstSymbol(symbols, _tickChartError));
      case 'tdx_history_tick':
        return await _tdx.historyTick(
          _firstSymbol(symbols, _historyTickError),
          input,
        );
      case 'tdx_transactions':
      case 'transactions':
        return await _tdx.transactions(
          _firstSymbol(symbols, _transactionsError),
          input,
        );
      case 'tdx_history_trans':
        return await _tdx.historyTrans(
          _firstSymbol(symbols, _historyTransError),
          input,
        );
      case 'tdx_unusual':
        return await _tdx.unusual(input);
      case 'tdx_volume_profile':
        return await _tdx.volumeProfile(
          _firstSymbol(symbols, _volumeProfileError),
        );
      case 'tdx_xdxr':
        return await _tdx.xdxr(_firstSymbol(symbols, _xdxrError));
      case 'tdx_auction':
        return await _tdx.auction(_firstSymbol(symbols, _auctionError));
      case 'tdx_company_info':
        return await _tdx.companyInfo(
          _firstSymbol(symbols, _companyInfoError),
          input,
        );
      case 'tdx_block':
        return await _tdx.block(symbols, input);
      case 'tdx_top_board':
        return await _tdx.topBoard(input);
      case 'tdx_momentum':
        return await _tdx.momentum(_firstSymbol(symbols, _momentumError));
    }
    throw ArgumentError('Unsupported routed TDX action: $action');
  }

  void _validateRoutedAction(
    String action,
    List<String> symbols,
    Map<String, dynamic> input,
  ) {
    switch (action) {
      case 'tdx_tick_chart':
        _firstSymbol(symbols, _tickChartError);
        return;
      case 'tdx_history_tick':
        _firstSymbol(symbols, _historyTickError);
        if ('${input['date'] ?? ''}'.trim().isEmpty) {
          throw ArgumentError(_historyTickError);
        }
        return;
      case 'tdx_transactions':
      case 'transactions':
        _firstSymbol(symbols, _transactionsError);
        return;
      case 'intraday_ohlcv_bars':
        _firstSymbol(symbols, _intradayOhlcvError);
        return;
      case 'tdx_history_trans':
        _firstSymbol(symbols, _historyTransError);
        if ('${input['date'] ?? ''}'.trim().isEmpty) {
          throw ArgumentError(_historyTransError);
        }
        return;
      case 'tdx_volume_profile':
        _firstSymbol(symbols, _volumeProfileError);
        return;
      case 'tdx_xdxr':
        _firstSymbol(symbols, _xdxrError);
        return;
      case 'tdx_auction':
        _firstSymbol(symbols, _auctionError);
        return;
      case 'tdx_company_info':
        _firstSymbol(symbols, _companyInfoError);
        return;
      case 'tdx_unusual':
        return;
      case 'tdx_momentum':
        _firstSymbol(symbols, _momentumError);
        return;
      case 'tdx_block':
      case 'tdx_top_board':
        return;
    }
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
    final data = result['data'];
    if (data is List) return data.isNotEmpty;
    final expiryCount = result['expiryCount'];
    final contractCount = result['contractCount'];
    if (expiryCount is num || contractCount is num) {
      return (expiryCount is num ? expiryCount : 0) > 0 ||
          (contractCount is num ? contractCount : 0) > 0;
    }
    return result.isNotEmpty && !result.containsKey('error');
  }
}

String _firstSymbol(List<String> symbols, String error) {
  if (symbols.isEmpty) throw ArgumentError(error);
  return symbols.first;
}

class _ActionMetadata {
  final String source;
  final String url;
  final String errorLabel;

  const _ActionMetadata({
    required this.source,
    required this.url,
    required this.errorLabel,
  });
}

class _RoutedTdxActionSpec {
  final String interfaceId;
  final String queryAction;
  final String canonicalTable;

  const _RoutedTdxActionSpec({
    required this.interfaceId,
    required this.queryAction,
    required this.canonicalTable,
  });
}

const _routedTdxActions = <String, _RoutedTdxActionSpec>{
  'intraday_ohlcv_bars': _RoutedTdxActionSpec(
    interfaceId: 'market.intraday_ohlcv_bars',
    queryAction: 'query_intraday_ohlcv_bars',
    canonicalTable: 'intraday_ohlcv_bars',
  ),
  'transactions': _RoutedTdxActionSpec(
    interfaceId: 'stock.transactions',
    queryAction: 'query_transactions',
    canonicalTable: 'transactions',
  ),
  'tdx_tick_chart': _RoutedTdxActionSpec(
    interfaceId: 'stock.tick_chart_intraday',
    queryAction: 'query_tick_chart',
    canonicalTable: 'tick_chart_intraday',
  ),
  'tdx_history_tick': _RoutedTdxActionSpec(
    interfaceId: 'stock.tick_chart_intraday',
    queryAction: 'query_tick_chart',
    canonicalTable: 'tick_chart_intraday',
  ),
  'tdx_transactions': _RoutedTdxActionSpec(
    interfaceId: 'stock.transactions',
    queryAction: 'query_transactions',
    canonicalTable: 'transactions',
  ),
  'tdx_history_trans': _RoutedTdxActionSpec(
    interfaceId: 'stock.transactions',
    queryAction: 'query_transactions',
    canonicalTable: 'transactions',
  ),
  'tdx_unusual': _RoutedTdxActionSpec(
    interfaceId: 'market.unusual_activity',
    queryAction: 'query_unusual',
    canonicalTable: 'unusual_activity',
  ),
  'tdx_volume_profile': _RoutedTdxActionSpec(
    interfaceId: 'stock.volume_profile',
    queryAction: 'query_volume_profile',
    canonicalTable: 'volume_profile',
  ),
  'tdx_xdxr': _RoutedTdxActionSpec(
    interfaceId: 'stock.xdxr_events',
    queryAction: 'query_xdxr',
    canonicalTable: 'xdxr_event',
  ),
  'tdx_auction': _RoutedTdxActionSpec(
    interfaceId: 'stock.auction_snapshot',
    queryAction: 'query_auction',
    canonicalTable: 'auction_snapshot',
  ),
  'tdx_company_info': _RoutedTdxActionSpec(
    interfaceId: 'stock.company_info',
    queryAction: 'query_stock_company_info',
    canonicalTable: 'stock_company_info',
  ),
  'tdx_block': _RoutedTdxActionSpec(
    interfaceId: 'market.tdx_block_member',
    queryAction: 'query_tdx_block_member',
    canonicalTable: 'tdx_block_member',
  ),
  'tdx_top_board': _RoutedTdxActionSpec(
    interfaceId: 'market.tdx_top_board',
    queryAction: 'query_top_board',
    canonicalTable: 'tdx_top_board',
  ),
  'tdx_momentum': _RoutedTdxActionSpec(
    interfaceId: 'index.momentum',
    queryAction: 'query_momentum',
    canonicalTable: 'tdx_index_momentum',
  ),
};

_RoutedTdxActionSpec _routedActionSpec(
  String action,
  List<String> symbols,
  Map<String, dynamic> input,
) {
  final base = _routedTdxActions[action]!;
  if (action != 'transactions') return base;
  final symbol = symbols.isEmpty ? '' : symbols.first;
  final instrumentType =
      '${input['instrumentType'] ?? input['assetType'] ?? ''}'
          .trim()
          .toLowerCase();
  final clean = symbol
      .replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '')
      .trim();
  final isEtf =
      instrumentType == 'etf' ||
      RegExp(r'^(15|16|50|51|52|56|58)\d{4}$').hasMatch(clean);
  if (!isEtf) return base;
  return const _RoutedTdxActionSpec(
    interfaceId: 'fund.etf_transactions',
    queryAction: 'query_transactions',
    canonicalTable: 'transactions',
  );
}

const _actionMetadata = <String, _ActionMetadata>{
  'tdx_tick_chart': _ActionMetadata(
    source: '通达信',
    url: 'tdx_tick_chart',
    errorLabel: 'TDX tick_chart',
  ),
  'tdx_transactions': _ActionMetadata(
    source: '通达信',
    url: 'tdx_transactions',
    errorLabel: 'TDX transactions',
  ),
  'tdx_finance': _ActionMetadata(
    source: '通达信',
    url: 'tdx_finance',
    errorLabel: 'TDX finance',
  ),
  'tdx_xdxr': _ActionMetadata(
    source: '通达信',
    url: 'tdx_xdxr',
    errorLabel: 'TDX xdxr',
  ),
  'tdx_unusual': _ActionMetadata(
    source: '通达信',
    url: 'tdx_unusual',
    errorLabel: 'TDX unusual',
  ),
  'tdx_index_info': _ActionMetadata(
    source: '通达信',
    url: 'tdx_index_info',
    errorLabel: 'TDX index_info',
  ),
  'tdx_count': _ActionMetadata(
    source: '通达信',
    url: 'tdx_count',
    errorLabel: 'TDX count',
  ),
  'tdx_sampling': _ActionMetadata(
    source: '通达信',
    url: 'tdx_sampling',
    errorLabel: 'TDX sampling',
  ),
  'tdx_stock_list': _ActionMetadata(
    source: '通达信',
    url: 'tdx_stock_list',
    errorLabel: 'TDX stock_list',
  ),
  'tdx_volume_profile': _ActionMetadata(
    source: '通达信',
    url: 'tdx_volume_profile',
    errorLabel: 'TDX volume_profile',
  ),
  'tdx_auction': _ActionMetadata(
    source: '通达信',
    url: 'tdx_auction',
    errorLabel: 'TDX auction',
  ),
  'tdx_history_tick': _ActionMetadata(
    source: '通达信',
    url: 'tdx_history_tick',
    errorLabel: 'TDX history_tick',
  ),
  'tdx_momentum': _ActionMetadata(
    source: '通达信',
    url: 'tdx_momentum',
    errorLabel: 'TDX momentum',
  ),
  'tdx_history_trans': _ActionMetadata(
    source: '通达信',
    url: 'tdx_history_trans',
    errorLabel: 'TDX history_trans',
  ),
  'tdx_top_board': _ActionMetadata(
    source: '通达信',
    url: 'tdx_top_board',
    errorLabel: 'TDX top_board',
  ),
  'tdx_quotes_list': _ActionMetadata(
    source: '通达信',
    url: 'tdx_quotes_list',
    errorLabel: 'TDX quotes_list',
  ),
  'tdx_index_bars': _ActionMetadata(
    source: '通达信',
    url: 'tdx_index_bars',
    errorLabel: 'TDX index_bars',
  ),
  'tdx_company_info': _ActionMetadata(
    source: '通达信',
    url: 'tdx_company_info',
    errorLabel: 'TDX company_info',
  ),
  'tdx_block': _ActionMetadata(
    source: '通达信',
    url: 'tdx_block',
    errorLabel: 'TDX block',
  ),
  'ex_categories': _ActionMetadata(
    source: '通达信扩展',
    url: 'ex_categories',
    errorLabel: 'ExTDX categories',
  ),
  'ex_count': _ActionMetadata(
    source: '通达信扩展',
    url: 'ex_count',
    errorLabel: 'ExTDX count',
  ),
  'ex_sampling': _ActionMetadata(
    source: '通达信扩展',
    url: 'ex_sampling',
    errorLabel: 'ExTDX sampling',
  ),
  'ex_table': _ActionMetadata(
    source: '通达信扩展',
    url: 'ex_table',
    errorLabel: 'ExTDX table',
  ),
  'ex_kline': _ActionMetadata(
    source: '通达信扩展',
    url: 'ex_kline',
    errorLabel: 'ExTDX kline',
  ),
  'ex_quote': _ActionMetadata(
    source: '通达信扩展',
    url: 'ex_quote',
    errorLabel: 'ExTDX quote',
  ),
  'ex_list': _ActionMetadata(
    source: '通达信扩展',
    url: 'ex_list',
    errorLabel: 'ExTDX list',
  ),
};

const _tickChartError =
    'symbols required. Example: MarketData(action:"tdx_tick_chart", symbols:["600519"])';
const _transactionsError =
    'symbols required. Example: MarketData(action:"tdx_transactions", symbols:["600519"])';
const _intradayOhlcvError =
    'symbols required. Example: MarketData(action:"intraday_ohlcv_bars", symbols:["600519"], intervalMinutes:5)';
const _financeError =
    'symbols required. Example: MarketData(action:"tdx_finance", symbols:["600519"])';
const _xdxrError =
    'symbols required. Example: MarketData(action:"tdx_xdxr", symbols:["600519"])';
const _indexInfoError =
    'symbols required. Example: MarketData(action:"tdx_index_info", symbols:["000001"])';
const _samplingError =
    'symbols required. Example: MarketData(action:"tdx_sampling", symbols:["000001"])';
const _volumeProfileError =
    'symbols required. Example: MarketData(action:"tdx_volume_profile", symbols:["600519"])';
const _auctionError =
    'symbols required. Example: MarketData(action:"tdx_auction", symbols:["600519"])';
const _historyTickError =
    'symbols required + date param (YYYYMMDD). Example: MarketData(action:"tdx_history_tick", symbols:["600519"], date:"20250519")';
const _momentumError =
    'symbols required. Example: MarketData(action:"tdx_momentum", symbols:["000001"])';
const _historyTransError =
    'symbols + date required. Example: MarketData(action:"tdx_history_trans", symbols:["600519"], date:"20250519")';
const _indexBarsError =
    'symbols required. Example: MarketData(action:"tdx_index_bars", symbols:["000001"])';
const _companyInfoError =
    'symbols required. Example: MarketData(action:"tdx_company_info", symbols:["600519"])';
