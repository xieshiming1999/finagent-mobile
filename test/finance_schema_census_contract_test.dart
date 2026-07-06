import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/artifact_registry.dart';
import 'package:finagent/agent/data_fetcher/finance_schema_census.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinAgent finance schema census contract', () {
    test('registers the shared mobile census as a FinAgent data snapshot', () {
      final dir = Directory.systemTemp.createTempSync(
        'finagent_schema_census_',
      );
      addTearDown(() => dir.deleteSync(recursive: true));

      final record = FinanceSchemaCensusRegistry(
        dir.path,
      ).register(runtime: 'finagent', now: DateTime.utc(2026, 6, 17, 12));

      expect(record.kind, ArtifactKind.dataSnapshot);
      expect(record.ownerTask, financeSchemaCensusOwnerTask);
      expect(record.verificationStatus, ArtifactVerificationStatus.verified);
      expect(record.metadata['runtime'], 'finagent');
      expect(record.provenance['finagentReuse'], contains('finagent/lib'));

      final payload = jsonDecode(File(record.path).readAsStringSync());
      expect(payload['runtime'], 'finagent');
      expect(payload['summary']['total'], mobileFinanceSchemaSurfaces.length);
      expect(
        payload['surfaces'].map((row) => row['id']),
        containsAll([
          'stock.quote',
          'stock.daily_kline',
          'market.margin_trading',
          'market.screening',
          'global.company_profile',
          'wind.financial_document',
        ]),
      );
      final surfaces = (payload['surfaces'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      final fundSurface = surfaces.firstWhere(
        (row) => row['id'] == 'fund.nav_history',
      );
      expect(fundSurface['queryActions'], contains('query_fund_nav'));
      expect(fundSurface['canonicalTables'], contains('fund_nav'));
      expect(fundSurface['runtimeDependency'], 'mobile-native');
      final marginSurface = surfaces.firstWhere(
        (row) => row['id'] == 'market.margin_trading',
      );
      expect(marginSurface['queryActions'], contains('query_margin_trading'));
      expect(marginSurface['canonicalTables'], contains('margin_trading'));
      expect(marginSurface['liveProbeStatus'], 'contract-tested');
      expect(marginSurface['runtimeDependency'], 'mobile-native');
      expect(
        marginSurface['classification'],
        'supported-reusable-schema',
      );
      final windSurface = surfaces.firstWhere(
        (row) => row['id'] == 'wind.financial_document',
      );
      expect(windSurface['liveProbeStatus'], 'credential-gated-live');
      expect(
        windSurface['runtimeDependency'],
        'configured-provider-credential',
      );
    });
  });
}
