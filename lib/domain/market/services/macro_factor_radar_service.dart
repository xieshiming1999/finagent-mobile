import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../shared/api_config.dart';

class MacroFactorRadarResult {
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> sources;
  final String generatedAt;
  final String? error;

  const MacroFactorRadarResult({
    required this.rows,
    required this.sources,
    required this.generatedAt,
    this.error,
  });
}

class MacroFactorRadarService {
  final ReusableDataStore store;
  final ApiConfigStore? apiConfig;
  final http.Client _http;

  MacroFactorRadarService({
    required this.store,
    this.apiConfig,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  MacroFactorRadarResult read() {
    final generatedAt = DateTime.now().toUtc().toIso8601String();
    final existing = store.queryMarketMovingFactors(limit: 80);
    if (existing.isNotEmpty) {
      return MacroFactorRadarResult(
        rows: existing,
        sources: _sourceRegistrySnapshot(),
        generatedAt: generatedAt,
      );
    }
    store.saveMarketMovingFactors(_seedRows(generatedAt));
    return MacroFactorRadarResult(
      rows: store.queryMarketMovingFactors(limit: 80),
      sources: _sourceRegistrySnapshot(),
      generatedAt: generatedAt,
    );
  }

  Future<MacroFactorRadarResult> refresh() async {
    final generatedAt = DateTime.now().toUtc().toIso8601String();
    final rows = <Map<String, dynamic>>[..._seedRows(generatedAt)];
    final sources = <Map<String, dynamic>>[
      {
        'id': 'manual.msci',
        'name': 'MSCI official/manual seed',
        'state': 'fallback-only',
        'detail':
            'Seeded index-classification evidence until a specific public document URL is configured.',
      },
      {
        'id': 'manual.goldman-copper',
        'name': 'Goldman/public research summary',
        'state': 'fallback-only',
        'detail':
            'Seeded research-summary evidence; licensed reports must be supplied explicitly.',
      },
    ];

    final fred = await _fetchFred(generatedAt);
    rows.addAll(fred.rows);
    sources.add(fred.source);

    final bls = await _fetchBls(generatedAt);
    rows.addAll(bls.rows);
    sources.add(bls.source);

    final bea = await _fetchBea(generatedAt);
    rows.addAll(bea.rows);
    sources.add(bea.source);

    final wind = _readCachedWindFactors(generatedAt);
    rows.addAll(wind.rows);
    sources.add(wind.source);

    final news = _readCachedNewsFactors(generatedAt);
    rows.addAll(news.rows);
    sources.add(news.source);

    store.saveMarketMovingFactors(rows);
    return MacroFactorRadarResult(
      rows: store.queryMarketMovingFactors(limit: 80),
      sources: sources,
      generatedAt: generatedAt,
    );
  }

  Future<_FetchResult> _fetchFred(String fetchedAt) async {
    final key = apiConfig?.get('FRED_API_KEY')?.trim();
    if (key == null || key.isEmpty) {
      return _FetchResult(
        rows: [
          _failureRow(
            'fred:macro_calendar:credential',
            'macro_calendar',
            'FRED API key missing',
            'FRED',
            'credential_missing',
            fetchedAt,
          ),
        ],
        source: {
          'id': 'fred',
          'name': 'FRED API',
          'state': 'credential-gated',
          'detail': 'FRED_API_KEY is required for the normal API path.',
        },
      );
    }
    final uri = Uri.https('api.stlouisfed.org', '/fred/series/observations', {
      'series_id': 'DGS10',
      'api_key': key,
      'file_type': 'json',
      'sort_order': 'desc',
      'limit': '1',
    });
    try {
      final json = await _getJson(uri);
      final observations = json['observations'];
      final point = observations is List && observations.isNotEmpty
          ? observations.first as Map
          : <String, dynamic>{};
      final date = point['date']?.toString();
      final value = point['value'];
      return _FetchResult(
        rows: [
          {
            'factor_id':
                'fred:rates_liquidity:DGS10:${date ?? fetchedAt.substring(0, 10)}',
            'family': 'rates_liquidity',
            'title': 'US 10Y Treasury yield',
            'summary':
                'Long-end Treasury yield is a rates/liquidity factor for equities, commodities, FX, and duration-sensitive assets.',
            'source_name': 'FRED',
            'source_url': 'https://fred.stlouisfed.org/series/DGS10',
            'source_type': 'official_api',
            'source_published_at': date,
            'fetched_at': fetchedAt,
            'event_at': date,
            'affected_assets': [
              'global equities',
              'USD',
              'gold',
              'copper',
              'duration assets',
            ],
            'affected_regions': ['United States', 'Global'],
            'affected_sectors': [],
            'transmission_channels': [
              'discount rate',
              'liquidity conditions',
              'USD pressure',
            ],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label': 'DGS10 ${date ?? '-'} = ${value ?? '-'}',
                'source_url': 'https://fred.stlouisfed.org/series/DGS10',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': value == '.' ? null : num.tryParse('$value'),
              'unit': 'percent',
              'period': date,
            },
            'retrieval_test': _retrieval(
              'fred',
              'fred.series.observations',
              'ok',
            ),
            'raw_json': point,
          },
        ],
        source: {
          'id': 'fred',
          'name': 'FRED API',
          'state': 'ok',
          'detail': 'DGS10 latest observation retrieved.',
        },
      );
    } catch (e) {
      return _sourceFailure(
        'fred',
        'FRED API',
        'rates_liquidity',
        'FRED DGS10 retrieval failed',
        fetchedAt,
        e,
      );
    }
  }

  Future<_FetchResult> _fetchBls(String fetchedAt) async {
    try {
      final json = await _postJson(
        Uri.https('api.bls.gov', '/publicAPI/v2/timeseries/data/'),
        {
          'seriesid': ['CUUR0000SA0'],
          'latest': true,
        },
      );
      final series = json['Results']?['series'];
      final firstSeries = series is List && series.isNotEmpty
          ? series.first as Map
          : null;
      final data = firstSeries?['data'];
      final point = data is List && data.isNotEmpty ? data.first as Map : {};
      final period = '${point['year'] ?? '-'}-${point['period'] ?? '-'}';
      return _FetchResult(
        rows: [
          {
            'factor_id': 'bls:macro_calendar:CPI:$period',
            'family': 'macro_calendar',
            'title': 'US CPI latest BLS observation',
            'summary':
                'CPI is a macro-calendar inflation factor that can affect rates, dollar, equities, gold, copper, and global risk appetite.',
            'source_name': 'BLS',
            'source_url':
                'https://api.bls.gov/publicAPI/v2/timeseries/data/CUUR0000SA0',
            'source_type': 'official_api',
            'source_published_at': period,
            'fetched_at': fetchedAt,
            'event_at': period,
            'affected_assets': [
              'US equities',
              'Treasury yields',
              'USD',
              'gold',
              'copper',
            ],
            'affected_regions': ['United States', 'Global'],
            'affected_sectors': [],
            'transmission_channels': [
              'inflation surprise',
              'Fed policy path',
              'real rates',
            ],
            'expected_direction': 'mixed',
            'severity': 'high',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label':
                    'CUUR0000SA0 ${point['year'] ?? '-'} ${point['period'] ?? '-'} = ${point['value'] ?? '-'}',
                'source_url': 'https://www.bls.gov/cpi/',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': num.tryParse('${point['value'] ?? ''}'),
              'unit': 'index',
              'period': period,
            },
            'retrieval_test': _retrieval(
              'bls',
              'bls.publicAPI.timeseries',
              'ok',
            ),
            'raw_json': point,
          },
        ],
        source: {
          'id': 'bls',
          'name': 'BLS Public Data API',
          'state': 'ok',
          'detail': 'CPI latest observation retrieved.',
        },
      );
    } catch (e) {
      return _sourceFailure(
        'bls',
        'BLS Public Data API',
        'macro_calendar',
        'BLS CPI retrieval failed',
        fetchedAt,
        e,
      );
    }
  }

  Future<_FetchResult> _fetchBea(String fetchedAt) async {
    final key = apiConfig?.get('BEA_API_KEY')?.trim() ?? _readBeaKeyFile();
    if (key == null || key.isEmpty) {
      return _FetchResult(
        rows: [
          _failureRow(
            'bea:macro_calendar:credential',
            'macro_calendar',
            'BEA API key missing',
            'BEA',
            'credential_missing',
            fetchedAt,
          ),
        ],
        source: {
          'id': 'bea',
          'name': 'BEA API',
          'state': 'credential-gated',
          'detail': 'BEA_API_KEY or local bea.txt is required.',
        },
      );
    }
    final uri = Uri.https('apps.bea.gov', '/api/data/', {
      'UserID': key,
      'method': 'GETDATA',
      'datasetname': 'NIPA',
      'TableName': 'T10101',
      'Frequency': 'Q',
      'Year': 'X',
      'ResultFormat': 'JSON',
    });
    try {
      final json = await _getJson(uri);
      final data = json['BEAAPI']?['Results']?['Data'];
      final point = data is List && data.isNotEmpty ? data.first as Map : {};
      return _FetchResult(
        rows: [
          {
            'factor_id':
                'bea:macro_calendar:GDP:${point['TimePeriod'] ?? fetchedAt.substring(0, 10)}',
            'family': 'macro_calendar',
            'title': 'US GDP/NIPA latest BEA observation',
            'summary':
                'BEA national accounts are macro growth evidence for broad equity, rates, dollar, and commodity analysis.',
            'source_name': 'BEA',
            'source_url': 'https://apps.bea.gov/api/',
            'source_type': 'official_api',
            'source_published_at': point['TimePeriod']?.toString(),
            'fetched_at': fetchedAt,
            'event_at': point['TimePeriod']?.toString(),
            'affected_assets': [
              'US equities',
              'Treasury yields',
              'USD',
              'cyclical sectors',
              'copper',
            ],
            'affected_regions': ['United States', 'Global'],
            'affected_sectors': ['Cyclicals', 'Materials'],
            'transmission_channels': [
              'growth surprise',
              'earnings expectations',
              'policy path',
            ],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label':
                    '${point['LineDescription'] ?? 'NIPA'} ${point['TimePeriod'] ?? '-'} = ${point['DataValue'] ?? '-'}',
                'source_url': 'https://apps.bea.gov/api/',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': num.tryParse(
                '${point['DataValue'] ?? ''}'.replaceAll(',', ''),
              ),
              'unit': point['CL_UNIT']?.toString(),
              'period': point['TimePeriod']?.toString(),
            },
            'retrieval_test': _retrieval('bea', 'bea.NIPA.T10101', 'ok'),
            'raw_json': point,
          },
        ],
        source: {
          'id': 'bea',
          'name': 'BEA API',
          'state': 'ok',
          'detail': 'NIPA/GDP latest row retrieved.',
        },
      );
    } catch (e) {
      return _sourceFailure(
        'bea',
        'BEA API',
        'macro_calendar',
        'BEA NIPA retrieval failed',
        fetchedAt,
        e,
      );
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    final response = await _http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _postJson(
    Uri uri,
    Map<String, dynamic> payload,
  ) async {
    final response = await _http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  _FetchResult _readCachedWindFactors(String fetchedAt) {
    final economic = store.queryWindEconomicSeries(limit: 8);
    final documents = store.queryWindDocuments(limit: 8);
    final rows = <Map<String, dynamic>>[];
    for (final row in economic.take(3)) {
      final key =
          '${row['series_key'] ?? row['metric_code'] ?? row['metric_name'] ?? 'economic'}';
      rows.add({
        'factor_id':
            'wind:cached:economic:$key:${row['date'] ?? row['updated_at'] ?? fetchedAt}',
        'family': 'macro_series',
        'title':
            '${row['metric_name'] ?? row['metric_query'] ?? 'Wind cached economic series'}',
        'summary':
            'Cached Wind economic series row: ${row['metric_name'] ?? row['metric_query'] ?? key}.',
        'source_name': 'Wind',
        'source_type': 'cached_provider_row',
        'source_published_at': row['date'],
        'fetched_at': fetchedAt,
        'event_at': row['date'],
        'affected_assets': [
          'China equities',
          'China rates',
          'CNY',
          'commodities',
        ],
        'affected_regions': ['China'],
        'affected_sectors': [],
        'transmission_channels': [
          'macro growth/liquidity evidence',
          'policy expectation',
        ],
        'expected_direction': 'mixed',
        'severity': 'medium',
        'confidence': 'medium',
        'status': 'active',
        'evidence_items': [
          {
            'label':
                '${row['metric_name'] ?? key} ${row['date'] ?? '-'} = ${row['value_num'] ?? row['value_text'] ?? '-'}',
            'retrieved_at': fetchedAt,
          },
        ],
        'macro_values': {
          'actual': _parseNumber(row['value_num']),
          'text': row['value_text'],
          'unit': row['unit'],
          'period': row['date'],
        },
        'retrieval_test': _retrieval(
          'wind',
          'wind.economic_series.cached_readback',
          'ok',
        ),
        'raw_json': row,
      });
    }
    for (final row in documents.take(2)) {
      final title = '${row['title'] ?? row['query'] ?? 'Wind cached document'}';
      rows.add({
        'factor_id':
            'wind:cached:document:${_stableId(title)}:${row['published_at'] ?? row['updated_at'] ?? fetchedAt}',
        'family': 'research_report',
        'title': title,
        'summary':
            '${row['summary'] ?? row['query'] ?? 'Cached Wind document/news evidence.'}',
        'source_name': 'Wind',
        'source_url': row['url'],
        'source_type': 'cached_provider_row',
        'source_published_at': row['published_at'],
        'fetched_at': fetchedAt,
        'event_at': row['published_at'],
        'affected_assets': [],
        'affected_regions': [],
        'affected_sectors': [],
        'transmission_channels': [
          'research/news narrative',
          'positioning attention',
        ],
        'expected_direction': 'unknown',
        'severity': 'medium',
        'confidence': 'medium',
        'status': 'watch',
        'evidence_items': [
          {'label': title, 'source_url': row['url'], 'retrieved_at': fetchedAt},
        ],
        'macro_values': {},
        'retrieval_test': _retrieval(
          'wind',
          'wind.document.cached_readback',
          'ok',
        ),
        'raw_json': row,
      });
    }
    if (rows.isNotEmpty) {
      return _FetchResult(
        rows: rows,
        source: {
          'id': 'wind.cached',
          'name': 'Wind cached macro/document rows',
          'state': 'ok',
          'detail':
              '${rows.length} cached Wind row(s) promoted as macro-factor evidence.',
        },
      );
    }
    final windKey = apiConfig?.get('WIND_API_KEY')?.trim();
    final configured = windKey != null && windKey.isNotEmpty;
    return _FetchResult(
      rows: [
        _failureRow(
          'wind:macro:cached_readback:missing',
          'macro_series',
          configured
              ? 'No reusable Wind macro rows found'
              : 'Wind API key missing',
          'Wind',
          configured ? 'cache_miss' : 'credential_missing',
          fetchedAt,
          configured
              ? 'Wind credential is configured, but no cached wind_economic_series or wind_document rows are available for macro radar readback.'
              : 'WIND_API_KEY is not configured; macro radar can still use public/manual sources.',
        ),
      ],
      source: {
        'id': 'wind.cached',
        'name': 'Wind cached macro/document rows',
        'state': configured ? 'fallback-only' : 'credential-gated',
        'detail': configured
            ? 'Configured, but no cached Wind macro/document evidence is currently reusable.'
            : 'WIND_API_KEY is required before Wind live refresh can populate reusable macro rows.',
      },
    );
  }

  _FetchResult _readCachedNewsFactors(String fetchedAt) {
    final selected = store.queryFinanceNews(limit: 80).take(5).toList();
    if (selected.isEmpty) {
      return _FetchResult(
        rows: [
          _failureRow(
            'news:macro:cached_readback:missing',
            'narrative_attention',
            'No reusable cached finance news rows found',
            'finance_news',
            'cache_miss',
            fetchedAt,
            'No cached finance_news rows are available; refresh governed news first if narrative observations are needed.',
          ),
        ],
        source: {
          'id': 'finance_news.cached',
          'name': 'Cached finance news',
          'state': 'fallback-only',
          'detail':
              'Uses persisted finance_news rows only; no broad live search is triggered by macro radar.',
        },
      );
    }
    return _FetchResult(
      rows: [for (final row in selected) _newsFactorRow(row, fetchedAt)],
      source: {
        'id': 'finance_news.cached',
        'name': 'Cached finance news',
        'state': 'ok',
        'detail':
            '${selected.length} cached finance_news row(s) promoted as macro narrative evidence.',
      },
    );
  }

  _FetchResult _sourceFailure(
    String id,
    String name,
    String family,
    String title,
    String fetchedAt,
    Object error,
  ) {
    final message = error.toString();
    return _FetchResult(
      rows: [
        _failureRow(
          '$id:$family:error',
          family,
          title,
          name,
          'unknown',
          fetchedAt,
          message,
        ),
      ],
      source: {
        'id': id,
        'name': name,
        'state': 'unsupported',
        'detail': message,
      },
    );
  }

  String? _readBeaKeyFile() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) return null;
    final file = File('$home/.fin_electron/bea.txt');
    if (!file.existsSync()) return null;
    final value = file.readAsStringSync().trim();
    return value.isEmpty ? null : value;
  }
}

class _FetchResult {
  final List<Map<String, dynamic>> rows;
  final Map<String, dynamic> source;

  const _FetchResult({required this.rows, required this.source});
}

List<Map<String, dynamic>> _seedRows(String fetchedAt) => [
  {
    'factor_id': 'manual:index_classification:msci:indonesia-watch',
    'family': 'index_classification',
    'title': 'MSCI Indonesia market-classification watch',
    'summary':
        'Index-provider classification, investability, or accessibility reports can affect Indonesia equities through passive-flow and institutional-access channels.',
    'source_name': 'MSCI',
    'source_url': 'https://www.msci.com/market-classification',
    'source_type': 'manual_seed',
    'fetched_at': fetchedAt,
    'affected_assets': ['Indonesia equities', 'IDR', 'EIDO'],
    'affected_regions': ['Indonesia'],
    'affected_sectors': [],
    'transmission_channels': [
      'passive benchmark flow',
      'investability review',
      'active de-risking',
    ],
    'expected_direction': 'mixed',
    'severity': 'medium',
    'confidence': 'medium',
    'status': 'watch',
    'evidence_items': [
      {
        'label':
            'Manual seed from macro factor source-probe report; replace with configured public MSCI document when available.',
        'source_url': 'https://www.msci.com/market-classification',
        'retrieved_at': fetchedAt,
      },
    ],
    'macro_values': {},
    'retrieval_test': _retrieval('manual', 'manual.msci', 'fallback-only'),
  },
  {
    'factor_id': 'manual:research_report:goldman:copper-pulse',
    'family': 'research_report',
    'title': 'Copper research-summary pulse',
    'summary':
        'Major public or licensed copper research summaries can affect copper and miner sentiment through supply-demand revisions, forecasts, positioning, and sector allocation.',
    'source_name': 'Goldman Sachs / public summary',
    'source_type': 'licensed_summary',
    'fetched_at': fetchedAt,
    'affected_assets': ['Copper', 'global miners', 'commodity currencies'],
    'affected_regions': ['Global'],
    'affected_sectors': ['Metals', 'Mining'],
    'transmission_channels': [
      'supply-demand revision',
      'price forecast',
      'sector allocation',
    ],
    'expected_direction': 'unknown',
    'severity': 'medium',
    'confidence': 'low',
    'status': 'watch',
    'evidence_items': [
      {
        'label':
            'Fallback research-summary factor. Do not label as official unless a licensed/public source is supplied.',
        'retrieved_at': fetchedAt,
      },
    ],
    'macro_values': {},
    'retrieval_test': _retrieval(
      'manual',
      'manual.goldman-copper',
      'fallback-only',
    ),
  },
];

List<Map<String, dynamic>> _sourceRegistrySnapshot() => [
  {
    'id': 'fred',
    'name': 'FRED API',
    'state': 'credential-gated',
    'detail': 'Uses FRED_API_KEY when configured.',
  },
  {
    'id': 'bls',
    'name': 'BLS Public Data API',
    'state': 'ok',
    'detail': 'Public CPI/labor/price series path.',
  },
  {
    'id': 'bea',
    'name': 'BEA API',
    'state': 'credential-gated',
    'detail': 'Uses BEA_API_KEY or local bea.txt fallback.',
  },
  {
    'id': 'manual.msci',
    'name': 'MSCI official/manual seed',
    'state': 'fallback-only',
    'detail': 'Use configured official URL or manual seed before broad search.',
  },
  {
    'id': 'manual.goldman-copper',
    'name': 'Goldman/public research summary',
    'state': 'fallback-only',
    'detail': 'Public/licensed summaries only.',
  },
];

Map<String, dynamic> _failureRow(
  String factorId,
  String family,
  String title,
  String sourceName,
  String failureClass,
  String fetchedAt, [
  String? error,
]) => {
  'factor_id': factorId,
  'family': family,
  'title': title,
  'summary':
      error ??
      '$sourceName is not currently available for live factor refresh.',
  'source_name': sourceName,
  'source_type': 'provider',
  'fetched_at': fetchedAt,
  'affected_assets': [],
  'affected_regions': [],
  'affected_sectors': [],
  'transmission_channels': [],
  'expected_direction': 'unknown',
  'severity': 'low',
  'confidence': 'low',
  'status': 'unsupported',
  'failure_class': failureClass,
  'evidence_items': [
    {'label': error ?? failureClass, 'retrieved_at': fetchedAt},
  ],
  'macro_values': {},
  'retrieval_test': _retrieval(
    sourceName.toLowerCase(),
    '$sourceName.refresh',
    failureClass,
    error,
  ),
};

Map<String, dynamic> _retrieval(
  String provider,
  String capabilityId,
  String status, [
  String? error,
]) => {
  'provider': provider,
  'interface_id': 'macro.factor_radar',
  'capability_id': capabilityId,
  'candidate_schema': 'market_moving_factor_v1',
  'status': status,
  'error': error,
};

Map<String, dynamic> _newsFactorRow(
  Map<String, dynamic> row,
  String fetchedAt,
) {
  final title = '${row['title'] ?? 'Macro news factor'}';
  final summary =
      '${row['summary'] ?? row['content'] ?? 'Cached finance news row promoted as macro narrative evidence.'}';
  return {
    'factor_id':
        'news:cached:${_stableId(title)}:${row['published_at'] ?? row['fetched_at'] ?? fetchedAt}',
    'family': 'narrative_attention',
    'title': title,
    'summary': summary,
    'source_name': row['source'] ?? row['publisher'] ?? 'finance_news',
    'source_url': row['url'],
    'source_type': 'cached_finance_news',
    'source_published_at': row['published_at'],
    'fetched_at': fetchedAt,
    'event_at': row['published_at'],
    'affected_assets': <String>[],
    'affected_regions': [],
    'affected_sectors': [],
    'transmission_channels': <String>[],
    'expected_direction': 'unknown',
    'severity': 'medium',
    'confidence': 'unassessed',
    'status': 'watch',
    'evidence_items': [
      {'label': title, 'source_url': row['url'], 'retrieved_at': fetchedAt},
    ],
    'macro_values': {},
    'retrieval_test': _retrieval(
      'finance_news',
      'finance_news.cached_macro_readback',
      'ok',
    ),
    'raw_json': row,
  };
}

num? _parseNumber(Object? value) {
  return num.tryParse('${value ?? ''}'.replaceAll(',', '').trim());
}

String _stableId(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return 'row';
  return slug.length > 80 ? slug.substring(0, 80) : slug;
}
