import 'dart:convert';

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/http_utils.dart';
import '../../../agent/data_fetcher/provider_policy.dart';
import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';
import '../../../agent/tools/wind_mcp_tool/wind_mcp_tool.dart';
import '../../../shared/api_config.dart';
import '../providers/data_api_interface_contract.dart';
import '../providers/data_api_interface_router.dart';
import '../providers/tushare_market_provider.dart';
import 'cache_policy.dart';

typedef FinanceNewsRowsFetcher =
    Future<List<Map<String, dynamic>>> Function(String query, int limit);
typedef WindFinanceNewsInvoker =
    Future<void> Function(ToolContext context, String query, int limit);

class FinanceNewsMarketDataService {
  final DataApiInterfaceRouter _router;
  final DataManager? _dataManager;
  final FinanceNewsRowsFetcher _eastmoneyFetcher;
  final FinanceNewsRowsFetcher _sinaFetcher;
  late final Future<List<Map<String, dynamic>>> Function(
    String query,
    int limit,
  )
  _tushareFetcher;
  final WindFinanceNewsInvoker _windInvoker;
  TushareMarketProvider? _tushareProvider;

  FinanceNewsMarketDataService({
    DataManager? dataManager,
    DataApiInterfaceRouter? router,
    FinanceNewsRowsFetcher? eastmoneyFetcher,
    FinanceNewsRowsFetcher? sinaFetcher,
    Future<List<Map<String, dynamic>>> Function(String query, int limit)?
    tushareFetcher,
    WindFinanceNewsInvoker? windInvoker,
    TushareMarketProvider? tushareProvider,
  }) : _router =
           router ??
           DataApiInterfaceRouter(
             runtimeBasePathProvider: dataManager == null
                 ? null
                 : () => dataManager.basePath,
           ),
       _dataManager = dataManager,
       _eastmoneyFetcher = eastmoneyFetcher ?? _fetchEastMoneyNews,
       _sinaFetcher = sinaFetcher ?? _fetchSinaNews,
       _windInvoker = windInvoker ?? _callWindFinanceNews,
       _tushareProvider = tushareProvider {
    _tushareFetcher = tushareFetcher ?? _fetchTushareNews;
  }

  Future<Map<String, dynamic>> fetch(
    ToolContext context,
    Map<String, dynamic> input,
  ) async {
    final query =
        (input['query'] as String?)?.trim() ??
        (input['keyword'] as String?)?.trim() ??
        '';
    if (query.isEmpty) {
      throw ArgumentError(
        'query or keyword required for finance_news. Example: MarketData(action:"finance_news", query:"美联储利率政策")',
      );
    }
    final limit = _limit(input);
    final sourceFilter = (input['source'] as String?)?.trim();
    final result = await _router.runCapability<List<Map<String, dynamic>>>(
      interfaceId: 'news.finance_feed',
      call: (capability) async {
        switch (capability.provider) {
          case FinanceProvider.eastmoneyDirect:
            return DataApiProviderExecution(
              data: await _fetchAndReadback(
                context,
                capability,
                query: query,
                limit: limit,
                sourceFilter: sourceFilter,
                fetchRows: () => _eastmoneyFetcher(query, limit),
              ),
              source: 'EastMoney',
              providerName: 'EastMoney',
            );
          case FinanceProvider.sina:
            return DataApiProviderExecution(
              data: await _fetchAndReadback(
                context,
                capability,
                query: query,
                limit: limit,
                sourceFilter: sourceFilter,
                fetchRows: () => _sinaFetcher(query, limit),
              ),
              source: 'Sina',
              providerName: 'Sina',
            );
          case FinanceProvider.tushare:
            return DataApiProviderExecution(
              data: await _fetchAndReadback(
                context,
                capability,
                query: query,
                limit: limit,
                sourceFilter: sourceFilter,
                fetchRows: () => _tushareFetcher(query, limit),
              ),
              source: 'Tushare',
              providerName: 'Tushare',
            );
          case FinanceProvider.wind:
            return DataApiProviderExecution(
              data: await _refreshWindAndReadback(
                context,
                capability,
                query: query,
                limit: limit,
                sourceFilter: sourceFilter,
              ),
              source: 'WindMcp',
              providerName: 'Wind',
            );
          default:
            return null;
        }
      },
      isUsable: (rows) => rows.isNotEmpty,
      emptyMessage: 'returned empty finance news rows',
      failureMessage: 'All finance news providers failed',
      constraint: _constraintFromInput(input),
      cachePolicy: CachePolicy.fromInput(input),
      readCache: () async {
        final rows = _queryRows(
          context,
          query: query,
          limit: limit,
          sourceFilter: sourceFilter,
        );
        if (rows.isEmpty) return null;
        return DataApiLocalCacheResult(
          data: rows,
          source: 'local finance_news',
          providerName: 'local',
        );
      },
    );
    final sourceDataTime = _latestValue(result.data, const ['published_at']);
    final fetchedAt = _latestValue(result.data, const ['fetched_at']);
    return {
      'action': 'finance_news',
      'query': query,
      if (sourceFilter != null && sourceFilter.isNotEmpty)
        'sourceFilter': sourceFilter,
      'interfaceId': result.provenance.interfaceId,
      'provider': result.provenance.provider,
      'providerId': result.provenance.provider,
      'capabilityId': result.provenance.capabilityId,
      'cacheStatus': result.provenance.cacheStatus,
      'cacheMode': _cacheMode(input),
      'cachePolicyMode': result.provenance.cachePolicyMode,
      'cacheDecision': result.provenance.cacheDecision,
      ...result.provenance.routePolicyJson(),
      'canonicalSchema': 'finance_news',
      'canonicalTable': 'finance_news',
      if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
      if (fetchedAt != null) 'fetchedAt': fetchedAt,
      'sourceHealth': _sourceHealth(
        cacheStatus: result.provenance.cacheStatus,
        provider: result.provenance.provider,
        rows: result.data,
      ),
      'count': result.data.length,
      'source': result.source,
      'data': result.data,
      'provenance': {
        ...result.provenance.toJson(),
        if (sourceDataTime != null) 'sourceDataTime': sourceDataTime,
        if (fetchedAt != null) 'fetchedAt': fetchedAt,
      },
    };
  }

  Future<List<Map<String, dynamic>>> _fetchAndReadback(
    ToolContext context,
    DataApiProviderCapability capability, {
    required String query,
    required int limit,
    required String? sourceFilter,
    required Future<List<Map<String, dynamic>>> Function() fetchRows,
  }) async {
    final startedAt = DateTime.now().toUtc();
    final rows = await fetchRows();
    if (rows.isEmpty) return const <Map<String, dynamic>>[];
    final store = ReusableDataStore(context.basePath);
    store.saveFinanceNews(rows);
    return _queryRows(
      context,
      query: query,
      limit: limit,
      sourceFilter: sourceFilter,
      minFetchedAt: startedAt,
    );
  }

  Future<List<Map<String, dynamic>>> _refreshWindAndReadback(
    ToolContext context,
    DataApiProviderCapability capability, {
    required String query,
    required int limit,
    required String? sourceFilter,
  }) async {
    final startedAt = DateTime.now().toUtc();
    await _windInvoker(context, query, limit);
    return _queryRows(
      context,
      query: query,
      limit: limit,
      sourceFilter: sourceFilter,
      minFetchedAt: startedAt,
    );
  }

  List<Map<String, dynamic>> _queryRows(
    ToolContext context, {
    required String query,
    required int limit,
    String? sourceFilter,
    DateTime? minFetchedAt,
  }) {
    final rows = ReusableDataStore(
      context.basePath,
    ).queryFinanceNews(keyword: query, source: sourceFilter, limit: limit);
    if (minFetchedAt == null) return rows;
    return rows
        .where((row) {
          final fetchedAt = row['fetched_at']?.toString();
          if (fetchedAt == null || fetchedAt.isEmpty) return false;
          final parsed = DateTime.tryParse(fetchedAt)?.toUtc();
          return parsed != null &&
              (parsed.isAtSameMomentAs(minFetchedAt) ||
                  parsed.isAfter(minFetchedAt));
        })
        .toList(growable: false);
  }

  int _limit(Map<String, dynamic> input) {
    final raw = input['limit'];
    if (raw is num) return raw.toInt().clamp(1, 50);
    if (raw is String) {
      final parsed = int.tryParse(raw);
      if (parsed != null) return parsed.clamp(1, 50);
    }
    return 20;
  }

  String _cacheMode(Map<String, dynamic> input) =>
      '${input['cacheMode'] ?? 'cache-first'}';

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

  Map<String, dynamic> _sourceHealth({
    required String cacheStatus,
    required String provider,
    required List<Map<String, dynamic>> rows,
  }) {
    final lastSuccessfulFetch = _latestValue(rows, const [
      'fetched_at',
      'fetchedAt',
    ]);
    final isCache = cacheStatus == 'cache-hit';
    return {
      'status': isCache ? 'cached' : 'live',
      'provider': provider,
      if (lastSuccessfulFetch != null) 'lastSuccessfulFetch': lastSuccessfulFetch,
      'nextRetryPolicy': isCache
          ? 'use-cache-first; refresh only when the user asks for live news or cache freshness is insufficient'
          : 'live rows were queryable; normal cache-first reuse is allowed',
    };
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

  Future<List<Map<String, dynamic>>> _fetchTushareNews(
    String query,
    int limit,
  ) async {
    final provider = _requireTushareProvider();
    final results = <Map<String, dynamic>>[];
    final major = await provider.callRaw('major_news', {
      'src': '',
      'start_date': _daysAgo(7),
      'end_date': '',
    }, fields: 'title,content,pub_time,src');
    final items = major['items'] as List? ?? const [];
    final fields = major['fields'] as List? ?? const [];
    for (final row in items) {
      if (row is! List) continue;
      final mapped = <String, dynamic>{};
      for (var i = 0; i < fields.length && i < row.length; i++) {
        mapped['${fields[i]}'] = row[i];
      }
      final title = '${mapped['title'] ?? ''}';
      final content = '${mapped['content'] ?? ''}';
      final lowerQuery = query.toLowerCase();
      if (!title.toLowerCase().contains(lowerQuery) &&
          !content.toLowerCase().contains(lowerQuery)) {
        continue;
      }
      results.add({
        'title': title,
        'summary': content,
        'content': content,
        'source': 'Tushare重大新闻',
        'publisher': '${mapped['src'] ?? 'Tushare'}',
        'published_at': '${mapped['pub_time'] ?? ''}',
      });
      if (results.length >= limit) break;
    }
    return results;
  }

  TushareMarketProvider _requireTushareProvider() {
    return _tushareProvider ??= FetcherTushareMarketProvider(
      _dataManager ?? DataManager(),
    );
  }

  String _daysAgo(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }
}

Future<void> _callWindFinanceNews(
  ToolContext context,
  String query,
  int limit,
) async {
  final apiConfig = ApiConfigStore();
  final tool = WindMcpTool(basePath: context.basePath, apiConfig: apiConfig);
  final result = await tool.call('finance_news', {
    'action': 'call',
    'server': 'financial_docs',
    'tool': 'get_financial_news',
    'arguments': {'query': query, 'top_k': limit},
  }, context);
  if (result.isError) {
    throw StateError(result.content);
  }
}

Future<List<Map<String, dynamic>>> _fetchEastMoneyNews(
  String query,
  int limit,
) async {
  final response = await fetchWithRetry(
    'https://search-api-web.eastmoney.com/search/jsonp',
    queryParams: {
      'cb': 'jQuery',
      'param':
          '{"uid":"","keyword":"$query","type":["cmsArticleWebOld"],"client":"web","clientVersion":"curr","param":{"cmsArticleWebOld":{"searchScope":"default","sort":"default","pageIndex":1,"pageSize":$limit}}}',
    },
    headers: {'User-Agent': randomUserAgent()},
  );
  var body = response.body;
  if (body.startsWith('jQuery')) {
    body = body.substring(body.indexOf('(') + 1, body.lastIndexOf(')'));
  }
  final json = jsonDecode(body) as Map<String, dynamic>;
  final articles = json['result']?['cmsArticleWebOld'] as List? ?? const [];
  return articles
      .take(limit)
      .whereType<Map>()
      .map(
        (a) => <String, dynamic>{
          'title': a['title'] ?? '',
          'url': a['url'] ?? '',
          'source': '东方财富',
          'published_at': a['date'] ?? '',
        },
      )
      .toList(growable: false);
}

Future<List<Map<String, dynamic>>> _fetchSinaNews(
  String query,
  int limit,
) async {
  final response = await fetchWithRetry(
    'https://feed.mix.sina.com.cn/api/roll/get',
    queryParams: {
      'pageid': '153',
      'lid': '2516',
      'k': query,
      'num': '$limit',
      'page': '1',
    },
    headers: {
      'User-Agent': randomUserAgent(),
      'Referer': 'https://finance.sina.com.cn',
    },
  );
  final json = jsonDecode(response.body) as Map<String, dynamic>;
  final result = json['result'] as Map<String, dynamic>? ?? const {};
  final data = result['data'] as List? ?? const [];
  return data
      .take(limit)
      .whereType<Map>()
      .map(
        (item) => <String, dynamic>{
          'title': item['title'] ?? '',
          'url': item['url'] ?? '',
          'source': '新浪财经',
          'published_at': item['ctime'] ?? item['createtime'] ?? '',
        },
      )
      .where((row) => '${row['title'] ?? ''}'.trim().isNotEmpty)
      .toList(growable: false);
}
