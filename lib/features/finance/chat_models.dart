/// A sub-agent progress event displayed under a tool_use item.
class SubEvent {
  final String type; // 'thinking', 'tool', 'result'
  final String content;
  String? status; // null=running, 'ok', 'error'

  SubEvent({required this.type, required this.content, this.status});
}

/// A single chat item (one message, tool call, or UI widget).
class ChatItem {
  final String role; // 'user', 'assistant', 'tool_use', 'tool_result', 'ui_widget'
  String content;
  Map<String, dynamic>? metadata;
  String? thinking;
  List<SubEvent>? subEvents;

  ChatItem({required this.role, required this.content, this.metadata, this.thinking, this.subEvents});
}

/// A group of related chat items displayed together.
///
/// User messages form single-item groups.
/// Assistant interactions (text + tool calls + results) form multi-item groups.
class ChatGroup {
  final String role; // 'user' or 'assistant'
  final List<ChatItem> items;

  ChatGroup({required this.role, required this.items});

  /// Build copyable text for the entire group.
  String get copyText {
    final buf = StringBuffer();
    for (final item in items) {
      switch (item.role) {
        case 'assistant':
          if (item.content.isNotEmpty) {
            if (buf.isNotEmpty) buf.writeln();
            buf.writeln(item.content);
          }
        case 'tool_use':
          final status = item.metadata?['status'] ?? '?';
          final icon = status == 'ok' ? '\u2713' : status == 'error' ? '\u2717' : '\u2026';
          buf.writeln('$icon ${item.content}');
          if (status == 'error') {
            buf.writeln('  Error: ${item.metadata?['error'] ?? 'unknown'}');
          }
        case 'ui_widget':
          if (buf.isNotEmpty) buf.writeln();
          buf.writeln(_uiWidgetCopyText(item));
        default:
          buf.writeln(item.content);
      }
    }
    return buf.toString().trimRight();
  }

  static String _uiWidgetCopyText(ChatItem item) {
    final meta = item.metadata;
    if (meta == null) return item.content;
    final action = meta['action'];
    final params = meta['params'] as Map<String, dynamic>? ?? {};
    if (action == 'showQuote') {
      final d = params['data'] as Map<String, dynamic>? ?? params;
      final code = d['ts_code'] ?? '';
      final name = d['name'] ?? '';
      final close = d['close'] ?? '';
      final pct = d['pct_change'] ?? '';
      return '$code $name  $close  ${_numSign(pct)}$pct%';
    }
    return item.content;
  }

  static String _numSign(dynamic v) {
    final n = (v is num) ? v : (double.tryParse('$v') ?? 0);
    return n >= 0 ? '+' : '';
  }
}

/// Build groups from a flat items list for rendering.
List<ChatGroup> buildChatGroups(List<ChatItem> items) {
  final groups = <ChatGroup>[];
  for (final item in items) {
    if (item.role == 'user' || item.role == 'recap') {
      groups.add(ChatGroup(role: item.role, items: [item]));
    } else {
      // assistant, tool_use, tool_result, ui_widget belong to assistant group
      if (groups.isEmpty || groups.last.role != 'assistant') {
        groups.add(ChatGroup(role: 'assistant', items: [item]));
      } else {
        groups.last.items.add(item);
      }
    }
  }
  return groups;
}
