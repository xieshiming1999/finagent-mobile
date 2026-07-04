import 'dart:async';
import 'dart:convert';

import '../../ask_user_question_contract.dart';
import '../../message.dart';
import '../../tool.dart';
import '../../tool_context.dart';
import 'prompt.dart' as tool_prompt;

/// Data model for a single question option.
class QuestionOption {
  final String label;
  final String description;
  final String? preview;

  const QuestionOption({
    required this.label,
    required this.description,
    this.preview,
  });

  Map<String, dynamic> toJson() => {
    'label': label,
    'description': description,
    if (preview != null) 'preview': preview,
  };

  factory QuestionOption.fromJson(Map<String, dynamic> json) => QuestionOption(
    label: json['label'] as String,
    description: json['description'] as String? ?? '',
    preview: json['preview'] as String?,
  );
}

/// Data model for a single question.
class UserQuestion {
  final String question;
  final String header;
  final List<QuestionOption> options;
  final bool multiSelect;

  const UserQuestion({
    required this.question,
    required this.header,
    required this.options,
    this.multiSelect = false,
  });

  Map<String, dynamic> toJson() => {
    'question': question,
    'header': header,
    'options': options.map((o) => o.toJson()).toList(),
    'multiSelect': multiSelect,
  };

  factory UserQuestion.fromJson(Map<String, dynamic> json) => UserQuestion(
    question: json['question'] as String,
    header: json['header'] as String? ?? '',
    options:
        (json['options'] as List<dynamic>?)
            ?.map((o) => QuestionOption.fromJson(o as Map<String, dynamic>))
            .toList() ??
        [],
    multiSelect: json['multiSelect'] as bool? ?? false,
  );
}

/// Callback type for asking the user a question.
/// Returns a map of question text → answer string.
typedef AskUserHandler =
    Future<Map<String, String>> Function(List<UserQuestion> questions);

/// Tool that asks the user questions via the UI.
///
/// The tool pauses agent execution until the user responds.
/// The UI renders options inline in the chat and switches the
/// input bar to answer mode.
///
/// Reference: claude-code-best AskUserQuestion tool
class AskUserQuestionTool extends Tool {
  /// Handler set by the UI layer to render questions and collect answers.
  AskUserHandler? handler;

  @override
  String get name => 'AskUserQuestion';

  @override
  String get description => tool_prompt.description;

  @override
  String get prompt => tool_prompt.prompt;

  @override
  Map<String, dynamic> get inputSchema => {
    'type': 'object',
    'properties': {
      'questions': {
        'type': 'array',
        'description': 'Questions to ask the user (1-4 questions)',
        'minItems': 1,
        'maxItems': 4,
        'items': {
          'type': 'object',
          'properties': {
            'question': {
              'type': 'string',
              'description': 'The full question text',
            },
            'header': {
              'type': 'string',
              'description': 'Short chip/tag label (max 12 chars)',
            },
            'options': {
              'type': 'array',
              'description': 'Available choices (2-4 options)',
              'minItems': 2,
              'maxItems': 4,
              'items': {
                'type': 'object',
                'properties': {
                  'label': {
                    'type': 'string',
                    'description': 'Display text (1-5 words)',
                  },
                  'description': {
                    'type': 'string',
                    'description': 'What this option means',
                  },
                },
                'required': ['label', 'description'],
              },
            },
            'multiSelect': {
              'type': 'boolean',
              'description': 'Allow multiple selections (default false)',
              'default': false,
            },
          },
          'required': ['question', 'header', 'options', 'multiSelect'],
        },
      },
    },
    'required': ['questions'],
  };

  @override
  bool get isReadOnly => true;

  @override
  bool get requiresUserInteraction => true;

  @override
  bool needsPermissions(Map<String, dynamic> input) => false;

  @override
  Future<String?> validateInput(
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final questions = input['questions'] as List<dynamic>?;
    if (questions == null || questions.isEmpty) {
      return 'questions is required and must not be empty.';
    }
    if (questions.length > 4) {
      return 'Maximum 4 questions allowed.';
    }
    for (final q in questions) {
      final qMap = q as Map<String, dynamic>;
      if (qMap['question'] == null ||
          (qMap['question'] as String).trim().isEmpty) {
        return 'Each question must have a "question" text.';
      }
      final options = qMap['options'] as List<dynamic>?;
      if (options == null || options.length < 2) {
        return 'Each question must have at least 2 options.';
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
    if (handler == null) {
      return ToolResult(
        toolUseId: toolUseId,
        content: 'AskUserQuestion not available: no UI handler registered.',
        isError: true,
      );
    }

    final questionsList = (input['questions'] as List<dynamic>)
        .map((q) => UserQuestion.fromJson(q as Map<String, dynamic>))
        .toList();

    // Call UI handler — this blocks until user answers
    final answers = await handler!(questionsList);

    // Keep the Claude-style prose for the model, and append a machine-readable
    // answer contract for workflow code that must not infer decisions from text.
    final parts = <String>[];
    final structuredAnswers = <Map<String, dynamic>>[];
    for (final q in questionsList) {
      final answer = answers[q.question] ?? '(no answer)';
      parts.add('"${q.question}"="$answer"');
      structuredAnswers.add({
        'question': q.question,
        'answer': answer,
        'structuredAnswer': _structuredAnswer(q, answer),
      });
    }
    final contract = buildAskUserQuestionContract(structuredAnswers);

    return ToolResult(
      toolUseId: toolUseId,
      content:
          'User has answered your questions: ${parts.join(", ")}. '
          'You can now continue with the user\'s answers in mind.\n'
          '$askUserQuestionContractPrefix${jsonEncode(contract)}',
    );
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

  Map<String, dynamic>? _structuredAnswer(
    UserQuestion question,
    String answer,
  ) {
    final decoded = _decodeJsonObject(answer);
    if (decoded != null) return decoded;
    final text = answer.trim();
    final numeric = int.tryParse(text);
    if (numeric != null && numeric >= 1 && numeric <= question.options.length) {
      final option = question.options[numeric - 1];
      return {
        'selectedOptionIndex': numeric,
        'selectedOptionLabel': option.label,
      };
    }
    for (var i = 0; i < question.options.length; i++) {
      final option = question.options[i];
      if (option.label.trim() == text) {
        return {
          'selectedOptionIndex': i + 1,
          'selectedOptionLabel': option.label,
        };
      }
    }
    return null;
  }
}
