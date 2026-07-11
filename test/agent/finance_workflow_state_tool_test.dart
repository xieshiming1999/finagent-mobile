import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/finance_workflow_state_tool/finance_workflow_state_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('FinanceWorkflowState creates explicit typed workflow state', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_finance_workflow_state_tool_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final tool = FinanceWorkflowStateTool();
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

    final result = await tool.call('tool-1', {
      'action': 'create',
      'workflowKind': 'trade_prep',
      'assetClass': 'stock',
      'intentMode': 'size',
      'executionMode': 'requires_confirmation',
      'confirmationState': 'pending',
      'safetyBoundary': 'trade preparation only',
      'evidenceRefs': ['trade-prep-v1'],
      'subject': '600519',
    }, context);

    expect(result.isError, isFalse);
    final decoded = jsonDecode(result.content) as Map<String, dynamic>;
    expect(decoded['contract'], 'finance-workflow-state-result-v1');
    expect(decoded['workflowState']['contract'], 'finance-workflow-state-v1');
    expect(decoded['workflowState']['workflowKind'], 'trade_prep');
    expect(decoded['workflowState']['subject'], '600519');
  });

  test('FinanceWorkflowState rejects incomplete state with correction guidance', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_finance_workflow_state_tool_error_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final tool = FinanceWorkflowStateTool();
    final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');

    final result = await tool.call('tool-2', {
      'action': 'create',
      'workflowKind': 'trade_prep',
    }, context);

    expect(result.isError, isTrue);
    expect(result.content, contains('Invalid finance workflow state'));
    expect(result.content, contains('assetClass must be one of'));
    expect(result.content, contains('Use FinanceWorkflowState(action:"help")'));
  });
}
