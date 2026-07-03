// ignore_for_file: unintended_html_in_doc_comment
import 'dart:io';
import 'package:path/path.dart' as p;

import 'llm_client.dart';
import 'message.dart';
import 'tool_context.dart';

// Reference: claude-code-best/src/services/compact/

/// Constants matching Claude Code's compact configuration.
const autocompactBufferTokens = 13000;
const compactMaxOutputTokens = 20000;
const postCompactMaxFiles = 5;
const postCompactTokenBudget = 50000;
const postCompactMaxTokensPerFile = 5000;
const maxConsecutiveAutocompactFailures = 3;

/// Rough token estimation: ~4 chars per token for English, ~1.5 for Chinese.
/// Reference: claude-code-best tokenCountWithEstimation()
int estimateTokenCount(List<Message> messages) {
  var totalChars = 0;
  for (final msg in messages) {
    totalChars += msg.content.length;
    // Count current turn reasoning (if present) — it's sent to LLM
    if (msg.reasoning != null) totalChars += msg.reasoning!.length;
    if (msg.toolUses != null) {
      for (final tu in msg.toolUses!) {
        totalChars += tu.name.length + tu.input.toString().length;
      }
    }
    if (msg.toolResult != null) {
      totalChars += msg.toolResult!.content.length;
    }
  }
  // Use a blended estimate: ~3 chars/token (between English and Chinese)
  return (totalChars / 3).ceil();
}

/// Check if auto compaction should trigger.
/// Reference: claude-code-best shouldAutoCompact()
bool shouldAutoCompact(
  List<Message> messages, {
  required int contextWindow,
  required int maxOutputTokens,
}) {
  final effectiveWindow = contextWindow - maxOutputTokens.clamp(0, 20000);
  final threshold = effectiveWindow - autocompactBufferTokens;
  final currentTokens = estimateTokenCount(messages);
  return currentTokens > threshold;
}

/// Maximum total image bytes allowed in messages (8 MB).
const maxImageBudgetBytes = 8 * 1024 * 1024;

/// Minimum number of recent images always kept regardless of budget.
const minProtectedImages = 5;

/// Strip old images from messages when total exceeds budget.
/// Iterates from newest to oldest, keeping images until budget is exhausted.
/// The most recent [minProtectedImages] images are always kept.
void enforceImageBudget(List<Message> messages) {
  // First pass: count images from newest to oldest, mark protected ones
  var imageCount = 0;
  final protectedIndices = <int>{};
  for (var i = messages.length - 1; i >= 0; i--) {
    final msg = messages[i];
    final hasUserImages =
        msg.role == Role.user && msg.images != null && msg.images!.isNotEmpty;
    final hasToolImages =
        msg.role == Role.tool &&
        msg.toolResult != null &&
        msg.toolResult!.images != null &&
        msg.toolResult!.images!.isNotEmpty;
    if (hasUserImages || hasToolImages) {
      imageCount++;
      if (imageCount <= minProtectedImages) {
        protectedIndices.add(i);
      }
    }
  }

  // Second pass: enforce budget, skipping protected
  var totalBytes = 0;
  for (var i = messages.length - 1; i >= 0; i--) {
    if (protectedIndices.contains(i)) {
      final msg = messages[i];
      if (msg.role == Role.user && msg.images != null) {
        totalBytes += msg.images!.fold<int>(0, (sum, img) => sum + img.length);
      }
      if (msg.role == Role.tool && msg.toolResult?.images != null) {
        totalBytes += msg.toolResult!.images!.fold<int>(
          0,
          (sum, img) => sum + img.length,
        );
      }
      continue;
    }

    final msg = messages[i];

    if (msg.role == Role.user && msg.images != null && msg.images!.isNotEmpty) {
      final size = msg.images!.fold<int>(0, (sum, img) => sum + img.length);
      if (totalBytes + size <= maxImageBudgetBytes) {
        totalBytes += size;
      } else {
        msg.images = null;
      }
    }

    if (msg.role == Role.tool &&
        msg.toolResult != null &&
        msg.toolResult!.images != null &&
        msg.toolResult!.images!.isNotEmpty) {
      final size = msg.toolResult!.images!.fold<int>(
        0,
        (sum, img) => sum + img.length,
      );
      if (totalBytes + size <= maxImageBudgetBytes) {
        totalBytes += size;
      } else {
        final count = msg.toolResult!.images!.length;
        msg.toolResult!.images = null;
        msg.toolResult!.content +=
            '\n[$count image(s) removed to save context space]';
      }
    }
  }
}

/// Result of a compaction operation.
class CompactResult {
  final Message summaryMessage;
  final List<Message>? messagesToKeep;
  final List<Message> fileAttachments;
  final int preCompactMessageCount;
  final String summary;

  const CompactResult({
    required this.summaryMessage,
    this.messagesToKeep,
    this.fileAttachments = const [],
    required this.preCompactMessageCount,
    required this.summary,
  });
}

/// Build the post-compact message array.
/// Reference: claude-code-best buildPostCompactMessages()
List<Message> buildPostCompactMessages(CompactResult result) {
  return [
    result.summaryMessage,
    if (result.messagesToKeep != null) ...result.messagesToKeep!,
    ...result.fileAttachments,
  ];
}

/// Compact the conversation by generating an LLM summary.
/// Reference: claude-code-best compactConversation()
Future<CompactResult> compactConversation(
  List<Message> messages,
  LLMClient client,
  ToolContext context, {
  String? customInstructions,
  bool suppressFollowUp = false,
}) async {
  // Strip images from messages for compact (replace with [image] markers)
  final strippedMessages = _stripImagesFromMessages(messages);

  // Prune large tool results from middle of conversation to reduce compact cost
  final prunedMessages = _pruneOldToolResults(strippedMessages);

  // Build compact prompt — pass previous summary for iterative update
  final systemPrompt = compactSystemPrompt;
  final previousSummary = _extractPreviousSummary(prunedMessages);
  final userPrompt = _buildCompactUserPrompt(
    prunedMessages,
    customInstructions: customInstructions,
    previousSummary: previousSummary,
  );

  // Call LLM for summary (non-streaming, single response)
  final summaryMessages = [
    ...prunedMessages,
    Message(role: Role.user, content: userPrompt, timestamp: DateTime.now()),
  ];

  final rawSummary = await _callLLMForSummary(
    client,
    summaryMessages,
    systemPrompt,
  );

  // Format the summary (strip <analysis> block, keep <summary>)
  final formattedSummary = formatCompactSummary(rawSummary);

  // Create post-compact file attachments
  final fileAttachments = createPostCompactFileAttachments(context);

  // Build the summary user message
  final summaryContent = _wrapSummaryMessage(
    formattedSummary,
    suppressFollowUp: suppressFollowUp,
  );

  final summaryMessage = Message(
    role: Role.user,
    content: summaryContent,
    timestamp: DateTime.now(),
    isCompactSummary: true,
  );

  return CompactResult(
    summaryMessage: summaryMessage,
    fileAttachments: fileAttachments,
    preCompactMessageCount: messages.length,
    summary: formattedSummary,
  );
}

/// Call LLM to generate a compact summary.
/// Collects the full response text (non-streaming).
Future<String> _callLLMForSummary(
  LLMClient client,
  List<Message> messages,
  String systemPrompt,
) async {
  final buffer = StringBuffer();

  await for (final event in client.sendMessage(
    messages: messages,
    tools: [], // No tools during compact
    systemPrompt: systemPrompt,
  )) {
    if (event is SSETextDelta) {
      buffer.write(event.text);
    }
  }

  final result = buffer.toString();
  if (result.isEmpty) {
    throw Exception('Compact: LLM returned empty summary');
  }
  return result;
}

/// Format the compact summary: strip <analysis> block, extract <summary> content.
/// Reference: claude-code-best formatCompactSummary()
String formatCompactSummary(String rawSummary) {
  var result = rawSummary;

  // Strip <analysis>...</analysis> drafting block
  final analysisPattern = RegExp(
    r'<analysis>[\s\S]*?</analysis>',
    multiLine: true,
  );
  result = result.replaceAll(analysisPattern, '').trim();

  // Extract content from <summary>...</summary> tags
  final summaryMatch = RegExp(
    r'<summary>([\s\S]*?)</summary>',
    multiLine: true,
  ).firstMatch(result);
  if (summaryMatch != null) {
    result = summaryMatch.group(1)!.trim();
  }

  return result;
}

/// Wrap the formatted summary in the standard compact framing message.
/// Reference: claude-code-best getCompactUserSummaryMessage()
String _wrapSummaryMessage(String summary, {bool suppressFollowUp = false}) {
  final buf = StringBuffer();
  buf.writeln(
    'This session is being continued from a previous conversation that ran '
    'out of context. The summary below covers the earlier portion of the '
    'conversation.',
  );
  buf.writeln();
  buf.writeln(summary);

  if (suppressFollowUp) {
    buf.writeln();
    buf.writeln(
      'Continue the conversation from where it left off without asking the '
      'user any further questions. Resume directly with the task at hand.',
    );
  }

  return buf.toString();
}

/// Create file restoration attachments after compaction.
/// Reads the most recently accessed files from readFileTimestamps.
/// Reference: claude-code-best createPostCompactFileAttachments()
List<Message> createPostCompactFileAttachments(ToolContext context) {
  if (context.readFileTimestamps.isEmpty) return [];

  // Sort files by most recently accessed
  final sortedFiles = context.readFileTimestamps.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  final attachments = <Message>[];
  var totalTokens = 0;

  for (final entry in sortedFiles.take(postCompactMaxFiles)) {
    if (totalTokens >= postCompactTokenBudget) break;

    try {
      final file = File(entry.key);
      if (!file.existsSync()) continue;

      var content = file.readAsStringSync();
      // Truncate to per-file token budget
      final maxChars = postCompactMaxTokensPerFile * 3; // ~3 chars/token
      if (content.length > maxChars) {
        content = '${content.substring(0, maxChars)}\n... (truncated)';
      }

      final relativePath = p.relative(entry.key, from: context.basePath);
      attachments.add(
        Message(
          role: Role.user,
          content:
              '[File restored after compaction: $relativePath]\n\n$content',
          timestamp: DateTime.now(),
        ),
      );

      totalTokens += (content.length / 3).ceil();
    } catch (_) {
      continue;
    }
  }

  return attachments;
}

/// Strip image references from messages (replace with [image] markers).
/// Reference: claude-code-best stripImagesFromMessages()
List<Message> _stripImagesFromMessages(List<Message> messages) {
  // On mobile we don't have image content in messages yet,
  // but this is here for future compatibility
  return messages;
}

/// Prune large tool results from the middle of the conversation before compact.
/// Keeps head (first 3) and tail (last 5) messages intact, replaces large tool
/// results in between with a placeholder. This reduces compact token cost and
/// improves summary quality by removing noise.
/// Reference: Hermes context_compressor.py _prune_old_tool_results()
List<Message> _pruneOldToolResults(List<Message> messages, {int tailKeep = 5}) {
  if (messages.length <= tailKeep + 3) return messages;

  final headKeep = 3;
  final tailStart = messages.length - tailKeep;

  return List.generate(messages.length, (i) {
    if (i < headKeep || i >= tailStart) return messages[i];

    final msg = messages[i];
    if (msg.role == Role.tool &&
        msg.toolResult != null &&
        msg.toolResult!.content.length > 200) {
      return Message(
        role: Role.tool,
        toolResult: ToolResult(
          toolUseId: msg.toolResult!.toolUseId,
          content: '[Old tool output cleared to save context space]',
          isError: msg.toolResult!.isError,
        ),
        timestamp: msg.timestamp,
      );
    }
    return msg;
  });
}

/// Build the user prompt for compact, requesting a structured summary.
String _buildCompactUserPrompt(
  List<Message> messages, {
  String? customInstructions,
  String? previousSummary,
}) {
  final buf = StringBuffer();
  buf.writeln(
    'Please summarize this conversation following the structure below. '
    'First produce an <analysis> block (your drafting scratchpad, will be '
    'discarded), then a <summary> block with the final summary.',
  );

  if (previousSummary != null && previousSummary.isNotEmpty) {
    buf.writeln();
    buf.writeln(
      'Previous summary to update (incorporate new information, '
      "don't lose important details from this):",
    );
    buf.writeln(previousSummary);
  }

  if (customInstructions != null && customInstructions.isNotEmpty) {
    buf.writeln();
    buf.writeln('Additional instructions: $customInstructions');
  }

  return buf.toString();
}

/// Extract previous compact summary from messages, if any.
/// The first message after a compact is a user message with isCompactSummary=true.
String? _extractPreviousSummary(List<Message> messages) {
  if (messages.isEmpty) return null;
  final first = messages.first;
  if (!first.isCompactSummary) return null;
  // The summary content is inside the wrapper text — extract the middle part
  // (between the header line and the "Continue the conversation" line)
  return first.content;
}

/// The system prompt for the compact summarization agent.
/// Reference: claude-code-best compact/prompt.ts
const compactSystemPrompt =
    '''You are a helpful AI assistant tasked with summarizing conversations.

Respond with TEXT ONLY. Do NOT call any tools.

Produce your response in two XML blocks:

1. <analysis> — Your drafting scratchpad. Think through what matters. This will be discarded.

2. <summary> — The final structured summary with these sections:

## Goal
What is the user trying to accomplish? What is the overall objective and constraints?

## Progress
What has been completed so far? Key milestones and their status.

## Key Decisions
Important decisions made, approaches chosen, and reasoning.

## Relevant Files
Files viewed, edited, or created. Include brief code snippets for critical sections.

## Errors and Fixes
Any errors encountered and how they were resolved.

## All User Messages
Reproduce ALL user messages verbatim or near-verbatim. User feedback and preferences must be preserved.

## Pending Tasks
Tasks mentioned but not completed, with their current status.

## Current Work
What was being worked on most recently? Include file names and specific code if applicable.

## Next Steps
If the conversation ended mid-task, what should happen next? Include direct quotes from the user's last request if relevant.

## Critical Context
Any non-obvious constraints, preferences, or context that would be lost without this summary.

Remember: Respond with TEXT ONLY. Do NOT call any tools.''';
