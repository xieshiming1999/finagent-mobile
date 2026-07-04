import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../data_fetcher/http_utils.dart';
import '../../data_fetcher/data_manager.dart';
import '../../data_fetcher/reusable_data_store.dart';
import '../../data_fetcher/search_providers.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../../../shared/api_config.dart';
import '../../../domain/market/services/finance_news_market_data_service.dart';

/// Unified research tool: web search, news, social sentiment, web fetch.
class ResearchTool extends Tool {
  ApiConfigStore? _apiConfig;
  int _paidSearchCount = 0; // round-robin between Brave and Tavily

  /// Initialize search backends. Call once on app startup.
  void init(String basePath, {ApiConfigStore? apiConfig}) {
    _apiConfig = apiConfig;
  }

  @override
  String get name => 'Research';

  @override
  String get description =>
      'Research tool for search engines, financial news, social sentiment, and fetch URLs. Use action="help".';

  @override
  String get prompt =>
      '''Research and information gathering. Use action="help" to discover all capabilities.

Key actions:
- **providers** — List configured search/news providers and current availability.
- **search** — Web search via explicit search engines. auto = monthly-limited Brave/Tavily routing. Use only when Wind/local/free finance sources cannot answer. query: "关键词"
- **news** — Search financial news for a stock/topic. query: "贵州茅台"
- **sentiment** — Social sentiment (StockTwits for US stocks). symbols: ["AAPL"]
- **fetch** — Fetch any web URL content. url: "https://..."
- **help** — List all actions''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['providers', 'search', 'news', 'sentiment', 'fetch', 'help'],
      },
      'query': {'type': 'string', 'description': '(news) Search query'},
      'provider': {
        'type': 'string',
        'enum': ['auto', 'brave', 'tavily'],
        'description':
            '(search) Search engine to use. auto = Brave/Tavily routing.',
      },
      'symbols': {
        'type': 'array',
        'items': {'type': 'string'},
        'description': '(sentiment) Stock symbols',
      },
      'url': {'type': 'string', 'description': '(fetch) URL to fetch'},
      'method': {
        'type': 'string',
        'description': '(fetch) HTTP method: GET/POST',
      },
      'headers': {'type': 'object', 'description': '(fetch) Custom headers'},
      'body': {'type': 'string', 'description': '(fetch) POST body'},
      'maxLength': {
        'type': 'integer',
        'description': '(fetch) Max content length (default 50000)',
      },
    },
    'required': ['action'],
  };

  @override
  bool get isReadOnly => true;
  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final action = input['action'] as String? ?? 'help';
    try {
      return switch (action) {
        'help' => _help(toolUseId),
        'providers' => _providers(toolUseId),
        'search' => await _search(toolUseId, input),
        'news' => await _news(toolUseId, input, context),
        'sentiment' => await _sentiment(toolUseId, input),
        'fetch' => await _fetch(toolUseId, input),
        _ => ToolResult(
          toolUseId: toolUseId,
          content: 'Unknown action "$action". Use action="help".',
          isError: true,
        ),
      };
    } catch (e) {
      return ToolResult(toolUseId: toolUseId, content: '$e', isError: true);
    }
  }

  ToolResult _help(String toolUseId) {
    return ToolResult(
      toolUseId: toolUseId,
      content: '''Research actions:

WEB SEARCH:
  providers — Show search engines and news sources known to this runtime
    Search engines:
      - Brave Search API (paid/monthly-limited key)
      - Tavily Search API (paid/monthly-limited key)

  search — General web search via explicit search engines
    query: "any search query"
    provider: "auto" | "brave" | "tavily" (optional, default auto)
    Returns: title, url, content snippet, search engine source, provider provenance
    auto mode: Brave/Tavily routing
    Budget: use only when Wind/local/free finance sources cannot answer; batch related questions into one precise query

FINANCIAL NEWS:
  news — Search financial news from Baidu Finance + East Money
    query: "贵州茅台" or "AAPL earnings"
    Returns: title, url, source, date

SOCIAL SENTIMENT:
  sentiment — Social media sentiment for US stocks
    symbols: ["AAPL", "TSLA"]
    Source: StockTwits (bullish/bearish ratio)

WEB FETCH:
  fetch — Fetch content from any URL
    url: "https://..."
    method: GET/POST, headers: {}, body: ""
    Returns: text content (HTML stripped)

Note: agent can also use WebView to open Google/Bing directly for interactive search.''',
    );
  }

  ToolResult _providers(String toolUseId) {
    final braveKey = _apiConfig?.get('BRAVE_SEARCH_KEY');
    final tavilyKey = _apiConfig?.get('TAVILY_API_KEY');
    final hasBrave = braveKey != null && braveKey.isNotEmpty;
    final hasTavily = tavilyKey != null && tavilyKey.isNotEmpty;
    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'tool': 'Research',
        'action': 'providers',
        'searchEngines': [
          {
            'provider': 'brave',
            'label': 'Brave Search API',
            'kind': 'search-engine',
            'quotaClass': 'paid-monthly-limited',
            'configured': hasBrave,
            'available': hasBrave,
          },
          {
            'provider': 'tavily',
            'label': 'Tavily Search API',
            'kind': 'search-engine',
            'quotaClass': 'paid-monthly-limited',
            'configured': hasTavily,
            'available': hasTavily,
          },
        ],
        'newsSources': const [
          {
            'provider': 'baidu-finance',
            'label': 'Baidu Finance',
            'kind': 'news-source',
          },
          {
            'provider': 'eastmoney-news',
            'label': 'EastMoney',
            'kind': 'news-source',
          },
          {
            'provider': 'sina-finance',
            'label': 'Sina Finance',
            'kind': 'news-source',
          },
          {
            'provider': 'tushare-news',
            'label': 'Tushare News',
            'kind': 'news-source',
          },
        ],
      }),
    );
  }

  // ─── Web Search ───

  Future<ToolResult> _search(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final query = input['query'] as String?;
    final provider = (input['provider'] as String? ?? 'auto').toLowerCase();
    if (query == null || query.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'query required. Example: Research(action: "search", query: "贵州茅台 最新消息")',
        isError: true,
      );
    }

    if (!['auto', 'brave', 'tavily'].contains(provider)) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'provider must be one of auto, brave, tavily. Example: Research(action: "search", query: "AAPL earnings guidance", provider: "brave")',
        isError: true,
      );
    }

    final fetchedAt = DateTime.now().toIso8601String();
    final errors = <String>[];
    final routeTried = <String>[];

    final braveKey = _apiConfig?.get('BRAVE_SEARCH_KEY');
    final tavilyKey = _apiConfig?.get('TAVILY_API_KEY');
    final hasBrave = braveKey != null && braveKey.isNotEmpty;
    final hasTavily = tavilyKey != null && tavilyKey.isNotEmpty;

    ToolResult successResult({
      required String providerUsed,
      required String searchEngine,
      required String quotaClass,
      required List<Map<String, dynamic>> results,
    }) {
      return ToolResult(
        toolUseId: toolUseId,
        content: const JsonEncoder.withIndent('  ').convert({
          'tool': 'Research',
          'capability': 'search-engine',
          'action': 'search',
          'query': query,
          'providerRequested': provider,
          'providerUsed': providerUsed,
          'searchEngine': searchEngine,
          'quotaClass': quotaClass,
          'routeTried': routeTried,
          'fetchedAt': fetchedAt,
          'source': searchEngine,
          'count': results.length,
          'results': results,
        }),
      );
    }

    Future<ToolResult?> tryBrave() async {
      routeTried.add('brave');
      if (!hasBrave) {
        errors.add('Brave: not configured');
        return null;
      }
      try {
        final results = await BraveSearchProvider(
          apiKey: braveKey,
        ).search(query);
        if (results.isNotEmpty) {
          return successResult(
            providerUsed: 'brave',
            searchEngine: 'Brave',
            quotaClass: 'paid-monthly-limited',
            results: results,
          );
        }
      } catch (e) {
        errors.add('Brave: $e');
      }
      return null;
    }

    Future<ToolResult?> tryTavily() async {
      routeTried.add('tavily');
      if (!hasTavily) {
        errors.add('Tavily: not configured');
        return null;
      }
      try {
        final results = await TavilySearchProvider(
          apiKey: tavilyKey,
        ).search(query);
        if (results.isNotEmpty) {
          return successResult(
            providerUsed: 'tavily',
            searchEngine: 'Tavily',
            quotaClass: 'paid-monthly-limited',
            results: results,
          );
        }
      } catch (e) {
        errors.add('Tavily: $e');
      }
      return null;
    }

    if (provider == 'brave') {
      final result = await tryBrave();
      if (result != null) return result;
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Search failed. ${errors.join("; ")}',
        isError: true,
      );
    }
    if (provider == 'tavily') {
      final result = await tryTavily();
      if (result != null) return result;
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Search failed. ${errors.join("; ")}',
        isError: true,
      );
    }

    if (hasBrave || hasTavily) {
      final providers = <Future<ToolResult?> Function()>[];
      if (_paidSearchCount % 2 == 0) {
        if (hasBrave) providers.add(tryBrave);
        if (hasTavily) providers.add(tryTavily);
      } else {
        if (hasTavily) providers.add(tryTavily);
        if (hasBrave) providers.add(tryBrave);
      }
      _paidSearchCount++;

      for (final provider in providers) {
        final result = await provider();
        if (result != null) return result;
      }
    }

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Search failed. ${errors.join("; ")}\nAlternatives: Research(news) for financial news, or open Google in WebView.',
      isError: true,
    );
  }

  // ─── News Search ───

  Future<ToolResult> _news(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final query = input['query'] as String?;
    if (query == null || query.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'query required. Example: Research(action: "news", query: "贵州茅台")',
        isError: true,
      );
    }

    final results = <Map<String, dynamic>>[];
    final errors = <String>[];

    // Source 1: Baidu Finance News
    try {
      final baiduResults = await _searchBaiduNews(query);
      results.addAll(baiduResults);
    } catch (e) {
      errors.add('Baidu: $e');
    }

    // Source 2: East Money News
    try {
      final emResults = await _searchEastMoneyNews(query);
      results.addAll(emResults);
    } catch (e) {
      errors.add('EastMoney: $e');
    }

    // Source 3: Sina Finance News
    try {
      final sinaResults = await _searchSinaNews(query, context);
      results.addAll(sinaResults);
    } catch (e) {
      errors.add('Sina: $e');
    }

    // Source 4: Tushare News (if token available)
    final tushareToken = _apiConfig?.get('TUSHARE_TOKEN');
    if (tushareToken != null && tushareToken.isNotEmpty) {
      try {
        final tsResults = await _searchTushareNews(query, tushareToken);
        results.addAll(tsResults);
      } catch (e) {
        errors.add('Tushare: $e');
      }
    }

    // Deduplicate by title similarity and sort by date
    final seen = <String>{};
    final deduped = results.where((r) {
      final title = (r['title'] as String? ?? '').trim();
      if (title.isEmpty || seen.contains(title)) return false;
      seen.add(title);
      return true;
    }).toList();
    Map<String, dynamic>? ingestion;
    if (context.basePath.isNotEmpty && deduped.isNotEmpty) {
      final store = ReusableDataStore(context.basePath);
      ingestion = store.saveFinanceNews(deduped);
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'news',
        'source': '百度/东方财富/新浪/Tushare',
        'query': query,
        'count': deduped.length,
        'interfaceId': 'news.finance_feed',
        'canonicalSchema': 'finance_news',
        'canonicalTable': 'finance_news',
        ...?ingestion == null ? null : {'ingestion': ingestion},
        'results': deduped.take(20).toList(),
        if (errors.isNotEmpty) 'errors': errors,
      }),
    );
  }

  Future<List<Map<String, dynamic>>> _searchBaiduNews(String query) async {
    final response = await fetchWithRetry(
      'https://gushitong.baidu.com/opendata',
      queryParams: {
        'query': query,
        'resource_id': '5352',
        'pn': '0',
        'rn': '10',
      },
      headers: {'Referer': 'https://gushitong.baidu.com'},
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final data = json['Result'] as List? ?? [];
    final items = <Map<String, dynamic>>[];
    for (final group in data) {
      final list =
          (group as Map?)?['DisplayData']?['resultData']?['tplData']?['result']?['list']
              as List? ??
          [];
      for (final item in list) {
        if (item is Map) {
          items.add({
            'title': item['title'] ?? '',
            'url': item['url'] ?? '',
            'source': item['media_name'] ?? 'Baidu',
            'date': item['publish_time'] ?? '',
          });
        }
      }
    }
    return items;
  }

  Future<List<Map<String, dynamic>>> _searchEastMoneyNews(String query) async {
    final response = await fetchWithRetry(
      'https://search-api-web.eastmoney.com/search/jsonp',
      queryParams: {
        'cb': 'jQuery',
        'param':
            '{"uid":"","keyword":"$query","type":["cmsArticleWebOld"],"client":"web","clientVersion":"curr","param":{"cmsArticleWebOld":{"searchScope":"default","sort":"default","pageIndex":1,"pageSize":10}}}',
      },
    );

    var body = response.body;
    if (body.startsWith('jQuery')) {
      body = body.substring(body.indexOf('(') + 1, body.lastIndexOf(')'));
    }

    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      final articles = json['result']?['cmsArticleWebOld'] as List? ?? [];
      return articles
          .take(10)
          .map(
            (a) => {
              'title': a['title'] ?? '',
              'url': a['url'] ?? '',
              'source': '东方财富',
              'date': a['date'] ?? '',
            },
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ─── Sina Finance News ───

  Future<List<Map<String, dynamic>>> _searchSinaNews(
    String query,
    ToolContext context,
  ) async {
    final result =
        await FinanceNewsMarketDataService(
          dataManager: DataManager(basePath: context.basePath),
        ).fetch(context, {
          'query': query,
          'keyword': query,
          'provider': 'sina',
          'cacheMode': 'live-only',
          'limit': 10,
        });
    final rows = result['data'] as List? ?? const [];
    final provenance =
        result['provenance'] as Map<String, dynamic>? ?? const {};
    return rows
        .take(10)
        .map((item) {
          if (item is! Map) return <String, dynamic>{};
          return <String, dynamic>{
            'title': item['title'] ?? '',
            'url': item['url'] ?? '',
            'source': item['source'] ?? '新浪财经',
            'date': item['published_at'] ?? item['date'] ?? '',
            'interfaceId': result['interfaceId'] ?? 'news.finance_feed',
            'provider': provenance['provider'] ?? 'sina',
            'capabilityId':
                provenance['capabilityId'] ?? 'sina.news.finance_feed',
            'cacheStatus': provenance['cacheStatus'],
          };
        })
        .where((m) => (m['title'] as String).isNotEmpty)
        .toList();
  }

  // ─── Tushare News ───

  Future<List<Map<String, dynamic>>> _searchTushareNews(
    String query,
    String token,
  ) async {
    final results = <Map<String, dynamic>>[];

    // 1. Major news (重大新闻)
    try {
      final response = await http
          .post(
            Uri.parse('http://api.tushare.pro'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'api_name': 'major_news',
              'token': token,
              'params': {'src': '', 'start_date': _daysAgo(7), 'end_date': ''},
              'fields': 'title,content,pub_time,src',
            }),
          )
          .timeout(const Duration(seconds: 10));

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      if (json['code'] == 0) {
        final data = json['data'] as Map<String, dynamic>? ?? {};
        final items = data['items'] as List? ?? [];
        final fields = data['fields'] as List? ?? [];
        for (final row in items.take(10)) {
          if (row is! List) continue;
          final map = <String, dynamic>{};
          for (var i = 0; i < fields.length && i < row.length; i++) {
            map['${fields[i]}'] = row[i];
          }
          final title = '${map['title'] ?? ''}';
          if (title.isNotEmpty &&
              title.toLowerCase().contains(query.toLowerCase())) {
            results.add({
              'title': title,
              'url': '',
              'source': 'Tushare重大新闻',
              'date': '${map['pub_time'] ?? ''}',
            });
          }
        }
      }
    } catch (_) {}

    // 2. Company announcements (公司公告) — if query looks like a stock code
    final codeMatch = RegExp(r'\d{6}').firstMatch(query);
    if (codeMatch != null) {
      final code = codeMatch.group(0)!;
      final tsCode = code.startsWith('6') ? '$code.SH' : '$code.SZ';
      try {
        final response = await http
            .post(
              Uri.parse('http://api.tushare.pro'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'api_name': 'anns',
                'token': token,
                'params': {
                  'ts_code': tsCode,
                  'start_date': _daysAgo(30),
                  'end_date': '',
                },
                'fields': 'title,ann_date,url',
              }),
            )
            .timeout(const Duration(seconds: 10));

        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['code'] == 0) {
          final data = json['data'] as Map<String, dynamic>? ?? {};
          final items = data['items'] as List? ?? [];
          final fields = data['fields'] as List? ?? [];
          for (final row in items.take(10)) {
            if (row is! List) continue;
            final map = <String, dynamic>{};
            for (var i = 0; i < fields.length && i < row.length; i++) {
              map['${fields[i]}'] = row[i];
            }
            results.add({
              'title': '${map['title'] ?? ''}',
              'url': '${map['url'] ?? ''}',
              'source': 'Tushare公告',
              'date': '${map['ann_date'] ?? ''}',
            });
          }
        }
      } catch (_) {}
    }

    return results;
  }

  String _daysAgo(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  // ─── Social Sentiment ───

  Future<ToolResult> _sentiment(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    final symbols = (input['symbols'] as List?)?.cast<String>() ?? [];
    if (symbols.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'symbols required. Example: Research(action: "sentiment", symbols: ["AAPL"])',
        isError: true,
      );
    }

    final results = <Map<String, dynamic>>[];
    for (final symbol in symbols) {
      final sentimentData = <String, dynamic>{'symbol': symbol};

      // StockTwits sentiment (US stocks)
      try {
        final stResponse = await fetchWithRetry(
          'https://api.stocktwits.com/api/2/streams/symbol/$symbol.json',
          headers: {'User-Agent': randomUserAgent()},
        );
        if (stResponse.statusCode == 200) {
          final stJson = jsonDecode(stResponse.body) as Map<String, dynamic>;
          final messages = stJson['messages'] as List? ?? [];
          var bullish = 0, bearish = 0;
          for (final msg in messages) {
            final sentiment =
                (msg as Map?)?['entities']?['sentiment']?['basic'] as String?;
            if (sentiment == 'Bullish') bullish++;
            if (sentiment == 'Bearish') bearish++;
          }
          sentimentData['stocktwits'] = {
            'messages': messages.length,
            'bullish': bullish,
            'bearish': bearish,
            'ratio': bullish + bearish > 0
                ? double.parse(
                    (bullish / (bullish + bearish) * 100).toStringAsFixed(1),
                  )
                : null,
          };
        }
      } catch (_) {}

      // Guba exposes post titles but no typed sentiment label. Preserve the
      // observations without guessing their meaning from words in the title.
      final cleanCode = symbol
          .replaceAll(RegExp(r'\.(SH|SZ|BJ)$', caseSensitive: false), '')
          .replaceAll(RegExp(r'^(SH|SZ|BJ)', caseSensitive: false), '');
      if (RegExp(r'^\d{6}$').hasMatch(cleanCode)) {
        try {
          final gubaResp = await fetchWithRetry(
            'https://guba.eastmoney.com/list,$cleanCode.html',
            headers: {
              'User-Agent': randomUserAgent(),
              'Referer': 'https://guba.eastmoney.com/',
            },
          );
          if (gubaResp.statusCode == 200) {
            final titles = RegExp(r'title="([^"]{4,})"')
                .allMatches(gubaResp.body)
                .map((m) => m.group(1)!)
                .where((t) => !t.contains('东方财富') && !t.contains('股吧'))
                .take(30)
                .toList();
            sentimentData['guba'] = buildUnclassifiedGubaObservation(titles);
          }
        } catch (_) {}
      }

      results.add(sentimentData);
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: const JsonEncoder.withIndent('  ').convert({
        'action': 'sentiment',
        'source': 'StockTwits typed sentiment and unclassified Guba posts',
        'data': results,
      }),
    );
  }

  // ─── Web Fetch ───

  Future<ToolResult> _fetch(
    String toolUseId,
    Map<String, dynamic> input,
  ) async {
    var url = input['url'] as String?;
    if (url == null || url.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'url required. Example: Research(action: "fetch", url: "https://...")',
        isError: true,
      );
    }

    // Auto-inject API keys for known services
    final injected = _injectApiKey(url);
    if (injected == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'FRED_API_KEY not configured. Please set it in Settings, or use Econdb (https://www.econdb.com/api/) as a free alternative.',
      );
    }
    url = injected;

    final method = (input['method'] as String? ?? 'GET').toUpperCase();
    final customHeaders = (input['headers'] as Map<String, dynamic>?)?.map(
      (k, v) => MapEntry(k, v.toString()),
    );
    final body = input['body'] as String?;
    final maxLength = input['maxLength'] as int? ?? 50000;

    final headers = {'User-Agent': randomUserAgent(), ...?customHeaders};

    final http.Response response;
    if (method == 'POST') {
      response = await http
          .post(Uri.parse(url), headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
    } else {
      response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));
    }

    if (response.statusCode != 200) {
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'HTTP ${response.statusCode}: ${response.body.length > 200 ? response.body.substring(0, 200) : response.body}',
        isError: true,
      );
    }

    // Decode body with correct charset (some Chinese APIs use GBK)
    final contentType = response.headers['content-type'] ?? '';
    var content = decodeResponseBody(response);
    if (contentType.contains('html') ||
        content.contains('<html') ||
        content.contains('<!DOCTYPE')) {
      content = content
          .replaceAll(
            RegExp(r'<script[^>]*>[\s\S]*?</script>', caseSensitive: false),
            '',
          )
          .replaceAll(
            RegExp(r'<style[^>]*>[\s\S]*?</style>', caseSensitive: false),
            '',
          )
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
    }

    if (content.length > maxLength) {
      content =
          '${content.substring(0, maxLength)}\n\n[Truncated: ${content.length} chars total, showing first $maxLength]';
    }

    return ToolResult(toolUseId: toolUseId, content: content);
  }

  String? _injectApiKey(String url) {
    // FRED: auto-append api_key if configured and not already in URL
    if (url.contains('api.stlouisfed.org') && !url.contains('api_key=')) {
      final fredKey = _apiConfig?.get('FRED_API_KEY');
      if (fredKey != null && fredKey.isNotEmpty) {
        final separator = url.contains('?') ? '&' : '?';
        return '$url${separator}api_key=$fredKey';
      }
      return null; // key not configured
    }
    return url;
  }
}

Map<String, dynamic> buildUnclassifiedGubaObservation(List<String> titles) => {
  'source': '东方财富股吧',
  'posts': titles.length,
  'classification': 'unclassified',
  'classificationReason':
      'The source does not provide a typed sentiment label.',
  'topTitles': titles.take(5).toList(),
};
