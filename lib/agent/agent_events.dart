import 'dart:async';

import 'message.dart';
import 'session.dart';

/// Events emitted by the Agent during a run.
sealed class AgentEvent {}

class AgentTextDelta extends AgentEvent {
  final String text;
  AgentTextDelta(this.text);
}

/// Emitted when a tool call starts streaming (name known, args still incoming).
/// Allows UI to show "Generating Write(...)" instead of "thinking...".
class AgentToolCallStreaming extends AgentEvent {
  final String toolName;
  AgentToolCallStreaming({required this.toolName});
}

class AgentToolUseStart extends AgentEvent {
  final String toolName;
  final Map<String, dynamic> input;
  AgentToolUseStart({required this.toolName, required this.input});
}

class AgentToolResult extends AgentEvent {
  final String toolName;
  final String result;
  final bool isError;
  final int durationMs;
  AgentToolResult({
    required this.toolName,
    required this.result,
    this.isError = false,
    this.durationMs = 0,
  });
}

/// LLM 请求开始（用于显示 "思考中..."）
class AgentStreamStart extends AgentEvent {}

/// LLM token 用量统计
class AgentUsage extends AgentEvent {
  final int promptTokens;
  final int completionTokens;
  AgentUsage({required this.promptTokens, required this.completionTokens});
}

/// 轮次完成统计摘要
class AgentTurnComplete extends AgentEvent {
  final int durationMs;
  final int toolCallCount;
  final int promptTokens;
  final int completionTokens;
  AgentTurnComplete({
    required this.durationMs,
    required this.toolCallCount,
    required this.promptTokens,
    required this.completionTokens,
  });
}

/// Tool 执行进度（长时间运行的 tool，如 Bash）
class AgentToolProgress extends AgentEvent {
  final String toolName;
  final String output;
  final int elapsedMs;
  AgentToolProgress({
    required this.toolName,
    required this.output,
    required this.elapsedMs,
  });
}

/// Incremental output chars from tool arg streaming (for live token estimation).
class AgentOutputChars extends AgentEvent {
  final int chars;
  AgentOutputChars(this.chars);
}

/// LLM thinking/reasoning content (not shown to user, used for status display).
class AgentThinking extends AgentEvent {
  final String text;
  AgentThinking(this.text);
}

/// Emitted when tasks change (TaskCreate/TaskUpdate).
class AgentTasksChanged extends AgentEvent {
  final List<Map<String, dynamic>> tasks;
  AgentTasksChanged(this.tasks);
}

/// Result of a tool confirmation dialog.
class ToolConfirmResult {
  final bool approved;
  final bool alwaysAllow;
  final String? rejectReason;
  const ToolConfirmResult.approve()
    : approved = true,
      alwaysAllow = false,
      rejectReason = null;
  const ToolConfirmResult.alwaysApprove()
    : approved = true,
      alwaysAllow = true,
      rejectReason = null;
  const ToolConfirmResult.reject([this.rejectReason])
    : approved = false,
      alwaysAllow = false;
}

/// Emitted when a tool needs user confirmation before executing.
class AgentToolConfirmRequest extends AgentEvent {
  final String toolName;
  final Map<String, dynamic> input;
  final Completer<ToolConfirmResult> completer;
  AgentToolConfirmRequest({
    required this.toolName,
    required this.input,
    required this.completer,
  });
}

/// Emitted when a slash command produces text output.
class AgentCommandOutput extends AgentEvent {
  final String text;
  AgentCommandOutput(this.text);
}

/// Emitted when /clear is executed.
class AgentSessionCleared extends AgentEvent {}

/// Emitted when /resume produces a session list for user selection.
class AgentSessionList extends AgentEvent {
  final String prompt;
  final List<SessionSummary> sessions;
  final Completer<String?> completer; // user selects a filePath or null
  AgentSessionList({
    required this.prompt,
    required this.sessions,
    required this.completer,
  });
}

/// Emitted when session is resumed with restored messages.
class AgentSessionResumed extends AgentEvent {
  final List<Message> messages;
  AgentSessionResumed(this.messages);
}

/// Emitted when compaction happened.
class AgentCompacted extends AgentEvent {
  final int preCompactCount;
  final int postCompactCount;
  AgentCompacted({
    required this.preCompactCount,
    required this.postCompactCount,
  });
}

class AgentDone extends AgentEvent {}

/// Emitted when a foreground task is moved to background.
class AgentBackgrounded extends AgentEvent {
  final String taskId;
  AgentBackgrounded({required this.taskId});
}

class AgentError extends AgentEvent {
  final String message;
  AgentError(this.message);
}

/// Emitted when speculation suggests a next user prompt.
class AgentSuggestion extends AgentEvent {
  final String suggestion;
  AgentSuggestion(this.suggestion);
}

/// Emitted by _pump() before running a notification batch.
class AgentNotificationReceived extends AgentEvent {
  final String prompt;
  AgentNotificationReceived(this.prompt);
}
