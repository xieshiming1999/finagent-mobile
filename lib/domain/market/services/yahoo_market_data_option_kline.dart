import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/tool_context.dart';
import '../providers/data_api_interface_contract.dart';
import '../providers/data_api_interface_router.dart';
import '../repositories/local_market_data_repository.dart';
import 'cache_policy.dart';
import 'yahoo_market_data_market_fetch.dart';

class YahooMarketDataOptionKlineService {
  final DataApiInterfaceRouter _router;
  final LocalMarketDataRepository _localRepository;
  final YahooMarketDataMarketFetch _market;

  const YahooMarketDataOptionKlineService({
    required DataApiInterfaceRouter router,
    required LocalMarketDataRepository localRepository,
    required YahooMarketDataMarketFetch market,
  }) : _router = router,
       _localRepository = localRepository,
       _market = market;

  Future<Map<String, dynamic>> optionDailyKline(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context, {
    required DataApiProviderConstraint Function(Map<String, dynamic>)
    constraintFromInput,
    required bool Function(Map<String, dynamic>) isUsableResult,
    required Map<String, dynamic> Function(Object?) yahooGlobalProvenance,
  }) async {
    final normalizedInput = {
      ...input,
      '_queryAction': 'query_option_daily_kline',
    };
    final result = await _router.runCapability<Map<String, dynamic>>(
      interfaceId: 'option.daily_kline',
      constraint: constraintFromInput(normalizedInput),
      cachePolicy: CachePolicy.fromInput(normalizedInput),
      readCache: () async {
        final cached = _readOptionDailyKlineCache(
          context,
          symbol,
          normalizedInput,
        );
        return isUsableResult(cached)
            ? DataApiLocalCacheResult(data: cached)
            : null;
      },
      call: (capability) async {
        if (capability.provider != FinanceProvider.yfinance) return null;
        return DataApiProviderExecution(
          data: await _market.history(symbol, normalizedInput, context),
          source: 'yahoo',
          providerName: 'Yahoo Finance',
        );
      },
      isUsable: isUsableResult,
      emptyMessage: 'returned empty option_daily_kline rows',
      failureMessage: 'All option.daily_kline providers failed',
    );
    return {
      ...result.data,
      'action': 'option_daily_kline',
      'source': result.source,
      'interfaceId': result.provenance.interfaceId,
      'capabilityId': result.provenance.capabilityId,
      'provider': result.provenance.provider,
      'providerId': 'yahoo',
      ...yahooGlobalProvenance(result.data),
      'canonicalSchema': result.provenance.canonicalSchema,
      'canonicalTable': result.provenance.canonicalTable,
      'cacheStatus': result.provenance.cacheStatus,
      'cachePolicyMode': result.provenance.cachePolicyMode,
      'cacheDecision': result.provenance.cacheDecision,
      ...result.provenance.routePolicyJson(),
      'provenance': {...result.provenance.toJson(), 'providerId': 'yahoo'},
    };
  }

  Map<String, dynamic> _readOptionDailyKlineCache(
    ToolContext context,
    String symbol,
    Map<String, dynamic> input,
  ) {
    final rows = _localRepository.queryKline(
      context,
      symbol,
      startDate: input['startDate'] as String? ?? '',
      endDate: input['endDate'] as String? ?? '',
      adjust: 'none',
      limit: (input['limit'] as num?)?.toInt(),
    );
    return {
      'action': 'query_option_daily_kline',
      'symbol': symbol.toUpperCase(),
      'period': input['period'] ?? input['range'] ?? '6mo',
      'source': 'local kline_daily',
      'count': rows.length,
      'data': rows.map((row) => row.toJson()).toList(),
      'ingestion': {
        'persisted': rows.isNotEmpty,
        'tables': ['kline_daily'],
      },
    };
  }
}
