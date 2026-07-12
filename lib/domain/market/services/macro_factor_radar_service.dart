import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../shared/api_config.dart';
import 'macro_numeric_series_catalog.dart';
import 'macro_research_source_catalog_data.dart';

class MacroFactorRadarResult {
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> sources;
  final List<Map<String, dynamic>> numericSeriesCatalog;
  final String generatedAt;
  final String? error;

  const MacroFactorRadarResult({
    required this.rows,
    required this.sources,
    this.numericSeriesCatalog = const [],
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
    final macroEvidence = _extractSourceReaderMacroEvidence(generatedAt);
    if (macroEvidence.rows.isNotEmpty) {
      store.saveMarketMovingFactors(macroEvidence.rows);
    }
    final existing = store.queryMarketMovingFactors(limit: 80);
    if (existing.isNotEmpty) {
      return MacroFactorRadarResult(
        rows: existing,
        sources: [..._sourceRegistrySnapshot(), macroEvidence.source],
        numericSeriesCatalog: _numericSeriesCatalogSnapshot(),
        generatedAt: generatedAt,
      );
    }
    store.saveMarketMovingFactors(_seedRows(generatedAt));
    return MacroFactorRadarResult(
      rows: store.queryMarketMovingFactors(limit: 80),
      sources: [..._sourceRegistrySnapshot(), macroEvidence.source],
      numericSeriesCatalog: _numericSeriesCatalogSnapshot(),
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

    final officialResults = await Future.wait([
      _fetchFred(generatedAt),
      _fetchBls(generatedAt),
      _fetchBea(generatedAt),
      _fetchWorldBank(generatedAt),
      _fetchImf(generatedAt),
      _fetchOecd(generatedAt),
      _fetchEia(generatedAt),
      _fetchNbsChina(generatedAt),
    ]);
    for (final result in officialResults) {
      rows.addAll(result.rows);
      sources.add(result.source);
    }

    final wind = _readCachedWindFactors(generatedAt);
    rows.addAll(wind.rows);
    sources.add(wind.source);

    final news = _readCachedNewsFactors(generatedAt);
    rows.addAll(news.rows);
    sources.add(news.source);

    final macroEvidence = _extractSourceReaderMacroEvidence(generatedAt);
    rows.addAll(macroEvidence.rows);
    sources.add(macroEvidence.source);

    store.saveMarketMovingFactors(rows);
    return MacroFactorRadarResult(
      rows: store.queryMarketMovingFactors(limit: 80),
      sources: sources,
      numericSeriesCatalog: _numericSeriesCatalogSnapshot(),
      generatedAt: generatedAt,
    );
  }

  List<Map<String, dynamic>> _numericSeriesCatalogSnapshot() {
    final result = macroNumericSeriesCatalog(const {'limit': 80});
    final rows = result['rows'];
    return rows is List
        ? rows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];
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

  Future<_FetchResult> _fetchWorldBank(String fetchedAt) async {
    final uri = Uri.https(
      'api.worldbank.org',
      '/v2/country/US/indicator/NY.GDP.MKTP.CD',
      {'format': 'json', 'per_page': '2'},
    );
    try {
      final json = await _getJsonList(uri);
      final metadata = json.isNotEmpty && json.first is Map
          ? json.first as Map
          : const <String, dynamic>{};
      final data = json.length > 1 && json[1] is List ? json[1] as List : [];
      final point = data.cast<Object?>().whereType<Map>().firstWhere(
        (row) => row['value'] != null,
        orElse: () => data.isNotEmpty && data.first is Map
            ? data.first as Map
            : const <String, dynamic>{},
      );
      final date = point['date']?.toString();
      return _FetchResult(
        rows: [
          {
            'factor_id':
                'world_bank:macro_series:NY.GDP.MKTP.CD:${date ?? fetchedAt.substring(0, 10)}',
            'family': 'macro_series',
            'title': 'US GDP current US\$ World Bank observation',
            'summary':
                'World Bank GDP current US\$ is official numeric growth evidence for cross-country macro and broad equity/rates analysis.',
            'source_name': 'World Bank',
            'source_url':
                'https://api.worldbank.org/v2/country/US/indicator/NY.GDP.MKTP.CD',
            'source_type': 'official_api',
            'source_published_at': metadata['lastupdated'] ?? date,
            'fetched_at': fetchedAt,
            'event_at': date,
            'affected_assets': [
              'US equities',
              'global equities',
              'Treasury yields',
              'USD',
              'cyclical sectors',
            ],
            'affected_regions': ['United States', 'Global'],
            'affected_sectors': ['Cyclicals'],
            'transmission_channels': [
              'growth level',
              'earnings expectations',
              'cross-country macro comparison',
            ],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label':
                    'NY.GDP.MKTP.CD ${date ?? '-'} = ${point['value'] ?? '-'}',
                'source_url':
                    'https://data.worldbank.org/indicator/NY.GDP.MKTP.CD?locations=US',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': _parseNumber(point['value']),
              'unit': 'current US\$',
              'period': date,
              'frequency': 'annual',
              'lastUpdated': metadata['lastupdated'],
            },
            'retrieval_test': _retrieval(
              'world_bank',
              'world_bank.indicator.NY.GDP.MKTP.CD',
              'ok',
            ),
            'raw_json': point,
          },
        ],
        source: {
          'id': 'world_bank',
          'name': 'World Bank API',
          'state': 'ok',
          'detail': 'US GDP current US\$ latest row retrieved.',
        },
      );
    } catch (e) {
      return _sourceFailure(
        'world_bank',
        'World Bank API',
        'macro_series',
        'World Bank GDP retrieval failed',
        fetchedAt,
        e,
      );
    }
  }

  Future<_FetchResult> _fetchImf(String fetchedAt) async {
    final uri = Uri.https(
      'www.imf.org',
      '/external/datamapper/api/v1/NGDP_RPCH/USA',
    );
    try {
      final json = await _getJson(uri);
      final values = json['values']?['NGDP_RPCH']?['USA'];
      final point = _latestNumericEntry(values);
      return _FetchResult(
        rows: [
          {
            'factor_id':
                'imf:macro_series:NGDP_RPCH:USA:${point?['period'] ?? fetchedAt.substring(0, 10)}',
            'family': 'macro_series',
            'title': 'US real GDP growth IMF DataMapper observation',
            'summary':
                'IMF real GDP growth is official numeric growth evidence for cross-country macro and broad asset-allocation analysis.',
            'source_name': 'IMF',
            'source_url':
                'https://www.imf.org/external/datamapper/api/v1/NGDP_RPCH/USA',
            'source_type': 'official_api',
            'source_published_at': point?['period'],
            'fetched_at': fetchedAt,
            'event_at': point?['period'],
            'affected_assets': [
              'US equities',
              'global equities',
              'Treasury yields',
              'USD',
              'cyclical sectors',
            ],
            'affected_regions': ['United States', 'Global'],
            'affected_sectors': ['Cyclicals'],
            'transmission_channels': [
              'growth momentum',
              'cross-country macro comparison',
              'policy expectation',
            ],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label':
                    'NGDP_RPCH USA ${point?['period'] ?? '-'} = ${point?['value'] ?? '-'}',
                'source_url':
                    'https://www.imf.org/external/datamapper/NGDP_RPCH@WEO/USA',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': point?['value'],
              'unit': 'percent change',
              'period': point?['period'],
              'frequency': 'annual',
            },
            'retrieval_test': _retrieval(
              'imf',
              'imf.datamapper.NGDP_RPCH.USA',
              'ok',
            ),
            'raw_json': {
              'indicator': 'NGDP_RPCH',
              'country': 'USA',
              'period': point?['period'],
              'value': point?['value'],
            },
          },
        ],
        source: {
          'id': 'imf',
          'name': 'IMF DataMapper API',
          'state': 'ok',
          'detail': 'US real GDP growth latest row retrieved.',
        },
      );
    } catch (e) {
      return _sourceFailure(
        'imf',
        'IMF DataMapper API',
        'macro_series',
        'IMF real GDP growth retrieval failed',
        fetchedAt,
        e,
      );
    }
  }

  Future<_FetchResult> _fetchOecd(String fetchedAt) async {
    final uri = Uri.https(
      'sdmx.oecd.org',
      '/public/rest/v1/data/OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA_EXPENDITURE_GROWTH_OECD',
      {
        'startPeriod': '2024-Q1',
        'endPeriod': '2026-Q4',
        'firstNObservations': '20',
      },
    );
    try {
      final json = await _getJsonWithHeaders(uri, const {
        'Accept': 'application/vnd.sdmx.data+json; version=2.0',
        'Accept-Language': 'en',
        'User-Agent': 'Mozilla/5.0',
      });
      final point = _extractOecdGrowthObservation(json);
      if (point == null) {
        throw const FormatException(
          'OECD SDMX response did not include the governed B1GQ OECD growth series.',
        );
      }
      final period = point['period']?.toString();
      final value = point['value'];
      return _FetchResult(
        rows: [
          {
            'factor_id':
                'oecd:macro_series:DF_QNA_EXPENDITURE_GROWTH_OECD:OECD:${period ?? fetchedAt.substring(0, 10)}',
            'family': 'macro_series',
            'title': 'OECD quarterly real GDP growth observation',
            'summary':
                'OECD quarterly real GDP growth is official numeric growth evidence for cross-country macro, country-risk, rates, FX, and equity analysis.',
            'source_name': 'OECD',
            'source_url': uri.toString(),
            'source_type': 'official_api',
            'source_published_at': period,
            'fetched_at': fetchedAt,
            'event_at': period,
            'affected_assets': [
              'global equities',
              'country risk',
              'FX',
              'rates',
            ],
            'affected_regions': ['OECD', 'Global'],
            'affected_sectors': ['Cyclicals'],
            'transmission_channels': [
              'growth momentum',
              'cross-country macro comparison',
              'risk appetite',
            ],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label':
                    'DF_QNA_EXPENDITURE_GROWTH_OECD B1GQ OECD ${period ?? '-'} = ${value ?? '-'}',
                'source_url': uri.toString(),
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': value,
              'unit': 'percent',
              'period': period,
              'frequency': 'quarterly',
              'transformation': 'GCM',
              'seriesId': 'DF_QNA_EXPENDITURE_GROWTH_OECD:B1GQ:OECD:GCM',
            },
            'retrieval_test': _retrieval(
              'oecd',
              'oecd.sdmx.DF_QNA_EXPENDITURE_GROWTH_OECD.B1GQ',
              'ok',
            ),
            'raw_json': point['raw'],
          },
        ],
        source: {
          'id': 'oecd',
          'name': 'OECD SDMX API',
          'state': 'ok',
          'detail':
              'OECD quarterly real GDP growth latest row retrieved from official SDMX JSON.',
        },
      );
    } catch (e) {
      return _sourceFailure(
        'oecd',
        'OECD SDMX API',
        'macro_series',
        'OECD quarterly real GDP growth retrieval failed',
        fetchedAt,
        e,
      );
    }
  }

  Future<_FetchResult> _fetchEia(String fetchedAt) async {
    final key = apiConfig?.get('EIA_API_KEY')?.trim();
    if (key == null || key.isEmpty) {
      return _FetchResult(
        rows: [
          _failureRow(
            'eia:macro_series:WCESTUS1:credential',
            'macro_series',
            'EIA API key missing',
            'EIA',
            'credential_missing',
            fetchedAt,
            'EIA_API_KEY is required for official EIA v2 data calls.',
          ),
        ],
        source: {
          'id': 'eia',
          'name': 'EIA API',
          'state': 'credential-gated',
          'detail': 'EIA_API_KEY is required for official EIA v2 data calls.',
        },
      );
    }
    final uri = Uri.https('api.eia.gov', '/v2/petroleum/stoc/wstk/data/', {
      'api_key': key,
      'frequency': 'weekly',
      'data[0]': 'value',
      'facets[series][]': 'WCESTUS1',
      'sort[0][column]': 'period',
      'sort[0][direction]': 'desc',
      'offset': '0',
      'length': '1',
    });
    try {
      final json = await _getJson(uri);
      final data = json['response']?['data'];
      final point = data is List && data.isNotEmpty
          ? data.first as Map
          : const <String, dynamic>{};
      final period = point['period']?.toString();
      return _FetchResult(
        rows: [
          {
            'factor_id':
                'eia:macro_series:WCESTUS1:${period ?? fetchedAt.substring(0, 10)}',
            'family': 'macro_series',
            'title': 'US commercial crude oil inventories EIA observation',
            'summary':
                'EIA weekly petroleum stocks are official numeric energy inventory evidence for oil, inflation, energy equities, and commodity-sensitive macro analysis.',
            'source_name': 'EIA',
            'source_url': 'https://api.eia.gov/v2/petroleum/stoc/wstk/data/',
            'source_type': 'official_api',
            'source_published_at': period,
            'fetched_at': fetchedAt,
            'event_at': period,
            'affected_assets': [
              'oil',
              'energy equities',
              'inflation expectations',
              'commodity currencies',
            ],
            'affected_regions': ['United States', 'Global'],
            'affected_sectors': ['Energy'],
            'transmission_channels': [
              'energy inventory',
              'oil supply demand',
              'inflation input',
            ],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label': 'WCESTUS1 ${period ?? '-'} = ${point['value'] ?? '-'}',
                'source_url':
                    'https://www.eia.gov/dnav/pet/pet_stoc_wstk_dcu_nus_w.htm',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': _parseNumber(point['value']),
              'unit': point['units'] ?? 'thousand barrels',
              'period': period,
              'frequency': 'weekly',
            },
            'retrieval_test': _retrieval(
              'eia',
              'eia.petroleum.stoc.wstk.WCESTUS1',
              'ok',
            ),
            'raw_json': point,
          },
        ],
        source: {
          'id': 'eia',
          'name': 'EIA API',
          'state': 'ok',
          'detail': 'US weekly crude inventory latest row retrieved.',
        },
      );
    } catch (e) {
      return _sourceFailure(
        'eia',
        'EIA API',
        'macro_series',
        'EIA weekly crude inventory retrieval failed',
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

  Future<Map<String, dynamic>> _getJsonWithHeaders(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final response = await _http
        .get(uri, headers: headers)
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Map<String, dynamic>? _latestNumericEntry(Object? values) {
    if (values is! Map) return null;
    final entries =
        values.entries
            .map((entry) {
              final value = _parseNumber(entry.value);
              if (value == null) return null;
              return {'period': '${entry.key}', 'value': value};
            })
            .whereType<Map<String, dynamic>>()
            .toList()
          ..sort(
            (a, b) => num.parse(
              '${a['period']}',
            ).compareTo(num.parse('${b['period']}')),
          );
    return entries.isEmpty ? null : entries.last;
  }

  Future<List<dynamic>> _getJsonList(Uri uri) async {
    final response = await _http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as List<dynamic>;
  }

  Map<String, dynamic>? _extractOecdGrowthObservation(
    Map<String, dynamic> json,
  ) {
    final data = json['data'] is Map ? json['data'] as Map : json;
    final dataSets = data['dataSets'];
    final structures = data['structures'];
    if (dataSets is! List ||
        dataSets.isEmpty ||
        dataSets.first is! Map ||
        structures is! List ||
        structures.isEmpty ||
        structures.first is! Map) {
      return null;
    }
    final dataSet = dataSets.first as Map;
    final structure = structures.first as Map;
    final dimensions = structure['dimensions'];
    if (dimensions is! Map) return null;
    final seriesDims = dimensions['series'];
    final observationDims = dimensions['observation'];
    if (seriesDims is! List || observationDims is! List) return null;
    final timeDim = observationDims.whereType<Map>().firstWhere(
      (dim) => dim['id'] == 'TIME_PERIOD',
      orElse: () => observationDims.first is Map
          ? observationDims.first as Map
          : const <String, dynamic>{},
    );
    final timeValues = timeDim['values'];
    final series = dataSet['series'];
    if (timeValues is! List || series is! Map) return null;

    for (final entry in series.entries) {
      final key = '${entry.key}';
      final parts = key.split(':');
      final byDim = <String, String>{};
      for (var i = 0; i < parts.length && i < seriesDims.length; i++) {
        final dim = seriesDims[i];
        if (dim is! Map) continue;
        final values = dim['values'];
        final index = int.tryParse(parts[i]);
        if (values is! List || index == null || index >= values.length) {
          continue;
        }
        final value = values[index];
        if (value is Map) {
          byDim['${dim['id'] ?? i}'] = '${value['id'] ?? value['name'] ?? ''}';
        }
      }
      if (byDim['FREQ'] != 'Q' ||
          byDim['ADJUSTMENT'] != 'Y' ||
          byDim['REF_AREA'] != 'OECD' ||
          byDim['SECTOR'] != 'S1' ||
          byDim['COUNTERPART_SECTOR'] != 'S1' ||
          byDim['TRANSACTION'] != 'B1GQ' ||
          byDim['UNIT_MEASURE'] != 'PC' ||
          byDim['TRANSFORMATION'] != 'GCM' ||
          byDim['TABLE_IDENTIFIER'] != 'T0102') {
        continue;
      }
      final seriesRow = entry.value;
      if (seriesRow is! Map || seriesRow['observations'] is! Map) {
        return null;
      }
      final points = <Map<String, dynamic>>[];
      for (final observation in (seriesRow['observations'] as Map).entries) {
        final obsKey = '${observation.key}'.split(':').first;
        final timeIndex = int.tryParse(obsKey);
        if (timeIndex == null || timeIndex >= timeValues.length) continue;
        final timeValue = timeValues[timeIndex];
        final period = timeValue is Map
            ? '${timeValue['id'] ?? timeValue['name'] ?? ''}'
            : null;
        final rawList = observation.value is List
            ? observation.value as List
            : null;
        final rawValue = rawList == null
            ? observation.value
            : (rawList.isEmpty ? null : rawList.first);
        final value = _parseNumber(rawValue);
        if (period == null || period.isEmpty || value == null) continue;
        points.add({
          'period': period,
          'value': value,
          'raw': {
            'seriesKey': key,
            'dimensions': byDim,
            'observationKey': observation.key,
            'value': rawValue,
          },
        });
      }
      points.sort((a, b) => '${a['period']}'.compareTo('${b['period']}'));
      return points.isEmpty ? null : points.last;
    }
    return null;
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

  Future<_FetchResult> _fetchNbsChina(String fetchedAt) async {
    const message =
        'NBS China official entry pages are validated, but current EasyQuery numeric API probes returned HTTP 403 UrlACL from this environment. Keep China official numeric series as browser/manual or future source-specific adapter evidence until a stable public table/API contract is verified.';
    return _FetchResult(
      rows: [
        _failureRow(
          'nbs_china:macro_series:easyquery:security_control',
          'macro_series',
          'NBS China official numeric series access requires source-specific validation',
          'NBS China',
          'security_control',
          fetchedAt,
          message,
        ),
      ],
      source: {
        'id': 'nbs_china',
        'name': 'National Bureau of Statistics of China',
        'state': 'security-control',
        'detail': message,
      },
    );
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

  _FetchResult _extractSourceReaderMacroEvidence(String fetchedAt) {
    final dir = Directory('${store.basePath}/memory/macro_evidence');
    if (!dir.existsSync()) {
      return _FetchResult(
        rows: const [],
        source: {
          'id': 'source_reader.macro_evidence',
          'name': 'SourceReader macro evidence artifacts',
          'state': 'fallback-only',
          'detail':
              'No memory/macro_evidence directory is currently available.',
        },
      );
    }
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort(
            (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
          );
    final rows = <Map<String, dynamic>>[];
    for (final file in files.take(20)) {
      try {
        final decoded = jsonDecode(file.readAsStringSync());
        if (decoded is! Map) continue;
        final row = _sourceReaderMacroRecordToFactorRow(
          Map<String, dynamic>.from(decoded),
          file.path,
          fetchedAt,
        );
        if (row != null) rows.add(row);
      } catch (_) {
        // Skip unreadable evidence artifacts; malformed records are not reusable.
      }
    }
    return _FetchResult(
      rows: rows,
      source: {
        'id': 'source_reader.macro_evidence',
        'name': 'SourceReader macro evidence artifacts',
        'state': rows.isNotEmpty ? 'ok' : 'fallback-only',
        'detail': rows.isNotEmpty
            ? '${rows.length} durable macro evidence artifact(s) promoted into the macro research surface.'
            : 'No readable macro-evidence-record-v1 artifacts are currently available.',
      },
    );
  }

  Map<String, dynamic>? _sourceReaderMacroRecordToFactorRow(
    Map<String, dynamic> record,
    String filePath,
    String fetchedAt,
  ) {
    if (record['contract'] != 'macro-evidence-record-v1') return null;
    final numeric = record['numericSeries'] is Map
        ? Map<String, dynamic>.from(record['numericSeries'] as Map)
        : <String, dynamic>{};
    final sourceName = _firstString([
      record['source'],
      record['provider'],
      'SourceReader',
    ]);
    final sourceDate = _firstString([
      record['sourceDate'],
      numeric['sourceDataTime'],
    ]);
    final fetched = _firstString([
      record['fetchedAt'],
      numeric['fetchedAt'],
      fetchedAt,
    ]);
    final title = _firstString([record['title'], '$sourceName macro evidence']);
    final affectedAssets = _macroEvidenceStringList(record['affectedAssets']);
    final keyClaims = _macroEvidenceStringList(record['keyClaims']);
    final missingEvidence = _macroEvidenceStringList(record['missingEvidence']);
    final evidenceClass = _stringValue(record['evidenceClass']);
    final sourceUrl = _stringValue(record['url']);
    final evidenceId = _stringValue(record['id']);
    return {
      'factor_id':
          'source_reader:${_stableId(evidenceId.isEmpty ? title : evidenceId)}',
      'family': evidenceClass.isNotEmpty ? evidenceClass : 'macro_evidence',
      'title': title,
      'summary': keyClaims.isNotEmpty
          ? keyClaims.join(' ')
          : 'Durable SourceReader macro evidence artifact.',
      'source_name': sourceName,
      'source_url': sourceUrl.isEmpty ? null : sourceUrl,
      'source_type': evidenceClass.isNotEmpty
          ? evidenceClass
          : 'source_reader_macro_evidence',
      'evidence_tier': evidenceClass.isNotEmpty
          ? evidenceClass
          : 'governed_macro_evidence',
      'source_published_at': sourceDate.isEmpty ? null : sourceDate,
      'fetched_at': fetched,
      'event_at': sourceDate.isEmpty ? null : sourceDate,
      'affected_assets': affectedAssets,
      'affected_regions': _macroEvidenceStringList(record['region']),
      'affected_sectors': const <String>[],
      'transmission_channels': _macroEvidenceStringList(record['assetClass']),
      'expected_direction': 'mixed',
      'severity': 'medium',
      'confidence': _confidenceFromMacroEvidenceRecord(record),
      'access_status': sourceUrl.isNotEmpty
          ? 'public-or-recorded'
          : 'artifact-readback',
      'freshness_status': _firstString([record['freshness'], 'unknown']),
      'confidence_effect': _firstString([
        record['confidenceEffect'],
        'requires evidence review',
      ]),
      'missing_evidence': missingEvidence.join('; '),
      'next_evidence_action': missingEvidence.isNotEmpty
          ? 'refresh or attach higher-tier evidence'
          : 'use artifact/readback',
      'asset_impact': affectedAssets.isNotEmpty ? 'linked' : 'needs-linking',
      'status': 'active',
      'limitations': [
        ...missingEvidence,
        'Macro evidence is context, hypothesis, and invalidation input, not a direct buy/sell rule.',
      ],
      'linked_macro_evidence_ids': [if (evidenceId.isNotEmpty) evidenceId],
      'evidence_items': [
        {
          'label': keyClaims.isNotEmpty ? keyClaims.first : title,
          'source_url': sourceUrl.isEmpty ? null : sourceUrl,
          'retrieved_at': fetched,
        },
      ],
      'macro_values': {
        'evidenceTier': evidenceClass.isNotEmpty
            ? evidenceClass
            : 'governed_macro_evidence',
        'evidenceClass': record['evidenceClass'],
        'confidenceEffect': record['confidenceEffect'],
        'sourceRecordPath': record['sourceRecordPath'],
        'artifactPath': filePath,
        'missingEvidence': missingEvidence,
        'limitations': [
          ...missingEvidence,
          'Macro evidence is context, hypothesis, and invalidation input, not a direct buy/sell rule.',
        ],
        'linkedMacroEvidenceIds': [if (evidenceId.isNotEmpty) evidenceId],
        'assetImpact': affectedAssets.isNotEmpty ? 'linked' : 'needs-linking',
        'numericSeries': numeric,
      },
      'retrieval_test': _retrieval(
        'source_reader',
        'source_reader.macro_evidence.readback',
        'ok',
      ),
      'raw_json': record,
    };
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

List<Map<String, dynamic>> _sourceRegistrySnapshot() =>
    macroResearchSourceCatalog
        .map(
          (source) => {
            'id': source['id'],
            'name': source['providerName'],
            'state': _sourceState(source),
            'detail': [
              source['evidenceValue'],
              source['accessClass'],
              source['testedStatus'],
              source['nextAction'],
            ].whereType<Object>().join(' · '),
          },
        )
        .toList();

String _sourceState(Map<String, Object?> source) {
  final access = source['accessClass']?.toString() ?? '';
  final tested = source['testedStatus']?.toString() ?? '';
  if (access.contains('anti-bot') ||
      access.contains('manual') ||
      access.contains('security') ||
      access.contains('licensed')) {
    return 'manual-or-gated';
  }
  if (tested.contains('needs-live-validation')) return 'needs-validation';
  if (tested.contains('ok') ||
      tested.contains('readable') ||
      access.contains('official-api')) {
    return 'available';
  }
  return 'cataloged';
}

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
    'evidence_tier': 'linked_news_evidence',
    'limitations': [
      'Finance news is a current-event clue, not an official macro fact.',
      'Use official data or content-backed research before making a root-cause conclusion.',
    ],
    'linked_macro_evidence_ids': [],
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
    'macro_values': {
      'evidenceTier': 'linked_news_evidence',
      'limitation': 'news_clue_not_official_fact',
      'limitations': [
        'Finance news is a current-event clue, not an official macro fact.',
        'Use official data or content-backed research before making a root-cause conclusion.',
      ],
      'publisher': row['publisher'] ?? row['source'],
    },
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

String _stringValue(Object? value) => '${value ?? ''}'.trim();

String _firstString(List<Object?> values) {
  for (final value in values) {
    final text = _stringValue(value);
    if (text.isNotEmpty) return text;
  }
  return '';
}

List<String> _macroEvidenceStringList(Object? value) {
  if (value is List) {
    return value.map(_stringValue).where((item) => item.isNotEmpty).toList();
  }
  final text = _stringValue(value);
  if (text.isEmpty) return const [];
  return text
      .split(RegExp(r'[;,，、]'))
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

String _confidenceFromMacroEvidenceRecord(Map<String, dynamic> record) {
  final freshness = _stringValue(record['freshness']).toLowerCase();
  final evidenceClass = _stringValue(record['evidenceClass']).toLowerCase();
  if (evidenceClass.contains('official') && !freshness.contains('stale')) {
    return 'high';
  }
  if (freshness.contains('stale') || freshness.contains('missing')) {
    return 'low';
  }
  return 'medium';
}

String _stableId(String value) {
  final slug = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\u4e00-\u9fa5]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (slug.isEmpty) return 'row';
  return slug.length > 80 ? slug.substring(0, 80) : slug;
}
