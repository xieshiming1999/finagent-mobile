// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'data_fetcher/api_stats.dart';
import 'data_fetcher/data_manager.dart';
import 'data_fetcher/http_utils.dart' as http_utils;
import 'data_fetcher/models.dart';
import 'log.dart';
import 'notification_queue.dart';

typedef DataTaskHttpFetch =
    Future<http.Response> Function(
      String url, {
      Map<String, String>? headers,
      Map<String, String>? queryParams,
      int maxAttempts,
    });

typedef DataTaskQuoteRead =
    Future<({List<StockQuote> data, String source})> Function(
      List<String> symbols,
    );

typedef DataTaskKlineRead =
    Future<({List<KlineBar> bars, String source})> Function(String symbol);

Future<http.Response> _defaultDataTaskFetch(
  String url, {
  Map<String, String>? headers,
  Map<String, String>? queryParams,
  int maxAttempts = 3,
}) {
  return http_utils.fetchWithRetry(
    url,
    headers: headers,
    queryParams: queryParams,
    maxAttempts: maxAttempts,
  );
}

enum DataTaskStatus { pending, running, completed, failed, cancelled }

class DataTask {
  final String id;
  final String type;
  final Map<String, dynamic> params;
  DataTaskStatus status;
  double progress;
  String? result;
  String? error;
  DateTime createdAt;
  DateTime? completedAt;

  DataTask({
    required this.id,
    required this.type,
    required this.params,
    this.status = DataTaskStatus.pending,
    this.progress = 0,
    this.result,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'params': params,
    'status': status.name,
    'progress': progress,
    'result': result,
    'error': error,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };

  factory DataTask.fromJson(Map<String, dynamic> j) => DataTask(
    id: j['id'] as String,
    type: j['type'] as String,
    params: j['params'] as Map<String, dynamic>? ?? {},
    status: DataTaskStatus.values.firstWhere(
      (s) => s.name == j['status'],
      orElse: () => DataTaskStatus.pending,
    ),
    progress: (j['progress'] as num?)?.toDouble() ?? 0,
    result: j['result'] as String?,
    error: j['error'] as String?,
    createdAt:
        DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
    completedAt: DateTime.tryParse(j['completedAt'] as String? ?? ''),
  );
}

class DataTaskEngine {
  final String basePath;
  NotificationQueue? notificationQueue;
  final List<DataTask> _tasks = [];
  final Map<String, DataTaskExecutor> _executors = {};
  bool _running = false;

  DataTaskEngine({
    required this.basePath,
    this.notificationQueue,
    Map<String, DataTaskExecutor>? executorsForTest,
  }) {
    if (executorsForTest != null) {
      _executors.addAll(executorsForTest);
    } else {
      _registerExecutors();
    }
  }

  void _registerExecutors() {
    final dataManager = DataManager(basePath: basePath);
    _executors['screen_advanced'] = ScreenAdvancedExecutor();
    _executors['batch_quote'] = BatchQuoteExecutor(dataManager: dataManager);
    _executors['batch_score'] = BatchScoreExecutor(dataManager: dataManager);
  }

  String get _storagePath => '$basePath/memory/data_tasks';
  String get _indexPath => '$_storagePath/index.json';

  void load() {
    final file = File(_indexPath);
    if (!file.existsSync()) return;
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      _tasks.addAll(
        list.map((e) => DataTask.fromJson(e as Map<String, dynamic>)),
      );
    } catch (_) {}
  }

  void _save() {
    final dir = Directory(_storagePath);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    File(_indexPath).writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_tasks.map((t) => t.toJson()).toList()),
    );
  }

  DataTask submit(String type, Map<String, dynamic> params) {
    final executor = _executors[type];
    if (executor == null) throw ArgumentError('Unknown task type: $type');

    final cached = _findCachedResult(type, params);
    if (cached != null) return cached;

    final id = '${type}_${DateTime.now().millisecondsSinceEpoch}';
    final task = DataTask(id: id, type: type, params: params);
    _tasks.add(task);
    _save();
    _scheduleExecution(task);
    return task;
  }

  DataTask? _findCachedResult(String type, Map<String, dynamic> params) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    return _tasks
        .where(
          (t) =>
              t.type == type &&
              t.status == DataTaskStatus.completed &&
              t.completedAt?.toIso8601String().substring(0, 10) == today &&
              jsonEncode(t.params) == jsonEncode(params),
        )
        .firstOrNull;
  }

  void _scheduleExecution(DataTask task) {
    if (_running) return;
    _running = true;
    _executeNext();
  }

  Future<void> _executeNext() async {
    final pending = _tasks
        .where((t) => t.status == DataTaskStatus.pending)
        .firstOrNull;
    if (pending == null) {
      _running = false;
      return;
    }

    pending.status = DataTaskStatus.running;
    _save();

    final executor = _executors[pending.type]!;
    final sw = Stopwatch()..start();
    try {
      final resultPath = '$_storagePath/${pending.id}.json';
      await executor.execute(
        params: pending.params,
        outputPath: resultPath,
        onProgress: (p) {
          pending.progress = p;
          _save();
        },
      );
      pending.status = DataTaskStatus.completed;
      pending.progress = 100;
      pending.result = resultPath;
      pending.completedAt = DateTime.now();

      notificationQueue?.enqueue(
        PendingNotification(
          prompt:
              '📊 数据任务完成: ${executor.describe(pending.params)}\n结果已保存,共 ${_readResultCount(resultPath)} 条数据。',
          source: 'data_task',
          priority: NotificationPriority.now,
        ),
      );
    } catch (e) {
      sw.stop();
      pending.status = DataTaskStatus.failed;
      pending.error = e.toString();
      log('DataTask', 'Failed ${pending.id}: $e');
      _recordTaskFailure(pending, sw.elapsedMilliseconds);
    }
    _save();
    _executeNext();
  }

  void _recordTaskFailure(DataTask task, int durationMs) {
    ApiStats.instance.record(
      source: _sourceForTask(task.type),
      method: 'TASK',
      url: 'data_task:${task.type}',
      statusCode: 0,
      durationMs: durationMs,
      success: false,
      error: task.error,
      responseSummary: jsonEncode({
        'taskId': task.id,
        'taskType': task.type,
        'params': task.params,
      }),
    );
  }

  String _sourceForTask(String type) => switch (type) {
    'screen_advanced' || 'batch_quote' || 'batch_score' => 'eastmoney',
    _ => 'data_task',
  };

  int _readResultCount(String path) {
    try {
      final json =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      return (json['data'] as List?)?.length ?? 0;
    } catch (_) {
      return 0;
    }
  }

  void cancel(String taskId) {
    final task = _tasks.where((t) => t.id == taskId).firstOrNull;
    if (task != null &&
        (task.status == DataTaskStatus.pending ||
            task.status == DataTaskStatus.running)) {
      task.status = DataTaskStatus.cancelled;
      _save();
    }
  }

  List<DataTask> list({DataTaskStatus? status}) {
    if (status != null) return _tasks.where((t) => t.status == status).toList();
    return List.unmodifiable(_tasks);
  }

  DataTask? get(String id) => _tasks.where((t) => t.id == id).firstOrNull;

  String? readResult(String taskId) {
    final task = get(taskId);
    if (task?.result == null) return null;
    try {
      return File(task!.result!).readAsStringSync();
    } catch (_) {
      return null;
    }
  }

  void resumePending() {
    final pending = _tasks
        .where(
          (t) =>
              t.status == DataTaskStatus.running ||
              t.status == DataTaskStatus.pending,
        )
        .toList();
    for (final t in pending) {
      if (t.status == DataTaskStatus.running) t.status = DataTaskStatus.pending;
    }
    if (pending.isNotEmpty) {
      _save();
      _scheduleExecution(pending.first);
    }
  }
}

abstract class DataTaskExecutor {
  Future<void> execute({
    required Map<String, dynamic> params,
    required String outputPath,
    required void Function(double progress) onProgress,
  });
  String describe(Map<String, dynamic> params);
}

class ScreenAdvancedExecutor extends DataTaskExecutor {
  ScreenAdvancedExecutor({DataTaskHttpFetch? fetch})
    : _fetch = fetch ?? _defaultDataTaskFetch;

  static const _baseUrl = 'https://data.eastmoney.com/dataapi/xuangu/list';
  static final _rng = Random();
  final DataTaskHttpFetch _fetch;

  @override
  String describe(Map<String, dynamic> params) {
    final conditions = params['conditions'] as List? ?? [];
    return '全市场筛选 (${conditions.length}个条件)';
  }

  @override
  Future<void> execute({
    required Map<String, dynamic> params,
    required String outputPath,
    required void Function(double progress) onProgress,
  }) async {
    final conditions = params['conditions'] as List? ?? [];
    final filter = _buildFilter(conditions);
    final allResults = <Map<String, dynamic>>[];
    var page = 1;
    const pageSize = 100;
    var totalPages = 1;

    while (page <= totalPages) {
      onProgress(page > 1 ? min((page / totalPages * 100), 99) : 5);

      final uri = Uri.parse(_baseUrl).replace(
        queryParameters: {
          'st': 'CHANGE_RATE',
          'sr': '-1',
          'ps': '$pageSize',
          'p': '$page',
          'sty':
              'SECUCODE,SECURITY_CODE,SECURITY_NAME_ABBR,CHANGE_RATE,NEW_PRICE,VOLUME_RATIO,TOTAL_MARKET_CAP,PE9,PB_NEW_MRQ,ROE_WEIGHT',
          'filter': filter,
          'source': 'SELECT_SECURITIES',
          'client': 'WEB',
        },
      );

      final resp = await _fetchWithRetry(uri);
      if (resp == null) {
        if (page == 1) {
          throw StateError(
            'EastMoney screen_advanced fetch failed before any rows were returned',
          );
        }
        break;
      }

      final json = jsonDecode(resp) as Map<String, dynamic>;
      final data = json['result']?['data'] as List? ?? [];
      final total = json['result']?['count'] as int? ?? 0;
      totalPages = (total / pageSize).ceil();

      for (final item in data) {
        allResults.add({
          'code': item['SECURITY_CODE'],
          'name': item['SECURITY_NAME_ABBR'],
          'price': item['NEW_PRICE'],
          'changePct': item['CHANGE_RATE'],
          'volumeRatio': item['VOLUME_RATIO'],
          'marketCap': item['TOTAL_MARKET_CAP'],
          'pe': item['PE9'],
          'pb': item['PB_NEW_MRQ'],
          'roe': item['ROE_WEIGHT'],
        });
      }

      if (data.isEmpty) break;
      page++;
      await Future.delayed(Duration(milliseconds: 1200 + _rng.nextInt(800)));
    }

    onProgress(100);
    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'type': 'screen_advanced',
        'conditions': conditions,
        'timestamp': DateTime.now().toIso8601String(),
        'count': allResults.length,
        'data': allResults,
      }),
    );
  }

  String _buildFilter(List conditions) {
    if (conditions.isEmpty) return '(MARKET+in+("沪A","深A"))';
    final parts = <String>['(MARKET+in+("沪A","深A"))'];
    for (final c in conditions) {
      final field = _mapField(c['field'] as String? ?? '');
      final op = c['op'] as String? ?? '>';
      final value = c['value'];
      if (field.isNotEmpty) parts.add('($field$op$value)');
    }
    return parts.join('+and+');
  }

  String _mapField(String field) => switch (field) {
    'pe' => 'PE9',
    'pb' => 'PB_NEW_MRQ',
    'roe' => 'ROE_WEIGHT',
    'changePct' => 'CHANGE_RATE',
    'marketCap' => 'TOTAL_MARKET_CAP',
    'volumeRatio' => 'VOLUME_RATIO',
    'price' => 'NEW_PRICE',
    _ => field.toUpperCase(),
  };

  Future<String?> _fetchWithRetry(Uri uri, {int retries = 3}) async {
    try {
      final resp = await _fetch(
        uri.toString(),
        headers: {
          'User-Agent': http_utils.configuredHttpUserAgent(),
          'Referer': 'https://data.eastmoney.com/xuangu/',
        },
        maxAttempts: retries,
      );
      if (resp.statusCode == 200) return resp.body;
      log('DataTask', 'HTTP ${resp.statusCode}: $uri');
    } catch (e) {
      log('DataTask', 'Fetch error: $e');
    }
    return null;
  }
}

class BatchQuoteExecutor extends DataTaskExecutor {
  BatchQuoteExecutor({DataManager? dataManager, DataTaskQuoteRead? readQuotes})
    : _readQuotes = readQuotes ?? (dataManager ?? DataManager()).getQuotes;

  final DataTaskQuoteRead _readQuotes;

  @override
  String describe(Map<String, dynamic> params) {
    final symbols = params['symbols'] as List? ?? [];
    return '批量行情 (${symbols.length}只)';
  }

  @override
  Future<void> execute({
    required Map<String, dynamic> params,
    required String outputPath,
    required void Function(double progress) onProgress,
  }) async {
    final symbols = (params['symbols'] as List?)?.cast<String>() ?? [];
    if (symbols.isEmpty) throw ArgumentError('symbols required');

    final results = <Map<String, dynamic>>[];
    var failedBatches = 0;
    const batchSize = 20;
    for (var i = 0; i < symbols.length; i += batchSize) {
      final batch = symbols.sublist(i, min(i + batchSize, symbols.length));
      try {
        final quotes = (await _readQuotes(batch)).data;
        if (quotes.isEmpty) {
          failedBatches++;
        }
        for (final quote in quotes) {
          results.add({
            'code': quote.code,
            'name': quote.name,
            'price': quote.price,
            'changePct': quote.changePct,
            'volume': quote.volume,
            'amount': quote.amount,
            'turnoverRate': quote.turnoverRate,
            'pe': quote.pe,
            'source': quote.source,
            if (quote.timestamp != null) 'timestamp': quote.timestamp,
            if (quote.fetchedAt != null) 'fetchedAt': quote.fetchedAt,
          });
        }
      } catch (e) {
        failedBatches++;
        log('DataTask', 'BatchQuote error batch $i: $e');
      }
      onProgress(min((i + batchSize) / symbols.length * 100, 99));
      if (i + batchSize < symbols.length)
        await Future.delayed(const Duration(milliseconds: 500));
    }

    if (results.isEmpty && failedBatches > 0) {
      throw StateError(
        'EastMoney batch_quote returned no rows after $failedBatches failed batch(es)',
      );
    }

    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'type': 'batch_quote',
        'timestamp': DateTime.now().toIso8601String(),
        'count': results.length,
        'failedBatches': failedBatches,
        'dataInterface': 'stock.quote',
        'data': results,
      }),
    );
  }
}

class BatchScoreExecutor extends DataTaskExecutor {
  BatchScoreExecutor({DataManager? dataManager, DataTaskKlineRead? readKline})
    : _readKline = readKline ?? (dataManager ?? DataManager()).getKline;

  final DataTaskKlineRead _readKline;

  @override
  String describe(Map<String, dynamic> params) {
    final symbols = params['symbols'] as List? ?? [];
    return '批量评分 (${symbols.length}只)';
  }

  @override
  Future<void> execute({
    required Map<String, dynamic> params,
    required String outputPath,
    required void Function(double progress) onProgress,
  }) async {
    final symbols = (params['symbols'] as List?)?.cast<String>() ?? [];
    if (symbols.isEmpty) throw ArgumentError('symbols required');

    final results = <Map<String, dynamic>>[];
    var failedSymbols = 0;
    for (var i = 0; i < symbols.length; i++) {
      final symbol = symbols[i];
      try {
        final bars = (await _readKline(symbol)).bars;
        if (bars.length >= 30) {
          final closes = bars.map((bar) => bar.close).toList();
          final score = _simpleScore(closes);
          results.add({
            'symbol': symbol,
            'score': score,
            'bars': bars.length,
            'sourceDate': bars.last.date,
          });
        } else if (bars.isEmpty) {
          failedSymbols++;
        }
      } catch (e) {
        failedSymbols++;
        log('DataTask', 'BatchScore error $symbol: $e');
      }
      onProgress(min((i + 1) / symbols.length * 100, 99));
      if (i < symbols.length - 1)
        await Future.delayed(const Duration(milliseconds: 1500));
    }

    if (results.isEmpty && failedSymbols > 0) {
      throw StateError(
        'EastMoney batch_score returned no rows after $failedSymbols failed symbol(s)',
      );
    }

    results.sort((a, b) => (b['score'] as int).compareTo(a['score'] as int));

    final output = File(outputPath);
    output.parent.createSync(recursive: true);
    output.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
        'type': 'batch_score',
        'timestamp': DateTime.now().toIso8601String(),
        'count': results.length,
        'failedSymbols': failedSymbols,
        'dataInterface': 'stock.daily_kline',
        'data': results,
      }),
    );
  }

  static int _simpleScore(List<double> closes) {
    if (closes.length < 30) return 0;
    var score = 0;
    final n = closes.length;
    final ma5 = closes.sublist(n - 5).reduce((a, b) => a + b) / 5;
    final ma10 = closes.sublist(n - 10).reduce((a, b) => a + b) / 10;
    final ma20 = closes.sublist(n - 20).reduce((a, b) => a + b) / 20;
    final price = closes.last;

    if (ma5 > ma10 && ma10 > ma20) {
      score += 30;
    } else if (ma5 > ma20)
      score += 18;
    else if (ma5 < ma10 && ma10 < ma20)
      score += 0;
    else
      score += 10;

    final bias = (price - ma5) / ma5 * 100;
    if (bias <= 0 && bias >= -3) {
      score += 20;
    } else if (bias > 0 && bias <= 2)
      score += 16;
    else if (bias > 5)
      score += 4;
    else
      score += 10;

    final change = (price - closes[n - 2]) / closes[n - 2] * 100;
    if (change > 0 && change < 5) {
      score += 15;
    } else if (change > 5)
      score += 8;
    else
      score += 5;

    score += 25;
    return min(score, 100);
  }
}
