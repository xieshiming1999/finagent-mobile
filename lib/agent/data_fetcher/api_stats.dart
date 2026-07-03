import 'dart:developer' as developer;
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

class ApiRequestRecord {
  final int? id;
  final String source;
  final String method;
  final String url;
  final int statusCode;
  final int durationMs;
  final bool success;
  final String? failureClass;
  final String? error;
  final String? responseSummary;
  final DateTime requestedAt;

  ApiRequestRecord({
    this.id,
    required this.source,
    required this.method,
    required this.url,
    required this.statusCode,
    required this.durationMs,
    required this.success,
    this.failureClass,
    this.error,
    this.responseSummary,
    required this.requestedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'method': method,
    'url': url,
    'statusCode': statusCode,
    'durationMs': durationMs,
    'success': success,
    'failureClass': failureClass,
    'error': error,
    'responseSummary': responseSummary,
    'requestedAt': requestedAt.toIso8601String(),
  };
}

class SourceSummary {
  final String source;
  final int totalRequests;
  final int successCount;
  final int failCount;
  final double failRate;
  final double avgLatencyMs;
  final double p95LatencyMs;
  final DateTime? lastRequest;
  final String? lastError;
  final String? lastFailureClass;

  SourceSummary({
    required this.source,
    required this.totalRequests,
    required this.successCount,
    required this.failCount,
    required this.failRate,
    required this.avgLatencyMs,
    required this.p95LatencyMs,
    this.lastRequest,
    this.lastError,
    this.lastFailureClass,
  });
}

class ApiStats {
  static final instance = ApiStats._();
  ApiStats._();

  Database? _db;
  bool _initialized = false;

  void init(String basePath) {
    if (_initialized) return;
    try {
      final dir = Directory('$basePath/logs');
      dir.createSync(recursive: true);
      _db = sqlite3.open('${dir.path}/api_stats.db');
      _db!.execute('''
        CREATE TABLE IF NOT EXISTS api_requests (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          source TEXT NOT NULL,
          method TEXT NOT NULL,
          url TEXT NOT NULL,
          status_code INTEGER NOT NULL,
          duration_ms INTEGER NOT NULL,
          success INTEGER NOT NULL,
          failure_class TEXT,
          error TEXT,
          response_summary TEXT,
          requested_at TEXT NOT NULL
        )
      ''');
      final columns = _db!.select('PRAGMA table_info(api_requests)');
      if (!columns.any((row) => row['name'] == 'failure_class')) {
        _db!.execute('ALTER TABLE api_requests ADD COLUMN failure_class TEXT');
      }
      _db!.execute(
        'CREATE INDEX IF NOT EXISTS idx_requested_at ON api_requests(requested_at)',
      );
      _db!.execute(
        'CREATE INDEX IF NOT EXISTS idx_source ON api_requests(source)',
      );
      _db!.execute(
        'CREATE INDEX IF NOT EXISTS idx_source_time ON api_requests(source, requested_at)',
      );
      _db!.execute(
        'CREATE INDEX IF NOT EXISTS idx_source_success ON api_requests(source, success, requested_at)',
      );
      _initialized = true;
      _cleanup();
    } catch (e) {
      _db = null;
      developer.log('init failed: $e', name: 'ApiStats');
    }
  }

  void resetForTest() {
    try {
      _db?.close();
    } catch (_) {}
    _db = null;
    _initialized = false;
  }

  void record({
    required String source,
    required String method,
    required String url,
    required int statusCode,
    required int durationMs,
    required bool success,
    String? failureClass,
    String? error,
    String? responseSummary,
  }) {
    if (_db == null) {
      developer.log('record skipped: db not initialized', name: 'ApiStats');
      return;
    }
    try {
      final summary = responseSummary != null && responseSummary.length > 200
          ? responseSummary.substring(0, 200)
          : responseSummary;
      _db!.execute(
        'INSERT INTO api_requests (source, method, url, status_code, duration_ms, success, failure_class, error, response_summary, requested_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        [
          source,
          method,
          url,
          statusCode,
          durationMs,
          success ? 1 : 0,
          failureClass,
          error,
          summary,
          DateTime.now().toIso8601String(),
        ],
      );
    } catch (_) {}
  }

  List<ApiRequestRecord> getRecent({
    Duration range = const Duration(minutes: 30),
    String? source,
  }) {
    if (_db == null) return [];
    try {
      final since = DateTime.now().subtract(range).toIso8601String();
      final ResultSet result;
      if (source != null) {
        result = _db!.select(
          'SELECT * FROM api_requests WHERE requested_at > ? AND source = ? ORDER BY requested_at DESC LIMIT 200',
          [since, source],
        );
      } else {
        result = _db!.select(
          'SELECT * FROM api_requests WHERE requested_at > ? ORDER BY requested_at DESC LIMIT 200',
          [since],
        );
      }
      return result.map(_rowToRecord).toList();
    } catch (_) {
      return [];
    }
  }

  List<ApiRequestRecord> getRecentFailures({
    Duration range = const Duration(minutes: 30),
    String? source,
    int limit = 50,
  }) {
    if (_db == null) return [];
    try {
      final since = DateTime.now().subtract(range).toIso8601String();
      final boundedLimit = limit.clamp(1, 200);
      final ResultSet result;
      if (source != null && source.trim().isNotEmpty) {
        result = _db!.select(
          'SELECT * FROM api_requests WHERE requested_at > ? AND source = ? AND success = 0 ORDER BY requested_at DESC LIMIT ?',
          [since, source.trim(), boundedLimit],
        );
      } else {
        result = _db!.select(
          'SELECT * FROM api_requests WHERE requested_at > ? AND success = 0 ORDER BY requested_at DESC LIMIT ?',
          [since, boundedLimit],
        );
      }
      return result.map(_rowToRecord).toList();
    } catch (_) {
      return [];
    }
  }

  List<SourceSummary> getSummary({Duration range = const Duration(hours: 1)}) {
    if (_db == null) return [];
    try {
      final since = DateTime.now().subtract(range).toIso8601String();
      final result = _db!.select(
        '''
        SELECT source,
               COUNT(*) as total,
               SUM(CASE WHEN success = 1 THEN 1 ELSE 0 END) as successes,
               SUM(CASE WHEN success = 0 THEN 1 ELSE 0 END) as failures,
               AVG(duration_ms) as avg_latency,
               MAX(requested_at) as last_req
        FROM api_requests
        WHERE requested_at > ?
        GROUP BY source
        ORDER BY total DESC
      ''',
        [since],
      );

      return result.map((row) {
        final source = row['source'] as String;
        final total = row['total'] as int;
        final successes = row['successes'] as int;
        final failures = row['failures'] as int;
        final avgLatency = (row['avg_latency'] as num?)?.toDouble() ?? 0;
        final lastReq = DateTime.tryParse(row['last_req'] as String? ?? '');

        // Get P95 latency
        final p95Result = _db!.select(
          'SELECT duration_ms FROM api_requests WHERE requested_at > ? AND source = ? ORDER BY duration_ms ASC',
          [since, source],
        );
        final durations = p95Result
            .map((r) => r['duration_ms'] as int)
            .toList();
        final p95 = durations.isNotEmpty
            ? durations[(durations.length * 0.95).floor().clamp(
                    0,
                    durations.length - 1,
                  )]
                  .toDouble()
            : 0.0;

        // Get last error
        final errResult = _db!.select(
          'SELECT error, failure_class FROM api_requests WHERE requested_at > ? AND source = ? AND success = 0 ORDER BY requested_at DESC LIMIT 1',
          [since, source],
        );
        final lastError = errResult.isNotEmpty
            ? errResult.first['error'] as String?
            : null;
        final lastFailureClass = errResult.isNotEmpty
            ? errResult.first['failure_class'] as String?
            : null;

        return SourceSummary(
          source: source,
          totalRequests: total,
          successCount: successes,
          failCount: failures,
          failRate: total > 0 ? failures / total : 0,
          avgLatencyMs: avgLatency,
          p95LatencyMs: p95,
          lastRequest: lastReq,
          lastError: lastError,
          lastFailureClass: lastFailureClass,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  void clear() {
    if (_db == null) return;
    try {
      _db!.execute('DELETE FROM api_requests');
    } catch (_) {}
  }

  void _cleanup() {
    if (_db == null) return;
    try {
      final cutoff = DateTime.now()
          .subtract(const Duration(days: 7))
          .toIso8601String();
      _db!.execute('DELETE FROM api_requests WHERE requested_at < ?', [cutoff]);
    } catch (_) {}
  }

  ApiRequestRecord _rowToRecord(Row row) {
    return ApiRequestRecord(
      id: row['id'] as int?,
      source: row['source'] as String,
      method: row['method'] as String,
      url: row['url'] as String,
      statusCode: row['status_code'] as int,
      durationMs: row['duration_ms'] as int,
      success: (row['success'] as int) == 1,
      failureClass: row['failure_class'] as String?,
      error: row['error'] as String?,
      responseSummary: row['response_summary'] as String?,
      requestedAt:
          DateTime.tryParse(row['requested_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  /// Extract source name from URL host
  static String sourceFromUrl(String url) {
    try {
      final host = Uri.parse(url).host.toLowerCase();
      if (host.contains('eastmoney')) return 'eastmoney';
      if (host.contains('sina')) return 'sina';
      if (host.contains('tencent') || host.contains('gtimg')) return 'tencent';
      if (host.contains('tushare')) return 'tushare';
      if (host.contains('wind.com.cn')) return 'wind';
      if (host.contains('xueqiu')) return 'xueqiu';
      if (host.contains('brave')) return 'brave';
      if (host.contains('tavily')) return 'tavily';
      if (host.contains('tradingview')) return 'tradingview';
      if (host.contains('yahoo') || host.contains('finance.yahoo')) {
        return 'yahoo';
      }
      return host.split('.').reversed.skip(1).firstOrNull ?? host;
    } catch (_) {
      return 'unknown';
    }
  }
}
