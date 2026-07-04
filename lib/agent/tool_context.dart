// ignore_for_file: unintended_html_in_doc_comment
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'background_task.dart';
import 'session_index.dart';
import 'strategy.dart';
import 'task_store.dart';
import 'team_context.dart';

/// Shared context passed to all tool calls.
///
/// Reference: Claude Code's ToolUseContext in query.ts
class ToolContext {
  /// Maps file path → last read timestamp in milliseconds.
  /// Used by write tools to enforce read-before-write safety.
  final Map<String, int> readFileTimestamps = {};

  /// Agent's storage root directory (e.g. <documents>/agents/finance/).
  final String basePath;

  /// Service base URL for REST API calls (e.g. "http://localhost:3033").
  /// Shared by Agent (ServiceCallTool) and Flutter UI.
  String serviceBaseUrl;

  /// Agent's memory directory (e.g. <documents>/agents/finance/memory/).
  String get memoryDir => '$basePath/memory';

  /// Agent's bundle directory (e.g. <documents>/agents/finance/bundle/).
  /// Read-only for Agent — App controls this directory.
  String get bundleDir => '$basePath/bundle';

  /// If true, skip all permission checks.
  /// Reference: Claude Code's dangerouslySkipPermissions option.
  final bool skipPermissions;

  /// In-memory task management for the agent session.
  final TaskStore taskStore;

  /// Registry for background sub-agent tasks.
  /// Shared between parent and sub-agents so parent can see task status.
  final TaskRegistry taskRegistry;

  /// Registry for active teams (swarms).
  final TeamRegistry teamRegistry;

  /// Whether the agent is currently in plan mode.
  bool planMode = false;

  /// Event sink for tools to emit progress events (e.g. sub-agent progress).
  /// Set by Agent before each tool execution, cleared after.
  /// Type is dynamic to avoid circular import with agent.dart.
  StreamSink<dynamic>? eventSink;

  /// Optional session search index for cross-session search.
  SessionIndex? sessionIndex;

  /// Strategy store — lazy-loaded on first access.
  StrategyStore? _strategyStore;
  StrategyStore get strategyStore {
    _strategyStore ??= StrategyStore()..load(basePath);
    return _strategyStore!;
  }

  /// Set of tool names that have been pre-approved (no confirmation needed).
  /// Reference: Claude Code's approved-tools config.
  final Set<String> approvedTools;

  ToolContext({
    required this.basePath,
    required this.serviceBaseUrl,
    this.skipPermissions = false,
    Set<String>? approvedTools,
    TaskStore? taskStore,
    TaskRegistry? taskRegistry,
    TeamRegistry? teamRegistry,
  }) : approvedTools = approvedTools ?? {},
       taskStore = taskStore ?? TaskStore(),
       taskRegistry = taskRegistry ?? TaskRegistry(),
       teamRegistry = teamRegistry ?? TeamRegistry();

  /// Approve a tool for the rest of this session (and optionally persist).
  void approveTool(String toolName, {bool persist = false}) {
    approvedTools.add(toolName);
    if (persist) {
      _saveApprovedTools();
    }
  }

  /// Check if a tool needs permission, considering skipPermissions and approvedTools.
  bool needsPermission(String toolName) {
    if (skipPermissions) return false;
    if (approvedTools.contains(toolName)) return false;
    return true;
  }

  void _saveApprovedTools() {
    final file = File('$basePath/approved_tools.json');
    file.writeAsStringSync(jsonEncode(approvedTools.toList()));
  }

  /// Load approved tools from persisted config.
  static Set<String> loadApprovedTools(String basePath) {
    final file = File('$basePath/approved_tools.json');
    if (!file.existsSync()) return {};
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      return list.cast<String>().toSet();
    } catch (_) {
      return {};
    }
  }
}
