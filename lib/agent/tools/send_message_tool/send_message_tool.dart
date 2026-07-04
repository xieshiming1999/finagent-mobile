import '../../agent.dart';
import '../../message.dart';
import '../../notification_queue.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Tool for sending messages to running background agents.
///
/// Reference: claude-code-best SendMessageTool (simplified — no cross-process,
/// no file mailbox, no team/swarm protocol).
class SendMessageTool extends Tool {
  final Agent parentAgent;

  SendMessageTool({required this.parentAgent});

  @override
  String get name => 'SendMessage';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'to': {
        'type': 'string',
        'description': 'The agent name or task ID to send the message to.',
      },
      'message': {
        'type': 'string',
        'description': 'The message content to send.',
      },
    },
    'required': ['to', 'message'],
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
    final to = input['to'] as String?;
    if (to == null || to.trim().isEmpty) {
      return '"to" is required — provide the agent name or task ID.';
    }
    final message = input['message'] as String?;
    if (message == null || message.trim().isEmpty) {
      return '"message" is required.';
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final to = (input['to'] as String).trim();
    final message = (input['message'] as String).trim();

    // Send to parent/main agent
    if (to == 'main' || to == 'parent') {
      parentAgent.notificationQueue.enqueue(
        PendingNotification(
          prompt: '<teammate-message>\n$message\n</teammate-message>',
          priority: NotificationPriority.now,
          source: 'send_message',
        ),
      );
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Message delivered to main agent.',
      );
    }

    // Try direct task ID first
    var delivered = parentAgent.sendMessageToAgent(to, message);

    // If not found by ID, try name lookup
    if (!delivered) {
      final taskId = parentAgent.findAgentIdByName(to);
      if (taskId != null) {
        delivered = parentAgent.sendMessageToAgent(taskId, message);
      }
    }

    if (delivered) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Message delivered to agent "$to".',
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Agent "$to" not found. It may have already completed or been stopped. '
          'Use TaskList to see available agents.',
      isError: true,
    );
  }
}
