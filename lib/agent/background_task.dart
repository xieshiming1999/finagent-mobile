// ignore_for_file: unintended_html_in_doc_comment
import 'dart:io';

// Background task management for sub-agents.
// Reference: claude-code-best LocalAgentTaskState in src/tasks/types.ts

/// Maximum concurrent background agents (Mobile resource limit).
const maxConcurrentBackgroundAgents = 5;

/// Background task status lifecycle: pending → running → completed/failed/killed
enum BackgroundTaskStatus { pending, running, completed, failed, killed }

/// State of a background sub-agent task.
/// Reference: claude-code-best LocalAgentTaskState
class BackgroundTask {
  final String id;
  final String description;
  final String prompt;
  final String? toolUseId;
  final String? parentSessionId;
  BackgroundTaskStatus status;
  String? result;
  String? error;
  String? outputFilePath; // Disk-backed output file path
  final DateTime startTime;
  DateTime? endTime;
  bool notified;
  bool isBackgrounded;
  String? sidechainPath;

  // Progress tracking (reference: claude-code-best AgentProgress)
  int toolUseCount;
  int estimatedTokens;
  final List<String> recentActivities;

  BackgroundTask({
    required this.id,
    required this.description,
    required this.prompt,
    this.toolUseId,
    this.parentSessionId,
    this.status = BackgroundTaskStatus.pending,
    this.result,
    this.error,
    DateTime? startTime,
    this.endTime,
    this.notified = false,
    this.isBackgrounded = true,
    this.sidechainPath,
    this.toolUseCount = 0,
    this.estimatedTokens = 0,
    List<String>? recentActivities,
  }) : startTime = startTime ?? DateTime.now(),
       recentActivities = recentActivities ?? [];
}

/// In-memory registry of all background tasks with disk-backed output.
/// Reference: claude-code-best AppState.tasks (Record<string, TaskState>)
class TaskRegistry {
  final Map<String, BackgroundTask> _tasks = {};
  int _nextId = 1;

  /// Base path for disk-backed output files. Set by Agent on init.
  String? basePath;

  /// Register a new background task.
  BackgroundTask register({
    required String description,
    required String prompt,
    String? toolUseId,
    String? parentSessionId,
    bool isBackgrounded = true,
  }) {
    final id = 'agent-${_nextId++}';
    final task = BackgroundTask(
      id: id,
      description: description,
      prompt: prompt,
      toolUseId: toolUseId,
      parentSessionId: parentSessionId,
      isBackgrounded: isBackgrounded,
    );
    _tasks[id] = task;
    return task;
  }

  /// Get a task by ID.
  BackgroundTask? get(String id) => _tasks[id];

  /// List all tasks (excluding removed ones).
  List<BackgroundTask> list() => _tasks.values.toList();

  /// Count currently running tasks.
  int get runningCount => _tasks.values
      .where((t) => t.status == BackgroundTaskStatus.running)
      .length;

  /// Update task status. Large results are written to disk.
  void updateStatus(
    String id,
    BackgroundTaskStatus status, {
    String? result,
    String? error,
  }) {
    final task = _tasks[id];
    if (task == null) return;
    task.status = status;
    if (error != null) task.error = error;

    // Disk-back large results (>10K chars)
    if (result != null) {
      if (result.length > 10000 && basePath != null) {
        final outputDir = '$basePath/.task_outputs';
        Directory(outputDir).createSync(recursive: true);
        final filePath = '$outputDir/$id.txt';
        File(filePath).writeAsStringSync(result);
        task.outputFilePath = filePath;
        // Store preview in memory
        task.result =
            '${result.substring(0, 500)}\n\n'
            '... (${result.length} chars, full output at $filePath)';
      } else {
        task.result = result;
      }
    }

    if (status == BackgroundTaskStatus.completed ||
        status == BackgroundTaskStatus.failed ||
        status == BackgroundTaskStatus.killed) {
      task.endTime = DateTime.now();
    }
  }

  /// Read full output for a task (from disk if backed, else from memory).
  String? readOutput(String id) {
    final task = _tasks[id];
    if (task == null) return null;
    if (task.outputFilePath != null) {
      final file = File(task.outputFilePath!);
      if (file.existsSync()) return file.readAsStringSync();
    }
    return task.result;
  }

  /// Get completed/failed/killed tasks that haven't been notified to parent.
  List<BackgroundTask> getCompletedUnnotified() => _tasks.values
      .where(
        (t) =>
            !t.notified &&
            (t.status == BackgroundTaskStatus.completed ||
                t.status == BackgroundTaskStatus.failed ||
                t.status == BackgroundTaskStatus.killed),
      )
      .toList();

  /// Mark a task as notified.
  void markNotified(String id) {
    _tasks[id]?.notified = true;
  }

  /// Update progress for a running task.
  void updateProgress(
    String id, {
    int? toolUseCount,
    int? tokens,
    String? activity,
  }) {
    final task = _tasks[id];
    if (task == null) return;
    if (toolUseCount != null) task.toolUseCount = toolUseCount;
    if (tokens != null) task.estimatedTokens = tokens;
    if (activity != null) {
      task.recentActivities.add(activity);
      // Keep only last 10 activities
      if (task.recentActivities.length > 10) {
        task.recentActivities.removeAt(0);
      }
    }
  }

  /// Remove a task (GC). Also cleans up disk-backed output file.
  void remove(String id) {
    final task = _tasks[id];
    if (task?.outputFilePath != null) {
      try {
        File(task!.outputFilePath!).deleteSync();
      } catch (_) {}
    }
    _tasks.remove(id);
  }
}
