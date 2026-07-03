import 'package:path/path.dart' as p;

import 'agent.dart';
import 'consolidation_lock.dart';
import 'llm_client.dart';
import 'log.dart';
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

// Reference: claude-code-best/src/services/autoDream/

const _defaultMinHours = 24;
const _defaultMinModifiedFiles = 5;

/// Mutable dream state, scoped to a single agent lifetime.
class AutoDreamState {
  bool inProgress = false;
}

/// Check all 3 gates and run dream if they pass. Fire-and-forget.
///
/// Gates (cheapest first):
/// 1. Time gate: >= 24h since last dream
/// 2. Change gate: >= 5 modified .md files since last dream
/// 3. Lock gate: no other dream in progress
Future<void> maybeRunAutoDream({
  required LLMClient client,
  required ToolContext toolContext,
  required PromptBuilder promptBuilder,
  required SessionManager sessionManager,
  required AutoDreamState state,
  int minHours = _defaultMinHours,
  int minModifiedFiles = _defaultMinModifiedFiles,
}) async {
  if (state.inProgress) {
    log('AutoDream', 'Skipped: already in progress');
    return;
  }

  final memoryDir = toolContext.memoryDir;

  // Gate 1: Time
  final lastDreamMs = readLastConsolidatedAt(memoryDir);
  final elapsedMs = DateTime.now().millisecondsSinceEpoch - lastDreamMs;
  final minMs = minHours * 60 * 60 * 1000;
  if (elapsedMs < minMs) {
    log(
      'AutoDream',
      'Skipped: time gate (${elapsedMs ~/ 3600000}h < ${minHours}h)',
    );
    return;
  }

  // Gate 2: Change count
  final modifiedCount = countModifiedFilesSince(memoryDir, lastDreamMs);
  if (modifiedCount < minModifiedFiles) {
    log(
      'AutoDream',
      'Skipped: change gate ($modifiedCount < $minModifiedFiles files)',
    );
    return;
  }

  // Gate 3: Lock
  final priorMtime = tryAcquireConsolidationLock(memoryDir);
  if (priorMtime == null) {
    log('AutoDream', 'Skipped: lock gate (another dream in progress)');
    return;
  }

  state.inProgress = true;
  log(
    'AutoDream',
    'All gates passed. Starting dream '
        '(elapsed: ${elapsedMs ~/ 3600000}h, modified: $modifiedCount files)',
  );

  try {
    await _runDreamAgent(
      client: client,
      toolContext: toolContext,
      promptBuilder: promptBuilder,
      sessionManager: sessionManager,
    );
    releaseConsolidationLock(memoryDir);
    log('AutoDream', 'Dream completed successfully');
  } catch (e) {
    rollbackConsolidationLock(memoryDir, priorMtime);
    log('AutoDream', 'Dream failed, lock rolled back: $e');
  } finally {
    state.inProgress = false;
  }
}

/// Run dream unconditionally (for /dream slash command).
/// Skips all gates, acquires lock, runs, releases.
Future<String> runDreamManually({
  required LLMClient client,
  required ToolContext toolContext,
  required PromptBuilder promptBuilder,
  required SessionManager sessionManager,
}) async {
  final memoryDir = toolContext.memoryDir;

  final priorMtime = tryAcquireConsolidationLock(memoryDir);
  if (priorMtime == null) {
    return 'Another dream process is already running. Please wait for it to complete.';
  }

  try {
    final result = await _runDreamAgent(
      client: client,
      toolContext: toolContext,
      promptBuilder: promptBuilder,
      sessionManager: sessionManager,
    );
    releaseConsolidationLock(memoryDir);
    recordConsolidation(memoryDir);
    return result;
  } catch (e) {
    rollbackConsolidationLock(memoryDir, priorMtime);
    return 'Dream failed: $e';
  }
}

/// Build the 4-phase consolidation prompt.
String _buildDreamPrompt(String memoryDir) {
  return '''You are the memory consolidation sub-agent. Your job is to organize, deduplicate, and prune the memory directory to keep it clean and useful.

Work through these 4 phases in order:

## Phase 1 — Orient

- ls the memory/ directory (including memory/skills/)
- Read MEMORY.md index
- Skim existing memory files (read frontmatter + first few lines of each)

## Phase 2 — Analyze

Identify issues:
- **Duplicate** memories (same information in different files)
- **Contradictory** memories (conflicting facts)
- **Stale** memories (past deadlines, completed projects, outdated info)
- **Similar skills** with overlapping functionality
- **Orphaned** index entries (pointing to deleted files) or unindexed files

## Phase 3 — Consolidate

Take action:
- Merge duplicate memory files into one (keep the more complete version)
- Merge overlapping skills (combine into one, delete the other)
- Delete stale entries (past deadlines, completed one-off projects)
- Convert relative dates to absolute dates
- Consolidate fragmented small files into topic-based files
- Update frontmatter (name, description, type) to be accurate

## Phase 4 — Prune index

- Update MEMORY.md to reflect current state
- Keep MEMORY.md under 200 lines
- Remove dead pointers
- Ensure every memory file and skill has an index entry
- Keep entries concise (one line each, under ~150 chars)

## Rules

- Only write to the memory/ directory
- Do not delete bundle/skills/ content (read-only)
- If the memory system is already clean, say so and stop
- Be conservative: when in doubt, keep rather than delete
- Report what you changed at the end

## Working directory

memory/ is at: $memoryDir''';
}

/// Restricted tools for dream sub-agent.
List<Tool> _getDreamTools() => [
  FileReadTool(),
  FileWriteTool(),
  FileEditTool(),
  GlobTool(),
  GrepTool(),
  LSTool(),
  SkillTool(),
];

/// Create and run the dream sub-agent. Returns the agent's text output.
Future<String> _runDreamAgent({
  required LLMClient client,
  required ToolContext toolContext,
  required PromptBuilder promptBuilder,
  required SessionManager sessionManager,
}) async {
  final dreamPrompt = _buildDreamPrompt(toolContext.memoryDir);

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
    'dream',
  );
  final subSessionManager = SessionManager(sessionsDir: sidechainDir);

  // Independent mode (no fork) — dream doesn't need conversation context
  final subPromptBuilder = PromptBuilder(
    basePrompt:
        'You are a memory consolidation agent. Organize and clean up the memory directory.',
    basePath: toolContext.basePath,
  );

  final subAgent = Agent(
    client: subClient,
    tools: _getDreamTools(),
    promptBuilder: subPromptBuilder,
    toolContext: subContext,
    sessionManager: subSessionManager,
    contextWindow: 160000,
    maxOutputTokens: 8192,
  );

  return subAgent.runToCompletion(dreamPrompt);
}
