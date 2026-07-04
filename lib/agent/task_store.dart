/// In-memory task store for the Agent.
///
/// Tasks are session-scoped — they do not persist across app restarts.
/// Reference: claude-code-best TaskCreateTool/TaskUpdateTool/TaskListTool/TaskGetTool
library;

/// A single task in the task list.
class Task {
  final String id;
  String subject;
  String description;
  String? activeForm;
  String status; // 'pending', 'in_progress', 'completed'
  String? owner;
  List<String> blocks;
  List<String> blockedBy;
  Map<String, dynamic>? metadata;

  Task({
    required this.id,
    required this.subject,
    required this.description,
    this.activeForm,
    this.status = 'pending',
    this.owner,
    List<String>? blocks,
    List<String>? blockedBy,
    this.metadata,
  }) : blocks = blocks ?? [],
       blockedBy = blockedBy ?? [];

  Map<String, dynamic> toSummary() => {
    'id': id,
    'subject': subject,
    'status': status,
    if (owner != null) 'owner': owner,
    if (blockedBy.isNotEmpty) 'blockedBy': blockedBy,
  };

  Map<String, dynamic> toFull() => {
    'id': id,
    'subject': subject,
    'description': description,
    'status': status,
    if (activeForm != null) 'activeForm': activeForm,
    if (owner != null) 'owner': owner,
    'blocks': blocks,
    'blockedBy': blockedBy,
    if (metadata != null) 'metadata': metadata,
  };
}

/// Session-scoped in-memory task store.
class TaskStore {
  final Map<String, Task> _tasks = {};
  int _nextId = 1;

  /// Create a new task. Returns the created task.
  Task create({
    required String subject,
    required String description,
    String? activeForm,
    Map<String, dynamic>? metadata,
  }) {
    final id = (_nextId++).toString();
    final task = Task(
      id: id,
      subject: subject,
      description: description,
      activeForm: activeForm,
      metadata: metadata,
    );
    _tasks[id] = task;
    return task;
  }

  /// Get a task by ID. Returns null if not found.
  Task? get(String id) => _tasks[id];

  /// List all non-deleted tasks.
  List<Task> list() => _tasks.values.toList();

  /// Remove all completed tasks. Called after compact to prevent
  /// the model from re-doing finished work.
  void removeCompleted() {
    final completedIds = _tasks.entries
        .where((e) => e.value.status == 'completed')
        .map((e) => e.key)
        .toList();
    for (final id in completedIds) {
      _tasks.remove(id);
      for (final other in _tasks.values) {
        other.blocks.remove(id);
        other.blockedBy.remove(id);
      }
    }
  }

  /// Update a task. Returns the updated task, or null if not found.
  /// Pass fields to update; null values are ignored (except metadata keys).
  Task? update(
    String id, {
    String? subject,
    String? description,
    String? activeForm,
    String? status,
    String? owner,
    List<String>? addBlocks,
    List<String>? addBlockedBy,
    Map<String, dynamic>? metadata,
  }) {
    final task = _tasks[id];
    if (task == null) return null;

    // Handle deletion
    if (status == 'deleted') {
      _tasks.remove(id);
      // Clean up references in other tasks
      for (final other in _tasks.values) {
        other.blocks.remove(id);
        other.blockedBy.remove(id);
      }
      return task..status = 'deleted';
    }

    if (subject != null) task.subject = subject;
    if (description != null) task.description = description;
    if (activeForm != null) task.activeForm = activeForm;
    if (status != null) task.status = status;
    if (owner != null) task.owner = owner;

    if (addBlocks != null) {
      for (final blockedId in addBlocks) {
        if (!task.blocks.contains(blockedId)) task.blocks.add(blockedId);
        // Also update the other task's blockedBy
        _tasks[blockedId]?.blockedBy.add(id);
      }
    }

    if (addBlockedBy != null) {
      for (final blockerId in addBlockedBy) {
        if (!task.blockedBy.contains(blockerId)) task.blockedBy.add(blockerId);
        // Also update the other task's blocks
        _tasks[blockerId]?.blocks.add(id);
      }
    }

    if (metadata != null) {
      task.metadata ??= {};
      for (final entry in metadata.entries) {
        if (entry.value == null) {
          task.metadata!.remove(entry.key);
        } else {
          task.metadata![entry.key] = entry.value;
        }
      }
    }

    return task;
  }
}
