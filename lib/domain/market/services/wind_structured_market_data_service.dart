import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/tool_context.dart';
import '../../../agent/tools/wind_mcp_tool/wind_mcp_tool.dart';
import '../../../shared/api_config.dart';
import '../repositories/wind_market_data_repository.dart';

typedef WindStructuredActionInvoker =
    Future<void> Function(
      WindStructuredActionSpec spec,
      ToolContext context,
      String windcode,
      Map<String, dynamic> input,
    );

class WindStructuredActionSpec {
  final String action;
  final String interfaceId;
  final String capabilityId;
  final String canonicalSchema;
  final String canonicalTable;
  final String server;
  final String tool;
  final String family;
  final String? defaultInfoType;

  const WindStructuredActionSpec({
    required this.action,
    required this.interfaceId,
    required this.capabilityId,
    required this.canonicalSchema,
    required this.canonicalTable,
    required this.server,
    required this.tool,
    required this.family,
    this.defaultInfoType,
  });
}

class WindStructuredMarketDataService {
  final WindMarketDataRepository _repository;
  final WindStructuredActionInvoker _invokeWind;

  WindStructuredMarketDataService({
    DataManager? dataManager,
    WindMarketDataRepository? repository,
    WindStructuredActionInvoker? invokeWind,
  }) : _repository =
           repository ?? WindMarketDataRepository(dataManager ?? DataManager()),
       _invokeWind = invokeWind ?? _callWindStructuredTool;

  Future<Map<String, dynamic>> run(
    String action,
    String code,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final spec = _specs[action];
    if (spec == null) {
      throw ArgumentError('Unsupported Wind structured action: $action');
    }
    _enforceWindProviderOnly(action, input['provider'] as String?);
    final windcode = _normalizeWindcode(spec.family, code);
    final cacheMode = _normalizeCacheMode(input);
    final limit = _limit(input);
    final cachedRows = _readStructuredRows(spec, code, input, context, limit);
    if (cacheMode != _WindStructuredCacheMode.liveOnly &&
        cachedRows.isNotEmpty) {
      return _buildResult(
        spec,
        code: code,
        windcode: windcode,
        rows: cachedRows,
        provider: 'local',
        providerId: 'local',
        capabilityId: 'local.cache',
        cacheStatus: 'cache-hit',
        cacheMode: cacheMode,
        cacheDecision: spec.canonicalTable == 'fundamental'
            ? 'cacheFirst read reusable local Wind fundamental rows before provider routing; cache reader returned governed canonical rows'
            : 'cacheFirst read reusable local Wind company-info rows before provider routing; cache reader returned governed canonical rows',
        source: 'local ${spec.canonicalTable}',
      );
    }
    if (cacheMode == _WindStructuredCacheMode.cacheOnly) {
      throw StateError(
        '${spec.interfaceId} cache-only lookup missed; no reusable canonical rows matched $code.',
      );
    }
    await _invokeWind(spec, context, windcode, input);
    final rows = _readStructuredRows(spec, code, input, context, limit);
    if (rows.isEmpty) {
      throw StateError(
        'Wind ${spec.interfaceId} call finished but no canonical ${spec.canonicalTable} rows were readable for $code. Check persistence/normalizer contract.',
      );
    }
    return _buildResult(
      spec,
      code: code,
      windcode: windcode,
      rows: rows,
      provider: 'wind',
      providerId: 'wind',
      capabilityId: spec.capabilityId,
      cacheStatus: 'provider-hit',
      cacheMode: cacheMode,
      cacheDecision: cacheMode == _WindStructuredCacheMode.liveOnly
          ? 'liveOnly bypassed reusable local data and refreshed through the governed Wind provider path'
          : 'cacheFirst checked reusable local data first; no matching canonical rows were found so the governed Wind provider path refreshed and persisted the requirement',
      source: 'WindMcp ${spec.server}.${spec.tool}',
    );
  }

  List<Map<String, dynamic>> _readStructuredRows(
    WindStructuredActionSpec spec,
    String code,
    Map<String, dynamic> input,
    ToolContext context,
    int limit,
  ) {
    if (spec.canonicalTable == 'fundamental') {
      return _repository.queryFundamental(
        context,
        code,
        reportDate: input['reportDate'] as String? ?? input['date'] as String?,
        source: 'Wind',
        limit: limit,
      );
    }
    final infoType =
        input['infoType'] as String? ??
        input['type'] as String? ??
        input['info_type'] as String? ??
        spec.defaultInfoType;
    return _repository
        .queryCompanyInfo(context, code, infoType: infoType, limit: limit)
        .where((row) => row['source']?.toString() == 'Wind')
        .toList();
  }

  Map<String, dynamic> _buildResult(
    WindStructuredActionSpec spec, {
    required String code,
    required String windcode,
    required List<Map<String, dynamic>> rows,
    required String provider,
    required String providerId,
    required String capabilityId,
    required String cacheStatus,
    required _WindStructuredCacheMode cacheMode,
    required String cacheDecision,
    required String source,
  }) {
    final sourceDataTime = spec.canonicalTable == 'fundamental'
        ? _latestValue(rows, const ['report_date', 'fetched_at'])
        : _latestValue(rows, const ['updated_at']);
    final fetchedAt = spec.canonicalTable == 'fundamental'
        ? _latestValue(rows, const ['fetched_at', 'report_date'])
        : _latestValue(rows, const ['updated_at']);
    return {
      'action': spec.action,
      'symbol': code,
      'windcode': windcode,
      'interfaceId': spec.interfaceId,
      'provider': provider,
      'providerId': providerId,
      'capabilityId': capabilityId,
      'cacheStatus': cacheStatus,
      'cacheMode': cacheMode.value,
      'cachePolicyMode': cacheMode.policyMode,
      'cacheDecision': cacheDecision,
      'canonicalSchema': spec.canonicalSchema,
      'canonicalTable': spec.canonicalTable,
      'source': source,
      'count': rows.length,
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'data': rows,
    };
  }

  int _limit(Map<String, dynamic> input) {
    final raw = input['limit'];
    if (raw is num) return raw.toInt().clamp(1, 100);
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed.clamp(1, 100);
    }
    return 20;
  }

  String? _latestValue(List<Map<String, dynamic>> rows, List<String> keys) {
    for (final key in keys) {
      String? latest;
      for (final row in rows) {
        final value = row[key];
        if (value == null) continue;
        final text = '$value'.trim();
        if (text.isEmpty) continue;
        if (latest == null || text.compareTo(latest) > 0) {
          latest = text;
        }
      }
      if (latest != null) return latest;
    }
    return null;
  }
}

enum _WindStructuredCacheMode {
  cacheFirst('cache-first', 'cacheFirst'),
  liveOnly('live-only', 'liveOnly'),
  cacheOnly('cache-only', 'cacheOnly');

  final String value;
  final String policyMode;

  const _WindStructuredCacheMode(this.value, this.policyMode);
}

const Map<String, WindStructuredActionSpec> _specs = {
  'stock_risk_metrics': WindStructuredActionSpec(
    action: 'stock_risk_metrics',
    interfaceId: 'stock.risk_metrics',
    capabilityId: 'wind.stock.risk_metrics',
    canonicalSchema: 'stock_company_info',
    canonicalTable: 'stock_company_info',
    server: 'stock_data',
    tool: 'get_risk_metrics',
    family: 'stock',
    defaultInfoType: 'get_risk_metrics',
  ),
  'fund_company_info': WindStructuredActionSpec(
    action: 'fund_company_info',
    interfaceId: 'fund.company_info',
    capabilityId: 'wind.fund.company_info',
    canonicalSchema: 'stock_company_info',
    canonicalTable: 'stock_company_info',
    server: 'fund_data',
    tool: 'get_fund_company_info',
    family: 'fund',
    defaultInfoType: 'get_fund_company_info',
  ),
  'fund_investor_holders': WindStructuredActionSpec(
    action: 'fund_investor_holders',
    interfaceId: 'fund.investor_holders',
    capabilityId: 'wind.fund.investor_holders',
    canonicalSchema: 'stock_company_info',
    canonicalTable: 'stock_company_info',
    server: 'fund_data',
    tool: 'get_fund_holders',
    family: 'fund',
    defaultInfoType: 'get_fund_holders',
  ),
  'fund_financials': WindStructuredActionSpec(
    action: 'fund_financials',
    interfaceId: 'fund.financials',
    capabilityId: 'wind.fund.financials',
    canonicalSchema: 'fundamental',
    canonicalTable: 'fundamental',
    server: 'fund_data',
    tool: 'get_fund_financials',
    family: 'fund',
  ),
  'index_fundamentals': WindStructuredActionSpec(
    action: 'index_fundamentals',
    interfaceId: 'index.fundamentals',
    capabilityId: 'wind.index.fundamentals',
    canonicalSchema: 'fundamental',
    canonicalTable: 'fundamental',
    server: 'index_data',
    tool: 'get_index_fundamentals',
    family: 'index',
  ),
  'index_profile': WindStructuredActionSpec(
    action: 'index_profile',
    interfaceId: 'index.profile',
    capabilityId: 'wind.index.profile',
    canonicalSchema: 'stock_company_info',
    canonicalTable: 'stock_company_info',
    server: 'index_data',
    tool: 'get_index_basicinfo',
    family: 'index',
    defaultInfoType: 'get_index_basicinfo',
  ),
  'bond_profile': WindStructuredActionSpec(
    action: 'bond_profile',
    interfaceId: 'bond.profile',
    capabilityId: 'wind.bond.profile',
    canonicalSchema: 'stock_company_info',
    canonicalTable: 'stock_company_info',
    server: 'bond_data',
    tool: 'get_bond_basicinfo',
    family: 'bond',
    defaultInfoType: 'get_bond_basicinfo',
  ),
  'bond_market_data': WindStructuredActionSpec(
    action: 'bond_market_data',
    interfaceId: 'bond.market_data',
    capabilityId: 'wind.bond.market_data',
    canonicalSchema: 'stock_company_info',
    canonicalTable: 'stock_company_info',
    server: 'bond_data',
    tool: 'get_bond_market_data',
    family: 'bond',
    defaultInfoType: 'get_bond_market_data',
  ),
  'bond_issuer_financials': WindStructuredActionSpec(
    action: 'bond_issuer_financials',
    interfaceId: 'bond.issuer_financials',
    capabilityId: 'wind.bond.issuer_financials',
    canonicalSchema: 'fundamental',
    canonicalTable: 'fundamental',
    server: 'bond_data',
    tool: 'get_bond_financial_data',
    family: 'bond',
  ),
};

Future<void> _callWindStructuredTool(
  WindStructuredActionSpec spec,
  ToolContext context,
  String windcode,
  Map<String, dynamic> input,
) async {
  final apiConfig = ApiConfigStore();
  await apiConfig.load();
  final tool = WindMcpTool(basePath: context.basePath, apiConfig: apiConfig);
  final args = <String, dynamic>{'windcode': windcode};
  if (input['query'] is String &&
      (input['query'] as String).trim().isNotEmpty) {
    args['query'] = (input['query'] as String).trim();
  }
  if (input['question'] is String &&
      (input['question'] as String).trim().isNotEmpty) {
    args['question'] = (input['question'] as String).trim();
  }
  final result = await tool.call('wind-structured:${spec.action}', {
    'action': 'call',
    'server': spec.server,
    'tool': spec.tool,
    'arguments': args,
  }, context);
  if (result.isError) {
    throw StateError(result.content);
  }
}

void _enforceWindProviderOnly(String action, String? provider) {
  if (provider == null) return;
  final value = provider.trim().toLowerCase();
  if (value.isEmpty || value == 'wind') return;
  throw ArgumentError(
    '$action only supports provider:"wind" in the current governed workflow. Remove the provider override or set provider:"wind".',
  );
}

_WindStructuredCacheMode _normalizeCacheMode(Map<String, dynamic> input) {
  final raw =
      input['cacheMode'] ?? input['cachePolicy'] ?? input['readPreference'];
  return switch (raw?.toString()) {
    'liveOnly' || 'live-only' => _WindStructuredCacheMode.liveOnly,
    'cacheOnly' || 'cache-only' => _WindStructuredCacheMode.cacheOnly,
    _ => _WindStructuredCacheMode.cacheFirst,
  };
}

String _normalizeWindcode(String family, String raw) {
  final value = raw.trim().toUpperCase();
  if (value.isEmpty) {
    throw ArgumentError('symbol/code required for Wind structured workflow');
  }
  if (value.contains('.')) return value;
  switch (family) {
    case 'fund':
      return '$value.OF';
    case 'index':
      return value.startsWith('399') ? '$value.SZ' : '$value.SH';
    case 'stock':
      return value.startsWith('6') || value.startsWith('9')
          ? '$value.SH'
          : '$value.SZ';
    case 'bond':
      return value.startsWith('0') ||
              value.startsWith('1') ||
              value.startsWith('2')
          ? '$value.SH'
          : '$value.SZ';
    default:
      return value;
  }
}
