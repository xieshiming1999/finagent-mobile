import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/artifact_registry.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/workflow_verifier_tool/workflow_verifier_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('WorkflowVerifier passes with tool and artifact evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'MarketData');
    ArtifactRegistry(context.basePath).register(
      kind: ArtifactKind.analysis,
      path: 'memory/reports/stock-analysis.md',
      title: 'Stock analysis',
      source: 'agent-workflow',
      verificationStatus: ArtifactVerificationStatus.verified,
    );

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-1', {
                'action': 'check',
                'workflow': 'stock_research',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['contract'], 'workflow-verifier-check-v1');
    expect(result['passed'], true);
    expect(result['missing'], isEmpty);
    expect(result['observed']['toolNames'], contains('MarketData'));
  });

  test('WorkflowVerifier reports missing artifact evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'MarketData');

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-2', {
                'action': 'check',
                'workflow': 'stock_research',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['passed'], false);
    expect(result['missing'], contains('artifact_evidence'));
    expect(result['nextAction'], contains('Do not finalize yet'));
  });

  test(
    'WorkflowVerifier rejects unknown workflow through tool error',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final result = await WorkflowVerifierTool().call('verify-3', {
        'action': 'check',
        'workflow': 'unknown',
      }, context);

      expect(result.isError, true);
      expect(result.content, contains('Unknown WorkflowVerifier workflow'));
    },
  );
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_workflow_verifier_tool_test_',
  );
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}

void _seedSession(ToolContext context, {required String toolName}) {
  final dir = Directory('${context.basePath}/sessions')
    ..createSync(recursive: true);
  final file = File('${dir.path}/current.jsonl');
  file.writeAsStringSync(
    [
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'toolUses': [
          {'id': 'tool-1', 'name': toolName, 'input': {}},
        ],
      }),
      jsonEncode({
        'type': 'message',
        'role': 'tool',
        'toolResult': {
          'toolUseId': 'tool-1',
          'content': '{}',
          'isError': false,
        },
      }),
    ].join('\n'),
  );
}
