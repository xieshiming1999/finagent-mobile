import 'dart:convert';

const askUserQuestionContractPrefix = 'askUserQuestion:';
const askUserQuestionContractVersion = 'ask-user-question-v1';

Map<String, dynamic> buildAskUserQuestionContract(
  List<Map<String, dynamic>> answers,
) {
  return {'contract': askUserQuestionContractVersion, 'answers': answers};
}

/// Reads the generic AskUserQuestion answer contract from a tool result.
///
/// This helper intentionally knows nothing about finance, trading, or workflow
/// policy. Callers may interpret the returned `decision`, `action`, or
/// `selectedOptionIndex` according to their own typed contract.
Map<String, dynamic>? latestAskUserQuestionStructuredAnswer(String content) {
  final direct = _decodeJsonObject(content);
  if (direct != null) return direct;
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final text = line.trim();
    if (!text.startsWith(askUserQuestionContractPrefix)) continue;
    final envelope = _decodeJsonObject(
      text.substring(askUserQuestionContractPrefix.length),
    );
    if (envelope == null ||
        envelope['contract'] != askUserQuestionContractVersion) {
      continue;
    }
    final answers = envelope['answers'];
    if (answers is! List) continue;
    for (final answer in answers.reversed) {
      if (answer is! Map) continue;
      final structured = answer['structuredAnswer'];
      if (structured is Map) return Map<String, dynamic>.from(structured);
      final raw = answer['answer'];
      if (raw is String) {
        final decoded = _decodeJsonObject(raw);
        if (decoded != null) return decoded;
      }
    }
  }
  return null;
}

Map<String, dynamic>? _decodeJsonObject(String value) {
  final text = value.trim();
  if (!text.startsWith('{')) return null;
  try {
    final decoded = jsonDecode(text);
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}
