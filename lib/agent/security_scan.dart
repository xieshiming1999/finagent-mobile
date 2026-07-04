/// Security scanning for skill and memory content.
///
/// Detects prompt injection patterns that could compromise the Agent.
/// Skill writes are rejected, memory writes show a warning.
class SecurityScan {
  static final _injectionPatterns = [
    (RegExp(r'<system\b', caseSensitive: false), 'system tag injection'),
    (RegExp(r'</system>', caseSensitive: false), 'system tag injection'),
    (
      RegExp(
        r'ignore\s+(previous|above|all|prior)\s+instructions',
        caseSensitive: false,
      ),
      'instruction override',
    ),
    (RegExp(r'you\s+are\s+now\s+', caseSensitive: false), 'role hijacking'),
    (
      RegExp(r'new\s+instructions?\s*:', caseSensitive: false),
      'instruction injection',
    ),
    (
      RegExp(
        r'forget\s+(everything|all|your\s+instructions)',
        caseSensitive: false,
      ),
      'memory wipe',
    ),
    (
      RegExp(r'override\s+(system|instructions|rules)', caseSensitive: false),
      'rule override',
    ),
    (RegExp(r'exfiltrate', caseSensitive: false), 'data exfiltration'),
  ];

  /// Check if content has prompt injection risk.
  static bool hasInjectionRisk(String content) {
    return _injectionPatterns.any((p) => p.$1.hasMatch(content));
  }

  /// Describe the first matched risk pattern. Returns null if clean.
  static String? describeRisk(String content) {
    for (final (pattern, label) in _injectionPatterns) {
      final match = pattern.firstMatch(content);
      if (match != null) {
        return 'Suspicious pattern ($label): "${match.group(0)}"';
      }
    }
    return null;
  }
}
