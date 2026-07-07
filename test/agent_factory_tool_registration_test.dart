import 'dart:io';

import 'package:finagent/agent/tools/wind_mcp_tool/wind_mcp_tool.dart';
import 'package:finagent/shared/agent_factory.dart';
import 'package:finagent/shared/api_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync(
      'finagent_agent_factory_tool_registration_test_',
    );
  });

  tearDown(() {
    if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
  });

  test('does not expose WindMcp when WIND_API_KEY is missing', () {
    final config = ApiConfigStore();
    final runtime = createAgentRuntime(
      basePath: tmpDir.path,
      serverUrl: '',
      featurePrompt: 'test',
      skipPermissions: true,
      enableWatchlistRefresher: false,
      apiConfig: config,
    );
    addTearDown(() {
      runtime.agent.stopAutoProcessing();
      runtime.monitorScheduler.stop();
      runtime.cronScheduler.stop();
    });

    expect(runtime.agent.findTool<WindMcpTool>(), isNull);
  });

  test('exposes WindMcp when WIND_API_KEY is configured', () {
    final config = ApiConfigStore()..set('WIND_API_KEY', 'test-key');
    final runtime = createAgentRuntime(
      basePath: tmpDir.path,
      serverUrl: '',
      featurePrompt: 'test',
      skipPermissions: true,
      enableWatchlistRefresher: false,
      apiConfig: config,
    );
    addTearDown(() {
      runtime.agent.stopAutoProcessing();
      runtime.monitorScheduler.stop();
      runtime.cronScheduler.stop();
    });

    expect(runtime.agent.findTool<WindMcpTool>(), isNotNull);
  });
}
