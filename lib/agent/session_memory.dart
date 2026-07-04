import 'dart:io';
import 'package:path/path.dart' as p;

import 'compact.dart';
import 'llm_client.dart';
import 'memory_lifecycle.dart';
import 'memory_quality.dart';
import 'message.dart';
import 'tool_context.dart';

// Reference: claude-code-best/src/services/SessionMemory/
// Reference: claude-code-best/src/services/compact/sessionMemoryCompact.ts

/// Default configuration matching Claude Code.
const _minimumMessageTokensToInit = 10000;
const _minimumTokensBetweenUpdate = 5000;
const _toolCallsBetweenUpdates = 3;

/// Session memory compact configuration.
const _smCompactMinTokens = 10000;
const _smCompactMinTextBlockMessages = 5;
const _smCompactMaxTokens = 40000;

/// Tracks session memory extraction state.
class SessionMemoryState {
  /// The index of the last message that session memory covers.
  int? lastSummarizedIndex;

  /// Token count at last extraction.
  int tokensAtLastExtraction = 0;

  /// Whether session memory has been initialized (first extraction done).
  bool initialized = false;

  /// Whether an extraction is currently in progress.
  bool extracting = false;
}

/// Check if session memory should be extracted.
/// Reference: claude-code-best shouldExtractMemory()
bool shouldExtractMemory(List<Message> messages, SessionMemoryState state) {
  if (state.extracting) return false;

  final currentTokens = estimateTokenCount(messages);

  // Initialization threshold: need at least 10K tokens before first extraction
  if (!state.initialized) {
    if (currentTokens < _minimumMessageTokensToInit) return false;
  }

  // Token growth threshold: need at least 5K tokens since last extraction
  final tokenGrowth = currentTokens - state.tokensAtLastExtraction;
  if (tokenGrowth < _minimumTokensBetweenUpdate) return false;

  // Tool call threshold: need at least 3 tool calls since last extraction
  final toolCalls = _countToolCallsSince(messages, state.lastSummarizedIndex);

  // Both thresholds met
  if (toolCalls >= _toolCallsBetweenUpdates) return true;

  // Or: token threshold met AND last assistant turn has no tool calls
  // (natural conversation break)
  if (toolCalls == 0 && messages.isNotEmpty) {
    final lastMsg = messages.last;
    if (lastMsg.role == Role.assistant &&
        (lastMsg.toolUses == null || lastMsg.toolUses!.isEmpty)) {
      return true;
    }
  }

  return false;
}

/// Count tool calls in messages after the given index.
int _countToolCallsSince(List<Message> messages, int? sinceIndex) {
  final startIdx = (sinceIndex ?? -1) + 1;
  var count = 0;
  for (var i = startIdx; i < messages.length; i++) {
    if (messages[i].toolUses != null) {
      count += messages[i].toolUses!.length;
    }
  }
  return count;
}

/// Get the session memory file path.
String getSessionMemoryPath(String sessionsDir, String sessionId) {
  return p.join(sessionsDir, sessionId, 'session-memory.md');
}

/// Extract session memory by calling LLM to update the notes file.
/// This runs "in the background" — caller should not await for compact purposes,
/// but may await for testing.
/// Reference: claude-code-best extractSessionMemory()
Future<void> extractSessionMemory(
  List<Message> messages,
  LLMClient client,
  ToolContext context,
  SessionMemoryState state,
  String sessionsDir,
  String sessionId,
) async {
  if (state.extracting) return;
  state.extracting = true;

  try {
    final memoryPath = getSessionMemoryPath(sessionsDir, sessionId);
    final memoryDir = p.dirname(memoryPath);
    Directory(memoryDir).createSync(recursive: true);

    // Read existing session memory or use default template
    final memoryFile = File(memoryPath);
    final existingContent = memoryFile.existsSync()
        ? memoryFile.readAsStringSync()
        : defaultSessionMemoryTemplate;

    // Build the update prompt
    final updatePrompt = _buildSessionMemoryUpdatePrompt(
      existingContent,
      messages,
    );

    // Call LLM to generate updated session memory
    final buffer = StringBuffer();
    await for (final event in client.sendMessage(
      messages: [
        Message(
          role: Role.user,
          content: updatePrompt,
          timestamp: DateTime.now(),
        ),
      ],
      tools: [],
      systemPrompt: _sessionMemorySystemPrompt,
    )) {
      if (event is SSETextDelta) {
        buffer.write(event.text);
      }
    }

    final updatedContent = buffer.toString().trim();
    if (updatedContent.isNotEmpty) {
      final quality = normalizeSessionMemoryContent(
        updatedContent,
        sessionId: sessionId,
        extractedAt: DateTime.now().toUtc().toIso8601String(),
      );
      if (!quality.accepted) return;
      memoryFile.writeAsStringSync(quality.content);
    }

    // Update state
    state.lastSummarizedIndex = messages.length - 1;
    state.tokensAtLastExtraction = estimateTokenCount(messages);
    state.initialized = true;
  } finally {
    state.extracting = false;
  }
}

/// Try session memory compaction (free path, no LLM call).
/// Returns a CompactResult if successful, null if should fall back to traditional compact.
/// Reference: claude-code-best trySessionMemoryCompaction()
Future<CompactResult?> trySessionMemoryCompaction(
  List<Message> messages,
  ToolContext context,
  SessionMemoryState state,
  String sessionsDir,
  String sessionId, {
  required int contextWindow,
  required int maxOutputTokens,
}) async {
  // Need session memory to exist and be current
  if (!state.initialized || state.lastSummarizedIndex == null) return null;

  final memoryPath = getSessionMemoryPath(sessionsDir, sessionId);
  final memoryFile = File(memoryPath);
  if (!memoryFile.existsSync()) return null;

  final memoryContent = memoryFile.readAsStringSync().trim();
  if (memoryContent.isEmpty || memoryContent == defaultSessionMemoryTemplate) {
    return null;
  }
  if (!isUsableSessionMemory(memoryContent)) return null;

  final lastSummarizedIndex = state.lastSummarizedIndex!;
  if (lastSummarizedIndex >= messages.length) return null;

  // Calculate which messages to keep
  final keepIndex = calculateMessagesToKeepIndex(messages, lastSummarizedIndex);

  final messagesToKeep = messages.sublist(keepIndex);

  // Build the summary message from session memory content
  final summaryContent =
      'This session is being continued from a previous conversation that ran '
      'out of context. The summary below covers the earlier portion of the '
      'conversation.\n\n'
      '$memoryContent\n\n'
      'Continue the conversation from where it left off without asking the '
      'user any further questions. Resume directly with the task at hand.';

  final summaryMessage = Message(
    role: Role.user,
    content: summaryContent,
    timestamp: DateTime.now(),
    isCompactSummary: true,
  );

  // Check if post-compact would still be over threshold
  final postCompactMessages = [summaryMessage, ...messagesToKeep];
  final postCompactTokens = estimateTokenCount(postCompactMessages);

  final effectiveWindow = contextWindow - maxOutputTokens.clamp(0, 20000);
  final threshold = effectiveWindow - autocompactBufferTokens;

  if (postCompactTokens >= threshold) {
    // Still over threshold — fall back to traditional compact
    return null;
  }

  final fileAttachments = createPostCompactFileAttachments(context);

  return CompactResult(
    summaryMessage: summaryMessage,
    messagesToKeep: messagesToKeep,
    fileAttachments: fileAttachments,
    preCompactMessageCount: messages.length,
    summary: memoryContent,
  );
}

/// Calculate the index from which to keep messages after session memory compact.
/// Expands backwards from lastSummarizedIndex+1 to meet minimum thresholds.
/// Reference: claude-code-best calculateMessagesToKeepIndex()
int calculateMessagesToKeepIndex(
  List<Message> messages,
  int lastSummarizedIndex, {
  int minTokens = _smCompactMinTokens,
  int minTextBlockMessages = _smCompactMinTextBlockMessages,
  int maxTokens = _smCompactMaxTokens,
}) {
  // Start from the first unsummarized message
  var startIndex = lastSummarizedIndex + 1;
  if (startIndex >= messages.length) startIndex = messages.length;

  // Calculate tokens and text block count from startIndex to end
  var keepIndex = startIndex;

  while (keepIndex > 0) {
    final kept = messages.sublist(keepIndex);
    final tokens = estimateTokenCount(kept);
    final textBlocks = kept
        .where((m) => m.role == Role.user || m.role == Role.assistant)
        .length;

    // If we've hit maxTokens, stop expanding
    if (tokens >= maxTokens) break;

    // If both minimums are met, stop
    if (tokens >= minTokens && textBlocks >= minTextBlockMessages) break;

    // Expand backwards
    keepIndex--;

    // Don't cross compact boundaries
    if (keepIndex >= 0 && messages[keepIndex].isCompactSummary) {
      keepIndex++;
      break;
    }
  }

  // Adjust to not split tool_use/tool_result pairs
  keepIndex = _adjustIndexForToolPairs(messages, keepIndex);

  return keepIndex;
}

/// Ensure we don't split a tool_use from its tool_result.
int _adjustIndexForToolPairs(List<Message> messages, int index) {
  if (index <= 0 || index >= messages.length) return index;

  // If the message at index is a tool result, include the preceding assistant message
  if (messages[index].role == Role.tool) {
    return index - 1;
  }

  return index;
}

/// Build the prompt for updating session memory.
String _buildSessionMemoryUpdatePrompt(
  String existingContent,
  List<Message> messages,
) {
  final conversationText = messages
      .map((m) {
        final role = m.role.name.toUpperCase();
        var content = m.content;
        if (m.toolUses != null && m.toolUses!.isNotEmpty) {
          final toolNames = m.toolUses!.map((t) => t.name).join(', ');
          content += '\n[Tool calls: $toolNames]';
        }
        if (m.toolResult != null) {
          content =
              '[Tool result: ${m.toolResult!.content.length > 200 ? '${m.toolResult!.content.substring(0, 200)}...' : m.toolResult!.content}]';
        }
        return '$role: $content';
      })
      .join('\n\n');

  return '''Here is the current session memory:

$existingContent

---

Here is the conversation so far:

$conversationText

---

Update the session memory to reflect the current state of the conversation.
Keep each section concise (under ~2000 tokens per section, ~12000 tokens total).
Preserve lifecycle frontmatter and section headers. Update content to reflect the latest state.
The final file must include non-placeholder content in Current State, Task Specification, and Worklog. Include provenance, source_session_id, extracted_at, and expires metadata in frontmatter when available.
If a section is not relevant, leave its description in italics.
Keep current task state in this session memory. Do not promote stable facts to durable memory or repeated workflow to skills from this update; that requires a separate reviewed memory/skill action.
Output the complete updated session memory file.''';
}

const _sessionMemorySystemPrompt =
    'You are a session memory manager. Your job is to maintain a structured '
    'summary of the current conversation session. Output ONLY the updated '
    'session memory file content. Do NOT call any tools.';

/// Default session memory template.
/// Reference: claude-code-best DEFAULT_SESSION_MEMORY_TEMPLATE
final defaultSessionMemoryTemplate =
    '${memoryLifecycleFrontmatter(MemoryLifecycleKind.session)}'
    '''## Session Title
*Auto-generated title for this conversation*

## Current State
*What the assistant is currently doing*

## Task Specification
*The user's original request and constraints*

## Files and Functions
*Key files and functions involved in this session*

## Workflow
*Steps taken so far*

## Errors & Corrections
*Errors encountered and how they were fixed*

## Key Results
*Important outputs and conclusions*

## Worklog
*Chronological log of actions taken*
''';
