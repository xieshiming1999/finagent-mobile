import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_js/flutter_js.dart';

import 'bridge/bridge_js.dart';
import 'data_fetcher/reusable_data_store.dart';
import 'http_bridge.dart';
import 'log.dart';
import 'monitor.dart';
import 'ui_notification.dart';
import '../shared/api_config.dart';

// Reference: monitor_design.md

/// Callback fired when a monitor alert triggers (for haptic + UI badge).
typedef MonitorAlertCallback = void Function(String monitorId, String message);

/// Executes monitor scripts on a timer and updates MonitorStore.
///
/// JS execution model: since flutter_js (QuickJS) is synchronous,
/// we use a two-phase approach:
///   Phase 1 (Dart): execute all callService() requests declared in script
///   Phase 2 (JS):   inject results as variables, run processing logic
///
/// Monitor scripts use a synchronous `callService(path, params)` bridge
/// that returns cached results pre-fetched by Dart.
class MonitorScheduler {
  final MonitorStore store;
  final String serviceBaseUrl;
  final String basePath;

  /// Called when a monitor fires an alert (for haptic feedback).
  MonitorAlertCallback? onAlert;

  /// Notification store for persisting alerts visible to user.
  UINotificationStore? notificationStore;

  /// Called when a monitor script sends a message to the agent via Bridge.sendToAgent().
  void Function(String monitorName, String message, Map<String, dynamic> data)?
  onAgentMessage;
  ApiConfigStore? apiConfig;

  Timer? _timer;
  JavascriptRuntime? _jsRuntime;
  bool _ticking = false;
  static const _tickInterval = Duration(seconds: 15);
  static const _scriptTimeout = Duration(seconds: 10);

  final Map<String, WebSocket> _wsConnections = {};
  final Map<String, Timer> _wsReconnectTimers = {};
  final Map<String, _WsBridgeConfig> _wsBridgeConfigs = {};
  final Map<String, Map<String, String>> _pushHandlers =
      {}; // monitorId → {channel → handlerJs}

  MonitorScheduler({
    required this.store,
    required this.serviceBaseUrl,
    required this.basePath,
    this.onAlert,
  });

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_tickInterval, (_) => tick());
    log('MonitorScheduler', 'Started (${store.count} monitors)');
    tick();
    _connectWebSocketMonitors();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _jsRuntime?.dispose();
    _jsRuntime = null;
    _disconnectAllWebSockets();
    log('MonitorScheduler', 'Stopped');
  }

  void _connectWebSocketMonitors() {
    for (final m in store.monitors) {
      if (m.enabled && m.streamUrl != null && m.streamUrl!.isNotEmpty) {
        _connectWebSocket(m);
      }
    }
  }

  void _disconnectAllWebSockets() {
    for (final ws in _wsConnections.values) {
      ws.close();
    }
    _wsConnections.clear();
    for (final t in _wsReconnectTimers.values) {
      t.cancel();
    }
    _wsReconnectTimers.clear();
  }

  Future<void> _connectWebSocket(Monitor monitor) async {
    if (_wsConnections.containsKey(monitor.id)) return;
    try {
      final ws = await WebSocket.connect(monitor.streamUrl!);
      _wsConnections[monitor.id] = ws;
      log(
        'MonitorScheduler',
        'WebSocket connected: ${monitor.name} → ${monitor.streamUrl}',
      );

      ws.listen(
        (data) => _handleWebSocketMessage(monitor, data),
        onError: (e) {
          log('MonitorScheduler', 'WebSocket error (${monitor.name}): $e');
          _scheduleReconnect(monitor);
        },
        onDone: () {
          log('MonitorScheduler', 'WebSocket closed (${monitor.name})');
          _wsConnections.remove(monitor.id);
          _scheduleReconnect(monitor);
        },
      );
    } catch (e) {
      log('MonitorScheduler', 'WebSocket connect failed (${monitor.name}): $e');
      _scheduleReconnect(monitor);
    }
  }

  void _scheduleReconnect(Monitor monitor) {
    _wsReconnectTimers[monitor.id]?.cancel();
    _wsReconnectTimers[monitor.id] = Timer(const Duration(seconds: 30), () {
      _wsReconnectTimers.remove(monitor.id);
      if (monitor.enabled && monitor.streamUrl != null) {
        _connectWebSocket(monitor);
      }
    });
  }

  void _handleWebSocketMessage(Monitor monitor, dynamic rawData) {
    try {
      final data = rawData is String
          ? jsonDecode(rawData) as Map<String, dynamic>
          : <String, dynamic>{};
      monitor.lastResult = data;
      monitor.lastRunTime = DateTime.now();
      monitor.lastError = null;

      if (monitor.condition != null && monitor.condition!.isNotEmpty) {
        final triggered = _evaluateConditionSync(monitor, data);
        if (triggered && !monitor.conditionTriggered) {
          monitor.conditionTriggered = true;
          _emitAlert(monitor, data);
        } else if (!triggered) {
          monitor.conditionTriggered = false;
        }
      }

      store.save();
      store.onChanged?.call();
    } catch (e) {
      monitor.lastError = e.toString();
      log('MonitorScheduler', 'WebSocket message error (${monitor.name}): $e');
    }
  }

  bool _evaluateConditionSync(Monitor monitor, Map<String, dynamic> data) {
    try {
      _jsRuntime ??= getJavascriptRuntime();
      final js = _jsRuntime!;
      js.evaluate('var data = ${jsonEncode(data)};');
      final result = js.evaluate('(${monitor.condition})');
      return result.stringResult == 'true';
    } catch (e) {
      log('MonitorScheduler', 'Condition eval error (${monitor.name}): $e');
      return false;
    }
  }

  /// Execute all due monitors. Called every tick.
  /// HTTP pre-fetches run in parallel; JS execution is serial (shared runtime).
  Future<void> tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _tickImpl();
    } finally {
      _ticking = false;
    }
  }

  Future<void> _tickImpl() async {
    final now = DateTime.now();
    final due = <Monitor>[];
    for (final monitor in store.monitors) {
      if (!monitor.enabled) continue;
      if (monitor.streamUrl != null && monitor.streamUrl!.isNotEmpty) continue;
      if (monitor.lastRunTime != null) {
        final elapsed = now.difference(monitor.lastRunTime!);
        if (elapsed < monitor.interval) continue;
      }
      due.add(monitor);
    }
    if (due.isEmpty) return;

    // Phase 1: parallel HTTP pre-fetch for all due monitors
    final fetchResults = await Future.wait(
      due.map(
        (m) => _prefetchServiceCalls(
          m.script,
        ).catchError((_) => <String, dynamic>{}),
      ),
    );

    // Phase 2: serial JS execution (QuickJS is single-threaded)
    for (var i = 0; i < due.length; i++) {
      await _executeMonitor(due[i], prefetched: fetchResults[i]);
    }
  }

  /// Execute a single monitor's script. Also used for test-run on creation.
  Future<Map<String, dynamic>> executeOnce(
    Monitor monitor, {
    bool forceAgentNotification = false,
  }) async {
    return _executeMonitor(
      monitor,
      persist: false,
      forceAgentNotification: forceAgentNotification,
    );
  }

  Future<Map<String, dynamic>> _executeMonitor(
    Monitor monitor, {
    bool persist = true,
    Map<String, dynamic>? prefetched,
    bool forceAgentNotification = false,
  }) async {
    try {
      final result = await _runScript(
        monitor,
        prefetched: prefetched,
        forceAgentNotification: forceAgentNotification,
      );

      if (persist) {
        store.updateResult(monitor.id, result, monitor.state);
      } else {
        monitor.lastResult = result;
        monitor.lastRunTime = DateTime.now();
        monitor.lastError = null;
      }

      // Evaluate alert condition with edge detection (only fire on transition)
      if (monitor.condition != null && monitor.condition!.isNotEmpty) {
        final triggered = _evaluateCondition(
          result,
          monitor.state,
          monitor.condition!,
        );
        if (triggered && !monitor.conditionTriggered) {
          monitor.conditionTriggered = true;
          _emitAlert(monitor, result);
        } else if (!triggered && monitor.conditionTriggered) {
          monitor.conditionTriggered = false;
        }
      }

      return result;
    } catch (e) {
      final error = e.toString();
      if (persist) {
        store.updateError(monitor.id, error);
      } else {
        monitor.lastError = error;
      }
      log('MonitorScheduler', '${monitor.name} failed: $error');
      rethrow;
    }
  }

  /// Run a monitor script via flutter_js with callService bridge.
  Future<Map<String, dynamic>> _runScript(
    Monitor monitor, {
    Map<String, dynamic>? prefetched,
    bool forceAgentNotification = false,
  }) async {
    _jsRuntime ??= getJavascriptRuntime();
    final js = _jsRuntime!;

    // Use pre-fetched results if available, otherwise fetch now
    final fetchResults =
        prefetched ?? await _prefetchServiceCalls(monitor.script);

    // Inject state and bridge functions
    final state = Map<String, dynamic>.from(monitor.state);
    if (forceAgentNotification) {
      state.remove('lastPortfolioReviewKey');
    }

    js.evaluate('''
      var state = ${jsonEncode(state)};
      var __fetchCache = ${jsonEncode(fetchResults)};
      var __sideEffects = { notifications: [], logs: [] };
      var __apiConfig = ${jsonEncode(apiConfig?.toMap() ?? {})};
      var Bridge = {};
      ${BridgeJs.httpBridge}
      ${BridgeJs.fileBridgeCache}
      ${BridgeJs.dataFunctions}
      ${BridgeJs.statsFunctions}
      ${BridgeJs.consoleSideEffects}
      Bridge.sendToMonitor = function(monitorId, channel, data) {
        if (!__sideEffects.monitorPush) __sideEffects.monitorPush = [];
        __sideEffects.monitorPush.push({ monitorId: monitorId, channel: channel, data: data || {} });
      };
      Bridge.ws = function(url, options) {
        if (!__sideEffects.ws) __sideEffects.ws = [];
        var opts = options || {};
        __sideEffects.ws.push({
          url: url,
          onMessage: opts.onMessage ? '(' + opts.onMessage.toString() + ')' : null,
          onOpen: opts.onOpen || null
        });
      };
      Bridge.onPush = function(channel, handler) {
        if (!__sideEffects.pushHandlers) __sideEffects.pushHandlers = [];
        __sideEffects.pushHandlers.push({
          channel: channel,
          handler: handler ? '(' + handler.toString() + ')' : null
        });
      };
    ''');

    // Wrap script in an IIFE that returns JSON + side effects
    final wrappedScript =
        '''
      (function() {
        try {
          var __fn = function() { ${monitor.script} };
          var __result = __fn();
          return JSON.stringify({ ok: true, result: __result, state: state, sideEffects: __sideEffects });
        } catch(e) {
          return JSON.stringify({ ok: false, error: e.message || String(e), sideEffects: __sideEffects });
        }
      })()
    ''';

    final jsResult = js.evaluate(wrappedScript);
    final resultStr = jsResult.stringResult;

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(resultStr) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('Script returned invalid JSON: $resultStr');
    }

    if (parsed['ok'] != true) {
      throw Exception(parsed['error'] ?? 'Unknown script error');
    }

    // Update state from JS
    if (parsed['state'] is Map) {
      monitor.state = Map<String, dynamic>.from(parsed['state'] as Map);
    }

    // Process side effects (notifications, logs)
    _processSideEffects(monitor, parsed['sideEffects']);

    // Process WebSocket registrations from Bridge.ws()
    if (parsed['sideEffects'] is Map) {
      _processWsRegistrations(
        monitor,
        parsed['sideEffects'] as Map<String, dynamic>,
      );
      _processFileOps(parsed['sideEffects'] as Map<String, dynamic>);
      _processPushHandlers(
        monitor,
        parsed['sideEffects'] as Map<String, dynamic>,
      );
      _processMonitorPush(parsed['sideEffects'] as Map<String, dynamic>);
    }

    final result = parsed['result'];
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {'value': result};
  }

  /// Process JS side effects: notifications and logs.
  void _processSideEffects(Monitor monitor, dynamic sideEffects) {
    if (sideEffects is! Map) return;

    // Logs
    final logs = sideEffects['logs'];
    if (logs is List && logs.isNotEmpty) {
      for (final line in logs) {
        log('Monitor:${monitor.name}', line.toString());
      }
    }

    // Notifications — local alert badge + haptic, no agent injection
    final notifications = sideEffects['notifications'];
    if (notifications is! List || notifications.isEmpty) return;

    for (final n in notifications) {
      if (n is! Map) continue;
      final type = n['type'] as String? ?? '';
      final message = n['message']?.toString() ?? '';
      if (message.isEmpty) continue;

      switch (type) {
        case 'alert':
          store.setAlert(monitor.id, message);
          onAlert?.call(monitor.id, message);
          notificationStore?.add(
            UINotification(
              id: 'mon_${monitor.id}_${DateTime.now().millisecondsSinceEpoch}',
              title: monitor.name,
              message: message,
              source: 'monitor:${monitor.id}',
              severity: NotificationSeverity.alert,
            ),
          );
        case 'notify':
          notificationStore?.add(
            UINotification(
              id: 'mon_${monitor.id}_${DateTime.now().millisecondsSinceEpoch}',
              title: monitor.name,
              message: message,
              source: 'monitor:${monitor.id}',
              severity: NotificationSeverity.notify,
            ),
          );
        case 'agent_message':
          final data = n['data'] as Map<String, dynamic>? ?? {};
          onAgentMessage?.call(monitor.name, message, data);
      }
    }
  }

  /// Parse the script to find callService() calls and pre-fetch them.
  /// Uses regex extraction — not perfect but covers common patterns.
  /// Supports: callService(path, params) and callService(path, params, 'POST')
  Future<Map<String, dynamic>> _prefetchServiceCalls(String script) async {
    final results = <String, dynamic>{};

    // Relaxed regex: capture path, params (with nested braces), and optional method.
    final pattern = RegExp(
      r'''callService\s*\(\s*['"]([^'"]+)['"]\s*(?:,\s*(\{[\s\S]*?\})\s*)?(?:,\s*['"](\w+)['"]\s*)?\)''',
    );
    // Variable URL pattern: callService(varName, ...)
    final varCallPattern = RegExp(
      r'''callService\s*\(\s*(\w+)\s*(?:,\s*(\{[\s\S]*?\})\s*)?(?:,\s*['"](\w+)['"]\s*)?\)''',
    );
    // Extract variable declarations
    final varDeclPattern = RegExp(
      r'''(?:const|let|var)\s+(\w+)\s*=\s*(?:['"]([^'"]+)['"]|`([^`]+)`)''',
    );

    final vars = <String, String>{};
    for (final m in varDeclPattern.allMatches(script)) {
      vars[m.group(1)!] = m.group(2) ?? m.group(3) ?? '';
    }

    final futures = <String, Future<Map<String, dynamic>>>{};

    void addCall(String path, String paramsStr, String method) {
      Map<String, dynamic> params;
      try {
        final jsonStr = paramsStr
            .replaceAllMapped(RegExp(r"(\w+)\s*:"), (m) => '"${m.group(1)}":')
            .replaceAll("'", '"');
        params = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (e) {
        final key = '$method:$path|$paramsStr';
        results[key] = {
          'error': 'Failed to parse callService params: $paramsStr ($e)',
        };
        log(
          'MonitorScheduler',
          'Failed to parse callService params for $path: $paramsStr',
        );
        return;
      }
      final key = '$method:$path|${jsonEncode(params)}';
      if (!futures.containsKey(key)) {
        futures[key] = _callService(path, params, method: method);
      }
    }

    // Match literal URLs
    for (final match in pattern.allMatches(script)) {
      addCall(
        match.group(1)!,
        match.group(2) ?? '{}',
        (match.group(3) ?? 'GET').toUpperCase(),
      );
    }

    // Match variable URLs
    for (final match in varCallPattern.allMatches(script)) {
      final varName = match.group(1)!;
      final resolved = vars[varName];
      if (resolved != null && resolved.isNotEmpty) {
        addCall(
          resolved,
          match.group(2) ?? '{}',
          (match.group(3) ?? 'GET').toUpperCase(),
        );
      }
    }

    // Execute all fetches in parallel
    for (final entry in futures.entries) {
      try {
        results[entry.key] = await entry.value;
      } catch (e) {
        results[entry.key] = {'error': e.toString()};
      }
    }

    // Pre-fetch file reads: Bridge.readFile('path')
    final filePattern = RegExp(
      r'''Bridge\.readFile\s*\(\s*['"]([^'"]+)['"]\s*\)''',
    );
    for (final match in filePattern.allMatches(script)) {
      final filePath = match.group(1)!;
      final key = '__file:$filePath';
      if (!results.containsKey(key)) {
        try {
          final resolved = '$basePath/$filePath';
          if (!resolved.contains('..') && File(resolved).existsSync()) {
            final content = File(resolved).readAsStringSync();
            try {
              results[key] = jsonDecode(content);
            } catch (_) {
              results[key] = content;
            }
          }
        } catch (_) {}
      }
    }

    // Pre-fetch dir listings: Bridge.listDir('path')
    final dirPattern = RegExp(
      r'''Bridge\.listDir\s*\(\s*['"]([^'"]*)['"]\s*\)''',
    );
    for (final match in dirPattern.allMatches(script)) {
      final dirPath = match.group(1)!;
      final key = '__dir:${dirPath.isEmpty ? '.' : dirPath}';
      if (!results.containsKey(key)) {
        try {
          final resolved = dirPath.isEmpty ? basePath : '$basePath/$dirPath';
          if (!resolved.contains('..') && Directory(resolved).existsSync()) {
            results[key] = Directory(resolved)
                .listSync()
                .map(
                  (e) => {
                    'name': e.path.split('/').last,
                    'type': e is Directory ? 'dir' : 'file',
                  },
                )
                .toList();
          }
        } catch (_) {}
      }
    }

    return results;
  }

  /// Call a server REST API endpoint (GET or POST).
  Future<Map<String, dynamic>> _callService(
    String path,
    Map<String, dynamic> params, {
    String method = 'GET',
  }) async {
    final localResult = _tryLocalFinanceService(path, params);
    if (localResult != null) return localResult;

    final response = await bridgeHttp(
      url: path,
      method: method,
      params: method == 'GET' || method == 'DELETE' ? params : null,
      body: method == 'POST' || method == 'PUT' ? params : null,
      serviceBaseUrl: serviceBaseUrl,
    ).timeout(_scriptTimeout);

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final body = jsonDecode(response.body);
    if (body is Map<String, dynamic>) return body;
    if (body is List) return {'data': body};
    return {'value': body};
  }

  Map<String, dynamic>? _tryLocalFinanceService(
    String path,
    Map<String, dynamic> params,
  ) {
    final rawCode = (params['ts_code'] ?? params['code'] ?? params['symbol'])
        ?.toString()
        .trim();
    if (rawCode == null || rawCode.isEmpty) {
      return {'data': const []};
    }
    final code = rawCode.split('.').first;
    final store = ReusableDataStore(basePath);
    if (path == '/api/finance/quote') {
      final rows = store.queryQuotes(code, limit: 1);
      return {
        'data': rows.map((row) => row.toJson()).toList(),
        'source': 'local quote_snapshot',
        'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      };
    }
    if (path == '/api/finance/kline') {
      final limit = _intParam(params['limit'] ?? params['bars']) ?? 150;
      final adjust = '${params['adjust'] ?? 'qfq'}'.trim();
      final rows = store.queryKline(
        code,
        adjust: adjust.isEmpty ? 'qfq' : adjust,
        limit: limit,
      );
      return {
        'data': rows.map((row) => row.toJson()).toList(),
        'source': 'local kline_daily',
        'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      };
    }
    if (path == '/api/finance/fund/nav') {
      final limit = _intParam(params['limit'] ?? params['rows']) ?? 30;
      final rows = _queryFundNavWithCodeVariants(store, rawCode, limit);
      return {
        'data': rows,
        'source': 'local fund_nav',
        'cacheStatus': rows.isEmpty ? 'cache-miss' : 'cache-hit',
      };
    }
    return null;
  }

  List<Map<String, dynamic>> _queryFundNavWithCodeVariants(
    ReusableDataStore store,
    String rawCode,
    int limit,
  ) {
    final trimmed = rawCode.trim();
    final baseCode = trimmed.split('.').first;
    final candidates = <String>[
      trimmed,
      if (baseCode.isNotEmpty) baseCode,
      if (baseCode.isNotEmpty && !trimmed.toUpperCase().endsWith('.OF'))
        '$baseCode.OF',
    ];
    for (final candidate in LinkedHashSet<String>.from(candidates)) {
      final rows = store.queryFundNav(candidate, limit: limit);
      if (rows.isNotEmpty) return rows;
    }
    return const [];
  }

  int? _intParam(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  /// Evaluate a condition expression against the result.
  bool _evaluateCondition(
    Map<String, dynamic> result,
    Map<String, dynamic> state,
    String condition,
  ) {
    _jsRuntime ??= getJavascriptRuntime();
    try {
      final js = _jsRuntime!;
      js.evaluate('var result = ${jsonEncode(result)};');
      js.evaluate('var state = ${jsonEncode(state)};');
      final evalResult = js.evaluate('!!($condition)');
      return evalResult.stringResult == 'true';
    } catch (e) {
      log('MonitorScheduler', 'Condition eval error: $e');
      return false;
    }
  }

  /// Emit a local alert for the monitor (badge + haptic).
  void _emitAlert(Monitor monitor, Map<String, dynamic> result) {
    final message =
        'Condition triggered: ${monitor.condition}\nResult: ${jsonEncode(result)}';
    log('MonitorScheduler', 'Alert triggered: ${monitor.name}');
    store.setAlert(monitor.id, message);
    onAlert?.call(monitor.id, message);
    notificationStore?.add(
      UINotification(
        id: 'mon_${monitor.id}_${DateTime.now().millisecondsSinceEpoch}',
        title: '${monitor.name} 告警',
        message: message,
        source: 'monitor:${monitor.id}',
        severity: NotificationSeverity.alert,
      ),
    );
  }

  void _processPushHandlers(Monitor monitor, Map<String, dynamic> sideEffects) {
    final handlers = sideEffects['pushHandlers'] as List? ?? [];
    for (final h in handlers) {
      if (h is! Map) continue;
      final channel = h['channel'] as String?;
      final handler = h['handler'] as String?;
      if (channel == null || handler == null) continue;
      _pushHandlers.putIfAbsent(monitor.id, () => {});
      _pushHandlers[monitor.id]![channel] = handler;
    }
  }

  /// Push data to a monitor's registered handler.
  void pushToMonitor(
    String monitorId,
    String channel,
    Map<String, dynamic> data,
  ) {
    final handlers = _pushHandlers[monitorId];
    if (handlers == null || !handlers.containsKey(channel)) return;
    final handlerJs = handlers[channel]!;
    final monitor = store.get(monitorId);
    if (monitor == null) return;

    try {
      _jsRuntime ??= getJavascriptRuntime();
      final js = _jsRuntime!;

      js.evaluate('''
        var state = ${jsonEncode(monitor.state)};
        var __sideEffects = { notifications: [], logs: [] };
        var __apiConfig = ${jsonEncode(apiConfig?.toMap() ?? {})};
        var Bridge = {};
        Bridge.notify = function(msg, sev) { __sideEffects.notifications.push({type: sev==='alert'?'alert':'notify', message: msg}); };
        Bridge.alert = function(msg) { __sideEffects.notifications.push({type:'alert', message: msg}); };
        Bridge.sendToAgent = function(msg, d) { __sideEffects.notifications.push({type:'agent_message', message: msg, data: d||{}}); };
        Bridge.getConfig = function(k) { return (__apiConfig||{})[k] || null; };
        ${BridgeJs.dataFunctions}
        ${BridgeJs.statsFunctions}
        ${BridgeJs.consoleSideEffects}
      ''');

      final dataJson = jsonEncode(
        data,
      ).replaceAll('\\', '\\\\').replaceAll("'", "\\'");
      final wrappedCode =
          '''
        (function() {
          try {
            var data = JSON.parse('$dataJson');
            var __handler = $handlerJs;
            var __result = __handler(data);
            return JSON.stringify({ ok: true, result: __result, state: state, sideEffects: __sideEffects });
          } catch(e) {
            return JSON.stringify({ ok: false, error: e.message || String(e), sideEffects: __sideEffects });
          }
        })()
      ''';

      final jsResult = js.evaluate(wrappedCode);
      final parsed = jsonDecode(jsResult.stringResult) as Map<String, dynamic>;

      if (parsed['state'] is Map) {
        monitor.state = Map<String, dynamic>.from(parsed['state'] as Map);
      }
      if (parsed['ok'] == true && parsed['result'] is Map) {
        monitor.lastResult = Map<String, dynamic>.from(parsed['result'] as Map);
      }
      monitor.lastRunTime = DateTime.now();

      _processSideEffects(
        monitor,
        parsed['sideEffects'] as Map<String, dynamic>? ?? {},
      );
      store.save();
      store.onChanged?.call();
    } catch (e) {
      log('MonitorScheduler', 'Push handler error ($monitorId/$channel): $e');
    }
  }

  void _processMonitorPush(Map<String, dynamic> sideEffects) {
    final pushes = sideEffects['monitorPush'] as List? ?? [];
    for (final p in pushes) {
      if (p is! Map) continue;
      final monitorId = p['monitorId'] as String?;
      final channel = p['channel'] as String?;
      final data = p['data'] as Map<String, dynamic>? ?? {};
      if (monitorId != null && channel != null) {
        pushToMonitor(monitorId, channel, data);
      }
    }
  }

  void _processFileOps(Map<String, dynamic> sideEffects) {
    final fileOps = sideEffects['fileOps'] as List? ?? [];
    for (final op in fileOps) {
      if (op is! Map) continue;
      final action = op['op'] as String?;
      final path = op['path'] as String?;
      if (action == 'write' && path != null) {
        final content = op['content'] as String? ?? '';
        if (path.contains('..')) continue;
        final resolved = '$basePath/$path';
        try {
          final file = File(resolved);
          file.parent.createSync(recursive: true);
          file.writeAsStringSync(content);
        } catch (e) {
          log('MonitorScheduler', 'File write failed ($path): $e');
        }
      }
    }
  }

  // ─── Bridge.ws() support ───

  /// Called after running a monitor script that used Bridge.ws().
  /// Picks up ws registrations from __sideEffects and manages connections.
  void _processWsRegistrations(
    Monitor monitor,
    Map<String, dynamic> sideEffects,
  ) {
    final wsList = sideEffects['ws'] as List? ?? [];
    for (final ws in wsList) {
      if (ws is! Map) continue;
      final url = ws['url'] as String?;
      final onMessage = ws['onMessage'] as String?;
      final onOpen = ws['onOpen'] as String?;
      if (url == null || url.isEmpty) continue;

      final key = '${monitor.id}:$url';
      if (_wsConnections.containsKey(key)) continue;

      _wsBridgeConfigs[key] = _WsBridgeConfig(
        monitorId: monitor.id,
        url: url,
        onMessageJs: onMessage ?? '',
        onOpenJs: onOpen,
      );
      _connectBridgeWebSocket(key, monitor);
    }
  }

  Future<void> _connectBridgeWebSocket(String key, Monitor monitor) async {
    final config = _wsBridgeConfigs[key];
    if (config == null) return;

    try {
      final ws = await WebSocket.connect(config.url);
      _wsConnections[key] = ws;
      log(
        'MonitorScheduler',
        'Bridge.ws connected: ${monitor.name} → ${config.url}',
      );

      if (config.onOpenJs != null && config.onOpenJs!.isNotEmpty) {
        try {
          _jsRuntime ??= getJavascriptRuntime();
          final result = _jsRuntime!.evaluate('(${config.onOpenJs})');
          final msg = result.stringResult;
          if (msg.isNotEmpty && msg != 'undefined' && msg != 'null') {
            ws.add(msg);
          }
        } catch (e) {
          log('MonitorScheduler', 'Bridge.ws onOpen error: $e');
        }
      }

      ws.listen(
        (rawData) => _handleBridgeWsMessage(key, monitor, rawData),
        onError: (e) {
          log('MonitorScheduler', 'Bridge.ws error ($key): $e');
          _wsConnections.remove(key);
          _scheduleBridgeReconnect(key, monitor);
        },
        onDone: () {
          _wsConnections.remove(key);
          _scheduleBridgeReconnect(key, monitor);
        },
      );
    } catch (e) {
      log('MonitorScheduler', 'Bridge.ws connect failed ($key): $e');
      _scheduleBridgeReconnect(key, monitor);
    }
  }

  void _scheduleBridgeReconnect(String key, Monitor monitor) {
    _wsReconnectTimers[key]?.cancel();
    _wsReconnectTimers[key] = Timer(const Duration(seconds: 30), () {
      _wsReconnectTimers.remove(key);
      if (monitor.enabled && _wsBridgeConfigs.containsKey(key)) {
        _connectBridgeWebSocket(key, monitor);
      }
    });
  }

  void _handleBridgeWsMessage(String key, Monitor monitor, dynamic rawData) {
    final config = _wsBridgeConfigs[key];
    if (config == null || config.onMessageJs.isEmpty) return;

    try {
      _jsRuntime ??= getJavascriptRuntime();
      final js = _jsRuntime!;

      final dataStr = rawData is String ? rawData : jsonEncode(rawData);
      js.evaluate('''
        var state = ${jsonEncode(monitor.state)};
        var __sideEffects = { notifications: [], logs: [] };
        var __apiConfig = ${jsonEncode(apiConfig?.toMap() ?? {})};
        var Bridge = {};
        Bridge.notify = function(msg, sev) { __sideEffects.notifications.push({type: sev==='alert'?'alert':'notify', message: msg}); };
        Bridge.alert = function(msg) { __sideEffects.notifications.push({type:'alert', message: msg}); };
        Bridge.sendToAgent = function(msg, data) { __sideEffects.notifications.push({type:'agent_message', message: msg, data: data||{}}); };
        Bridge.getConfig = function(k) { return (__apiConfig||{})[k] || null; };
        ${BridgeJs.dataFunctions}
        ${BridgeJs.statsFunctions}
        ${BridgeJs.consoleSideEffects}
      ''');

      final wrappedCode =
          '''
        (function() {
          try {
            var data = JSON.parse('${dataStr.replaceAll('\\', '\\\\').replaceAll("'", "\\'")}');
            var __handler = ${config.onMessageJs};
            var __result = __handler(data);
            return JSON.stringify({ ok: true, result: __result, state: state, sideEffects: __sideEffects });
          } catch(e) {
            return JSON.stringify({ ok: false, error: e.message || String(e), sideEffects: __sideEffects });
          }
        })()
      ''';

      final jsResult = js.evaluate(wrappedCode);
      final parsed = jsonDecode(jsResult.stringResult) as Map<String, dynamic>;

      if (parsed['state'] is Map) {
        monitor.state = Map<String, dynamic>.from(parsed['state'] as Map);
      }
      if (parsed['ok'] == true && parsed['result'] is Map) {
        monitor.lastResult = Map<String, dynamic>.from(parsed['result'] as Map);
      }
      monitor.lastRunTime = DateTime.now();
      monitor.lastError = parsed['ok'] == true
          ? null
          : parsed['error'] as String?;

      _processSideEffects(
        monitor,
        parsed['sideEffects'] as Map<String, dynamic>? ?? {},
      );
      store.save();
      store.onChanged?.call();
    } catch (e) {
      log('MonitorScheduler', 'Bridge.ws handler error ($key): $e');
    }
  }
}

class _WsBridgeConfig {
  final String monitorId;
  final String url;
  final String onMessageJs;
  final String? onOpenJs;

  _WsBridgeConfig({
    required this.monitorId,
    required this.url,
    required this.onMessageJs,
    this.onOpenJs,
  });
}
