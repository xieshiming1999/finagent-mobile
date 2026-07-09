const List<Map<String, dynamic>> macroNumericSeriesCatalogRows = [
  {
    'id': 'fred.DGS10',
    'provider': 'fred',
    'sourceName': 'FRED',
    'seriesId': 'DGS10',
    'metricName': 'US 10Y Treasury yield',
    'family': 'rates_liquidity',
    'region': 'United States',
    'assets': ['rates', 'bonds', 'equities', 'USD'],
    'frequency': 'daily',
    'unit': 'percent',
    'credentialRequired': true,
    'credentialKey': 'FRED_API_KEY',
    'status': 'credential-gated',
    'sourceUrl': 'https://api.stlouisfed.org/fred/series/observations',
    'nextAction': 'Configure FRED_API_KEY or use local readback if rows exist.',
  },
  {
    'id': 'bls.CUUR0000SA0',
    'provider': 'bls',
    'sourceName': 'BLS',
    'seriesId': 'CUUR0000SA0',
    'metricName': 'US CPI-U all items',
    'family': 'inflation',
    'region': 'United States',
    'assets': ['rates', 'bonds', 'equities', 'USD'],
    'frequency': 'monthly',
    'unit': 'index',
    'credentialRequired': false,
    'credentialKey': null,
    'status': 'supported',
    'sourceUrl': 'https://api.bls.gov/publicAPI/v2/timeseries/data/',
    'nextAction': 'Use macro factor refresh or local numeric readback.',
  },
  {
    'id': 'bea.NIPA.T10101',
    'provider': 'bea',
    'sourceName': 'BEA',
    'seriesId': 'NIPA:T10101',
    'metricName': 'US GDP and national income account headline table',
    'family': 'growth',
    'region': 'United States',
    'assets': ['equities', 'rates', 'USD'],
    'frequency': 'quarterly',
    'unit': 'varies by line',
    'credentialRequired': true,
    'credentialKey': 'BEA_API_KEY',
    'status': 'credential-gated',
    'sourceUrl': 'https://apps.bea.gov/api/data/',
    'nextAction':
        'Configure BEA_API_KEY in settings or ~/.fin_electron/bea.txt.',
  },
  {
    'id': 'world_bank.NY.GDP.MKTP.CD',
    'provider': 'world_bank',
    'sourceName': 'World Bank',
    'seriesId': 'NY.GDP.MKTP.CD',
    'metricName': 'GDP current US dollars',
    'family': 'growth',
    'region': 'global',
    'assets': ['equities', 'country risk', 'FX'],
    'frequency': 'annual',
    'unit': r'current US$',
    'credentialRequired': false,
    'credentialKey': null,
    'status': 'supported',
    'sourceUrl':
        'https://api.worldbank.org/v2/country/all/indicator/NY.GDP.MKTP.CD',
    'nextAction': 'Use macro factor refresh or local numeric readback.',
  },
  {
    'id': 'imf.NGDP_RPCH.USA',
    'provider': 'imf',
    'sourceName': 'IMF',
    'seriesId': 'NGDP_RPCH',
    'metricName': 'Real GDP growth forecast',
    'family': 'growth',
    'region': 'global',
    'assets': ['equities', 'country risk', 'FX'],
    'frequency': 'annual',
    'unit': 'percent change',
    'credentialRequired': false,
    'credentialKey': null,
    'status': 'supported',
    'sourceUrl': 'https://www.imf.org/external/datamapper/api/v1/NGDP_RPCH',
    'nextAction': 'Use IMF DataMapper refresh or local numeric readback.',
  },
  {
    'id': 'oecd.DF_QNA_EXPENDITURE_GROWTH_OECD.B1GQ',
    'provider': 'oecd',
    'sourceName': 'OECD',
    'seriesId': 'DF_QNA_EXPENDITURE_GROWTH_OECD:B1GQ:OECD:GCM',
    'metricName': 'OECD quarterly real GDP growth',
    'family': 'growth',
    'region': 'global',
    'assets': ['equities', 'country risk', 'FX', 'rates'],
    'frequency': 'quarterly',
    'unit': 'percent',
    'credentialRequired': false,
    'credentialKey': null,
    'status': 'supported',
    'sourceUrl':
        'https://sdmx.oecd.org/public/rest/v1/data/OECD.SDD.NAD,DSD_NAMAIN1@DF_QNA_EXPENDITURE_GROWTH_OECD',
    'nextAction': 'Use macro factor refresh or local numeric readback.',
  },
  {
    'id': 'eia.WCESTUS1',
    'provider': 'eia',
    'sourceName': 'EIA',
    'seriesId': 'WCESTUS1',
    'metricName': 'US commercial crude oil inventories',
    'family': 'commodities_energy',
    'region': 'United States',
    'assets': ['oil', 'energy equities', 'inflation'],
    'frequency': 'weekly',
    'unit': 'thousand barrels',
    'credentialRequired': true,
    'credentialKey': 'EIA_API_KEY',
    'status': 'credential-gated',
    'sourceUrl': 'https://api.eia.gov/v2/petroleum/stoc/wstk/data/',
    'nextAction': 'Configure EIA_API_KEY before live EIA v2 refresh.',
  },
  {
    'id': 'nbs_china.NBS_EASYQUERY_PENDING',
    'provider': 'nbs_china',
    'sourceName': 'NBS China',
    'seriesId': 'NBS_EASYQUERY_PENDING',
    'metricName':
        'China official numeric series pending stable public contract',
    'family': 'china_statistics',
    'region': 'China',
    'assets': ['A-shares', 'China rates', 'CNH', 'commodities'],
    'frequency': 'varies',
    'unit': null,
    'credentialRequired': false,
    'credentialKey': null,
    'status': 'security-control',
    'sourceUrl': 'https://data.stats.gov.cn/easyquery.htm',
    'nextAction':
        'Use NBS official public pages or browser/manual evidence until a stable API contract is verified.',
  },
  {
    'id': 'wind.cached.economic_series',
    'provider': 'wind',
    'sourceName': 'Wind',
    'seriesId': 'wind_economic_series',
    'metricName': 'Wind economic series cache/readback',
    'family': 'professional_macro',
    'region': 'China/global',
    'assets': ['equities', 'rates', 'funds', 'commodities'],
    'frequency': 'varies',
    'unit': 'varies',
    'credentialRequired': true,
    'credentialKey': 'WIND_API_KEY',
    'status': 'credential-gated',
    'sourceUrl': null,
    'nextAction':
        'Use cached Wind rows first; live refresh requires configured Wind access.',
  },
];

Map<String, dynamic> macroNumericSeriesCatalog(Map<String, dynamic> input) {
  final provider = _clean(input['provider'] ?? input['source']);
  final seriesId = _clean(
    input['seriesId'] ?? input['target'] ?? input['query'],
  );
  final family = _clean(input['family']);
  final status = _clean(input['status']);
  final rows = macroNumericSeriesCatalogRows
      .where((row) {
        if (provider != null &&
            !_matches(row['provider'], provider) &&
            !_matches(row['sourceName'], provider)) {
          return false;
        }
        if (seriesId != null &&
            !_matches(row['seriesId'], seriesId) &&
            !_matches(row['metricName'], seriesId)) {
          return false;
        }
        if (family != null && !_matches(row['family'], family)) return false;
        if (status != null && !_matches(row['status'], status)) return false;
        return true;
      })
      .take(_limit(input['limit'], 80))
      .toList();
  return {
    'action': 'macro_numeric_series_catalog',
    'count': rows.length,
    'status': rows.isEmpty ? 'missing' : 'ok',
    if (rows.isEmpty)
      'missingReason':
          'No official numeric macro series catalog rows matched the requested provider/series/family/status filters. Treat this as a catalog gap, not as evidence the macro topic is irrelevant.',
    'provenance': {
      'interfaceId': 'macro.official_series',
      'providerId': 'local',
      'provider': 'local',
      'capabilityId': 'local.macro_numeric_series_catalog',
      'providerMode': 'catalog-readback',
      'cacheStatus': 'bundled-catalog',
      'cacheDecision':
          'inspect official numeric macro series availability before refresh or readback',
      'canonicalSchema': 'market_moving_factor_v1',
      'canonicalTable': 'market_moving_factor',
      'readbackAction': 'query_macro_numeric_series',
      'source': 'bundled official numeric macro series catalog',
      'fetchedAt': DateTime.now().toUtc().toIso8601String(),
    },
    'guidance': {
      'readbackRule':
          'Use query_macro_numeric_series for local rows. Use refresh only when the catalog status and credentials allow it.',
      'separationRule':
          'Official numeric series are facts; research articles explain interpretation and expectations. Do not infer numeric observations from prose.',
    },
    'rows': rows,
  };
}

String? _clean(Object? value) {
  final text = '${value ?? ''}'.trim();
  return text.isEmpty ? null : text;
}

bool _matches(Object? value, String needle) {
  return '${value ?? ''}'.toLowerCase().contains(needle.toLowerCase());
}

int _limit(Object? value, int fallback) {
  if (value is num) return value.toInt().clamp(1, 500);
  return int.tryParse('${value ?? ''}')?.clamp(1, 500) ?? fallback;
}
