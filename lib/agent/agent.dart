import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'agent_events.dart';
import 'auto_dream.dart';
import 'background_housekeeping.dart';
import 'background_task.dart';
import 'compact.dart';
import 'cron_scheduler.dart';
import 'domain_workflow_hooks.dart';
import 'extract_memories.dart';
import 'llm_client.dart';
import 'magic_docs.dart';
import 'post_turn_hooks.dart';
import 'skill_improvement.dart';
import 'log.dart';
import 'message.dart';
import 'micro_compact.dart';
import 'notification_queue.dart';
import 'prompt_builder.dart';
import 'recap.dart';
import 'session.dart';
import 'session_memory.dart';
import 'slash_command.dart';
import 'speculation.dart';
import 'goal_manager.dart';
import 'goal_judge.dart';
import 'goal_verifier.dart';
import 'tool.dart';
import 'tool_context.dart';
import 'tools/bash_tool/bash_tool.dart';

export 'agent_events.dart';

/// The core Agent loop with session persistence, compaction, and slash commands.
///
/// Reference: Claude Code's query() in query.ts
class Agent {
  LLMClient client;
  final List<Tool> _tools;
  final PromptBuilder _promptBuilder;
  final ToolContext toolContext;
  final SessionManager sessionManager;
  final NotificationQueue notificationQueue = NotificationQueue();
  final CronScheduler? cronScheduler;

  /// Context hints: attached to next LLM call, then cleared.
  /// Same-type hints are deduplicated (only latest kept).
  final Map<String, String> _contextHints = {};

  void addContextHint(String type, String content) {
    final ts = DateTime.now().toIso8601String().substring(11, 19);
    _contextHints[type] = '[$ts] $content';
  }

  String? _drainContextHints() {
    if (_contextHints.isEmpty) return null;
    final lines = _contextHints.values.toList();
    _contextHints.clear();
    return '[Context update]\n${lines.join('\n')}';
  }

  /// LLM context window size (default 200K).
  int contextWindow;

  /// Latest prompt_tokens from API (actual context usage). Persists across turns.
  int lastPromptTokens = 0;

  /// messages.length at the moment lastPromptTokens was recorded, so we can
  /// estimate tokens added by tool results / assistant turns since then.
  int _lastPromptTokensMsgCount = 0;

  /// LLM max output tokens (default 8192).
  final int maxOutputTokens;

  /// History source label for dual-write (for example, 'chat' or a feature id).
  final String historySource;

  /// Batch drain mode: _pump drains all queued notifications at once into a single
  /// run() call. During the agent loop, no new notifications are drained mid-turn.
  /// After the turn completes, _pump fires again to process the next batch.
  bool batchDrainQueue;

  /// Full conversation history, maintained by the Agent.
  final List<Message> messages = [];

  bool _cancelled = false;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  void _setIdle() {
    _isRunning = false;
    _disabledToolsForRun = const {};
    _pump();
  }

  void _scheduleRecap() {
    if (batchDrainQueue) return;
    _recapTimer?.cancel();
    _recapTimer = Timer(_recapDelay, _tryGenerateRecap);
  }

  Future<void> _tryGenerateRecap() async {
    log(
      'Recap',
      '_tryGenerateRecap fired (isRunning=$_isRunning, batch=$batchDrainQueue, userTurns=$_userTurnCount)',
    );
    if (_isRunning) return;
    if (batchDrainQueue) return;
    if (_userTurnCount < 20) return;

    log('Recap', 'Generating away summary...');
    final text = await generateRecap(messages, client.clone());
    if (text == null) return;
    if (_isRunning) return;
    _userTurnCount = 0;

    final msg = Message(
      role: Role.user,
      content: text,
      timestamp: DateTime.now(),
      isRecap: true,
    );
    messages.add(msg);
    sessionManager.currentSession?.appendMessage(msg);
    onRecap?.call(msg);
  }

  int _loopCount = 0;
  String? _lastToolName;
  int _consecutiveToolCount = 0;
  String? _lastToolInputHash;
  int _consecutiveSameInputCount = 0;
  static const _maxConsecutiveSameTool = 100;
  static const _doomLoopThreshold = 3;
  DateTime? _turnStartTime;
  int _turnToolCallCount = 0;
  int _turnDataToolCallCount = 0;
  int _turnDataToolBudgetWarnings = 0;
  int _turnPromptTokens = 0;
  int _turnCompletionTokens = 0;
  int _turnMessageStartIndex = 0; // for history dual-write
  final DomainDataBudgetPolicy _domainDataBudgetPolicy;
  final DomainTurnPolicy _domainTurnPolicy;
  final DomainWorkflowHooks _domainWorkflowHooks;
  StreamController<AgentEvent>? _currentController;
  String? _currentPrompt;
  Set<String> _disabledToolsForRun = const {};

  // Compact state
  int _autoCompactFailures = 0;

  // Max-tokens recovery state
  int _maxTokensRecoveryCount = 0;
  static const _maxTokensRecoveryLimit = 3;
  bool _contextExceededRetried = false;

  // Session memory state
  final SessionMemoryState _sessionMemoryState = SessionMemoryState();

  // Auto dream state
  final AutoDreamState _autoDreamState = AutoDreamState();

  // Skill improvement state
  final SkillImprovementState _skillImprovementState = SkillImprovementState();

  // Magic docs state
  final MagicDocsState _magicDocsState = MagicDocsState();

  // Speculation state
  final SpeculationState _speculationState = SpeculationState();

  // Goal system
  late final GoalManager goalManager;
  late final JudgeFn _goalJudge;

  // Housekeeping: delayed cleanup, runs once
  bool _housekeepingScheduled = false;
  Timer? _housekeepingTimer;

  // Recap: generates a summary after user inactivity
  static const _recapDelay = Duration(minutes: 5);
  Timer? _recapTimer;
  void Function(Message recap)? onRecap;

  // Unified user turn counter — shared by recap, extract_memories, skill_improvement, etc.
  int _userTurnCount = 0;

  // Post-turn hook registry
  final PostTurnHookRegistry postTurnHooks = PostTurnHookRegistry();

  // Slash commands
  late final List<SlashCommand> _commands;

  // Background agent management
  final Map<String, Agent> _backgroundAgents = {};

  Agent({
    required this.client,
    required List<Tool> tools,
    required PromptBuilder promptBuilder,
    required this.toolContext,
    required this.sessionManager,
    this.cronScheduler,
    this.contextWindow = 160000,
    this.maxOutputTokens = 8192,
    this.historySource = 'chat',
    this.batchDrainQueue = false,
    bool enableBackgroundHooks = true,
    DomainDataBudgetPolicy? domainDataBudgetPolicy,
    DomainTurnPolicy? domainTurnPolicy,
    DomainWorkflowHooks? domainWorkflowHooks,
  }) : _tools = tools,
       _domainDataBudgetPolicy =
           domainDataBudgetPolicy ?? const NoopDomainDataBudgetPolicy(),
       _domainTurnPolicy = domainTurnPolicy ?? const NoopDomainTurnPolicy(),
       _domainWorkflowHooks =
           domainWorkflowHooks ?? const NoopDomainWorkflowHooks(),
       _promptBuilder = promptBuilder {
    _commands = getAllCommands(toolContext.basePath);

    // Goal system
    goalManager = GoalManager(toolContext.basePath);
    _goalJudge = createGoalJudge(client);

    // Wire cron scheduler to notification queue
    cronScheduler?.onFire = _onCronFire;

    // Wire session search index to tool context
    toolContext.sessionIndex = sessionManager.sessionIndex;

    // Wire disk-backed task output path
    toolContext.taskRegistry.basePath = toolContext.memoryDir;

    // Set notification queue source policies for goal
    notificationQueue.setSourcePolicy(
      'goal',
      enabled: true,
      minInterval: Duration.zero,
    );
    notificationQueue.setSourcePolicy(
      'goal-status',
      enabled: true,
      minInterval: Duration.zero,
    );

    // Register default post-turn hooks
    postTurnHooks.register('session_memory', _hookSessionMemory);
    if (enableBackgroundHooks) {
      postTurnHooks.register('extract_memories', _hookExtractMemories);
      postTurnHooks.register('auto_dream', _hookAutoDream);
      postTurnHooks.register('skill_improvement', _hookSkillImprovement);
      postTurnHooks.register('magic_docs', _hookMagicDocs);
      postTurnHooks.register('speculation', _hookSpeculation);
    }
    postTurnHooks.register('goal_continuation', _hookGoalContinuation);

    // Initialize magic docs file read listener
    initMagicDocs(_magicDocsState);
  }

  /// Build the current system prompt.
  String get systemPrompt => _promptBuilder.build(tools: _activeTools);

  List<Tool> get _activeTools {
    if (_disabledToolsForRun.isEmpty) return _tools;
    return _tools
        .where((tool) => !_disabledToolsForRun.contains(tool.name))
        .toList(growable: false);
  }

  /// Expose LLMClient baseUrl for sub-agent creation.
  String get clientBaseUrl => client.baseUrl;

  /// Current agent loop iteration count (resets each turn).
  int get loopCount => _loopCount;

  /// Expose PromptBuilder for fork sub-agents.
  PromptBuilder get promptBuilder => _promptBuilder;

  /// Add a tool after construction (for tools that need Agent reference).
  void addTool(Tool tool) => _tools.add(tool);

  T? findTool<T extends Tool>() {
    for (final t in _tools) {
      if (t is T) return t;
    }
    return null;
  }

  /// Restore session on startup. Returns the restored messages.
  List<Message> restoreSession({String? feature}) {
    final (_, restoredMessages) = sessionManager.loadOrCreate(feature: feature);
    messages.addAll(restoredMessages);
    _userTurnCount = 0;
    return restoredMessages;
  }

  /// Run a single turn: user sends a message, agent loops until done.
  /// [imageBytes] — optional image data attached to the user message (multimodal).
  Stream<AgentEvent> run(
    String userMessage, {
    List<Uint8List>? images,
    Uint8List? audioBytes,
    String? audioFormat,
    Set<String> disabledTools = const {},
  }) {
    final controller = StreamController<AgentEvent>();
    _cancelled = false;
    _isRunning = true;
    _recapTimer?.cancel();
    _loopCount = 0;
    _lastToolName = null;
    _consecutiveToolCount = 0;
    _lastToolInputHash = null;
    _consecutiveSameInputCount = 0;
    _turnStartTime = DateTime.now();
    _turnToolCallCount = 0;
    _turnDataToolCallCount = 0;
    _turnDataToolBudgetWarnings = 0;
    _turnPromptTokens = 0;
    _turnCompletionTokens = 0;
    _domainTurnPolicy.reset();
    _currentController = controller;
    _currentPrompt = userMessage;
    _disabledToolsForRun = disabledTools;

    _turnMessageStartIndex = messages.length; // for history dual-write

    // Clear reasoning from historical turns — only keep current turn's reasoning
    for (final msg in messages) {
      msg.reasoning = null;
    }

    // Check for slash commands
    final parsed = parseSlashCommand(userMessage);
    if (parsed != null) {
      _handleSlashCommand(parsed.$1, parsed.$2, controller);
      return controller.stream;
    }

    // Normal message flow
    final msg = Message(
      role: Role.user,
      content: userMessage,
      timestamp: DateTime.now(),
      images: images,
      audioBytes: audioBytes,
      audioFormat: audioFormat,
    );
    messages.add(msg);
    sessionManager.currentSession?.appendMessage(msg);

    _agentLoop(controller);

    return controller.stream;
  }

  /// Cancel the current run.
  void cancel() {
    _cancelled = true;
    client.cancel();
  }

  /// Clear all conversation history and start new session.
  void clearHistory() {
    _recapTimer?.cancel();
    final feature = sessionManager.currentSession?.feature;
    // Trigger final memory extraction before clearing (fire-and-forget).
    // This captures insights from the ending session.
    if (messages.length > 3) {
      extractSessionMemory(
        messages,
        client,
        toolContext,
        _sessionMemoryState,
        sessionManager.sessionsDir,
        sessionManager.currentSession?.id ?? '',
      );
    }

    messages.clear();
    _autoCompactFailures = 0;
    _userTurnCount = 0;
    _sessionMemoryState
      ..lastSummarizedIndex = null
      ..tokensAtLastExtraction = 0
      ..initialized = false;
    sessionManager.archiveAndCreate(feature: feature);
  }

  /// Dual-write this turn's messages to the history file.
  void _appendTurnToHistory() {
    if (_turnMessageStartIndex >= messages.length) return;
    final turnMessages = messages.sublist(_turnMessageStartIndex);
    sessionManager.appendToHistory(turnMessages, source: historySource);
  }

  /// Run agent to completion with a single prompt (used by AgentTool for sync sub-agents).
  Future<String> runToCompletion(String prompt) async {
    final buffer = StringBuffer();
    await for (final event in run(prompt)) {
      if (event is AgentTextDelta) buffer.write(event.text);
      if (event is AgentError) throw Exception(event.message);
    }
    return buffer.toString();
  }

  /// Register a background sub-agent (called by AgentTool).
  void registerBackgroundAgent(String taskId, Agent agent) {
    _backgroundAgents[taskId] = agent;
  }

  /// Remove a background sub-agent reference (called after completion).
  void removeBackgroundAgent(String taskId) {
    _backgroundAgents.remove(taskId);
  }

  /// Cancel a background sub-agent (called by TaskStopTool).
  void cancelBackgroundAgent(String taskId) {
    _backgroundAgents[taskId]?.cancel();
    _backgroundAgents.remove(taskId);
  }

  /// Send a message to a running background agent.
  /// Returns true if delivered, false if agent not found.
  bool sendMessageToAgent(String taskId, String message) {
    final agent = _backgroundAgents[taskId];
    if (agent == null) return false;
    agent.notificationQueue.enqueue(
      PendingNotification(
        prompt: '<teammate-message>\n$message\n</teammate-message>',
        priority: NotificationPriority.now,
        source: 'send_message',
      ),
    );
    return true;
  }

  /// Get a background agent by name (searches task descriptions).
  String? findAgentIdByName(String name) {
    for (final entry in _backgroundAgents.entries) {
      final task = toolContext.taskRegistry.get(entry.key);
      if (task != null && task.description.contains(name)) {
        return entry.key;
      }
    }
    return null;
  }

  /// Move the current foreground task to background (Mobile alternative to Ctrl+B).
  void backgroundCurrentTask() {
    if (!_isRunning) return;

    final task = toolContext.taskRegistry.register(
      description: 'Backgrounded task',
      prompt: _currentPrompt ?? '',
      parentSessionId: sessionManager.currentSession?.id,
      isBackgrounded: true,
    );
    task.status = BackgroundTaskStatus.running;

    // Signal UI to release loading state
    _currentController?.add(AgentBackgrounded(taskId: task.id));
    _currentController?.add(AgentDone());
  }

  /// Handle a cron task firing — enqueue as notification.
  void _onCronFire(CronTask task) {
    notificationQueue.enqueue(
      PendingNotification(
        prompt: task.prompt,
        priority: NotificationPriority.later,
        source: 'cron',
      ),
    );
  }

  /// Enqueue a UI event for the Agent to process when idle.
  void addUIEvent(String action, Map<String, dynamic> params) {
    final paramsXml = params.entries
        .map((e) => '<${e.key}>${e.value}</${e.key}>')
        .join('\n');
    notificationQueue.enqueue(
      PendingNotification(
        prompt: '<ui-event>\n<action>$action</action>\n$paramsXml\n</ui-event>',
        priority: NotificationPriority.next,
        source: 'ui',
      ),
    );
  }

  /// Event-driven pump: process queued notifications when idle.
  /// Replaces Timer-based polling — triggered by enqueue and turn completion.
  StreamController<AgentEvent>? _pumpController;

  Stream<AgentEvent> startAutoProcessing() {
    _pumpController = StreamController<AgentEvent>.broadcast();
    notificationQueue.onEnqueue = _pump;
    return _pumpController!.stream;
  }

  void stopAutoProcessing() {
    notificationQueue.onEnqueue = null;
    _pumpController?.close();
    _pumpController = null;
    _recapTimer?.cancel();
    _housekeepingTimer?.cancel();
    _housekeepingTimer = null;
  }

  /// Try to process the next queued notification.
  /// Safe: all synchronous — _isRunning check and run() setting _isRunning=true
  /// happen without async gaps, so Dart's single-thread guarantees no interleaving.
  void _pump() {
    if (_isRunning) {
      log(
        'Agent',
        'Pump: skipped (agent running), queue=${notificationQueue.length}',
      );
      return;
    }
    if (!notificationQueue.isNotEmpty) {
      log('Agent', 'Pump: skipped (queue empty)');
      return;
    }

    if (batchDrainQueue) {
      // Drain all queued notifications into a single prompt
      final batch = <String>[];
      while (notificationQueue.isNotEmpty) {
        final n = notificationQueue.dequeueNext();
        if (n != null) batch.add(n.prompt);
      }
      if (batch.isEmpty) return;
      final combined = batch.length == 1
          ? batch.first
          : batch.join('\n\n---\n\n');
      log(
        'Agent',
        'Pump: batch processing ${batch.length} notifications (${combined.length} chars)',
      );
      _pumpController?.add(AgentNotificationReceived(combined));
      final stream = run(combined);
      stream.listen(
        (event) {
          _pumpController?.add(event);
        },
        onDone: () {
          log(
            'Agent',
            'Pump: turn done, re-checking queue=${notificationQueue.length}',
          );
          _pump();
        },
      );
    } else {
      final next = notificationQueue.dequeueNext();
      if (next == null) return;
      log(
        'Agent',
        'Pump: processing queued notification (${notificationQueue.length} remaining, source=${next.source})',
      );
      final stream = run(next.prompt);
      stream.listen(
        (event) {
          _pumpController?.add(event);
        },
        onDone: () {
          log(
            'Agent',
            'Pump: turn done, re-checking queue=${notificationQueue.length}',
          );
          _pump();
        },
      );
    }
  }

  /// Handle a slash command.
  Future<void> _handleSlashCommand(
    String command,
    String args,
    StreamController<AgentEvent> controller,
  ) async {
    final cmd = findCommand(command, _commands);
    if (cmd == null) {
      controller.add(
        AgentCommandOutput(
          'Unknown command: /$command. Type /help for available commands.',
        ),
      );
      controller.add(AgentDone());
      await controller.close();
      return;
    }

    try {
      final context = CommandContext(
        sessionManager: sessionManager,
        toolContext: toolContext,
        messages: messages,
        client: client,
        promptBuilder: _promptBuilder,
        goalManager: goalManager,
        compactFn: ({String? customInstructions}) => compactConversation(
          messages,
          client,
          toolContext,
          customInstructions: customInstructions,
        ),
      );

      final result = await cmd.handler(args, context);

      switch (result) {
        case TextCommandResult(:final text):
          controller.add(AgentCommandOutput(text));

        case CompactCommandResult(:final result):
          final preCount = messages.length;
          messages
            ..clear()
            ..addAll(buildPostCompactMessages(result));
          _userTurnCount = 0;
          sessionManager.currentSession?.appendCompactBoundary(
            result.summary,
            result.preCompactMessageCount,
          );
          controller.add(
            AgentCompacted(
              preCompactCount: preCount,
              postCompactCount: messages.length,
            ),
          );
          controller.add(
            AgentCommandOutput(
              'Conversation compacted: $preCount → ${messages.length} messages.',
            ),
          );

        case ClearCommandResult():
          clearHistory();
          controller.add(AgentSessionCleared());
          controller.add(AgentCommandOutput('Session cleared and archived.'));

        case ResumeCommandResult(:final session, :final messages):
          this.messages
            ..clear()
            ..addAll(messages);
          _userTurnCount = 0;
          controller.add(AgentSessionResumed(messages));
          controller.add(
            AgentCommandOutput(
              'Session resumed: ${session.title ?? session.id}',
            ),
          );

        case ListCommandResult(:final prompt, :final sessions):
          final completer = Completer<String?>();
          controller.add(
            AgentSessionList(
              prompt: prompt,
              sessions: sessions,
              completer: completer,
            ),
          );

          final selectedPath = await completer.future;
          if (selectedPath != null) {
            final (session, msgs) = sessionManager.resumeSession(selectedPath);
            messages
              ..clear()
              ..addAll(msgs);
            _userTurnCount = 0;
            controller.add(AgentSessionResumed(msgs));
            controller.add(
              AgentCommandOutput(
                'Session resumed: ${session.title ?? session.id}',
              ),
            );
          } else {
            controller.add(AgentCommandOutput('Resume cancelled.'));
          }

        case PromptCommandResult(:final prompt):
          // File-based command: run the prompt through the agent
          _turnMessageStartIndex = messages.length;
          final userMsg = Message(
            role: Role.user,
            content: prompt,
            timestamp: DateTime.now(),
          );
          messages.add(userMsg);
          sessionManager.currentSession?.appendMessage(userMsg);
          await _agentLoop(controller);
          return; // _agentLoop handles AgentDone

        case GoalSetCommandResult(:final goalPrompt):
          controller.add(
            AgentCommandOutput(
              '⊙ Goal set (max ${goalManager.state?.maxTurns ?? 20} turns). Working...',
            ),
          );
          _turnMessageStartIndex = messages.length;
          final goalMsg = Message(
            role: Role.user,
            content: goalPrompt,
            timestamp: DateTime.now(),
          );
          messages.add(goalMsg);
          sessionManager.currentSession?.appendMessage(goalMsg);
          await _agentLoop(controller);
          return;

        case ForkCommandResult():
          final currentMsgs = List<Message>.from(messages);
          sessionManager.archiveAndCreate(
            feature: sessionManager.currentSession?.feature,
          );
          messages
            ..clear()
            ..addAll(currentMsgs);
          for (final msg in currentMsgs) {
            sessionManager.currentSession?.appendMessage(msg);
          }
          controller.add(
            AgentCommandOutput(
              'Session forked. New session with ${currentMsgs.length} messages. Previous session archived.',
            ),
          );

        case BtwCommandResult(:final question):
          final answer = await _runBtw(question);
          controller.add(AgentCommandOutput('BTW: $question\n\n$answer'));

        case SteerCommandResult(:final text):
          notificationQueue.enqueue(
            PendingNotification(
              prompt: text,
              priority: NotificationPriority.now,
              source: 'user_input',
            ),
          );
          controller.add(
            AgentCommandOutput(
              '⏩ Steer queued — will be seen at the next opportunity.',
            ),
          );

        case ExportCommandResult(:final content, :final filename):
          final exportDir = '${toolContext.basePath}/exports';
          final dir = Directory(exportDir);
          if (!dir.existsSync()) dir.createSync(recursive: true);
          final exportPath = '$exportDir/$filename';
          File(exportPath).writeAsStringSync(content);
          controller.add(
            AgentCommandOutput(
              'Exported to $exportPath (${(content.length / 1024).toStringAsFixed(1)}KB)',
            ),
          );
      }
    } catch (e) {
      controller.add(AgentError('Command error: $e'));
    }

    controller.add(AgentDone());
    await controller.close();
  }

  /// The recursive agent loop.
  Future<void> _agentLoop(StreamController<AgentEvent> controller) async {
    if (_cancelled) {
      _setIdle();
      controller.add(AgentDone());
      await controller.close();
      return;
    }

    _loopCount++;
    log('Agent', 'Loop $_loopCount (${messages.length} messages)');

    // Inject background task notifications (reference: enqueuePendingNotification)
    final notifications = toolContext.taskRegistry.getCompletedUnnotified();
    for (final task in notifications) {
      final notification = Message(
        role: Role.user,
        content:
            '<task-notification>\n'
            '<task_id>${task.id}</task_id>\n'
            '<status>${task.status.name}</status>\n'
            '<description>${task.description}</description>\n'
            '<result>${task.result ?? "No result"}</result>\n'
            '</task-notification>',
        timestamp: DateTime.now(),
      );
      messages.add(notification);
      sessionManager.currentSession?.appendMessage(notification);
      toolContext.taskRegistry.markNotified(task.id);
    }

    // Drain cron/notification queue (skip in fire-and-forget and batch-drain modes)
    // Drain cron/notification queue (skip in batch-drain mode — handled by _pump)
    if (!batchDrainQueue) {
      final queuedMessages = notificationQueue.drainAsMessages();
      for (final msg in queuedMessages) {
        messages.add(msg);
        sessionManager.currentSession?.appendMessage(msg);
      }
    }

    // Sanitize: remove incomplete tool_use/tool_result pairs before sending.
    // This can happen if a previous turn was cancelled mid-tool-execution.
    Session.trimIncompleteToolUse(messages);

    // Strip images from old turns to reduce request size.
    // Keep images from the last 3 user-turns; older images are already saved
    // to files (by _maybePersistResult) with paths noted in content.
    _stripOldImages(messages, keepTurns: 3);

    // Inject context hints (dashboard changes etc.) into the last user message
    final hints = _drainContextHints();
    if (hints != null && messages.isNotEmpty) {
      final lastUserIdx = messages.lastIndexWhere((m) => m.role == Role.user);
      if (lastUserIdx >= 0) {
        messages[lastUserIdx] = Message(
          role: Role.user,
          content: '${messages[lastUserIdx].content}\n\n$hints',
        );
      }
    }

    final textBuffer = StringBuffer();
    final reasoningBuffer = StringBuffer();
    var toolCalls = <ToolUse>[];
    var hasError = false;

    // 通知 UI: LLM 请求开始
    controller.add(AgentStreamStart());

    final preflightFinished = await _runDomainPreflight(controller);
    if (preflightFinished) return;

    // Enforce image budget before sending
    enforceImageBudget(messages);

    final stream = client.sendMessage(
      messages: messages,
      tools: _activeTools,
      systemPrompt: systemPrompt,
      maxOutputTokens: maxOutputTokens,
    );

    String? lastFinishReason;

    await for (final event in stream) {
      if (_cancelled) break;

      switch (event) {
        case SSETextDelta(:final text):
          textBuffer.write(text);
          controller.add(AgentTextDelta(text));
          controller.add(AgentOutputChars(text.length));

        case SSEThinkingDelta(:final text):
          reasoningBuffer.write(text);
          controller.add(AgentThinking(text));

        case SSEToolCall(:final id, :final name, :final arguments):
          toolCalls.add(ToolUse(id: id, name: name, input: arguments));

        case SSEToolCallStart(:final name):
          controller.add(AgentToolCallStreaming(toolName: name));

        case SSEOutputChars(:final chars):
          controller.add(AgentOutputChars(chars));

        case SSEUsage(:final promptTokens, :final completionTokens):
          _turnPromptTokens += promptTokens;
          _turnCompletionTokens += completionTokens;
          goalManager.recordTokenUsage(promptTokens, completionTokens);
          if (promptTokens > 0) {
            lastPromptTokens = promptTokens;
            _lastPromptTokensMsgCount = messages.length;
          }
          controller.add(
            AgentUsage(
              promptTokens: promptTokens,
              completionTokens: completionTokens,
            ),
          );

        case SSEError(:final message):
          hasError = true;
          log('Agent', 'LLM error:', message);
          controller.add(AgentError(message));

        case SSEDone(:final finishReason):
          lastFinishReason = finishReason;
      }
    }

    if (_cancelled || hasError) {
      _setIdle();
      controller.add(
        AgentTurnComplete(
          durationMs: _turnStartTime != null
              ? DateTime.now().difference(_turnStartTime!).inMilliseconds
              : 0,
          toolCallCount: _turnToolCallCount,
          promptTokens: _turnPromptTokens,
          completionTokens: _turnCompletionTokens,
        ),
      );
      controller.add(AgentDone());
      await controller.close();
      return;
    }

    // Handle refusal — Claude declined due to safety concerns
    if (lastFinishReason == 'refusal') {
      log('Agent', 'LLM refused to respond (safety).');
      if (textBuffer.isEmpty) {
        controller.add(AgentTextDelta('[Request refused by the model.]'));
      }
      _setIdle();
      controller.add(AgentDone());
      await controller.close();
      return;
    }

    // Handle context window exceeded — force compact and retry (once)
    if (lastFinishReason == 'context_exceeded') {
      if (_contextExceededRetried) {
        log('Agent', 'Context still exceeded after compact. Stopping.');
        controller.add(
          AgentError('Context window still full after compaction.'),
        );
        _setIdle();
        controller.add(AgentDone());
        await controller.close();
        return;
      }
      _contextExceededRetried = true;
      log('Agent', 'Context window exceeded. Force compacting.');
      controller.add(
        AgentTextDelta('\n[Context window full — compacting...]\n'),
      );
      try {
        final result = await compactConversation(
          messages,
          client,
          toolContext,
          suppressFollowUp: true,
        );
        final preCount = messages.length;
        messages
          ..clear()
          ..addAll(buildPostCompactMessages(result));
        _userTurnCount = 0;
        sessionManager.currentSession?.appendCompactBoundary(
          result.summary,
          result.preCompactMessageCount,
        );
        controller.add(
          AgentCompacted(
            preCompactCount: preCount,
            postCompactCount: messages.length,
          ),
        );
        // Retry the LLM call with compacted context
        return _agentLoop(controller);
      } catch (e) {
        log('Agent', 'Compact failed: $e');
        controller.add(
          AgentError('Context window full and compact failed: $e'),
        );
        _setIdle();
        controller.add(AgentDone());
        await controller.close();
        return;
      }
    }

    // Handle max_tokens truncation — LLM output was cut off
    if (lastFinishReason == 'length') {
      _maxTokensRecoveryCount++;
      log(
        'Agent',
        'Output truncated (max_tokens). Recovery attempt $_maxTokensRecoveryCount/$_maxTokensRecoveryLimit',
      );

      if (_maxTokensRecoveryCount > _maxTokensRecoveryLimit) {
        log('Agent', 'Max recovery attempts reached. Stopping.');
        controller.add(
          AgentError(
            'Output repeatedly truncated after $_maxTokensRecoveryLimit recovery attempts.',
          ),
        );
        _setIdle();
        controller.add(AgentDone());
        await controller.close();
        return;
      }

      // Keep partial text output in conversation (discard incomplete tool calls)
      if (textBuffer.isNotEmpty) {
        final partialMsg = Message(
          role: Role.assistant,
          content: textBuffer.toString(),
          timestamp: DateTime.now(),
        );
        messages.add(partialMsg);
        sessionManager.currentSession?.appendMessage(partialMsg);
      }

      // Don't add a new user message — just re-enter the loop.
      // The partial assistant message is already in messages,
      // so the model will see its own truncated output and continue from there.

      // Continue the loop
      return _agentLoop(controller);
    }

    // Reset recovery counters on successful completion
    _maxTokensRecoveryCount = 0;
    _contextExceededRetried = false;

    var finalText = textBuffer.toString();
    if (toolCalls.isNotEmpty) {
      toolCalls = _domainWorkflowHooks.rewriteToolCalls(
        messages: messages,
        turnStartIndex: _turnMessageStartIndex,
        prompt: _currentPrompt,
        toolCalls: toolCalls,
      );
    }
    if (toolCalls.isEmpty) {
      final rewritten = _domainWorkflowHooks.rewriteFinalAnswer(
        messages: messages,
        turnStartIndex: _turnMessageStartIndex,
        prompt: _currentPrompt,
        answer: finalText,
      );
      if (rewritten != null && rewritten.trim().isNotEmpty) {
        finalText = rewritten.trim();
        controller.add(
          AgentTextDelta('\n\n[Workflow evidence summary]\n$finalText'),
        );
      }
    }

    final assistantMsg = Message(
      role: Role.assistant,
      content: finalText,
      toolUses: toolCalls.isNotEmpty ? toolCalls : null,
      timestamp: DateTime.now(),
      reasoning: reasoningBuffer.isNotEmpty ? reasoningBuffer.toString() : null,
    );
    messages.add(assistantMsg);
    sessionManager.currentSession?.appendMessage(assistantMsg);

    if (toolCalls.isEmpty) {
      if (!_turnUsedTool('MonitorCreate')) {
        final monitorRecovery = await _tryStrategyMonitorBudgetRecovery(
          controller,
        );
        if (monitorRecovery != null) {
          final recoveredMsg = Message(
            role: Role.assistant,
            content: '\n\n$monitorRecovery',
            timestamp: DateTime.now(),
          );
          messages.add(recoveredMsg);
          sessionManager.currentSession?.appendMessage(recoveredMsg);
          controller.add(AgentTextDelta(recoveredMsg.content));
        }
      }
      // No tool calls — conversation turn complete
      log(
        'Agent',
        'Turn complete (no tool calls). Text length: ${finalText.length}',
      );

      // Dual-write this turn's messages to history (before compact may clear messages)
      _appendTurnToHistory();

      await _checkAutoCompact(controller);

      // Fire all post-turn hooks (session memory, extract, dream, etc.)
      try {
        postTurnHooks.fireAll(
          PostTurnContext(
            messages: messages,
            turnStartIndex: _turnMessageStartIndex,
            client: client,
            toolContext: toolContext,
            promptBuilder: _promptBuilder,
            sessionManager: sessionManager,
            turnToolCallCount: _turnToolCallCount,
          ),
        );

        // Schedule background housekeeping once (10 min after first turn)
        if (!_housekeepingScheduled) {
          _housekeepingScheduled = true;
          _housekeepingTimer = Timer(const Duration(minutes: 10), () {
            runBackgroundHousekeeping(toolContext.memoryDir);
            _housekeepingTimer = null;
          });
        }

        _setIdle();
        _userTurnCount++;
        _scheduleRecap();
        controller.add(
          AgentTurnComplete(
            durationMs: _turnStartTime != null
                ? DateTime.now().difference(_turnStartTime!).inMilliseconds
                : 0,
            toolCallCount: _turnToolCallCount,
            promptTokens: _turnPromptTokens,
            completionTokens: _turnCompletionTokens,
          ),
        );
        controller.add(AgentDone());
      } catch (e) {
        log('Agent', 'Turn completion failed: $e');
        _setIdle();
        if (!controller.isClosed) {
          controller.add(AgentError('Turn completion failed: $e'));
          controller.add(AgentDone());
        }
      }
      if (!controller.isClosed) unawaited(controller.close());
      return;
    }

    // Execute tool calls with per-call concurrency classification.
    // Consecutive read-only, no-permission-needed calls are batched for parallel execution.
    // Any non-read-only or permission-needed call starts a serial segment.
    // Detect consecutive same-tool loops
    final toolNames = toolCalls.map((t) => t.name).toSet();
    if (toolNames.length == 1 && toolNames.first == _lastToolName) {
      _consecutiveToolCount += toolCalls.length;
    } else {
      _lastToolName = toolNames.length == 1 ? toolNames.first : null;
      _consecutiveToolCount = toolCalls.length;
    }

    final domainInterception = _domainWorkflowHooks.interceptToolCalls(
      messages: messages,
      turnStartIndex: _turnMessageStartIndex,
      prompt: _currentPrompt,
      toolCalls: toolCalls,
    );
    if (domainInterception != null) {
      _recordDomainSkippedToolCalls(
        toolCalls,
        controller,
        domainInterception.skippedReason,
      );
      await _finishTurnWithAssistantText(domainInterception.answer, controller);
      return;
    }

    if (_wouldExceedDataToolBudget(toolCalls)) {
      _turnDataToolBudgetWarnings++;
      _recordBudgetSkippedToolCalls(toolCalls, controller);
      final monitorRecovery = await _tryStrategyMonitorBudgetRecovery(
        controller,
      );
      if (monitorRecovery != null) {
        final recoveredMsg = Message(
          role: Role.assistant,
          content: monitorRecovery,
          timestamp: DateTime.now(),
        );
        messages.add(recoveredMsg);
        sessionManager.currentSession?.appendMessage(recoveredMsg);
        controller.add(AgentTextDelta(monitorRecovery));
        _setIdle();
        controller.add(
          AgentTurnComplete(
            durationMs: _turnStartTime != null
                ? DateTime.now().difference(_turnStartTime!).inMilliseconds
                : 0,
            toolCallCount: _turnToolCallCount,
            promptTokens: _turnPromptTokens,
            completionTokens: _turnCompletionTokens,
          ),
        );
        controller.add(AgentDone());
        await controller.close();
        return;
      }
      await _finishTurnWithAssistantText(_domainBudgetStopText(), controller);
      return;
    }

    // Doom loop detection: same tool + same input 3 times
    if (toolCalls.length == 1) {
      final inputHash = toolCalls.first.input.toString();
      if (toolCalls.first.name == _lastToolName &&
          inputHash == _lastToolInputHash) {
        _consecutiveSameInputCount++;
      } else {
        _consecutiveSameInputCount = 1;
      }
      _lastToolInputHash = inputHash;

      if (_consecutiveSameInputCount >= _doomLoopThreshold) {
        log(
          'Agent',
          'Doom loop: $_lastToolName called $_consecutiveSameInputCount times with identical input',
        );
        final warningMsg = Message(
          role: Role.tool,
          toolResult: ToolResult(
            toolUseId: toolCalls.first.id,
            content:
                'Warning: You have called "$_lastToolName" $_consecutiveSameInputCount times '
                'with identical arguments. This appears to be a loop. '
                'Try a different approach or different parameters.',
            isError: true,
          ),
          timestamp: DateTime.now(),
        );
        messages.add(warningMsg);
        sessionManager.currentSession?.appendMessage(warningMsg);
        controller.add(
          AgentToolResult(
            toolName: _lastToolName!,
            result: warningMsg.toolResult!.content,
            isError: true,
          ),
        );
        _consecutiveSameInputCount = 0;
        await _agentLoop(controller);
        return;
      }
    }
    if (_consecutiveToolCount >= _maxConsecutiveSameTool) {
      log(
        'Agent',
        'Stopping: $_lastToolName called $_consecutiveToolCount times consecutively',
      );
      final errorMsg = Message(
        role: Role.assistant,
        content:
            'Stopped: tool "$_lastToolName" was called $_consecutiveToolCount times consecutively. '
            'This looks like a loop. Please try a different approach.',
        timestamp: DateTime.now(),
      );
      messages.add(errorMsg);
      sessionManager.currentSession?.appendMessage(errorMsg);
      controller.add(AgentTextDelta(errorMsg.content));
      _setIdle();
      controller.add(
        AgentTurnComplete(
          durationMs: _turnStartTime != null
              ? DateTime.now().difference(_turnStartTime!).inMilliseconds
              : 0,
          toolCallCount: _turnToolCallCount,
          promptTokens: _turnPromptTokens,
          completionTokens: _turnCompletionTokens,
        ),
      );
      controller.add(AgentDone());
      await controller.close();
      return;
    }

    await _executeToolCalls(toolCalls, controller);

    // Check for auto compact between tool call rounds (not just at turn end)
    await _checkAutoCompact(controller);

    // Loop: send tool results back to LLM
    await _agentLoop(controller);
  }

  Future<bool> _runDomainPreflight(
    StreamController<AgentEvent> controller,
  ) async {
    const maxPreflightBatches = 4;
    for (var i = 0; i < maxPreflightBatches; i++) {
      final existingAnswer = _domainWorkflowHooks.buildPreflightAnswer(
        messages,
      );
      if (existingAnswer != null) {
        await _finishTurnWithAssistantText(existingAnswer, controller);
        return true;
      }
      final calls = _domainWorkflowHooks.buildPreflightToolCalls(messages);
      if (calls == null || calls.isEmpty) return false;
      final assistantMsg = Message(
        role: Role.assistant,
        content: '',
        toolUses: calls,
        timestamp: DateTime.now(),
      );
      messages.add(assistantMsg);
      sessionManager.currentSession?.appendMessage(assistantMsg);
      await _executeToolCalls(calls, controller);
      final answer = _domainWorkflowHooks.buildPreflightAnswer(messages);
      if (answer != null) {
        await _finishTurnWithAssistantText(answer, controller);
        return true;
      }
    }
    return false;
  }

  bool _wouldExceedDataToolBudget(List<ToolUse> toolCalls) {
    return _domainDataBudgetPolicy.wouldExceedBudget(
      prompt: _currentPrompt,
      currentDataToolCalls: _turnDataToolCallCount,
      existingBudgetWarnings: _turnDataToolBudgetWarnings,
      proposedToolCalls: toolCalls,
    );
  }

  void _recordDomainSkippedToolCalls(
    List<ToolUse> toolCalls,
    StreamController<AgentEvent> controller,
    String reason,
  ) {
    for (final toolCall in toolCalls) {
      final result = ToolResult(
        toolUseId: toolCall.id,
        content: reason,
        isError: false,
      );
      final toolMsg = Message(
        role: Role.tool,
        toolResult: result,
        timestamp: DateTime.now(),
      );
      messages.add(toolMsg);
      sessionManager.currentSession?.appendMessage(toolMsg);
      controller.add(
        AgentToolResult(
          toolName: toolCall.name,
          result: result.content,
          isError: false,
        ),
      );
    }
  }

  Future<void> _finishTurnWithAssistantText(
    String text,
    StreamController<AgentEvent> controller,
  ) async {
    final msg = Message(
      role: Role.assistant,
      content: text,
      timestamp: DateTime.now(),
    );
    messages.add(msg);
    sessionManager.currentSession?.appendMessage(msg);
    controller.add(AgentTextDelta(text));
    _appendTurnToHistory();
    await _checkAutoCompact(controller);
    _setIdle();
    _userTurnCount++;
    _scheduleRecap();
    controller.add(
      AgentTurnComplete(
        durationMs: _turnStartTime != null
            ? DateTime.now().difference(_turnStartTime!).inMilliseconds
            : 0,
        toolCallCount: _turnToolCallCount,
        promptTokens: _turnPromptTokens,
        completionTokens: _turnCompletionTokens,
      ),
    );
    controller.add(AgentDone());
    if (!controller.isClosed) await controller.close();
  }

  void _recordBudgetSkippedToolCalls(
    List<ToolUse> toolCalls,
    StreamController<AgentEvent> controller,
  ) {
    for (final toolCall in toolCalls) {
      final result = ToolResult(
        toolUseId: toolCall.id,
        content:
            'Domain workflow budget reached before executing this extra call. '
            'No external request was made for this skipped call. '
            'Answer now from existing session evidence, disclose source and freshness when relevant, '
            'and list missing evidence as a limitation instead of trying unrelated tools.',
        isError: false,
      );
      final toolMsg = Message(
        role: Role.tool,
        toolResult: result,
        timestamp: DateTime.now(),
      );
      messages.add(toolMsg);
      sessionManager.currentSession?.appendMessage(toolMsg);
      controller.add(
        AgentToolResult(
          toolName: toolCall.name,
          result: result.content,
          isError: false,
        ),
      );
    }
  }

  String _domainBudgetStopText() {
    return _domainWorkflowHooks.buildBudgetStopText(
      messages: messages,
      turnStartIndex: _turnMessageStartIndex,
      prompt: _currentPrompt,
      failureSummary: _turnFailureSummary(),
    );
  }

  String _turnFailureSummary() {
    final failures = <String>[];
    var skipped = 0;
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null) continue;
      if (result.isError) {
        failures.add(result.content.replaceAll(RegExp(r'\s+'), ' ').trim());
      } else if (result.content.contains('Domain workflow budget reached')) {
        skipped++;
      }
    }
    final parts = <String>[
      if (failures.isEmpty) '无阻断性工具错误' else failures.take(3).join('；'),
      if (skipped > 0) '预算保护跳过 $skipped 个额外调用，未发出 provider 请求',
    ];
    return parts.join('；');
  }

  Future<String?> _tryStrategyMonitorBudgetRecovery(
    StreamController<AgentEvent> controller,
  ) async {
    return _domainWorkflowHooks.buildRecovery(
      prompt: _currentPrompt,
      messages: messages,
      toolByName: _toolByName,
      callTool: (tool, toolUseId, input) =>
          _callRecoveryTool(tool, toolUseId, input, controller),
    );
  }

  Future<ToolResult> _callRecoveryTool(
    Tool tool,
    String toolUseId,
    Map<String, dynamic> input,
    StreamController<AgentEvent> controller,
  ) async {
    final toolUseMessage = Message(
      role: Role.assistant,
      content: '',
      toolUses: [ToolUse(id: toolUseId, name: tool.name, input: input)],
      timestamp: DateTime.now(),
    );
    messages.add(toolUseMessage);
    sessionManager.currentSession?.appendMessage(toolUseMessage);
    final result = await tool.call(toolUseId, input, toolContext);
    final message = Message(
      role: Role.tool,
      toolResult: ToolResult(
        toolUseId: toolUseId,
        content: result.content,
        isError: result.isError,
      ),
      timestamp: DateTime.now(),
    );
    messages.add(message);
    sessionManager.currentSession?.appendMessage(message);
    controller.add(
      AgentToolResult(
        toolName: tool.name,
        result: result.content,
        isError: result.isError,
      ),
    );
    return result;
  }

  Tool? _toolByName(String name) {
    for (final tool in _tools) {
      if (tool.name == name) return tool;
    }
    return null;
  }

  bool _turnUsedTool(String toolName) {
    for (final message in messages.skip(_turnMessageStartIndex)) {
      final uses = message.toolUses;
      if (uses == null) continue;
      if (uses.any((use) => use.name == toolName)) return true;
    }
    return false;
  }

  /// Check and perform auto compaction if needed.
  Future<void> _checkAutoCompact(
    StreamController<AgentEvent> controller,
  ) async {
    if (_autoCompactFailures >= maxConsecutiveAutocompactFailures) return;

    // Prefer real prompt_tokens from API, plus estimated tokens for messages
    // added since the last API response (tool results, assistant turns).
    int currentTokens;
    if (lastPromptTokens > 0) {
      final newMsgs = messages.length > _lastPromptTokensMsgCount
          ? messages.sublist(_lastPromptTokensMsgCount)
          : <Message>[];
      currentTokens = lastPromptTokens + estimateTokenCount(newMsgs);
    } else {
      currentTokens = estimateTokenCount(messages);
    }
    final effectiveWindow = contextWindow - maxOutputTokens.clamp(0, 20000);
    final threshold = effectiveWindow - autocompactBufferTokens;
    log(
      'Agent',
      'Auto-compact check: ${messages.length} msgs, '
          '${lastPromptTokens > 0 ? "" : "~"}$currentTokens tokens, '
          'threshold=$threshold, contextWindow=$contextWindow',
    );

    if (currentTokens <= threshold) {
      return;
    }

    try {
      // Try micro compact first (free, no LLM call)
      if (tryMicroCompact(messages)) {
        // Re-check if micro compact was sufficient
        if (!shouldAutoCompact(
          messages,
          contextWindow: contextWindow,
          maxOutputTokens: maxOutputTokens,
        )) {
          log('Agent', 'Micro compact was sufficient');
          return;
        }
      }

      // Try session memory compact (free path)
      final smResult = await trySessionMemoryCompaction(
        messages,
        toolContext,
        _sessionMemoryState,
        sessionManager.sessionsDir,
        sessionManager.currentSession?.id ?? '',
        contextWindow: contextWindow,
        maxOutputTokens: maxOutputTokens,
      );

      if (smResult != null) {
        final preCount = messages.length;
        messages
          ..clear()
          ..addAll(buildPostCompactMessages(smResult));
        _userTurnCount = 0;
        sessionManager.currentSession?.appendCompactBoundary(
          smResult.summary,
          smResult.preCompactMessageCount,
        );
        _autoCompactFailures = 0;
        _sessionMemoryState.lastSummarizedIndex = null;
        toolContext.taskStore.removeCompleted();
        controller.add(
          AgentCompacted(
            preCompactCount: preCount,
            postCompactCount: messages.length,
          ),
        );
        return;
      }

      // Fall back to traditional compact
      final result = await compactConversation(
        messages,
        client,
        toolContext,
        suppressFollowUp: true,
      );

      final preCount = messages.length;
      messages
        ..clear()
        ..addAll(buildPostCompactMessages(result));
      _userTurnCount = 0;
      sessionManager.currentSession?.appendCompactBoundary(
        result.summary,
        result.preCompactMessageCount,
      );
      _autoCompactFailures = 0;
      _sessionMemoryState.lastSummarizedIndex = null;
      toolContext.taskStore.removeCompleted();
      _sessionMemoryState.lastSummarizedIndex = null;
      controller.add(
        AgentCompacted(
          preCompactCount: preCount,
          postCompactCount: messages.length,
        ),
      );
    } catch (e) {
      _autoCompactFailures++;
    }
  }

  /// Check and trigger session memory extraction (non-blocking).
  Future<void> _hookSessionMemory(PostTurnContext ctx) async {
    if (!shouldExtractMemory(ctx.messages, _sessionMemoryState)) return;
    extractSessionMemory(
      ctx.messages,
      ctx.client.clone(),
      ctx.toolContext,
      _sessionMemoryState,
      ctx.sessionManager.sessionsDir,
      ctx.sessionManager.currentSession?.id ?? '',
    );
  }

  /// Check and trigger extract memories (non-blocking, fire-and-forget).
  /// Throttled: at least 20 user turns AND 30 minutes since last run.
  DateTime _lastExtractMemories = DateTime(2000);
  Future<void> _hookExtractMemories(PostTurnContext ctx) async {
    if (_userTurnCount < 20) return;
    final now = DateTime.now();
    if (now.difference(_lastExtractMemories).inMinutes < 30) return;
    _lastExtractMemories = now;
    await runExtractMemories(
      messages: ctx.messages,
      turnStartIndex: ctx.turnStartIndex,
      client: ctx.client,
      toolContext: ctx.toolContext,
      promptBuilder: ctx.promptBuilder,
      sessionManager: ctx.sessionManager,
    );
  }

  /// Check and trigger auto dream (non-blocking, fire-and-forget).
  Future<void> _hookAutoDream(PostTurnContext ctx) async {
    await maybeRunAutoDream(
      client: ctx.client,
      toolContext: ctx.toolContext,
      promptBuilder: ctx.promptBuilder,
      sessionManager: ctx.sessionManager,
      state: _autoDreamState,
    );
  }

  /// Check and trigger skill improvement (non-blocking, fire-and-forget).
  Future<void> _hookSkillImprovement(PostTurnContext ctx) async {
    await hookSkillImprovement(ctx, _skillImprovementState);
  }

  /// Check and trigger magic docs update (non-blocking, fire-and-forget).
  Future<void> _hookMagicDocs(PostTurnContext ctx) async {
    await hookMagicDocs(ctx, _magicDocsState);
  }

  /// Check and trigger speculation (non-blocking, fire-and-forget).
  Future<void> _hookSpeculation(PostTurnContext ctx) async {
    await hookSpeculation(ctx, _speculationState, (suggestion) {
      _currentController?.add(AgentSuggestion(suggestion));
    });
  }

  Future<void> _hookGoalContinuation(PostTurnContext ctx) async {
    if (!goalManager.isActive) return;

    final assistantMsgs = ctx.messages.where((m) => m.role == Role.assistant);
    if (assistantMsgs.isEmpty) return;
    final lastResponse = assistantMsgs.last.content;
    if (lastResponse.trim().isEmpty) return;

    final decision = await goalManager.evaluateAfterTurn(
      lastResponse,
      _goalJudge,
      (state, judgment) =>
          verifyGoalState(state, judgment, basePath: ctx.toolContext.basePath),
    );

    if (decision.message.isNotEmpty) {
      notificationQueue.enqueue(
        PendingNotification(
          prompt: decision.message,
          priority: NotificationPriority.now,
          source: 'goal-status',
          isMeta: true,
        ),
      );
    }
    if (decision.shouldContinue && decision.continuationPrompt != null) {
      notificationQueue.enqueue(
        PendingNotification(
          prompt: decision.continuationPrompt!,
          priority: NotificationPriority.next,
          source: 'goal',
        ),
      );
    }
  }

  Future<String> _runBtw(String question) async {
    const btwSystemPrompt =
        'You are answering an ephemeral /btw side question about the current conversation.\n'
        'Use the conversation only as background context.\n'
        'Answer only the side question in the last user message.\n'
        'Do not continue, resume, or complete any unfinished task from the conversation.\n'
        'Do not emit tool calls or code unless the side question explicitly asks for them.\n'
        'If the question can be answered briefly, answer briefly.';

    final contextMessages = messages
        .where((m) => m.role == Role.user || m.role == Role.assistant)
        .toList()
        .reversed
        .take(30)
        .toList()
        .reversed
        .toList();

    contextMessages.add(
      Message(
        role: Role.user,
        content:
            'Answer this side question only. Ignore any unfinished task in the conversation.\n\n'
            '<btw_side_question>\n$question\n</btw_side_question>',
        timestamp: DateTime.now(),
      ),
    );

    final parts = <String>[];
    try {
      await for (final ev in client.sendMessage(
        systemPrompt: btwSystemPrompt,
        messages: contextMessages,
        tools: [],
      )) {
        if (ev is SSETextDelta) parts.add(ev.text);
      }
    } catch (e) {
      return 'Side question failed: $e';
    }
    return parts.join().trim().isEmpty
        ? 'No response generated.'
        : parts.join();
  }

  Future<ToolResult> _executeTool(Tool tool, ToolUse toolUse) async {
    try {
      toolContext.eventSink = _currentController?.sink;
      // BashTool uses its own onProgress callback for stdout streaming
      if (tool is BashTool) {
        tool.onProgress = (toolUseId, output, elapsedMs) {
          _currentController?.add(
            AgentToolProgress(
              toolName: 'Bash',
              output: output,
              elapsedMs: elapsedMs,
            ),
          );
        };
      }
      final result = await tool.call(toolUse.id, toolUse.input, toolContext);
      if (tool is BashTool) tool.onProgress = null;
      toolContext.eventSink = null;
      return result;
    } catch (e) {
      toolContext.eventSink = null;
      return ToolResult(
        toolUseId: toolUse.id,
        content: 'Error executing tool: $e',
        isError: true,
      );
    }
  }

  /// Execute tool calls with per-call concurrency classification.
  ///
  /// Consecutive read-only, no-permission-needed calls batch into
  /// parallel execution (Future.wait). Any non-safe call triggers
  /// a serial segment.
  Future<void> _executeToolCalls(
    List<ToolUse> toolCalls,
    StreamController<AgentEvent> controller,
  ) async {
    int i = 0;
    final activeTools = _activeTools;
    while (i < toolCalls.length && !_cancelled) {
      // Classify: find a batch of consecutive same-name, parallelizable calls
      final batchStart = i;
      final batchToolName = toolCalls[i].name;
      while (i < toolCalls.length) {
        final tu = toolCalls[i];
        if (tu.name != batchToolName) break;
        final tool = activeTools.where((t) => t.name == tu.name).firstOrNull;
        if (tool == null || !tool.canRunInParallel(tu.input)) break;
        final needsConfirm =
            toolContext.needsPermission(tu.name) &&
            tool.needsPermissions(tu.input);
        if (needsConfirm) break;
        i++;
      }

      final batchEnd = i;
      if (batchEnd > batchStart) {
        // Parallel batch: all are read-only, no permission needed
        final batch = toolCalls.sublist(batchStart, batchEnd);
        if (batch.length == 1) {
          final shouldContinue = await _executeSingleToolCall(
            batch.first,
            controller,
          );
          if (!shouldContinue) {
            _recordSkippedToolCalls(toolCalls, batchStart + 1, controller);
            break;
          }
        } else {
          // Notify UI for all
          for (final tu in batch) {
            controller.add(
              AgentToolUseStart(toolName: tu.name, input: tu.input),
            );
          }

          // Execute in parallel
          final stopwatch = Stopwatch()..start();
          final futures = batch.map((tu) {
            final tool = activeTools.firstWhere((t) => t.name == tu.name);
            return _executeSafeToolCall(tool, tu);
          }).toList();
          final results = await Future.wait(futures);
          stopwatch.stop();

          // Record results in order
          for (int j = 0; j < batch.length; j++) {
            final tu = batch[j];
            var result = results[j];
            _turnToolCallCount++;
            if (_domainDataBudgetPolicy.isDataTool(tu.name)) {
              _turnDataToolCallCount++;
            }
            result = _maybePersistResult(result);
            _domainTurnPolicy.recordToolResult(tu, result);
            final shouldStopBatch = _domainTurnPolicy
                .shouldStopToolBatchAfterResult(tu, result);

            log(
              'Agent',
              '${tu.name} →',
              result.isError ? 'ERROR: ${result.content}' : 'OK',
            );

            final toolMsg = Message(
              role: Role.tool,
              toolResult: result,
              timestamp: DateTime.now(),
            );
            messages.add(toolMsg);
            sessionManager.currentSession?.appendMessage(toolMsg);

            controller.add(
              AgentToolResult(
                toolName: tu.name,
                result: result.content,
                isError: result.isError,
                durationMs: stopwatch.elapsedMilliseconds ~/ batch.length,
              ),
            );
            if (shouldStopBatch) {
              _recordSkippedToolCalls(
                toolCalls,
                batchStart + j + 1,
                controller,
              );
              return;
            }
          }
        }
      }

      // Serial: execute the next non-safe call (if any)
      if (i < toolCalls.length && !_cancelled) {
        final currentIndex = i;
        final shouldContinue = await _executeSingleToolCall(
          toolCalls[currentIndex],
          controller,
        );
        if (!shouldContinue) {
          _recordSkippedToolCalls(toolCalls, currentIndex + 1, controller);
          break;
        }
        i++;
      }
    }
  }

  /// Execute a single tool call with full permission handling and result persistence.
  ///
  /// Returns false when the current assistant-issued tool batch must not
  /// continue, for example after an explicit user permission rejection.
  Future<bool> _executeSingleToolCall(
    ToolUse toolUse,
    StreamController<AgentEvent> controller,
  ) async {
    controller.add(
      AgentToolUseStart(toolName: toolUse.name, input: toolUse.input),
    );

    final stopwatch = Stopwatch()..start();
    final activeTools = _activeTools;
    final tool = activeTools.where((t) => t.name == toolUse.name).firstOrNull;
    ToolResult result;
    var shouldContinueBatch = true;

    if (tool == null) {
      // Tool call repair: try case-insensitive and fuzzy matching
      final repaired = _repairToolLookup(toolUse.name);
      if (repaired != null) {
        log(
          'Agent',
          'Repaired tool name: "${toolUse.name}" → "${repaired.name}"',
        );
        result = await _executeTool(repaired, toolUse);
      } else {
        final available = activeTools.map((t) => t.name).join(', ');
        log('Agent', 'Unknown tool: ${toolUse.name}');
        result = ToolResult(
          toolUseId: toolUse.id,
          content:
              'Unknown tool "${toolUse.name}". '
              'Available tools: $available',
          isError: true,
        );
      }
    } else {
      final guardedError = _domainTurnPolicy.blockedToolUseReason(toolUse);
      if (guardedError != null) {
        result = ToolResult(
          toolUseId: toolUse.id,
          content: guardedError,
          isError: true,
        );
      } else {
        final validationError = await tool.validateInput(
          toolUse.input,
          toolContext,
        );
        if (validationError != null) {
          log(
            'Agent',
            '${toolUse.name} validation error:',
            '$validationError input: ${toolUse.input}',
          );
          result = ToolResult(
            toolUseId: toolUse.id,
            content: 'Validation error: $validationError',
            isError: true,
          );
        } else {
          final needsConfirm =
              toolContext.needsPermission(toolUse.name) &&
              tool.needsPermissions(toolUse.input);

          if (needsConfirm) {
            final completer = Completer<ToolConfirmResult>();
            controller.add(
              AgentToolConfirmRequest(
                toolName: toolUse.name,
                input: toolUse.input,
                completer: completer,
              ),
            );

            final confirmResult = await completer.future;
            if (!confirmResult.approved) {
              final reason = confirmResult.rejectReason;
              result = ToolResult(
                toolUseId: toolUse.id,
                content: reason != null && reason.isNotEmpty
                    ? 'Tool use was rejected by the user. Feedback: $reason'
                    : 'Tool use was rejected by the user.',
                isError: true,
              );
              shouldContinueBatch = false;
            } else {
              if (confirmResult.alwaysAllow) {
                toolContext.approveTool(toolUse.name, persist: true);
              }
              result = await _executeTool(tool, toolUse);
            }
          } else {
            result = await _executeTool(tool, toolUse);
          }
        }
      }
    }

    stopwatch.stop();
    _turnToolCallCount++;
    if (_domainDataBudgetPolicy.isDataTool(toolUse.name)) {
      _turnDataToolCallCount++;
    }
    result = _maybePersistResult(result);
    _domainTurnPolicy.recordToolResult(toolUse, result);
    if (_domainTurnPolicy.shouldStopToolBatchAfterResult(toolUse, result)) {
      shouldContinueBatch = false;
    }

    log(
      'Agent',
      '${toolUse.name} →',
      result.isError ? 'ERROR: ${result.content}' : 'OK',
    );

    final toolMsg = Message(
      role: Role.tool,
      toolResult: result,
      timestamp: DateTime.now(),
    );
    messages.add(toolMsg);
    sessionManager.currentSession?.appendMessage(toolMsg);

    controller.add(
      AgentToolResult(
        toolName: toolUse.name,
        result: result.content,
        isError: result.isError,
        durationMs: stopwatch.elapsedMilliseconds,
      ),
    );

    // Emit task list changes after task tools
    if (toolUse.name == 'TaskCreate' || toolUse.name == 'TaskUpdate') {
      controller.add(
        AgentTasksChanged(
          toolContext.taskStore.list().map((t) => t.toSummary()).toList(),
        ),
      );
    }

    return shouldContinueBatch;
  }

  void _recordSkippedToolCalls(
    List<ToolUse> toolCalls,
    int startIndex,
    StreamController<AgentEvent> controller,
  ) {
    for (var j = startIndex; j < toolCalls.length; j++) {
      final skipped = toolCalls[j];
      final result = ToolResult(
        toolUseId: skipped.id,
        content:
            'Skipped: a previous tool call in this assistant response was rejected by the user.',
        isError: true,
      );
      final toolMsg = Message(
        role: Role.tool,
        toolResult: result,
        timestamp: DateTime.now(),
      );
      messages.add(toolMsg);
      sessionManager.currentSession?.appendMessage(toolMsg);
      controller.add(
        AgentToolResult(
          toolName: skipped.name,
          result: result.content,
          isError: true,
        ),
      );
    }
  }

  /// Execute a safe (read-only, no-permission) tool call. Used in parallel batches.
  Future<ToolResult> _executeSafeToolCall(Tool tool, ToolUse toolUse) async {
    final validationError = await tool.validateInput(
      toolUse.input,
      toolContext,
    );
    if (validationError != null) {
      return ToolResult(
        toolUseId: toolUse.id,
        content: 'Validation error: $validationError',
        isError: true,
      );
    }
    return _executeTool(tool, toolUse);
  }

  /// Try to repair a misnamed tool call via case-insensitive or fuzzy matching.
  Tool? _repairToolLookup(String name) {
    final lower = name.toLowerCase();
    final activeTools = _activeTools;
    // Case-insensitive exact match
    for (final t in activeTools) {
      if (t.name.toLowerCase() == lower) return t;
    }
    // Substring match (tool name contains query or query contains tool name)
    for (final t in activeTools) {
      final tLower = t.name.toLowerCase();
      if (tLower.contains(lower) || lower.contains(tLower)) return t;
    }
    return null;
  }

  /// Persist oversized tool results to file.
  ToolResult _maybePersistResult(ToolResult result) {
    var updatedResult = result;
    if (result.images != null &&
        result.images!.isNotEmpty &&
        (result.imagePaths == null || result.imagePaths!.isEmpty)) {
      // Images not yet saved — persist them now
      final outputDir = '${toolContext.memoryDir}/.screenshots';
      Directory(outputDir).createSync(recursive: true);
      final paths = <String>[];
      final imageInfos = <String>[];
      for (var i = 0; i < result.images!.length; i++) {
        final bytes = result.images![i];
        final ts = DateTime.now().microsecondsSinceEpoch;
        final filePath = '$outputDir/${ts}_$i.png';
        File(filePath).writeAsBytesSync(bytes);
        paths.add(filePath);
        final sizeKb = (bytes.length / 1024).toStringAsFixed(1);
        String dims = '';
        if (bytes.length > 24 && bytes[0] == 0x89 && bytes[1] == 0x50) {
          final w =
              (bytes[16] << 24) |
              (bytes[17] << 16) |
              (bytes[18] << 8) |
              bytes[19];
          final h =
              (bytes[20] << 24) |
              (bytes[21] << 16) |
              (bytes[22] << 8) |
              bytes[23];
          dims = ', ${w}x${h}px';
        }
        imageInfos.add('Image saved: $filePath (${sizeKb}KB$dims)');
      }
      updatedResult = ToolResult(
        toolUseId: result.toolUseId,
        content: '${result.content}\n${imageInfos.join('\n')}',
        images: result.images,
        imagePaths: paths,
        isError: result.isError,
      );
    }

    const maxToolResultChars = 30000;
    if (updatedResult.content.length <= maxToolResultChars) {
      return updatedResult;
    }

    final fileName = 'tool_output_${DateTime.now().millisecondsSinceEpoch}.txt';
    final outputDir = '${toolContext.memoryDir}/.tool_outputs';
    Directory(outputDir).createSync(recursive: true);
    final filePath = '$outputDir/$fileName';
    File(filePath).writeAsStringSync(updatedResult.content);

    final compactJson = _compactPersistedJsonResult(
      updatedResult.content,
      filePath: filePath,
    );
    final preview = compactJson ?? updatedResult.content.substring(0, 2000);
    return ToolResult(
      toolUseId: updatedResult.toolUseId,
      content: compactJson ??
          '$preview\n\n'
              '... (${updatedResult.content.length} chars total, '
              'full output was persisted in diagnostic tool-output storage at $filePath. '
              'For normal answers, use this preview and call a narrower query '
              'with limit/filters or a code-owned summary action instead of reading '
              'the full generated output.)',
      images: updatedResult.images,
      imagePaths: updatedResult.imagePaths,
      isError: updatedResult.isError,
    );
  }

  String? _compactPersistedJsonResult(
    String content, {
    required String filePath,
  }) {
    final text = content.trimLeft();
    if (!text.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return null;
      final compact = <String, dynamic>{};
      const preserveKeys = [
        'action',
        'interfaceId',
        'provider',
        'capabilityId',
        'cacheStatus',
        'cacheMode',
        'cachePolicyMode',
        'cacheDecision',
        'canonicalSchema',
        'canonicalTable',
        'sourceDataTime',
        'fetchedAt',
        'count',
        'source',
        'symbol',
        'fundCodes',
        'seriesSummary',
        'provenance',
        'status',
        'missingReason',
      ];
      for (final key in preserveKeys) {
        if (decoded.containsKey(key)) compact[key] = decoded[key];
      }
      _copyCompactedRows(decoded, compact, 'data');
      _copyCompactedRows(decoded, compact, 'rows');
      compact['diagnosticOutputPath'] = filePath;
      compact['diagnosticTruncated'] = true;
      compact['diagnosticOriginalChars'] = content.length;
      return const JsonEncoder.withIndent('  ').convert(compact);
    } catch (_) {
      return null;
    }
  }

  void _copyCompactedRows(
    Map<String, dynamic> decoded,
    Map<String, dynamic> compact,
    String key,
  ) {
    final value = decoded[key];
    if (value is! List) return;
    const headCount = 12;
    const tailCount = 3;
    final head = value.take(headCount).toList(growable: false);
    final tailStart = value.length - tailCount < headCount
        ? headCount
        : value.length - tailCount;
    final tail = value.length > headCount
        ? value.skip(tailStart).toList(growable: false)
        : const [];
    compact[key] = [...head, ...tail];
    compact['${key}PreviewCount'] = head.length + tail.length;
    compact['${key}OriginalCount'] = value.length;
    final omitted = value.length - head.length - tail.length;
    compact['${key}OmittedCount'] = omitted < 0 ? 0 : omitted;
  }

  /// Strip images from messages older than [keepTurns] user turns.
  /// Counts user messages from the end; messages before that cutoff have
  /// their images nulled out (the files are already saved on disk).
  static void _stripOldImages(
    List<Message> messages, {
    required int keepTurns,
  }) {
    // Find the index of the Nth-from-last user message
    var userCount = 0;
    var cutoffIndex = 0;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role == Role.user && !messages[i].isCompactSummary) {
        userCount++;
        if (userCount >= keepTurns) {
          cutoffIndex = i;
          break;
        }
      }
    }
    if (userCount < keepTurns) return;

    for (var i = 0; i < cutoffIndex; i++) {
      final msg = messages[i];
      if (msg.images != null && msg.images!.isNotEmpty) {
        messages[i] = Message(
          role: msg.role,
          content:
              '${msg.content}\n[${msg.images!.length} image(s) removed from context — use Read tool on saved path to view]',
          toolUses: msg.toolUses,
          toolResult: msg.toolResult,
          timestamp: msg.timestamp,
          isCompactSummary: msg.isCompactSummary,
        );
      }
      if (msg.toolResult?.images != null &&
          msg.toolResult!.images!.isNotEmpty) {
        final tr = msg.toolResult!;
        messages[i] = Message(
          role: msg.role,
          content: msg.content,
          toolUses: msg.toolUses,
          toolResult: ToolResult(
            toolUseId: tr.toolUseId,
            content:
                '${tr.content}\n[${tr.images!.length} image(s) removed from context — use Read tool on saved path to view]',
            isError: tr.isError,
            imagePaths: tr.imagePaths,
          ),
          timestamp: msg.timestamp,
          isCompactSummary: msg.isCompactSummary,
        );
      }
    }
  }
}
