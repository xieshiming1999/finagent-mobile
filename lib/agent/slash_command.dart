// ignore_for_file: unintended_html_in_doc_comment
import 'dart:convert';
import 'dart:io';

import 'auto_dream.dart';
import 'command_loader.dart';
import 'compact.dart';
import 'file_history.dart';
import 'goal_manager.dart';
import 'goal_templates.dart';
import 'goal_automation_types.dart';
import 'llm_client.dart';
import 'message.dart';
import 'prompt_builder.dart';
import 'session.dart';
import 'tool_context.dart';

// Reference: claude-code-best/src/commands.ts, processSlashCommand.tsx

/// Result of executing a slash command.
sealed class CommandResult {}

/// Text output to show the user.
class TextCommandResult extends CommandResult {
  final String text;
  TextCommandResult(this.text);
}

/// Compaction was performed.
class CompactCommandResult extends CommandResult {
  final CompactResult result;
  CompactCommandResult(this.result);
}

/// Conversation cleared and archived.
class ClearCommandResult extends CommandResult {}

/// Session resumed from history.
class ResumeCommandResult extends CommandResult {
  final Session session;
  final List<Message> messages;
  ResumeCommandResult({required this.session, required this.messages});
}

/// Command produced a list for user selection (e.g., /resume without args).
class ListCommandResult extends CommandResult {
  final String prompt;
  final List<SessionSummary> sessions;
  ListCommandResult({required this.prompt, required this.sessions});
}

/// Command produced a prompt to send to the agent (file-based commands).
class PromptCommandResult extends CommandResult {
  final String prompt;
  PromptCommandResult(this.prompt);
}

/// Goal was set — run the goal text as a prompt and start the goal loop.
class GoalSetCommandResult extends CommandResult {
  final String goalPrompt;
  GoalSetCommandResult(this.goalPrompt);
}

/// Session forked into a new session with current messages.
class ForkCommandResult extends CommandResult {}

/// Side question result — does not modify session.
class BtwCommandResult extends CommandResult {
  final String question;
  BtwCommandResult(this.question);
}

/// Steer message to be injected at next opportunity.
class SteerCommandResult extends CommandResult {
  final String text;
  SteerCommandResult(this.text);
}

/// Export session content to a file.
class ExportCommandResult extends CommandResult {
  final String format; // 'markdown' | 'json'
  final String content;
  final String filename;
  ExportCommandResult({
    required this.format,
    required this.content,
    required this.filename,
  });
}

/// A slash command definition.
class SlashCommand {
  final String name;
  final List<String> aliases;
  final String description;
  final Future<CommandResult> Function(String args, CommandContext context)
  handler;

  const SlashCommand({
    required this.name,
    this.aliases = const [],
    required this.description,
    required this.handler,
  });
}

/// Context passed to command handlers.
class CommandContext {
  final SessionManager sessionManager;
  final ToolContext toolContext;
  final List<Message> messages;
  final LLMClient client;
  final PromptBuilder promptBuilder;
  final GoalManager goalManager;

  /// Callback to trigger compaction (needs access to LLMClient via Agent).
  final Future<CompactResult> Function({String? customInstructions}) compactFn;

  const CommandContext({
    required this.sessionManager,
    required this.toolContext,
    required this.messages,
    required this.client,
    required this.promptBuilder,
    required this.goalManager,
    required this.compactFn,
  });
}

/// Parse user input to check if it's a slash command.
/// Returns (commandName, args) or null if not a command.
(String, String)? parseSlashCommand(String input) {
  final trimmed = input.trim();
  if (!trimmed.startsWith('/')) return null;

  final spaceIdx = trimmed.indexOf(' ');
  if (spaceIdx == -1) {
    return (trimmed.substring(1).toLowerCase(), '');
  }

  final command = trimmed.substring(1, spaceIdx).toLowerCase();
  final args = trimmed.substring(spaceIdx + 1).trim();
  return (command, args);
}

/// Find a command by name or alias.
SlashCommand? findCommand(String name, List<SlashCommand> commands) {
  for (final cmd in commands) {
    if (cmd.name == name) return cmd;
    if (cmd.aliases.contains(name)) return cmd;
  }
  return null;
}

/// Get all slash commands: built-ins + file-defined commands.
List<SlashCommand> getAllCommands(String basePath) {
  final commands = getBuiltinCommands();

  // Load file-based commands from bundle/commands/ and memory/commands/
  for (final fc in discoverCommands(basePath)) {
    // Skip if name conflicts with built-in
    if (findCommand(fc.name, commands) != null) continue;
    commands.add(
      SlashCommand(
        name: fc.name,
        description: fc.description,
        handler: (args, context) async {
          final expanded = expandCommandTemplate(fc.promptTemplate, args);
          return PromptCommandResult(expanded);
        },
      ),
    );
  }

  return commands;
}

/// Get built-in slash commands only.
List<SlashCommand> getBuiltinCommands() => [
  SlashCommand(
    name: 'compact',
    description: 'Compress conversation history to save context space',
    handler: _handleCompact,
  ),
  SlashCommand(
    name: 'clear',
    aliases: ['reset', 'new'],
    description: 'Clear conversation and start a new session',
    handler: _handleClear,
  ),
  SlashCommand(
    name: 'resume',
    aliases: ['continue'],
    description: 'Resume a previous conversation session',
    handler: _handleResume,
  ),
  SlashCommand(
    name: 'memory',
    description: 'Show current memory index',
    handler: _handleMemory,
  ),
  SlashCommand(
    name: 'help',
    description: 'Show available commands',
    handler: _handleHelpUpdated,
  ),
  SlashCommand(
    name: 'dream',
    description: 'Consolidate and organize memory files',
    handler: _handleDream,
  ),
  SlashCommand(
    name: 'undo',
    description: 'Restore a file to its previous version',
    handler: _handleUndo,
  ),
  SlashCommand(
    name: 'goal',
    description:
        'Autonomous goal loop: /goal <text>, /goal status/pause/resume/clear/help',
    handler: _handleGoal,
  ),
  SlashCommand(
    name: 'subgoal',
    description:
        'Add criteria to active goal: /subgoal <text>, /subgoal remove/clear/list/help',
    handler: _handleSubgoal,
  ),
  SlashCommand(
    name: 'status',
    description: 'Show agent status (tools, session, goals)',
    handler: _handleStatus,
  ),
  SlashCommand(
    name: 'fork',
    description:
        'Fork conversation into a new session (keeps current messages)',
    handler: _handleFork,
  ),
  SlashCommand(
    name: 'diff',
    description: 'Show files modified in this session',
    handler: _handleDiff,
  ),
  SlashCommand(
    name: 'cost',
    aliases: ['usage'],
    description: 'Show session token usage',
    handler: _handleCost,
  ),
  SlashCommand(
    name: 'btw',
    aliases: ['side'],
    description: 'Ask a side question without modifying the session',
    handler: _handleBtw,
  ),
  SlashCommand(
    name: 'export',
    description: 'Export session: /export [markdown|json]',
    handler: _handleExport,
  ),
  SlashCommand(
    name: 'steer',
    aliases: ['tell'],
    description: 'Inject a message for the agent at the next opportunity',
    handler: _handleSteer,
  ),
  SlashCommand(
    name: 'background',
    aliases: ['bg'],
    description: 'Run a prompt in the background (parallel)',
    handler: _handleBackground,
  ),
  SlashCommand(
    name: 'rollback',
    description: 'List or restore filesystem checkpoints',
    handler: _handleRollback,
  ),
  SlashCommand(
    name: 'agents',
    aliases: ['tasks'],
    description: 'Show active and recent background tasks',
    handler: _handleAgents,
  ),
  SlashCommand(
    name: 'stash',
    description: 'Save/restore prompts: /stash push/pop/list/drop/clear',
    handler: _handleStash,
  ),
  SlashCommand(
    name: 'busy',
    description:
        'Control input behavior while agent is working: /busy [queue|steer|interrupt]',
    handler: _handleBusy,
  ),
  SlashCommand(
    name: 'reasoning',
    aliases: ['thinking'],
    description: 'Control reasoning display: /reasoning [show|hide]',
    handler: _handleReasoning,
  ),
];

// --- Command Handlers ---

/// /compact [custom instructions]
Future<CommandResult> _handleCompact(
  String args,
  CommandContext context,
) async {
  final result = await context.compactFn(
    customInstructions: args.isNotEmpty ? args : null,
  );
  return CompactCommandResult(result);
}

/// /clear — archive current session, create new
Future<CommandResult> _handleClear(String args, CommandContext context) async {
  context.sessionManager.archiveAndCreate(
    feature: context.sessionManager.currentSession?.feature,
  );
  return ClearCommandResult();
}

/// /resume [session id or search term]
Future<CommandResult> _handleResume(String args, CommandContext context) async {
  final sessions = context.sessionManager.listHistory();

  if (sessions.isEmpty) {
    return TextCommandResult('No previous sessions found.');
  }

  if (args.isEmpty) {
    // Return list for UI to present to user
    return ListCommandResult(
      prompt: 'Select a session to resume:',
      sessions: sessions,
    );
  }

  // Search by ID or title
  final match = sessions.where((s) {
    if (s.id == args) return true;
    if (s.title != null &&
        s.title!.toLowerCase().contains(args.toLowerCase())) {
      return true;
    }
    if (s.firstPrompt != null &&
        s.firstPrompt!.toLowerCase().contains(args.toLowerCase())) {
      return true;
    }
    return false;
  }).firstOrNull;

  if (match == null) {
    return TextCommandResult(
      'No session found matching "$args". '
      'Use /resume without arguments to see all sessions.',
    );
  }

  final (session, messages) = context.sessionManager.resumeSession(
    match.filePath,
  );
  return ResumeCommandResult(session: session, messages: messages);
}

/// /memory — show MEMORY.md content
Future<CommandResult> _handleMemory(String args, CommandContext context) async {
  final memoryFile = File('${context.toolContext.memoryDir}/MEMORY.md');

  if (!memoryFile.existsSync()) {
    return TextCommandResult(
      'No memories saved yet. '
      'The agent will automatically save important information to memory/.',
    );
  }

  final content = memoryFile.readAsStringSync().trim();
  if (content.isEmpty) {
    return TextCommandResult('Memory index is empty.');
  }

  return TextCommandResult('# Memory Index\n\n$content');
}

/// /dream — manually trigger memory consolidation
Future<CommandResult> _handleDream(String args, CommandContext context) async {
  final result = await runDreamManually(
    client: context.client,
    toolContext: context.toolContext,
    promptBuilder: context.promptBuilder,
    sessionManager: context.sessionManager,
  );
  return TextCommandResult(result);
}

/// /undo <file_path> — restore a file to its previous version
Future<CommandResult> _handleUndo(String args, CommandContext context) async {
  if (args.isEmpty) {
    return TextCommandResult(
      'Usage: /undo <file_path>\n'
      'Restores the file to its most recent snapshot (taken before each edit/write).',
    );
  }

  final filePath = args.trim();
  final basePath = context.toolContext.basePath;
  final snapshots = listSnapshots(filePath, basePath);

  if (snapshots.isEmpty) {
    return TextCommandResult('No snapshots found for "$filePath".');
  }

  final restored = restoreLatest(filePath, basePath);
  if (restored == null) {
    return TextCommandResult('Failed to restore "$filePath".');
  }

  final time =
      '${restored.hour}:${restored.minute.toString().padLeft(2, '0')}:${restored.second.toString().padLeft(2, '0')}';
  return TextCommandResult(
    'Restored "$filePath" to snapshot from $time.\n'
    '${snapshots.length - 1} older snapshots still available.',
  );
}

// --- /goal ---

const _goalHelp = '''Goal — Autonomous Multi-Turn Loop

Commands:
  /goal <text>                              Set a goal and start working
  /goal templates                           List reusable goal templates
  /goal template <id>                       Start from a reusable template
  /goal status                              Show current goal progress
  /goal pause                               Pause the goal loop
  /goal resume                              Resume (resets turn budget)
  /goal clear                               Abandon the goal
  /goal help                                Show this help

Examples:
  /goal 分析贵州茅台最新财报并输出分析报告
  /goal Analyze AAPL, MSFT, GOOG earnings and compare profitability
  /goal template api_error_triage
  /goal Read plans/example_goal_plan.md and implement it

Long-running goals should point at a concrete artifact, not only chat context.
Prefer: "Read <plan-file> and implement it." Avoid vague text such as "above
plan" unless the command can snapshot the recent conversation into the goal.

The agent works autonomously turn by turn. After each turn, a judge
evaluates whether the goal is complete. The loop continues until:
  - Goal is achieved (judge says done)
  - Goal is blocked and needs input or an external change
  - Turn budget exhausted (default 20, marks budget-limited)
  - You pause or clear the goal

Side effects:
  - /goal writes goal state in the runtime memory/session area.
  - It may continue across turns and trigger normal tools according to the
    active app, skills, permissions, and goal text.
  - Real trading or destructive operations still require explicit guarded
    workflow approval and should stop when credentials or confirmation are
    missing.

Use /subgoal to add criteria mid-loop.''';

Future<CommandResult> _handleGoal(String args, CommandContext ctx) async {
  final parts = args.trim().split(RegExp(r'\s+'));
  final subCmd = parts.first.toLowerCase();

  switch (subCmd) {
    case 'templates':
      return TextCommandResult(
        [
          'Goal templates:',
          ...goalTemplates.map((t) => '- ${t.id.wireName}: ${t.title}'),
          '',
          'Use: /goal template <id>',
        ].join('\n'),
      );

    case 'template':
      final id = parts.length > 1 ? parts[1] : '';
      final template = getGoalTemplate(id);
      if (template == null) {
        return TextCommandResult(
          'Unknown goal template. Available: ${goalTemplates.map((t) => t.id.wireName).join(', ')}',
        );
      }
      if (ctx.goalManager.isActive) {
        return TextCommandResult(
          'A goal is already active. /goal clear first, or /goal pause then set a new one.',
        );
      }
      final prompt = buildGoalPrompt(template);
      ctx.goalManager.set(
        prompt,
        maxTurns: template.defaultMaxTurns,
        options: GoalSetOptions(
          templateId: template.id,
          successCriteria: template.successCriteria,
          source: 'template:${template.id.wireName}',
          planSnapshot: _buildRecentContextSnapshot(ctx),
          doneCriteria: template.successCriteria,
          verification: template.verifierChecks.join('; '),
          escalation: template.guardrails.join('; '),
          verifierResult: GoalVerifierResult(
            status: 'unchecked',
            checkedAt: DateTime.now().millisecondsSinceEpoch,
            reason: 'Manual template goal started; verifier has not run yet.',
          ),
        ),
      );
      return GoalSetCommandResult(prompt);

    case 'status':
      return TextCommandResult(ctx.goalManager.statusLine());

    case 'pause':
      if (!ctx.goalManager.hasGoal) return TextCommandResult('No active goal.');
      ctx.goalManager.pause('user-paused');
      return TextCommandResult('⏸ Goal paused. Use /goal resume to continue.');

    case 'resume':
      if (!ctx.goalManager.hasGoal) {
        return TextCommandResult('No goal to resume.');
      }
      ctx.goalManager.resume();
      final prompt = ctx.goalManager.nextContinuationPrompt();
      if (prompt != null) return GoalSetCommandResult(prompt);
      return TextCommandResult('⊙ Goal resumed.');

    case 'clear':
    case 'stop':
    case 'done':
      if (!ctx.goalManager.hasGoal) return TextCommandResult('No active goal.');
      ctx.goalManager.clear();
      return TextCommandResult('✗ Goal cleared.');

    case 'help':
      return TextCommandResult(_goalHelp);

    case '':
      return TextCommandResult(_goalHelp);
  }

  // Set a new goal
  final goalText = args.trim();
  if (goalText.isEmpty) return TextCommandResult(_goalHelp);
  if (ctx.goalManager.isActive) {
    return TextCommandResult(
      'A goal is already active. /goal clear first, or /goal pause then set a new one.',
    );
  }
  try {
    ctx.goalManager.set(
      goalText,
      options: GoalSetOptions(
        source: 'slash-command:/goal',
        planSnapshot: _shouldSnapshotRecentContext(goalText)
            ? _buildRecentContextSnapshot(ctx)
            : null,
        scope:
            'Current conversation and current workspace unless the goal narrows the scope.',
        doneCriteria: const [
          'The objective is completed and verified against the current repository state.',
        ],
        verification:
            'Report concrete evidence from files, command output, tests, or runtime behavior.',
        escalation:
            'Stop and ask for input before destructive schema changes, real trading side effects, missing credentials, or incompatible backward-compatibility changes.',
      ),
    );
    return GoalSetCommandResult(goalText);
  } catch (e) {
    return TextCommandResult('Error: $e');
  }
}

bool _shouldSnapshotRecentContext(String text) {
  final lower = text.toLowerCase();
  return RegExp(
        r'\b(above|previous|this|that|recent)\s+(plan|discussion|idea|context|report|design)\b',
      ).hasMatch(lower) ||
      text.contains('上面') ||
      text.contains('刚才') ||
      text.contains('前面') ||
      text.contains('这个计划') ||
      text.contains('上述计划') ||
      text.contains('之前');
}

String _buildRecentContextSnapshot(CommandContext ctx) {
  final lines = ctx.messages.reversed
      .take(10)
      .toList()
      .reversed
      .map((message) {
        final compact = message.content.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (compact.isEmpty) return '';
        return '${message.role.name}: ${compact.length > 800 ? compact.substring(0, 800) : compact}';
      })
      .where((line) => line.isNotEmpty)
      .toList();
  final joined = lines.join('\n');
  return joined.length > 6000 ? joined.substring(joined.length - 6000) : joined;
}

// --- /subgoal ---

const _subgoalHelp = '''Subgoal — Add Criteria to Active Goal

Commands:
  /subgoal <text>                           Add a criterion
  /subgoal remove <N>                       Remove criterion by number
  /subgoal clear                            Remove all criteria
  /subgoal list                             List current criteria
  /subgoal help                             Show this help

Subgoals are additional criteria the judge checks alongside the main goal.
All subgoals must be satisfied for the goal to be marked complete.''';

Future<CommandResult> _handleSubgoal(String args, CommandContext ctx) async {
  final parts = args.trim().split(RegExp(r'\s+'));
  final subCmd = parts.first.toLowerCase();

  switch (subCmd) {
    case 'remove':
      final n = parts.length > 1 ? int.tryParse(parts[1]) : null;
      if (n == null) {
        return TextCommandResult('Usage: /subgoal remove <number>');
      }
      try {
        final removed = ctx.goalManager.removeSubgoal(n);
        return TextCommandResult('Removed subgoal #$n: "$removed"');
      } catch (e) {
        return TextCommandResult('Error: $e');
      }

    case 'clear':
      final count = ctx.goalManager.clearSubgoals();
      return TextCommandResult(
        count > 0 ? 'Cleared $count subgoals.' : 'No subgoals to clear.',
      );

    case 'list':
      final state = ctx.goalManager.state;
      if (state == null || state.subgoals.isEmpty) {
        return TextCommandResult('No subgoals.');
      }
      final lines = state.subgoals.asMap().entries.map(
        (e) => '  ${e.key + 1}. ${e.value}',
      );
      return TextCommandResult(
        'Subgoals (${state.subgoals.length}):\n${lines.join('\n')}',
      );

    case 'help':
    case '':
      return TextCommandResult(_subgoalHelp);
  }

  // Add a subgoal
  final text = args.trim();
  if (text.isEmpty) return TextCommandResult(_subgoalHelp);
  try {
    final added = ctx.goalManager.addSubgoal(text);
    final state = ctx.goalManager.state;
    return TextCommandResult(
      'Added subgoal #${state?.subgoals.length ?? '?'}: "$added"',
    );
  } catch (e) {
    return TextCommandResult('Error: $e');
  }
}

// --- /status ---

Future<CommandResult> _handleStatus(String args, CommandContext ctx) async {
  final lines = <String>[];

  // Session info
  final session = ctx.sessionManager.currentSession;
  if (session != null) {
    lines.add('Session: ${session.title ?? session.id}');
    lines.add('Messages: ${ctx.messages.length}');
  }

  // Goal status
  if (ctx.goalManager.hasGoal) {
    lines.add('');
    lines.add(ctx.goalManager.statusLine());
  } else {
    lines.add('Goal: none');
  }

  // Memory
  final memoryFile = File('${ctx.toolContext.memoryDir}/MEMORY.md');
  if (memoryFile.existsSync()) {
    final lineCount = memoryFile.readAsStringSync().split('\n').length;
    lines.add('Memory: $lineCount lines in MEMORY.md');
  }

  return TextCommandResult(lines.join('\n'));
}

// --- /fork ---

Future<CommandResult> _handleFork(String args, CommandContext ctx) async {
  return ForkCommandResult();
}

// --- /diff ---

Future<CommandResult> _handleDiff(String args, CommandContext ctx) async {
  return PromptCommandResult(
    'List all files that have been created, modified, or deleted in this session. '
    'Show a summary of changes for each file.',
  );
}

// --- /cost ---

Future<CommandResult> _handleCost(String args, CommandContext ctx) async {
  // Compute token estimates from messages
  int totalChars = 0;
  int userChars = 0;
  int assistantChars = 0;
  int toolChars = 0;
  int userMsgs = 0;
  int assistantMsgs = 0;
  int toolCalls = 0;

  for (final msg in ctx.messages) {
    final len = msg.content.length;
    totalChars += len;
    switch (msg.role) {
      case Role.user:
        userChars += len;
        userMsgs++;
      case Role.assistant:
        assistantChars += len;
        assistantMsgs++;
        if (msg.toolUses != null) toolCalls += msg.toolUses!.length;
      case Role.tool:
        toolChars += len;
    }
  }

  // Rough token estimate: ~4 chars per token for English, ~2 for CJK mix
  final estTokens = totalChars ~/ 3;

  return TextCommandResult(
    'Session usage:\n'
    '  Messages: $userMsgs user, $assistantMsgs assistant\n'
    '  Tool calls: $toolCalls\n'
    '  Characters: ${_formatNumber(totalChars)} total '
    '(user ${_formatNumber(userChars)}, assistant ${_formatNumber(assistantChars)}, tool ${_formatNumber(toolChars)})\n'
    '  Est. tokens: ~${_formatNumber(estTokens)}',
  );
}

String _formatNumber(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
  return '$n';
}

// --- Update /help to include new commands ---

Future<CommandResult> _handleHelpUpdated(
  String args,
  CommandContext context,
) async {
  final detail = _commandHelpDetail(args.trim());
  if (detail != null) return TextCommandResult(detail);

  final commands = getBuiltinCommands();
  String line(SlashCommand c) {
    final aliases = c.aliases.isNotEmpty
        ? ' (${c.aliases.map((a) => '/$a').join(', ')})'
        : '';
    return '  /${c.name}$aliases — ${c.description}';
  }

  final core = commands
      .where((c) => {
            'compact',
            'clear',
            'resume',
            'memory',
            'help',
            'status',
            'fork',
            'diff',
            'cost',
            'export',
          }.contains(c.name))
      .map(line);
  final goal = commands
      .where((c) => {'goal', 'subgoal'}.contains(c.name))
      .map(line);
  final workflow = commands
      .where((c) => {
            'dream',
            'undo',
            'btw',
            'steer',
            'background',
            'rollback',
            'agents',
            'stash',
            'busy',
            'reasoning',
          }.contains(c.name))
      .map(line);

  return TextCommandResult(
    [
      'Command help',
      '',
      'Core/session commands:',
      core.join('\n'),
      '',
      'Goal commands:',
      goal.join('\n'),
      '',
      'Workflow/debug commands:',
      workflow.join('\n'),
      '',
      'Use /help <command> for usage and side effects.',
      'Detailed help: /goal help, /subgoal help, /stash help, /busy help.',
      '',
      'Runtime notes:',
      '- FinAgent and Fin Electron share core command semantics where command names match.',
      '- Unsupported commands should report explicit usage instead of silently doing nothing.',
      '- Test/full-app automation is not a normal slash command; it is enabled only by debug flags such as FINAGENT_WORKFLOW_AUTOMATION.',
    ].join('\n'),
  );
}

String? _commandHelpDetail(String rawName) {
  if (rawName.isEmpty) return null;
  final name = rawName.startsWith('/') ? rawName.substring(1) : rawName;
  switch (name.toLowerCase()) {
    case 'goal':
      return _goalHelp;
    case 'subgoal':
      return _subgoalHelp;
    case 'compact':
      return '''/compact [instructions]

Compress conversation history to save context space.
Side effects: rewrites compact/session memory for the active session.''';
    case 'clear':
    case 'reset':
    case 'new':
      return '''/clear

Archive the current session and start a new one.
Side effects: changes active session; does not delete archived history.''';
    case 'resume':
    case 'continue':
      return '''/resume [session id | search text]

Resume a previous conversation. With no argument, lists available sessions.
Side effects: changes the active chat session.''';
    case 'memory':
      return '''/memory

Show the current MEMORY.md index.
Side effects: read-only.''';
    case 'status':
      return '''/status

Show session, goal, and memory status.
Side effects: read-only.''';
    case 'diff':
      return '''/diff

Ask the agent to summarize files changed in this session.
Side effects: read-only unless the agent later chooses tools for follow-up.''';
    case 'cost':
    case 'usage':
      return '''/cost

Estimate session size and token usage.
Side effects: read-only.''';
    case 'btw':
    case 'side':
      return '''/btw <question>

Ask a side question using the current context without changing the main task.
Side effects: returns a side answer; does not set a goal.''';
    case 'export':
      return '''/export [markdown|json] [filename]

Export the current session.
Side effects: writes an export artifact when the UI/runtime supports export.''';
    case 'steer':
    case 'tell':
      return '''/steer <message>

Inject guidance for the agent at the next safe opportunity.
Side effects: can change the current turn direction.''';
    case 'background':
    case 'bg':
      return '''/background <prompt>

Run a prompt as a parallel/background task when the runtime supports it.
Side effects: may create background agent/task state.''';
    case 'stash':
      return '''/stash push <text>
/stash pop
/stash list
/stash drop <N>
/stash clear

Save and restore prompt snippets.
Side effects: writes prompt-stash state in runtime memory.''';
    case 'busy':
      return '''/busy <queue|steer|interrupt>

Control how new input is handled while the agent is working.
Side effects: changes input handling policy for the current runtime.''';
    case 'dream':
      return '''/dream

Ask the agent to consolidate memory files.
Side effects: may rewrite memory files.''';
    case 'undo':
      return '''/undo <file>

Restore a file to its most recent snapshot.
Side effects: modifies the target file.''';
    case 'rollback':
      return '''/rollback [list|<number>|<hash>]

List or request restore of filesystem checkpoints.
Side effects: restore actions can modify many files and should be confirmed.''';
    case 'agents':
    case 'tasks':
      return '''/agents

Show active and recent background agents/tasks.
Side effects: read-only.''';
    case 'reasoning':
    case 'thinking':
      return '''/reasoning <show|hide>

Control reasoning display in supported UIs.
Side effects: changes UI display preference only.''';
    default:
      return 'Unknown command: /$name. Use /help for available commands.';
  }
}

// --- /btw ---

Future<CommandResult> _handleBtw(String args, CommandContext ctx) async {
  final question = args.trim();
  if (question.isEmpty) {
    return TextCommandResult(
      'Usage: /btw <question>\nAsk a side question without affecting the main conversation.',
    );
  }
  return BtwCommandResult(question);
}

// --- /export ---

Future<CommandResult> _handleExport(String args, CommandContext ctx) async {
  final parts = args.trim().split(RegExp(r'\s+'));
  var format = 'markdown';
  var filename = '';

  for (final p in parts) {
    if (p == 'json') {
      format = 'json';
    } else if (p == 'markdown' || p == 'md') {
      format = 'markdown';
    } else if (p.isNotEmpty) {
      filename = p;
    }
  }

  final now = DateTime.now();
  final dateStr =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  final timeStr =
      '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

  if (format == 'json') {
    final data = <Map<String, dynamic>>[];
    for (final m in ctx.messages) {
      final entry = <String, dynamic>{
        'role': m.role.name,
        'content': m.content,
        'timestamp': m.timestamp?.toIso8601String(),
      };
      if (m.toolUses != null) {
        entry['toolUses'] = m.toolUses!
            .map((t) => <String, dynamic>{'name': t.name, 'input': t.input})
            .toList();
      }
      data.add(entry);
    }
    final content = const JsonEncoder.withIndent('  ').convert(data);
    if (filename.isEmpty) filename = 'session-$dateStr-$timeStr.json';
    return ExportCommandResult(
      format: format,
      content: content,
      filename: filename,
    );
  }

  // Markdown export
  final lines = <String>['# Session Export — $dateStr\n'];
  var toolCallCount = 0;
  for (final m in ctx.messages) {
    final roleLabel = m.role == Role.user
        ? '**User**'
        : m.role == Role.assistant
        ? '**Assistant**'
        : '**Tool**';
    final time = m.timestamp != null
        ? '${m.timestamp!.hour}:${m.timestamp!.minute.toString().padLeft(2, '0')}'
        : '';
    lines.add('### $roleLabel $time\n');
    lines.add('${m.content}\n');
    if (m.toolUses != null) {
      toolCallCount += m.toolUses!.length;
      for (final tu in m.toolUses!) {
        final inputStr = tu.input is String
            ? (tu.input as String)
            : tu.input.toString();
        lines.add(
          '> Tool: **${tu.name}**(${inputStr.length > 100 ? inputStr.substring(0, 100) : inputStr}...)\n',
        );
      }
    }
  }
  lines.add(
    '\n---\n*${ctx.messages.length} messages, $toolCallCount tool calls*\n',
  );
  final content = lines.join('\n');
  if (filename.isEmpty) filename = 'session-$dateStr-$timeStr.md';
  return ExportCommandResult(
    format: format,
    content: content,
    filename: filename,
  );
}

// --- /steer ---

Future<CommandResult> _handleSteer(String args, CommandContext ctx) async {
  final text = args.trim();
  if (text.isEmpty) {
    return TextCommandResult(
      'Usage: /steer <message>\nInjects guidance that the agent sees at the next opportunity.',
    );
  }
  return SteerCommandResult(text);
}

// --- /background ---

Future<CommandResult> _handleBackground(String args, CommandContext ctx) async {
  final prompt = args.trim();
  if (prompt.isEmpty) {
    return TextCommandResult(
      'Usage: /background <prompt>\nRuns the prompt as a parallel background task.',
    );
  }
  return PromptCommandResult(
    '[Background task requested] Run the following in the background as a sub-agent:\n\n$prompt',
  );
}

// --- /rollback ---

Future<CommandResult> _handleRollback(String args, CommandContext ctx) async {
  final subCmd = args.trim();
  if (subCmd.isEmpty || subCmd == 'list') {
    return PromptCommandResult(
      'List all available git snapshots/checkpoints. Show the index number, time, and description for each.',
    );
  }
  return PromptCommandResult(
    'Rollback the working directory to checkpoint "$subCmd". Use the GitSnapshot restore function.',
  );
}

// --- /agents ---

Future<CommandResult> _handleAgents(String args, CommandContext ctx) async {
  return PromptCommandResult(
    'Show the status of all background tasks and sub-agents. Include: task ID, description, status, duration, and any results.',
  );
}

// --- /stash ---

Future<CommandResult> _handleStash(String args, CommandContext ctx) async {
  // Simple in-memory stash for finagent (no file persistence on mobile)
  final parts = args.trim().split(RegExp(r'\s+'));
  final subCmd = parts.isNotEmpty ? parts.first.toLowerCase() : '';

  switch (subCmd) {
    case 'push':
      final text = args.contains(' ')
          ? args.substring(args.indexOf(' ') + 1).trim()
          : '';
      if (text.isEmpty) return TextCommandResult('Usage: /stash push <text>');
      return TextCommandResult(
        'Stash not yet available on mobile. Use memory/ files instead.',
      );

    case 'pop':
      return TextCommandResult(
        'Stash not yet available on mobile. Use memory/ files instead.',
      );

    case 'list':
      return TextCommandResult(
        'Stash not yet available on mobile. Use memory/ files instead.',
      );

    case 'help':
    case '':
      return TextCommandResult(
        'Prompt Stash (desktop only)\n\n'
        'Commands:\n'
        '  /stash push <text>   Save a prompt for later\n'
        '  /stash pop           Restore the most recent prompt\n'
        '  /stash list          Show all stashed prompts\n'
        '  /stash drop <N>      Remove a specific entry\n'
        '  /stash clear         Clear all stashed prompts\n\n'
        'Note: Full stash is available on desktop. On mobile, use memory/ files.',
      );

    default:
      return TextCommandResult(
        'Stash not yet available on mobile. Use memory/ files instead.',
      );
  }
}

// --- /busy ---

Future<CommandResult> _handleBusy(String args, CommandContext ctx) async {
  final mode = args.trim().toLowerCase();
  if (mode.isEmpty || !['queue', 'steer', 'interrupt'].contains(mode)) {
    return TextCommandResult(
      'Busy Mode — controls what happens when you send a message while the agent is working\n\n'
      'Usage: /busy <mode>\n'
      '  queue     — queue the message for after the current turn (default)\n'
      '  steer     — inject as guidance after the next tool call\n'
      '  interrupt — cancel current turn and send immediately',
    );
  }
  return TextCommandResult(
    'Busy mode set to "$mode". When the agent is working, your input will be '
    '${mode == 'queue'
        ? 'queued for the next turn'
        : mode == 'steer'
        ? 'injected after the next tool call'
        : 'used to interrupt the current turn'}.',
  );
}

// --- /reasoning ---

Future<CommandResult> _handleReasoning(String args, CommandContext ctx) async {
  final mode = args.trim().toLowerCase();
  if (mode.isEmpty || mode == 'status') {
    return TextCommandResult(
      'Reasoning visibility — controls whether thinking/reasoning blocks are shown\n\n'
      'Usage: /reasoning <mode>\n'
      '  show    — display reasoning blocks in output\n'
      '  hide    — suppress reasoning blocks',
    );
  }
  if (mode == 'show' || mode == 'on') {
    return TextCommandResult(
      'Reasoning display enabled. Thinking blocks will be shown.',
    );
  }
  if (mode == 'hide' || mode == 'off') {
    return TextCommandResult(
      'Reasoning display disabled. Thinking blocks will be hidden.',
    );
  }
  return TextCommandResult('Usage: /reasoning [show|hide|status]');
}
