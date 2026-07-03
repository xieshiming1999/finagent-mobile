import 'dart:io';

import 'package:path/path.dart' as p;

import 'log.dart';
import 'tools/skill_tool/skill_utils.dart';

// Reference: opencode .opencode/command/*.md

/// A file-defined slash command loaded from bundle/commands/ or memory/commands/.
class FileCommand {
  final String name;
  final String description;
  final String promptTemplate;
  final String? agent; // optional agent override
  final String source; // 'bundle' or 'memory'

  const FileCommand({
    required this.name,
    required this.description,
    required this.promptTemplate,
    this.agent,
    required this.source,
  });
}

/// Discover file-based commands from bundle/commands/ and memory/commands/.
/// memory/ commands override bundle/ commands with the same name.
List<FileCommand> discoverCommands(String basePath) {
  final commands = <String, FileCommand>{};

  // Load bundle commands first
  _loadCommandsFromDir(
    p.join(basePath, 'bundle', 'commands'),
    'bundle',
    commands,
  );

  // Memory commands override bundle
  _loadCommandsFromDir(
    p.join(basePath, 'memory', 'commands'),
    'memory',
    commands,
  );

  return commands.values.toList()..sort((a, b) => a.name.compareTo(b.name));
}

void _loadCommandsFromDir(
  String dirPath,
  String source,
  Map<String, FileCommand> commands,
) {
  final dir = Directory(dirPath);
  if (!dir.existsSync()) return;

  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith('.md')) continue;

    try {
      final content = entity.readAsStringSync();
      final parsed = parseFrontmatter(content);
      final name =
          parsed.frontmatter['name'] ?? p.basenameWithoutExtension(entity.path);
      final description = parsed.frontmatter['description'] ?? '(file command)';
      final agent = parsed.frontmatter['agent'];

      commands[name] = FileCommand(
        name: name,
        description: description,
        promptTemplate: parsed.body,
        agent: agent,
        source: source,
      );
    } catch (e) {
      log('CommandLoader', 'Failed to load ${entity.path}: $e');
    }
  }
}

/// Expand a command template with user arguments.
/// Replaces $ARGUMENTS with the full args string, $1/$2/etc with positional args.
String expandCommandTemplate(String template, String args) {
  var result = template.replaceAll('\$ARGUMENTS', args);

  // Positional arguments
  final parts = args.split(RegExp(r'\s+'));
  for (var i = 0; i < parts.length && i < 9; i++) {
    result = result.replaceAll('\$${i + 1}', parts[i]);
  }

  return result;
}
