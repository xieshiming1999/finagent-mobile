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

  test('WorkflowVerifier accepts matching typed workflow state', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    _seedSession(context, toolName: 'MarketData');
    _seedWorkflowState(context, workflowKind: 'stock_research');
    ArtifactRegistry(context.basePath).register(
      kind: ArtifactKind.analysis,
      path: 'memory/reports/stock-analysis.md',
      title: 'Stock analysis',
      source: 'agent-workflow',
      verificationStatus: ArtifactVerificationStatus.verified,
    );

    final result =
        jsonDecode(
              (await WorkflowVerifierTool().call('verify-state', {
                'action': 'check',
                'workflow': 'stock_research',
                'requireWorkflowState': true,
                'providerHealth': [
                  {'provider': 'tdx', 'status': 'healthy'},
                ],
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['passed'], true);
    expect(result['missing'], isEmpty);
    expect(result['observed']['workflowState']['id'], 'state-1');
  });

  test('WorkflowVerifier fails on blocking provider health', () async {
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
              (await WorkflowVerifierTool().call('verify-health', {
                'action': 'check',
                'workflow': 'stock_research',
                'providerHealth': [
                  {'provider': 'eastmoney', 'status': 'transport_unstable'},
                ],
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(result['passed'], false);
    expect(result['missing'], contains('provider_health'));
    expect(
      result['checks'].firstWhere(
        (check) => check['id'] == 'provider_health',
      )['message'],
      contains('eastmoney:transport_unstable'),
    );
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

void _seedWorkflowState(ToolContext context, {required String workflowKind}) {
  final dir = Directory('${context.memoryDir}/workflows')
    ..createSync(recursive: true);
  File('${dir.path}/state.json').writeAsStringSync(
    jsonEncode({
      'contract': 'workflow-state-store-v1',
      'records': [
        {
          'id': 'state-1',
          'contract': 'workflow-state-record-v1',
          'status': 'active',
          'workflowState': {
            'contract': 'finance-workflow-state-v1',
            'workflowKind': workflowKind,
            'assetClass': 'stock',
            'intentMode': 'analysis',
            'executionMode': 'preview_only',
            'safetyBoundary': 'no_trade',
            'evidenceRefs': ['quote'],
            'confirmationState': 'none',
            'source': 'test',
          },
          'requiredEvidence': ['quote'],
          'completedSteps': ['quote'],
          'generatedArtifacts': [],
          'updatedAt': '2026-07-11T00:00:00.000Z',
        },
      ],
    }),
  );
}
