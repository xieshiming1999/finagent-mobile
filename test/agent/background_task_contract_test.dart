import 'dart:convert';
import 'dart:io';

import 'package:finagent/agent/agent.dart';
import 'package:finagent/agent/background_task.dart';
import 'package:finagent/agent/llm_client.dart';
import 'package:finagent/agent/message.dart';
import 'package:finagent/agent/prompt_builder.dart';
import 'package:finagent/agent/session.dart';
import 'package:finagent/agent/tool.dart';
import 'package:finagent/agent/tool_context.dart';
import 'package:finagent/agent/tools/agent_tool/agent_tool.dart';
import 'package:finagent/agent/tools/task_output_tool/task_output_tool.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('TaskOutput returns completed background task output', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final task = context.taskRegistry.register(
      description: 'research',
      prompt: 'inspect',
      toolUseId: 'agent-call',
      parentSessionId: 'parent-session',
      isBackgrounded: true,
    );
    context.taskRegistry.updateStatus(
      task.id,
      BackgroundTaskStatus.completed,
      result: 'done',
    );

    final result = await TaskOutputTool().call('task-output', {
      'task_id': task.id,
      'block': false,
    }, context);
    final decoded = jsonDecode(result.content) as Map<String, dynamic>;

    expect(result.isError, isFalse);
    expect(decoded['retrieval_status'], 'success');
    expect(decoded['task_id'], task.id);
    expect(decoded['status'], 'completed');
    expect(decoded['result'], 'done');
  });

  test(
    'TaskOutput reports failed background tasks through error channel',
    () async {
      final context = _tempContext();
      addTearDown(() {
        final dir = Directory(context.basePath);
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final task = context.taskRegistry.register(
        description: 'research',
        prompt: 'inspect',
        isBackgrounded: true,
      );
      context.taskRegistry.updateStatus(
        task.id,
        BackgroundTaskStatus.failed,
        error: 'sub-agent crashed',
      );

      final result = await TaskOutputTool().call('task-output', {
        'task_id': task.id,
        'block': false,
      }, context);
      final decoded = jsonDecode(result.content) as Map<String, dynamic>;

      expect(result.isError, isTrue);
      expect(decoded['retrieval_status'], 'failed');
      expect(decoded['status'], 'failed');
      expect(decoded['error'], 'sub-agent crashed');
    },
  );

  test('TaskOutput validates expected output contract and evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final task = context.taskRegistry.register(
      description: 'research',
      prompt: 'inspect',
      isBackgrounded: true,
    );
    context.taskRegistry.updateStatus(
      task.id,
      BackgroundTaskStatus.completed,
      result: jsonEncode({
        'contract': 'task-analysis-v1',
        'evidenceRefs': ['quote', 'macro'],
        'summary': 'done',
      }),
    );

    final result = await TaskOutputTool().call('task-output', {
      'task_id': task.id,
      'block': false,
      'expectedContract': 'task-analysis-v1',
      'requiredEvidence': ['quote', 'macro'],
    }, context);

    expect(result.isError, isFalse);
    expect(jsonDecode(result.content)['retrieval_status'], 'success');
  });

  test('TaskOutput fails validation for missing required evidence', () async {
    final context = _tempContext();
    addTearDown(() {
      final dir = Directory(context.basePath);
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final task = context.taskRegistry.register(
      description: 'research',
      prompt: 'inspect',
      isBackgrounded: true,
    );
    context.taskRegistry.updateStatus(
      task.id,
      BackgroundTaskStatus.completed,
      result: jsonEncode({
        'contract': 'task-analysis-v1',
        'evidenceRefs': ['quote'],
      }),
    );

    final result = await TaskOutputTool().call('task-output', {
      'task_id': task.id,
      'block': false,
      'expectedContract': 'task-analysis-v1',
      'requiredEvidence': ['quote', 'macro'],
    }, context);
    final decoded = jsonDecode(result.content) as Map<String, dynamic>;

    expect(result.isError, isTrue);
    expect(decoded['retrieval_status'], 'validation_failed');
    expect(decoded['outputValidation']['missingEvidence'], ['macro']);
  });

  test('Agent help teaches TaskOutput requirement before delegation', () async {
    final dir = Directory.systemTemp.createTempSync(
      'finagent_agent_help_test_',
    );
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    final context = ToolContext(
      basePath: dir.path,
      serviceBaseUrl: '',
      skipPermissions: true,
    );
    final sessionManager = SessionManager(sessionsDir: '${dir.path}/sessions')
      ..loadOrCreate(feature: 'test');
    final parentAgent = Agent(
      client: _FakeLLMClient(),
      tools: const [],
      promptBuilder: PromptBuilder(basePrompt: 'test', basePath: dir.path),
      toolContext: context,
      sessionManager: sessionManager,
      enableBackgroundHooks: false,
    );
    final agentTool = AgentTool(parentAgent: parentAgent);
    final result = await agentTool.call('agent-help', {
      'action': 'help',
    }, context);

    expect(result.isError, isFalse);
    expect(result.content, contains('"background"'));
    expect(result.content, contains('TaskOutput'));
    expect(
      result.content,
      contains('If the current answer depends on a background sub-agent'),
    );
  });
}

ToolContext _tempContext() {
  final dir = Directory.systemTemp.createTempSync(
    'finagent_task_output_contract_test_',
  );
  final context = ToolContext(basePath: dir.path, serviceBaseUrl: '');
  context.taskRegistry.basePath = context.memoryDir;
  return context;
}

class _FakeLLMClient extends LLMClient {
  @override
  LLMClient clone() => _FakeLLMClient();

  @override
  Stream<SSEEvent> sendMessage({
    required List<Message> messages,
    required List<Tool> tools,
    String? systemPrompt,
    int? maxOutputTokens,
    String? model,
  }) async* {
    yield SSETextDelta('ok');
    yield SSEDone();
  }
}
