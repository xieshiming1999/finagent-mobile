import 'dart:io';
import 'dart:convert';

import 'package:path/path.dart' as p;

import 'llm_client.dart';
import 'log.dart';
import 'message.dart';
import 'post_turn_hooks.dart';
import 'tools/skill_tool/skill_tool.dart';

// Reference: claude-code-best/src/utils/hooks/skillImprovement.ts

const _turnBatchSize = 20;

/// Mutable state for skill improvement, scoped to agent lifetime.
class SkillImprovementState {
  int turnsSinceLastCheck = 0;
  bool inProgress = false;
}

/// Post-turn hook: every [_turnBatchSize] turns, analyze invoked skills
/// against recent conversation and auto-improve if needed.
Future<void> hookSkillImprovement(
  PostTurnContext ctx,
  SkillImprovementState state,
) async {
  if (state.inProgress) return;

  state.turnsSinceLastCheck++;
  if (state.turnsSinceLastCheck < _turnBatchSize) return;
  state.turnsSinceLastCheck = 0;

  // Only improve skills that were actually invoked
  final invoked = Set<String>.from(SkillTool.invokedSkills);
  if (invoked.isEmpty) {
    log('SkillImprovement', 'Skipped: no skills invoked');
    return;
  }

  // Find skill files that exist in memory/ (writable)
  final candidates = <String, String>{}; // name -> file path
  for (final name in invoked) {
    final memoryPath = p.join(
      ctx.toolContext.memoryDir,
      'skills',
      name,
      'skill.md',
    );
    final bundlePath = p.join(
      ctx.toolContext.bundleDir,
      'skills',
      name,
      'skill.md',
    );
    if (File(memoryPath).existsSync()) {
      candidates[name] = memoryPath;
    } else if (File(bundlePath).existsSync()) {
      // Bundle skill — would create memory override
      candidates[name] = bundlePath;
    }
  }

  if (candidates.isEmpty) {
    log('SkillImprovement', 'Skipped: no writable skill candidates');
    return;
  }

  state.inProgress = true;
  log(
    'SkillImprovement',
    'Analyzing ${candidates.length} skills: ${candidates.keys.join(', ')}',
  );

  try {
    await _analyzeAndImprove(ctx, candidates);
  } catch (e) {
    log('SkillImprovement', 'Error: $e');
  } finally {
    state.inProgress = false;
  }
}

Future<void> _analyzeAndImprove(
  PostTurnContext ctx,
  Map<String, String> candidates,
) async {
  for (final entry in candidates.entries) {
    final skillName = entry.key;
    final skillPath = entry.value;
    final skillContent = File(skillPath).readAsStringSync();

    // Build a compact view of recent messages (last N turns only)
    final recentMessages = ctx.messages.length > 20
        ? ctx.messages.sublist(ctx.messages.length - 20)
        : ctx.messages;

    final conversationSummary = recentMessages
        .map((m) {
          final role = m.role.name.toUpperCase();
          if (m.toolUses != null && m.toolUses!.isNotEmpty) {
            final tools = m.toolUses!.map((t) => t.name).join(', ');
            return '$role: [tools: $tools] ${m.content.length > 200 ? '${m.content.substring(0, 200)}...' : m.content}';
          }
          if (m.toolResult != null) {
            return '$role: [result: ${m.toolResult!.content.length > 100 ? '${m.toolResult!.content.substring(0, 100)}...' : m.toolResult!.content}]';
          }
          return '$role: ${m.content.length > 300 ? '${m.content.substring(0, 300)}...' : m.content}';
        })
        .join('\n');

    final analysisPrompt =
        '''Analyze this skill definition against the recent conversation.
Identify concrete improvements: user corrections, missing steps, better defaults, or outdated instructions.

## Current skill: $skillName

$skillContent

## Recent conversation

$conversationSummary

## Instructions

If the skill needs improvement, output the complete updated skill.md content (including frontmatter).
If no changes needed, respond with exactly: NO_CHANGES_NEEDED

Only make changes that are clearly supported by the conversation evidence.
Do not add speculative improvements. Preserve the overall structure and frontmatter format.

Finance skill guardrails:
- Record stable workflow guidance only; never convert one market observation into current investment advice.
- Keep provider/source freshness, quota limits, and local-first reuse explicit.
- If the improvement depends on a market/API condition, phrase it as a verification step, not as a permanent fact.''';

    final subClient = ctx.client.clone();
    final buffer = StringBuffer();
    await for (final event in subClient.sendMessage(
      messages: [
        Message(
          role: Role.user,
          content: analysisPrompt,
          timestamp: DateTime.now(),
        ),
      ],
      tools: [],
      systemPrompt:
          'You are a skill improvement agent. Analyze skill definitions and suggest concrete improvements based on conversation evidence. Output only the updated skill content or NO_CHANGES_NEEDED.',
      maxOutputTokens: 4096,
    )) {
      if (event is SSETextDelta) buffer.write(event.text);
    }

    final result = buffer.toString().trim();
    if (result.isEmpty || result.contains('NO_CHANGES_NEEDED')) {
      log('SkillImprovement', '$skillName: no changes needed');
      continue;
    }

    // Validate the output has frontmatter
    if (!result.contains('---')) {
      log(
        'SkillImprovement',
        '$skillName: invalid output (no frontmatter), skipping',
      );
      continue;
    }
    final validationError = validateSkillImprovementContent(
      skillName: skillName,
      content: result,
    );
    if (validationError != null) {
      log(
        'SkillImprovement',
        '$skillName: unsafe output, skipping: $validationError',
      );
      continue;
    }

    // Write to memory/skills/ (create override if bundle skill)
    final memoryPath = p.join(
      ctx.toolContext.memoryDir,
      'skills',
      skillName,
      'skill.md',
    );
    Directory(p.dirname(memoryPath)).createSync(recursive: true);
    File(memoryPath).writeAsStringSync(result);
    maybeWriteSkillGovernanceRecord(
      skillName: skillName,
      sourceSkillPath: skillPath,
      memorySkillPath: memoryPath,
      resultSummary: result,
    );
    log('SkillImprovement', '$skillName: updated at $memoryPath');
  }
}

bool maybeWriteSkillGovernanceRecord({
  required String skillName,
  required String sourceSkillPath,
  required String memorySkillPath,
  required String resultSummary,
  DateTime? now,
}) {
  if (resultSummary.trim().isEmpty ||
      resultSummary.contains('NO_CHANGES_NEEDED') ||
      !File(memorySkillPath).existsSync()) {
    return false;
  }
  final path = p.join(p.dirname(memorySkillPath), 'governance.json');
  final record = {
    'version': 1,
    'lifecycle': 'procedural',
    'skillName': skillName,
    'updatedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
    'sourceSkillPath': sourceSkillPath,
    'memorySkillPath': memorySkillPath,
    'reason': _truncate(resultSummary.trim(), 500),
    'promotion': {
      'source': 'skill_improvement',
      'evidenceRequired': true,
      'stableWorkflowOnly': true,
    },
    'financeFreshness': {
      'marketObservationPolicy': 'verification-step-only',
      'requiresSourceAndAsOf': true,
      'forbidsCurrentAdviceClaims': true,
    },
    'guardrails': [
      'Conversation evidence required.',
      'Finance market observations must remain verification steps, not permanent current facts.',
      'Provider/source freshness and local-first reuse must stay explicit.',
    ],
    'rollback': {
      'deleteMemoryOverride': memorySkillPath,
      'sourceOfTruth': sourceSkillPath,
    },
  };
  Directory(p.dirname(path)).createSync(recursive: true);
  File(
    path,
  ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(record));
  return true;
}

String? validateSkillImprovementContent({
  required String skillName,
  required String content,
}) {
  final trimmed = content.trim();
  if (!trimmed.contains('---')) {
    return 'skill content must include frontmatter';
  }
  if (!_isFinanceSkillName(skillName)) return null;
  final blocked = <RegExp>[
    RegExp(r'\b(buy|sell)\s+(now|today)\b', caseSensitive: false),
    RegExp(r'\bcurrent\s+(price|nav|valuation)\s+is\b', caseSensitive: false),
    RegExp(
      r'\b(guaranteed|certain)\s+(return|profit|rise|gain)\b',
      caseSensitive: false,
    ),
    RegExp(r'\bwill\s+(rise|fall|gain|drop)\b', caseSensitive: false),
  ];
  return blocked.any((pattern) => pattern.hasMatch(trimmed))
      ? 'finance skills must phrase market conditions as verification steps, not permanent current advice'
      : null;
}

bool _isFinanceSkillName(String skillName) => RegExp(
  r'(fin|stock|fund|market|trade|trading|quote|kline|wind|tushare|eastmoney|yfinance)',
  caseSensitive: false,
).hasMatch(skillName);

String _truncate(String value, int max) =>
    value.length > max ? '${value.substring(0, max)}...' : value;
