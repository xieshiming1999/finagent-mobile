import 'log.dart';
import 'message.dart';

// Reference: claude-code-best micro compaction concept
// Selectively truncate old tool results to reduce context size
// without a full LLM-based compaction.

/// Number of recent message turns to keep intact (not truncate).
const _keepRecentTurns = 6;

/// Minimum content length to bother truncating.
const _minTruncateLength = 500;

/// Try micro compaction: truncate old tool_result content.
/// Returns true if any messages were truncated, false if nothing to do.
///
/// This is a "free" compaction — no LLM call, just rule-based truncation.
/// Should be tried before session memory compact and full LLM compact.
bool tryMicroCompact(List<Message> messages) {
  if (messages.length < _keepRecentTurns * 2) return false;

  // Find the boundary: keep the last N user/assistant turns intact
  var recentTurnCount = 0;
  var keepFromIndex = messages.length;
  for (var i = messages.length - 1; i >= 0; i--) {
    final msg = messages[i];
    if (msg.role == Role.user || msg.role == Role.assistant) {
      recentTurnCount++;
      if (recentTurnCount >= _keepRecentTurns) {
        keepFromIndex = i;
        break;
      }
    }
  }

  var truncatedCount = 0;

  for (var i = 0; i < keepFromIndex; i++) {
    final msg = messages[i];

    // Truncate tool results
    if (msg.role == Role.tool && msg.toolResult != null) {
      final content = msg.toolResult!.content;
      if (content.length >= _minTruncateLength) {
        messages[i] = Message(
          role: msg.role,
          content: msg.content,
          toolResult: ToolResult(
            toolUseId: msg.toolResult!.toolUseId,
            content: '[Tool result truncated, was ${content.length} chars]',
            isError: msg.toolResult!.isError,
          ),
          timestamp: msg.timestamp,
          isCompactSummary: msg.isCompactSummary,
        );
        truncatedCount++;
      }
    }

    // Truncate long assistant tool call inputs (keep name + short summary)
    if (msg.role == Role.assistant && msg.toolUses != null) {
      var modified = false;
      final newToolUses = msg.toolUses!.map((tu) {
        final inputStr = tu.input.toString();
        if (inputStr.length > 1000) {
          modified = true;
          // Keep only essential keys for context
          final shortInput = <String, dynamic>{};
          for (final key in tu.input.keys.take(3)) {
            final val = tu.input[key];
            if (val is String && val.length > 100) {
              shortInput[key] = '${val.substring(0, 100)}...';
            } else {
              shortInput[key] = val;
            }
          }
          return ToolUse(id: tu.id, name: tu.name, input: shortInput);
        }
        return tu;
      }).toList();

      if (modified) {
        messages[i] = Message(
          role: msg.role,
          content: msg.content,
          toolUses: newToolUses,
          timestamp: msg.timestamp,
          isCompactSummary: msg.isCompactSummary,
        );
        truncatedCount++;
      }
    }
  }

  if (truncatedCount > 0) {
    log(
      'MicroCompact',
      'Truncated $truncatedCount messages (before index $keepFromIndex)',
    );
  }
  return truncatedCount > 0;
}
