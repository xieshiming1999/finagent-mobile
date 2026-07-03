// ignore_for_file: unintended_html_in_doc_comment

// Reference: claude-code-best/src/utils/cron.ts, cronTasks.ts, cronScheduler.ts

/// Maximum number of scheduled tasks.
const maxCronJobs = 50;

/// Recurring tasks auto-expire after 7 days.
const recurringMaxAgeMs = 7 * 24 * 60 * 60 * 1000;

// --- Cron Expression Parser ---

/// Parsed cron fields (all values as Set<int>).
class CronFields {
  final Set<int> minutes; // 0-59
  final Set<int> hours; // 0-23
  final Set<int> daysOfMonth; // 1-31
  final Set<int> months; // 1-12
  final Set<int> daysOfWeek; // 0-6 (0=Sunday)

  const CronFields({
    required this.minutes,
    required this.hours,
    required this.daysOfMonth,
    required this.months,
    required this.daysOfWeek,
  });
}

/// Parse a 5-field cron expression. Returns null if invalid.
/// Supports: *, */N, N, N-M, N-M/S, comma-separated lists.
/// Reference: claude-code-best/src/utils/cron.ts parseCronExpression()
CronFields? parseCronExpression(String expr) {
  final parts = expr.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return null;

  final minutes = _expandField(parts[0], 0, 59);
  final hours = _expandField(parts[1], 0, 23);
  final dom = _expandField(parts[2], 1, 31);
  final months = _expandField(parts[3], 1, 12);
  final dow = _expandField(parts[4], 0, 6, allowSeven: true);

  if (minutes == null ||
      hours == null ||
      dom == null ||
      months == null ||
      dow == null) {
    return null;
  }

  return CronFields(
    minutes: minutes,
    hours: hours,
    daysOfMonth: dom,
    months: months,
    daysOfWeek: dow,
  );
}

Set<int>? _expandField(
  String field,
  int minVal,
  int maxVal, {
  bool allowSeven = false,
}) {
  final result = <int>{};

  for (final part in field.split(',')) {
    final trimmed = part.trim();

    // */N
    final stepAll = RegExp(r'^\*/(\d+)$').firstMatch(trimmed);
    if (stepAll != null) {
      final step = int.parse(stepAll.group(1)!);
      if (step <= 0) return null;
      for (var i = minVal; i <= maxVal; i += step) {
        result.add(i);
      }
      continue;
    }

    // *
    if (trimmed == '*') {
      for (var i = minVal; i <= maxVal; i++) {
        result.add(i);
      }
      continue;
    }

    // N-M/S or N-M
    final rangeMatch = RegExp(r'^(\d+)-(\d+)(?:/(\d+))?$').firstMatch(trimmed);
    if (rangeMatch != null) {
      var start = int.parse(rangeMatch.group(1)!);
      var end = int.parse(rangeMatch.group(2)!);
      final step = rangeMatch.group(3) != null
          ? int.parse(rangeMatch.group(3)!)
          : 1;
      if (allowSeven && start == 7) start = 0;
      if (allowSeven && end == 7) end = 0;
      if (step <= 0) return null;
      if (start <= end) {
        for (var i = start; i <= end; i += step) {
          result.add(i.clamp(minVal, maxVal));
        }
      }
      continue;
    }

    // N (literal)
    final num = int.tryParse(trimmed);
    if (num != null) {
      var val = num;
      if (allowSeven && val == 7) val = 0;
      if (val < minVal || val > maxVal) return null;
      result.add(val);
      continue;
    }

    return null; // invalid
  }

  return result.isEmpty ? null : result;
}

/// Compute the next cron run time from [from]. Returns null if none within 366 days.
/// Reference: claude-code-best/src/utils/cron.ts computeNextCronRun()
DateTime? computeNextCronRun(CronFields fields, DateTime from) {
  var candidate = DateTime(
    from.year,
    from.month,
    from.day,
    from.hour,
    from.minute + 1,
  ); // start from next minute

  final deadline = from.add(const Duration(days: 366));

  while (candidate.isBefore(deadline)) {
    if (!fields.months.contains(candidate.month)) {
      // Skip to next month
      candidate = DateTime(candidate.year, candidate.month + 1, 1);
      continue;
    }

    // Day check: standard cron uses OR when both dom and dow are constrained
    final domAll = fields.daysOfMonth.length == 31; // unrestricted
    final dowAll = fields.daysOfWeek.length == 7;
    final domMatch = fields.daysOfMonth.contains(candidate.day);
    final dowMatch = fields.daysOfWeek.contains(candidate.weekday % 7);

    bool dayMatch;
    if (domAll && dowAll) {
      dayMatch = true;
    } else if (domAll) {
      dayMatch = dowMatch;
    } else if (dowAll) {
      dayMatch = domMatch;
    } else {
      dayMatch = domMatch || dowMatch; // OR semantics
    }

    if (!dayMatch) {
      candidate = DateTime(candidate.year, candidate.month, candidate.day + 1);
      continue;
    }

    if (!fields.hours.contains(candidate.hour)) {
      candidate = DateTime(
        candidate.year,
        candidate.month,
        candidate.day,
        candidate.hour + 1,
      );
      continue;
    }

    if (!fields.minutes.contains(candidate.minute)) {
      candidate = candidate.add(const Duration(minutes: 1));
      continue;
    }

    return candidate;
  }

  return null;
}

/// Convert cron to human-readable string.
String cronToHuman(String cron) {
  final parts = cron.trim().split(RegExp(r'\s+'));
  if (parts.length != 5) return cron;

  final m = parts[0],
      h = parts[1],
      dom = parts[2],
      mon = parts[3],
      dow = parts[4];

  // Every N minutes
  final everyNMin = RegExp(r'^\*/(\d+)$').firstMatch(m);
  if (everyNMin != null && h == '*' && dom == '*' && mon == '*' && dow == '*') {
    return 'Every ${everyNMin.group(1)} minutes';
  }

  // Every minute
  if (m == '*' && h == '*' && dom == '*' && mon == '*' && dow == '*') {
    return 'Every minute';
  }

  // Every hour at :MM
  if (h == '*' && dom == '*' && mon == '*' && dow == '*') {
    return 'Every hour at :${m.padLeft(2, '0')}';
  }

  // Daily at HH:MM
  if (dom == '*' && mon == '*' && dow == '*') {
    return 'Every day at $h:${m.padLeft(2, '0')}';
  }

  // Weekdays
  if (dom == '*' && mon == '*' && dow == '1-5') {
    return 'Weekdays at $h:${m.padLeft(2, '0')}';
  }

  return cron;
}

// --- Schedule Expression Parser (extends beyond standard cron) ---

class ScheduleConfig {
  final String type; // 'cron', 'interval', 'delay'
  final String? cron; // 5-field cron expression
  final int? intervalMs; // interval mode
  final int? delayMs; // delay mode

  const ScheduleConfig({
    required this.type,
    this.cron,
    this.intervalMs,
    this.delayMs,
  });
}

/// Parse a schedule expression. Supports:
/// - Standard cron: "*/5 * * * *"
/// - Interval: "every 1 minute", "every 30 seconds"
/// - Delay: "after 30 minutes", "in 1 hour"
ScheduleConfig parseSchedule(String schedule) {
  final trimmed = schedule.trim().toLowerCase();

  // Interval: "every N unit(s)"
  final intervalMatch = RegExp(
    r'^every\s+(\d+)\s+(second|minute|hour|day)s?$',
  ).firstMatch(trimmed);
  if (intervalMatch != null) {
    final n = int.parse(intervalMatch.group(1)!);
    final unit = intervalMatch.group(2)!;
    return ScheduleConfig(type: 'interval', intervalMs: n * _unitToMs(unit));
  }

  // Delay: "after N unit(s)" or "in N unit(s)"
  final delayMatch = RegExp(
    r'^(?:after|in)\s+(\d+)\s+(second|minute|hour|day)s?$',
  ).firstMatch(trimmed);
  if (delayMatch != null) {
    final n = int.parse(delayMatch.group(1)!);
    final unit = delayMatch.group(2)!;
    return ScheduleConfig(type: 'delay', delayMs: n * _unitToMs(unit));
  }

  // Standard cron expression
  return ScheduleConfig(type: 'cron', cron: schedule);
}

int _unitToMs(String unit) => switch (unit) {
  'second' => 1000,
  'minute' => 60 * 1000,
  'hour' => 60 * 60 * 1000,
  'day' => 24 * 60 * 60 * 1000,
  _ => 60 * 1000,
};

/// Convert schedule to human-readable string.
String scheduleToHuman(String schedule) {
  final config = parseSchedule(schedule);
  return switch (config.type) {
    'interval' => 'Every ${_msToHuman(config.intervalMs!)}',
    'delay' => 'After ${_msToHuman(config.delayMs!)}',
    'cron' => cronToHuman(config.cron ?? schedule),
    _ => schedule,
  };
}

String _msToHuman(int ms) {
  if (ms >= 86400000) return '${ms ~/ 86400000} day(s)';
  if (ms >= 3600000) return '${ms ~/ 3600000} hour(s)';
  if (ms >= 60000) return '${ms ~/ 60000} minute(s)';
  return '${ms ~/ 1000} second(s)';
}

// --- CronTask ---
