import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/domain/market/services/market_data_action_service.dart';
import 'package:finagent/domain/market/services/macro_factor_radar_service.dart';
import 'package:finagent/domain/market/services/macro_research_extraction.dart';
import 'package:finagent/domain/market/services/macro_research_source_catalog_data.dart';
import 'package:finagent/shared/api_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('MacroFactorRadarService', () {
    test('seeds market_moving_factor_v1 rows with provenance', () {
      final dir = Directory.systemTemp.createTempSync('finagent_macro_factor_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final store = ReusableDataStore(dir.path);
      final service = MacroFactorRadarService(store: store);
      final result = service.read();

      expect(result.rows.length, greaterThanOrEqualTo(2));
      final msci = result.rows.firstWhere(
        (row) =>
            row['factor_id'] ==
            'manual:index_classification:msci:indonesia-watch',
      );
      expect(msci['family'], 'index_classification');
      expect(msci['source_name'], 'MSCI');
      expect(msci['source_type'], 'manual_seed');
      expect(msci['status'], 'watch');
      expect(msci['affected_assets'], contains('Indonesia equities'));
      expect(msci['transmission_channels'], contains('passive benchmark flow'));
      expect(msci['access_status'], 'public');
      expect(msci['freshness_status'], 'acceptable');
      expect(msci['confidence_effect'], 'mixed');
      expect(msci['next_evidence_action'], 'use cache/readback');
      expect(msci['asset_impact'], 'mixed');
      expect(msci['retrieval_test'], isA<Map>());
      expect(
        (msci['retrieval_test'] as Map)['candidate_schema'],
        'market_moving_factor_v1',
      );
    });

    test('promotes SourceReader macro evidence artifacts into radar rows', () {
      final dir = Directory.systemTemp.createTempSync('finagent_macro_factor_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final evidenceDir = Directory('${dir.path}/memory/macro_evidence')
        ..createSync(recursive: true);
      File('${evidenceDir.path}/macro_eia.json').writeAsStringSync(
        jsonEncode({
          'contract': 'macro-evidence-record-v1',
          'id': 'macro:eia-oil',
          'source': 'EIA',
          'provider': 'eia',
          'title': 'EIA official series WCESTUS1',
          'sourceDate': '2026-07-03',
          'topic': 'oil inventory pressure',
          'region': 'US/global',
          'assetClass': 'commodity/equity/fund',
          'keyClaims': [
            'US commercial crude oil inventories WCESTUS1 = 420000 MBBL as of 2026-07-03.',
          ],
          'affectedAssets': ['oil', 'energy equities', 'A-shares'],
          'confidenceEffect': 'Adds official inventory context.',
          'freshness': 'ok',
          'evidenceClass': 'official-numeric-series',
          'numericSeries': {
            'seriesId': 'WCESTUS1',
            'metricName': 'US commercial crude oil inventories',
            'value': 420000,
            'unit': 'MBBL',
            'sourceDataTime': '2026-07-03',
            'fetchedAt': '2026-07-12T02:00:00Z',
            'provider': 'eia',
            'status': 'ok',
          },
          'fetchedAt': '2026-07-12T02:00:00Z',
          'tradeBoundary':
              'Macro numeric evidence is context, hypothesis, and invalidation input. It is not a direct buy/sell rule.',
          'missingEvidence': ['No second official source attached.'],
        }),
      );

      final store = ReusableDataStore(dir.path);
      final result = MacroFactorRadarService(store: store).read();
      final row = result.rows.firstWhere(
        (item) => item['factor_id'] == 'source_reader:macro-eia-oil',
      );

      expect(row['family'], 'official-numeric-series');
      expect(row['title'], 'EIA official series WCESTUS1');
      expect(row['source_name'], 'EIA');
      expect(row['source_type'], 'official-numeric-series');
      expect(row['evidence_tier'], 'official-numeric-series');
      expect(row['source_published_at'], '2026-07-03');
      expect(row['fetched_at'], '2026-07-12T02:00:00Z');
      expect(row['status'], 'active');
      expect(row['asset_impact'], 'linked');
      expect(row['affected_assets'], ['oil', 'energy equities', 'A-shares']);
      expect(row['linked_macro_evidence_ids'], ['macro:eia-oil']);
      expect(
        (row['macro_values'] as Map)['artifactPath'],
        '${evidenceDir.path}/macro_eia.json',
      );
      expect(
        (row['macro_values'] as Map)['numericSeries'],
        containsPair('seriesId', 'WCESTUS1'),
      );
      expect(
        result.sources.firstWhere(
          (source) => source['id'] == 'source_reader.macro_evidence',
        )['state'],
        'ok',
      );
    });

    test(
      'promotes cached finance news as unclassified narrative observations',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final store = ReusableDataStore(dir.path);
        store.saveFinanceNews([
          {
            'news_id': 'macro-copper-news',
            'title': 'Copper supply report lifts miner attention',
            'summary':
                'Copper and commodity prices are reacting to a supply-demand research update.',
            'source': 'test-news',
            'published_at': DateTime.now()
                .subtract(const Duration(days: 1))
                .toUtc()
                .toIso8601String(),
            'url': 'https://example.test/copper',
          },
        ]);

        final service = MacroFactorRadarService(
          store: store,
          httpClient: MockClient((request) async {
            final url = request.url.toString();
            if (url.contains('api.bls.gov/publicAPI/v2/timeseries/data')) {
              return http.Response(
                jsonEncode({
                  'Results': {
                    'series': [
                      {
                        'data': [
                          {
                            'year': '2026',
                            'period': 'M06',
                            'periodName': 'June',
                            'value': '321.0',
                          },
                        ],
                      },
                    ],
                  },
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (url.contains(
              'api.worldbank.org/v2/country/US/indicator/NY.GDP.MKTP.CD',
            )) {
              return http.Response(
                jsonEncode([
                  {'lastupdated': '2026-07-01'},
                  [
                    {'date': '2025', 'value': 30769700000000},
                  ],
                ]),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (url.contains(
              'imf.org/external/datamapper/api/v1/NGDP_RPCH/USA',
            )) {
              return http.Response(
                jsonEncode({
                  'values': {
                    'NGDP_RPCH': {
                      'USA': {'2030': 1.7, '2031': 1.8},
                    },
                  },
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            if (url.contains(
              'sdmx.oecd.org/public/rest/v1/data/OECD.SDD.NAD',
            )) {
              return http.Response(
                jsonEncode({
                  'dataSets': [
                    {
                      'series': {
                        '0:0:0:0:0:0:0:0:0': {
                          'observations': {
                            '0': [1.2],
                          },
                        },
                      },
                    },
                  ],
                  'structures': [
                    {
                      'dimensions': {
                        'series': [
                          {
                            'id': 'FREQ',
                            'values': [
                              {'id': 'Q'},
                            ],
                          },
                          {
                            'id': 'ADJUSTMENT',
                            'values': [
                              {'id': 'Y'},
                            ],
                          },
                          {
                            'id': 'REF_AREA',
                            'values': [
                              {'id': 'OECD'},
                            ],
                          },
                          {
                            'id': 'SECTOR',
                            'values': [
                              {'id': 'S1'},
                            ],
                          },
                          {
                            'id': 'COUNTERPART_SECTOR',
                            'values': [
                              {'id': 'S1'},
                            ],
                          },
                          {
                            'id': 'TRANSACTION',
                            'values': [
                              {'id': 'B1GQ'},
                            ],
                          },
                          {
                            'id': 'UNIT_MEASURE',
                            'values': [
                              {'id': 'PC'},
                            ],
                          },
                          {
                            'id': 'TRANSFORMATION',
                            'values': [
                              {'id': 'GCM'},
                            ],
                          },
                          {
                            'id': 'TABLE_IDENTIFIER',
                            'values': [
                              {'id': 'T0102'},
                            ],
                          },
                        ],
                        'observation': [
                          {
                            'id': 'TIME_PERIOD',
                            'values': [
                              {'id': '2026-Q1'},
                            ],
                          },
                        ],
                      },
                    },
                  ],
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({'error': 'unexpected test URL'}),
              404,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final result = await service.refresh();
        final queryService = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        final row = result.rows.firstWhere(
          (item) => '${item['factor_id']}'.startsWith('news:cached:'),
        );
        expect(row['family'], 'narrative_attention');
        expect(row['source_type'], 'cached_finance_news');
        expect(row['evidence_tier'], 'linked_news_evidence');
        expect(row['source_name'], 'test-news');
        expect(row['status'], 'watch');
        expect(
          row['limitations'],
          contains(
            'Finance news is a current-event clue, not an official macro fact.',
          ),
        );
        expect(row['access_status'], 'public');
        expect(row['freshness_status'], 'fresh');
        expect(row['confidence_effect'], 'neutral');
        expect(row['next_evidence_action'], 'use cache/readback');
        expect(row['asset_impact'], 'no direct relevance');
        expect(row['affected_assets'], isEmpty);
        expect(row['confidence'], 'unassessed');
        expect(
          (row['macro_values'] as Map)['evidenceTier'],
          'linked_news_evidence',
        );
        expect(
          (row['macro_values'] as Map)['limitation'],
          'news_clue_not_official_fact',
        );
        expect(row['affected_assets'], isEmpty);
        expect((row['retrieval_test'] as Map)['provider'], 'finance_news');
        expect((row['retrieval_test'] as Map)['status'], 'ok');
        final attribution =
            await queryService.run('query_macro_attribution', const [], {
                  'target': 'Copper',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        final newsAttribution = (attribution['attributions'] as List)
            .cast<Map>()
            .firstWhere(
              (item) => (item['evidence'] as List).cast<Map>().any(
                (evidence) => evidence['sourceType'] == 'cached_finance_news',
              ),
            );
        final newsEvidence = (newsAttribution['evidence'] as List)
            .cast<Map>()
            .firstWhere(
              (evidence) => evidence['sourceType'] == 'cached_finance_news',
            );
        expect(newsEvidence['evidenceTier'], 'linked_news_evidence');
        expect(
          newsEvidence['limitations'],
          contains(
            'Finance news is a current-event clue, not an official macro fact.',
          ),
        );
        final worldBank = result.rows.firstWhere(
          (item) => '${item['factor_id']}'.startsWith(
            'world_bank:macro_series:NY.GDP.MKTP.CD:',
          ),
        );
        expect(worldBank['family'], 'macro_series');
        expect(worldBank['source_name'], 'World Bank');
        expect(worldBank['source_type'], 'official_api');
        expect(worldBank['status'], 'active');
        final imf = result.rows.firstWhere(
          (item) => '${item['factor_id']}'.startsWith(
            'imf:macro_series:NGDP_RPCH:USA:',
          ),
        );
        expect(imf['family'], 'macro_series');
        expect(imf['source_name'], 'IMF');
        expect(imf['source_type'], 'official_api');
        expect(imf['status'], 'active');
        final oecd = result.rows.firstWhere(
          (item) => '${item['factor_id']}'.startsWith(
            'oecd:macro_series:DF_QNA_EXPENDITURE_GROWTH_OECD:OECD:',
          ),
        );
        expect(oecd['family'], 'macro_series');
        expect(oecd['source_name'], 'OECD');
        expect(oecd['source_type'], 'official_api');
        expect(oecd['status'], 'active');
        final eia = result.rows.firstWhere(
          (item) => item['factor_id'] == 'eia:macro_series:WCESTUS1:credential',
        );
        expect(eia['family'], 'macro_series');
        expect(eia['source_name'], 'EIA');
        expect(eia['status'], 'unsupported');
        expect(eia['failure_class'], 'credential_missing');
        final nbs = result.rows.firstWhere(
          (item) =>
              item['factor_id'] ==
              'nbs_china:macro_series:easyquery:security_control',
        );
        expect(nbs['family'], 'macro_series');
        expect(nbs['source_name'], 'NBS China');
        expect(nbs['status'], 'unsupported');
        expect(nbs['failure_class'], 'security_control');

        final nbsReadback =
            await queryService.run('query_macro_numeric_series', const [], {
                  'provider': 'nbs_china',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(nbsReadback['status'], 'ok');
        expect(nbsReadback['count'], 1);
        final nbsSeries = (nbsReadback['series'] as List).first as Map;
        expect(nbsSeries['seriesId'], 'NBS_EASYQUERY_PENDING');
        expect(nbsSeries['provider'], 'nbs china');
        expect(nbsSeries['failureClass'], 'security_control');
        expect(nbsSeries['value'], isNull);
        final oecdReadback =
            await queryService.run('query_macro_numeric_series', const [], {
                  'provider': 'oecd',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(oecdReadback['status'], 'ok');
        expect(oecdReadback['count'], 1);
        final oecdSeries = (oecdReadback['series'] as List).first as Map;
        expect(
          oecdSeries['seriesId'],
          'DF_QNA_EXPENDITURE_GROWTH_OECD:B1GQ:OECD:GCM',
        );
        expect(oecdSeries['provider'], 'oecd');
        expect(oecdSeries['sourceName'], 'OECD');
        expect(oecdSeries['value'], isA<num>());
      },
    );

    test('query_macro_factors reads relevant rows and reports gaps', () async {
      final dir = Directory.systemTemp.createTempSync('finagent_macro_factor_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final store = ReusableDataStore(dir.path);
      MacroFactorRadarService(store: store).read();
      final service = MarketDataActionService();
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

      final copper =
          await service.run('query_macro_factors', const [], {
                'target': 'Copper',
                'limit': 5,
              }, context)
              as Map<String, dynamic>;
      expect(copper['action'], 'query_macro_factors');
      expect(copper['status'], 'ok');
      expect((copper['rows'] as List), isNotEmpty);
      expect(
        (copper['provenance'] as Map)['canonicalSchema'],
        'market_moving_factor_v1',
      );

      final missing =
          await service.run('query_macro_factors', const [], {
                'target': 'Nonexistent factor target',
                'limit': 5,
              }, context)
              as Map<String, dynamic>;
      expect(missing['status'], 'missing');
      expect(missing['count'], 0);
      expect('${missing['missingReason']}', contains('macro-evidence gap'));
    });

    test(
      'query_macro_attribution returns structured root-cause rows',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final store = ReusableDataStore(dir.path);
        MacroFactorRadarService(store: store).read();
        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

        final attribution =
            await service.run('query_macro_attribution', const [], {
                  'target': 'Copper',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(attribution['action'], 'query_macro_attribution');
        expect(attribution['status'], 'ok');
        expect(
          (attribution['provenance'] as Map)['canonicalSchema'],
          'macro_attribution_v1',
        );
        final attributions = attribution['attributions'] as List;
        expect(attributions, isNotEmpty);
        final first = Map<String, dynamic>.from(attributions.first as Map);
        expect(first['category'], isA<String>());
        expect(first['confidence'], isA<String>());
        expect(first['invalidationCondition'], isA<String>());
        expect(first['nextUpdateAction'], isA<String>());
        expect(first['evidence'], isNotEmpty);

        final missing =
            await service.run('query_macro_attribution', const [], {
                  'target': 'No such macro target',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(missing['status'], 'missing');
        expect((missing['updateDecision'] as Map)['requiresUpdate'], isTrue);
        final missingAttribution =
            (missing['attributions'] as List).first as Map<String, dynamic>;
        expect(missingAttribution['category'], 'data-quality');
        expect(missingAttribution['confidence'], 'unknown');
      },
    );

    test(
      'query_macro_numeric_series reads official series separately from research evidence',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final fetchedAt = '2026-07-08T00:00:00.000Z';
        final store = ReusableDataStore(dir.path);
        store.saveMarketMovingFactors([
          {
            'factor_id': 'fred:rates_liquidity:DGS10:2026-07-07',
            'family': 'rates_liquidity',
            'title': 'US 10Y Treasury yield',
            'summary': 'Official numeric rates evidence.',
            'source_name': 'FRED',
            'source_url': 'https://fred.stlouisfed.org/series/DGS10',
            'source_type': 'official_api',
            'source_published_at': '2026-07-07',
            'fetched_at': fetchedAt,
            'event_at': '2026-07-07',
            'affected_assets': ['Treasury yields'],
            'affected_regions': ['United States'],
            'affected_sectors': [],
            'transmission_channels': ['discount rate'],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {'label': 'DGS10 2026-07-07 = 4.1', 'retrieved_at': fetchedAt},
            ],
            'macro_values': {
              'actual': 4.1,
              'unit': 'percent',
              'period': '2026-07-07',
            },
            'retrieval_test': {
              'provider': 'fred',
              'interface_id': 'macro.factor_radar',
              'capability_id': 'fred.series.observations',
              'status': 'ok',
            },
          },
          {
            'factor_id': 'macro:macro_research_document:goldman_sachs',
            'family': 'macro_research_document',
            'title': 'Research narrative row',
            'summary': 'Narrative row must not be returned as numeric series.',
            'source_name': 'Goldman Sachs',
            'source_type': 'research_narrative',
            'fetched_at': fetchedAt,
            'status': 'usable',
            'macro_values': {
              'keyClaims': ['macro view'],
            },
          },
          {
            'factor_id': 'world_bank:macro_series:NY.GDP.MKTP.CD:2025',
            'family': 'macro_series',
            'title': 'US GDP current US\$ World Bank observation',
            'summary': 'Official numeric growth evidence.',
            'source_name': 'World Bank',
            'source_url':
                'https://api.worldbank.org/v2/country/US/indicator/NY.GDP.MKTP.CD',
            'source_type': 'official_api',
            'source_published_at': '2026-07-01',
            'fetched_at': fetchedAt,
            'event_at': '2025',
            'affected_assets': ['US equities'],
            'affected_regions': ['United States'],
            'affected_sectors': [],
            'transmission_channels': ['growth level'],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label': 'NY.GDP.MKTP.CD 2025 = 30769700000000',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': 30769700000000,
              'unit': 'current US\$',
              'period': '2025',
              'frequency': 'annual',
            },
            'retrieval_test': {
              'provider': 'world_bank',
              'interface_id': 'macro.factor_radar',
              'capability_id': 'world_bank.indicator.NY.GDP.MKTP.CD',
              'status': 'ok',
            },
          },
          {
            'factor_id': 'imf:macro_series:NGDP_RPCH:USA:2031',
            'family': 'macro_series',
            'title': 'US real GDP growth IMF DataMapper observation',
            'summary': 'Official numeric growth evidence.',
            'source_name': 'IMF',
            'source_url':
                'https://www.imf.org/external/datamapper/api/v1/NGDP_RPCH/USA',
            'source_type': 'official_api',
            'source_published_at': '2031',
            'fetched_at': fetchedAt,
            'event_at': '2031',
            'affected_assets': ['US equities'],
            'affected_regions': ['United States'],
            'affected_sectors': [],
            'transmission_channels': ['growth momentum'],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {'label': 'NGDP_RPCH USA 2031 = 1.8', 'retrieved_at': fetchedAt},
            ],
            'macro_values': {
              'actual': 1.8,
              'unit': 'percent change',
              'period': '2031',
              'frequency': 'annual',
            },
            'retrieval_test': {
              'provider': 'imf',
              'interface_id': 'macro.factor_radar',
              'capability_id': 'imf.datamapper.NGDP_RPCH.USA',
              'status': 'ok',
            },
          },
          {
            'factor_id': 'eia:macro_series:WCESTUS1:2026-07-03',
            'family': 'macro_series',
            'title': 'US commercial crude oil inventories EIA observation',
            'summary': 'Official numeric energy inventory evidence.',
            'source_name': 'EIA',
            'source_url': 'https://api.eia.gov/v2/petroleum/stoc/wstk/data/',
            'source_type': 'official_api',
            'source_published_at': '2026-07-03',
            'fetched_at': fetchedAt,
            'event_at': '2026-07-03',
            'affected_assets': ['oil'],
            'affected_regions': ['United States'],
            'affected_sectors': ['Energy'],
            'transmission_channels': ['energy inventory'],
            'expected_direction': 'mixed',
            'severity': 'medium',
            'confidence': 'high',
            'status': 'active',
            'evidence_items': [
              {
                'label': 'WCESTUS1 2026-07-03 = 420000',
                'retrieved_at': fetchedAt,
              },
            ],
            'macro_values': {
              'actual': 420000,
              'unit': 'thousand barrels',
              'period': '2026-07-03',
              'frequency': 'weekly',
            },
            'retrieval_test': {
              'provider': 'eia',
              'interface_id': 'macro.factor_radar',
              'capability_id': 'eia.petroleum.stoc.wstk.WCESTUS1',
              'status': 'ok',
            },
          },
        ]);

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        final result =
            await service.run('query_macro_numeric_series', const [], {
                  'provider': 'fred',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(result['action'], 'query_macro_numeric_series');
        expect(result['status'], 'ok');
        expect(result['count'], 1);
        expect(
          (result['provenance'] as Map)['interfaceId'],
          'macro.official_series',
        );
        final row = ((result['series'] as List).first as Map);
        expect(row['seriesId'], 'DGS10');
        expect(row['metricName'], 'US 10Y Treasury yield');
        expect(row['provider'], 'fred');
        expect(row['value'], 4.1);
        expect(row['unit'], 'percent');
        expect(row['sourceDataTime'], '2026-07-07');
        expect(row['fetchedAt'], fetchedAt);

        final worldBank =
            await service.run('query_macro_numeric_series', const [], {
                  'provider': 'world_bank',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(worldBank['action'], 'query_macro_numeric_series');
        expect(worldBank['status'], 'ok');
        expect(worldBank['count'], 1);
        final worldBankRow = ((worldBank['series'] as List).first as Map);
        expect(worldBankRow['seriesId'], 'NY.GDP.MKTP.CD');
        expect(worldBankRow['provider'], 'world_bank');
        expect(worldBankRow['value'], 30769700000000);
        expect(worldBankRow['unit'], 'current US\$');
        expect(worldBankRow['sourceDataTime'], '2025');

        final imf =
            await service.run('query_macro_numeric_series', const [], {
                  'provider': 'imf',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(imf['action'], 'query_macro_numeric_series');
        expect(imf['status'], 'ok');
        expect(imf['count'], 1);
        final imfRow = ((imf['series'] as List).first as Map);
        expect(imfRow['seriesId'], 'NGDP_RPCH');
        expect(imfRow['provider'], 'imf');
        expect(imfRow['value'], 1.8);
        expect(imfRow['unit'], 'percent change');
        expect(imfRow['sourceDataTime'], '2031');

        final eia =
            await service.run('query_macro_numeric_series', const [], {
                  'provider': 'eia',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(eia['action'], 'query_macro_numeric_series');
        expect(eia['status'], 'ok');
        expect(eia['count'], 1);
        final eiaRow = ((eia['series'] as List).first as Map);
        expect(eiaRow['seriesId'], 'WCESTUS1');
        expect(eiaRow['provider'], 'eia');
        expect(eiaRow['value'], 420000);
        expect(eiaRow['unit'], 'thousand barrels');
        expect(eiaRow['sourceDataTime'], '2026-07-03');
      },
    );

    test(
      'configured EIA refresh persists governed numeric readback rows',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final apiConfig = ApiConfigStore()..set('EIA_API_KEY', 'test-eia-key');
        final store = ReusableDataStore(dir.path);
        final service = MacroFactorRadarService(
          store: store,
          apiConfig: apiConfig,
          httpClient: MockClient((request) async {
            final url = request.url.toString();
            if (url.contains('api.eia.gov/v2/petroleum/stoc/wstk/data')) {
              return http.Response(
                jsonEncode({
                  'response': {
                    'data': [
                      {
                        'period': '2026-07-03',
                        'series': 'WCESTUS1',
                        'value': '420000',
                        'units': 'MBBL',
                        'series-description':
                            'Weekly U.S. Ending Stocks of Crude Oil',
                      },
                    ],
                  },
                }),
                200,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              jsonEncode({'error': 'provider not needed for this test'}),
              500,
              headers: {'content-type': 'application/json'},
            );
          }),
        );

        final refreshed = await service.refresh();
        final eiaRow = refreshed.rows.firstWhere(
          (row) => row['factor_id'] == 'eia:macro_series:WCESTUS1:2026-07-03',
        );
        expect(eiaRow['family'], 'macro_series');
        expect(eiaRow['source_name'], 'EIA');
        expect(eiaRow['source_type'], 'official_api');
        expect(eiaRow['status'], 'active');
        expect(eiaRow['access_status'], 'public');
        expect(eiaRow['freshness_status'], 'acceptable');
        expect(eiaRow['confidence_effect'], 'mixed');
        expect((eiaRow['macro_values'] as Map)['actual'], 420000);
        expect((eiaRow['macro_values'] as Map)['unit'], 'MBBL');
        expect((eiaRow['retrieval_test'] as Map)['provider'], 'eia');
        expect((eiaRow['retrieval_test'] as Map)['status'], 'ok');

        final queryService = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        final readback =
            await queryService.run('query_macro_numeric_series', const [], {
                  'provider': 'eia',
                  'seriesId': 'WCESTUS1',
                  'limit': 5,
                }, context)
                as Map<String, dynamic>;
        expect(readback['action'], 'query_macro_numeric_series');
        expect(readback['status'], 'ok');
        expect(readback['count'], 1);
        expect(
          (readback['provenance'] as Map)['canonicalTable'],
          'market_moving_factor',
        );
        expect(
          (readback['provenance'] as Map)['readbackAction'],
          'query_macro_numeric_series',
        );
        final seriesRow = ((readback['series'] as List).first as Map);
        expect(seriesRow['provider'], 'eia');
        expect(seriesRow['seriesId'], 'WCESTUS1');
        expect(seriesRow['value'], 420000);
        expect(seriesRow['unit'], 'MBBL');
        expect(seriesRow['sourceDataTime'], '2026-07-03');
      },
    );

    test(
      'macro_research_sources exposes source-specific access behavior',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

        final all =
            await service.run('macro_research_sources', const [], {
                  'limit': 80,
                }, context)
                as Map<String, dynamic>;
        expect(all['action'], 'macro_research_sources');
        expect(all['status'], 'ok');
        expect(
          (all['provenance'] as Map)['interfaceId'],
          'macro.research_source_catalog',
        );
        expect(
          (all['provenance'] as Map)['canonicalSchema'],
          'macro_research_source_catalog_v1',
        );

        final rows = (all['rows'] as List).cast<Map<String, dynamic>>();
        final byId = {for (final row in rows) row['id']: row};
        expect(byId['oecd']?['accessClass'], 'browser-public');
        expect(byId['oecd']?['testedStatus'], 'browser-ua-http-readable');
        expect(byId['lme']?['testedStatus'], 'playwright-browser-ua-readable');
        expect(byId['iea']?['accessClass'], 'anti-bot-manual-browser');
        expect(
          byId['iea']?['automationPolicy'],
          'do-not-repeat-automated-fetch-after-challenge',
        );
        expect(byId['opec']?['testedStatus'], 'cloudflare-verification');
        expect(byId['sp_dji']?['accessClass'], contains('manual-browser'));
        expect(
          byId['fidelity']?['testedStatus'],
          'security-blocked-in-automation',
        );
        expect(byId['pboc']?['evidenceValue'], 'official_policy_event');
        expect(
          byId['pboc_policy_reports']?['testedStatus'],
          'official-subpage-html-ok',
        );
        expect(
          byId['pboc_policy_reports']?['categories'],
          contains('policy_report'),
        );
        expect(
          byId['pboc_news_releases']?['categories'],
          contains('open_market_operations'),
        );
        expect(byId['nbs_china']?['evidenceValue'], 'official_macro_fact');
        expect(
          byId['nbs_data_releases']?['testedStatus'],
          'official-list-detail-html-ok',
        );
        expect(
          byId['nbs_data_releases']?['categories'],
          contains('data_release'),
        );
        expect(
          byId['nbs_data_releases']?['retrievalMethods'],
          contains('list_to_detail_html'),
        );
        expect(
          byId['csrc_policy_notices']?['categories'],
          contains('capital_market_policy'),
        );
        expect(byId['safe_china']?['categories'], contains('capital_flow'));
        expect(
          byId['safe_statistics']?['categories'],
          contains('cross_border_finance'),
        );
        expect(
          byId['china_exchanges']?['categories'],
          contains('market_structure_event'),
        );
        expect(
          byId['china_exchange_notices']?['entryUrls'],
          contains('https://www.sse.com.cn/disclosure/announcement/general/'),
        );
        expect(
          byId['hkex_news_releases']?['accessClass'],
          'manual-browser-or-webview',
        );
        expect(
          byId['hkex_news_releases']?['testedStatus'],
          'akamai-503-to-simple-http',
        );
        expect(
          byId['hkex_news_releases']?['retrievalMethods'],
          contains('webview'),
        );
        expect(
          byId['szse_notice_api']?['accessClass'],
          'official-api-and-public-report',
        );
        expect(
          byId['szse_notice_api']?['testedStatus'],
          'official-api-payload-ok',
        );
        expect(
          byId['szse_notice_api']?['evidenceValue'],
          'official_policy_event',
        );
        expect(
          byId['szse_notice_api']?['retrievalMethods'],
          contains('official_api'),
        );
        expect(byId['szse_notice_api']?['categories'], contains('api_payload'));
        expect(byId['imf']?['categories'], contains('country_risk'));
        expect(byId['world_bank']?['accessClass'], 'official-api');
        expect(byId['vanguard']?['evidenceValue'], 'allocation_regime');
        expect(
          byId['state_street']?['categories'],
          contains('etf_flow_context'),
        );

        final cme =
            await service.run('macro_research_sources', const [], {
                  'provider': 'cme',
                }, context)
                as Map<String, dynamic>;
        final cmeRow = ((cme['rows'] as List).first as Map);
        expect(
          cmeRow['accessClass'],
          'manual-browser-or-official-data-delivery',
        );
        expect(cmeRow['automationPolicy'], 'do-not-scrape');

        final ubs =
            await service.run('macro_research_sources', const [], {
                  'provider': 'ubs',
                }, context)
                as Map<String, dynamic>;
        final ubsRow = ((ubs['rows'] as List).first as Map);
        expect(ubsRow['accessClass'], 'browser-public');
        expect(ubsRow['testedStatus'], 'playwright-browser-ua-readable');

        final msci =
            await service.run('macro_research_sources', const [], {
                  'category': 'market_classification',
                }, context)
                as Map<String, dynamic>;
        final msciRows = (msci['rows'] as List).cast<Map<String, dynamic>>();
        expect(msciRows.any((row) => row['provider'] == 'msci'), isTrue);
        expect(
          msciRows.every(
            (row) =>
                (row['categories'] as List).contains('market_classification'),
          ),
          isTrue,
        );

        final commodity =
            await service.run('macro_research_sources', const [], {
                  'category': 'commodity_research',
                  'priority': 1,
                }, context)
                as Map<String, dynamic>;
        expect(commodity['action'], 'macro_research_sources');
        expect(commodity['status'], 'ok');
        final commodityRows = (commodity['rows'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          commodityRows.any((row) => row['provider'] == 'goldman_sachs'),
          isTrue,
        );
        expect(commodityRows.any((row) => row['provider'] == 'eia'), isTrue);

        final chinaPolicy =
            await service.run('macro_research_sources', const [], {
                  'category': 'official_policy_event',
                  'priority': 1,
                }, context)
                as Map<String, dynamic>;
        final chinaPolicyRows = (chinaPolicy['rows'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          chinaPolicyRows.any(
            (row) => row['provider'] == 'pboc_policy_reports',
          ),
          isTrue,
        );
        expect(
          chinaPolicyRows.any(
            (row) => row['provider'] == 'csrc_policy_notices',
          ),
          isTrue,
        );
        expect(
          chinaPolicyRows.any(
            (row) => row['provider'] == 'china_exchange_notices',
          ),
          isTrue,
        );
      },
    );

    test(
      'macro_numeric_series_catalog exposes official series availability',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

        final all =
            await service.run('macro_numeric_series_catalog', const [], {
                  'limit': 20,
                }, context)
                as Map<String, dynamic>;
        expect(all['action'], 'macro_numeric_series_catalog');
        expect(all['status'], 'ok');
        expect(all['count'], greaterThanOrEqualTo(8));
        expect(
          (all['provenance'] as Map)['interfaceId'],
          'macro.official_series',
        );
        expect(
          (all['provenance'] as Map)['canonicalTable'],
          'market_moving_factor',
        );
        expect(
          (all['provenance'] as Map)['readbackAction'],
          'query_macro_numeric_series',
        );

        final rows = (all['rows'] as List).cast<Map>();
        expect(
          rows.map((row) => row['seriesId']),
          containsAll([
            'DGS10',
            'CUUR0000SA0',
            'NIPA:T10101',
            'NY.GDP.MKTP.CD',
            'NGDP_RPCH',
            'DF_QNA_EXPENDITURE_GROWTH_OECD:B1GQ:OECD:GCM',
            'WCESTUS1',
            'NBS_EASYQUERY_PENDING',
          ]),
        );

        final bea =
            await service.run('macro_numeric_series_catalog', const [], {
                  'provider': 'bea',
                }, context)
                as Map<String, dynamic>;
        expect(bea['count'], 1);
        final beaRow = (bea['rows'] as List).first as Map;
        expect(beaRow['credentialKey'], 'BEA_API_KEY');
        expect(beaRow['status'], 'credential-gated');

        final securityControlled =
            await service.run('macro_numeric_series_catalog', const [], {
                  'status': 'security-control',
                }, context)
                as Map<String, dynamic>;
        expect(securityControlled['count'], 1);
        expect(
          ((securityControlled['rows'] as List).first as Map)['provider'],
          'nbs_china',
        );

        final oecd =
            await service.run('macro_numeric_series_catalog', const [], {
                  'provider': 'oecd',
                }, context)
                as Map<String, dynamic>;
        expect(oecd['count'], 1);
        final oecdRow = (oecd['rows'] as List).first as Map;
        expect(
          oecdRow['seriesId'],
          'DF_QNA_EXPENDITURE_GROWTH_OECD:B1GQ:OECD:GCM',
        );
        expect(oecdRow['status'], 'supported');
      },
    );

    test(
      'macro_research_provenance persists reusable and blocked source evidence',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

        final generated =
            await service.run('macro_research_provenance', const [], {
                  'limit': 120,
                }, context)
                as Map<String, dynamic>;
        expect(generated['action'], 'macro_research_provenance');
        expect(generated['status'], 'ok');
        expect(generated['persisted'], isTrue);
        expect(
          (generated['provenance'] as Map)['canonicalSchema'],
          'market_moving_factor_v1',
        );
        expect(generated['generatedRows'], greaterThan(10));
        expect((generated['providerMatrix'] as List).length, greaterThan(10));

        final readback =
            await service.run('query_macro_research_evidence', const [], {
                  'limit': 120,
                }, context)
                as Map<String, dynamic>;
        expect(readback['action'], 'query_macro_research_evidence');
        expect(readback['status'], 'ok');
        expect(
          (readback['provenance'] as Map)['canonicalTable'],
          'market_moving_factor',
        );

        final rows = (readback['rows'] as List).cast<Map<String, dynamic>>();
        final families = {for (final row in rows) row['family']};
        expect(families, contains('macro_research_document'));
        expect(families, contains('macro_index_event'));
        expect(families, contains('macro_policy_event'));
        expect(families, contains('macro_official_series'));
        expect(families, contains('macro_commodity_event'));
        expect(families, contains('macro_source_retrieval_evidence'));

        final cme = rows.firstWhere(
          (row) => row['factor_id'] == 'macro:source_retrieval:cme',
        );
        expect(cme['family'], 'macro_source_retrieval_evidence');
        expect(cme['status'], 'blocked');
        expect(
          cme['failure_class'],
          'manual-browser-or-official-data-delivery',
        );
        expect(
          (cme['retrieval_test'] as Map)['automationPolicy'],
          'do-not-scrape',
        );
        expect(
          rows.any(
            (row) => row['factor_id'] == 'macro:macro_commodity_event:cme',
          ),
          isFalse,
        );

        final msci = rows.firstWhere(
          (row) => row['factor_id'] == 'macro:macro_index_event:msci',
        );
        expect(msci['family'], 'macro_index_event');
        expect(msci['source_name'], 'MSCI');
        expect(msci['status'], 'usable');
        expect(
          ((msci['macro_values'] as Map)['extractableFields'] as List),
          contains('effectiveDate'),
        );

        final commodity =
            await service.run('macro_research_provenance', const [], {
                  'family': 'commodity_research',
                }, context)
                as Map<String, dynamic>;
        expect(commodity['action'], 'macro_research_provenance');
        expect(commodity['status'], 'ok');
        expect(commodity['generatedRows'], greaterThan(0));
        final commodityRows = (commodity['rows'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          commodityRows.any((row) => row['family'] == 'macro_commodity_event'),
          isTrue,
        );

        final commodityReadback =
            await service.run('query_macro_research_evidence', const [], {
                  'family': 'commodity_research',
                  'limit': 20,
                }, context)
                as Map<String, dynamic>;
        expect(commodityReadback['action'], 'query_macro_research_evidence');
        expect(commodityReadback['status'], 'ok');
        final commodityReadbackRows = (commodityReadback['rows'] as List)
            .cast<Map<String, dynamic>>();
        expect(
          commodityReadbackRows.any((row) => row['source_name'] == 'EIA'),
          isTrue,
        );

        final factorAlias =
            await service.run('query_macro_factors', const [], {
                  'target': 'Copper',
                  'family': 'commodity_research',
                  'limit': 10,
                }, context)
                as Map<String, dynamic>;
        expect(factorAlias['action'], 'query_macro_factors');
        expect(factorAlias['status'], 'ok');
      },
    );

    test(
      'macro_research_extract follows official list pages to bounded detail evidence',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        const listUrl =
            'https://www.pbc.gov.cn/zhengcehuobisi/125207/125227/125957/index.html';
        const detailUrl =
            'https://www.pbc.gov.cn/zhengcehuobisi/125207/125227/125957/202607/t20260708_600001.html';
        final store = ReusableDataStore(dir.path);
        final client = _MacroResearchFakeClient({
          listUrl: '''
            <html><body>
              <a href="/english/">English</a>
              <a href="./202607/t20260708_600001.html">2026年7月货币政策执行报告发布</a>
            </body></html>
          ''',
          detailUrl: '''
            <html><head><title>2026年7月货币政策执行报告发布</title></head>
            <body><article>
              <h1>2026年7月货币政策执行报告发布</h1>
              <time>2026-07-08</time>
              <p>中国人民银行发布货币政策执行报告，指出稳健的货币政策将保持流动性合理充裕，并关注利率、汇率和信贷结构对债券、A股和实体经济的传导。</p>
              <p>报告强调政策协调、资本流动和金融市场预期管理，相关变化应作为市场分析中的宏观假设、风险边界和失效条件，而不是直接买卖信号。</p>
              <p>后续分析应持续跟踪公开市场操作、贷款市场报价利率、银行间流动性和外汇市场稳定情况。</p>
            </article></body></html>
          ''',
        });

        final result = await macroResearchExtract(
          store,
          {'provider': 'pboc_policy_reports'},
          basePath: dir.path,
          httpClient: client,
        );

        expect(result['status'], 'ok');
        expect(result['extracted'], 1);
        final row = (result['rows'] as List).first as Map<String, dynamic>;
        expect(row['source_url'], detailUrl);
        expect((row['macro_values'] as Map)['listSourceUrl'], listUrl);
        expect((row['retrieval_test'] as Map)['listSourceUrl'], listUrl);
        expect(
          (row['macro_values'] as Map)['bodyPreview'],
          contains('流动性合理充裕'),
        );

        final readback = queryMacroResearchContent(store, {
          'provider': 'pboc_policy_reports',
          'target': '流动性',
        });
        expect(readback['status'], 'ok');
        expect(readback['count'], 1);
      },
    );

    test(
      'macro detail selector rejects directories and preserves source order',
      () {
        final source = {
          'categories': ['official_policy_event', 'data_release'],
        };
        final selected = macroResearchSelectDetailUrlForTest(
          sourceUrl: 'https://www.szse.cn/disclosure/notice/general/index.html',
          source: source,
          html: '''
          <html><body>
            <a href="/disclosure/notice/general/">通知公告</a>
            <a href="/disclosure/notice/general/t20260708_600001.html">2026年7月8日深交所通知公告</a>
          </body></html>
        ''',
        );
        expect(
          selected,
          'https://www.szse.cn/disclosure/notice/general/t20260708_600001.html',
        );

        final tied = macroResearchSelectDetailUrlForTest(
          sourceUrl: 'http://www.csrc.gov.cn/csrc/c100028/common_list.shtml',
          source: source,
          html: '''
          <html><body>
            <a href="/csrc/c100028/c20260708/content.shtml">证监会组织开展上市公司报告专项活动</a>
            <a href="/csrc/c100028/c20210101/content.shtml">证监会较长旧标题公告通知政策数据统计市场交易</a>
          </body></html>
        ''',
        );
        expect(
          tied,
          'http://www.csrc.gov.cn/csrc/c100028/c20260708/content.shtml',
        );
      },
    );

    test(
      'macro_research_extract persists article content with hash and claims',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        final html = '''
          <html>
            <head><title>Why record-high copper prices are not forecast to last</title></head>
            <body>
              <nav>Global navigation should be removed</nav>
              <article>
                <h1>Why record-high copper prices are not forecast to last</h1>
                <time>June 18, 2026</time>
                <p>Goldman Sachs Research says copper markets face a near-term price shock as inventories tighten and miners react to supply limits.</p>
                <p>The report argues that copper demand, energy transition spending, and China construction activity can change commodity expectations for several months.</p>
                <p>Rates, inflation, and global growth still affect whether investors treat the copper move as a durable macro signal or as a temporary inventory event.</p>
              </article>
            </body>
          </html>
        ''';

        final extracted =
            await service.run('macro_research_extract', const [], {
                  'provider': 'goldman_sachs',
                  'content': html,
                  'contentType': 'html',
                }, context)
                as Map<String, dynamic>;
        expect(extracted['action'], 'macro_research_extract');
        expect(extracted['status'], 'ok');
        expect(extracted['extracted'], 1);
        expect(extracted['failed'], 0);
        final row = ((extracted['rows'] as List).first as Map);
        expect(
          (row['macro_values'] as Map)['contentHash'],
          matches(RegExp(r'^[a-f0-9]{64}$')),
        );
        expect(
          (row['macro_values'] as Map)['artifactPath'],
          contains('macro_research_content'),
        );
        expect(
          ((row['macro_values'] as Map)['keyClaims'] as List).length,
          greaterThanOrEqualTo(2),
        );

        final readback =
            await service.run('query_macro_research_content', const [], {
                  'provider': 'Goldman Sachs',
                  'target': 'copper',
                }, context)
                as Map<String, dynamic>;
        expect(readback['status'], 'ok');
        expect(readback['count'], 1);
        expect(
          (readback['readbackContract'] as Map)['normalUse'],
          contains('contentEvidence'),
        );
        final contentEvidence =
            ((readback['contentEvidence'] as List).first as Map);
        expect(
          contentEvidence['title'],
          'Why record-high copper prices are not forecast to last',
        );
        expect(contentEvidence['sourceName'], 'Goldman Sachs');
        expect(contentEvidence['sourceDataTime'], '2026-06-18');
        expect(contentEvidence['bodyPreview'], contains('copper markets'));
        expect(
          (contentEvidence['keyClaims'] as List).any(
            (claim) => '${(claim as Map)['claim']}'.contains('copper markets'),
          ),
          isTrue,
        );
        final readbackRow = ((readback['rows'] as List).first as Map);
        expect(readbackRow['source_published_at'], '2026-06-18');
        expect(
          ((readbackRow['macro_values'] as Map)['keyClaims'] as List).first,
          containsPair(
            'contentHash',
            (row['macro_values'] as Map)['contentHash'],
          ),
        );

        final readbackByProviderId =
            await service.run('query_macro_research_content', const [], {
                  'provider': 'goldman_sachs',
                  'target': 'copper',
                }, context)
                as Map<String, dynamic>;
        expect(readbackByProviderId['status'], 'ok');
        expect(readbackByProviderId['count'], 1);
      },
    );

    test(
      'macro_research_extract handles PDF text and blocks do-not-scrape sources',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        const pdfText = '''
          MSCI 2026 Market Classification Review
          2026-06-20
          MSCI announced that Indonesia remains under review for market accessibility and index classification.
          The effective date for any reclassification would affect passive benchmark flow and emerging market allocation.
          Investors should monitor consultation status, implementation timing, and official document updates.
        ''';
        final extracted =
            await service.run('macro_research_extract', const [], {
                  'provider': 'msci',
                  'urlIndex': 1,
                  'content': pdfText,
                  'contentType': 'pdf_text',
                }, context)
                as Map<String, dynamic>;
        expect(extracted['extracted'], 1);
        final row = ((extracted['rows'] as List).first as Map);
        expect(row['family'], 'macro_index_event');
        expect(row['source_name'], 'MSCI');
        expect((row['macro_values'] as Map)['contentType'], 'pdf_text');
        expect(
          ((row['macro_values'] as Map)['keyClaims'] as List).any(
            (claim) => '${(claim as Map)['claim']}'.contains('Indonesia'),
          ),
          isTrue,
        );

        const policyHtml = '''
          <html><head><title>中国人民银行货币政策执行报告</title></head>
          <body><article>
          <h1>中国人民银行货币政策执行报告</h1>
          <time>2026-07-08</time>
          <p>中国人民银行指出，稳健的货币政策要保持流动性合理充裕，关注利率、汇率和信贷结构对 A股、债券和实体经济的传导影响。</p>
          <p>报告强调政策协调、资本流动和金融市场预期管理，相关政策变化应作为市场分析的宏观假设和失效条件，而不是直接买卖信号。</p>
          </article></body></html>
        ''';
        final policy =
            await service.run('macro_research_extract', const [], {
                  'provider': 'pboc',
                  'content': policyHtml,
                  'contentType': 'html',
                }, context)
                as Map<String, dynamic>;
        expect(policy['extracted'], 1);
        final policyRow = ((policy['rows'] as List).first as Map);
        expect(policyRow['family'], 'macro_policy_event');
        expect(
          (policyRow['macro_values'] as Map)['interfaceId'],
          'macro.policy_event',
        );
        expect(
          ((policyRow['macro_values'] as Map)['keyClaims'] as List)
              .map((claim) => (claim as Map)['claimCategory'])
              .toSet(),
          {'official_policy_event'},
        );

        final blocked =
            await service.run('macro_research_extract', const [], {
                  'provider': 'cme',
                }, context)
                as Map<String, dynamic>;
        expect(blocked['status'], 'failed');
        expect(blocked['extracted'], 0);
        expect(blocked['failed'], 1);
        final blockedRow = ((blocked['rows'] as List).first as Map);
        expect(blockedRow['family'], 'macro_source_retrieval_evidence');
        expect(blockedRow['status'], 'blocked');
        expect(
          blockedRow['failure_class'],
          'manual-browser-or-official-data-delivery',
        );
      },
    );

    test(
      'macro_research_extract extracts China official metadata without navigation noise',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        const detailUrl =
            'https://www.pbc.gov.cn/zhengcehuobisi/125207/125227/125957/202607/t20260708_600001.html';
        const detailHtml = '''
          <html>
            <head>
              <title>站点导航 - 中国人民银行</title>
              <meta name="ArticleTitle" content="中国人民银行开展公开市场逆回购操作">
              <meta name="PubDate" content="2026年7月8日">
            </head>
            <body>
              <nav>首页 机构设置 政策法规 统计数据 English</nav>
              <div class="TRS_Editor">
                <p>中国人民银行公告称，为保持银行体系流动性合理充裕，开展公开市场逆回购操作，并继续关注利率、汇率和信贷结构对金融市场的传导。</p>
                <p>本次操作属于官方政策和流动性事件，应作为A股、债券和银行间资金面的宏观假设、观察因素和失效条件，而不是直接买卖信号。</p>
                <p>后续市场分析需要跟踪公开市场操作规模、利率变化、资金价格和外汇市场预期。</p>
              </div>
              <footer>版权所有 联系我们 网站地图</footer>
            </body>
          </html>
        ''';

        final extracted =
            await service.run('macro_research_extract', const [], {
                  'provider': 'pboc_policy_reports',
                  'url': detailUrl,
                  'content': detailHtml,
                  'contentType': 'html',
                }, context)
                as Map<String, dynamic>;

        expect(extracted['action'], 'macro_research_extract');
        expect(extracted['status'], 'ok');
        expect(extracted['extracted'], 1);
        expect(extracted['failed'], 0);
        final row = ((extracted['rows'] as List).first as Map);
        expect(row['source_url'], detailUrl);
        expect(row['source_published_at'], '2026-07-08');
        final values = row['macro_values'] as Map;
        expect(values['title'], '中国人民银行开展公开市场逆回购操作');
        expect(values['bodyPreview'], contains('流动性合理充裕'));
        expect(values['bodyPreview'], isNot(contains('首页 机构设置')));
        expect(
          (values['keyClaims'] as List).any(
            (claim) => '${(claim as Map)['claim']}'.contains('公开市场逆回购操作'),
          ),
          isTrue,
        );
      },
    );

    test(
      'macro_research_extract extracts CSRC-style notice body and h2 title',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        const detailUrl =
            'http://www.csrc.gov.cn/csrc/c100028/c20260708/content.shtml';
        const noticeHtml = '''
          <html>
            <head><title>信息公开 - 中国证监会</title></head>
            <body>
              <div class="topnav">首页 机构概况 政府信息公开 政策法规</div>
              <div class="content">
                <h2>证监会发布资本市场制度型开放政策安排</h2>
                <div class="source">时间：2026-07-08 来源：证监会</div>
                <p>证监会表示，将完善资本市场基础制度，优化境内外投资者参与机制，并加强上市公司监管和信息披露质量。</p>
                <p>该政策可能影响A股风险偏好、外资配置、券商和交易所相关市场结构预期，应作为宏观政策和监管事件证据使用。</p>
                <p>后续应跟踪配套规则发布时间、交易所细则和市场主体反馈，不能把政策公告直接转化为买卖信号。</p>
              </div>
              <footer>版权所有 网站地图</footer>
            </body>
          </html>
        ''';

        final extracted =
            await service.run('macro_research_extract', const [], {
                  'provider': 'csrc_policy_notices',
                  'url': detailUrl,
                  'content': noticeHtml,
                  'contentType': 'html',
                }, context)
                as Map<String, dynamic>;

        expect(extracted['action'], 'macro_research_extract');
        expect(extracted['status'], 'ok');
        expect(extracted['extracted'], 1);
        expect(extracted['failed'], 0);
        final row = ((extracted['rows'] as List).first as Map);
        expect(row['source_url'], detailUrl);
        expect(row['family'], 'macro_policy_event');
        expect(row['source_published_at'], '2026-07-08');
        final values = row['macro_values'] as Map;
        expect(values['title'], '证监会发布资本市场制度型开放政策安排');
        expect(values['bodyPreview'], contains('资本市场基础制度'));
        expect(values['bodyPreview'], isNot(contains('首页 机构概况')));
        expect(
          (values['keyClaims'] as List)
              .map((claim) => (claim as Map)['claimCategory'])
              .toSet(),
          {'official_policy_event'},
        );
      },
    );

    test(
      'macro_research_extract extracts SAFE-style statistics tables',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        const detailUrl = 'https://www.safe.gov.cn/safe/2026/0708/25001.html';
        const tableHtml = '''
          <html>
            <head><title>统计数据 - 国家外汇管理局门户网站</title></head>
            <body>
              <div class="channel">首页 数据统计 外汇储备 国际收支</div>
              <div class="article">
                <h1>2026年6月末外汇储备规模数据</h1>
                <p>发布时间：2026年7月8日 来源：国家外汇管理局</p>
                <table>
                  <tr><th>项目</th><th>金额</th><th>说明</th></tr>
                  <tr><td>外汇储备</td><td>32000亿美元</td><td>跨境资金流动总体稳定</td></tr>
                  <tr><td>黄金储备</td><td>7300万盎司</td><td>储备结构保持连续披露</td></tr>
                </table>
                <p>外汇储备和跨境资金流动数据应作为汇率、外资流动和A股风险偏好的官方宏观事实证据。</p>
              </div>
            </body>
          </html>
        ''';

        final extracted =
            await service.run('macro_research_extract', const [], {
                  'provider': 'safe_statistics',
                  'url': detailUrl,
                  'content': tableHtml,
                  'contentType': 'html',
                }, context)
                as Map<String, dynamic>;

        expect(extracted['action'], 'macro_research_extract');
        expect(extracted['status'], 'ok');
        expect(extracted['extracted'], 1);
        expect(extracted['failed'], 0);
        final row = ((extracted['rows'] as List).first as Map);
        expect(row['source_url'], detailUrl);
        expect(row['family'], 'macro_official_series');
        expect(row['source_published_at'], '2026-07-08');
        final values = row['macro_values'] as Map;
        expect(values['title'], '2026年6月末外汇储备规模数据');
        expect(values['bodyPreview'], contains('外汇储备'));
        expect(values['bodyPreview'], contains('跨境资金流动'));
        expect(values['bodyPreview'], isNot(contains('首页 数据统计')));
        expect(
          (values['keyClaims'] as List)
              .map((claim) => (claim as Map)['claimCategory'])
              .toSet(),
          {'official_macro_fact'},
        );
      },
    );

    test(
      'macro_research_extract extracts exchange notice policy events',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        const detailUrl =
            'https://www.sse.com.cn/disclosure/announcement/general/c20260708_600001.html';
        const noticeHtml = '''
          <html>
            <head><title>上交所公告 | 上海证券交易所</title></head>
            <body>
              <header>首页 披露 公告 服务</header>
              <main class="detail">
                <h1>关于优化科创板做市和交易机制安排的通知</h1>
                <p>日期：2026-07-08 来源：上海证券交易所</p>
                <p>上海证券交易所发布通知，优化科创板做市、交易机制和信息披露监管安排，提升市场流动性和价格发现效率。</p>
                <p>该通知属于交易所官方政策和市场结构事件，应进入宏观政策事件证据，用于观察券商、科创板和A股风险偏好变化。</p>
              </main>
              <footer>版权所有 网站地图</footer>
            </body>
          </html>
        ''';

        final extracted =
            await service.run('macro_research_extract', const [], {
                  'provider': 'china_exchange_notices',
                  'url': detailUrl,
                  'content': noticeHtml,
                  'contentType': 'html',
                }, context)
                as Map<String, dynamic>;

        expect(extracted['action'], 'macro_research_extract');
        expect(extracted['status'], 'ok');
        expect(extracted['extracted'], 1);
        expect(extracted['failed'], 0);
        final row = ((extracted['rows'] as List).first as Map);
        expect(row['source_url'], detailUrl);
        expect(row['family'], 'macro_policy_event');
        expect(row['source_published_at'], '2026-07-08');
        final values = row['macro_values'] as Map;
        expect(values['title'], '关于优化科创板做市和交易机制安排的通知');
        expect(values['bodyPreview'], contains('市场流动性'));
        expect(values['bodyPreview'], isNot(contains('首页 披露')));
        expect(
          (values['keyClaims'] as List)
              .map((claim) => (claim as Map)['claimCategory'])
              .toSet(),
          {'official_policy_event'},
        );
      },
    );

    test(
      'macro_research_extract classifies attachment and JavaScript list pages',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

        final attachmentResult =
            await service.run('macro_research_extract', const [], {
                  'provider': 'safe_statistics',
                  'url':
                      'https://www.safe.gov.cn/safe/2026/0708/attachment-only.html',
                  'contentType': 'html',
                  'content': '''
                    <html><body>
                      <div class="article">
                        <h1>外汇统计数据附件下载</h1>
                        <a href="/safe/2026/0708/reserve-data.xlsx">附件：外汇储备统计表下载</a>
                      </div>
                    </body></html>
                  ''',
                }, context)
                as Map<String, dynamic>;

        expect(attachmentResult['action'], 'macro_research_extract');
        expect(attachmentResult['status'], 'failed');
        expect(attachmentResult['extracted'], 0);
        expect(attachmentResult['failed'], 1);
        final attachmentFailure =
            (attachmentResult['failures'] as List).first as Map;
        expect(attachmentFailure['provider'], 'safe_statistics');
        expect(attachmentFailure['failureClass'], 'attachment-only-source');
        final attachmentRow = (attachmentResult['rows'] as List).first as Map;
        expect(attachmentRow['family'], 'macro_source_retrieval_evidence');
        expect(attachmentRow['status'], 'blocked');
        expect(attachmentRow['failure_class'], 'attachment-only-source');

        final jsResult =
            await service.run('macro_research_extract', const [], {
                  'provider': 'china_exchange_notices',
                  'url':
                      'https://www.szse.cn/disclosure/notice/general/index.html',
                  'contentType': 'html',
                  'content': '''
                    <html><body>
                      <div id="app"></div>
                      <script src="/js/runtime.js"></script>
                      <script src="/js/notices.js"></script>
                    </body></html>
                  ''',
                }, context)
                as Map<String, dynamic>;

        expect(jsResult['action'], 'macro_research_extract');
        expect(jsResult['status'], 'failed');
        expect(jsResult['extracted'], 0);
        expect(jsResult['failed'], 1);
        final jsFailure = (jsResult['failures'] as List).first as Map;
        expect(jsFailure['provider'], 'china_exchange_notices');
        expect(jsFailure['failureClass'], 'javascript-rendered-list');
        final jsRow = (jsResult['rows'] as List).first as Map;
        expect(jsRow['family'], 'macro_source_retrieval_evidence');
        expect(jsRow['status'], 'blocked');
        expect(jsRow['failure_class'], 'javascript-rendered-list');
      },
    );

    test('macro_research_extract extracts official API payloads', () async {
      final dir = Directory.systemTemp.createTempSync('finagent_macro_factor_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final service = MarketDataActionService();
      final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
      final apiPayload = jsonEncode({
        'data': {
          'title': '深圳证券交易所发布市场交易机制优化通知',
          'publishTime': '2026-07-08',
          'source': '深圳证券交易所',
          'content':
              '深圳证券交易所发布通知，优化交易机制、信息披露和市场监管安排，提升市场流动性和风险定价效率。该通知属于交易所官方政策和市场结构事件，应作为A股风险偏好、券商业务和成长板块交易活跃度的宏观假设和观察因素，而不是直接买卖信号。',
        },
      });

      final extracted =
          await service.run('macro_research_extract', const [], {
                'provider': 'szse_notice_api',
                'url':
                    'https://www.szse.cn/api/disclosure/notice/detail?id=20260708',
                'contentType': 'api_payload',
                'apiPayload': apiPayload,
              }, context)
              as Map<String, dynamic>;

      expect(extracted['action'], 'macro_research_extract');
      expect(extracted['status'], 'ok');
      expect(extracted['extracted'], 1);
      expect(extracted['failed'], 0);
      final row = (extracted['rows'] as List).first as Map;
      expect(row['family'], 'macro_policy_event');
      expect(row['source_name'], 'SZSE Notice API');
      expect(row['source_published_at'], '2026-07-08');
      final values = row['macro_values'] as Map;
      expect(values['title'], '深圳证券交易所发布市场交易机制优化通知');
      expect(values['contentType'], 'api_payload');
      expect(values['bodyPreview'], contains('市场流动性'));
      expect(values['bodyPreview'], contains('风险定价效率'));
      expect((row['retrieval_test'] as Map)['status'], 'extracted');
    });

    test(
      'macro_research_extract selects and extracts NBS list-detail pages',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'finagent_macro_factor_',
        );
        addTearDown(() => dir.deleteSync(recursive: true));

        final service = MarketDataActionService();
        final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
        final source = macroResearchSourceCatalog.firstWhere(
          (row) => row['provider'] == 'nbs_data_releases',
        );
        const listUrl = 'https://www.stats.gov.cn/sj/zxfb/';
        const listHtml = '''
          <html><body>
            <a href="#">上一页</a>
            <a href="./202607/t20260703_1964057.html" target="_blank" title="2026年6月下旬流通领域重要生产资料市场价格变动情况">
              2026年6月下旬流通领域重要生产资料市场价格变动情况
            </a>
            <span>2026-07-04</span>
            <a href="./202606/t20260630_1964032.html" target="_blank" title="2026年6月中国采购经理指数运行情况">
              2026年6月中国采购经理指数运行情况
            </a>
            <span>2026-06-30</span>
          </body></html>
        ''';
        final selected = macroResearchSelectDetailUrlForTest(
          sourceUrl: listUrl,
          html: listHtml,
          source: source,
        );
        expect(
          selected,
          'https://www.stats.gov.cn/sj/zxfb/202607/t20260703_1964057.html',
        );

        final extracted =
            await service.run('macro_research_extract', const [], {
                  'provider': 'nbs_data_releases',
                  'url': selected,
                  'contentType': 'html',
                  'content': '''
                    <html>
                      <head>
                        <title>2026年6月下旬流通领域重要生产资料市场价格变动情况 - 国家统计局</title>
                        <meta name="ArticleTitle" content="2026年6月下旬流通领域重要生产资料市场价格变动情况">
                        <meta name="PubDate" content="2026-07-04">
                      </head>
                      <body>
                        <nav>首页 数据 数据发布</nav>
                        <div class="article">
                          <h1>2026年6月下旬流通领域重要生产资料市场价格变动情况</h1>
                          <p>发布时间：2026-07-04 来源：国家统计局</p>
                          <table>
                            <tr><th>产品名称</th><th>本期价格</th><th>涨跌幅</th></tr>
                            <tr><td>电解铜</td><td>85000元/吨</td><td>1.2%</td></tr>
                          </table>
                          <p>流通领域重要生产资料价格变化可作为商品、工业成本和通胀压力的官方宏观事实证据。</p>
                        </div>
                      </body>
                    </html>
                  ''',
                }, context)
                as Map<String, dynamic>;

        expect(extracted['action'], 'macro_research_extract');
        expect(extracted['status'], 'ok');
        expect(extracted['extracted'], 1);
        expect(extracted['failed'], 0);
        final row = ((extracted['rows'] as List).first as Map);
        expect(row['family'], 'macro_official_series');
        expect(row['source_url'], selected);
        expect(row['source_published_at'], '2026-07-04');
        final values = row['macro_values'] as Map;
        expect(values['title'], '2026年6月下旬流通领域重要生产资料市场价格变动情况');
        expect(values['bodyPreview'], contains('电解铜'));
        expect(values['bodyPreview'], isNot(contains('首页 数据')));
      },
    );

    test('macro_research_extraction_status covers current providers', () async {
      final service = MarketDataActionService();
      final context = ToolContext(basePath: '', serviceBaseUrl: '');
      final status =
          await service.run(
                'macro_research_extraction_status',
                const [],
                const {},
                context,
              )
              as Map<String, dynamic>;
      expect(status['action'], 'macro_research_extraction_status');
      final rows = (status['rows'] as List).cast<Map<String, dynamic>>();
      expect(rows.length, greaterThanOrEqualTo(25));
      final byProvider = {for (final row in rows) row['provider']: row};
      expect(
        byProvider['goldman_sachs']?['contentExtractorStatus'],
        'implemented',
      );
      expect(
        byProvider['goldman_sachs']?['keyClaimExtractorStatus'],
        'bounded-structural-extraction',
      );
      expect(
        byProvider['msci']?['canonicalEvidenceFamily'],
        'macro_index_event',
      );
      expect(byProvider['msci']?['pdfExtractorStatus'], 'minimal-text-parser');
      expect(
        byProvider['pboc_policy_reports']?['canonicalEvidenceFamily'],
        'macro_policy_event',
      );
      expect(
        byProvider['nbs_data_releases']?['canonicalEvidenceFamily'],
        'macro_official_series',
      );
      expect(
        byProvider['hkex_news_releases']?['contentExtractorStatus'],
        'not-extracted',
      );
      expect(
        byProvider['hkex_news_releases']?['contentHashReadbackStatus'],
        'retrieval-evidence-only',
      );
      expect(
        byProvider['szse_notice_api']?['contentExtractorStatus'],
        'implemented',
      );
      expect(
        byProvider['szse_notice_api']?['canonicalEvidenceFamily'],
        'macro_policy_event',
      );
      expect(
        byProvider['szse_notice_api']?['allowedRetrievalMethod'],
        'official_api',
      );
      expect(
        byProvider['safe_statistics']?['contentHashReadbackStatus'],
        'supported',
      );
      expect(byProvider['cme']?['contentExtractorStatus'], 'not-extracted');
      expect(
        byProvider['cme']?['contentHashReadbackStatus'],
        'retrieval-evidence-only',
      );
      expect(
        byProvider['sp_dji']?['contentHashReadbackStatus'],
        'retrieval-evidence-only',
      );
      expect(
        byProvider['pboc']?['canonicalEvidenceFamily'],
        'macro_policy_event',
      );
      expect(
        byProvider['vanguard']?['canonicalEvidenceFamily'],
        'macro_research_document',
      );
    });
  });
}

class _MacroResearchFakeClient extends http.BaseClient {
  _MacroResearchFakeClient(this.responses);

  final Map<String, String> responses;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = responses[request.url.toString()];
    if (body == null) {
      return http.StreamedResponse(Stream.value(const <int>[]), 404);
    }
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      200,
      headers: {'content-type': 'text/html; charset=utf-8'},
    );
  }
}
