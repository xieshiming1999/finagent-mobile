import 'dart:convert';
import 'dart:io';

import 'finance_output_standard.dart';
import 'memory_lifecycle.dart';
import 'strategy.dart';
import 'tool.dart';
import 'tools/skill_tool/skill_utils.dart';

/// Assembles the system prompt for the Agent.
///
/// All prompt content comes from files — code only handles assembly logic.
///
/// Files loaded (in order):
///   1. bundle/AGENTS.md — project identity, rules, file system, behavior
///   2. Available Tools (auto-generated from registered tools)
///   3. Skills Index (lazy — only names, loaded on demand via SkillTool)
///   4. memory/MEMORY.md — current memory index
///   5. memory/[role]/soul.md — agent's personal soul (editable)
///   6. Environment (auto-generated: platform, date)
///
/// Falls back to built-in defaults if files don't exist yet.
class PromptBuilder {
  /// Optional base prompt fallback (used when AGENTS.md doesn't exist yet).
  final String basePrompt;

  /// Optional feature prompt fallback (used when AGENTS.md doesn't exist yet).
  final String? featurePrompt;
  final String basePath;

  /// Agent role identifier — determines which soul file to load.
  /// e.g. 'chat' loads memory/chat/soul.md, 'event' loads memory/event/soul.md.
  final String? agentRole;

  /// Optional provider hint for provider-specific prompt sections.
  String? providerHint;

  PromptBuilder({
    this.basePrompt = '',
    required this.basePath,
    this.featurePrompt,
    this.agentRole,
    this.providerHint,
  });

  /// Build the full system prompt.
  String build({required List<Tool> tools}) {
    final sections = <String>[];

    // 1. bundle/AGENTS.md — shared project identity, rules, file system, behavior
    final agentsMd =
        _loadFile('bundle/AGENTS.md') ?? _loadFile('bundle/CLAUDE.md');
    if (agentsMd != null) {
      sections.add(
        '# Project Instructions (from bundle/AGENTS.md — read-only)\n\n$agentsMd',
      );
    } else if (featurePrompt != null && featurePrompt!.isNotEmpty) {
      sections.add(featurePrompt!);
    } else if (basePrompt.isNotEmpty) {
      sections.add(basePrompt);
    } else {
      sections.add(_fallbackBasePrompt);
    }

    // 2. bundle/<role>/AGENTS.md — role-specific instructions
    if (agentRole != null && agentRole!.isNotEmpty) {
      final roleMd = _loadFile('bundle/$agentRole/AGENTS.md');
      if (roleMd != null) {
        sections.add(
          '# Role Instructions (from bundle/$agentRole/AGENTS.md — read-only)\n\n$roleMd',
        );
      }
    }

    // 3. Available Tools (auto-generated)
    if (tools.isNotEmpty) {
      final sorted = tools.toList()..sort((a, b) => a.name.compareTo(b.name));
      final toolDescriptions = sorted
          .map(
            (tool) =>
                '- ${tool.name} '
                '[${_toolCapabilityFlags(summarizeToolCapability(tool)).join(', ')}]: '
                '${tool.description}',
          )
          .join('\n');
      sections.add('# Available Tools\n$toolDescriptions');
    }

    // 4. Skills Index
    final skillsListing = _buildSkillsIndex();
    if (skillsListing != null) {
      sections.add(skillsListing);
    }

    // 5. MEMORY.md content (current memory index)
    sections.add(memoryLifecyclePromptGuidance);
    sections.add(financeOutputStandardPromptGuidance);
    sections.add(_loadMemoryIndex());

    // 5a. Active Wind daily quota state, if Wind already reported exhaustion.
    final windQuotaStatus = _loadWindQuotaStatus(
      hasWindMcp: tools.any((tool) => tool.name == 'WindMcp'),
    );
    if (windQuotaStatus != null) {
      sections.add(windQuotaStatus);
    }

    // 5b. Agent-specific config (editable by this agent)
    final agentConfig = _loadAgentConfig();
    if (agentConfig != null) {
      sections.add(agentConfig);
    }

    // 5c. AI analysis reflections (cross-ticker lessons from past predictions)
    final reflections = _loadFile('memory/ai_reflections.md');
    if (reflections != null) {
      sections.add(
        '# Past Analysis Reflections (from memory/ai_reflections.md — editable)\n$reflections',
      );
    }

    // 5d. Active strategies (agent's internal decision-making tools)
    final strategySummary = _loadStrategySummary();
    if (strategySummary != null) {
      sections.add(strategySummary);
    }

    // 6. Environment (auto-generated)
    sections.add(_buildEnvironment());

    // 7. Provider-specific prompt (optional)
    final providerPrompt = _loadProviderPrompt();
    if (providerPrompt != null) {
      sections.add(providerPrompt);
    }

    return sections.join('\n\n');
  }

  List<String> _toolCapabilityFlags(ToolCapabilitySummary capability) {
    return [
      capability.permission,
      if (capability.requiresUserInteraction) 'requires-user-input',
      capability.canParallel ? 'parallel-ok' : 'serial',
      if (capability.actionValues.isNotEmpty)
        'actions=${capability.actionValues.join('|')}',
    ];
  }

  /// Load a file relative to basePath, return trimmed content or null.
  String? _loadFile(String relativePath) {
    final file = File('$basePath/$relativePath');
    if (!file.existsSync()) return null;
    final content = file.readAsStringSync().trim();
    return content.isEmpty ? null : content;
  }

  /// Load strategy summary from persisted strategies.json.
  String? _loadStrategySummary() {
    final store = StrategyStore();
    store.load(basePath);
    if (store.strategies.isEmpty) return null;

    final buf = StringBuffer(
      '# Investment Strategies (from strategies.json — editable)\n\n',
    );
    buf.writeln(
      'Available strategies for DataProcess(action: "strategy_execute"):',
    );
    for (final s in store.strategies) {
      final wr = s.timesUsed >= 3
          ? ' 胜率${(s.winRate * 100).toStringAsFixed(0)}%'
          : '';
      buf.writeln('- ${s.name} (${s.id}): ${s.description}$wr');
    }
    buf.writeln(
      '\nUse strategy_execute to run a strategy with full reasoning chain.',
    );
    return buf.toString();
  }

  /// Load and format skills listing for the system prompt.
  String? _buildSkillsIndex() {
    final skills = discoverSkills(basePath);
    if (skills.isEmpty) return null;

    final listing = formatSkillsListing(skills);
    return '# Available Skills\n$listing\n'
        'Use the Skill tool to load skill details when needed.\n'
        'Use Skill(skill: "create", content: "...") to save reusable workflows as new skills.\n'
        'Before creating, check existing skills to avoid duplicates — merge if similar.';
  }

  /// Load memory/MEMORY.md index.
  String _loadMemoryIndex() {
    final file = File('$basePath/memory/MEMORY.md');
    if (!file.existsSync()) {
      return '# Memory Index (from memory/MEMORY.md — editable)\n(No memories saved yet.)';
    }

    final content = file.readAsStringSync().trim();
    if (content.isEmpty) {
      return '# Memory Index (from memory/MEMORY.md — editable)\n(No memories saved yet.)';
    }

    return '# Memory Index (from memory/MEMORY.md — editable)\n$content';
  }

  String? _loadWindQuotaStatus({required bool hasWindMcp}) {
    if (!hasWindMcp) return null;
    final file = File('$basePath/memory/wind_usage.json');
    if (!file.existsSync()) return _windQuotaAvailableStatus('+08:00');
    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final offset = _normalizeUtcOffset(data['resetUtcOffset'] as String?);
      final today = _dateForOffset(offset);
      if (data['exhausted'] != true || data['date'] != today) {
        return _windQuotaAvailableStatus(offset);
      }

      final code = data['exhaustedCode'] as String? ?? 'RATE_LIMIT_DAILY';
      final message =
          data['exhaustedMessage'] as String? ??
          'Wind reported daily quota exhaustion or insufficient balance.';
      final nextDate = _nextDate(today);
      final retryGuidance = code == 'BALANCE_INSUFFICIENT'
          ? 'Do not call WindMcp again until the user tops up the Wind account or configures a different key.'
          : 'Do not call WindMcp again until quota date $nextDate starts at reset offset $offset, unless the user configures a different key.';
      return '# Wind AIFinMarket Quota Status\n'
          'WindMcp is unavailable for quota date $today (reset offset $offset).\n'
          'Stored error: $code. $message\n'
          '$retryGuidance\n'
          'Use non-Wind sources such as cache, EastMoney, TDX, Yahoo, or DataStore for this turn.';
    } catch (_) {
      return _windQuotaAvailableStatus('+08:00');
    }
  }

  String _windQuotaAvailableStatus(String offset) {
    return '# Wind AIFinMarket Quota Status\n'
        'WindMcp is available to try for the current Wind quota day, if WIND_API_KEY is configured.\n'
        'Use WindMcp for Wind-covered data before spending monthly Brave/Tavily search quota.\n'
        'Ignore previous-session Wind daily quota errors from older quota dates.';
  }

  /// Load agent-specific soul from memory/[agentRole]/soul.md.
  String? _loadAgentConfig() {
    if (agentRole == null || agentRole!.isEmpty) return null;
    final role = agentRole!;
    final path = 'memory/$role/soul.md';
    final content = _loadFile(path);
    if (content == null) {
      return '# Your Soul (from $path — editable)\n'
          '(Not configured yet. You can create this file to customize your behavior, '
          'record reflections, and reference other memory files. Keep it concise.)';
    }
    return '# Your Soul (from $path — editable)\n$content';
  }

  String _buildEnvironment() {
    final now = DateTime.now();
    final date = '${now.year}-${_pad(now.month)}-${_pad(now.day)}';
    final platform = Platform.operatingSystem;

    return '# Environment\n'
        'Platform: $platform\n'
        'Date: $date\n'
        'All file paths are relative to: $basePath';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');

  String _normalizeUtcOffset(String? raw) {
    final text = raw == null || raw.trim().isEmpty ? '+08:00' : raw.trim();
    final match = RegExp(r'^([+-])(\d{1,2})(?::?(\d{2}))?$').firstMatch(text);
    if (match == null) return '+08:00';
    final hours = int.tryParse(match.group(2) ?? '');
    final minutes = int.tryParse(match.group(3) ?? '0');
    if (hours == null || minutes == null || hours > 14 || minutes > 59) {
      return '+08:00';
    }
    return '${match.group(1)}${_pad(hours)}:${_pad(minutes)}';
  }

  String _dateForOffset(String normalizedOffset) {
    final sign = normalizedOffset.startsWith('-') ? -1 : 1;
    final hours = int.parse(normalizedOffset.substring(1, 3));
    final minutes = int.parse(normalizedOffset.substring(4, 6));
    final offset = Duration(minutes: sign * (hours * 60 + minutes));
    return DateTime.now()
        .toUtc()
        .add(offset)
        .toIso8601String()
        .substring(0, 10);
  }

  String _nextDate(String yyyyMmDd) {
    final date = DateTime.parse(yyyyMmDd).add(const Duration(days: 1));
    return '${date.year}-${_pad(date.month)}-${_pad(date.day)}';
  }

  /// Load provider-specific prompt from bundle/prompts/[providerHint].md.
  String? _loadProviderPrompt() {
    if (providerHint == null || providerHint!.isEmpty) return null;
    final provider = providerHint!.toLowerCase();
    final path = 'bundle/prompts/$provider.md';
    final content = _loadFile(path);
    if (content == null) return null;
    return '# Provider Prompt (from $path — read-only)\n$content';
  }

  /// Minimal fallback when BASE_PROMPT.md doesn't exist yet.
  static const _fallbackBasePrompt = 'You are a helpful AI assistant. 请用中文交流。';
}
