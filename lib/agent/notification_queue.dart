import 'message.dart';

// Reference: claude-code-best commandQueue / enqueuePendingNotification

/// Priority levels for pending notifications.
/// 'now' fires immediately, 'next' fires before the next LLM call, 'later' waits for idle.
enum NotificationPriority { now, next, later }

/// A pending notification to be injected into the conversation.
class PendingNotification {
  final String prompt;
  final NotificationPriority priority;
  final String?
  source; // 'cron', 'task-notification', 'dashboard', 'user_input', etc.
  final bool isMeta;
  final DateTime createdAt;

  PendingNotification({
    required this.prompt,
    this.priority = NotificationPriority.later,
    this.source,
    this.isMeta = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();
}

/// Per-source throttle/filter configuration.
class SourcePolicy {
  /// Whether this source is accepted at all.
  bool enabled;

  /// Minimum interval between accepted messages from this source.
  /// null = no throttle.
  Duration? minInterval;

  /// Last time a message from this source was accepted.
  DateTime? _lastAccepted;

  SourcePolicy({this.enabled = true, this.minInterval});

  bool shouldAccept() {
    if (!enabled) return false;
    if (minInterval == null) return true;
    final now = DateTime.now();
    if (_lastAccepted == null ||
        now.difference(_lastAccepted!) >= minInterval!) {
      _lastAccepted = now;
      return true;
    }
    return false;
  }

  void reset() => _lastAccepted = null;
}

/// Queue for pending notifications that get injected into the Agent conversation.
/// Agent drains this at the start of each _agentLoop iteration.
///
/// Supports:
/// - Global pause (accepting = false)
/// - Per-source enable/disable and throttling
/// - Queue inspection and clearing
class NotificationQueue {
  final List<PendingNotification> _queue = [];
  final Map<String, SourcePolicy> _sourcePolicies = {};

  /// Global switch: when false, all incoming notifications are silently dropped.
  bool accepting = true;

  /// Stats: total dropped since creation.
  int _droppedCount = 0;
  int get droppedCount => _droppedCount;

  /// Called synchronously after enqueue. Agent uses this to trigger _pump().
  void Function()? onEnqueue;

  // ─── Source Policies ───

  /// Set policy for a specific source. Creates if not exists.
  void setSourcePolicy(String source, {bool? enabled, Duration? minInterval}) {
    final policy = _sourcePolicies.putIfAbsent(source, () => SourcePolicy());
    if (enabled != null) policy.enabled = enabled;
    if (minInterval != null) policy.minInterval = minInterval;
  }

  /// Get current policy for a source, or null if no policy set.
  SourcePolicy? getSourcePolicy(String source) => _sourcePolicies[source];

  /// Remove policy for a source (reverts to default accept-all).
  void removeSourcePolicy(String source) => _sourcePolicies.remove(source);

  /// All configured source policies.
  Map<String, SourcePolicy> get sourcePolicies =>
      Map.unmodifiable(_sourcePolicies);

  // ─── Enqueue ───

  /// Enqueue a notification. Returns true if accepted, false if dropped.
  bool enqueue(PendingNotification notification) {
    // User input always bypasses throttle
    if (notification.source != 'user_input') {
      if (!accepting) {
        _droppedCount++;
        return false;
      }

      final source = notification.source;
      if (source != null) {
        final policy = _sourcePolicies[source];
        if (policy != null && !policy.shouldAccept()) {
          _droppedCount++;
          return false;
        }
      }
    }

    _queue.add(notification);
    // Sort by priority: now > next > later, then by creation time
    _queue.sort((a, b) {
      final priCmp = a.priority.index.compareTo(b.priority.index);
      if (priCmp != 0) return priCmp;
      return a.createdAt.compareTo(b.createdAt);
    });
    onEnqueue?.call();
    return true;
  }

  // ─── Dequeue ───

  /// Dequeue the highest-priority notification, or null if empty.
  PendingNotification? dequeueNext() {
    if (_queue.isEmpty) return null;
    return _queue.removeAt(0);
  }

  /// Drain all pending notifications as Messages for injection into conversation.
  /// Returns empty list if no notifications pending.
  List<Message> drainAsMessages() {
    if (_queue.isEmpty) return [];

    final messages = <Message>[];
    while (_queue.isNotEmpty) {
      final notification = _queue.removeAt(0);
      messages.add(
        Message(
          role: Role.user,
          content: notification.source == 'cron'
              ? '<scheduled-task>\n${notification.prompt}\n</scheduled-task>'
              : notification.prompt,
          timestamp: DateTime.now(),
        ),
      );
    }
    return messages;
  }

  // ─── Inspection ───

  /// Whether there are pending notifications.
  bool get isNotEmpty => _queue.isNotEmpty;

  /// Number of pending notifications.
  int get length => _queue.length;

  /// Peek at pending notifications (read-only).
  List<PendingNotification> get pending => List.unmodifiable(_queue);

  /// Count by source.
  Map<String, int> get countBySource {
    final counts = <String, int>{};
    for (final n in _queue) {
      final key = n.source ?? 'unknown';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    return counts;
  }

  // ─── Clear ───

  /// Clear all pending notifications.
  void clear() => _queue.clear();

  /// Clear only notifications from a specific source.
  void clearSource(String source) {
    _queue.removeWhere((n) => n.source == source);
  }

  /// Reset all throttle timers.
  void resetThrottles() {
    for (final policy in _sourcePolicies.values) {
      policy.reset();
    }
  }
}
