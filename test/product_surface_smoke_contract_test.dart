import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FinAgent product surface smoke contract', () {
    for (final surface in _surfaces) {
      test('${surface.id} exposes useful states and actions', () {
        final text = surface.files.map(_read).join('\n');
        for (final pattern in surface.requiredPatterns) {
          expect(
            text,
            contains(pattern),
            reason: '${surface.id} missing "$pattern"',
          );
        }
      });
    }
  });
}

class _SurfaceContract {
  const _SurfaceContract({
    required this.id,
    required this.files,
    required this.requiredPatterns,
  });

  final String id;
  final List<String> files;
  final List<String> requiredPatterns;
}

const _surfaces = [
  _SurfaceContract(
    id: 'watchlist',
    files: ['lib/shared/watchlist_panel.dart'],
    requiredPatterns: [
      'l10n.noWatchlists',
      'l10n.emptyListPrompt',
      'searchCachedAssets',
      'suggestions',
      'onAnalyze',
      'removeItem',
    ],
  ),
  _SurfaceContract(
    id: 'monitor-card-watchlist',
    files: ['lib/shared/monitor_panel_cards.dart'],
    requiredPatterns: [
      'WatchlistCard',
      'watchlistMiniCount',
      'formatMonitorValue',
      'hasError',
    ],
  ),
  _SurfaceContract(
    id: 'api-health-data-manager',
    files: ['lib/features/finance/build_helpers_api_health.dart'],
    requiredPatterns: [
      'l10n.apiHealth',
      'l10n.reusableData',
      'l10n.dataTasks',
      'financeDataContractSteps',
      'FinanceSchemaCensusRegistry',
      'financeSchemaCensusTitle',
      'schemaArtifactRef',
      'l10n.noData',
      'l10n.decisionHistory',
    ],
  ),
  _SurfaceContract(
    id: 'history-and-session',
    files: [
      'lib/features/finance/build_helpers_sessions.dart',
      'lib/features/finance/build_helpers_toolbar.dart',
    ],
    requiredPatterns: [
      'l10n.history',
      'l10n.noHistoryYet',
      'l10n.noSessionsToResume',
      '_resumeSession',
      'l10n.emptySession',
      'api_health',
    ],
  ),
];

String _read(String path) => File(path).readAsStringSync();
