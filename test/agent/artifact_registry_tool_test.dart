import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/artifact_registry_tool/artifact_registry_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'ArtifactRegistry registers, lists, and gets durable artifacts',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final tool = ArtifactRegistryTool();

      final created =
          jsonDecode(
                (await tool.call('artifact-1', {
                  'action': 'register',
                  'kind': 'analysis',
                  'path': 'memory/reports/stock-analysis.md',
                  'title': 'Stock analysis',
                  'source': 'agent-workflow',
                  'verificationStatus': 'verified',
                  'freshness': {'status': 'fresh'},
                  'provenance': {'workflow': 'stock_research'},
                  'links': ['workflow:stock_research'],
                  'metadata': {'templateId': 'stock_research'},
                }, context)).content,
              )
              as Map<String, dynamic>;
      final artifact = created['artifact'] as Map<String, dynamic>;
      expect(created['contract'], 'artifact-registry-record-v1');
      expect(artifact['kind'], 'analysis');
      expect(artifact['stableRef'], startsWith('artifact:analysis:'));
      expect(artifact['verificationStatus'], 'verified');
      expect(artifact['freshness'], {'status': 'fresh'});

      final list =
          jsonDecode(
                (await tool.call('artifact-2', {
                  'action': 'list',
                  'kind': 'analysis',
                }, context)).content,
              )
              as Map<String, dynamic>;
      expect(list['contract'], 'artifact-registry-list-v1');
      expect(list['count'], 1);

      final get =
          jsonDecode(
                (await tool.call('artifact-3', {
                  'action': 'get',
                  'id': artifact['stableRef'],
                }, context)).content,
              )
              as Map<String, dynamic>;
      expect(get['artifact']['title'], 'Stock analysis');

      final graph =
          jsonDecode(
                (await tool.call('artifact-graph', {
                  'action': 'graph',
                  'kind': 'analysis',
                }, context)).content,
              )
              as Map<String, dynamic>;
      expect(graph['contract'], 'artifact-evidence-graph-v1');
      expect(graph['artifactCount'], 1);
      expect(
        graph['nodes'],
        contains(containsPair('id', artifact['stableRef'])),
      );
      expect(
        graph['edges'],
        contains(
          allOf([
            containsPair('from', artifact['stableRef']),
            containsPair('relation', 'from_source'),
          ]),
        ),
      );
    },
  );

  test(
    'ArtifactRegistry rejects register input without title/source',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final result = await ArtifactRegistryTool().call('artifact-4', {
        'action': 'register',
        'kind': 'analysis',
        'title': 'Stock analysis',
      }, context);

      expect(result.isError, true);
      expect(result.content, contains('requires non-empty title and source'));
    },
  );

  test('ArtifactRegistry help discloses managed register requirements', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final tool = ArtifactRegistryTool();
    final help =
        jsonDecode(
              (await tool.call('artifact-help', {
                'action': 'help',
              }, context)).content,
            )
            as Map<String, dynamic>;
    final guidance = (help['guidance'] as List).join('\n');
    final schema = tool.inputSchema['properties'] as Map<String, dynamic>;

    expect(guidance, contains('kind, title, and source'));
    expect(
      (schema['source'] as Map<String, dynamic>)['description'],
      contains('Required for register'),
    );
  });

  test('ArtifactRegistry creates managed artifact file without path', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final decoded =
        jsonDecode(
              (await ArtifactRegistryTool().call('artifact-managed', {
                'action': 'register',
                'kind': 'macro_evidence',
                'title': 'Energy macro evidence',
                'source': 'EIA',
                'metadata': {
                  'topic': 'energy',
                  'affectedAssets': ['energy equities'],
                },
              }, context)).content,
            )
            as Map<String, dynamic>;
    final artifact = decoded['artifact'] as Map<String, dynamic>;

    expect(decoded['contract'], 'artifact-registry-record-v1');
    expect(decoded['managedArtifact'], true);
    expect(
      artifact['path'],
      matches(
        RegExp(r'^memory[/\\]artifacts[/\\]macro_evidence[/\\].+\.json$'),
      ),
    );
    expect(File('${context.basePath}/${artifact['path']}').existsSync(), true);
  });

  test(
    'ArtifactRegistry normalizes macro evidence into report artifacts',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final decoded =
          jsonDecode(
                (await ArtifactRegistryTool().call('artifact-macro-report', {
                  'action': 'register',
                  'kind': 'report',
                  'title': 'Macro factor report',
                  'source': 'macro workflow',
                  'metadata': {
                    'topic': 'energy',
                    'affectedAssets': ['oil', 'energy equities'],
                    'missingEvidence': ['second official source'],
                    'confidenceEffect':
                        'raises confidence for energy-sensitive watch conditions',
                    'sourceDataTime': '2026-07-03',
                    'fetchedAt': '2026-07-12T04:00:00Z',
                    'freshnessStatus': 'stale',
                    'failureClass': 'credential-or-quota-required',
                  },
                }, context)).content,
              )
              as Map<String, dynamic>;
      final artifact = decoded['artifact'] as Map<String, dynamic>;
      final summary =
          (artifact['metadata'] as Map<String, dynamic>)['macroEvidenceSummary']
              as Map<String, dynamic>;

      expect(summary['contract'], 'macro-artifact-evidence-summary-v1');
      expect(summary['topic'], 'energy');
      expect(summary['sourceTime'], '2026-07-03');
      expect(summary['fetchedAt'], '2026-07-12T04:00:00Z');
      expect(summary['freshnessStatus'], 'stale');
      expect(
        summary['confidenceEffect'],
        'raises confidence for energy-sensitive watch conditions',
      );
      expect(summary['affectedAssets'], ['oil', 'energy equities']);
      expect(summary['missingEvidence'], ['second official source']);
      expect(summary['failureClass'], 'credential-or-quota-required');

      expect(
        (artifact['provenance'] as Map<String, dynamic>)['failureClass'],
        'credential-or-quota-required',
      );
      expect(
        (artifact['provenance']
            as Map<String, dynamic>)['macroEvidenceSummary'],
        summary,
      );
      expect(artifact['freshness'], {
        'sourceTime': '2026-07-03',
        'fetchedAt': '2026-07-12T04:00:00Z',
        'status': 'stale',
      });
      final stored =
          jsonDecode(
                File(
                  '${context.basePath}/${artifact['path']}',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(stored['macroEvidenceSummary'], summary);
    },
  );
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_artifact_registry_tool_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}
