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
    final service = MacroFactorRadarService(store: ReusableDataStore(dir.path));

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
            height: 720,
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

    expect(find.text('Factor Radar'), findsOneWidget);
    expect(find.textContaining('MSCI Indonesia'), findsOneWidget);
    expect(find.textContaining('Indonesia equities'), findsWidgets);
    expect(find.textContaining('manual_seed'), findsWidgets);
  });
}
