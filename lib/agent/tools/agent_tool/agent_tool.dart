import 'dart:async';

import 'package:path/path.dart' as p;

import '../../agent.dart';
import '../../background_task.dart';
import '../../message.dart';
import '../../prompt_builder.dart';
import '../../session.dart';
import '../../team_context.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../file_edit_tool/file_edit_tool.dart';
import '../file_read_tool/file_read_tool.dart';
import '../file_write_tool/file_write_tool.dart';
import '../file_manage_tool/file_manage_tool.dart';
import '../glob_tool/glob_tool.dart';
import '../grep_tool/grep_tool.dart';
import '../ls_tool/ls_tool.dart';
import '../send_message_tool/send_message_tool.dart';
import '../skill_tool/skill_tool.dart';
import '../task_create_tool/task_create_tool.dart';
import '../task_get_tool/task_get_tool.dart';
import '../task_list_tool/task_list_tool.dart';
import '../task_update_tool/task_update_tool.dart';
import '../enter_plan_mode_tool/enter_plan_mode_tool.dart';
import '../exit_plan_mode_tool/exit_plan_mode_tool.dart';
import 'prompt.dart' as tool_prompt;

/// Launches a sub-agent to handle tasks autonomously.
///
/// Supports sync (foreground) and async (background) execution,
/// with fork (inherit parent context) and independent modes.
///
/// Reference: claude-code-best/src/tools/AgentTool/AgentTool.tsx
class AgentTool extends Tool {
  /// Reference to the parent agent (needed for messages, client baseUrl, etc.)
  final Agent parentAgent;

  /// Optional factory for extra tools to add to sub-agents (e.g. paper-specific tools).
  final List<Tool> Function(Agent subAgent)? extraToolsFactory;

  AgentTool({required this.parentAgent, this.extraToolsFactory});

  @override
  String get name => 'Agent';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'description': {
        'type': 'string',
        'description': 'A short (3-5 word) description of the task',
      },
      'prompt': {
        'type': 'string',
        'description': 'The full task prompt for the sub-agent',
      },
      'run_in_background': {
        'type': 'boolean',
        'description':
            'Set to true to run this agent in the background (default false)',
      },
      'isolation': {
        'type': 'string',
        'enum': ['fork', 'independent'],
        'description':
            'Context mode: "fork" (default) inherits conversation context, '
            '"independent" starts fresh',
      },
      'name': {
        'type': 'string',
        'description':
            'Name for the agent. Makes it addressable via SendMessage.',
      },
      'team_name': {
        'type': 'string',
        'description':
            'Team name to join. The team must be created first via TeamCreate.',
      },
    },
    'required': ['description', 'prompt'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final desc = input['description'] as String?;
    if (desc == null || desc.trim().isEmpty) {
      return 'description is required.';
    }
    final prompt = input['prompt'] as String?;
    if (prompt == null || prompt.trim().isEmpty) {
      return 'prompt is required.';
    }

    // Check concurrent limit for background agents
    final runInBackground = input['run_in_background'] as bool? ?? false;
    if (runInBackground) {
      if (context.taskRegistry.runningCount >= maxConcurrentBackgroundAgents) {
        return 'Cannot launch background agent: maximum concurrent limit '
            '($maxConcurrentBackgroundAgents) reached. '
            'Wait for running tasks to complete or use TaskStop to cancel one.';
      }
    }

    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final description = input['description'] as String;
    final prompt = input['prompt'] as String;
    final runInBackground = input['run_in_background'] as bool? ?? false;
    final isolation = input['isolation'] as String? ?? 'fork';
    final agentName = input['name'] as String?;
    final teamName = input['team_name'] as String?;

    // Create sub-agent
    final subAgent = _createSubAgent(context, isolation);

    // Fork mode: inherit parent messages (in-memory only, not persisted to sidechain)
    if (isolation == 'fork') {
      subAgent.messages.addAll(
        parentAgent.messages.map(
          (m) => Message(
            role: m.role,
            content: m.content,
            toolUses: m.toolUses,
            toolResult: m.toolResult,
            timestamp: m.timestamp,
            isCompactSummary: m.isCompactSummary,
          ),
        ),
      );
    }

    // Synchronous execution
    if (!runInBackground) {
      try {
        final sink = context.eventSink;
        final buffer = StringBuffer();
        final stopwatch = Stopwatch()..start();
        await for (final event in subAgent.run(prompt)) {
          if (event is AgentTextDelta) {
            buffer.write(event.text);
          } else if (event is AgentThinking) {
            final preview = event.text.length > 80
                ? '${event.text.substring(0, 80)}...'
                : event.text;
            sink?.add(
              AgentToolProgress(
                toolName: 'Agent',
                output: 'thinking: $preview',
                elapsedMs: 0,
              ),
            );
          } else if (event is AgentToolUseStart) {
            sink?.add(
              AgentToolProgress(
                toolName: 'Agent',
                output: 'tool: ${event.toolName}',
                elapsedMs: 0,
              ),
            );
          } else if (event is AgentToolResult) {
            sink?.add(
              AgentToolProgress(
                toolName: 'Agent',
                output: 'result: ${event.isError ? "error" : "ok"}',
                elapsedMs: 0,
              ),
            );
          } else if (event is AgentError) {
            throw Exception(event.message);
          }
        }
        stopwatch.stop();
        final elapsed = stopwatch.elapsedMilliseconds >= 1000
            ? '${(stopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s'
            : '${stopwatch.elapsedMilliseconds}ms';
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Sub-agent completed in $elapsed.\n\n${buffer.toString()}',
        );
      } catch (e) {
        return ToolResult(
          toolUseId: toolUseId,
          content: 'Sub-agent failed: $e',
          isError: true,
        );
      }
    }

    // Asynchronous (background) execution
    final task = context.taskRegistry.register(
      description: description,
      prompt: prompt,
      toolUseId: toolUseId,
      parentSessionId: parentAgent.sessionManager.currentSession?.id,
      isBackgrounded: true,
    );

    parentAgent.registerBackgroundAgent(task.id, subAgent);

    // Register as team member if team_name is provided
    if (teamName != null) {
      final team = context.teamRegistry.getTeam(teamName);
      if (team != null) {
        team.addMember(
          TeamMember(
            agentId: task.id,
            name: agentName ?? description,
            role: description,
            prompt: prompt,
          ),
        );
      }
    }

    // Fire-and-forget
    _runBackgroundAgent(subAgent, prompt, task, context);

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Background agent launched.\n'
          'Task ID: ${task.id}\n'
          'Description: $description\n\n'
          'You will receive a <task-notification> when it completes.\n'
          'Use TaskOutput to check status, or TaskStop to cancel.',
    );
  }

  /// Create a sub-agent with isolated context and restricted tools.
  Agent _createSubAgent(ToolContext parentContext, String isolation) {
    // Independent LLMClient (same type as parent, avoids cancel interference)
    final client = parentAgent.client.clone();

    // Cloned ToolContext (isolated readFileTimestamps)
    final subContext = ToolContext(
      basePath: parentContext.basePath,
      serviceBaseUrl: parentContext.serviceBaseUrl,
      skipPermissions: true, // sub-agent skips permissions
      approvedTools: Set.from(parentContext.approvedTools),
      taskRegistry: parentContext.taskRegistry, // shared registry
    );
    subContext.readFileTimestamps.addAll(parentContext.readFileTimestamps);

    // Restricted tool set (no AgentTool to prevent infinite nesting)
    final tools = _getSubAgentTools();

    // PromptBuilder: fork inherits parent's, independent uses simplified
    final promptBuilder = isolation == 'fork'
        ? parentAgent.promptBuilder
        : PromptBuilder(
            basePrompt:
                'You are a helpful sub-agent. Complete the assigned task '
                'concisely and report your findings.',
            basePath: parentContext.basePath,
          );

    // Sidechain session for persistence
    final sidechainDir = _getSidechainDir(parentContext);
    final sidechainSessionManager = SessionManager(sessionsDir: sidechainDir);

    final subAgent = Agent(
      client: client,
      tools: tools,
      promptBuilder: promptBuilder,
      toolContext: subContext,
      sessionManager: sidechainSessionManager,
      contextWindow: parentAgent.contextWindow,
      maxOutputTokens: parentAgent.maxOutputTokens,
    );

    subAgent.addTool(
      AgentTool(parentAgent: subAgent, extraToolsFactory: extraToolsFactory),
    );

    // Add extra tools from factory (e.g. paper-specific tools)
    if (extraToolsFactory != null) {
      for (final tool in extraToolsFactory!(subAgent)) {
        subAgent.addTool(tool);
      }
    }

    return subAgent;
  }

  /// Restricted tool set for sub-agents.
  /// Reference: claude-code-best ASYNC_AGENT_ALLOWED_TOOLS
  List<Tool> _getSubAgentTools() => [
    FileReadTool(),
    FileWriteTool(),
    FileEditTool(),
    FileManageTool(),
    GlobTool(),
    GrepTool(),
    LSTool(),
    SkillTool(),
    TaskCreateTool(),
    TaskGetTool(),
    TaskListTool(),
    TaskUpdateTool(),
    EnterPlanModeTool(),
    ExitPlanModeTool(),
    SendMessageTool(parentAgent: parentAgent),
    // Disallowed (prevent nesting + user interaction):
    // AgentTool, TaskOutputTool, TaskStopTool,
    // AskUserQuestionTool (requiresUserInteraction)
  ];

  /// Get the sidechain directory for sub-agent sessions.
  String _getSidechainDir(ToolContext context) {
    final parentSessionId =
        parentAgent.sessionManager.currentSession?.id ?? 'unknown';
    return p.join(context.basePath, 'sessions', parentSessionId, 'subagents');
  }

  /// Run a background agent (fire-and-forget).
  Future<void> _runBackgroundAgent(
    Agent subAgent,
    String prompt,
    BackgroundTask task,
    ToolContext context,
  ) async {
    context.taskRegistry.updateStatus(task.id, BackgroundTaskStatus.running);

    try {
      final result = await subAgent.runToCompletion(prompt);
      context.taskRegistry.updateStatus(
        task.id,
        BackgroundTaskStatus.completed,
        result: result,
      );
      // Update team member status if applicable
      _updateTeamMemberStatus(context, task.id, 'completed', result: result);
    } catch (e) {
      final status = e.toString().contains('cancel')
          ? BackgroundTaskStatus.killed
          : BackgroundTaskStatus.failed;
      context.taskRegistry.updateStatus(task.id, status, error: e.toString());
      _updateTeamMemberStatus(context, task.id, status.name);
    } finally {
      parentAgent.removeBackgroundAgent(task.id);
    }
  }

  /// Update team member status when a background agent completes/fails.
  void _updateTeamMemberStatus(
    ToolContext context,
    String agentId,
    String status, {
    String? result,
  }) {
    for (final team in context.teamRegistry.teams) {
      if (team.members.containsKey(agentId)) {
        team.updateMemberStatus(agentId, status, result: result);
        break;
      }
    }
  }
}
