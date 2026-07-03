import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'cron_parser.dart';

export 'cron_parser.dart';

class CronTask {
  final String id;
  final String? key;
  final String schedule; // original schedule expression
  final String prompt;
  final int createdAt; // epoch ms
  int? lastFiredAt; // epoch ms
  bool recurring;
  bool durable;
  bool runInBackground;
  String? lastTriggeredTaskId;

  // Resolved scheduling
  int? intervalMs; // for interval mode
  int? fireAtMs; // for delay mode (absolute target time)
  String? cron; // resolved 5-field cron (null for interval/delay)

  CronTask({
    required this.id,
    this.key,
    required this.schedule,
    required this.prompt,
    required this.createdAt,
    this.lastFiredAt,
    this.recurring = true,
    this.durable = false,
    this.runInBackground = true,
    this.lastTriggeredTaskId,
    this.intervalMs,
    this.fireAtMs,
    this.cron,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    if (key != null && key!.isNotEmpty) 'key': key,
    'schedule': schedule,
    'cron': cron,
    'prompt': prompt,
    'createdAt': createdAt,
    if (lastFiredAt != null) 'lastFiredAt': lastFiredAt,
    'recurring': recurring,
    'runInBackground': runInBackground,
    if (intervalMs != null) 'intervalMs': intervalMs,
    if (fireAtMs != null) 'fireAtMs': fireAtMs,
  };

  factory CronTask.fromJson(Map<String, dynamic> json) => CronTask(
    id: json['id'] as String,
    key: json['key'] as String?,
    schedule: json['schedule'] as String? ?? json['cron'] as String? ?? '',
    prompt: json['prompt'] as String,
    createdAt: json['createdAt'] as int,
    lastFiredAt: json['lastFiredAt'] as int?,
    recurring: json['recurring'] as bool? ?? true,
    durable: true, // loaded from file = durable
    runInBackground: json['runInBackground'] as bool? ?? true,
    intervalMs: json['intervalMs'] as int?,
    fireAtMs: json['fireAtMs'] as int?,
    cron: json['cron'] as String?,
  );

  bool get isExpired =>
      recurring &&
      DateTime.now().millisecondsSinceEpoch - createdAt >= recurringMaxAgeMs;
}

// --- Jitter ---

/// Deterministic jitter fraction [0, 1) based on task ID hash.
/// Reference: claude-code-best/src/utils/cronTasks.ts jitterFrac()
double jitterFrac(String taskId) {
  // Parse first 8 hex chars as uint32
  final hex = taskId.padRight(8, '0').substring(0, 8);
  final value = int.tryParse(hex, radix: 16) ?? 0;
  return value / 0x100000000;
}

// --- CronScheduler ---

/// Callback when a task fires.
typedef OnCronFire = void Function(CronTask task);

/// Manages scheduled cron tasks with 1-second polling.
/// Reference: claude-code-best/src/utils/cronScheduler.ts
class CronScheduler {
  final String storagePath; // path to scheduled_tasks.json
  Timer? _ticker;
  final List<CronTask> _sessionTasks = [];
  List<CronTask> _durableTasks = [];
  final Map<String, int> _nextFireAt = {}; // taskId → epoch ms

  /// Called when a task fires. Agent integrates this with NotificationQueue.
  OnCronFire? onFire;

  CronScheduler({required this.storagePath});

  /// Start the 1-second polling loop.
  void start() {
    _loadDurableTasks();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  /// Stop the scheduler.
  void stop() {
    _ticker?.cancel();
    _ticker = null;
  }

  /// Add a task. Returns the created CronTask.
  CronTask addTask({
    String? key,
    required String schedule,
    required String prompt,
    bool recurring = true,
    bool durable = false,
    bool runInBackground = true,
  }) {
    final id = _generateId();
    final config = parseSchedule(schedule);
    final now = DateTime.now().millisecondsSinceEpoch;

    final task = CronTask(
      id: id,
      key: key,
      schedule: schedule,
      prompt: prompt,
      createdAt: now,
      recurring: recurring,
      durable: durable,
      runInBackground: runInBackground,
      cron: config.type == 'cron' ? config.cron : null,
      intervalMs: config.type == 'interval' ? config.intervalMs : null,
      fireAtMs: config.type == 'delay' ? now + (config.delayMs ?? 0) : null,
    );

    if (durable) {
      _durableTasks.add(task);
      _saveDurableTasks();
    } else {
      _sessionTasks.add(task);
    }

    // Compute initial nextFireAt
    _nextFireAt[id] = _computeNextFire(task, now);

    return task;
  }

  /// Remove a task by ID.
  void removeTask(String id) {
    _sessionTasks.removeWhere((t) => t.id == id);
    _durableTasks.removeWhere((t) => t.id == id);
    _nextFireAt.remove(id);
    _saveDurableTasks();
  }

  /// Remove all tasks (session + durable).
  void clearAll() {
    _sessionTasks.clear();
    _durableTasks.clear();
    _nextFireAt.clear();
    _saveDurableTasks();
  }

  /// List all tasks (session + durable).
  List<CronTask> listTasks() => [..._sessionTasks, ..._durableTasks];

  /// Get a task by ID.
  CronTask? getTask(String id) =>
      _sessionTasks.where((t) => t.id == id).firstOrNull ??
      _durableTasks.where((t) => t.id == id).firstOrNull;

  /// Total task count.
  int get taskCount => _sessionTasks.length + _durableTasks.length;

  // --- Core tick ---

  void _tick() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final toRemove = <String>[];
    final firedDurable = <CronTask>[];

    for (final task in [..._sessionTasks, ..._durableTasks]) {
      final fireAt = _nextFireAt[task.id];
      if (fireAt == null || now < fireAt) continue;

      // Fire!
      onFire?.call(task);
      task.lastFiredAt = now;

      if (task.recurring && !task.isExpired) {
        // Reschedule from now (not from scheduled time)
        _nextFireAt[task.id] = _computeNextFire(task, now);
        if (task.durable) firedDurable.add(task);
      } else {
        // One-shot or expired recurring → remove
        toRemove.add(task.id);
      }
    }

    for (final id in toRemove) {
      removeTask(id);
    }

    if (firedDurable.isNotEmpty) {
      _saveDurableTasks();
    }
  }

  // --- Scheduling ---

  int _computeNextFire(CronTask task, int fromMs) {
    // Delay mode: absolute target time
    if (task.fireAtMs != null) return task.fireAtMs!;

    // Interval mode
    if (task.intervalMs != null) {
      final base = task.lastFiredAt ?? task.createdAt;
      return base + task.intervalMs!;
    }

    // Cron mode
    if (task.cron != null) {
      final fields = parseCronExpression(task.cron!);
      if (fields != null) {
        final from = DateTime.fromMillisecondsSinceEpoch(fromMs);
        final next = computeNextCronRun(fields, from);
        if (next != null) {
          // Apply jitter
          final nextMs = next.millisecondsSinceEpoch;
          final frac = jitterFrac(task.id);
          // Recurring: delay up to 10% of interval, max 15 min
          if (task.recurring) {
            final after = computeNextCronRun(fields, next);
            if (after != null) {
              final interval = after.millisecondsSinceEpoch - nextMs;
              final jitter = min(frac * 0.1 * interval, 15 * 60 * 1000).toInt();
              return nextMs + jitter;
            }
          }
          return nextMs;
        }
      }
    }

    // Fallback: 1 minute from now
    return fromMs + 60000;
  }

  // --- Durable storage ---

  void _loadDurableTasks() {
    final file = File(storagePath);
    if (!file.existsSync()) return;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final tasks = json['tasks'] as List? ?? [];
      _durableTasks = tasks
          .map((t) => CronTask.fromJson(Map<String, dynamic>.from(t as Map)))
          .toList();

      // Initialize nextFireAt for loaded tasks
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final task in _durableTasks) {
        _nextFireAt[task.id] = _computeNextFire(task, now);
      }
    } catch (_) {
      _durableTasks = [];
    }
  }

  void _saveDurableTasks() {
    final file = File(storagePath);
    final dir = Directory(p.dirname(storagePath));
    if (!dir.existsSync()) dir.createSync(recursive: true);

    file.writeAsStringSync(
      jsonEncode({'tasks': _durableTasks.map((t) => t.toJson()).toList()}),
    );
  }

  String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    return now.toRadixString(16).padLeft(8, '0').substring(0, 8);
  }
}
