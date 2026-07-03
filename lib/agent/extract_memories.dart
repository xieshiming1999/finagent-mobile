import 'dart:io';

import 'package:path/path.dart' as p;

import 'agent.dart';
import 'llm_client.dart';
import 'log.dart';
import 'message.dart';
import 'prompt_builder.dart';
import 'session.dart';
import 'tool.dart';
import 'tool_context.dart';
import 'tools/file_edit_tool/file_edit_tool.dart';
import 'tools/file_read_tool/file_read_tool.dart';
import 'tools/file_write_tool/file_write_tool.dart';
import 'tools/glob_tool/glob_tool.dart';
import 'tools/grep_tool/grep_tool.dart';
import 'tools/ls_tool/ls_tool.dart';
import 'tools/skill_tool/skill_tool.dart';

// Reference: claude-code-best/src/services/extractMemories/

const _maxSubAgentTurns = 5;

/// Check whether the main agent wrote memory files this turn.
/// If so, extraction is unnecessary (agent already saved what it wanted).
bool hasMemoryWritesSince(List<Message> messages, int sinceIndex) {
  for (var i = sinceIndex; i < messages.length; i++) {
    final msg = messages[i];
    if (msg.role != Role.assistant || msg.toolUses == null) continue;
    for (final tu in msg.toolUses!) {
      if (tu.name == 'Write' || tu.name == 'Edit') {
        final filePath = tu.input['file_path'] as String? ?? '';
        if (filePath.contains('memory/')) return true;
      }
      if (tu.name == 'Skill') {
        final action = tu.input['skill'] as String? ?? '';
        if (action == 'create' || action == 'update') return true;
      }
    }
  }
  return false;
}

/// Scan memory directory for existing files and build a manifest string.
/// This is injected into the extraction prompt so the sub-agent knows
/// what already exists (avoids wasting turns on ls).
String buildMemoryManifest(String memoryDir) {
  final dir = Directory(memoryDir);
  if (!dir.existsSync()) return '(empty)';

  final entries = <String>[];
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File) continue;
    if (!entity.path.endsWith('.md')) continue;
    if (p.basename(entity.path).startsWith('.')) continue;

    final relativePath = p.relative(entity.path, from: memoryDir);
    final stat = entity.statSync();
    final modified = stat.modified.toIso8601String().substring(0, 10);

    // Read frontmatter for type and description
    String type = '?';
    String desc = '';
    try {
      final lines = entity.readAsStringSync().split('\n');
      for (final line in lines.take(10)) {
        if (line.startsWith('type:')) type = line.substring(5).trim();
        if (line.startsWith('description:')) desc = line.substring(12).trim();
      }
    } catch (_) {}

    entries.add('- [$type] $relativePath ($modified): $desc');
  }

  if (entries.isEmpty) return '(empty)';
  entries.sort();
  return entries.join('\n');
}

/// Build the extraction prompt for the sub-agent.
String _buildExtractPrompt(int newMessageCount, String manifest) {
  return '''You are the memory extraction sub-agent. Analyze the most recent ~$newMessageCount messages above and decide if any information should be persisted to memory.

## What to extract

1. **User preferences/role** → write memory file (type: user or feedback)
2. **Project state/deadlines** → write memory file (type: project or reference)
3. **Reusable multi-step workflows** → create skill via Skill tool
4. **Updates to existing memories/skills** → update rather than create duplicates
5. **None of the above** → do nothing (this is the most common outcome)

## What NOT to save

- Code patterns, architecture, file paths — derivable from reading the codebase
- Git history, recent changes — use git log/blame
- Debugging solutions — the fix is in the code
- Ephemeral task details or current conversation context
- Anything already covered by existing memories

## Existing files

<manifest>
$manifest
</manifest>

## Rules

- You have at most $_maxSubAgentTurns turns. Plan efficiently: turn 1 = read existing files if needed, turn 2 = write.
- Memory files use frontmatter: name, description, type (user/feedback/project/reference).
- Update MEMORY.md index when creating/modifying memory files.
- Only write to the memory/ directory.
- If nothing worth saving, respond with "No new memories to extract." and stop.
- Convert relative dates to absolute dates (e.g., "next Thursday" → "2026-05-01").
- For feedback type, include **Why:** and **How to apply:** lines.''';
}

/// Restricted tool set for memory extraction sub-agent.
/// Only file tools scoped to memory/ + Skill for create/update.
List<Tool> _getExtractTools() => [
  FileReadTool(),
  FileWriteTool(),
  FileEditTool(),
  GlobTool(),
  GrepTool(),
  LSTool(),
  SkillTool(),
];

/// Run memory extraction as a fire-and-forget sub-agent.
///
/// [messages] — the full conversation history (sub-agent sees this in fork mode).
/// [turnStartIndex] — index of the first message in this turn (for hasMemoryWritesSince).
/// [client] — parent's LLM client (will be cloned).
/// [toolContext] — parent's tool context.
/// [promptBuilder] — parent's prompt builder (for system prompt cache sharing).
/// [sessionManager] — parent's session manager (for sidechain session dir).
Future<void> runExtractMemories({
  required List<Message> messages,
  required int turnStartIndex,
  required LLMClient client,
  required ToolContext toolContext,
  required PromptBuilder promptBuilder,
  required SessionManager sessionManager,
}) async {
  // Gate: skip if agent already wrote memory this turn
  if (hasMemoryWritesSince(messages, turnStartIndex)) {
    log('ExtractMemories', 'Skipped: agent already wrote memory this turn');
    return;
  }

  // Gate: need at least a few messages to analyze
  if (messages.length < 3) {
    log('ExtractMemories', 'Skipped: too few messages (${messages.length})');
    return;
  }

  log(
    'ExtractMemories',
    'Starting extraction (${messages.length} messages, turn start: $turnStartIndex)',
  );

  try {
    final manifest = buildMemoryManifest(toolContext.memoryDir);
    final newMessageCount = messages.length - turnStartIndex;
    final extractPrompt = _buildExtractPrompt(newMessageCount, manifest);

    // Create sub-agent with restricted tools and fork context
    final subClient = client.clone();
    final subContext = ToolContext(
      basePath: toolContext.basePath,
      serviceBaseUrl: toolContext.serviceBaseUrl,
      skipPermissions: true,
    );
    subContext.readFileTimestamps.addAll(toolContext.readFileTimestamps);

    final sidechainDir = p.join(
      toolContext.basePath,
      'sessions',
      sessionManager.currentSession?.id ?? 'unknown',
      'extract',
    );
    final subSessionManager = SessionManager(sessionsDir: sidechainDir);

    final subAgent = Agent(
      client: subClient,
      tools: _getExtractTools(),
      promptBuilder: promptBuilder,
      toolContext: subContext,
      sessionManager: subSessionManager,
      contextWindow: 160000,
      maxOutputTokens: 4096,
    );

    // Fork: inherit parent messages for context
    subAgent.messages.addAll(
      messages.map(
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

    final result = await subAgent.runToCompletion(extractPrompt);
    log(
      'ExtractMemories',
      'Completed: ${result.length > 100 ? '${result.substring(0, 100)}...' : result}',
    );
  } catch (e) {
    log('ExtractMemories', 'Error: $e');
  }
}
