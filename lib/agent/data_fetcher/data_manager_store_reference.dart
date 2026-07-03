part of 'data_manager.dart';

extension DataManagerReferenceStoreAccess on DataManager {
  Map<String, dynamic>? saveExCategories(
    List<Map<String, dynamic>> rows, {
    String source = '通达信扩展',
  }) {
    return _store?.saveExCategories(rows, source: source);
  }

  void saveTdxSecurityCounts(
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
  }) {
    _store?.saveTdxSecurityCounts(rows, source: source);
  }

  List<Map<String, dynamic>> queryTdxSecurityCounts({
    String? scope,
    String? market,
    int limit = 20,
  }) {
    return _store?.queryTdxSecurityCounts(
          scope: scope,
          market: market,
          limit: limit,
        ) ??
        const [];
  }

  void saveTdxChartSampling(
    List<Map<String, dynamic>> rows, {
    String source = '通达信',
  }) {
    _store?.saveTdxChartSampling(rows, source: source);
  }

  List<Map<String, dynamic>> queryTdxChartSampling({
    String? scope,
    String? code,
    String? market,
    String? category,
    int limit = 120,
  }) {
    return _store?.queryTdxChartSampling(
          scope: scope,
          code: code,
          market: market,
          category: category,
          limit: limit,
        ) ??
        const [];
  }

  void saveExTableEntries(
    List<Map<String, dynamic>> rows, {
    String source = '通达信扩展',
  }) {
    _store?.saveExTableEntries(rows, source: source);
  }

  List<Map<String, dynamic>> queryExTableEntries({
    String? code,
    String? category,
    int limit = 100,
  }) {
    return _store?.queryExTableEntries(
          code: code,
          category: category,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryExCategories({int limit = 100}) {
    return _store?.queryExCategories(limit: limit) ?? const [];
  }

  List<Map<String, dynamic>> queryWindDocuments({
    String? query,
    String? tool,
    String? entityCode,
    String? source,
    int limit = 50,
  }) {
    return _store?.queryWindDocuments(
          query: query,
          tool: tool,
          entityCode: entityCode,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryWindEconomicSeries({
    String? metricQuery,
    String? source,
    int limit = 100,
  }) {
    return _store?.queryWindEconomicSeries(
          metricQuery: metricQuery,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryWindAnalyticsResults({
    String? question,
    String? source,
    int limit = 100,
  }) {
    return _store?.queryWindAnalyticsResults(
          question: question,
          source: source,
          limit: limit,
        ) ??
        const [];
  }

  List<Map<String, dynamic>> queryFundHolding({
    String? fundCode,
    String? stockCode,
    String? reportDate,
    int limit = 100,
  }) {
    return _store?.queryFundHolding(
          fundCode: fundCode,
          stockCode: stockCode,
          reportDate: reportDate,
          limit: limit,
        ) ??
        const [];
  }

  Map<String, dynamic> coverage({String? code}) {
    return _store?.coverage(code: code) ??
        {'available': false, 'message': 'Reusable data store not configured'};
  }

  Map<String, dynamic> stats() =>
      _store?.stats() ??
      {'available': false, 'message': 'Reusable data store not configured'};

  Map<String, dynamic> reusableSummary() => coverage();
}
