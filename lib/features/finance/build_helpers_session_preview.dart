part of 'finagent_screen.dart';

List<ChatItem> _loadChatItemsFromJsonl(String filePath) {
  final file = File(filePath);
  if (!file.existsSync()) return const [];
  final lines = file.readAsLinesSync().where((l) => l.trim().isNotEmpty);
  final items = <ChatItem>[];

  for (final line in lines) {
    try {
      final json = jsonDecode(line) as Map<String, dynamic>;
      final type = json['type'] as String?;
      final role = (json['role'] ?? '').toString();
      final content = (json['content'] ?? '').toString();
      if (role == 'user' && content.isNotEmpty) {
        items.add(ChatItem(role: 'user', content: content));
      } else if (role == 'assistant' && content.isNotEmpty) {
        items.add(ChatItem(role: 'assistant', content: content));
      } else if (json['tool_result'] is Map) {
        final result = json['tool_result'] as Map<String, dynamic>;
        final toolContent = (result['content'] ?? '').toString();
        if (toolContent.isNotEmpty) {
          items.add(ChatItem(role: 'tool_result', content: toolContent));
        }
      } else if (type == 'message') {
        final flatRole = (json['role'] ?? '').toString();
        final flatContent = (json['content'] ?? '').toString();
        if (flatContent.isNotEmpty) {
          items.add(ChatItem(role: flatRole, content: flatContent));
        }
      }
    } catch (_) {}
  }
  return items;
}

Widget _previewBubble(BuildContext context, ChatItem item) {
  final isUser = item.role == 'user';
  final isAssistant = item.role == 'assistant';
  return Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(
              color: isUser
                  ? Theme.of(context).colorScheme.primary
                  : isAssistant
                  ? Colors.green
                  : Theme.of(context).colorScheme.outline,
              width: 2,
            ),
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.role,
              style: TextStyle(
                fontSize: 9,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 2),
            Text(item.content, style: const TextStyle(fontSize: 13)),
          ],
        ),
      ),
    ),
  );
}

Widget _previewMetric(BuildContext context, String label, int value) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      '$value $label',
      style: TextStyle(
        fontSize: 10,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
        fontFamily: 'monospace',
      ),
    ),
  );
}

_ChatStats _chatStats(List<ChatItem> items) {
  var user = 0;
  var assistant = 0;
  var tool = 0;
  for (final item in items) {
    if (item.role == 'user') {
      user++;
    } else if (item.role == 'assistant') {
      assistant++;
    } else {
      tool++;
    }
  }
  return _ChatStats(user: user, assistant: assistant, tool: tool);
}

String _sessionTitle(String filePath, {String? title, String? firstPrompt}) {
  return title ??
      firstPrompt ??
      filePath.split('/').last.replaceAll('.jsonl', '');
}

class _ChatStats {
  final int user;
  final int assistant;
  final int tool;

  const _ChatStats({
    required this.user,
    required this.assistant,
    required this.tool,
  });
}
