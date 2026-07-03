final _requiredSessionSections = <String>[
  '## Current State',
  '## Task Specification',
  '## Worklog',
];

final _frontmatterPattern = RegExp(r'^---\n[\s\S]*?\n---\n?');
final _placeholderLinePattern = RegExp(r'^\s*\*[^*\n]+\*\s*$');

class SessionMemoryQualityResult {
  final bool accepted;
  final String content;
  final List<String> issues;

  const SessionMemoryQualityResult({
    required this.accepted,
    required this.content,
    required this.issues,
  });
}

SessionMemoryQualityResult normalizeSessionMemoryContent(
  String content, {
  required String sessionId,
  required String extractedAt,
  String expires = 'session-end',
}) {
  final trimmed = content.trim();
  if (trimmed.isEmpty) {
    return const SessionMemoryQualityResult(
      accepted: false,
      content: '',
      issues: ['empty session memory'],
    );
  }

  final issues = <String>[];
  final expiresValue = _frontmatterValue(trimmed, 'expires');
  if (expiresValue != null && _isExpired(expiresValue)) {
    issues.add('session memory is expired');
  }

  final body = _stripFrontmatter(trimmed).trim();
  for (final section in _requiredSessionSections) {
    if (!body.contains(section)) {
      issues.add('missing required section: $section');
    }
  }

  final meaningfulText = _collectMeaningfulText(body);
  if (meaningfulText.length < 80) {
    issues.add('session memory contains too little non-placeholder content');
  }

  if (_isMostlyPlaceholder(body)) {
    issues.add('session memory is mostly placeholder template text');
  }

  if (issues.isNotEmpty) {
    return SessionMemoryQualityResult(
      accepted: false,
      content: trimmed,
      issues: issues,
    );
  }

  return SessionMemoryQualityResult(
    accepted: true,
    content:
        '${_sessionMemoryFrontmatter(sessionId: sessionId, extractedAt: extractedAt, expires: expires)}$body\n',
    issues: const [],
  );
}

bool isUsableSessionMemory(String content) {
  return normalizeSessionMemoryContent(
    content,
    sessionId: 'unknown',
    extractedAt: 'unknown',
  ).accepted;
}

String _stripFrontmatter(String content) {
  return content.replaceFirst(_frontmatterPattern, '');
}

String? _frontmatterValue(String content, String key) {
  final match = _frontmatterPattern.firstMatch(content);
  if (match == null) return null;
  String? line;
  for (final entry in match.group(0)!.split('\n')) {
    if (entry.trim().startsWith('$key:')) {
      line = entry;
      break;
    }
  }
  if (line == null) {
    return null;
  }
  return line.substring(line.indexOf(':') + 1).trim();
}

bool _isExpired(String value) {
  if (value == 'session-end' || value == 'unknown') return false;
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return false;
  return parsed.isBefore(DateTime.now().toUtc());
}

String _collectMeaningfulText(String body) {
  return body
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .where((line) => !line.startsWith('## '))
      .where((line) => !_placeholderLinePattern.hasMatch(line))
      .join('\n')
      .trim();
}

bool _isMostlyPlaceholder(String body) {
  final contentLines = body
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty && !line.startsWith('## '))
      .toList();
  if (contentLines.isEmpty) return true;
  final placeholderLines = contentLines
      .where((line) => _placeholderLinePattern.hasMatch(line))
      .length;
  return placeholderLines / contentLines.length >= 0.6;
}

String _sessionMemoryFrontmatter({
  required String sessionId,
  required String extractedAt,
  required String expires,
}) {
  return '''---
lifecycle: session
purpose: Session-level summary and recovery state used by compaction.
retention: Current working session.
write_target: sessions/<session-id>/session-memory.md
promotion_rule: Review before promoting stable decisions to durable memory or repeated workflow to a skill.
provenance: session-memory-extraction
source_session_id: ${_sanitizeFrontmatterValue(sessionId)}
extracted_at: ${_sanitizeFrontmatterValue(extractedAt)}
expires: ${_sanitizeFrontmatterValue(expires)}
---
''';
}

String _sanitizeFrontmatterValue(String value) {
  return value.replaceAll(RegExp(r'\r?\n'), ' ').trim();
}
