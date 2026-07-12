import 'message.dart';
import 'tool.dart';

typedef DomainRecoveryToolCall =
    Future<ToolResult> Function(
      Tool tool,
      String toolUseId,
      Map<String, dynamic> input,
    );

class DomainToolInterception {
  final String answer;
  final String skippedReason;

  const DomainToolInterception({
    required this.answer,
    required this.skippedReason,
  });
}

abstract class DomainDataBudgetPolicy {
  const DomainDataBudgetPolicy();

  bool wouldExceedBudget({
    required String? prompt,
    required int currentDataToolCalls,
    required int existingBudgetWarnings,
    required List<ToolUse> proposedToolCalls,
  });

  bool isDataTool(String toolName);
}

class NoopDomainDataBudgetPolicy extends DomainDataBudgetPolicy {
  const NoopDomainDataBudgetPolicy();

  @override
  bool wouldExceedBudget({
    required String? prompt,
    required int currentDataToolCalls,
    required int existingBudgetWarnings,
    required List<ToolUse> proposedToolCalls,
  }) {
    return false;
  }

  @override
  bool isDataTool(String toolName) => false;
}

abstract class DomainTurnPolicy {
  void reset();
  String? blockedToolUseReason(ToolUse toolUse);
  void recordToolResult(ToolUse toolUse, ToolResult result);
  bool shouldStopToolBatchAfterResult(ToolUse toolUse, ToolResult result);
}

class NoopDomainTurnPolicy implements DomainTurnPolicy {
  const NoopDomainTurnPolicy();

  @override
  void reset() {}

  @override
  String? blockedToolUseReason(ToolUse toolUse) => null;

  @override
  void recordToolResult(ToolUse toolUse, ToolResult result) {}

  @override
  bool shouldStopToolBatchAfterResult(ToolUse toolUse, ToolResult result) =>
      false;
}

abstract class DomainWorkflowHooks {
  const DomainWorkflowHooks();

  List<ToolUse>? buildPreflightToolCalls(List<Message> messages);

  String? buildPreflightAnswer(List<Message> messages);

  List<ToolUse> rewriteToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  }) {
    return toolCalls;
  }

  DomainToolInterception? interceptToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  });

  String? rewriteFinalAnswer({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required String answer,
  });

  bool finalAnswerNeedsRequiredVerifier({
    required List<Message> messages,
    required int turnStartIndex,
  }) {
    return false;
  }

  String buildBudgetStopText({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required String failureSummary,
  });

  Future<String?> buildRecovery({
    required String? prompt,
    required List<Message> messages,
    required Tool? Function(String name) toolByName,
    required DomainRecoveryToolCall callTool,
  });
}

class NoopDomainWorkflowHooks extends DomainWorkflowHooks {
  const NoopDomainWorkflowHooks();

  @override
  List<ToolUse>? buildPreflightToolCalls(List<Message> messages) => null;

  @override
  String? buildPreflightAnswer(List<Message> messages) => null;

  @override
  List<ToolUse> rewriteToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  }) {
    return toolCalls;
  }

  @override
  DomainToolInterception? interceptToolCalls({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required List<ToolUse> toolCalls,
  }) {
    return null;
  }

  @override
  String? rewriteFinalAnswer({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required String answer,
  }) {
    return null;
  }

  @override
  String buildBudgetStopText({
    required List<Message> messages,
    required int turnStartIndex,
    required String? prompt,
    required String failureSummary,
  }) {
    return 'Stopped: this turn reached the configured domain workflow budget. '
        'No further tool calls were executed. Use the existing tool evidence, '
        'or ask a narrower follow-up.';
  }

  @override
  Future<String?> buildRecovery({
    required String? prompt,
    required List<Message> messages,
    required Tool? Function(String name) toolByName,
    required DomainRecoveryToolCall callTool,
  }) async {
    return null;
  }
}
