import 'dart:io';

import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';
import 'package:finagent/domain/market/services/macro_factor_radar_service.dart';
import 'package:flutter_test/flutter_test.dart';

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
      expect(msci['retrieval_test'], isA<Map>());
      expect(
        (msci['retrieval_test'] as Map)['candidate_schema'],
        'market_moving_factor_v1',
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

        final service = MacroFactorRadarService(store: store);
        final result = await service.refresh();
        final row = result.rows.firstWhere(
          (item) => '${item['factor_id']}'.startsWith('news:cached:'),
        );
        expect(row['family'], 'narrative_attention');
        expect(row['source_type'], 'cached_finance_news');
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
      },
    );
  });
}
