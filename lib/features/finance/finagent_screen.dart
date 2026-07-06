import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;

import '../../agent/agent.dart';
import '../../agent/agent_status.dart';
import '../../agent/data_fetcher/api_stats.dart';
import '../../agent/data_fetcher/data_manager.dart';
import '../../agent/data_fetcher/finance_data_contract.dart';
import '../../agent/data_fetcher/finance_schema_census.dart';
import '../../agent/data_fetcher/reusable_data_store.dart';
import '../../agent/artifact_registry.dart';
import '../../agent/data_task_engine.dart';
import '../../agent/finance_doctor.dart';
import '../../agent/goal_automation_suggestions.dart';
import '../../agent/goal_automation_service.dart';
import '../../agent/goal_automation_types.dart';
import '../../agent/http_bridge.dart';
import '../../domain/market/backtest/strategy_artifact_contract.dart';
import '../../agent/message.dart';
import '../../agent/session.dart';
import '../../agent/spinner_verbs.dart';
import '../../agent/notification_queue.dart';
import '../../agent/ui_notification.dart';
import '../../agent/monitor.dart';
import '../../agent/watchlist.dart';
import '../../agent/monitor_scheduler.dart';
import '../../agent/log.dart';
import '../../agent/tool_context.dart';
import '../../agent/workflow_automation_control.dart';
import '../../agent/tools/ask_user_question_tool/ask_user_question_tool.dart';
import '../../agent/tools/environment_tool/environment_tool.dart';
import '../../agent/tools/ui_control_tool/ui_control_tool.dart';
import '../../agent/tools/ui_query_tool/ui_query_tool.dart';
import '../../agent/tools/ui_notify_tool/ui_notify_tool.dart';
import '../../agent/tools/webview_tool/webview_tool.dart';
import '../../agent/tools/utils/summarize_input.dart';
import '../../domain/market/services/market_data_action_service.dart';
import '../../domain/market/services/market_data_action_service_factory.dart';
import '../../domain/market/services/market_data_runtime_probe_service.dart';
import '../../domain/market/services/market_data_support_service.dart';
import '../../shared/agent_factory.dart';
import '../../shared/api_config.dart';
import '../../shared/app_shell.dart';
import '../../shared/feature_prompts.dart';
import '../../shared/dashboard_panel_models.dart';
import '../../shared/dashboard_screen.dart';
import '../../shared/i18n/app_localizations.dart';
import '../../shared/monitor_panel.dart';
import '../../shared/strategy_library_model.dart';
import 'chat_models.dart';
import 'strategy_library_action_prompt.dart';
import 'webview_capture_evidence.dart';
import '../../agent/data_fetcher/eastmoney_advanced_fetcher.dart';

part 'finagent_init.dart';
part 'dashboard_handlers.dart';
part 'webview_handlers.dart';
part 'webview_import_export.dart';
part 'ui_handlers.dart';
part 'event_handler.dart';
part 'build_helpers.dart';
part 'build_helpers_toolbar.dart';
part 'build_helpers_sessions.dart';
part 'build_helpers_session_preview.dart';
part 'build_helpers_api_health.dart';

class FinAgentScreen extends StatefulWidget {
  final Agent agent;
  final UIQueryTool uiQueryTool;
  final UIControlTool uiControlTool;
  final AskUserQuestionTool askUserQuestionTool;
  final WebViewTool webViewTool;
  final EnvironmentTool environmentTool;
  final DataTaskEngine dataTaskEngine;
  final MonitorStore monitorStore;
  final WatchlistStore watchlistStore;
  final MonitorScheduler monitorScheduler;
  final UINotificationStore notificationStore;
  final bool? workflowAutomationEnabledOverride;
  final ValueChanged<WorkflowAutomationControl>?
  onWorkflowAutomationControlCreated;
  final ValueChanged<WorkflowAutomationInProcessBridge>?
  onWorkflowAutomationBridgeCreated;

  const FinAgentScreen({
    super.key,
    required this.agent,
    required this.uiQueryTool,
    required this.uiControlTool,
    required this.askUserQuestionTool,
    required this.webViewTool,
    required this.environmentTool,
    required this.dataTaskEngine,
    required this.monitorStore,
    required this.watchlistStore,
    required this.monitorScheduler,
    required this.notificationStore,
    this.workflowAutomationEnabledOverride,
    this.onWorkflowAutomationControlCreated,
    this.onWorkflowAutomationBridgeCreated,
  });

  @override
  State<FinAgentScreen> createState() => _FinAgentScreenState();
}

class _FinAgentScreenState extends State<FinAgentScreen> {
  void _setState(VoidCallback fn) => setState(fn);

  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final List<ChatItem> _items = [];
  final _dashKey = GlobalKey<DashboardScreenState>();

  bool _isLoading = false;
  final bool _eventNeedsAttention = false;
  StreamSubscription<AgentEvent>? _subscription;
  StreamSubscription<AgentEvent>? _autoSub;

  late AgentRuntime _eventRuntime;
  bool _eventRuntimeInitialized = false;
  StreamSubscription<AgentEvent>? _eventAutoSub;
  WorkflowAutomationHttpHost? _workflowAutomationHttpHost;

  AgentStatus? _agentStatus;
  Timer? _statusTimer;
  String? _turnSummary;
  Timer? _summaryTimer;
  List<Map<String, dynamic>> _tasks = [];

  String? get _contextInfo {
    final agent = widget.agent;
    if (agent.lastPromptTokens <= 0 || agent.contextWindow <= 0) return null;
    final pct = (agent.lastPromptTokens / agent.contextWindow * 100)
        .toStringAsFixed(1);
    return '$pct% (${formatTokenCount(agent.lastPromptTokens)}/${formatTokenCount(agent.contextWindow)})';
  }

  AgentStatus? _eventStatus;
  Timer? _eventStatusTimer;
  String? _eventTurnSummary;
  Timer? _eventSummaryTimer;
  Timer? _goalAutomationStartupTimer;
  Timer? _goalAutomationTimer;
  late GoalAutomationService _goalAutomationService;
  bool _apiHealthPanelVisible = false;
  bool _historyPanelVisible = false;
  bool _sessionPanelVisible = false;
  final ValueNotifier<int> _eventPanelNotifier = ValueNotifier(0);

  // Event agent chat state
  final List<ChatItem> _eventItems = [];
  final _eventController = TextEditingController();
  final _eventFocusNode = FocusNode();

  List<UserQuestion>? _pendingQuestions;
  Completer<Map<String, String>>? _questionCompleter;
  int _currentQuestionIndex = 0;
  final Map<String, String> _collectedAnswers = {};

  bool get _workflowAutomationEnabled =>
      widget.workflowAutomationEnabledOverride ??
      const bool.fromEnvironment('FINAGENT_WORKFLOW_AUTOMATION');

  DashboardScreenState? get _dash => _dashKey.currentState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
        _dash?.tabController.addListener(() {
          if (mounted) setState(() {});
        });
      }
    });
    _goalAutomationService = GoalAutomationService(
      basePath: widget.agent.toolContext.basePath,
      agent: widget.agent,
      dataTaskEngine: widget.dataTaskEngine,
    );
    _initWorkflowAutomationControl();
    _registerUIHandlers();
    _restoreSession();
    widget.agent.onRecap = (msg) {
      setState(() => _items.add(ChatItem(role: 'recap', content: msg.content)));
      _scrollToBottom();
    };
    if (_workflowAutomationEnabled) {
      widget.monitorScheduler.stop();
      widget.agent.notificationQueue
        ..clear()
        ..accepting = false;
    } else {
      _autoSub = widget.agent.startAutoProcessing().listen((e) {
        setState(() => _handleEvent(e));
        _scrollToBottom();
      });
      _goalAutomationStartupTimer = Timer(const Duration(seconds: 5), () {
        if (mounted) {
          _goalAutomationService.evaluateTriggers(trigger: 'startup');
        }
      });
      _goalAutomationTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        _goalAutomationService.evaluateTriggers();
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_eventRuntimeInitialized) return;
    _eventRuntimeInitialized = true;
    _initEventAgent();
    _restoreEventSession();
    _interceptCronForEventAgent();
    if (_workflowAutomationEnabled) {
      _eventRuntime.monitorScheduler.stop();
      _eventRuntime.agent.notificationQueue
        ..clear()
        ..accepting = false;
    } else {
      _eventAutoSub = _eventRuntime.agent.startAutoProcessing().listen((e) {
        setState(() => _handleEventAgentEvent(e));
      });
    }
  }

  void _restoreSession() {
    final pendingTools = <String, int>{};
    for (final msg in widget.agent.messages) {
      switch (msg.role) {
        case Role.user:
          if (msg.isRecap) {
            _items.add(ChatItem(role: 'recap', content: msg.content));
          } else if (!msg.isCompactSummary) {
            _items.add(ChatItem(role: 'user', content: msg.content));
          }
        case Role.assistant:
          if (msg.content.isNotEmpty) {
            _items.add(ChatItem(role: 'assistant', content: msg.content));
          }
          for (final tu in msg.toolUses ?? <ToolUse>[]) {
            _items.add(
              ChatItem(
                role: 'tool_use',
                content:
                    '${tu.name}(${_summarizeToolInput(tu.name, tu.input)})',
                metadata: {'status': 'running'},
              ),
            );
            pendingTools[tu.id] = _items.length - 1;
          }
        case Role.tool:
          if (msg.toolResult != null) {
            final idx = pendingTools.remove(msg.toolResult!.toolUseId);
            if (idx != null && idx < _items.length) {
              _items[idx].metadata?['status'] = msg.toolResult!.isError
                  ? 'error'
                  : 'ok';
            }
          }
      }
    }
    for (final idx in pendingTools.values) {
      if (idx < _items.length) _items[idx].metadata?['status'] = 'ok';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _subscription?.cancel();
    _autoSub?.cancel();
    _eventAutoSub?.cancel();
    _eventController.dispose();
    _eventFocusNode.dispose();
    _statusTimer?.cancel();
    _summaryTimer?.cancel();
    _eventStatusTimer?.cancel();
    _eventSummaryTimer?.cancel();
    _goalAutomationStartupTimer?.cancel();
    _goalAutomationTimer?.cancel();
    _eventPanelNotifier.dispose();
    final automationHost = _workflowAutomationHttpHost;
    _workflowAutomationHttpHost = null;
    unawaited(automationHost?.close());
    widget.agent.stopAutoProcessing();
    if (_eventRuntimeInitialized) {
      _eventRuntime.agent.stopAutoProcessing();
      _eventRuntime.cronScheduler.stop();
      _eventRuntime.monitorScheduler.stop();
    }
    super.dispose();
  }

  void _initWorkflowAutomationControl() {
    final enabled = _workflowAutomationEnabled;
    Log.log('WorkflowAutomation', [
      'FinAgent test HTTP server enabled=$enabled',
    ]);
    if (!enabled) return;
    final control = WorkflowAutomationControl(
      agent: widget.agent,
      enabled: enabled,
      uiStateProvider: _workflowAutomationUiState,
      uiSemanticsProvider: _workflowAutomationUiSemantics,
      uiArtifactsProvider: _workflowAutomationUiArtifacts,
      interactiveStateProvider: _workflowAutomationInteractiveState,
      interactiveAnswerHandler: _workflowAutomationAnswerQuestion,
      strategyLibraryActionHandler: _workflowAutomationStrategyLibraryAction,
      monitorTriggerHandler: _workflowAutomationTriggerMonitor,
      uiClearHandler: () {
        if (!mounted) return;
        setState(() {
          _items.clear();
          _tasks = [];
          _isLoading = false;
          _agentStatus = null;
          _turnSummary = null;
        });
      },
      promptRunHandler: _runWorkflowAutomationPrompt,
    );
    widget.onWorkflowAutomationControlCreated?.call(control);
    widget.onWorkflowAutomationBridgeCreated?.call(
      WorkflowAutomationInProcessBridge(control: control),
    );
    _startWorkflowAutomationHttpHost(control);
  }

  Future<List<AgentEvent>> _runWorkflowAutomationPrompt(String prompt) async {
    final events = <AgentEvent>[];
    if (!mounted) return events;
    setState(() {
      _items.add(ChatItem(role: 'user', content: prompt));
      _items.add(ChatItem(role: 'assistant', content: ''));
      _isLoading = true;
      _turnSummary = null;
      _summaryTimer?.cancel();
      _statusTimer?.cancel();
      _agentStatus =
          AgentStatus(
              verb: localizedRandomSpinnerVerb(
                isChinese: AppLocalizations.of(context).isChinese,
              ),
            )
            ..contextWindow = widget.agent.contextWindow
            ..lastPromptTokens = widget.agent.lastPromptTokens;
      _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    });
    try {
      await for (final event in widget.agent.run(prompt)) {
        events.add(event);
        if (!mounted) continue;
        setState(() => _handleEvent(event));
        _scrollToBottom();
      }
    } finally {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          if (_agentStatus != null) {
            _statusTimer?.cancel();
            _agentStatus = null;
          }
        });
      }
    }
    return events;
  }

  void _startWorkflowAutomationHttpHost(WorkflowAutomationControl control) {
    final port = const int.fromEnvironment('FINAGENT_WORKFLOW_AUTOMATION_PORT');
    final host = WorkflowAutomationHttpHost(control: control, port: port);
    _workflowAutomationHttpHost = host;
    unawaited(
      host
          .start()
          .then((boundPort) {
            if (boundPort == null) return;
            Log.log('WorkflowAutomation', [
              'FinAgent test HTTP server listening on http://127.0.0.1:$boundPort',
            ]);
          })
          .catchError((Object error) {
            Log.log('WorkflowAutomation', [
              'FinAgent test HTTP server failed: $error',
            ]);
          }),
    );
  }

  Future<Map<String, dynamic>> _workflowAutomationStrategyLibraryAction({
    required String action,
    String? strategyId,
  }) async {
    final file = File(_strategyLibraryPath);
    if (!file.existsSync()) {
      return {
        'ok': false,
        'error': 'strategy library file does not exist',
        'path': file.path,
      };
    }
    final decoded = jsonDecode(file.readAsStringSync());
    final items = parseStrategyLibraryRows(decoded);
    StrategyLibraryItem? item;
    if (strategyId == null || strategyId.trim().isEmpty) {
      item = items.isEmpty ? null : items.first;
    } else {
      for (final candidate in items) {
        if (candidate.strategyId == strategyId) {
          item = candidate;
          break;
        }
      }
    }
    if (item == null) {
      return {
        'ok': false,
        'error': 'strategy not found',
        'strategyId': strategyId,
        'available': items.map((item) => item.strategyId).toList(),
      };
    }
    final normalizedAction = action == 'rerun' && !item.runnable
        ? 'read'
        : action;
    final prompt = buildStrategyActionPrompt(normalizedAction, item);
    final run = await _runWorkflowAutomationPrompt(prompt);
    return {
      'ok': true,
      'action': normalizedAction,
      'strategyId': item.strategyId,
      'prompt': prompt,
      'eventTypes': run.map((event) => event.runtimeType.toString()).toList(),
      'toolCalls': run
          .whereType<AgentToolUseStart>()
          .map((event) => {'toolName': event.toolName, 'input': event.input})
          .toList(),
      'toolErrors': run
          .whereType<AgentToolResult>()
          .where((event) => event.isError)
          .map((event) => {'toolName': event.toolName, 'result': event.result})
          .toList(),
      'finalAssistantText': _assistantTextFromRun(run),
      'uiState': _workflowAutomationUiState(),
      'uiEvidence': _workflowAutomationUiSemantics(),
    };
  }

  Future<Map<String, dynamic>> _workflowAutomationTriggerMonitor({
    required String monitorId,
    Duration? timeout,
  }) async {
    final monitor = widget.monitorStore.get(monitorId);
    if (monitor == null) {
      return {
        'ok': false,
        'error': 'monitor not found',
        'monitorId': monitorId,
        'available': widget.monitorStore.monitors
            .map(
              (monitor) => {
                'id': monitor.id,
                'name': monitor.name,
                if (monitor.strategyId != null)
                  'strategyId': monitor.strategyId,
              },
            )
            .toList(),
      };
    }
    final capturedMessages = <Map<String, dynamic>>[];
    final original = widget.monitorScheduler.onAgentMessage;
    final eventMessagesStart = _eventRuntime.agent.messages.length;
    final originalAccepting = _eventRuntime.agent.notificationQueue.accepting;
    StreamSubscription<AgentEvent>? eventSub;
    final eventEvents = <AgentEvent>[];
    if (_workflowAutomationEnabled) {
      _eventRuntime.agent.notificationQueue.accepting = true;
      eventSub = _eventRuntime.agent.startAutoProcessing().listen((event) {
        eventEvents.add(event);
        if (mounted) setState(() => _handleEventAgentEvent(event));
      });
    }
    widget.monitorScheduler.onAgentMessage = (name, message, data) {
      capturedMessages.add({
        'monitorName': name,
        'message': message,
        'data': data,
      });
      original?.call(name, message, data);
    };
    Object? error;
    Map<String, dynamic>? result;
    try {
      result = await widget.monitorScheduler.executeOnce(
        monitor,
        forceAgentNotification: true,
      );
      if (_workflowAutomationEnabled && capturedMessages.isNotEmpty) {
        await _waitForWorkflowEventAgentCheckpoint(
          timeout: timeout ?? const Duration(seconds: 30),
        );
      }
    } catch (e) {
      error = e;
    } finally {
      widget.monitorScheduler.onAgentMessage = original;
      if (_workflowAutomationEnabled) {
        await eventSub?.cancel();
        _eventRuntime.agent.stopAutoProcessing();
        _eventRuntime.agent.notificationQueue.accepting = originalAccepting;
        if (!_isEventAgentBusy()) {
          _eventStatusTimer?.cancel();
          _eventStatus = null;
        }
      }
    }
    return {
      'ok': error == null,
      'monitorId': monitorId,
      'monitorName': monitor.name,
      if (monitor.strategyId != null) 'strategyId': monitor.strategyId,
      if (result case final value?) 'result': value,
      'agentMessages': capturedMessages,
      'agentMessageCount': capturedMessages.length,
      'eventAgent': _workflowAutomationEventAgentEvidence(
        messageStartIndex: eventMessagesStart,
        events: eventEvents,
      ),
      'eventQueueLength': _eventRuntime.agent.notificationQueue.length,
      'uiState': _workflowAutomationUiState(),
      'uiEvidence': _workflowAutomationUiSemantics(),
      if (error != null) 'error': error.toString(),
    };
  }

  Future<void> _waitForWorkflowEventAgentCheckpoint({
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_pendingQuestions != null) return;
      if (!_eventRuntime.agent.isRunning &&
          !_eventRuntime.agent.notificationQueue.isNotEmpty) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  Future<Map<String, dynamic>> _waitForWorkflowEventAgentIdle({
    required Duration timeout,
  }) async {
    final startedAt = DateTime.now();
    final deadline = startedAt.add(timeout);
    String reason = 'timeout';
    while (DateTime.now().isBefore(deadline)) {
      if (_pendingQuestions != null) {
        reason = 'pending-user-question';
        break;
      }
      if (!_eventRuntime.agent.isRunning &&
          !_eventRuntime.agent.notificationQueue.isNotEmpty) {
        reason = 'idle';
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    final waitedMs = DateTime.now().difference(startedAt).inMilliseconds;
    final idle =
        !_eventRuntime.agent.isRunning &&
        !_eventRuntime.agent.notificationQueue.isNotEmpty &&
        _pendingQuestions == null;
    return {
      'ok': idle,
      'reason': reason,
      'idle': idle,
      'waitedMs': waitedMs,
      'timedOut': reason == 'timeout',
      'queueLength': _eventRuntime.agent.notificationQueue.length,
      'isRunning': _eventRuntime.agent.isRunning,
      'hasPendingUserQuestion': _pendingQuestions != null,
    };
  }

  Map<String, dynamic> _workflowAutomationEventAgentEvidence({
    required int messageStartIndex,
    required List<AgentEvent> events,
  }) {
    final messages = _eventRuntime.agent.messages.skip(messageStartIndex);
    final toolCalls = <Map<String, dynamic>>[];
    final toolErrors = <Map<String, dynamic>>[];
    String finalAssistantText = '';
    for (final message in messages) {
      for (final toolUse in message.toolUses ?? <ToolUse>[]) {
        toolCalls.add({'toolName': toolUse.name, 'input': toolUse.input});
      }
      final result = message.toolResult;
      if (result != null && result.isError) {
        toolErrors.add({
          'toolUseId': result.toolUseId,
          'content': _truncateWorkflowText(result.content, max: 2000),
        });
      }
      if (message.role == Role.assistant && message.content.trim().isNotEmpty) {
        finalAssistantText = message.content.trim();
      }
    }
    return {
      'messageCount': messages.length,
      'eventCount': events.length,
      'toolCalls': toolCalls,
      'toolErrors': toolErrors,
      'toolCallCount': toolCalls.length,
      'toolErrorCount': toolErrors.length,
      'finalAssistantText': _truncateWorkflowText(
        finalAssistantText,
        max: 4000,
      ),
      'isRunning': _eventRuntime.agent.isRunning,
      'queueLength': _eventRuntime.agent.notificationQueue.length,
      'hasPendingUserQuestion': _pendingQuestions != null,
      if (_pendingQuestions != null)
        'pendingUserQuestions': _pendingQuestions!
            .map((question) => question.toJson())
            .toList(),
    };
  }

  String _assistantTextFromRun(List<AgentEvent> events) {
    final buffer = StringBuffer();
    for (final event in events) {
      if (event is AgentTextDelta) buffer.write(event.text);
    }
    final text = buffer.toString().trim();
    if (text.isNotEmpty) return _truncateWorkflowText(text, max: 4000);
    return _latestAssistantText();
  }

  String _latestAssistantText() {
    for (final message in widget.agent.messages.reversed) {
      if (message.role == Role.assistant && message.content.trim().isNotEmpty) {
        return _truncateWorkflowText(message.content.trim(), max: 4000);
      }
    }
    return '';
  }

  String _truncateWorkflowText(String value, {required int max}) {
    if (value.length <= max) return value;
    return '${value.substring(0, max)}...<truncated>';
  }

  Map<String, dynamic> _workflowAutomationUiState() {
    final dash = _dash;
    final active = dash?.activeDashboard;
    final eventBusy = _isEventAgentBusy();
    return {
      'runtime': 'finagent',
      'chatItemCount': _items.length,
      'eventItemCount': _eventItems.length,
      'isLoading': _isLoading,
      'isEventRunning': eventBusy,
      'eventQueueLength': _eventRuntime.agent.notificationQueue.length,
      'activeTabIndex': dash?.activeTabIndex,
      'chatCollapsed': dash?.chatCollapsed,
      'chatExpanded': dash?.chatExpanded,
      'searchVisible': dash?.searchVisible,
      'dashboardPanelExpanded': dash?.dashboardPanelExpanded,
      'apiHealthPanelVisible': _apiHealthPanelVisible,
      'historyPanelVisible': _historyPanelVisible,
      'sessionPanelVisible': _sessionPanelVisible,
      'strategyArtifactContract': strategyArtifactContract,
      'dashboardCount': dash?.dashboardItems.length ?? 0,
      'strategyLibraryPath': _strategyLibraryPath,
      'strategyItemDir': strategyArtifactPaths(
        widget.agent.toolContext.basePath,
      ).itemDir,
      'strategyLibraryCount': _strategyLibraryCount(),
      if (active != null)
        'activeDashboard': {
          'id': active.id,
          'title': active.title,
          'filePath': active.filePath,
        },
      'sessionId': widget.agent.sessionManager.currentSession?.id,
      'sessionPath': widget.agent.sessionManager.currentSession?.filePath,
      'messages': widget.agent.messages.length,
      'hasPendingUserQuestion': _pendingQuestions != null,
      if (_pendingQuestions != null)
        'pendingUserQuestionCount': _pendingQuestions!.length,
    };
  }

  Map<String, dynamic> _workflowAutomationInteractiveState() {
    final questions = _pendingQuestions ?? const <UserQuestion>[];
    return {
      'hasPendingUserQuestion':
          _pendingQuestions != null && _questionCompleter != null,
      'currentQuestionIndex': _currentQuestionIndex,
      'collectedAnswers': Map<String, String>.from(_collectedAnswers),
      'questions': questions.map((question) => question.toJson()).toList(),
    };
  }

  Future<Map<String, dynamic>> _workflowAutomationAnswerQuestion(
    List<String> answers,
  ) async {
    if (_pendingQuestions == null || _questionCompleter == null) {
      return {'ok': false, 'answered': false};
    }
    final eventMessagesStart = _eventRuntime.agent.messages.length;
    final originalAccepting = _eventRuntime.agent.notificationQueue.accepting;
    StreamSubscription<AgentEvent>? eventSub;
    final eventEvents = <AgentEvent>[];
    if (_workflowAutomationEnabled) {
      _eventRuntime.agent.notificationQueue.accepting = true;
      eventSub = _eventRuntime.agent.startAutoProcessing().listen((event) {
        eventEvents.add(event);
        if (mounted) setState(() => _handleEventAgentEvent(event));
      });
    }
    final answered = _answerQuestions(answers);
    Map<String, dynamic>? waitResult;
    try {
      if (answered && _workflowAutomationEnabled) {
        await Future<void>.delayed(Duration.zero);
        waitResult = await _waitForWorkflowEventAgentIdle(
          timeout: const Duration(seconds: 60),
        );
      }
    } finally {
      if (_workflowAutomationEnabled) {
        await eventSub?.cancel();
        _eventRuntime.agent.stopAutoProcessing();
        _eventRuntime.agent.notificationQueue.accepting = originalAccepting;
        if (!_isEventAgentBusy()) {
          _eventStatusTimer?.cancel();
          _eventStatus = null;
        }
      }
    }
    return {
      'ok': answered,
      'answered': answered,
      'eventAgent': _workflowAutomationEventAgentEvidence(
        messageStartIndex: eventMessagesStart,
        events: eventEvents,
      ),
      if (waitResult != null) 'eventAgentWait': waitResult,
      'interactiveState': _workflowAutomationInteractiveState(),
      'uiState': _workflowAutomationUiState(),
      'uiEvidence': _workflowAutomationUiSemantics(),
    };
  }

  Map<String, dynamic> _workflowAutomationUiSemantics() {
    final dash = _dash;
    final active = dash?.activeDashboard;
    final activeTab = dash?.activeTabIndex;
    final strategyCount = _strategyLibraryCount();
    final eventBusy = _isEventAgentBusy();
    final labels = <String>[
      'FinAgent',
      if (activeTab == 0) 'Chat',
      if (activeTab == 1) 'Watchlist',
      if (activeTab == 2) 'Event',
      if (activeTab == 3) 'Strategy Library',
      if (activeTab == 4) 'Dashboard',
      if (strategyCount > 0) 'Saved strategies: $strategyCount',
      if (dash?.dashboardPanelExpanded == true) 'Dashboard panel expanded',
      if (_apiHealthPanelVisible) 'API Health panel visible',
      if (_historyPanelVisible) 'History panel visible',
      if (_sessionPanelVisible) 'Session panel visible',
      if (active != null) active.title,
      if (_isLoading) 'Agent running',
      if (eventBusy) 'Event agent running',
    ];
    return {
      'runtime': 'finagent',
      'kind': 'semantic-state',
      'labels': labels,
      'activeTabLabel': switch (activeTab) {
        0 => 'Chat',
        1 => 'Watchlist',
        2 => 'Event',
        3 => 'Strategy Library',
        4 => 'Dashboard',
        _ => 'Unknown',
      },
      'strategyLibrary': {
        'artifactContract': strategyArtifactContract,
        'path': _strategyLibraryPath,
        'itemDir': strategyArtifactPaths(
          widget.agent.toolContext.basePath,
        ).itemDir,
        'count': strategyCount,
      },
      'dashboardReady': active != null,
      'apiHealthPanelVisible': _apiHealthPanelVisible,
      'historyPanelVisible': _historyPanelVisible,
      'sessionPanelVisible': _sessionPanelVisible,
      if (active != null)
        'activeDashboard': {'title': active.title, 'filePath': active.filePath},
      'chatItemCount': _items.length,
      'eventItemCount': _eventItems.length,
      'messageCount': widget.agent.messages.length,
    };
  }

  bool _isEventAgentBusy() {
    return _eventRuntime.agent.isRunning ||
        _eventRuntime.agent.notificationQueue.isNotEmpty ||
        _pendingQuestions != null;
  }

  String get _strategyLibraryPath =>
      readableStrategyLibraryPath(widget.agent.toolContext.basePath);

  int _strategyLibraryCount() {
    try {
      final file = File(_strategyLibraryPath);
      if (!file.existsSync()) return 0;
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is List ? decoded.length : 0;
    } catch (_) {
      return 0;
    }
  }

  List<Map<String, dynamic>> _workflowAutomationUiArtifacts() {
    final semantics = _workflowAutomationUiSemantics();
    return [
      {
        'kind': 'mobile-semantic-snapshot',
        'runtime': 'finagent',
        'capturedAt': DateTime.now().toUtc().toIso8601String(),
        'source': 'WorkflowAutomationInProcessBridge',
        'summary': 'FinAgent app-started semantic UI evidence snapshot',
        'semanticLabelCount': (semantics['labels'] as List?)?.length ?? 0,
        'semantics': semantics,
      },
    ];
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _controller.clear();

    // Handle /new command — archive current session and start fresh
    if (text == '/new') {
      if (_isLoading) return;
      widget.agent.clearHistory();
      setState(() {
        _items.clear();
        _tasks = [];
      });
      return;
    }

    if (_pendingQuestions != null && _questionCompleter != null) {
      _answerQuestion(text);
      return;
    }
    if (_isLoading) {
      widget.agent.notificationQueue.enqueue(
        PendingNotification(
          prompt: text,
          priority: NotificationPriority.now,
          source: 'user_input',
        ),
      );
      setState(() => _items.add(ChatItem(role: 'user', content: text)));
      return;
    }
    setState(() {
      _items.add(ChatItem(role: 'user', content: text));
      _items.add(ChatItem(role: 'assistant', content: ''));
      _isLoading = true;
    });
    _listenToStream(widget.agent.run(text));
  }

  void _answerQuestion(String answer) {
    if (_pendingQuestions == null || _questionCompleter == null) return;
    final resolvedAnswer = _resolveQuestionAnswerForIndex(
      answer,
      _currentQuestionIndex,
    );
    setState(() => _items.add(ChatItem(role: 'user', content: resolvedAnswer)));
    if (_pendingQuestions!.length == 1) {
      _questionCompleter!.complete({
        _pendingQuestions!.first.question: resolvedAnswer,
      });
    } else {
      _collectedAnswers[_pendingQuestions![_currentQuestionIndex].question] =
          resolvedAnswer;
      if (_collectedAnswers.length >= _pendingQuestions!.length) {
        _questionCompleter!.complete(Map.of(_collectedAnswers));
        setState(() => _collectedAnswers.clear());
      } else {
        setState(() => _currentQuestionIndex = _collectedAnswers.length);
      }
    }
  }

  String _resolveQuestionAnswerAt(String answer, int index) {
    return _resolveQuestionAnswerForIndex(answer, index);
  }

  String _resolveQuestionAnswerForIndex(String answer, int questionIndex) {
    final trimmed = answer.trim();
    final questions = _pendingQuestions;
    if (questions == null || questions.isEmpty) return trimmed;
    final index = questionIndex.clamp(0, questions.length - 1);
    final options = questions[index].options;
    final optionNumber = int.tryParse(trimmed);
    if (optionNumber != null &&
        optionNumber >= 1 &&
        optionNumber <= options.length) {
      return options[optionNumber - 1].label;
    }
    for (final option in options) {
      if (option.label == trimmed ||
          option.label.contains(trimmed) ||
          trimmed.contains(option.label)) {
        return option.label;
      }
    }
    return trimmed;
  }

  bool _answerQuestions(List<String> answers) {
    if (_pendingQuestions == null || _questionCompleter == null) return false;
    final questions = _pendingQuestions!;
    final boundedAnswers = answers
        .map((answer) => answer.trim())
        .where((answer) => answer.isNotEmpty)
        .toList(growable: false);
    if (boundedAnswers.isEmpty) return false;
    final resolved = <String, String>{};
    for (var i = 0; i < questions.length; i++) {
      final source = i < boundedAnswers.length
          ? boundedAnswers[i]
          : boundedAnswers.last;
      resolved[questions[i].question] = _resolveQuestionAnswerAt(source, i);
    }
    setState(() {
      _collectedAnswers
        ..clear()
        ..addAll(resolved);
      _items.addAll(
        resolved.values.map(
          (answer) => ChatItem(role: 'user', content: answer),
        ),
      );
    });
    _questionCompleter!.complete(Map.of(resolved));
    setState(() => _collectedAnswers.clear());
    return true;
  }

  void _selectOption(String questionText, String optionLabel) {
    if (_questionCompleter == null || _pendingQuestions == null) return;
    setState(() {
      _collectedAnswers[questionText] = optionLabel;
      _items.add(ChatItem(role: 'user', content: optionLabel));
    });
    if (_collectedAnswers.length >= _pendingQuestions!.length) {
      _questionCompleter!.complete(Map.of(_collectedAnswers));
      setState(() => _collectedAnswers.clear());
    } else {
      setState(() => _currentQuestionIndex = _collectedAnswers.length);
    }
  }

  void _cancel() {
    widget.agent.cancel();
    _subscription?.cancel();
    setState(() {
      _isLoading = false;
      if (_items.isNotEmpty &&
          _items.last.role == 'assistant' &&
          _items.last.content.isEmpty) {
        _items.removeLast();
      }
    });
  }

  void _clearHistory() {
    if (_isLoading) return;
    setState(() {
      _items.add(ChatItem(role: 'user', content: '/clear'));
      _isLoading = true;
    });
    _listenToStream(widget.agent.run('/clear'));
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    final toolbar = _buildToolbar();

    final content = Expanded(
      child: DashboardScreen(
        key: _dashKey,
        items: _items,
        isLoading: _isLoading,
        controller: _controller,
        focusNode: _focusNode,
        onSend: _send,
        agentStatus: _agentStatus,
        turnSummary: _turnSummary,
        contextInfo: _contextInfo,
        tasks: _tasks,
        basePath: widget.agent.toolContext.basePath,
        stateKey: 'fin',
        hintText: AppLocalizations.of(context).analyzeMarketHint,
        maxBackgroundTasks: 0,
        onBridgeMessage: _makeBridgeHandler(),
        monitorStore: widget.monitorStore,
        watchlistStore: widget.watchlistStore,
        onWatchlistAnalyze: (symbol) {
          _controller.text = AppLocalizations.of(
            context,
          ).analyzeSymbolPrompt(symbol);
          _send();
        },
        onStrategyAction: (action, item) {
          final normalizedAction = action == 'rerun' && !item.runnable
              ? 'read'
              : action;
          final prompt = buildStrategyActionPrompt(normalizedAction, item);
          _controller.text = prompt;
          _send();
        },
        onCreateStrategy: () {
          _controller.text = AppLocalizations.of(context).strategyCreatePrompt;
          _send();
        },
        onMonitorToggle: (id, enabled) =>
            widget.monitorStore.setEnabled(id, enabled),
        onMonitorDelete: (id) => widget.monitorStore.remove(id),
        notificationStore: widget.notificationStore,
        onCancel: _cancel,
        onCompact: () {
          _controller.text = '/compact';
          _send();
        },
        onClear: _clearHistory,
        onBackground: () => widget.agent.backgroundCurrentTask(),
        onImportHtml: _importHtml,
        onExportDashboard: _exportDashboardItem,
        onDashboardChanged: (item) {
          final l10n = AppLocalizations.of(context);
          final msg = item != null
              ? l10n.dashboardSwitchedTo(item.title, item.filePath)
              : l10n.dashboardClosed;
          widget.agent.addContextHint('dashboard', msg);
          _eventRuntime.agent.addContextHint('dashboard', msg);
          setState(() {});
        },
        onStartBackground: (_) => setState(() {}),
        onStopBackground: (_) => setState(() {}),
        eventItems: _eventItems,
        eventController: _eventController,
        eventFocusNode: _eventFocusNode,
        onEventSend: () {
          _sendToEventAgent();
          if (mounted) setState(() {});
        },
        eventStatus: _isEventAgentBusy() ? _eventStatus : null,
        eventSummary: _eventTurnSummary,
        eventQueueLength: _eventRuntime.agent.notificationQueue.length,
        eventPendingNotifications:
            _eventRuntime.agent.notificationQueue.pending,
        isEventRunning: _isEventAgentBusy(),
        isEventQueuePaused: !_eventRuntime.agent.notificationQueue.accepting,
        eventDroppedCount: _eventRuntime.agent.notificationQueue.droppedCount,
        eventNeedsAttention: _eventNeedsAttention,
        onEventCancel: () {
          _eventRuntime.agent.cancel();
        },
        onEventCompact: () {
          _eventRuntime.agent.notificationQueue.enqueue(
            PendingNotification(
              prompt: '/compact',
              priority: NotificationPriority.now,
              source: 'user_input',
            ),
          );
        },
        onEventClear: () {
          _eventItems.clear();
          _eventPanelNotifier.value++;
        },
        onEventClearQueue: () {
          _eventRuntime.agent.notificationQueue.clear();
          _eventPanelNotifier.value++;
        },
        onEventTogglePause: () {
          _eventRuntime.agent.notificationQueue.accepting =
              !_eventRuntime.agent.notificationQueue.accepting;
          _eventPanelNotifier.value++;
        },
        eventPanelNotifier: _eventPanelNotifier,
        onSelectOption: _selectOption,
        collectedAnswers: _collectedAnswers,
        hasPendingQuestions: _pendingQuestions != null,
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: isLandscape
            ? Row(children: [toolbar, content])
            : Column(children: [toolbar, content]),
      ),
    );
  }
}
