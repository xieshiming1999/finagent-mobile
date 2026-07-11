import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/recovery_planner_tool/recovery_planner_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'RecoveryPlanner infers repeated tool failure from session evidence',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      _seedRepeatedFailures(context);

      final plan =
          jsonDecode(
                (await RecoveryPlannerTool().call('recover-1', {
                  'action': 'plan',
                  'failureClass': 'auto',
                }, context)).content,
              )
              as Map<String, dynamic>;

      expect(plan['contract'], 'recovery-planner-plan-v1');
      expect(plan['failureClass'], 'repeated_tool_failure');
      expect(plan['recommended']['id'], 'stop_repeating_call');
      expect(plan['recommended']['stopBeforeFinalAnswer'], true);
    },
  );

  test('RecoveryPlanner returns typed credential recovery', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final plan =
        jsonDecode(
              (await RecoveryPlannerTool().call('recover-2', {
                'action': 'plan',
                'failureClass': 'credential_required',
                'provider': 'wind',
              }, context)).content,
            )
            as Map<String, dynamic>;

    expect(plan['failureClass'], 'credential_required');
    expect(plan['recommended']['id'], 'request_or_configure_credential');
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync('finagent_recovery_test_');
  return ToolContext(basePath: dir.path, serviceBaseUrl: '');
}

void _seedRepeatedFailures(ToolContext context) {
  final dir = Directory('${context.basePath}/sessions')
    ..createSync(recursive: true);
  final rows = <String>[];
  for (var i = 0; i < 3; i++) {
    rows.add(
      jsonEncode({
        'type': 'message',
        'role': 'assistant',
        'toolUses': [
          {
            'id': 'tool-$i',
            'name': 'MarketData',
            'input': {'action': 'query_quote', 'symbol': '300059'},
          },
        ],
      }),
    );
    rows.add(
      jsonEncode({
        'type': 'message',
        'role': 'tool',
        'toolResult': {
          'toolUseId': 'tool-$i',
          'content': 'unknown action',
          'isError': true,
        },
      }),
    );
  }
  File('${dir.path}/current.jsonl').writeAsStringSync(rows.join('\n'));
}
