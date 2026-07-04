import 'dart:io';
import 'package:path/path.dart' as p;

import '../../message.dart';
import '../../security_scan.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;
import 'skill_utils.dart';

/// Loads, creates, updates, and deletes skills.
///
/// Skills are .md files in bundle/skills/ and memory/skills/ directories.
/// memory/ skills override bundle/ skills with the same name.
/// create/update/delete only operate on memory/skills/ (never touch bundle/).
///
/// Reference: claude-code-best SkillTool + Hermes skill_manager_tool
class SkillTool extends Tool {
  /// Tracks which skills were loaded this session (for skill improvement).
  static final invokedSkills = <String>{};

  @override
  String get name => 'Skill';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'skill': {
        'type': 'string',
        'description':
            'Skill name to load, OR action: "create", "update", "delete".',
      },
      'args': {
        'type': 'string',
        'description':
            'Arguments when loading a skill, or skill name for update/delete.',
      },
      'content': {
        'type': 'string',
        'description':
            'Full skill.md content (for create/update). Must include frontmatter with name and description.',
      },
    },
    'required': ['skill'],
  };

  @override
  bool get isReadOnly => false;

  @override
  bool needsPermissions(Map<String, dynamic> input) {
    final skill = (input['skill'] as String?)?.trim();
    // Write actions need permissions, reads don't
    return skill == 'create' || skill == 'update' || skill == 'delete';
  }

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final skill = (input['skill'] as String?)?.trim();
    if (skill == null || skill.isEmpty) return 'skill is required.';

    switch (skill) {
      case 'create':
        final content = input['content'] as String?;
        if (content == null || content.isEmpty) {
          return 'create requires "content" with full skill.md including frontmatter.';
        }
        final parsed = parseFrontmatter(content);
        final name = parsed.frontmatter['name'];
        if (name == null || name.isEmpty) {
          return 'skill.md frontmatter must include "name" field.';
        }
        final nameError = _validateSkillName(name);
        if (nameError != null) return nameError;

      case 'update':
        final args = input['args'] as String?;
        final content = input['content'] as String?;
        if (args == null || args.isEmpty) {
          return 'update requires "args" with the skill name.';
        }
        if (content == null || content.isEmpty) {
          return 'update requires "content" with the updated skill.md.';
        }

      case 'delete':
        final args = input['args'] as String?;
        if (args == null || args.isEmpty) {
          return 'delete requires "args" with the skill name.';
        }

      default:
        // Load mode — check if skill exists
        final name = skill.startsWith('/') ? skill.substring(1) : skill;
        final skills = discoverSkills(context.basePath);
        if (!skills.any((s) => s.name == name)) {
          final available = skills.map((s) => s.name).join(', ');
          return 'Skill "$name" not found. '
              'Available: ${available.isEmpty ? "(none)" : available}';
        }
    }
    return null;
  }

  @override
  Future<ToolResult> call(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final skill = (input['skill'] as String).trim();

    return switch (skill) {
      'create' => _createSkill(toolUseId, input, context),
      'update' => _updateSkill(toolUseId, input, context),
      'delete' => _deleteSkill(toolUseId, input, context),
      _ => _loadSkill(toolUseId, skill, input, context),
    };
  }

  // ─── Load (existing) ───

  Future<ToolResult> _loadSkill(
    String toolUseId,
    String skillName,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final name = skillName.startsWith('/') ? skillName.substring(1) : skillName;
    final args = input['args'] as String?;

    final skills = discoverSkills(context.basePath);
    final skill = skills.firstWhere((s) => s.name == name);

    var content = substituteArguments(skill.content, args);

    // Track invocation for skill improvement
    invokedSkills.add(name);

    // Fetch API manifest if declared
    if (skill.apiManifest != null && skill.apiManifest!.isNotEmpty) {
      final manifest = await fetchAndFormatManifest(
        context.serviceBaseUrl,
        skill.apiManifest!,
      );
      content += manifest != null
          ? '\n\n## 可用 API\n\n$manifest'
          : '\n\n## 可用 API\n\n(API manifest 加载失败)';
    }

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Skill "$name" loaded (${skill.source}).\n\n'
          '--- Skill Instructions ---\n$content\n--- End Skill ---',
    );
  }

  // ─── Create ───

  Future<ToolResult> _createSkill(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final content = input['content'] as String;
    final parsed = parseFrontmatter(content);
    final name = parsed.frontmatter['name']!;

    // Content size check
    if (content.length > 50000) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Skill content must be ≤50KB.',
        isError: true,
      );
    }

    // Security scan
    final risk = SecurityScan.describeRisk(content);
    if (risk != null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Skill rejected: $risk',
        isError: true,
      );
    }

    // Check for existing skill in memory/
    final skillDir = p.join(context.memoryDir, 'skills', name);
    final skillFile = File(p.join(skillDir, 'skill.md'));
    if (skillFile.existsSync()) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Skill "$name" already exists. Use "update" to modify it.',
        isError: true,
      );
    }

    // Write
    Directory(skillDir).createSync(recursive: true);
    skillFile.writeAsStringSync(content);

    final desc = parsed.frontmatter['description'] ?? '(no description)';
    return ToolResult(
      toolUseId: toolUseId,
      content:
          'Skill "$name" created at memory/skills/$name/skill.md\n'
          'Description: $desc\n'
          'It will appear in the skills index on next conversation.',
    );
  }

  // ─── Update ───

  Future<ToolResult> _updateSkill(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final name = (input['args'] as String).trim();
    final content = input['content'] as String;

    if (content.length > 50000) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Skill content must be ≤50KB.',
        isError: true,
      );
    }

    final risk = SecurityScan.describeRisk(content);
    if (risk != null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Skill rejected: $risk',
        isError: true,
      );
    }

    final memorySkillFile = File(
      p.join(context.memoryDir, 'skills', name, 'skill.md'),
    );

    if (memorySkillFile.existsSync()) {
      // Update existing memory skill
      memorySkillFile.writeAsStringSync(content);
      final sizeKb = (content.length / 1024).toStringAsFixed(1);
      return ToolResult(
        toolUseId: toolUseId,
        content:
            'Skill "$name" updated (${sizeKb}KB, ${content.split('\n').length} lines). '
            'Path: memory/skills/$name/skill.md',
      );
    }

    // Check if it's a bundle skill — create memory override
    final bundleSkillFile = File(
      p.join(context.bundleDir, 'skills', name, 'skill.md'),
    );
    if (bundleSkillFile.existsSync()) {
      Directory(memorySkillFile.parent.path).createSync(recursive: true);
      memorySkillFile.writeAsStringSync(content);
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Created memory override for bundle skill "$name".',
      );
    }

    return ToolResult(
      toolUseId: toolUseId,
      content: 'Skill "$name" not found.',
      isError: true,
    );
  }

  // ─── Delete ───

  Future<ToolResult> _deleteSkill(
    String toolUseId,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final name = (input['args'] as String).trim();
    final skillDir = Directory(p.join(context.memoryDir, 'skills', name));

    if (!skillDir.existsSync()) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'Skill "$name" not found in memory/skills/.',
        isError: true,
      );
    }

    skillDir.deleteSync(recursive: true);
    return ToolResult(
      toolUseId: toolUseId,
      content: 'Skill "$name" deleted from memory/skills/.',
    );
  }

  // ─── Helpers ───

  static String? _validateSkillName(String name) {
    if (!RegExp(r'^[a-z0-9][a-z0-9\-]*$').hasMatch(name)) {
      return 'Invalid skill name "$name". '
          'Use lowercase letters, numbers, and hyphens only.';
    }
    if (name.length > 64) return 'Skill name must be ≤64 characters.';
    return null;
  }
}
