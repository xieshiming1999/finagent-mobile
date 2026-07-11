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
    },
  );

  test('ArtifactRegistry rejects incomplete register input', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final result = await ArtifactRegistryTool().call('artifact-4', {
      'action': 'register',
      'kind': 'analysis',
      'path': 'memory/reports/stock-analysis.md',
    }, context);

    expect(result.isError, true);
    expect(
      result.content,
      contains('requires non-empty path, title, and source'),
    );
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_artifact_registry_tool_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}
