import 'dart:io';

import 'package:path/path.dart' as p;

import 'log.dart';

// Reference: opencode src/session/instruction.ts

const _instructionFileNames = ['AGENTS.md', 'CLAUDE.md', 'CONTEXT.md'];

/// Walk up from [filePath]'s directory toward [basePath], collecting
/// instruction files (AGENTS.md, CLAUDE.md, CONTEXT.md) found along the way.
/// Returns concatenated content, closest directory first.
/// Stops at basePath (inclusive). Never goes above basePath.
String? loadHierarchicalInstructions(String filePath, String basePath) {
  final resolvedBase = p.canonicalize(basePath);
  var dir = p.canonicalize(p.dirname(filePath));

  // Safety: don't walk above basePath
  if (!dir.startsWith(resolvedBase)) return null;

  final sections = <String>[];

  while (true) {
    for (final name in _instructionFileNames) {
      final file = File(p.join(dir, name));
      if (file.existsSync()) {
        final content = file.readAsStringSync().trim();
        if (content.isNotEmpty) {
          final relative = p.relative(file.path, from: resolvedBase);
          sections.add('# Instructions from $relative\n$content');
        }
      }
    }

    // Stop at basePath
    if (dir == resolvedBase) break;

    // Walk up
    final parent = p.dirname(dir);
    if (parent == dir) break; // filesystem root
    dir = parent;
  }

  if (sections.isEmpty) return null;

  // Reverse: outermost (basePath) first, innermost (file dir) last (overrides)
  return sections.reversed.join('\n\n');
}

/// Attach hierarchical instructions to a file read result if found.
/// Returns the instruction text to append, or null.
String? getInstructionsForFile(String filePath, String basePath) {
  final instructions = loadHierarchicalInstructions(filePath, basePath);
  if (instructions == null) return null;

  log('Instruction', 'Found hierarchical instructions for $filePath');
  return '\n\n<nearby-instructions>\n$instructions\n</nearby-instructions>';
}
