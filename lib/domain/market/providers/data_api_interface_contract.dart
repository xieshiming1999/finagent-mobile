import '../../../agent/data_fetcher/provider_policy.dart';

enum DataApiCapabilityStatus {
  supported,
  disabled,
  credentialGated,
  quotaGated,
  transportUnstable,
  notSupported,
  outputOnly,
  globalOnly,
}

enum DataApiProviderMode { auto, preferred, strict }

const dataApiInterfaceContractVersion = '2026-06-25';

class DataApiProviderCapability {
  final String id;
  final FinanceProvider provider;
  final DataApiCapabilityStatus status;
  final String? upstreamOrigin;
  final String? adapter;
  final String? normalizer;
  final String? canonicalTable;
  final String? probeId;
  final String? reason;
  final int priority;

  const DataApiProviderCapability({
    required this.id,
    required this.provider,
    required this.status,
    this.upstreamOrigin,
    this.adapter,
    this.normalizer,
    this.canonicalTable,
    this.probeId,
    this.reason,
    this.priority = 999,
  });

  bool get isEligible =>
      status == DataApiCapabilityStatus.supported ||
      status == DataApiCapabilityStatus.globalOnly;
}

class DataApiInterfaceDefinition {
  final String id;
  final String label;
  final String canonicalSchema;
  final List<String> dataStoreTables;
  final List<String> queryActions;
  final List<String> params;
  final String freshnessPolicy;
  final List<DataApiProviderCapability> capabilities;

  const DataApiInterfaceDefinition({
    required this.id,
    required this.label,
    required this.canonicalSchema,
    required this.dataStoreTables,
    required this.queryActions,
    required this.params,
    required this.freshnessPolicy,
    required this.capabilities,
  });
}

class DataApiProviderConstraint {
  final FinanceProvider? provider;
  final DataApiProviderMode providerMode;
  final bool allowFallback;
  final bool allowDegraded;

  const DataApiProviderConstraint({
    this.provider,
    this.providerMode = DataApiProviderMode.auto,
    this.allowFallback = true,
    this.allowDegraded = false,
  });
}

class DataApiInterfaceContract {
  const DataApiInterfaceContract();

  List<DataApiInterfaceDefinition> get interfaces => _interfaces;

  DataApiInterfaceDefinition? getInterface(String id) {
    for (final item in _interfaces) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<DataApiProviderCapability> registeredCapabilities(
    String interfaceId, {
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) {
    final definition = getInterface(interfaceId);
    if (definition == null) return const <DataApiProviderCapability>[];
    final capabilities = [...definition.capabilities]
      ..sort(_compareCapabilities);
    final provider = constraint.provider;
    if (provider == null) return capabilities;
    final matched = capabilities
        .where((capability) => capability.provider == provider)
        .toList(growable: false);
    if (constraint.providerMode == DataApiProviderMode.strict) return matched;
    if (constraint.providerMode == DataApiProviderMode.preferred) {
      if (!constraint.allowFallback) return matched;
      return [
        ...matched,
        ...capabilities.where((capability) => capability.provider != provider),
      ];
    }
    return capabilities;
  }

  List<DataApiProviderCapability> eligibleCapabilities(
    String interfaceId, {
    DataApiProviderConstraint constraint = const DataApiProviderConstraint(),
  }) {
    return registeredCapabilities(interfaceId, constraint: constraint)
        .where(
          (capability) =>
              capability.isEligible ||
              (_allowsExplicitCredentialProvider(constraint, capability) &&
                  (capability.status ==
                          DataApiCapabilityStatus.credentialGated ||
                      capability.status ==
                          DataApiCapabilityStatus.quotaGated)) ||
              (constraint.allowDegraded &&
                  capability.status ==
                      DataApiCapabilityStatus.transportUnstable),
        )
        .toList(growable: false);
  }

  bool _allowsExplicitCredentialProvider(
    DataApiProviderConstraint constraint,
    DataApiProviderCapability capability,
  ) {
    final provider = constraint.provider;
    if (provider == null || provider != capability.provider) return false;
    return constraint.providerMode != DataApiProviderMode.auto;
  }

  List<String> validate() {
    final problems = <String>[];
    final interfaceIds = <String>{};
    for (final definition in _interfaces) {
      if (!interfaceIds.add(definition.id)) {
        problems.add('duplicate interface id: ${definition.id}');
      }
      if (definition.canonicalSchema.trim().isEmpty) {
        problems.add('${definition.id}: canonicalSchema required');
      }
      if (definition.params.isEmpty) {
        problems.add('${definition.id}: params required');
      }
      if (!definition.params.contains('provider')) {
        problems.add('${definition.id}: provider param required');
      }
      if (!definition.params.contains('providerMode')) {
        problems.add('${definition.id}: providerMode param required');
      }
      if (definition.capabilities.isEmpty) {
        problems.add('${definition.id}: provider capability required');
      }
      final capabilityIds = <String>{};
      final eligiblePriorityOwners = <int, String>{};
      for (final capability in definition.capabilities) {
        if (!capabilityIds.add(capability.id)) {
          problems.add(
            '${definition.id}: duplicate capability id ${capability.id}',
          );
        }
        if (capability.isEligible) {
          final existing = eligiblePriorityOwners[capability.priority];
          if (existing != null) {
            problems.add(
              '${definition.id}: duplicate eligible provider priority '
              '${capability.priority}: $existing and ${capability.id}',
            );
          } else {
            eligiblePriorityOwners[capability.priority] = capability.id;
          }
        }
        if (_requiresOperationalReason(capability.status) &&
            (capability.reason?.trim().isEmpty ?? true)) {
          problems.add(
            '${definition.id}/${capability.id}: ${capability.status.name} capability '
            'requires reason',
          );
        }
        if (_requiresCanonicalNormalizer(capability) &&
            (capability.normalizer == null ||
                capability.normalizer!.trim().isEmpty)) {
          problems.add(
            '${definition.id}/${capability.id}: provider normalizer required',
          );
        }
        if (_requiresCanonicalNormalizer(capability) &&
            definition.dataStoreTables.isNotEmpty &&
            (capability.canonicalTable == null ||
                capability.canonicalTable!.trim().isEmpty)) {
          problems.add(
            '${definition.id}/${capability.id}: canonicalTable required',
          );
        }
        if (_requiresCanonicalNormalizer(capability) &&
            capability.canonicalTable != null &&
            definition.dataStoreTables.isNotEmpty &&
            !definition.dataStoreTables.contains(capability.canonicalTable)) {
          problems.add(
            '${definition.id}/${capability.id}: canonicalTable '
            '${capability.canonicalTable} is not owned by interface tables '
            '${definition.dataStoreTables.join(',')}',
          );
        }
      }
    }
    return problems;
  }

  bool _requiresCanonicalNormalizer(DataApiProviderCapability capability) {
    return capability.status == DataApiCapabilityStatus.supported ||
        capability.status == DataApiCapabilityStatus.globalOnly ||
        capability.status == DataApiCapabilityStatus.credentialGated ||
        capability.status == DataApiCapabilityStatus.quotaGated ||
        capability.status == DataApiCapabilityStatus.transportUnstable;
  }

  bool _requiresOperationalReason(DataApiCapabilityStatus status) {
    return status == DataApiCapabilityStatus.notSupported ||
        status == DataApiCapabilityStatus.credentialGated ||
        status == DataApiCapabilityStatus.quotaGated ||
        status == DataApiCapabilityStatus.disabled;
  }
}

int _compareCapabilities(
  DataApiProviderCapability a,
  DataApiProviderCapability b,
) {
  final priority = a.priority.compareTo(b.priority);
  if (priority != 0) return priority;
  final provider = a.provider.name.compareTo(b.provider.name);
  if (provider != 0) return provider;
  return a.id.compareTo(b.id);
}

const dataApiInterfaceContract = DataApiInterfaceContract();

const _interfaces = <DataApiInterfaceDefinition>[
  DataApiInterfaceDefinition(
    id: 'stock.identity_list',
    label: 'Stock identity list',
    canonicalSchema: 'stock_list',
    dataStoreTables: ['stock_list'],
    queryActions: ['query_stock_list'],
    params: [
      'market',
      'industry',
      'stockType',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'daily-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.identity_list',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'stock list / ExTDX list',
        normalizer: 'saveStockList',
        canonicalTable: 'stock_list',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.identity_list',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'push2delay clist stock universe',
        normalizer: 'saveStockList',
        canonicalTable: 'stock_list',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'sina.stock.identity_list',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Sina quote list identity route',
        normalizer: 'saveStockList',
        canonicalTable: 'stock_list',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'tencent.stock.identity_list',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Tencent rank/hs getBoardRankList bounded A-share route',
        normalizer: 'TencentFetcher.getStockList/saveStockList',
        canonicalTable: 'stock_list',
        probeId: 'tencent.direct.stock_rank_list',
        priority: 5,
        reason:
            'Direct Tencent A-share rank/list probe passed and returns bounded code/name rows suitable for stock_list identity refresh.',
      ),
      DataApiProviderCapability(
        id: 'tushare.stock.identity_list',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'stock_basic',
        normalizer: 'ingestTushare',
        canonicalTable: 'stock_list',
        reason:
            'Requires explicit Tushare credential/config context; local stock-list reads should be tried first.',
        priority: 5,
      ),
      DataApiProviderCapability(
        id: 'wind.stock.identity_list',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp stock_data.get_stock_basicinfo/get_stock_quote',
        normalizer: 'persistWindResult',
        canonicalTable: 'stock_list',
        probeId: 'mobile_marketdata_wind_stock_basicinfo',
        reason:
            'Wind stock identity/basic-info tools require configured credential and quota; normalized identity rows are reusable through stock_list.',
        priority: 6,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.quote',
    label: 'Stock quote',
    canonicalSchema: 'quote_snapshot',
    dataStoreTables: ['quote_snapshot'],
    queryActions: ['query_quote'],
    params: ['symbols', 'provider', 'providerMode'],
    freshnessPolicy: 'intraday-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.quote',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'getQuotes',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.quote',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'getQuotes',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'sina.stock.quote',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'getQuotes',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        priority: 3,
      ),
      DataApiProviderCapability(
        id: 'tencent.stock.quote',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'getQuotes',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'tencent.global.stock_quote',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'getQuotes for hk/us qt.gtimg symbols',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        probeId: 'tencent.direct.hk_quote',
        priority: 7,
        reason:
            'Tencent HK/US quote probes passed; this route is global-only and must not be used for A-share symbols.',
      ),
      DataApiProviderCapability(
        id: 'yfinance.stock.quote',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo chart price route',
        normalizer: 'saveQuoteSnapshots',
        canonicalTable: 'quote_snapshot',
        probeId: 'mobile_marketdata_yahoo_price',
        priority: 5,
        reason:
            'Yahoo/yfinance quote is for US/HK/global symbols only; A-share quote routing should prefer native A-share providers.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.quote',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter:
            'WindMcp stock_data.get_stock_quote/get_stock_price_indicators',
        normalizer: 'persistWindResult',
        canonicalTable: 'quote_snapshot',
        probeId: 'mobile_marketdata_wind_stock_quote',
        reason:
            'Wind stock quote requires configured credential and quota; normalized snapshots are reusable through quote_snapshot.',
        priority: 6,
      ),
      DataApiProviderCapability(
        id: 'tushare.stock.quote',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'Tushare daily data is not a realtime quote capability.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'index.quote',
    label: 'Index quote',
    canonicalSchema: 'quote_snapshot',
    dataStoreTables: ['quote_snapshot'],
    queryActions: ['query_index_quote', 'query_quote'],
    params: ['symbols', 'provider', 'providerMode'],
    freshnessPolicy: 'intraday-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.index.quote',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'native TDX index quote route',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'sina.index.quote',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Sina index quote route',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.index.quote',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney index quote route',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        priority: 3,
      ),
      DataApiProviderCapability(
        id: 'tencent.index.quote',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Tencent qt.gtimg.cn index quote route',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        probeId: 'tencent.direct.index_quote',
        priority: 4,
        reason:
            'Shared mobile Tencent index quote uses an explicit index-symbol route to avoid stock/index code ambiguity and normalizes into quote_snapshot.',
      ),
      DataApiProviderCapability(
        id: 'wind.index.quote',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter:
            'WindMcp index_data.get_index_quote/get_index_price_indicators',
        normalizer: 'persistWindResult',
        canonicalTable: 'quote_snapshot',
        probeId: 'electron_wind_index_price_indicators',
        reason:
            'Wind index quote and price-indicator tools require configured credential and quota.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'index.daily_kline',
    label: 'Index daily K-line',
    canonicalSchema: 'kline_daily',
    dataStoreTables: ['kline_daily'],
    queryActions: ['query_kline'],
    params: [
      'symbols',
      'startDate',
      'endDate',
      'adjust',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'cache-first-min-rows',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.index.daily_kline',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'native TDX index K-line route',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.index.daily_kline',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'native EastMoney index K-line route',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'tencent.index.daily_kline',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'proxy.finance.qq.com ifzqgtimg newfqkline index day',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        probeId: 'tencent.direct.index_daily_kline',
        priority: 3,
        reason:
            'Shared mobile Tencent index daily K-line supports bounded unadjusted daily bars through newfqkline; adjusted bars remain unsupported until proven separately.',
      ),
      DataApiProviderCapability(
        id: 'tushare.index.daily_kline',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'index_daily',
        normalizer: 'ingestTushare',
        canonicalTable: 'kline_daily',
        priority: 4,
        reason:
            'Requires explicit Tushare credential/config context; local index K-line reads should be tried first.',
      ),
      DataApiProviderCapability(
        id: 'wind.index.daily_kline',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp index_data.get_index_kline',
        normalizer: 'persistWindResult',
        canonicalTable: 'kline_daily',
        probeId: 'electron_wind_index_kline',
        priority: 5,
        reason:
            'Wind index K-line requires configured credential and quota; normalized daily bars are reusable through kline_daily.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.daily_kline',
    label: 'Stock daily K-line',
    canonicalSchema: 'kline_daily',
    dataStoreTables: ['kline_daily'],
    queryActions: ['query_kline'],
    params: [
      'symbols',
      'startDate',
      'endDate',
      'adjust',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'cache-first-min-rows',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.daily_kline',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'getKline',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.daily_kline',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'getKline',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'akshare.stock.daily_kline',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare K-line is currently implemented through the Fin Electron sidecar; shared mobile / FinAgent has no native AkShare fetch adapter.',
      ),
      DataApiProviderCapability(
        id: 'sina.stock.daily_kline',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'CN_MarketData.getKLineData scale=240',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        priority: 3,
        reason:
            'Sina direct daily K-line returns unadjusted bars; use adjust=none or another provider for adjusted bars.',
      ),
      DataApiProviderCapability(
        id: 'tencent.stock.daily_kline',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'proxy.finance.qq.com ifzqgtimg newfqkline stock day',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        probeId: 'tencent.direct.stock_daily_kline',
        priority: 4,
        reason:
            'Shared mobile Tencent stock daily K-line supports bounded unadjusted daily bars through newfqkline; use adjust=none or another provider for adjusted bars.',
      ),
      DataApiProviderCapability(
        id: 'tushare.stock.daily_kline',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.supported,
        adapter: 'getKline',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        priority: 5,
      ),
      DataApiProviderCapability(
        id: 'yfinance.stock.daily_kline',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo chart history route',
        normalizer: 'saveKline',
        canonicalTable: 'kline_daily',
        probeId: 'mobile_marketdata_yahoo_history',
        priority: 6,
        reason:
            'Yahoo/yfinance daily history is for US/HK/global symbols only; A-share K-line routing should prefer native A-share providers.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.daily_kline',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp stock_data.get_stock_kline',
        normalizer: 'persistWindResult',
        canonicalTable: 'kline_daily',
        probeId: 'mobile_marketdata_wind_stock_kline',
        reason:
            'Wind stock K-line requires configured credential and quota; normalized daily bars are reusable through kline_daily.',
        priority: 7,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.intraday_ohlcv_bars',
    label: 'Intraday OHLCV bars',
    canonicalSchema: 'intraday_ohlcv_bars',
    dataStoreTables: ['intraday_ohlcv_bars'],
    queryActions: ['query_intraday_ohlcv_bars'],
    params: [
      'symbols',
      'startDate',
      'endDate',
      'intervalMinutes',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'intraday-cache-first-source-time',
    capabilities: [
      DataApiProviderCapability(
        id: 'sina.market.intraday_ohlcv_bars',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        upstreamOrigin: 'sina',
        adapter:
            'SinaFetcher.getIntradayOhlcvBars / CN_MarketData.getKLineData',
        normalizer: 'saveIntradayOhlcvBars',
        canonicalTable: 'intraday_ohlcv_bars',
        probeId: 'mobile_sina_intraday_ohlcv_bars',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'tdx.market.intraday_ohlcv_bars',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Mobile TDX intraday tick/chart structures are governed through stock.tick_chart_intraday and stock.transactions; no OHLCV minute-bar normalizer is registered for intraday_ohlcv_bars.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.market.intraday_ohlcv_bars',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No mobile EastMoney intraday OHLCV bar route has proven this schema and readback.',
      ),
      DataApiProviderCapability(
        id: 'tencent.market.intraday_ohlcv_bars',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No mobile Tencent intraday OHLCV bar route has proven this schema and readback.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'index.constituents',
    label: 'Index constituents',
    canonicalSchema: 'index_constituent',
    dataStoreTables: ['index_constituent'],
    queryActions: ['query_index_constituents'],
    params: ['indexCode', 'stockCode', 'asOfDate', 'provider', 'providerMode'],
    freshnessPolicy: 'membership-snapshot-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'akshare.index.constituents',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare index_stock_cons is a Sina-origin Python sidecar wrapper supported in Fin Electron. Shared mobile/FinAgent has index_constituent storage/readback but no native AkShare/Sina wrapper route or mobile live probe evidence, so this provider remains explicit not-supported.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.index.constituents',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No mobile EastMoney index constituent adapter is registered.',
      ),
      DataApiProviderCapability(
        id: 'tdx.index.constituents',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Mobile TDX quote/K-line support does not expose a canonical broad index constituent list.',
      ),
      DataApiProviderCapability(
        id: 'wind.index.constituents',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Requires mobile Wind credential plus a Wind index constituent provider normalizer before support; index_constituent storage/readback exists.',
      ),
      DataApiProviderCapability(
        id: 'tushare.index.constituents',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'index_weight',
        normalizer: 'saveIndexConstituents',
        canonicalTable: 'index_constituent',
        reason:
            'Requires explicit Tushare credential/config context; successful index_weight rows persist to index_constituent and should be reused through query_index_constituents.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.identity_list',
    label: 'Fund identity list',
    canonicalSchema: 'fund_list',
    dataStoreTables: ['fund_list'],
    queryActions: ['query_fund_list'],
    params: ['fundType', 'company', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'daily-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.identity_list',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'fundcode_search.js',
        normalizer: 'fund_list canonical writer',
        canonicalTable: 'fund_list',
        reason:
            'Native EastMoney fund-list fetch/persist/readback path is implemented in shared mobile/FinAgent.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.identity_list',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        upstreamOrigin: 'eastmoney',
        reason:
            'AkShare fund-list route is desktop sidecar-backed; mobile must stay native until a real provider path exists.',
      ),
      DataApiProviderCapability(
        id: 'tushare.fund.identity_list',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.disabled,
        reason:
            'fund_basic returned 40203 permission errors and is app-disabled.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.identity_list',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_info',
        normalizer: 'tryNormalizeWindFundListPayload',
        canonicalTable: 'fund_list',
        probeId: 'mobile_marketdata_wind_fund_info',
        reason:
            'Wind fund info requires configured credential and quota; normalized identity rows are reusable through fund_list.',
        priority: 4,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.performance_metrics',
    label: 'Fund performance metrics',
    canonicalSchema: 'fund_performance_metrics',
    dataStoreTables: ['fund_performance_metrics'],
    queryActions: ['query_fund_performance'],
    params: ['code', 'metricDate', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'daily-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.performance_metrics',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney fund performance route',
        normalizer: 'fund_performance_metrics canonical writer',
        canonicalTable: 'fund_performance_metrics',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.performance_metrics',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare is sidecar-backed in Fin Electron; mobile must stay native until a real mobile provider path exists.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.performance_metrics',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_performance',
        normalizer: 'tryNormalizeWindFundPerformancePayload',
        canonicalTable: 'fund_performance_metrics',
        probeId: 'electron_wind_fund_performance',
        reason:
            'Wind requires configured credential and quota; normalized fund performance rows are persisted.',
        priority: 3,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.holding',
    label: 'Fund holdings',
    canonicalSchema: 'fund_holding',
    dataStoreTables: ['fund_holding'],
    queryActions: ['query_fund_holding'],
    params: [
      'fundCode',
      'stockCode',
      'reportDate',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'quarterly-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.holding',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney FundArchivesDatas jjcc route',
        normalizer: 'fund_holding canonical writer',
        canonicalTable: 'fund_holding',
        reason:
            'Native EastMoney fund holding fetch/persist/readback path is implemented in shared mobile/FinAgent.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.holding',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare fund holding is sidecar-backed in Fin Electron; mobile must stay native until a real provider path exists.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.holding',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_holdings',
        normalizer: 'tryNormalizeWindFundHoldingPayload',
        canonicalTable: 'fund_holding',
        probeId: 'electron_wind_fund_holdings',
        reason: 'Wind requires configured credential and quota.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.company_info',
    label: 'Fund company and product information',
    canonicalSchema: 'stock_company_info',
    dataStoreTables: ['stock_company_info', 'stock_list'],
    queryActions: ['query_fund_company_info', 'query_company_info'],
    params: ['fundCode', 'infoType', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'fund-company-info-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.fund.company_info',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_info/get_fund_company_info',
        normalizer: 'tryNormalizeWindCompanyInfoPayload',
        canonicalTable: 'stock_company_info',
        probeId: 'electron_wind_fund_company_info',
        reason:
            'Wind fund company/product info requires configured credential and quota; cached rows are reusable through stock_company_info and stock_list fund identities.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.financials',
    label: 'Fund financial facts',
    canonicalSchema: 'fundamental',
    dataStoreTables: ['fundamental'],
    queryActions: ['query_fund_financials', 'query_fundamental'],
    params: ['fundCode', 'reportDate', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'fund-financials-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.fund.financials',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_financials',
        normalizer: 'tryNormalizeWindFundamentalPayload',
        canonicalTable: 'fundamental',
        probeId: 'electron_wind_fund_financials',
        reason:
            'Wind fund financial rows require configured credential and quota; normalized facts are reusable through fundamental.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.investor_holders',
    label: 'Fund investor holder information',
    canonicalSchema: 'stock_company_info',
    dataStoreTables: ['stock_company_info'],
    queryActions: ['query_fund_investor_holders', 'query_company_info'],
    params: ['fundCode', 'infoType', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'fund-holder-info-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.fund.investor_holders',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_holders',
        normalizer: 'tryNormalizeWindCompanyInfoPayload',
        canonicalTable: 'stock_company_info',
        probeId: 'electron_wind_fund_holders',
        reason:
            'Wind fund holder information requires configured credential and quota; cached rows are reusable through stock_company_info.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.money_flow',
    label: 'Stock money flow',
    canonicalSchema: 'money_flow',
    dataStoreTables: ['money_flow'],
    queryActions: ['query_money_flow'],
    params: ['symbols', 'period', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.stock.money_flow',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney individual flow provider route',
        normalizer: 'money_flow canonical writer',
        canonicalTable: 'money_flow',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.stock.money_flow',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare money-flow is currently sidecar-backed in Fin Electron; shared mobile / FinAgent uses native EastMoney for money_flow and has no native AkShare adapter.',
      ),
      DataApiProviderCapability(
        id: 'tushare.stock.money_flow',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.disabled,
        reason:
            'moneyflow returned 40203 permission errors and is app-disabled.',
      ),
      DataApiProviderCapability(
        id: 'tdx.stock.money_flow',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose canonical money_flow.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.money_flow',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp stock_data.get_stock_technicals',
        normalizer: 'tryNormalizeWindMoneyFlowPayload',
        canonicalTable: 'money_flow',
        probeId: 'electron_wind_stock_technicals',
        reason: 'Wind requires configured credential and quota.',
        priority: 3,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.daily_valuation',
    label: 'Stock daily valuation',
    canonicalSchema: 'fundamental',
    dataStoreTables: ['fundamental'],
    queryActions: ['query_stock_daily_valuation', 'query_fundamental'],
    params: ['symbols', 'date', 'provider', 'providerMode'],
    freshnessPolicy: 'daily-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tushare.stock.daily_valuation',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.supported,
        adapter: 'daily_basic',
        normalizer: 'fundamental canonical writer',
        canonicalTable: 'fundamental',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.daily_valuation',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney earnings provider route',
        normalizer: 'fundamental canonical writer',
        canonicalTable: 'fundamental',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'tdx.stock.daily_valuation',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'TDX company/finance route',
        normalizer: 'fundamental canonical writer',
        canonicalTable: 'fundamental',
        priority: 3,
      ),
      DataApiProviderCapability(
        id: 'wind.stock.daily_valuation',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'Wind price-indicator/fundamental tools',
        normalizer: 'fundamental canonical writer',
        canonicalTable: 'fundamental',
        reason: 'Wind requires configured credential and quota.',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'akshare.stock.daily_valuation',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No mobile-native AkShare valuation provider is registered outside Electron sidecar compatibility.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.etf_quote',
    label: 'ETF quote overview',
    canonicalSchema: 'quote_snapshot',
    dataStoreTables: ['quote_snapshot', 'stock_list'],
    queryActions: ['query_etf_quote', 'query_quote', 'query_stock_list'],
    params: ['limit', 'provider', 'providerMode'],
    freshnessPolicy: 'intraday-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.etf_quote',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney ETF quote provider route',
        normalizer: 'normalizeQuotes/saveStockList',
        canonicalTable: 'quote_snapshot',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.etf_quote',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent has no native AkShare ETF quote adapter.',
      ),
      DataApiProviderCapability(
        id: 'sina.fund.etf_quote',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Sina Market_Center.getHQNodeDataSimple node=etf_hq_fund',
        normalizer: 'normalizeQuotes/saveStockList',
        canonicalTable: 'quote_snapshot',
        probeId: 'sina.direct.fund_etf_quote_list',
        priority: 3,
        reason:
            'Direct Sina ETF quote/list live probe passed; rows normalize to quote_snapshot and stock_list through fund.etf_quote.',
      ),
      DataApiProviderCapability(
        id: 'tencent.fund.etf_quote',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'bounded Tencent qt.gtimg.cn ETF quote route',
        normalizer: 'normalizeQuotes/saveStockList',
        canonicalTable: 'quote_snapshot',
        probeId: 'tencent.direct.fund_etf_quote',
        priority: 4,
        reason:
            'Bounded Tencent ETF quote symbols normalize through fund.etf_quote; use EastMoney/Sina first for broad ETF universe coverage.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.etf_quote',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_quote/get_fund_price_indicators',
        normalizer: 'persistWindResult',
        canonicalTable: 'quote_snapshot',
        probeId: 'electron_wind_fund_price_indicators',
        reason:
            'Wind fund quote and price-indicator tools require configured credential and quota.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.listed_fund_quote',
    label: 'Listed fund and money-market fund quotes',
    canonicalSchema: 'quote_snapshot',
    dataStoreTables: ['quote_snapshot', 'stock_list'],
    queryActions: [
      'query_listed_fund_quote',
      'query_quote',
      'query_stock_list',
    ],
    params: ['limit', 'provider', 'providerMode'],
    freshnessPolicy: 'intraday-cache-first for exchange-listed fund symbols',
    capabilities: [
      DataApiProviderCapability(
        id: 'tencent.fund.listed_fund_quote',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        priority: 1,
        adapter: 'qt.gtimg.cn listed fund / money-market fund quote batch',
        normalizer: 'normalizeQuotes/saveStockList',
        canonicalTable: 'quote_snapshot',
        probeId: 'tencent.quote.listed_fund_batch',
        reason:
            'Bounded Tencent listed-fund and exchange money-market quote symbols normalize through fund.listed_fund_quote and persist to quote_snapshot plus listed_fund stock_list identities.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.fund.listed_fund_quote',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The mobile EastMoney ETF quote route is governed as fund.etf_quote; listed-fund and exchange money-market quote semantics are not proven for this interface.',
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.listed_fund_quote',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile/FinAgent has no native AkShare sidecar route for listed-fund quotes.',
      ),
      DataApiProviderCapability(
        id: 'sina.fund.listed_fund_quote',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Sina ETF quote/list support remains governed by fund.etf_quote; listed-fund and money-market fund quote semantics are not proven for this interface.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.listed_fund_quote',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Current Wind manifest/probe evidence does not prove a reusable listed-fund or exchange money-market quote route for this interface.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.etf_daily_ohlcv_bars',
    label: 'ETF daily OHLCV bars',
    canonicalSchema: 'kline_daily',
    dataStoreTables: ['kline_daily'],
    queryActions: ['query_kline'],
    params: [
      'symbols',
      'startDate',
      'endDate',
      'adjust',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'kline_daily requested-window cache-first for ETF symbols',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.etf_daily_ohlcv_bars',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        adapter: 'native EastMoney ETF daily K-line route',
        reason:
            'ETF daily bars do not yet have a mobile-traced direct EastMoney ETF-specific provider boundary; keep the interface/readback visible but do not route live calls here.',
      ),
      DataApiProviderCapability(
        id: 'akshare.sina.fund.etf_daily_ohlcv_bars',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        upstreamOrigin: 'sina',
        reason:
            'AkShare decodes the Sina ETF KLC payload in the Electron sidecar. Shared mobile/FinAgent has no native AkShare wrapper route, so this capability is not callable here.',
      ),
      DataApiProviderCapability(
        id: 'sina.fund.etf_daily_ohlcv_bars',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.notSupported,
        adapter: 'realstock/company/{symbol}/hisdata_klc2/klc_kl.js',
        reason:
            'Direct Sina ETF daily K-line returns encrypted KLC_K2 JavaScript payload; mobile native decoder is not implemented.',
      ),
      DataApiProviderCapability(
        id: 'tencent.fund.etf_daily_ohlcv_bars',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'proxy.finance.qq.com ifzqgtimg newfqkline ETF day',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        probeId: 'tencent.kline.etf_none',
        priority: 1,
        reason:
            'Shared mobile Tencent ETF unadjusted daily OHLCV route normalizes bounded SH/SZ ETF bars into kline_daily and reuses query_kline. qfq/hfq remain unsupported on mobile until adjusted ETF bars are proven separately.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.etf_daily_ohlcv_bars',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        adapter: 'WindMcp ETF daily K-line path not registered',
        reason:
            'Current Wind manifest/probe evidence does not prove a reusable ETF daily OHLCV route for this interface.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.etf_transactions',
    label: 'ETF transaction ticks',
    canonicalSchema: 'transactions',
    dataStoreTables: ['transactions'],
    queryActions: ['query_transactions'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first for ETF symbols',
    capabilities: [
      DataApiProviderCapability(
        id: 'tencent.fund.etf_transactions',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'stock.gtimg.cn data/index.php ETF detail pages',
        normalizer: 'TencentFetcher.getEtfTransactions/saveTransactions',
        canonicalTable: 'transactions',
        probeId: 'tencent.transactions.etf_page_0',
        priority: 1,
        reason:
            'Shared mobile Tencent ETF transaction route normalizes bounded SH/SZ ETF transaction pages into canonical transactions and reuses query_transactions with fund.etf_transactions provenance.',
      ),
      DataApiProviderCapability(
        id: 'tdx.fund.etf_transactions',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The current native TDX transaction route is governed for stock.transactions; ETF transaction evidence and provider boundary have not been proven for this interface.',
      ),
      DataApiProviderCapability(
        id: 'sina.fund.etf_transactions',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No direct Sina ETF transaction endpoint has passed a bounded mobile live probe with canonical transactions readback.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.fund.etf_transactions',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a proven ETF transaction-tick dataset equivalent to fund.etf_transactions.',
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.etf_transactions',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile/FinAgent has no native AkShare sidecar route for ETF transaction ticks.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.etf_transactions',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose ETF transaction tick rows equivalent to fund.etf_transactions.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.manager',
    label: 'Fund manager',
    canonicalSchema: 'fund_manager',
    dataStoreTables: ['fund_manager'],
    queryActions: ['query_fund_manager'],
    params: ['company', 'manager', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'weekly-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.manager',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney fund manager route',
        normalizer: 'fund_manager canonical writer',
        canonicalTable: 'fund_manager',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.manager',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare fund manager is Electron sidecar-backed; no mobile-native adapter is registered.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.manager',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_info/get_fund_company_info',
        normalizer: 'tryNormalizeWindFundManagerPayload',
        canonicalTable: 'fund_manager',
        probeId: 'electron_wind_fund_company_info',
        reason:
            'Wind fund info tools require configured credential and quota; manager fields are reusable through fund_manager when a native Wind route is enabled.',
        priority: 2,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.nav_history',
    label: 'Fund NAV history',
    canonicalSchema: 'fund_nav',
    dataStoreTables: ['fund_nav'],
    queryActions: ['query_fund_nav'],
    params: [
      'code',
      'startDate',
      'endDate',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'daily-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.nav_history',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'pingzhongdata Data_netWorthTrend',
        normalizer: 'fund_nav canonical writer',
        canonicalTable: 'fund_nav',
        reason:
            'Native EastMoney fund NAV fetch/persist/readback path is implemented in shared mobile/FinAgent.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.nav_history',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        upstreamOrigin: 'eastmoney',
        reason:
            'AkShare fund NAV route is desktop sidecar-backed; mobile must stay native until a real provider path exists.',
      ),
      DataApiProviderCapability(
        id: 'tushare.fund.nav_history',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.disabled,
        reason:
            'fund_nav returned 40203 permission errors and is app-disabled.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.nav_history',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp fund_data.get_fund_kline',
        normalizer: 'tryNormalizeWindFundNavPayload',
        canonicalTable: 'fund_nav',
        probeId: 'mobile_marketdata_wind_fund_kline',
        reason:
            'Wind fund K-line requires configured credential and quota; normalized daily NAV rows are reusable through fund_nav.',
        priority: 4,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.money_yield_history',
    label: 'Money fund yield history',
    canonicalSchema: 'fund_money_yield',
    dataStoreTables: ['fund_money_yield'],
    queryActions: ['query_fund_money_yield'],
    params: [
      'code',
      'startDate',
      'endDate',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'daily-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.fund.money_yield_history',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter:
            'pingzhongdata Data_millionCopiesIncome/Data_sevenDaysYearIncome',
        normalizer: 'fund_money_yield canonical writer',
        canonicalTable: 'fund_money_yield',
        probeId: 'electron_eastmoney_fund_money_yield',
        reason:
            'Money funds expose yield history rather than ordinary NAV trend; shared mobile/FinAgent should route them through this separate interface.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.fund.money_yield_history',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        upstreamOrigin: 'eastmoney',
        reason:
            'AkShare money-fund yield route is desktop sidecar-backed and is not a mobile-native provider path.',
      ),
      DataApiProviderCapability(
        id: 'tushare.fund.money_yield_history',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.disabled,
        reason:
            'Tushare fund permissions are disabled in this app; money-fund yield is not exposed through raw Tushare.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.money_yield_history',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Current Wind fund tools do not expose a proven per-10k income / seven-day yield history contract matching fund_money_yield.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'fund.dividend_factor',
    label: 'Fund dividend and factor history',
    canonicalSchema: 'fund_dividend_factor',
    dataStoreTables: ['fund_dividend_factor'],
    queryActions: ['query_fund_dividend_factor'],
    params: [
      'code',
      'startDate',
      'endDate',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'event-history-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'sina.fund.dividend_factor',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        upstreamOrigin: 'sina',
        adapter: 'SinaFetcher.getFundDividendFactors / hfq.js',
        normalizer: 'saveFundDividendFactors',
        canonicalTable: 'fund_dividend_factor',
        probeId: 'mobile_sina_fund_dividend_factor',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.fund.dividend_factor',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No mobile EastMoney fund dividend/factor route has proven this event-history schema and readback.',
      ),
      DataApiProviderCapability(
        id: 'wind.fund.dividend_factor',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind may expose dividend facts through credential-gated fund financial data, but no dedicated fund_dividend_factor mobile normalizer/readback has been proven.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.chip_distribution',
    label: 'Stock chip distribution',
    canonicalSchema: 'chip_distribution',
    dataStoreTables: ['chip_distribution'],
    queryActions: ['query_chip'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'daily-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.stock.chip_distribution',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney chip distribution provider route',
        normalizer: 'saveChipDistribution',
        canonicalTable: 'chip_distribution',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.stock.chip_distribution',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare chip distribution is Electron sidecar-backed; no mobile-native adapter is registered.',
      ),
      DataApiProviderCapability(
        id: 'tdx.stock.chip_distribution',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The TDX provider contract in this runtime does not expose a stable dataset equivalent to stock.chip_distribution; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.chip_distribution',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a chip-distribution dataset equivalent to stock.chip_distribution.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.sector_ranking',
    label: 'Market sector ranking',
    canonicalSchema: 'sector_rank',
    dataStoreTables: ['sector_rank'],
    queryActions: ['query_sector_ranking', 'query_sector'],
    params: ['boardType', 'date', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.sector_ranking',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney sector ranking provider route',
        normalizer: 'sector_rank canonical writer',
        canonicalTable: 'sector_rank',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.sector_ranking',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare sector ranking is currently sidecar-backed in Fin Electron; shared mobile / FinAgent uses native EastMoney sector routes and has no native AkShare adapter.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.sector_ranking',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose canonical sector_rank.',
      ),
      DataApiProviderCapability(
        id: 'sina.market.sector_ranking',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'newSinaHy.php/newFLJK.php',
        normalizer: 'SinaFetcher.getSectorRanking',
        canonicalTable: 'sector_rank',
        probeId: 'sina.direct.market_sector_ranking_industry',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'tushare.market.sector_ranking',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No Tushare sector-ranking capability is registered in mobile.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.sector_ranking',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a market-wide sector ranking dataset equivalent to market.sector_ranking.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.sector_constituents',
    label: 'Sector constituents',
    canonicalSchema: 'industry_map',
    dataStoreTables: ['industry_map', 'quote_snapshot', 'stock_list'],
    queryActions: [
      'query_sector_constituents',
      'query_industry_map',
      'query_quote',
      'query_stock_list',
    ],
    params: [
      'sectorCode',
      'sectorName',
      'boardType',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'intraday-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.sector_constituents',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney sector constituent provider route',
        normalizer: 'industry_map canonical writer',
        canonicalTable: 'industry_map',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.sector_constituents',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare board constituent wrappers are sidecar-backed and are not a proven mobile requirement-level sector identifier route.',
      ),
      DataApiProviderCapability(
        id: 'sina.market.sector_constituents',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Market_Center.getHQNodeData node=<sina sector node>',
        normalizer: 'SinaFetcher.getSectorStocks',
        canonicalTable: 'industry_map',
        probeId: 'sina.direct.market_sector_constituents',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'tdx.market.sector_constituents',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The TDX provider contract in this runtime does not expose a stable dataset equivalent to market.sector_constituents; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.sector_constituents',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a sector constituent route equivalent to market.sector_constituents.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.board_ranking',
    label: 'Board ranking and list',
    canonicalSchema: 'sector_rank',
    dataStoreTables: ['sector_rank'],
    queryActions: ['query_board_ranking', 'query_sector'],
    params: ['boardType', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'intraday-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.board_ranking',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney sector ranking provider route',
        normalizer: 'sector_rank canonical writer',
        canonicalTable: 'sector_rank',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.board_ranking',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare board ranking wrappers are sidecar-backed in Fin Electron; shared mobile / FinAgent uses native EastMoney sector routes.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.board_ranking',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX mac/board_list is implemented by Fin Electron gotdx. Shared mobile / FinAgent does not expose an equivalent native board-list fetch route yet.',
      ),
      DataApiProviderCapability(
        id: 'sina.market.board_ranking',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'newFLJK.php',
        normalizer: 'SinaFetcher.getSectorRanking',
        canonicalTable: 'sector_rank',
        probeId: 'sina.direct.market_sector_ranking_concept',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'wind.market.board_ranking',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a board ranking dataset equivalent to market.board_ranking.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.board_members',
    label: 'Board member list',
    canonicalSchema: 'industry_map',
    dataStoreTables: ['industry_map', 'quote_snapshot', 'stock_list'],
    queryActions: ['query_board_members', 'query_industry_map', 'query_quote'],
    params: [
      'boardCode',
      'boardName',
      'boardType',
      'symbols',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'intraday-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.board_members',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney sector constituent provider route',
        normalizer: 'industry_map canonical writer',
        canonicalTable: 'industry_map',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.board_members',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare board-member wrappers are sidecar-backed in Fin Electron; shared mobile / FinAgent uses native EastMoney sector routes.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.board_members',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX mac board-member endpoints are implemented by Fin Electron gotdx; shared mobile / FinAgent only exposes tdx_block_member for native TDX block files.',
      ),
      DataApiProviderCapability(
        id: 'sina.market.board_members',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Market_Center.getHQNodeData node route',
        normalizer: 'SinaFetcher.getSectorStocks + industry_map writer',
        canonicalTable: 'industry_map',
        probeId: 'sina.direct.market_sector_constituents',
        reason:
            'Sina node-style concept board constituent rows share the governed board-member schema when the caller supplies boardCode/boardName or boardType:"concept".',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'wind.market.board_members',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose board members equivalent to market.board_members.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.northbound_flow',
    label: 'Northbound capital flow',
    canonicalSchema: 'northbound_flow',
    dataStoreTables: ['northbound_flow', 'northbound_holding'],
    queryActions: ['query_northbound_flow', 'query_northbound'],
    params: ['days', 'symbols', 'kind', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.northbound_flow',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney northbound provider route',
        normalizer: 'northbound canonical writer',
        canonicalTable: 'northbound_flow',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.northbound_flow',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent has no native AkShare northbound adapter.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.northbound_flow',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose canonical northbound data.',
      ),
      DataApiProviderCapability(
        id: 'tushare.market.northbound_flow',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No Tushare northbound capability is registered in mobile.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.northbound_flow',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a northbound flow dataset equivalent to market.northbound_flow.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.northbound_holding',
    label: 'Northbound stock holding',
    canonicalSchema: 'northbound_holding',
    dataStoreTables: ['northbound_holding', 'stock_list'],
    queryActions: ['query_northbound_holding', 'query_northbound'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.northbound_holding',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney northbound holding provider route',
        normalizer: 'northbound_holding canonical writer',
        canonicalTable: 'northbound_holding',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.northbound_holding',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare northbound holding wrappers are sidecar-backed and are not a proven mobile code-specific canonical route.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.northbound_holding',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The TDX provider contract in this runtime does not expose a stable dataset equivalent to market.northbound_holding; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.northbound_holding',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a northbound holding dataset equivalent to market.northbound_holding.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.hot_rank',
    label: 'Hot stock ranking',
    canonicalSchema: 'hot_rank',
    dataStoreTables: ['hot_rank'],
    queryActions: ['query_hot_rank'],
    params: ['limit', 'date', 'code', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.hot_rank',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney hot-rank provider route',
        normalizer: 'hot_rank canonical writer',
        canonicalTable: 'hot_rank',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.hot_rank',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent has no native AkShare hot-rank adapter.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.hot_rank',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose canonical hot-rank data.',
      ),
      DataApiProviderCapability(
        id: 'tushare.market.hot_rank',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No Tushare hot-rank capability is registered in mobile.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.hot_rank',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a hot-rank dataset equivalent to market.hot_rank.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.dragon_tiger',
    label: 'Dragon tiger board',
    canonicalSchema: 'dragon_tiger',
    dataStoreTables: ['dragon_tiger'],
    queryActions: ['query_dragon_tiger'],
    params: ['date', 'code', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.dragon_tiger',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney dragon-tiger provider route',
        normalizer: 'dragon_tiger canonical writer',
        canonicalTable: 'dragon_tiger',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.dragon_tiger',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent has no native AkShare dragon-tiger adapter.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.dragon_tiger',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose canonical dragon-tiger data.',
      ),
      DataApiProviderCapability(
        id: 'tushare.market.dragon_tiger',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No Tushare dragon-tiger capability is registered in mobile.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.dragon_tiger',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a dragon-tiger dataset equivalent to market.dragon_tiger.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.unusual_activity',
    label: 'Unusual market activity',
    canonicalSchema: 'unusual_activity',
    dataStoreTables: ['unusual_activity'],
    queryActions: ['query_unusual'],
    params: ['date', 'code', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'event-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.unusual_activity',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney unusual-activity provider route',
        normalizer: 'unusual_activity canonical writer',
        canonicalTable: 'unusual_activity',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.unusual_activity',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent has no native AkShare unusual-activity adapter.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.unusual_activity',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Native TDX unusual-activity provider route',
        normalizer: 'unusual_activity canonical writer',
        canonicalTable: 'unusual_activity',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'tushare.market.unusual_activity',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No Tushare unusual-activity capability is registered in mobile.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.unusual_activity',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a market-wide unusual-activity dataset equivalent to market.unusual_activity.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.flow_rank',
    label: 'Market money-flow ranking',
    canonicalSchema: 'flow_rank',
    dataStoreTables: ['flow_rank'],
    queryActions: ['query_flow_rank'],
    params: ['period', 'date', 'code', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.flow_rank',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney flow-rank provider route',
        normalizer: 'flow_rank canonical writer',
        canonicalTable: 'flow_rank',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.flow_rank',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent has no native AkShare flow-rank adapter.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.flow_rank',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose canonical flow-rank data.',
      ),
      DataApiProviderCapability(
        id: 'tushare.market.flow_rank',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No Tushare flow-rank capability is registered in mobile.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.flow_rank',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a market-wide flow ranking dataset equivalent to market.flow_rank.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'calendar.trade_days',
    label: 'Trade calendar',
    canonicalSchema: 'trade_calendar',
    dataStoreTables: ['trade_calendar'],
    queryActions: ['query_trade_calendar'],
    params: ['market', 'startDate', 'endDate', 'provider', 'providerMode'],
    freshnessPolicy: 'calendar-year-coverage',
    capabilities: [
      DataApiProviderCapability(
        id: 'szse.calendar.trade_days',
        provider: FinanceProvider.szse,
        status: DataApiCapabilityStatus.supported,
        adapter: 'SZSE monthList',
        normalizer: 'trade_calendar canonical writer',
        canonicalTable: 'trade_calendar',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'tushare.calendar.trade_days',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.supported,
        adapter: 'trade_cal',
        normalizer: 'trade_calendar canonical writer',
        canonicalTable: 'trade_calendar',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'akshare.calendar.trade_days',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        upstreamOrigin: 'sina',
        adapter: 'tool_trade_date_hist_sina',
        normalizer: 'trade_calendar canonical writer',
        canonicalTable: 'trade_calendar',
        probeId: 'sina.reference.akshare.tool_trade_date_hist_sina',
        reason:
            'AkShare tool_trade_date_hist_sina is a Sina-origin Python sidecar wrapper supported in Fin Electron. Shared mobile/FinAgent has trade_calendar storage/readback but no native AkShare/Sina calendar wrapper route, so this provider remains explicit not-supported.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.calendar.trade_days',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No stable mobile EastMoney trade-calendar provider registered.',
      ),
      DataApiProviderCapability(
        id: 'tdx.calendar.trade_days',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose a canonical trade calendar.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.limit_pool',
    label: 'Limit-up/down pool',
    canonicalSchema: 'limit_pool',
    dataStoreTables: ['limit_pool'],
    queryActions: ['query_limit_pool'],
    params: ['poolType', 'date', 'code', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.market.limit_pool',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney limit pool provider route',
        normalizer: 'limit_pool canonical writer',
        canonicalTable: 'limit_pool',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.market.limit_pool',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent has no native AkShare limit-pool adapter.',
      ),
      DataApiProviderCapability(
        id: 'tushare.market.limit_pool',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No Tushare limit-pool capability is registered in mobile.',
      ),
      DataApiProviderCapability(
        id: 'tdx.market.limit_pool',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'TDX mobile route does not expose canonical limit pools.',
      ),
      DataApiProviderCapability(
        id: 'wind.market.limit_pool',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose a limit-up/down pool dataset equivalent to market.limit_pool.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.tick_chart_intraday',
    label: 'Stock intraday tick chart',
    canonicalSchema: 'tick_chart_intraday',
    dataStoreTables: ['tick_chart_intraday'],
    queryActions: ['query_tick_chart'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.tick_chart_intraday',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readTickChart/readHistoryTick',
        normalizer: 'saveTickChart',
        canonicalTable: 'tick_chart_intraday',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.tick_chart_intraday',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to stock.tick_chart_intraday; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.tick_chart_intraday',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose intraday tick-chart rows equivalent to stock.tick_chart_intraday.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.transactions',
    label: 'Stock transaction ticks',
    canonicalSchema: 'transactions',
    dataStoreTables: ['transactions'],
    queryActions: ['query_transactions'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.transactions',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readTransactions/readHistoryTransactions',
        normalizer: 'saveTransactions',
        canonicalTable: 'transactions',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'sina.stock.transactions',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'CN_Bill.GetBillList',
        normalizer: 'SinaFetcher.getTransactions',
        canonicalTable: 'transactions',
        probeId: 'sina.direct.stock_transactions',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'tencent.stock.transactions',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'stock.gtimg.cn data/index.php appn=detail action=data',
        normalizer: 'TencentFetcher.getStockTransactions/saveTransactions',
        canonicalTable: 'transactions',
        probeId: 'tencent.direct.stock_transactions',
        priority: 5,
        reason:
            'Shared mobile Tencent stock transaction route normalizes bounded SH/SZ transaction detail pages into canonical transactions and reuses query_transactions with stock.transactions provenance.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.transactions',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to stock.transactions; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.transactions',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose transaction tick rows equivalent to stock.transactions.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.volume_profile',
    label: 'Stock volume profile',
    canonicalSchema: 'volume_profile',
    dataStoreTables: ['volume_profile'],
    queryActions: ['query_volume_profile'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.volume_profile',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readVolumeProfile',
        normalizer: 'saveVolumeProfile',
        canonicalTable: 'volume_profile',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.volume_profile',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to stock.volume_profile; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.volume_profile',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose price-volume profile rows equivalent to stock.volume_profile.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.xdxr_events',
    label: 'Stock XDXR events',
    canonicalSchema: 'xdxr_event',
    dataStoreTables: ['xdxr_event'],
    queryActions: ['query_xdxr'],
    params: ['symbols', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'event-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.xdxr_events',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readXdxr',
        normalizer: 'saveXdxrEvents',
        canonicalTable: 'xdxr_event',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.xdxr_events',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to stock.xdxr_events; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.xdxr_events',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp stock_data.get_stock_events',
        normalizer: 'tryNormalizeWindXdxrPayload',
        canonicalTable: 'xdxr_event',
        probeId: 'electron_wind_stock_events',
        reason:
            'Wind requires configured credential and quota; only dividend/ex-right rows are persisted.',
        priority: 2,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.auction_snapshot',
    label: 'Stock auction snapshot',
    canonicalSchema: 'auction_snapshot',
    dataStoreTables: ['auction_snapshot'],
    queryActions: ['query_auction'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.auction_snapshot',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readAuction',
        normalizer: 'saveAuction',
        canonicalTable: 'auction_snapshot',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.auction_snapshot',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to stock.auction_snapshot; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.auction_snapshot',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The registered Wind AIFinMarket tool surface does not expose auction snapshot rows equivalent to stock.auction_snapshot.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.company_info',
    label: 'Stock company information',
    canonicalSchema: 'stock_company_info',
    dataStoreTables: ['stock_company_info'],
    queryActions: ['query_stock_company_info', 'query_company_info'],
    params: ['symbols', 'infoType', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'company-info-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.stock.company_info',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readCompanyCategories/readCompanyContent/readFinance',
        normalizer: 'saveCompanyInfo',
        canonicalTable: 'stock_company_info',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.stock.company_info',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter:
            'WindMcp stock_data.get_stock_basicinfo/get_stock_fundamentals',
        normalizer: 'persistWindResult',
        canonicalTable: 'stock_company_info',
        reason:
            'Requires Wind API key/quota and focused mobile readback verification.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.company_info',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney PC_HSF10 CompanySurveyAjax',
        normalizer: 'getStockCompanyInfo',
        canonicalTable: 'stock_company_info',
        priority: 2,
        reason:
            'Native EastMoney company-survey routing persists the structured PC_HSF10 CompanySurveyAjax payload into stock_company_info for governed stock.company_info reuse.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.shareholders',
    label: 'Stock shareholders',
    canonicalSchema: 'stock_shareholder',
    dataStoreTables: ['stock_shareholder'],
    queryActions: ['query_stock_shareholders'],
    params: [
      'symbols',
      'reportDate',
      'holderName',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'shareholder-report-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'akshare.stock.shareholders',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare shareholder ingestion is currently sidecar-backed in Fin Electron; shared mobile / FinAgent does not ship that sidecar.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.shareholders',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp stock_data.get_stock_equity_holders',
        normalizer: 'tryNormalizeWindStockShareholderPayload',
        canonicalTable: 'stock_shareholder',
        reason:
            'Requires Wind API key/quota; stock equity holder rows persist to stock_shareholder.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.stock.shareholders',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'EastMoney PC_HSF10 ShareholderResearch/PageAjax + PageSDGD',
        normalizer: 'getStockShareholders',
        canonicalTable: 'stock_shareholder',
        reason:
            'Native EastMoney shareholder routing resolves the latest report date from ShareholderResearch/PageAjax, then persists structured PageSDGD top-holder rows to stock_shareholder.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'tdx.stock.shareholders',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The TDX provider contract in this runtime does not expose a stable dataset equivalent to stock.shareholders; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.risk_metrics',
    label: 'Stock risk metrics',
    canonicalSchema: 'stock_company_info',
    dataStoreTables: ['stock_company_info'],
    queryActions: ['query_stock_risk_metrics', 'query_company_info'],
    params: ['symbols', 'period', 'metric', 'provider', 'providerMode'],
    freshnessPolicy: 'risk-metrics-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.stock.risk_metrics',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp stock_data.get_risk_metrics',
        normalizer: 'tryNormalizeWindCompanyInfoPayload',
        canonicalTable: 'stock_company_info',
        probeId: 'electron_wind_stock_risk_metrics',
        reason:
            'Wind stock risk metrics require configured credential and quota; beta, volatility, Sharpe, and VaR style rows are cached as typed company-info facts until a dedicated risk_metrics table is introduced.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'provider.api_call_log',
    label: 'Provider API call log',
    canonicalSchema: 'api_call_log',
    dataStoreTables: ['api_requests'],
    queryActions: ['query_api_calls', 'query_api_errors'],
    params: [
      'source',
      'provider',
      'endpoint',
      'failures',
      'minutes',
      'limit',
      'providerMode',
    ],
    freshnessPolicy: 'recent-api-log-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.provider.api_call_log',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'ApiStats.getRecentFailures',
        normalizer: 'ApiStats.record',
        canonicalTable: 'api_requests',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.provider.api_call_log',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; the durable API observability log is owned by the local mobile runtime.',
      ),
      DataApiProviderCapability(
        id: 'tdx.provider.api_call_log',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; the durable API observability log is owned by the local mobile runtime.',
      ),
      DataApiProviderCapability(
        id: 'yfinance.provider.api_call_log',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo/yfinance supplies upstream global data; the durable API observability log is owned by the local mobile runtime.',
      ),
      DataApiProviderCapability(
        id: 'wind.provider.api_call_log',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; the durable API observability log is owned by the local mobile runtime.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'provider.fetch_task_queue',
    label: 'Provider fetch task queue',
    canonicalSchema: 'fetch_task_queue',
    dataStoreTables: ['data_tasks'],
    queryActions: ['fetch_status'],
    params: ['status', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'current-fetch-queue-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.provider.fetch_task_queue',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'DataTaskEngine.list/get',
        normalizer: 'DataTaskEngine persisted task snapshot',
        canonicalTable: 'data_tasks',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.provider.fetch_task_queue',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; the durable fetch task queue is owned by the local mobile runtime.',
      ),
      DataApiProviderCapability(
        id: 'tdx.provider.fetch_task_queue',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; the durable fetch task queue is owned by the local mobile runtime.',
      ),
      DataApiProviderCapability(
        id: 'yfinance.provider.fetch_task_queue',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo/yfinance supplies upstream global data; the durable fetch task queue is owned by the local mobile runtime.',
      ),
      DataApiProviderCapability(
        id: 'wind.provider.fetch_task_queue',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; the durable fetch task queue is owned by the local mobile runtime.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'provider.coverage',
    label: 'Provider coverage metadata',
    canonicalSchema: 'provider_coverage',
    dataStoreTables: ['tdx_security_count', 'tdx_chart_sampling'],
    queryActions: ['query_tdx_count', 'query_tdx_sampling'],
    params: [
      'scope',
      'market',
      'code',
      'category',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'provider-metadata-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.provider.coverage',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'TdxDataFetchTool tdx_count/tdx_sampling/ex_count/ex_sampling',
        normalizer:
            'saveTdxSecurityCounts/saveTdxChartSampling via TdxMarketDataRepository/ExTdxMarketDataRepository',
        canonicalTable: 'tdx_security_count',
        probeId: 'mobile_marketdata_tdx_count',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.provider.coverage',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to provider.coverage; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'akshare.provider.coverage',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The AkShare sidecar provider contract in this runtime does not expose a stable dataset equivalent to provider.coverage; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'provider.table_metadata',
    label: 'Provider table metadata',
    canonicalSchema: 'provider_table_metadata',
    dataStoreTables: ['ex_category', 'ex_table_entry'],
    queryActions: ['query_ex_categories', 'query_ex_table'],
    params: ['code', 'category', 'table', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'provider-table-metadata-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.provider.table_metadata',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter:
            'TdxDataFetchTool ex_categories/ex_table/ex_list_extra/ex_server_info',
        normalizer:
            'saveExCategories/saveExTableEntries via ExTdxMarketDataRepository',
        canonicalTable: 'ex_category',
        probeId: 'mobile_marketdata_ex_categories',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.provider.table_metadata',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to provider.table_metadata; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'akshare.provider.table_metadata',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The AkShare sidecar provider contract in this runtime does not expose a stable dataset equivalent to provider.table_metadata; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.tdx_block_member',
    label: 'TDX block members',
    canonicalSchema: 'tdx_block_member',
    dataStoreTables: ['tdx_block_member'],
    queryActions: ['query_tdx_block_member'],
    params: [
      'symbols',
      'filename',
      'blockName',
      'blockCode',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'block-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.market.tdx_block_member',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readBlockMembers',
        normalizer: 'saveTdxBlockMembers',
        canonicalTable: 'tdx_block_member',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.market.tdx_block_member',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to market.tdx_block_member; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.tdx_top_board',
    label: 'TDX top board',
    canonicalSchema: 'tdx_top_board',
    dataStoreTables: ['tdx_top_board'],
    queryActions: ['query_top_board'],
    params: ['category', 'side', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.market.tdx_top_board',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readTopBoard',
        normalizer: 'saveTopBoard',
        canonicalTable: 'tdx_top_board',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.market.tdx_top_board',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to market.tdx_top_board; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'index.momentum',
    label: 'Index momentum',
    canonicalSchema: 'tdx_index_momentum',
    dataStoreTables: ['tdx_index_momentum'],
    queryActions: ['query_momentum'],
    params: ['symbols', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'tdx.index.momentum',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.supported,
        adapter: 'readMomentum',
        normalizer: 'saveIndexMomentum',
        canonicalTable: 'tdx_index_momentum',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.index.momentum',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The EastMoney direct provider contract in this runtime does not expose a stable dataset equivalent to index.momentum; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
      DataApiProviderCapability(
        id: 'wind.index.momentum',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp index_data.get_index_technicals',
        normalizer: 'tryNormalizeWindIndexMomentumPayload',
        canonicalTable: 'tdx_index_momentum',
        probeId: 'electron_wind_index_technicals',
        reason:
            'Wind requires configured credential and quota; numeric index technical rows are persisted.',
        priority: 2,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'index.profile',
    label: 'Index profile',
    canonicalSchema: 'stock_company_info',
    dataStoreTables: ['stock_company_info', 'stock_list'],
    queryActions: ['query_index_profile', 'query_company_info'],
    params: ['symbols', 'infoType', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'index-profile-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.index.profile',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp index_data.get_index_basicinfo',
        normalizer: 'tryNormalizeWindCompanyInfoPayload',
        canonicalTable: 'stock_company_info',
        probeId: 'electron_wind_index_basicinfo',
        reason:
            'Wind index profile requires configured credential and quota; index archive rows are cached through stock_company_info until a dedicated index_profile table is introduced.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'index.fundamentals',
    label: 'Index fundamentals',
    canonicalSchema: 'fundamental',
    dataStoreTables: ['fundamental'],
    queryActions: ['query_index_fundamentals', 'query_fundamental'],
    params: ['symbols', 'reportDate', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'index-fundamentals-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.index.fundamentals',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp index_data.get_index_fundamentals',
        normalizer: 'tryNormalizeWindFundamentalPayload',
        canonicalTable: 'fundamental',
        probeId: 'electron_wind_index_fundamentals',
        reason:
            'Wind index fundamental rows require configured credential and quota; normalized valuation and financial facts are reusable through fundamental.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'wind.financial_document',
    label: 'Wind financial documents',
    canonicalSchema: 'wind_document',
    dataStoreTables: ['wind_document'],
    queryActions: ['query_wind_document'],
    params: ['query', 'tool', 'code', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'research-document-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.financial_document',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter:
            'WindMcp financial_docs.get_company_announcements/get_financial_news',
        normalizer: 'persistWindResult',
        canonicalTable: 'wind_document',
        reason:
            'Wind financial_docs requires configured credential and quota; cached wind_document rows are reusable through the interface.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'wind.economic_series',
    label: 'Wind economic series',
    canonicalSchema: 'wind_economic_series',
    dataStoreTables: ['wind_economic_series'],
    queryActions: ['query_wind_economic'],
    params: ['metricQuery', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.economic_series',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp economic_data.get_economic_data',
        normalizer: 'persistWindResult',
        canonicalTable: 'wind_economic_series',
        reason:
            'Wind economic data requires configured credential and quota; cached rows are reusable through query_wind_economic.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'wind.analytics_result',
    label: 'Wind analytics result',
    canonicalSchema: 'wind_analytics_result',
    dataStoreTables: ['wind_analytics_result'],
    queryActions: ['query_wind_analytics'],
    params: ['question', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.analytics_result',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp analytics_data.get_financial_data',
        normalizer: 'persistWindResult',
        canonicalTable: 'wind_analytics_result',
        reason:
            'Wind analytics data requires configured credential and quota; cached rows are reusable through query_wind_analytics.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'news.finance_feed',
    label: 'Finance news feed',
    canonicalSchema: 'finance_news',
    dataStoreTables: ['finance_news'],
    queryActions: ['query_finance_news'],
    params: ['keyword', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'published_at max-age',
    capabilities: [
      DataApiProviderCapability(
        id: 'eastmoney.news.finance_feed',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Research(news) EastMoney finance search',
        normalizer: 'saveFinanceNews',
        canonicalTable: 'finance_news',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'sina.news.finance_feed',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.supported,
        adapter: 'Research(news) Sina finance feed',
        normalizer: 'saveFinanceNews',
        canonicalTable: 'finance_news',
        priority: 2,
      ),
      DataApiProviderCapability(
        id: 'tushare.news.finance_feed',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'Research(news) Tushare major_news/anns',
        normalizer: 'saveFinanceNews',
        canonicalTable: 'finance_news',
        reason: 'Tushare news requires configured TUSHARE_TOKEN.',
        priority: 3,
      ),
      DataApiProviderCapability(
        id: 'wind.news.finance_feed',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp financial_docs.get_financial_news',
        normalizer: 'tryNormalizeWindFinanceNewsPayload',
        canonicalTable: 'finance_news',
        reason:
            'Wind get_financial_news requires configured credential and quota; broad finance news rows persist to finance_news when the Wind MCP tool is available.',
        priority: 4,
      ),
      DataApiProviderCapability(
        id: 'yfinance.news.finance_feed',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo does not provide the broad finance-feed semantics for news.finance_feed in this app; symbol-scoped Yahoo news is governed by global.finance_news.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.company_profile',
    label: 'Global company profile',
    canonicalSchema: 'yfinance_profile_fields',
    dataStoreTables: ['yfinance_profile_fields'],
    queryActions: ['query_global_company_profile', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.company_profile',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quoteSummary profile modules',
        normalizer: 'saveYfinanceProfileFields',
        canonicalTable: 'yfinance_profile_fields',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.company_profile',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global profile probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.financial_statements',
    label: 'Global financial statements',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_financial_statements', 'query_yfinance'],
    params: [
      'symbols',
      'dataset',
      'statementType',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.financial_statements',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quoteSummary statement modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.financial_statements',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global fundamentals probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.income_statement',
    label: 'Global income statement',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_income_statement', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.income_statement',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo incomeStatementHistory modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.income_statement',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global income-statement probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.balance_sheet',
    label: 'Global balance sheet',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_balance_sheet', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.balance_sheet',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo balanceSheetHistory modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.balance_sheet',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global balance-sheet probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.cash_flow',
    label: 'Global cash flow statement',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_cash_flow', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.cash_flow',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo cashflowStatementHistory modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.cash_flow',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global cash-flow probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.earnings_calendar',
    label: 'Global earnings calendar',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_earnings_calendar', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.earnings_calendar',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo earnings_dates / earnings_history',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.earnings_calendar',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No Wind global earnings-calendar route is registered in the current app contract.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.earnings_history',
    label: 'Global earnings history',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_earnings_history', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.earnings_history',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo earnings_history',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.earnings_history',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No Wind global earnings-history route is registered in the current app contract.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.earnings_estimates',
    label: 'Global earnings estimates',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_earnings_estimates', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.earnings_estimates',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo earnings_estimate / eps_revisions / eps_trend',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.earnings_estimates',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No Wind global earnings-estimate route is registered in the current app contract.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.eps_revisions',
    label: 'Global EPS revisions',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_eps_revisions', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.eps_revisions',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo eps_revisions',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.eps_revisions',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No Wind global EPS revisions route is registered in the current app contract.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.eps_trend',
    label: 'Global EPS trend',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_eps_trend', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.eps_trend',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo eps_trend',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.eps_trend',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No Wind global EPS trend route is registered in the current app contract.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.quarterly_financial_statements',
    label: 'Global quarterly financial statements',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: [
      'query_global_quarterly_financial_statements',
      'query_yfinance',
    ],
    params: [
      'symbols',
      'dataset',
      'statementType',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.quarterly_financial_statements',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quarterly financial statement modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.quarterly_financial_statements',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global quarterly-fundamental probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.quarterly_income_statement',
    label: 'Global quarterly income statement',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_quarterly_income_statement', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.quarterly_income_statement',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quarterly income statement modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.quarterly_income_statement',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global quarterly income-statement probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.quarterly_balance_sheet',
    label: 'Global quarterly balance sheet',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_quarterly_balance_sheet', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.quarterly_balance_sheet',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quarterly balance sheet modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.quarterly_balance_sheet',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global quarterly balance-sheet probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.quarterly_cash_flow',
    label: 'Global quarterly cash flow statement',
    canonicalSchema: 'yfinance_statement_items',
    dataStoreTables: ['yfinance_statement_items'],
    queryActions: ['query_global_quarterly_cash_flow', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.quarterly_cash_flow',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quarterly cash flow modules',
        normalizer: 'saveYfinanceStatementItems',
        canonicalTable: 'yfinance_statement_items',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.quarterly_cash_flow',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global quarterly cash-flow probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.recommendations',
    label: 'Global analyst recommendations',
    canonicalSchema: 'yfinance_recommendations',
    dataStoreTables: ['yfinance_recommendations'],
    queryActions: ['query_global_recommendations', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.recommendations',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quoteSummary recommendationTrend',
        normalizer: 'saveYfinanceRecommendations',
        canonicalTable: 'yfinance_recommendations',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.recommendations',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global recommendation probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.upgrade_downgrade_events',
    label: 'Global upgrade/downgrade events',
    canonicalSchema: 'yfinance_recommendations',
    dataStoreTables: ['yfinance_recommendations'],
    queryActions: ['query_global_upgrade_downgrade_events', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.upgrade_downgrade_events',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo upgrades_downgrades',
        normalizer: 'saveYfinanceRecommendations',
        canonicalTable: 'yfinance_recommendations',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.upgrade_downgrade_events',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No Wind global upgrade/downgrade route is registered in the current app contract.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.holders',
    label: 'Global holders',
    canonicalSchema: 'yfinance_holders',
    dataStoreTables: ['yfinance_holders'],
    queryActions: ['query_global_holders', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.holders',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quoteSummary ownership modules',
        normalizer: 'saveYfinanceHolders',
        canonicalTable: 'yfinance_holders',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.holders',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global holder probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.major_holders',
    label: 'Global major holders',
    canonicalSchema: 'yfinance_holders',
    dataStoreTables: ['yfinance_holders'],
    queryActions: ['query_global_major_holders', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.major_holders',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo majorHoldersBreakdown / major_holders',
        normalizer: 'saveYfinanceHolders',
        canonicalTable: 'yfinance_holders',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.major_holders',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The Wind AIFinMarket provider contract in this runtime does not expose a stable dataset equivalent to global.major_holders; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.institutional_holders',
    label: 'Global institutional holders',
    canonicalSchema: 'yfinance_holders',
    dataStoreTables: ['yfinance_holders'],
    queryActions: ['query_global_institutional_holders', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.institutional_holders',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quoteSummary institutionOwnership',
        normalizer: 'saveYfinanceHolders',
        canonicalTable: 'yfinance_holders',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.institutional_holders',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind institutional-holder probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.mutual_fund_holders',
    label: 'Global mutual fund holders',
    canonicalSchema: 'yfinance_holders',
    dataStoreTables: ['yfinance_holders'],
    queryActions: ['query_global_mutual_fund_holders', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.mutual_fund_holders',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quoteSummary fundOwnership',
        normalizer: 'saveYfinanceHolders',
        canonicalTable: 'yfinance_holders',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.mutual_fund_holders',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind mutual-fund-holder probes exist, but the current interface-first global research route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.insider_transactions',
    label: 'Global insider transactions',
    canonicalSchema: 'yfinance_insider_transactions',
    dataStoreTables: ['yfinance_insider_transactions'],
    queryActions: ['query_global_insider_transactions', 'query_yfinance'],
    params: ['symbols', 'dataset', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-research-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.insider_transactions',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo quoteSummary insiderTransactions',
        normalizer: 'saveYfinanceInsiderTransactions',
        canonicalTable: 'yfinance_insider_transactions',
        probeId: 'mobile_yahoo_earnings',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.insider_transactions',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The Wind AIFinMarket provider contract in this runtime does not expose a stable dataset equivalent to global.insider_transactions; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.expiry_calendar',
    label: 'Option expiry calendar',
    canonicalSchema: 'yfinance_option_expiries',
    dataStoreTables: ['yfinance_option_expiries'],
    queryActions: ['query_option_expiry_calendar', 'query_yfinance'],
    params: ['symbols', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.expiry_calendar',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo options expiry calendar',
        normalizer: 'saveYfinanceOptionExpiries',
        canonicalTable: 'yfinance_option_expiries',
        probeId: 'mobile_yahoo_options',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.expiry_calendar',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No stable Wind option expiry-calendar schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.contract_list',
    label: 'Option contract list',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_contract_list', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'optionType',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.contract_list',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain contracts',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.contract_list',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option contract-list schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.quote',
    label: 'Option quote',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_quote', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.quote',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain quote fields',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry quote fields such as last, bid, ask, volume, open interest, and implied volatility.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.quote',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option quote schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.daily_kline',
    label: 'Option daily K-line',
    canonicalSchema: 'kline_daily',
    dataStoreTables: ['kline_daily'],
    queryActions: ['query_option_daily_kline', 'query_kline'],
    params: [
      'symbols',
      'period',
      'range',
      'startDate',
      'endDate',
      'limit',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-history-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.daily_kline',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option contract history',
        normalizer: 'saveKline',
        canonicalTable: 'kline_daily',
        probeId: 'electron_yahoo_history',
        reason:
            'Yahoo chart history can persist option-contract daily bars into kline_daily for global option contracts.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.daily_kline',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option daily K-line schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.open_interest',
    label: 'Option open interest',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_open_interest', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.open_interest',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain openInterest fields',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry open interest and volume fields suitable for global option liquidity screening.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.open_interest',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option open-interest schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.volume',
    label: 'Option contract volume',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_volume', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.volume',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain volume fields',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry volume fields suitable for global option liquidity screening.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.volume',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option volume schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.implied_volatility',
    label: 'Option implied volatility',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_implied_volatility', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.implied_volatility',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain impliedVolatility fields',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry implied volatility and moneyness fields suitable for global option risk screening.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.implied_volatility',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No stable Wind option implied-volatility schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.moneyness',
    label: 'Option moneyness',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_moneyness', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.moneyness',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain inTheMoney fields',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry in-the-money fields suitable for global option moneyness screening.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.moneyness',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option moneyness schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.bid_ask_spread',
    label: 'Option bid/ask spread',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_bid_ask_spread', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.bid_ask_spread',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain bid/ask fields',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry bid and ask fields suitable for global option spread and liquidity screening.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.bid_ask_spread',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No stable Wind option bid/ask spread schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.price_change',
    label: 'Option price change',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_price_change', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.price_change',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain change/percentChange fields',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry change and percent-change fields suitable for global option momentum screening.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.price_change',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option price-change schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.trade_recency',
    label: 'Option trade recency',
    canonicalSchema: 'yfinance_option_contracts',
    dataStoreTables: ['yfinance_option_contracts'],
    queryActions: ['query_option_trade_recency', 'query_yfinance'],
    params: [
      'symbols',
      'expiry',
      'contractSymbol',
      'optionType',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.trade_recency',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo option chain lastTradeDate field',
        normalizer: 'saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        reason:
            'Yahoo option-chain contract rows carry last-trade timestamps suitable for global option activity and staleness screening.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.trade_recency',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason: 'No stable Wind option trade-recency schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'option.chain_snapshot',
    label: 'Option chain snapshot',
    canonicalSchema: 'yfinance_options',
    dataStoreTables: ['yfinance_option_expiries', 'yfinance_option_contracts'],
    queryActions: ['query_option_chain_snapshot', 'query_yfinance'],
    params: ['symbols', 'expiry', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.option.chain_snapshot',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo options chain snapshot',
        normalizer: 'saveYfinanceOptionExpiries/saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.option.chain_snapshot',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No stable Wind option-chain snapshot schema is registered yet.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.options_chain',
    label: 'Global options chain',
    canonicalSchema: 'yfinance_options',
    dataStoreTables: ['yfinance_option_expiries', 'yfinance_option_contracts'],
    queryActions: ['query_global_options_chain', 'query_yfinance'],
    params: ['symbols', 'expiry', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-options-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.options_chain',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo options chain',
        normalizer: 'saveYfinanceOptionExpiries/saveYfinanceOptionContracts',
        canonicalTable: 'yfinance_option_contracts',
        probeId: 'mobile_yahoo_options',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.options_chain',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The Wind AIFinMarket provider contract in this runtime does not expose a stable dataset equivalent to global.options_chain; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.corporate_actions',
    label: 'Global corporate actions',
    canonicalSchema: 'yfinance_corporate_actions',
    dataStoreTables: ['yfinance_corporate_actions'],
    queryActions: ['query_global_corporate_actions', 'query_yfinance'],
    params: ['symbols', 'period', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-event-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.corporate_actions',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo chart actions events',
        normalizer: 'saveYfinanceCorporateActions',
        canonicalTable: 'yfinance_corporate_actions',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.corporate_actions',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind global-events probes exist, but the current interface-first corporate-actions route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.dividends',
    label: 'Global dividends',
    canonicalSchema: 'yfinance_corporate_actions',
    dataStoreTables: ['yfinance_corporate_actions'],
    queryActions: ['query_global_dividends', 'query_yfinance'],
    params: ['symbols', 'period', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-event-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.dividends',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo chart dividend events',
        normalizer: 'saveYfinanceCorporateActions',
        canonicalTable: 'yfinance_corporate_actions',
        reason:
            'Yahoo corporate-action rows carry dividend events suitable for global income and ex-date workflows.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.dividends',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind dividend-event probes exist, but the current interface-first corporate-actions route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.capital_gains',
    label: 'Global capital gains',
    canonicalSchema: 'yfinance_corporate_actions',
    dataStoreTables: ['yfinance_corporate_actions'],
    queryActions: ['query_global_capital_gains', 'query_yfinance'],
    params: ['symbols', 'period', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-event-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.capital_gains',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo chart capital-gains events / yfinance capital_gains',
        normalizer: 'saveYfinanceCorporateActions',
        canonicalTable: 'yfinance_corporate_actions',
        reason:
            'Yahoo corporate-action rows carry capital-gains events suitable for fund and ETF distribution workflows.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.capital_gains',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'The Wind AIFinMarket provider contract in this runtime does not expose a stable dataset equivalent to global.capital_gains; keep this cell not-supported until an adapter, normalizer, canonical persistence, readback, and live evidence exist.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.stock_splits',
    label: 'Global stock splits',
    canonicalSchema: 'yfinance_corporate_actions',
    dataStoreTables: ['yfinance_corporate_actions'],
    queryActions: ['query_global_stock_splits', 'query_yfinance'],
    params: ['symbols', 'period', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-event-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.stock_splits',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo chart split events',
        normalizer: 'saveYfinanceCorporateActions',
        canonicalTable: 'yfinance_corporate_actions',
        reason:
            'Yahoo corporate-action rows carry split events suitable for global adjustment and split-watch workflows.',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.stock_splits',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind split-event probes exist, but the current interface-first corporate-actions route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'global.finance_news',
    label: 'Global finance news',
    canonicalSchema: 'yfinance_news',
    dataStoreTables: ['yfinance_news'],
    queryActions: ['query_global_finance_news', 'query_yfinance'],
    params: ['symbols', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'global-news-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'yfinance.global.finance_news',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.globalOnly,
        adapter: 'Yahoo finance news',
        normalizer: 'saveYfinanceNews',
        canonicalTable: 'yfinance_news',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.global.finance_news',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind financial-news probes exist, but the current interface-first global news route only executes Yahoo in this runtime; keep this cell not-supported until a Wind fetch/readback path is implemented.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.screening',
    label: 'Market screening snapshot',
    canonicalSchema: 'screening_result',
    dataStoreTables: ['market_screening_snapshot'],
    queryActions: ['query_market_screening'],
    params: ['symbols', 'indicators', 'timeframe', 'provider', 'providerMode'],
    freshnessPolicy: 'screening-cache-first-by-request',
    capabilities: [
      DataApiProviderCapability(
        id: 'tradingview.market.screening',
        provider: FinanceProvider.tradingview,
        status: DataApiCapabilityStatus.supported,
        adapter: 'TradingviewMarketProvider.readScan',
        normalizer: 'TradingviewMarketDataService.scan',
        canonicalTable: 'market_screening_snapshot',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'wind.market.screening',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp stock_data.search_stocks/fund_data.search_funds',
        normalizer: 'persistWindResult + normalizeScreeningSnapshot',
        canonicalTable: 'market_screening_snapshot',
        probeId: 'electron_wind_market_screening',
        reason:
            'Wind screening requires configured credential and quota; successful search_stocks/search_funds rows should be normalized to market_screening_snapshot when a WindMcp adapter is active.',
        priority: 3,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'market.margin_trading',
    label: 'Margin trading balance',
    canonicalSchema: 'margin_trading',
    dataStoreTables: ['margin_trading'],
    queryActions: ['query_margin_trading'],
    params: ['code', 'date', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'trade-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'akshare.market.margin_trading',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        canonicalTable: 'margin_trading',
        reason:
            'AkShare margin trading is currently implemented through the Fin Electron sidecar; shared mobile / FinAgent has local margin_trading readback but no native fetch adapter yet.',
      ),
      DataApiProviderCapability(
        id: 'szse.market.margin_trading',
        provider: FinanceProvider.szse,
        status: DataApiCapabilityStatus.supported,
        adapter: 'SSE queryMargin.do / SZSE ShowReport data tab2',
        normalizer: 'margin_trading canonical writer',
        canonicalTable: 'margin_trading',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'data.coverage',
    label: 'Local reusable data coverage',
    canonicalSchema: 'data_coverage',
    dataStoreTables: ['data_coverage'],
    queryActions: ['coverage', 'reusable_summary'],
    params: ['code', 'dataType', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'local-coverage-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.data.coverage',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'DataManager.coverage/reusableSummary',
        normalizer: 'ReusableDataStore coverage summaries',
        canonicalTable: 'data_coverage',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.data.coverage',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; local reusable coverage is owned by the runtime data store.',
      ),
      DataApiProviderCapability(
        id: 'akshare.data.coverage',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare supplies upstream market data; local reusable coverage is owned by the runtime data store.',
      ),
      DataApiProviderCapability(
        id: 'tdx.data.coverage',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; local reusable coverage is owned by the runtime data store.',
      ),
      DataApiProviderCapability(
        id: 'tushare.data.coverage',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Tushare supplies upstream market data; local reusable coverage is owned by the runtime data store.',
      ),
      DataApiProviderCapability(
        id: 'yahoo.data.coverage',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo supplies upstream global data; local reusable coverage is owned by the runtime data store.',
      ),
      DataApiProviderCapability(
        id: 'wind.data.coverage',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; local reusable coverage is owned by the runtime data store.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'data.store_stats',
    label: 'Local reusable data store stats',
    canonicalSchema: 'data_store_stats',
    dataStoreTables: [],
    queryActions: ['stats'],
    params: ['provider', 'providerMode'],
    freshnessPolicy: 'generated-store-stats-evidence-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.data.store_stats',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'MarketDataSupportService.stats',
        normalizer: 'ReusableDataStore.stats',
        canonicalTable: 'data_store_stats',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.data.store_stats',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; local reusable data store stats are generated by the runtime storage layer.',
      ),
      DataApiProviderCapability(
        id: 'akshare.data.store_stats',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare supplies upstream market data; local reusable data store stats are generated by the runtime storage layer.',
      ),
      DataApiProviderCapability(
        id: 'tdx.data.store_stats',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; local reusable data store stats are generated by the runtime storage layer.',
      ),
      DataApiProviderCapability(
        id: 'tushare.data.store_stats',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Tushare supplies upstream market data; local reusable data store stats are generated by the runtime storage layer.',
      ),
      DataApiProviderCapability(
        id: 'yahoo.data.store_stats',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo supplies upstream global data; local reusable data store stats are generated by the runtime storage layer.',
      ),
      DataApiProviderCapability(
        id: 'wind.data.store_stats',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; local reusable data store stats are generated by the runtime storage layer.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'provider.source_status',
    label: 'Provider source status',
    canonicalSchema: 'provider_source_status',
    dataStoreTables: [],
    queryActions: ['sources'],
    params: ['provider', 'providerMode'],
    freshnessPolicy: 'generated-source-status-evidence-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.provider.source_status',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'MarketDataSupportService.sources',
        normalizer: 'DataManager.getSourceStatus',
        canonicalTable: 'provider_source_status',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.provider.source_status',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; provider source status is generated by the local runtime routing layer.',
      ),
      DataApiProviderCapability(
        id: 'akshare.provider.source_status',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare supplies upstream market data; provider source status is generated by the local runtime routing layer.',
      ),
      DataApiProviderCapability(
        id: 'tdx.provider.source_status',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; provider source status is generated by the local runtime routing layer.',
      ),
      DataApiProviderCapability(
        id: 'tushare.provider.source_status',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Tushare supplies upstream market data; provider source status is generated by the local runtime routing layer.',
      ),
      DataApiProviderCapability(
        id: 'yahoo.provider.source_status',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo supplies upstream global data; provider source status is generated by the local runtime routing layer.',
      ),
      DataApiProviderCapability(
        id: 'wind.provider.source_status',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; provider source status is generated by the local runtime routing layer.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'data.health',
    label: 'Unified data health view',
    canonicalSchema: 'data_health_report',
    dataStoreTables: ['finance_data_health_report'],
    queryActions: ['data_health'],
    params: ['section', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'generated-health-evidence-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.data_health',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'MarketDataSupportService.dataHealth',
        normalizer: 'dataHealth payload assembly',
        canonicalTable: 'finance_data_health_report',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.data_health',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; unified data health is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'akshare.data_health',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare supplies upstream market data; unified data health is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'tdx.data_health',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; unified data health is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'tushare.data_health',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Tushare supplies upstream market data; unified data health is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'yfinance.data_health',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo/yfinance supplies upstream global data; unified data health is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'wind.data_health',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; unified data health is generated by the local mobile runtime evidence layer.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'data.runtime_probe',
    label: 'Controlled runtime probe status and execution',
    canonicalSchema: 'runtime_probe_status',
    dataStoreTables: ['runtime_probe_status'],
    queryActions: ['runtime_probe'],
    params: ['probeAction', 'probeMode', 'provider', 'providerMode'],
    freshnessPolicy: 'runtime-probe-evidence-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.data.runtime_probe',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'MarketRuntimeProbeService',
        normalizer: 'runtimeProbe payload assembly',
        canonicalTable: 'runtime_probe_status',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'eastmoney.data.runtime_probe',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; runtime probe control is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'akshare.data.runtime_probe',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare supplies upstream market data; runtime probe control is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'tdx.data.runtime_probe',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; runtime probe control is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'tushare.data.runtime_probe',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Tushare supplies upstream market data; runtime probe control is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'yfinance.data.runtime_probe',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo/yfinance supplies upstream global data; runtime probe control is generated by the local mobile runtime evidence layer.',
      ),
      DataApiProviderCapability(
        id: 'wind.data.runtime_probe',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; runtime probe control is generated by the local mobile runtime evidence layer.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'data.feed_status',
    label: 'Data Manager configured feed status',
    canonicalSchema: 'data_feed_config',
    dataStoreTables: [],
    queryActions: [],
    params: ['feedId', 'limit', 'provider', 'providerMode'],
    freshnessPolicy:
        'desktop Data Manager feed status surface; mobile has no configured-feed manager yet',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.data.feed_status',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile / FinAgent does not yet implement a configured Data Feed manager. Use mobile data_health and runtime_probe status until a real feed manager exists.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.data.feed_status',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'EastMoney supplies upstream market data; configured feed status is a local Data Manager runtime surface.',
      ),
      DataApiProviderCapability(
        id: 'akshare.data.feed_status',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare supplies upstream market data; configured feed status is a local Data Manager runtime surface.',
      ),
      DataApiProviderCapability(
        id: 'tdx.data.feed_status',
        provider: FinanceProvider.tdx,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'TDX supplies upstream market data; configured feed status is a local Data Manager runtime surface.',
      ),
      DataApiProviderCapability(
        id: 'tushare.data.feed_status',
        provider: FinanceProvider.tushare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Tushare supplies upstream market data; configured feed status is a local Data Manager runtime surface.',
      ),
      DataApiProviderCapability(
        id: 'yfinance.data.feed_status',
        provider: FinanceProvider.yfinance,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Yahoo/yfinance supplies upstream global data; configured feed status is a local Data Manager runtime surface.',
      ),
      DataApiProviderCapability(
        id: 'wind.data.feed_status',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind supplies upstream data; configured feed status is a local Data Manager runtime surface.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'bond.convertible_quote',
    label: 'Convertible bond quote snapshots',
    canonicalSchema: 'quote_snapshot',
    dataStoreTables: ['quote_snapshot'],
    queryActions: ['query_bond_quote', 'query_quote'],
    params: ['code', 'provider', 'providerMode', 'useCache'],
    freshnessPolicy:
        'intraday-cache-first for exchange convertible-bond quote snapshots',
    capabilities: [
      DataApiProviderCapability(
        id: 'tencent.bond.convertible_quote',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter: 'qt.gtimg.cn convertible bond quote symbols',
        normalizer: 'normalizeQuotes',
        canonicalTable: 'quote_snapshot',
        probeId: 'tencent.quote.convertible_bond_batch',
        priority: 1,
        reason:
            'Shared mobile Tencent convertible-bond quote route normalizes SH/SZ convertible-bond quote snapshots into quote_snapshot and reuses query_bond_quote.',
      ),
      DataApiProviderCapability(
        id: 'wind.bond.convertible_quote',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Current Wind bond market-data route is governed as bond.market_data over stock_company_info; no quote_snapshot normalizer/readback has been proven for convertible-bond live quotes.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.bond.convertible_quote',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No mobile EastMoney direct convertible-bond quote route has proven quote_snapshot readback.',
      ),
      DataApiProviderCapability(
        id: 'akshare.bond.convertible_quote',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile/FinAgent has no native AkShare sidecar route for convertible-bond quotes.',
      ),
      DataApiProviderCapability(
        id: 'sina.bond.convertible_quote',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No direct Sina convertible-bond quote route is registered with canonical quote_snapshot readback.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'bond.convertible_daily_kline',
    label: 'Convertible bond daily K-line bars',
    canonicalSchema: 'kline_daily',
    dataStoreTables: ['kline_daily'],
    queryActions: ['query_bond_kline', 'query_kline'],
    params: [
      'code',
      'start',
      'end',
      'adjust',
      'provider',
      'providerMode',
      'useCache',
    ],
    freshnessPolicy:
        'daily-cache-first for exchange convertible-bond unadjusted bars',
    capabilities: [
      DataApiProviderCapability(
        id: 'tencent.bond.convertible_daily_kline',
        provider: FinanceProvider.tencent,
        status: DataApiCapabilityStatus.supported,
        adapter:
            'proxy.finance.qq.com ifzqgtimg newfqkline convertible bond day',
        normalizer: 'normalizeKlineBars',
        canonicalTable: 'kline_daily',
        probeId: 'tencent.kline.convertible_bond_none',
        priority: 1,
        reason:
            'Shared mobile Tencent convertible-bond unadjusted daily K-line route normalizes SH/SZ convertible-bond bars into kline_daily and reuses query_bond_kline.',
      ),
      DataApiProviderCapability(
        id: 'wind.bond.convertible_daily_kline',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Current Wind bond route is governed as bond.market_data over stock_company_info; no kline_daily normalizer/readback has been proven for convertible-bond bars.',
      ),
      DataApiProviderCapability(
        id: 'eastmoney.bond.convertible_daily_kline',
        provider: FinanceProvider.eastmoneyDirect,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No mobile EastMoney direct convertible-bond daily K-line route has proven kline_daily readback.',
      ),
      DataApiProviderCapability(
        id: 'akshare.bond.convertible_daily_kline',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile/FinAgent has no native AkShare sidecar route for convertible-bond daily K-line.',
      ),
      DataApiProviderCapability(
        id: 'sina.bond.convertible_daily_kline',
        provider: FinanceProvider.sina,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'No direct Sina convertible-bond daily K-line route is registered with canonical kline_daily readback.',
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'bond.profile',
    label: 'Bond profile and issuer information',
    canonicalSchema: 'stock_company_info',
    dataStoreTables: ['stock_company_info', 'stock_list'],
    queryActions: ['query_bond_profile', 'query_company_info'],
    params: ['symbols', 'infoType', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'bond-profile-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.bond.profile',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp bond_data.get_bond_basicinfo/get_bond_issuer_info',
        normalizer: 'tryNormalizeWindCompanyInfoPayload',
        canonicalTable: 'stock_company_info',
        probeId: 'electron_wind_bond_basicinfo',
        reason:
            'Wind bond profile and issuer data requires configured credential and quota; cached rows are reusable through stock_company_info and stock_list bond identities.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'bond.market_data',
    label: 'Bond market and valuation data',
    canonicalSchema: 'stock_company_info',
    dataStoreTables: ['stock_company_info'],
    queryActions: ['query_bond_market_data', 'query_company_info'],
    params: ['symbols', 'infoType', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'bond-market-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.bond.market_data',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp bond_data.get_bond_market_data',
        normalizer: 'tryNormalizeWindCompanyInfoPayload',
        canonicalTable: 'stock_company_info',
        probeId: 'electron_wind_bond_market_data',
        reason:
            'Wind bond market and valuation data requires configured credential and quota; cached rows are reusable through stock_company_info.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'bond.issuer_financials',
    label: 'Bond issuer financial data',
    canonicalSchema: 'fundamental',
    dataStoreTables: ['fundamental'],
    queryActions: ['query_bond_issuer_financials', 'query_fundamental'],
    params: ['symbols', 'reportDate', 'limit', 'provider', 'providerMode'],
    freshnessPolicy: 'bond-issuer-financials-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'wind.bond.issuer_financials',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter: 'WindMcp bond_data.get_bond_financial_data',
        normalizer: 'tryNormalizeWindFundamentalPayload',
        canonicalTable: 'fundamental',
        probeId: 'electron_wind_bond_financial_data',
        reason:
            'Wind bond issuer financial data requires configured credential and quota; normalized issuer facts are reusable through fundamental.',
        priority: 1,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'technical.indicator_series',
    label: 'Technical indicator series',
    canonicalSchema: 'technical_indicator_series',
    dataStoreTables: ['technical_indicator_series'],
    queryActions: ['query_technical_indicator'],
    params: [
      'symbol',
      'indicator',
      'fieldName',
      'since',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'indicator-source-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.technical.indicator_series',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'DataProcess(action:"indicators") local indicator computation',
        normalizer: 'saveTechnicalIndicatorSeries',
        canonicalTable: 'technical_indicator_series',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'tradingview.technical.indicator_series',
        provider: FinanceProvider.tradingview,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Shared mobile has technical_indicator_series storage/readback; no native TradingView/TA provider ingestion route or live evidence is registered yet.',
      ),
      DataApiProviderCapability(
        id: 'wind.technical.indicator_series',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.credentialGated,
        adapter:
            'WindMcp stock_data.get_stock_technicals/index_data.get_index_technicals',
        normalizer: 'tryNormalizeWindTechnicalIndicatorPayload',
        canonicalTable: 'technical_indicator_series',
        probeId: 'electron_wind_stock_technicals',
        reason:
            'Wind stock and index technical tools require configured credential and quota; numeric technical fields are reusable through technical_indicator_series when a native Wind route is enabled.',
        priority: 2,
      ),
    ],
  ),
  DataApiInterfaceDefinition(
    id: 'stock.alpha_factors',
    label: 'Stock alpha factor snapshot',
    canonicalSchema: 'alpha_factor',
    dataStoreTables: ['alpha_factor'],
    queryActions: ['query_alpha_factors'],
    params: [
      'symbol',
      'factorName',
      'period',
      'limit',
      'since',
      'provider',
      'providerMode',
    ],
    freshnessPolicy: 'factor-source-date-cache-first',
    capabilities: [
      DataApiProviderCapability(
        id: 'local.stock.alpha_factors',
        provider: FinanceProvider.local,
        status: DataApiCapabilityStatus.supported,
        adapter: 'DataProcess(action:"factors") local Alpha158 computation',
        normalizer: 'saveAlphaFactors',
        canonicalTable: 'alpha_factor',
        priority: 1,
      ),
      DataApiProviderCapability(
        id: 'akshare.stock.alpha_factors',
        provider: FinanceProvider.akshare,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'AkShare alpha factors are implemented through the Fin Electron sidecar /alpha/factors route; shared mobile / FinAgent uses local DataProcess factor computation instead of a Python sidecar.',
      ),
      DataApiProviderCapability(
        id: 'wind.stock.alpha_factors',
        provider: FinanceProvider.wind,
        status: DataApiCapabilityStatus.notSupported,
        reason:
            'Wind technical/risk tools are governed by technical.indicator_series and stock.risk_metrics until a stable alpha-factor schema is proven.',
      ),
    ],
  ),
];
