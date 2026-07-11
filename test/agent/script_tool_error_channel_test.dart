import 'dart:io';

import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/script_tool/script_tool.dart'
    as agent_script;
import 'package:finagent/shared/script_tool/script_tool.dart' as shared_script;
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late ToolContext context;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('finagent_script_error_test_');
    context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test(
    'shared ScriptTool reports native bridge errors through tool error channel',
    () async {
      final tool = shared_script.ScriptTool();

      final result = await tool.call('shared-script-error', {
        'code': 'Bridge.hash("abc", "unsupported")',
      }, context);

      expect(result.isError, isTrue);
      expect(
        result.content,
        contains('Bridge channel failed: Error: Unsupported algorithm'),
      );
    },
  );

  test(
    'agent ScriptTool reports native bridge errors through tool error channel',
    () async {
      final tool = agent_script.ScriptTool();

      final result = await tool.call('agent-script-error', {
        'code': 'return "Error: synthetic bridge failure";',
      }, context);

      expect(result.isError, isTrue);
      expect(
        result.content,
        contains('Bridge channel failed: Error: synthetic bridge failure'),
      );
    },
  );
}
