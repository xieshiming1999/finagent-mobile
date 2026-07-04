import 'llm_client.dart';
import 'log.dart';
import 'message.dart';
import 'post_turn_hooks.dart';

// Reference: claude-code-best/src/services/PromptSuggestion/

/// Mutable state for speculation, scoped to agent lifetime.
class SpeculationState {
  bool inProgress = false;
  String? lastSuggestion;
  int turnsSinceLastCheck = 0;
}

/// Post-turn hook: predict what the user might type next.
/// Emits suggestion via callback (agent wires this to an AgentEvent).
Future<void> hookSpeculation(
  PostTurnContext ctx,
  SpeculationState state,
  void Function(String suggestion)? onSuggestion,
) async {
  if (state.inProgress) return;
  if (onSuggestion == null) return;

  state.turnsSinceLastCheck++;
  if (state.turnsSinceLastCheck < 10) return;
  state.turnsSinceLastCheck = 0;

  // Need at least a few messages
  if (ctx.messages.length < 2) return;

  state.inProgress = true;

  try {
    final suggestion = await _generateSuggestion(ctx);
    if (suggestion != null) {
      state.lastSuggestion = suggestion;
      onSuggestion(suggestion);
      log('Speculation', 'Suggested: $suggestion');
    }
  } catch (e) {
    log('Speculation', 'Error: $e');
  } finally {
    state.inProgress = false;
  }
}

Future<String?> _generateSuggestion(PostTurnContext ctx) async {
  // Take the last few messages for context
  final recentMessages = ctx.messages.length > 10
      ? ctx.messages.sublist(ctx.messages.length - 10)
      : ctx.messages;

  final prompt =
      '''Based on the conversation so far, predict what the user would type next as their follow-up message. Output ONLY the predicted user message, nothing else.

Rules:
- 2-12 words, matching the user's language and style
- Must be a natural next step in the conversation
- Do not use evaluative language ("great", "perfect", "nice")
- Do not start with "Can you" or "Could you" — use direct language
- If there's no clear next step, output: NO_SUGGESTION''';

  final messagesForLlm = [
    ...recentMessages.map(
      (m) => Message(
        role: m.role,
        content: m.content.length > 500
            ? '${m.content.substring(0, 500)}...'
            : m.content,
        timestamp: m.timestamp,
      ),
    ),
    Message(role: Role.user, content: prompt, timestamp: DateTime.now()),
  ];

  final client = ctx.client.clone();
  final buffer = StringBuffer();

  await for (final event in client.sendMessage(
    messages: messagesForLlm,
    tools: [],
    systemPrompt:
        'You predict the user\'s next message. Output only the predicted text, 2-12 words.',
    maxOutputTokens: 100,
  )) {
    if (event is SSETextDelta) buffer.write(event.text);
  }

  final raw = buffer.toString().trim();
  return _filterSuggestion(raw);
}

/// Apply heuristic filters to reject bad suggestions.
String? _filterSuggestion(String raw) {
  if (raw.isEmpty) return null;
  if (raw.contains('NO_SUGGESTION')) return null;

  // Too long
  final words = raw.split(RegExp(r'\s+'));
  if (words.length > 15) return null;
  if (words.length < 2) return null;

  // Contains meta-text
  final lower = raw.toLowerCase();
  if (lower.startsWith('the user') ||
      lower.startsWith('i think') ||
      lower.startsWith('i would') ||
      lower.startsWith('predicted')) {
    return null;
  }

  // Contains evaluative language
  const evaluative = [
    'great',
    'perfect',
    'awesome',
    'nice',
    'good job',
    'well done',
  ];
  for (final word in evaluative) {
    if (lower.contains(word)) return null;
  }

  // Contains Claude-voice markers
  if (lower.startsWith('certainly') ||
      lower.startsWith('of course') ||
      lower.startsWith('sure,') ||
      lower.startsWith('absolutely')) {
    return null;
  }

  // Looks like formatting, not a message
  if (raw.startsWith('#') || raw.startsWith('```') || raw.startsWith('---')) {
    return null;
  }

  return raw;
}
