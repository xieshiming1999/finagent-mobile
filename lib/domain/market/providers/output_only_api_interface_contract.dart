class OutputOnlyApiInterfaceContract {
  const OutputOnlyApiInterfaceContract();

  List<OutputOnlyApiInterface> get interfaces => _interfaces;

  OutputOnlyApiInterface byId(String id) => _interfaces.firstWhere(
    (item) => item.id == id,
    orElse: () => throw ArgumentError('Unknown output-only interface: $id'),
  );

  List<String> validate() {
    final problems = <String>[];
    final ids = <String>{};
    final capabilityIds = <String>{};
    for (final item in _interfaces) {
      if (!ids.add(item.id)) problems.add('duplicate interface id: ${item.id}');
      if (item.persistencePolicy != 'output-only') {
        problems.add('${item.id}: persistencePolicy must be output-only');
      }
      if (item.unknownSchemaPolicy != 'reject-normal-workflow') {
        problems.add('${item.id}: unknown schema must reject normal workflow');
      }
      for (final capability in item.capabilities) {
        if (!capabilityIds.add(capability.id)) {
          problems.add('duplicate capability id: ${capability.id}');
        }
        if (capability.interfaceId != item.id) {
          problems.add('${capability.id}: capability interface mismatch');
        }
        if (capability.schemaId != item.schemaId) {
          problems.add('${capability.id}: capability schema mismatch');
        }
        if (capability.persistencePolicy != 'output-only') {
          problems.add('${capability.id}: capability must be output-only');
        }
      }
    }
    return problems;
  }
}

class OutputOnlyApiInterface {
  final String id;
  final String label;
  final String schemaId;
  final String schemaVersion;
  final String persistencePolicy;
  final String unknownSchemaPolicy;
  final List<OutputOnlyApiCapability> capabilities;

  const OutputOnlyApiInterface({
    required this.id,
    required this.label,
    required this.schemaId,
    required this.schemaVersion,
    required this.persistencePolicy,
    required this.unknownSchemaPolicy,
    required this.capabilities,
  });
}

class OutputOnlyApiCapability {
  final String id;
  final String interfaceId;
  final String provider;
  final String status;
  final int priority;
  final String schemaId;
  final String adapter;
  final String normalizer;
  final String persistencePolicy;

  const OutputOnlyApiCapability({
    required this.id,
    required this.interfaceId,
    required this.provider,
    required this.status,
    required this.priority,
    required this.schemaId,
    required this.adapter,
    required this.normalizer,
    required this.persistencePolicy,
  });
}

class OutputOnlyApiKnowledgeRecord {
  final String apiId;
  final String interfaceId;
  final String capabilityId;
  final String runtime;
  final String provider;
  final String endpointOrAction;
  final String schemaId;
  final String schemaVersion;
  final String persistencePolicy;
  final List<String> requiredParameters;
  final List<String> optionalParameters;
  final List<String> topLevelFields;
  final List<String> rowFields;
  final String emptyResultMeaning;
  final String retryPolicy;

  const OutputOnlyApiKnowledgeRecord({
    required this.apiId,
    required this.interfaceId,
    required this.capabilityId,
    required this.runtime,
    required this.provider,
    required this.endpointOrAction,
    required this.schemaId,
    required this.schemaVersion,
    required this.persistencePolicy,
    required this.requiredParameters,
    required this.optionalParameters,
    required this.topLevelFields,
    required this.rowFields,
    required this.emptyResultMeaning,
    required this.retryPolicy,
  });
}

const outputOnlyApiKnowledgeRecords = <OutputOnlyApiKnowledgeRecord>[
  OutputOnlyApiKnowledgeRecord(
    apiId: 'sina.provider_diagnostic',
    interfaceId: 'provider.diagnostic',
    capabilityId: 'sina.provider.diagnostic',
    runtime: 'shared_mobile_finagent',
    provider: 'sina',
    endpointOrAction: 'Sina finance provider diagnostic',
    schemaId: 'provider_diagnostic_result',
    schemaVersion: '2026-06-18',
    persistencePolicy: 'output-only',
    requiredParameters: ['endpoint'],
    optionalParameters: ['code', 'params'],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: ['sampleRows', 'sampleColumns'],
    emptyResultMeaning:
        'Provider diagnostic is intentionally not executable as a normal mobile workflow.',
    retryPolicy:
        'Mobile does not expose generic Sina provider diagnostics; use governed MarketData interfaces, runtime_probe, or explicit WebFetch diagnostics outside normal data workflow.',
  ),
  OutputOnlyApiKnowledgeRecord(
    apiId: 'tencent.provider_diagnostic',
    interfaceId: 'provider.diagnostic',
    capabilityId: 'tencent.provider.diagnostic',
    runtime: 'shared_mobile_finagent',
    provider: 'tencent',
    endpointOrAction: 'Tencent finance provider diagnostic',
    schemaId: 'provider_diagnostic_result',
    schemaVersion: '2026-06-18',
    persistencePolicy: 'output-only',
    requiredParameters: ['endpoint'],
    optionalParameters: ['code', 'params'],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: ['sampleRows', 'sampleColumns'],
    emptyResultMeaning:
        'Provider diagnostic is intentionally not executable as a normal mobile workflow.',
    retryPolicy:
        'Mobile does not expose generic Tencent provider diagnostics; use governed MarketData interfaces, runtime_probe, or explicit WebFetch diagnostics outside normal data workflow.',
  ),
  OutputOnlyApiKnowledgeRecord(
    apiId: 'akshare.sina.reference_dataset',
    interfaceId: 'provider.reference_dataset',
    capabilityId: 'akshare.sina.reference_dataset',
    runtime: 'shared_mobile_finagent',
    provider: 'akshare',
    endpointOrAction: 'akshare/*_sina',
    schemaId: 'provider_reference_dataset_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    requiredParameters: ['functionName'],
    optionalParameters: ['params', 'limit'],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: ['functionName', 'rowCount', 'sampleColumns', 'sampleRows'],
    emptyResultMeaning:
        'Valid AkShare/Sina reference request with no rows, not a canonical cache miss.',
    retryPolicy:
        'Use only as bounded known-schema evidence; promote only after a requirement-level interface, normalizer, storage, readback, and tests exist.',
  ),
  OutputOnlyApiKnowledgeRecord(
    apiId: 'sina.intraday_ohlcv_bars',
    interfaceId: 'market.intraday_ohlcv_bars',
    capabilityId: 'sina.market.intraday_ohlcv_bars',
    runtime: 'shared_mobile_finagent',
    provider: 'sina',
    endpointOrAction: 'CN_MarketData.getKLineData?scale=5',
    schemaId: 'intraday_ohlcv_bar_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    requiredParameters: ['symbol'],
    optionalParameters: ['scale', 'datalen'],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: ['time', 'open', 'high', 'low', 'close', 'volume'],
    emptyResultMeaning:
        'Valid Sina intraday request with no bars, not a canonical cache miss.',
    retryPolicy:
        'Normal workflow uses governed market.intraday_ohlcv_bars via intraday_ohlcv_bars refresh and query_intraday_ohlcv_bars readback; use this envelope only for bounded diagnostics.',
  ),
  OutputOnlyApiKnowledgeRecord(
    apiId: 'sina.stock_transaction_count',
    interfaceId: 'stock.transaction_count',
    capabilityId: 'sina.stock.transaction_count',
    runtime: 'shared_mobile_finagent',
    provider: 'sina',
    endpointOrAction: 'CN_Bill.GetBillListCount',
    schemaId: 'stock_transaction_count_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    requiredParameters: ['symbol'],
    optionalParameters: ['date', 'pageSize'],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: ['symbol', 'date', 'count', 'pageSize', 'estimatedPages'],
    emptyResultMeaning:
        'Valid Sina transaction-count request with no count, not a transactions cache miss.',
    retryPolicy:
        'Use only as bounded pagination evidence for stock.transactions; do not persist as transaction rows.',
  ),
  OutputOnlyApiKnowledgeRecord(
    apiId: 'sina.fund_dividend_factor',
    interfaceId: 'fund.dividend_factor',
    capabilityId: 'sina.fund.dividend_factor',
    runtime: 'shared_mobile_finagent',
    provider: 'sina',
    endpointOrAction: 'FundPage fundEtfFactorInfoService',
    schemaId: 'fund_dividend_factor_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    requiredParameters: ['symbol'],
    optionalParameters: ['limit'],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: ['date', 'dividend', 'factor'],
    emptyResultMeaning:
        'Valid Sina ETF dividend/factor request with no rows, not a canonical cache miss.',
    retryPolicy:
        'Normal workflow uses governed fund.dividend_factor via fund_dividend_factor refresh and query_fund_dividend_factor readback; use this envelope only for bounded diagnostics.',
  ),
  OutputOnlyApiKnowledgeRecord(
    apiId: 'sina.stock_classify_nodes',
    interfaceId: 'market.classification_nodes',
    capabilityId: 'sina.market.classification_nodes',
    runtime: 'shared_mobile_finagent',
    provider: 'sina',
    endpointOrAction: 'Market_Center.getHQNodes',
    schemaId: 'market_classification_node_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    requiredParameters: [],
    optionalParameters: [],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: ['name', 'code', 'parent'],
    emptyResultMeaning:
        'Valid Sina classification tree request with no nodes, not a sector cache miss.',
    retryPolicy:
        'Use only as bounded classification evidence; broad per-node expansion must be a deliberate batch workflow.',
  ),
  OutputOnlyApiKnowledgeRecord(
    apiId: 'sina.stock_esg_rate_page',
    interfaceId: 'stock.esg_rating_multi_agency',
    capabilityId: 'sina.stock.esg_rating_multi_agency',
    runtime: 'shared_mobile_finagent',
    provider: 'sina',
    endpointOrAction: 'EsgService.getEsgStocks?page=1&num=<bounded>',
    schemaId: 'stock_esg_rating_multi_agency_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    requiredParameters: [],
    optionalParameters: ['page', 'limit'],
    topLevelFields: [
      'ok',
      'action',
      'interfaceId',
      'schemaId',
      'data',
      'provenance',
    ],
    rowFields: [
      'symbol',
      'market',
      'agency',
      'agencyName',
      'esgScore',
      'esgDate',
      'remark',
    ],
    emptyResultMeaning:
        'Valid Sina ESG rating page with no rating rows, not a fundamental cache miss.',
    retryPolicy:
        'Use bounded pages for evidence; full ESG collection is a batch job and should not be a normal lightweight probe.',
  ),
];

const _interfaces = <OutputOnlyApiInterface>[
  OutputOnlyApiInterface(
    id: 'market.optimize_params',
    label: 'Strategy parameter optimization',
    schemaId: 'strategy_parameter_optimization_result',
    schemaVersion: '2026-06-27',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'local.market.optimize_params',
        interfaceId: 'market.optimize_params',
        provider: 'local',
        status: 'normalized-output-only',
        priority: 1,
        schemaId: 'strategy_parameter_optimization_result',
        adapter: 'MarketData(action:"optimize_params")',
        normalizer:
            'code-owned backtest optimizer over governed K-line evidence; returns bounded bestParams/bestResult/results and overfit note',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'provider.diagnostic',
    label: 'Provider diagnostic',
    schemaId: 'provider_diagnostic_result',
    schemaVersion: '2026-06-18',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'sina.provider.diagnostic',
        interfaceId: 'provider.diagnostic',
        provider: 'sina',
        status: 'not-supported',
        priority: 1,
        schemaId: 'provider_diagnostic_result',
        adapter: 'Sina finance provider diagnostic',
        normalizer:
            'mobile normal workflow uses governed MarketData interfaces or runtime_probe; no generic raw diagnostic executor',
        persistencePolicy: 'output-only',
      ),
      OutputOnlyApiCapability(
        id: 'tencent.provider.diagnostic',
        interfaceId: 'provider.diagnostic',
        provider: 'tencent',
        status: 'not-supported',
        priority: 2,
        schemaId: 'provider_diagnostic_result',
        adapter: 'Tencent finance provider diagnostic',
        normalizer:
            'mobile normal workflow uses governed MarketData interfaces or runtime_probe; no generic raw diagnostic executor',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'provider.reference_dataset',
    label: 'Provider reference dataset',
    schemaId: 'provider_reference_dataset_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'akshare.sina.reference_dataset',
        interfaceId: 'provider.reference_dataset',
        provider: 'akshare',
        status: 'not-supported',
        priority: 1,
        schemaId: 'provider_reference_dataset_result',
        adapter: 'akshare *_sina reference functions',
        normalizer: 'desktop Python sidecar reference envelope only',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'market.intraday_ohlcv_bars',
    label: 'Provider intraday OHLCV bars',
    schemaId: 'intraday_ohlcv_bar_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'sina.market.intraday_ohlcv_bars',
        interfaceId: 'market.intraday_ohlcv_bars',
        provider: 'sina',
        status: 'supported',
        priority: 1,
        schemaId: 'intraday_ohlcv_bar_result',
        adapter: 'CN_MarketData.getKLineData scale=5',
        normalizer: 'normalizeSinaIntradayOhlcvBars',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'stock.transaction_count',
    label: 'Stock transaction count',
    schemaId: 'stock_transaction_count_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'sina.stock.transaction_count',
        interfaceId: 'stock.transaction_count',
        provider: 'sina',
        status: 'supported',
        priority: 1,
        schemaId: 'stock_transaction_count_result',
        adapter: 'CN_Bill.GetBillListCount',
        normalizer: 'normalizeSinaStockTransactionCount',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'fund.dividend_factor',
    label: 'Fund dividend and factor rows',
    schemaId: 'fund_dividend_factor_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'sina.fund.dividend_factor',
        interfaceId: 'fund.dividend_factor',
        provider: 'sina',
        status: 'supported',
        priority: 1,
        schemaId: 'fund_dividend_factor_result',
        adapter: 'FundPage fundEtfFactorInfoService tab=fundFactor',
        normalizer: 'normalizeSinaFundDividendFactor',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'fund.etf_daily_ohlcv_bars',
    label: 'ETF daily OHLCV bars',
    schemaId: 'fund_etf_daily_ohlcv_bar_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'sina.fund.etf_daily_ohlcv_bars',
        interfaceId: 'fund.etf_daily_ohlcv_bars',
        provider: 'sina',
        status: 'not-supported',
        priority: 1,
        schemaId: 'fund_etf_daily_ohlcv_bar_result',
        adapter: 'realstock/company/{symbol}/hisdata_klc2/klc_kl.js',
        normalizer: 'native decoder not implemented',
        persistencePolicy: 'output-only',
      ),
      OutputOnlyApiCapability(
        id: 'akshare.sina.fund.etf_daily_ohlcv_bars',
        interfaceId: 'fund.etf_daily_ohlcv_bars',
        provider: 'akshare',
        status: 'not-supported',
        priority: 2,
        schemaId: 'fund_etf_daily_ohlcv_bar_result',
        adapter: 'fund_etf_hist_sina',
        normalizer: 'desktop Python sidecar decoder only',
        persistencePolicy: 'output-only',
      ),
      OutputOnlyApiCapability(
        id: 'tencent.fund.etf_daily_ohlcv_bars',
        interfaceId: 'fund.etf_daily_ohlcv_bars',
        provider: 'tencent',
        status: 'not-supported',
        priority: 3,
        schemaId: 'fund_etf_daily_ohlcv_bar_result',
        adapter: 'newfqkline ETF day/qfq/hfq',
        normalizer:
            'Electron direct Tencent output-only route only; mobile native adapter not implemented',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'market.classification_nodes',
    label: 'Market classification node tree',
    schemaId: 'market_classification_node_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'sina.market.classification_nodes',
        interfaceId: 'market.classification_nodes',
        provider: 'sina',
        status: 'supported',
        priority: 1,
        schemaId: 'market_classification_node_result',
        adapter: 'Market_Center.getHQNodes',
        normalizer: 'normalizeSinaClassificationNodes',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
  OutputOnlyApiInterface(
    id: 'stock.esg_rating_multi_agency',
    label: 'Stock ESG multi-agency rating page',
    schemaId: 'stock_esg_rating_multi_agency_result',
    schemaVersion: '2026-06-23',
    persistencePolicy: 'output-only',
    unknownSchemaPolicy: 'reject-normal-workflow',
    capabilities: [
      OutputOnlyApiCapability(
        id: 'sina.stock.esg_rating_multi_agency',
        interfaceId: 'stock.esg_rating_multi_agency',
        provider: 'sina',
        status: 'supported',
        priority: 1,
        schemaId: 'stock_esg_rating_multi_agency_result',
        adapter: 'EsgService.getEsgStocks bounded page',
        normalizer: 'normalizeSinaEsgRatePage',
        persistencePolicy: 'output-only',
      ),
    ],
  ),
];
