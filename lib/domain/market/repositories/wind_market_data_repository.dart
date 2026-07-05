import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';

class WindMarketDataRepository {
  ReusableDataStore? _store;
  String? _storeBasePath;
  final DataManager _dataManager;

  WindMarketDataRepository(this._dataManager);

  ReusableDataStore? _storeForContext(ToolContext context) {
    final basePath = context.basePath;
    if (basePath.isEmpty) return null;
    if (_store == null || _storeBasePath != basePath) {
      _storeBasePath = basePath;
      _store = ReusableDataStore(basePath)..cleanup();
    }
    return _store;
  }

  List<Map<String, dynamic>> queryDocuments(
    ToolContext context, {
    String? query,
    String? tool,
    String? entityCode,
    String? source,
    int limit = 50,
  }) {
    return _storeForContext(context)?.queryWindDocuments(
          query: query,
          tool: tool,
          entityCode: entityCode,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryWindDocuments(
          query: query,
          tool: tool,
          entityCode: entityCode,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryEconomicSeries(
    ToolContext context, {
    String? metricQuery,
    String? source,
    int limit = 100,
  }) {
    return _storeForContext(context)?.queryWindEconomicSeries(
          metricQuery: metricQuery,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryWindEconomicSeries(
          metricQuery: metricQuery,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryAnalyticsResults(
    ToolContext context, {
    String? question,
    String? source,
    int limit = 100,
  }) {
    return _storeForContext(context)?.queryWindAnalyticsResults(
          question: question,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryWindAnalyticsResults(
          question: question,
          source: source,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryFundPerformanceMetrics(
    ToolContext context, {
    String? code,
    String? provider,
    String? metricDate,
    int limit = 100,
  }) {
    return _storeForContext(context)?.queryFundPerformanceMetrics(
          code: code,
          provider: provider,
          metricDate: metricDate,
          limit: limit,
        ) ??
        _dataManager.queryFundPerformanceMetrics(
          code: code,
          provider: provider,
          metricDate: metricDate,
          limit: limit,
        );
  }

  List<Map<String, dynamic>> queryCompanyInfo(
    ToolContext context,
    String code, {
    String? infoType,
    int limit = 20,
  }) {
    return _storeForContext(
          context,
        )?.queryCompanyInfo(code, infoType: infoType, limit: limit) ??
        _dataManager.queryCompanyInfo(code, infoType: infoType, limit: limit);
  }

  List<Map<String, dynamic>> queryFundamental(
    ToolContext context,
    String code, {
    String? reportDate,
    String? source,
    int limit = 8,
  }) {
    return _storeForContext(context)?.queryFundamental(
          code,
          reportDate: reportDate,
          source: source,
          limit: limit,
        ) ??
        _dataManager.queryFundamental(
          code,
          reportDate: reportDate,
          source: source,
          limit: limit,
        );
  }
}
