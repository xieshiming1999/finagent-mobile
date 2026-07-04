// ignore_for_file: unintended_html_in_doc_comment
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// Parsed skill data from a skill.md file.
class SkillData {
  final String name;
  final String? description;
  final String? whenToUse;
  final String? apiManifest; // relative path to API manifest endpoint
  final String content;
  final String dirPath;
  final String source; // 'bundle' or 'memory'

  const SkillData({
    required this.name,
    this.description,
    this.whenToUse,
    this.apiManifest,
    required this.content,
    required this.dirPath,
    required this.source,
  });
}

/// Parse YAML frontmatter from a skill.md file.
///
/// Expects format:
/// ```
/// ---
/// description: ...
/// when_to_use: ...
/// ---
/// <markdown content>
/// ```
///
/// Reference: claude-code-best/src/utils/frontmatterParser.ts
({Map<String, String> frontmatter, String body}) parseFrontmatter(
  String content,
) {
  final trimmed = content.trimLeft();
  if (!trimmed.startsWith('---')) {
    return (frontmatter: {}, body: content);
  }

  final endIdx = trimmed.indexOf('---', 3);
  if (endIdx == -1) {
    return (frontmatter: {}, body: content);
  }

  final yamlBlock = trimmed.substring(3, endIdx).trim();
  final body = trimmed.substring(endIdx + 3).trim();

  // Simple YAML key: value parser (no nested structures needed)
  final frontmatter = <String, String>{};
  for (final line in yamlBlock.split('\n')) {
    final colonIdx = line.indexOf(':');
    if (colonIdx == -1) continue;
    final key = line.substring(0, colonIdx).trim();
    final value = line.substring(colonIdx + 1).trim();
    // Strip surrounding quotes
    if ((value.startsWith('"') && value.endsWith('"')) ||
        (value.startsWith("'") && value.endsWith("'"))) {
      frontmatter[key] = value.substring(1, value.length - 1);
    } else {
      frontmatter[key] = value;
    }
  }

  return (frontmatter: frontmatter, body: body);
}

/// Substitute $ARGUMENTS placeholders in skill content.
///
/// - $ARGUMENTS → full args string
/// - $ARGUMENTS[0], $0 → first argument
/// - $ARGUMENTS[1], $1 → second argument, etc.
/// - If no placeholders found, appends "ARGUMENTS: <args>"
///
/// Reference: claude-code-best/src/utils/argumentSubstitution.ts
String substituteArguments(String content, String? args) {
  if (args == null || args.isEmpty) return content;

  var result = content;
  var hadPlaceholder = false;

  // Split args (simple space-split, no shell-quote parsing)
  final argList = args.split(RegExp(r'\s+'));

  // Replace $ARGUMENTS
  if (result.contains(r'$ARGUMENTS')) {
    result = result.replaceAll(r'$ARGUMENTS', args);
    hadPlaceholder = true;
  }

  // Replace indexed: $ARGUMENTS[N] and $N
  for (var i = 0; i < argList.length; i++) {
    final indexedPlaceholder = '\$ARGUMENTS[$i]';
    final shortPlaceholder = '\$$i';
    if (result.contains(indexedPlaceholder)) {
      result = result.replaceAll(indexedPlaceholder, argList[i]);
      hadPlaceholder = true;
    }
    if (result.contains(shortPlaceholder)) {
      result = result.replaceAll(shortPlaceholder, argList[i]);
      hadPlaceholder = true;
    }
  }

  // If no placeholders were found, append args
  if (!hadPlaceholder) {
    result = '$result\n\nARGUMENTS: $args';
  }

  return result;
}

/// Discover all available skills from bundle/ and memory/ directories.
///
/// Priority: memory/ overrides bundle/ for same-named skills.
List<SkillData> discoverSkills(String basePath) {
  final skills = <String, SkillData>{};

  // 1. Load from bundle/skills/ (lower priority)
  _loadSkillsFromDir(p.join(basePath, 'bundle', 'skills'), 'bundle', skills);

  // 2. Load from memory/skills/ (higher priority, overrides bundle)
  _loadSkillsFromDir(p.join(basePath, 'memory', 'skills'), 'memory', skills);

  return skills.values.toList();
}

void _loadSkillsFromDir(
  String skillsDir,
  String source,
  Map<String, SkillData> skills,
) {
  final dir = Directory(skillsDir);
  if (!dir.existsSync()) return;

  for (final entity in dir.listSync()) {
    if (entity is! Directory) continue;

    final name = p.basename(entity.path);
    if (name.startsWith('.')) continue;

    // Look for skill.md in the directory
    final skillFile = File(p.join(entity.path, 'skill.md'));
    if (!skillFile.existsSync()) continue;

    final raw = skillFile.readAsStringSync();
    final parsed = parseFrontmatter(raw);

    skills[name] = SkillData(
      name: name,
      description: parsed.frontmatter['description'],
      whenToUse: parsed.frontmatter['when_to_use'],
      apiManifest: parsed.frontmatter['api_manifest'],
      content: parsed.body,
      dirPath: entity.path,
      source: source,
    );
  }
}

/// Format skills listing for the system prompt.
///
/// Returns a string like:
/// ```
/// - trading: 股票交易操作指南 (bundle)
/// - analysis: 技术分析方法 (bundle)
/// - my_strategy: 自定义策略 (memory)
/// ```
String formatSkillsListing(List<SkillData> skills) {
  if (skills.isEmpty) return '';

  // Cap each entry to ~250 chars to keep discovery budget tight.
  // Front-load trigger language — tails get truncated.
  const maxEntryChars = 250;

  final lines = skills.map((s) {
    final desc = s.description ?? 'No description';
    final whenToUse = s.whenToUse != null ? ' - ${s.whenToUse}' : '';
    var entry = '- ${s.name}: $desc$whenToUse (${s.source})';
    if (entry.length > maxEntryChars) {
      entry = '${entry.substring(0, maxEntryChars - 3)}...';
    }
    return entry;
  });

  return lines.join('\n');
}

/// Fetch an API manifest from the service and format as markdown.
/// Returns null if the fetch fails.
Future<String?> fetchAndFormatManifest(
  String serviceBaseUrl,
  String manifestPath,
) async {
  try {
    final url = '$serviceBaseUrl$manifestPath';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return formatManifest(json);
  } catch (_) {
    return null;
  }
}

/// Format a manifest JSON into readable markdown for the LLM.
String formatManifest(Map<String, dynamic> manifest) {
  final apis = manifest['apis'] as List? ?? [];
  if (apis.isEmpty) return '(No APIs available)';

  final buf = StringBuffer();
  buf.writeln('使用 ServiceCall tool 调用以下 API。\n');

  for (final api in apis) {
    final name = api['name'] ?? 'unknown';
    final desc = api['description'] ?? '';
    final method = api['method'] ?? 'GET';
    final path = api['path'] ?? '';
    final params = api['params'] as List? ?? [];

    buf.writeln('### $name — $desc');
    buf.writeln('- 方法: $method');
    buf.writeln('- 路径: $path');

    if (params.isNotEmpty) {
      buf.writeln('- 参数:');
      for (final p in params) {
        final pName = p['name'] ?? '';
        final pType = p['type'] ?? 'string';
        final required = p['required'] == true ? '必填' : '可选';
        final pDesc = p['description'] ?? '';
        final defaultVal = p['default'] != null ? ', 默认${p['default']}' : '';
        final enumVals = p['enum'] != null
            ? ', 可选值: ${(p['enum'] as List).join('/')}'
            : '';
        buf.writeln(
          '  - $pName ($pType, $required$defaultVal$enumVals): $pDesc',
        );
      }
    }
    buf.writeln();
  }

  return buf.toString();
}
