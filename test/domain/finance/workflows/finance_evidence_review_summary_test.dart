import 'package:finagent/agent/message.dart';
import 'package:finagent/domain/finance/workflows/finance_workflow_hooks.dart';
import 'package:flutter_test/flutter_test.dart';

const _evidenceReviewState = '''
data: {"workflowState":{"contract":"finance-workflow-state-v1","workflowKind":"evidence_review","assetClass":"mixed","intentMode":"review","executionMode":"preview_only","safetyBoundary":"read-only evidence review","evidenceRefs":["analysis-evidence-v1","prior-analysis"],"confirmationState":"none","source":"agent-structured-intent"}}
''';

void main() {
  test('structured evidence review state triggers session search preflight', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(
        role: Role.user,
        content: 'please inspect saved context\n$_evidenceReviewState',
      ),
    ]);

    expect(calls, isNotNull);
    expect(calls, hasLength(4));
    expect(calls!.map((call) => call.name).toSet(), {'SessionSearch'});
  });

  test('plain arbitrary text does not trigger evidence review preflight', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final calls = hooks.buildPreflightToolCalls([
      Message(role: Role.user, content: 'please inspect saved context'),
    ]);

    expect(calls, isNull);
  });

  test('uses structured SessionSearch rows as evidence excerpts', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final answer = hooks.buildPreflightAnswer([
      Message(role: Role.user, content: 'anything\n$_evidenceReviewState'),
      Message(
        role: Role.assistant,
        toolUses: const [
          ToolUse(
            id: 'self',
            name: 'SessionSearch',
            input: {'query': 'analysis'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'self',
          content: '''
{
  "contract": "session-search-result-v1",
  "mode": "search",
  "query": "analysis",
  "count": 1,
  "results": [
    {
      "sessionId": "s1",
      "title": "历史股票建议",
      "snippet": "assistant: Watchlist add 300059 with risk boundary",
      "timestamp": "2026-07-01T10:00:00.000Z"
    }
  ]
}
''',
        ),
      ),
    ]);

    expect(answer, contains('历史股票建议'));
    expect(answer, contains('session:s1'));
    expect(answer, contains('Watchlist add 300059'));
  });

  test('structured empty SessionSearch results produce no-evidence answer', () {
    final hooks = FinanceWorkflowHooks(isBypassTool: (_) => false);

    final answer = hooks.buildPreflightAnswer([
      Message(role: Role.user, content: 'anything\n$_evidenceReviewState'),
      Message(
        role: Role.assistant,
        toolUses: const [
          ToolUse(
            id: 'empty',
            name: 'SessionSearch',
            input: {'query': 'analysis'},
          ),
        ],
      ),
      Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: 'empty',
          content:
              '{"contract":"session-search-result-v1","mode":"search","query":"analysis","count":0,"results":[]}',
        ),
      ),
    ]);

    expect(answer, contains('没有找到可复核的历史股票或基金建议正文'));
  });
}
