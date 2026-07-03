import 'dart:io';

import 'agent.dart';
import 'log.dart';
import 'post_turn_hooks.dart';
import 'prompt_builder.dart';
import 'session.dart';
import 'tool_context.dart';
import 'tools/file_edit_tool/file_edit_tool.dart';
import 'tools/file_read_tool/file_read_tool.dart';

// Reference: claude-code-best/src/services/MagicDocs/magicDocs.ts

final _magicDocPattern = RegExp(r'^#\s*MAGIC\s+DOC:\s*(.+)$', multiLine: true);

/// Mutable state for magic docs, scoped to agent lifetime.
class MagicDocsState {
  /// Tracked magic doc file paths -> title.
  final trackedDocs = <String, String>{};
  bool inProgress = false;
  int turnsSinceLastCheck = 0;
}

/// Initialize magic docs: register the FileReadTool listener.
void initMagicDocs(MagicDocsState state) {
  FileReadTool.onFileRead = (filePath, content) {
    _onFileRead(state, filePath, content);
  };
}

/// Listener: detect magic doc headers in read files.
void _onFileRead(MagicDocsState state, String filePath, String content) {
  final match = _magicDocPattern.firstMatch(content);
  if (match != null) {
    final title = match.group(1)!.trim();
    if (!state.trackedDocs.containsKey(filePath)) {
      log('MagicDocs', 'Tracking: $filePath ($title)');
    }
    state.trackedDocs[filePath] = title;
  } else if (state.trackedDocs.containsKey(filePath)) {
    // Header removed — untrack
    log('MagicDocs', 'Untracking: $filePath (header removed)');
    state.trackedDocs.remove(filePath);
  }
}

/// Post-turn hook: update tracked magic docs when conversation is idle
/// (last assistant message has no tool calls).
Future<void> hookMagicDocs(PostTurnContext ctx, MagicDocsState state) async {
  if (state.inProgress) return;
  if (state.trackedDocs.isEmpty) return;

  state.turnsSinceLastCheck++;
  if (state.turnsSinceLastCheck < 20) return;
  state.turnsSinceLastCheck = 0;

  // Filter out deleted files
  state.trackedDocs.removeWhere((path, _) => !File(path).existsSync());
  if (state.trackedDocs.isEmpty) return;

  state.inProgress = true;
  log('MagicDocs', 'Updating ${state.trackedDocs.length} magic docs');

  try {
    // Process sequentially to avoid concurrent edits
    for (final entry in Map.of(state.trackedDocs).entries) {
      await _updateMagicDoc(ctx, entry.key, entry.value);
    }
  } catch (e) {
    log('MagicDocs', 'Error: $e');
  } finally {
    state.inProgress = false;
  }
}

Future<void> _updateMagicDoc(
  PostTurnContext ctx,
  String filePath,
  String title,
) async {
  final file = File(filePath);
  if (!file.existsSync()) return;

  final currentContent = file.readAsStringSync();

  // Re-check header is still present
  if (!_magicDocPattern.hasMatch(currentContent)) {
    log('MagicDocs', 'Skipping $filePath: header removed');
    return;
  }

  // Extract optional custom instructions (italicized line after header)
  String? customInstructions;
  final lines = currentContent.split('\n');
  if (lines.length > 1) {
    final secondLine = lines[1].trim();
    if (secondLine.startsWith('*') && secondLine.endsWith('*')) {
      customInstructions = secondLine.substring(1, secondLine.length - 1);
    }
  }

  // Build compact conversation context
  final recentMessages = ctx.messages.length > 15
      ? ctx.messages.sublist(ctx.messages.length - 15)
      : ctx.messages;

  final conversationSummary = recentMessages
      .map((m) {
        final role = m.role.name.toUpperCase();
        var text = m.content;
        if (text.length > 300) text = '${text.substring(0, 300)}...';
        if (m.toolUses != null && m.toolUses!.isNotEmpty) {
          final tools = m.toolUses!.map((t) => t.name).join(', ');
          return '$role: [tools: $tools] $text';
        }
        return '$role: $text';
      })
      .join('\n');

  final updatePrompt =
      '''Update this magic document with new information from the recent conversation.

## Document: $title
## Path: $filePath
${customInstructions != null ? '## Custom instructions: $customInstructions' : ''}

## Current content

$currentContent

## Recent conversation

$conversationSummary

## Rules

- Use the Edit tool to update the document
- Only add high-signal information: architecture, patterns, key decisions, entry points
- Do NOT add code walkthroughs or obvious information
- Keep the document concise and well-organized
- Preserve the # MAGIC DOC header and any custom instructions line
- If nothing new to add, do not make any edits''';

  // Create sub-agent with only Edit tool, restricted to this file
  final subClient = ctx.client.clone();
  final subContext = ToolContext(
    basePath: ctx.toolContext.basePath,
    serviceBaseUrl: ctx.toolContext.serviceBaseUrl,
    skipPermissions: true,
  );
  subContext.readFileTimestamps[filePath] = file
      .statSync()
      .modified
      .millisecondsSinceEpoch;

  final subSessionManager = SessionManager(
    sessionsDir: '${ctx.toolContext.basePath}/sessions/magic_docs',
  );

  final subAgent = Agent(
    client: subClient,
    tools: [FileReadTool(), FileEditTool()],
    promptBuilder: PromptBuilder(
      basePrompt:
          'You are a document updater. Update the specified magic document with new information from the conversation. Only use the Edit tool on the specified file.',
      basePath: ctx.toolContext.basePath,
    ),
    toolContext: subContext,
    sessionManager: subSessionManager,
    contextWindow: 160000,
    maxOutputTokens: 4096,
  );

  try {
    final result = await subAgent.runToCompletion(updatePrompt);
    log(
      'MagicDocs',
      '$title: ${result.length > 80 ? '${result.substring(0, 80)}...' : result}',
    );
  } catch (e) {
    log('MagicDocs', '$title update failed: $e');
  }
}
