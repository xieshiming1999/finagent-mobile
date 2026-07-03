import 'dart:io';

import 'data_fetcher/api_stats.dart';
import 'data_fetcher/reusable_data_store.dart';
import 'data_task_engine.dart';

enum FinanceDoctorStatus { ok, warning, critical }

class FinanceDoctorCheck {
  final String id;
  final FinanceDoctorStatus status;
  final String detail;
  final String? nextStep;
  final Map<String, Object?> metrics;

  const FinanceDoctorCheck({
    required this.id,
    required this.status,
    required this.detail,
    this.nextStep,
    this.metrics = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.name,
    'detail': detail,
    'nextStep': nextStep,
    'metrics': metrics,
  };
}

class FinanceDoctorReport {
  final FinanceDoctorStatus status;
  final DateTime generatedAt;
  final String summary;
  final List<FinanceDoctorCheck> checks;

  const FinanceDoctorReport({
    required this.status,
    required this.generatedAt,
    required this.summary,
    required this.checks,
  });

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'generatedAt': generatedAt.toIso8601String(),
    'summary': summary,
    'checks': checks.map((check) => check.toJson()).toList(),
  };
}

FinanceDoctorReport buildFinanceDoctorReport({
  required String basePath,
  DataTaskEngine? dataTaskEngine,
  Duration apiWindow = const Duration(minutes: 30),
}) {
  final checks = <FinanceDoctorCheck>[];
  _addRuntimeChecks(checks, basePath);
  _addApiFailureCheck(checks, apiWindow);
  if (dataTaskEngine != null) _addDataTaskCheck(checks, dataTaskEngine);
  _addReusableChecks(checks, basePath);
  return _finalize(checks);
}

void _addRuntimeChecks(List<FinanceDoctorCheck> checks, String basePath) {
  final runtime = _inspectDirectory(basePath);
  checks.add(
    FinanceDoctorCheck(
      id: 'runtime_paths',
      status: runtime.ok
          ? FinanceDoctorStatus.ok
          : FinanceDoctorStatus.critical,
      detail: runtime.ok
          ? 'Runtime directory is readable and writable.'
          : runtime.detail,
      nextStep: runtime.ok
          ? null
          : 'Fix app runtime directory permissions before running data or automation tasks.',
      metrics: {
        'path': basePath,
        'readable': runtime.readable,
        'writable': runtime.writable,
      },
    ),
  );

  final memory = _inspectDirectory('$basePath/memory');
  checks.add(
    FinanceDoctorCheck(
      id: 'memory_paths',
      status: memory.ok ? FinanceDoctorStatus.ok : FinanceDoctorStatus.warning,
      detail: memory.ok
          ? 'Memory directory is readable and writable.'
          : memory.detail,
      nextStep: memory.ok
          ? null
          : 'Open the app once or repair memory directory permissions before relying on local state.',
      metrics: {
        'path': '$basePath/memory',
        'readable': memory.readable,
        'writable': memory.writable,
      },
    ),
  );

  final sessionsDir = '$basePath/sessions';
  final historyDir = '$sessionsDir/history';
  final archiveDir = '$sessionsDir/archive';
  final currentPath = '$sessionsDir/current.jsonl';
  final sessions = _inspectDirectory(sessionsDir);
  final history = _inspectDirectory(historyDir);
  final archive = _inspectDirectory(archiveDir);
  final current = _inspectOptionalSessionFile(currentPath);
  final ok = sessions.ok && history.ok && archive.ok && current.ok;
  checks.add(
    FinanceDoctorCheck(
      id: 'session_history',
      status: ok ? FinanceDoctorStatus.ok : FinanceDoctorStatus.warning,
      detail: ok
          ? 'Session working context, archive, and audit history paths are readable.'
          : [
              sessions.ok ? null : 'sessions: ${sessions.detail}',
              history.ok ? null : 'history: ${history.detail}',
              archive.ok ? null : 'archive: ${archive.detail}',
              current.ok ? null : 'current: ${current.detail}',
            ].whereType<String>().join('; '),
      nextStep: ok
          ? null
          : 'Open a session once or repair session/history directory state before relying on resume or history.',
      metrics: {
        'sessionsDir': sessionsDir,
        'historyDir': historyDir,
        'archiveDir': archiveDir,
        'currentPath': currentPath,
        'currentExists': current.exists,
      },
    ),
  );
}

void _addApiFailureCheck(List<FinanceDoctorCheck> checks, Duration window) {
  final failures = ApiStats.instance.getRecentFailures(
    range: window,
    limit: 100,
  );
  if (failures.isEmpty) {
    checks.add(
      const FinanceDoctorCheck(
        id: 'api_failures',
        status: FinanceDoctorStatus.ok,
        detail: 'No API failures in the recent debug window.',
      ),
    );
    return;
  }
  final bySource = <String, int>{};
  for (final failure in failures) {
    bySource[failure.source] = (bySource[failure.source] ?? 0) + 1;
  }
  final top = bySource.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topText = top.take(3).map((e) => '${e.key}:${e.value}').join(', ');
  checks.add(
    FinanceDoctorCheck(
      id: 'api_failures',
      status: failures.length >= 5
          ? FinanceDoctorStatus.critical
          : FinanceDoctorStatus.warning,
      detail:
          '${failures.length} failure(s) in the recent debug window${topText.isEmpty ? '' : ' ($topText)'}.',
      nextStep:
          'Inspect recent API failures and retry only the smallest failed dataset after a source recovers.',
      metrics: {'failures': failures.length, 'top': topText},
    ),
  );
}

void _addDataTaskCheck(List<FinanceDoctorCheck> checks, DataTaskEngine engine) {
  final tasks = engine.list();
  final pending = tasks
      .where((task) => task.status == DataTaskStatus.pending)
      .length;
  final running = tasks
      .where((task) => task.status == DataTaskStatus.running)
      .length;
  final failed = tasks
      .where((task) => task.status == DataTaskStatus.failed)
      .length;
  checks.add(
    FinanceDoctorCheck(
      id: 'data_tasks',
      status: failed > 0 ? FinanceDoctorStatus.warning : FinanceDoctorStatus.ok,
      detail: '$pending pending, $running running, $failed failed task(s).',
      nextStep: failed > 0
          ? 'Retry the smallest failed data task after checking the matching provider.'
          : null,
      metrics: {'pending': pending, 'running': running, 'failed': failed},
    ),
  );
}

void _addReusableChecks(List<FinanceDoctorCheck> checks, String basePath) {
  final summary = ReusableDataStore(basePath).reusableSummary();
  if (summary['available'] != true) {
    checks.add(
      const FinanceDoctorCheck(
        id: 'reusable_store',
        status: FinanceDoctorStatus.warning,
        detail: 'Reusable data store is unavailable.',
        nextStep:
            'Open Data or run a targeted finance data task before relying on local cache.',
      ),
    );
    return;
  }
  for (final row in const [
    ('stock_identity', 'stock_list', 'stock code/name search'),
    ('fund_identity', 'fund_list', 'fund search and Fund Pulse'),
    ('quote_cache', 'quote_snapshot', 'stock/fund pulse quotes'),
    ('kline_cache', 'kline_daily', 'backtests and chart reuse'),
  ]) {
    final value = summary[row.$2];
    final table = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    final count = (table['rows'] as num?)?.toInt() ?? 0;
    checks.add(
      FinanceDoctorCheck(
        id: row.$1,
        status: count > 0
            ? FinanceDoctorStatus.ok
            : FinanceDoctorStatus.warning,
        detail:
            '${row.$2}: $count row(s)${table['latest'] == null ? '' : ', latest ${table['latest']}'}.',
        nextStep: count > 0
            ? null
            : 'Run the targeted feed for ${row.$3} when data is needed.',
        metrics: {
          'table': row.$2,
          'count': count,
          'latest': table['latest'],
          'purpose': row.$3,
        },
      ),
    );
  }
}

FinanceDoctorReport _finalize(List<FinanceDoctorCheck> checks) {
  final status =
      checks.any((check) => check.status == FinanceDoctorStatus.critical)
      ? FinanceDoctorStatus.critical
      : checks.any((check) => check.status == FinanceDoctorStatus.warning)
      ? FinanceDoctorStatus.warning
      : FinanceDoctorStatus.ok;
  final critical = checks
      .where((check) => check.status == FinanceDoctorStatus.critical)
      .length;
  final warning = checks
      .where((check) => check.status == FinanceDoctorStatus.warning)
      .length;
  return FinanceDoctorReport(
    status: status,
    generatedAt: DateTime.now(),
    summary: status == FinanceDoctorStatus.ok
        ? 'All local diagnostics passed.'
        : '$critical critical, $warning warning check(s).',
    checks: checks,
  );
}

_PathInspection _inspectDirectory(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    return _PathInspection(
      ok: false,
      detail: '$path is missing.',
      readable: false,
      writable: false,
    );
  }
  final readable = _canList(dir);
  final writable = _canWrite(dir);
  return _PathInspection(
    ok: readable && writable,
    detail: readable && writable
        ? '$path is readable and writable.'
        : '$path permission check failed.',
    readable: readable,
    writable: writable,
  );
}

bool _canList(Directory dir) {
  try {
    dir.listSync(followLinks: false);
    return true;
  } catch (_) {
    return false;
  }
}

bool _canWrite(Directory dir) {
  final path = '${dir.path}/.doctor_write_test';
  try {
    final file = File(path)..writeAsStringSync('ok');
    file.deleteSync();
    return true;
  } catch (_) {
    try {
      File(path).deleteSync();
    } catch (_) {}
    return false;
  }
}

_FileInspection _inspectOptionalSessionFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return _FileInspection(
      ok: true,
      exists: false,
      detail: '$path is not present yet.',
    );
  }
  try {
    final stat = file.statSync();
    if (stat.type != FileSystemEntityType.file) {
      return _FileInspection(
        ok: false,
        exists: true,
        detail: '$path is not a file.',
      );
    }
    String? firstLine;
    for (final line in file.readAsLinesSync()) {
      if (line.trim().isNotEmpty) {
        firstLine = line;
        break;
      }
    }
    if (firstLine == null) {
      return _FileInspection(
        ok: true,
        exists: true,
        detail: '$path is empty and will be recreated on next session write.',
      );
    }
    if (!firstLine.contains('"type":"session_meta"')) {
      return _FileInspection(
        ok: false,
        exists: true,
        detail: '$path does not start with session_meta.',
      );
    }
    return _FileInspection(
      ok: true,
      exists: true,
      detail: '$path is readable and has session metadata.',
    );
  } catch (e) {
    return _FileInspection(
      ok: false,
      exists: true,
      detail: '$path cannot be inspected: $e',
    );
  }
}

class _PathInspection {
  final bool ok;
  final String detail;
  final bool readable;
  final bool writable;

  const _PathInspection({
    required this.ok,
    required this.detail,
    required this.readable,
    required this.writable,
  });
}

class _FileInspection {
  final bool ok;
  final bool exists;
  final String detail;

  const _FileInspection({
    required this.ok,
    required this.exists,
    required this.detail,
  });
}
