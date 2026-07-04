import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import '../../ui_notification.dart';

/// Sends an alert notification visible to the user in the notification center.
/// Only use for important events that require user attention.
class UINotifyTool extends Tool {
  UINotificationStore? store;

  @override
  String get name => 'UINotify';

  @override
  String get description =>
      'Send an alert notification to the user\'s notification center.';

  @override
  String get prompt =>
      '''Send an important alert to the user's notification center.

Only use this for events that genuinely require user attention:
- Price threshold breaches
- Anomalous data patterns
- Task failures that need manual intervention
- Critical status changes

Do NOT use for routine updates, successful data refreshes, or informational messages.
Those are logged automatically and visible in event history.''';

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'title': {
        'type': 'string',
        'description': 'Short alert title (e.g. "茅台价格告警")',
      },
      'message': {
        'type': 'string',
        'description': 'Alert details (e.g. "当前价格 1795，跌破 1800 阈值")',
      },
    },
    'required': ['title', 'message'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) => true;

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final title = input['title'] as String? ?? '';
    final message = input['message'] as String? ?? '';

    if (title.isEmpty || message.isEmpty) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Both title and message are required.',
        isError: true,
      );
    }

    store?.add(
      UINotification(
        id: 'agent_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        message: message,
        source: 'event_agent',
        severity: NotificationSeverity.alert,
      ),
    );

    return ToolResult(toolUseId: toolUseId, content: 'Alert sent: $title');
  }
}
