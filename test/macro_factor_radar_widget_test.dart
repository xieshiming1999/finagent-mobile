import 'dart:io';

import 'package:finagent/agent/data_fetcher/reusable_data_store.dart';
import 'package:finagent/domain/market/services/macro_factor_radar_service.dart';
import 'package:finagent/features/finance/finagent_screen.dart';
import 'package:finagent/shared/i18n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('FactorRadarSheet renders seeded macro factor provenance', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_macro_factor_widget_',
    );
    addTearDown(() => dir.deleteSync(recursive: true));
    final service = _FakeMacroFactorRadarService(
      store: ReusableDataStore(dir.path),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          ...AppLocalizations.localizationsDelegates,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 1400,
            child: FactorRadarSheet(
              basePath: dir.path,
              service: service,
              onAnalyze: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Macro Research'), findsOneWidget);
    expect(find.text('Source coverage'), findsOneWidget);
    expect(find.text('Official numeric series'), findsOneWidget);
    expect(find.text('Asset'), findsOneWidget);
    expect(find.text('Region'), findsOneWidget);
    expect(find.text('Retrieval'), findsOneWidget);

    for (var i = 0; i < 8 && find.text('Evidence').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
    }
    expect(find.text('US 10Y Treasury yield'), findsOneWidget);
    expect(find.text('Evidence'), findsOneWidget);
    for (var i = 0; i < 8 && find.text('Reliability').evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pumpAndSettle();
    }
    expect(find.text('Reliability'), findsOneWidget);
    expect(find.text('Asset impact'), findsOneWidget);
    expect(find.text('Decision support'), findsOneWidget);
    expect(find.textContaining('freshness:'), findsWidgets);
    expect(find.textContaining('confidence effect:'), findsWidgets);
  });
}

class _FakeMacroFactorRadarService extends MacroFactorRadarService {
  _FakeMacroFactorRadarService({required super.store});

  @override
  MacroFactorRadarResult read() {
    return const MacroFactorRadarResult(
      generatedAt: '2026-07-08T00:00:00Z',
      sources: [
        {
          'id': 'manual.msci',
          'name': 'MSCI official/manual seed',
          'state': 'fallback-only',
          'detail': 'Manual official-source evidence; use browser/PDF path.',
        },
      ],
      numericSeriesCatalog: [
        {
          'id': 'fred.DGS10',
          'provider': 'fred',
          'sourceName': 'FRED',
          'seriesId': 'DGS10',
          'metricName': 'US 10Y Treasury yield',
          'frequency': 'daily',
          'unit': 'percent',
          'credentialKey': 'FRED_API_KEY',
          'status': 'credential-gated',
          'nextAction': 'Configure FRED_API_KEY or use local readback.',
        },
      ],
      rows: [
        {
          'factor_id': 'manual:index_classification:msci:indonesia-watch',
          'family': 'index_classification',
          'title': 'MSCI Indonesia market-classification watch',
          'summary':
              'Index-provider classification evidence for passive-flow context.',
          'source_name': 'MSCI',
          'source_type': 'manual_seed',
          'source_published_at': null,
          'fetched_at': '2026-07-08T00:00:00Z',
          'affected_assets': ['Indonesia equities'],
          'affected_regions': ['Indonesia'],
          'affected_sectors': [],
          'transmission_channels': ['passive benchmark flow'],
          'expected_direction': 'mixed',
          'severity': 'medium',
          'confidence': 'medium',
          'status': 'watch',
          'retrieval_test': {
            'provider': 'manual',
            'interface_id': 'macro.factor_radar',
            'capability_id': 'manual.msci',
            'candidate_schema': 'market_moving_factor_v1',
            'status': 'fallback-only',
            'error': null,
          },
        },
      ],
    );
  }
}
