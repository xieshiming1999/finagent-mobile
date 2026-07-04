import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'log.dart';

/// A monitor definition: JS script + schedule + display config.
/// Persisted to monitors.json.
class Monitor {
  final String id;
  String name;
  String script;
  Duration interval;
  String? condition;
  String
  displayType; // 'value_card' | 'status_row' | 'alert_list' | 'mini_chart' | 'watchlist'
  bool enabled;

  /// User's original request that led to creating this monitor.
  String? userPrompt;

  /// Agent-generated natural language description of what this monitor does.
  String? description;

  /// Group ID for organizing related monitors (e.g. "自选股盯盘").
  String? groupId;

  /// Display name for the group.
  String? groupName;

  /// Strategy artifact identity when a monitor is derived from StrategySpec.
  String? strategyId;

  /// Structured strategy-derived rule provenance for audit/readback.
  Map<String, dynamic>? strategyRules;

  /// WebSocket URL for push-based monitoring (no polling needed).
  String? streamUrl;

  /// Whether this monitor uses WebSocket (streamUrl or Bridge.ws in script).
  bool get isWebSocket => streamUrl != null && streamUrl!.isNotEmpty;

  // Runtime state (persisted)
  Map<String, dynamic> state;
  Map<String, dynamic>? lastResult;
  DateTime? lastRunTime;
  String? lastError;
  bool conditionTriggered;

  /// Alert badge: true when condition triggered or Bridge.alert() fired.
  /// Cleared when user taps the monitor card.
  bool hasUnreadAlert;

  /// Last alert message text (for display in detail sheet).
  String? alertMessage;

  Monitor({
    required this.id,
    required this.name,
    required this.script,
    this.interval = const Duration(minutes: 5),
    this.condition,
    this.displayType = 'value_card',
    this.enabled = true,
    this.userPrompt,
    this.description,
    this.groupId,
    this.groupName,
    this.strategyId,
    this.strategyRules,
    this.streamUrl,
    Map<String, dynamic>? state,
    this.lastResult,
    this.lastRunTime,
    this.lastError,
    this.conditionTriggered = false,
    this.hasUnreadAlert = false,
    this.alertMessage,
  }) : state = state ?? {};

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'script': script,
    'intervalSeconds': interval.inSeconds,
    'condition': condition,
    'displayType': displayType,
    'enabled': enabled,
    'userPrompt': userPrompt,
    'description': description,
    'groupId': groupId,
    'groupName': groupName,
    'strategyId': strategyId,
    'strategyRules': strategyRules,
    'streamUrl': streamUrl,
    'state': state,
    'lastResult': lastResult,
    'lastRunTime': lastRunTime?.toIso8601String(),
    'lastError': lastError,
    'conditionTriggered': conditionTriggered,
    'hasUnreadAlert': hasUnreadAlert,
    'alertMessage': alertMessage,
  };

  factory Monitor.fromJson(Map<String, dynamic> json) => Monitor(
    id: json['id'] as String,
    name: json['name'] as String,
    script: json['script'] as String,
    interval: Duration(seconds: json['intervalSeconds'] as int? ?? 300),
    condition: json['condition'] as String?,
    displayType: json['displayType'] as String? ?? 'value_card',
    enabled: json['enabled'] as bool? ?? true,
    userPrompt: json['userPrompt'] as String?,
    description: json['description'] as String?,
    groupId: json['groupId'] as String?,
    groupName: json['groupName'] as String?,
    strategyId: json['strategyId'] as String?,
    strategyRules: json['strategyRules'] is Map
        ? Map<String, dynamic>.from(json['strategyRules'] as Map)
        : null,
    streamUrl: json['streamUrl'] as String?,
    state: Map<String, dynamic>.from(json['state'] as Map? ?? {}),
    lastResult: json['lastResult'] != null
        ? Map<String, dynamic>.from(json['lastResult'] as Map)
        : null,
    lastRunTime: json['lastRunTime'] != null
        ? DateTime.tryParse(json['lastRunTime'] as String)
        : null,
    lastError: json['lastError'] as String?,
    conditionTriggered: json['conditionTriggered'] as bool? ?? false,
    hasUnreadAlert: json['hasUnreadAlert'] as bool? ?? false,
    alertMessage: json['alertMessage'] as String?,
  );

  /// Summary for MonitorList tool output.
  String toSummary() {
    final status = enabled ? (lastError != null ? 'error' : 'ok') : 'disabled';
    final lastRun = lastRunTime != null
        ? lastRunTime!.toIso8601String().substring(11, 19)
        : 'never';
    final resultPreview = lastResult != null
        ? lastResult.toString()
        : '(no data)';
    final strategy = strategyId == null ? '' : '\n  strategyId: $strategyId';
    final rules = strategyRules == null
        ? ''
        : '\n  strategyRules: ${jsonEncode(strategyRules)}';
    return '[$status] $name (id: $id, interval: ${interval.inMinutes}m, lastRun: $lastRun)$strategy$rules\n'
        '  result: ${resultPreview.length > 100 ? '${resultPreview.substring(0, 100)}...' : resultPreview}';
  }
}

/// Persists monitors to disk and provides CRUD operations.
class MonitorStore {
  final String _filePath;
  final _monitors = <String, Monitor>{};
  void Function()? onChanged;

  static const maxMonitors = 50;

  MonitorStore({required String memoryDir})
    : _filePath = p.join(memoryDir, 'monitors.json');

  List<Monitor> get monitors => _monitors.values.toList();
  Monitor? get(String id) => _monitors[id];
  int get count => _monitors.length;

  void load() {
    final file = File(_filePath);
    if (!file.existsSync()) return;

    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      _monitors.clear();
      for (final item in list) {
        final m = Monitor.fromJson(item as Map<String, dynamic>);
        _monitors[m.id] = m;
      }
      log('MonitorStore', 'Loaded ${_monitors.length} monitors');
    } catch (e) {
      log('MonitorStore', 'Load error: $e');
    }
  }

  void save() {
    try {
      Directory(p.dirname(_filePath)).createSync(recursive: true);
      final json = jsonEncode(_monitors.values.map((m) => m.toJson()).toList());
      File(_filePath).writeAsStringSync(json);
    } catch (e) {
      log('MonitorStore', 'Save error: $e');
    }
  }

  String add(Monitor monitor) {
    if (_monitors.length >= maxMonitors) {
      return 'Cannot create monitor: maximum limit ($maxMonitors) reached.';
    }
    _monitors[monitor.id] = monitor;
    save();
    onChanged?.call();
    return '';
  }

  bool remove(String id) {
    if (_monitors.remove(id) != null) {
      save();
      onChanged?.call();
      return true;
    }
    return false;
  }

  void updateResult(
    String id,
    Map<String, dynamic> result,
    Map<String, dynamic> state,
  ) {
    final m = _monitors[id];
    if (m == null) return;
    m.lastResult = result;
    m.state = state;
    m.lastRunTime = DateTime.now();
    m.lastError = null;
    save();
    onChanged?.call();
  }

  void updateError(String id, String error) {
    final m = _monitors[id];
    if (m == null) return;
    m.lastError = error;
    m.lastRunTime = DateTime.now();
    save();
    onChanged?.call();
  }

  void setEnabled(String id, bool enabled) {
    final m = _monitors[id];
    if (m == null) return;
    m.enabled = enabled;
    save();
    onChanged?.call();
  }

  void setAlert(String id, String message) {
    final m = _monitors[id];
    if (m == null) return;
    m.hasUnreadAlert = true;
    m.alertMessage = message;
    save();
    onChanged?.call();
  }

  void clearAlert(String id) {
    final m = _monitors[id];
    if (m == null) return;
    if (!m.hasUnreadAlert) return;
    m.hasUnreadAlert = false;
    save();
    onChanged?.call();
  }
}
