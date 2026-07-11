import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'agent.dart';
import 'message.dart';

typedef WorkflowUiStateProvider = FutureOr<Map<String, dynamic>?> Function();
typedef WorkflowUiSemanticsProvider =
    FutureOr<Map<String, dynamic>?> Function();
typedef WorkflowUiArtifactsProvider =
    FutureOr<List<Map<String, dynamic>>> Function();
typedef WorkflowUiClearHandler = FutureOr<void> Function();
typedef WorkflowPromptRunHandler =
    Future<List<AgentEvent>> Function(
      String prompt, {
      Set<String> disabledTools,
    });
typedef WorkflowInteractiveStateProvider =
    FutureOr<Map<String, dynamic>?> Function();
typedef WorkflowInteractiveAnswerHandler =
    FutureOr<Object?> Function(List<String> answers);
typedef WorkflowStrategyLibraryActionHandler =
    FutureOr<Map<String, dynamic>> Function({
      required String action,
      String? strategyId,
    });
typedef WorkflowMonitorTriggerHandler =
    FutureOr<Map<String, dynamic>> Function({
      required String monitorId,
      Duration? timeout,
    });

class WorkflowAutomationControl {
  WorkflowAutomationControl({
    required this.agent,
    this.enabled = false,
    this.uiStateProvider,
    this.uiSemanticsProvider,
    this.uiArtifactsProvider,
    this.uiClearHandler,
    this.promptRunHandler,
    this.interactiveStateProvider,
    this.interactiveAnswerHandler,
    this.strategyLibraryActionHandler,
    this.monitorTriggerHandler,
    String? outputDir,
  }) : outputDir =
           outputDir ??
           '${agent.toolContext.basePath}/data/workflow-automation';

  final Agent agent;
  final bool enabled;
  final WorkflowUiStateProvider? uiStateProvider;
  final WorkflowUiSemanticsProvider? uiSemanticsProvider;
  final WorkflowUiArtifactsProvider? uiArtifactsProvider;
  final WorkflowUiClearHandler? uiClearHandler;
  final WorkflowPromptRunHandler? promptRunHandler;
  final WorkflowInteractiveStateProvider? interactiveStateProvider;
  final WorkflowInteractiveAnswerHandler? interactiveAnswerHandler;
  final WorkflowStrategyLibraryActionHandler? strategyLibraryActionHandler;
  final WorkflowMonitorTriggerHandler? monitorTriggerHandler;
  final String outputDir;

  bool get isAvailable => enabled;

  Future<WorkflowAutomationRunResult> sendPrompt(
    String prompt, {
    Set<String> disabledTools = const {},
    int? timeoutMs,
  }) async {
    _ensureEnabled();
    final startedAt = DateTime.now().toUtc();
    final runId = _runId(startedAt);
    final events = <AgentEvent>[];
    final deadline = timeoutMs == null
        ? null
        : startedAt.add(Duration(milliseconds: timeoutMs));

    Object? error;
    String? limitError;
    if (agent.isRunning) {
      error = StateError(
        'workflow automation prompt rejected because agent is already running; '
        'wait for idle or cancel before sending the next prompt',
      );
    } else {
      try {
        if (promptRunHandler != null) {
          final future = promptRunHandler!(
            prompt,
            disabledTools: disabledTools,
          );
          final rawEvents = deadline == null
              ? await future
              : await future.timeout(
                  _remainingUntil(deadline),
                  onTimeout: () => throw TimeoutException(
                    'workflow automation prompt timed out after ${timeoutMs}ms',
                    Duration(milliseconds: timeoutMs ?? 0),
                  ),
                );
          events.addAll(rawEvents);
        } else {
          final stream = agent.run(prompt, disabledTools: disabledTools);
          await for (final event in _withDeadline(
            stream,
            deadline: deadline,
            timeoutMs: timeoutMs,
          )) {
            events.add(event);
          }
        }
        limitError = _workflowLimitError(
          events,
          maxToolCalls: null,
          maxDataToolCalls: null,
          disallowTools: const [],
        );
      } catch (e) {
        error = e;
        if (e is TimeoutException) {
          agent.cancel();
        }
      }
    }

    final finishedAt = DateTime.now().toUtc();
    final report = await _buildReport(
      runId: runId,
      prompt: prompt,
      startedAt: startedAt,
      finishedAt: finishedAt,
      queued: false,
      events: events,
      error: error,
    );
    if (error is TimeoutException) {
      report['workflowTimeout'] = true;
      report['timeoutMs'] = timeoutMs;
      report['agentRunningAfterCancel'] = agent.isRunning;
    }
    final path = await _writeReport(runId, report);
    return WorkflowAutomationRunResult(
      runId: runId,
      ok: report['ok'] == true && limitError == null && error == null,
      queued: false,
      reportPath: path,
      report: report,
      error:
          error?.toString() ??
          limitError ??
          ((report['agentErrors'] as List?)?.isNotEmpty == true
              ? (report['agentErrors'] as List).join('\n')
              : null),
    );
  }

  Future<WorkflowAutomationScenarioResult> runScenario(
    WorkflowAutomationScenario scenario,
  ) async {
    _ensureEnabled();
    if (scenario.id.trim().isEmpty) {
      throw ArgumentError('scenario id is required');
    }
    Map<String, dynamic>? clearSessionResult;
    if (scenario.cleanSession) {
      clearSessionResult = await clearSession(
        reason: 'workflow-scenario:${scenario.id}',
      );
      if (clearSessionResult['ok'] != true) {
        throw StateError(
          'cleanSession failed for ${scenario.id}: '
          '${clearSessionResult['error'] ?? clearSessionResult}',
        );
      }
    }
    final run = await _sendPromptForScenario(scenario);
    final assertions = _evaluateScenario(scenario, run);
    final ok = run.ok && assertions.every((assertion) => assertion.ok);
    final path = await _writeScenarioReport(run.runId, scenario.id, {
      'scenarioId': scenario.id,
      'ok': ok,
      'cleanSession': scenario.cleanSession,
      ...?clearSessionResult == null
          ? null
          : {'clearSession': clearSessionResult},
      'runId': run.runId,
      'runReportPath': run.reportPath,
      'sessionId': run.report['sessionId'],
      'sessionPath': run.report['sessionPath'],
      'rawSessionAvailable': run.report['rawSessionAvailable'],
      'rawLineCount': run.report['rawLineCount'],
      'prompt': run.report['prompt'],
      'assertions': assertions.map((a) => a.toJson()).toList(),
      'eventTypes': run.report['eventTypes'],
      'toolCalls': run.report['toolCalls'],
      'toolResults': run.report['toolResults'],
      'toolErrors': run.report['toolErrors'],
      'minToolCalls': scenario.minToolCalls,
      'maxToolCalls': scenario.maxToolCalls,
      'maxDataToolCalls': scenario.maxDataToolCalls,
      'finalAssistantText': run.report['finalAssistantText'],
      if (run.report.containsKey('pendingUserQuestionObserved'))
        'pendingUserQuestionObserved':
            run.report['pendingUserQuestionObserved'],
      if (run.report.containsKey('pendingUserQuestion'))
        'pendingUserQuestion': run.report['pendingUserQuestion'],
      if (run.report.containsKey('autoAnsweredUserQuestion'))
        'autoAnsweredUserQuestion': run.report['autoAnsweredUserQuestion'],
      if (run.report.containsKey('autoAnswerUserQuestions'))
        'autoAnswerUserQuestions': run.report['autoAnswerUserQuestions'],
      if (run.report.containsKey('interactiveState'))
        'interactiveState': run.report['interactiveState'],
      if (run.report.containsKey('uiState')) 'uiState': run.report['uiState'],
      if (run.report.containsKey('uiEvidence'))
        'uiEvidence': run.report['uiEvidence'],
      if (run.report.containsKey('uiArtifacts'))
        'uiArtifacts': run.report['uiArtifacts'],
    });
    return WorkflowAutomationScenarioResult(
      ok: ok,
      scenarioId: scenario.id,
      run: run,
      assertions: assertions,
      scenarioReportPath: path,
    );
  }

  Future<Map<String, dynamic>> runScenarioSequence({
    required String id,
    required List<Map<String, dynamic>> turns,
    List<String> expectSessionContains = const [],
    List<String> expectUiStateKeys = const [],
    List<String> expectUiEvidencePaths = const [],
    List<String> expectUiArtifactKinds = const [],
  }) async {
    _ensureEnabled();
    final scenarioId = id.trim();
    if (scenarioId.isEmpty) {
      throw ArgumentError('scenario id is required');
    }
    if (turns.isEmpty) {
      throw ArgumentError('scenario turns are required');
    }
    final results = <Map<String, dynamic>>[];
    for (var i = 0; i < turns.length; i++) {
      final turn = turns[i];
      final turnId = '${turn['id'] ?? turn['turnId'] ?? 'turn-${i + 1}'}'
          .trim();
      final prompt = '${turn['prompt'] ?? ''}'.trim();
      if (prompt.isEmpty) {
        throw ArgumentError('scenario turn ${i + 1} prompt is required');
      }
      final result = await runScenario(
        WorkflowAutomationScenario(
          id: '$scenarioId:$turnId',
          prompt: prompt,
          workflowState: turn['workflowState'],
          minToolCalls: _optionalPositiveInt(turn['minToolCalls']),
          maxToolCalls: _optionalPositiveInt(turn['maxToolCalls']),
          maxDataToolCalls: _optionalPositiveInt(turn['maxDataToolCalls']),
          allowedTools: _stringList(turn['allowedTools']),
          expectTools: _stringList(turn['expectTools']),
          expectToolActions: _stringList(turn['expectToolActions']),
          maxToolActionCounts: _stringIntMap(turn['maxToolActionCounts']),
          expectNoToolErrors: turn['expectNoToolErrors'] == true,
          expectToolErrors: _stringList(turn['expectToolErrors']),
          expectToolResultContains: _stringList(
            turn['expectToolResultContains'],
          ),
          expectFinalContains: _stringList(turn['expectFinalContains']),
          expectSessionContains: _stringList(turn['expectSessionContains']),
          expectUiStateKeys: _stringList(turn['expectUiStateKeys']),
          expectUiEvidencePaths: _stringList(turn['expectUiEvidencePaths']),
          expectUiArtifactKinds: _stringList(turn['expectUiArtifactKinds']),
          disallowTools: _stringList(turn['disallowTools']),
          allowPendingUserQuestion: turn['allowPendingUserQuestion'] == true,
          autoAnswerUserQuestions:
              _stringList(turn['autoAnswerUserQuestions']).isNotEmpty
              ? _stringList(turn['autoAnswerUserQuestions'])
              : turn['autoAnswerUserQuestion'] is String
              ? [turn['autoAnswerUserQuestion'] as String]
              : const [],
          timeoutMs: _optionalPositiveInt(turn['timeoutMs']),
        ),
      );
      results.add({
        'ok': result.ok,
        'scenarioId': result.scenarioId,
        'turnId': turnId,
        'turnIndex': i,
        'run': result.run.toJson(),
        'assertions': result.assertions.map((a) => a.toJson()).toList(),
        'scenarioReportPath': result.scenarioReportPath,
      });
    }
    final finalRunMap = results.last['run'] as Map<String, dynamic>;
    final finalRun = WorkflowAutomationRunResult(
      runId: '${finalRunMap['runId'] ?? ''}',
      ok: finalRunMap['ok'] == true,
      queued: finalRunMap['queued'] == true,
      reportPath: '${finalRunMap['reportPath'] ?? ''}',
      report: finalRunMap['report'] is Map
          ? Map<String, dynamic>.from(finalRunMap['report'] as Map)
          : const {},
      error: finalRunMap['error']?.toString(),
    );
    final aggregateAssertions = <WorkflowAutomationScenarioAssertion>[
      WorkflowAutomationScenarioAssertion(
        name: 'turns.ok',
        ok: results.every((turn) => turn['ok'] == true),
        expected: 'all turns ok',
        actual: results
            .map((turn) => {'turnId': turn['turnId'], 'ok': turn['ok']})
            .toList(),
      ),
      ..._evaluateScenario(
        WorkflowAutomationScenario(
          id: scenarioId,
          prompt: turns.map((turn) => '${turn['prompt'] ?? ''}').join('\n'),
          expectSessionContains: expectSessionContains,
          expectUiStateKeys: expectUiStateKeys,
          expectUiEvidencePaths: expectUiEvidencePaths,
          expectUiArtifactKinds: expectUiArtifactKinds,
        ),
        finalRun,
      ),
    ];
    final ok =
        results.every((turn) => turn['ok'] == true) &&
        aggregateAssertions.every((assertion) => assertion.ok);
    final report = {
      'scenarioId': scenarioId,
      'ok': ok,
      'turns': results,
      'assertions': aggregateAssertions.map((a) => a.toJson()).toList(),
    };
    final path = await _writeScenarioReport(
      finalRun.runId,
      '$scenarioId-multiturn',
      report,
    );
    return {...report, 'scenarioReportPath': path};
  }

  Future<WorkflowAutomationRunResult> _sendPromptForScenario(
    WorkflowAutomationScenario scenario,
  ) async {
    if (scenario.allowPendingUserQuestion) {
      return _sendPromptWithPendingQuestionSupport(scenario);
    }
    final disabledTools = _disabledToolsForScenario(scenario);
    final run = await sendPrompt(
      _promptWithScenarioConstraints(scenario),
      disabledTools: disabledTools,
      timeoutMs: scenario.timeoutMs,
    );
    return _applyScenarioLimit(scenario, run);
  }

  Future<WorkflowAutomationRunResult> _sendPromptWithPendingQuestionSupport(
    WorkflowAutomationScenario scenario,
  ) async {
    var completed = false;
    final disabledTools = _disabledToolsForScenario(scenario);
    final future = sendPrompt(
      _promptWithScenarioConstraints(scenario),
      disabledTools: disabledTools,
      timeoutMs: scenario.timeoutMs,
    ).whenComplete(() => completed = true);
    final pendingSnapshots = <Map<String, dynamic>>[];
    final answeredPendingKeys = <String>{};
    final deadline = DateTime.now().toUtc().add(
      Duration(milliseconds: scenario.timeoutMs ?? 180000),
    );
    while (!completed && DateTime.now().toUtc().isBefore(deadline)) {
      final state = await interactiveStateProvider?.call();
      if (state != null && state['hasPendingUserQuestion'] == true) {
        final pendingSnapshot = Map<String, dynamic>.from(state);
        final pendingKey = _pendingQuestionKey(pendingSnapshot);
        if (answeredPendingKeys.add(pendingKey)) {
          pendingSnapshots.add(pendingSnapshot);
          final answers = scenario.autoAnswerUserQuestions
              .map((answer) => answer.trim())
              .where((answer) => answer.isNotEmpty)
              .toList(growable: false);
          if (answers.isNotEmpty) {
            await interactiveAnswerHandler?.call(answers);
          }
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }

    final run = await future;
    final report = Map<String, dynamic>.from(run.report);
    if (pendingSnapshots.isNotEmpty) {
      report['pendingUserQuestionObserved'] = true;
      report['pendingUserQuestion'] = pendingSnapshots.last;
      report['pendingUserQuestions'] = pendingSnapshots;
      report['autoAnsweredUserQuestion'] =
          scenario.autoAnswerUserQuestions.isNotEmpty;
      if (scenario.autoAnswerUserQuestions.isNotEmpty) {
        report['autoAnswerUserQuestions'] = scenario.autoAnswerUserQuestions;
      }
      final path = await _writeReport(run.runId, report);
      return WorkflowAutomationRunResult(
        runId: run.runId,
        ok: run.ok,
        queued: run.queued,
        reportPath: path,
        report: report,
        error: run.error,
      );
    }
    return _applyScenarioLimit(scenario, run);
  }

  String _promptWithScenarioConstraints(WorkflowAutomationScenario scenario) {
    final constraints = <String>[];
    if (scenario.allowedTools.isNotEmpty) {
      constraints.add(
        'Use only these tools in this scenario: '
        '${scenario.allowedTools.join(', ')}.',
      );
    }
    if (scenario.disallowTools.isNotEmpty) {
      constraints.add(
        'Do not use these tools in this scenario: '
        '${scenario.disallowTools.join(', ')}.',
      );
    }
    if (scenario.maxToolCalls != null) {
      constraints.add(
        'Keep the workflow within ${scenario.maxToolCalls} total tool calls.',
      );
    }
    if (scenario.minToolCalls != null) {
      constraints.add(
        'This workflow requires at least ${scenario.minToolCalls} observable tool calls before the final answer.',
      );
    }
    if (scenario.maxDataToolCalls != null) {
      constraints.add(
        'Keep the workflow within ${scenario.maxDataToolCalls} finance/data workflow tool calls.',
      );
    }
    if (scenario.maxToolActionCounts.isNotEmpty) {
      constraints.add(
        'Respect these per-action call limits: '
        '${scenario.maxToolActionCounts.entries.map((entry) => '${entry.key} <= ${entry.value}').join(', ')}.',
      );
    }
    if (scenario.expectTools.isNotEmpty) {
      constraints.add(
        'This workflow requires these observable tools before the final answer: '
        '${scenario.expectTools.join(', ')}.',
      );
    }
    if (scenario.expectToolActions.isNotEmpty) {
      constraints.add(
        'This workflow requires these observable tool actions before the final answer: '
        '${scenario.expectToolActions.join(', ')}.',
      );
    }
    final parts = <String>[];
    if (constraints.isNotEmpty) {
      parts.addAll([
        '<workflow-test-constraints>',
        ...constraints,
        '</workflow-test-constraints>',
        '',
      ]);
    }
    parts.add(scenario.prompt);
    if (scenario.workflowState case final Map workflowState) {
      parts.add('');
      parts.add(
        'data: ${jsonEncode({'workflowState': Map<String, dynamic>.from(workflowState)})}',
      );
    }
    return parts.join('\n');
  }

  Set<String> _disabledToolsForScenario(WorkflowAutomationScenario scenario) {
    final disabled = scenario.disallowTools.toSet();
    if (scenario.allowedTools.isEmpty) return disabled;
    final allowed = scenario.allowedTools.toSet();
    for (final toolName in agent.toolNames) {
      if (!allowed.contains(toolName)) disabled.add(toolName);
    }
    return disabled;
  }

  String _pendingQuestionKey(Map<String, dynamic> state) {
    final current = state['currentQuestionIndex']?.toString() ?? '';
    final questions = (state['questions'] as List? ?? const [])
        .map((question) {
          if (question is! Map) return question.toString();
          return '${question['header'] ?? ''}:${question['question'] ?? ''}';
        })
        .join('|');
    final answers = state['collectedAnswers']?.toString() ?? '';
    return '$current::$questions::$answers';
  }

  Future<WorkflowAutomationRunResult> _applyScenarioLimit(
    WorkflowAutomationScenario scenario,
    WorkflowAutomationRunResult run,
  ) async {
    final limitError = _workflowLimitError(
      _eventsFromReport(run.report),
      maxToolCalls: scenario.maxToolCalls,
      maxDataToolCalls: scenario.maxDataToolCalls,
      disallowTools: scenario.disallowTools,
    );
    if (limitError == null) return run;
    final report = Map<String, dynamic>.from(run.report);
    report['ok'] = false;
    report['workflowLimitError'] = limitError;
    report['agentErrors'] = [
      ...((report['agentErrors'] as List?) ?? const []),
      limitError,
    ];
    return WorkflowAutomationRunResult(
      runId: run.runId,
      ok: false,
      queued: run.queued,
      reportPath: run.reportPath,
      report: report,
      error: limitError,
    );
  }

  Future<Map<String, dynamic>> sessionEvidence() async {
    _ensureEnabled();
    final sessionPath = agent.sessionManager.currentSession?.filePath;
    return {
      'sessionId': agent.sessionManager.currentSession?.id,
      'sessionPath': sessionPath,
      'rawSessionAvailable': _sessionFileExists(sessionPath),
      'rawLineCount': _countNonEmptyLines(sessionPath),
      'messageCount': agent.messages.length,
      'messages': agent.messages.map(_messageToEvidence).toList(),
    };
  }

  Future<Map<String, dynamic>> clearSession({
    String reason = 'workflow-automation',
  }) async {
    _ensureEnabled();
    if (agent.isRunning) {
      return {
        'ok': false,
        'agentReady': true,
        'agentRunning': true,
        'error': 'agent is running; cancel or wait for idle before clearing',
      };
    }
    final previousSessionId = agent.sessionManager.currentSession?.id;
    final previousSessionPath = agent.sessionManager.currentSession?.filePath;
    final previousMessageCount = agent.messages.length;
    agent.clearHistory();
    await uiClearHandler?.call();
    return {
      'ok': true,
      'agentReady': true,
      'agentRunning': false,
      'reason': reason.trim().isEmpty ? 'workflow-automation' : reason.trim(),
      'previousSessionId': previousSessionId,
      'previousSessionPath': previousSessionPath,
      'previousMessageCount': previousMessageCount,
      'sessionId': agent.sessionManager.currentSession?.id,
      'sessionPath': agent.sessionManager.currentSession?.filePath,
      'messageCount': agent.messages.length,
    };
  }

  Future<Map<String, dynamic>?> uiState() async {
    _ensureEnabled();
    return await uiStateProvider?.call();
  }

  Future<Map<String, dynamic>> interactiveState() async {
    _ensureEnabled();
    return await interactiveStateProvider?.call() ??
        {'hasPendingUserQuestion': false};
  }

  Future<Map<String, dynamic>> answerInteractiveQuestion(
    List<String> answers,
  ) async {
    _ensureEnabled();
    final trimmedAnswers = answers
        .map((answer) => answer.trim())
        .where((answer) => answer.isNotEmpty)
        .toList(growable: false);
    if (trimmedAnswers.isEmpty) {
      throw ArgumentError('answer is required');
    }
    final rawResult = await interactiveAnswerHandler?.call(trimmedAnswers);
    final handled = rawResult is Map
        ? rawResult['ok'] == true || rawResult['answered'] == true
        : rawResult == true;
    return {
      'ok': handled,
      'answered': handled,
      'answers': trimmedAnswers,
      if (rawResult is Map)
        ...rawResult.map((key, value) => MapEntry('$key', value)),
      if (!handled) 'error': 'no pending interactive question',
    };
  }

  Future<Map<String, dynamic>> uiEvidence() async {
    _ensureEnabled();
    return _buildUiEvidence(
      await uiStateProvider?.call(),
      semantics: await uiSemanticsProvider?.call(),
    );
  }

  Future<List<Map<String, dynamic>>> uiArtifacts() async {
    _ensureEnabled();
    final artifacts = await uiArtifactsProvider?.call();
    return artifacts?.take(20).toList(growable: false) ?? [];
  }

  Future<Map<String, dynamic>> strategyLibraryAction({
    required String action,
    String? strategyId,
  }) async {
    _ensureEnabled();
    final handler = strategyLibraryActionHandler;
    if (handler == null) {
      throw StateError('strategy library action handler is not configured');
    }
    final normalizedAction = action.trim();
    if (normalizedAction.isEmpty) {
      throw ArgumentError('action is required');
    }
    return await handler(action: normalizedAction, strategyId: strategyId);
  }

  Future<Map<String, dynamic>> triggerMonitor({
    required String monitorId,
    Duration? timeout,
  }) async {
    _ensureEnabled();
    final handler = monitorTriggerHandler;
    if (handler == null) {
      throw StateError('monitor trigger action handler is not configured');
    }
    final normalizedMonitorId = monitorId.trim();
    if (normalizedMonitorId.isEmpty) {
      throw ArgumentError('monitorId is required');
    }
    return await handler(monitorId: normalizedMonitorId, timeout: timeout);
  }

  Future<Map<String, dynamic>> waitForIdle({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _ensureEnabled();
    final startedAt = DateTime.now().toUtc();
    final boundedTimeout = timeout < Duration.zero
        ? Duration.zero
        : timeout > const Duration(seconds: 60)
        ? const Duration(seconds: 60)
        : timeout;
    while (agent.isRunning &&
        DateTime.now().toUtc().difference(startedAt) < boundedTimeout) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final waitedMs = DateTime.now()
        .toUtc()
        .difference(startedAt)
        .inMilliseconds;
    final idle = !agent.isRunning;
    return {
      'ok': idle,
      'idle': idle,
      'agentReady': true,
      'agentRunning': agent.isRunning,
      'waitedMs': waitedMs,
      'timedOut': !idle && waitedMs >= boundedTimeout.inMilliseconds,
    };
  }

  Future<Map<String, dynamic>> cancel({
    String reason = 'workflow-automation',
  }) async {
    _ensureEnabled();
    final runningBeforeCancel = agent.isRunning;
    if (runningBeforeCancel) {
      agent.cancel();
    }
    return {
      'ok': true,
      'agentReady': true,
      'runningBeforeCancel': runningBeforeCancel,
      'cancelRequested': runningBeforeCancel,
      'agentRunning': agent.isRunning,
      'reason': reason.trim().isEmpty ? 'workflow-automation' : reason.trim(),
    };
  }

  Future<Map<String, dynamic>> reports({int limit = 20}) async {
    _ensureEnabled();
    final dir = Directory(outputDir);
    if (!dir.existsSync()) {
      return {'ok': true, 'reportDir': outputDir, 'count': 0, 'reports': []};
    }
    final boundedLimit = limit.clamp(1, 100);
    final files =
        dir
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.json'))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    final entries = files
        .take(boundedLimit)
        .map(_summarizeReportFile)
        .toList(growable: false);
    return {
      'ok': true,
      'reportDir': outputDir,
      'count': entries.length,
      'reports': entries,
    };
  }

  Future<Map<String, dynamic>> _buildReport({
    required String runId,
    required String prompt,
    required DateTime startedAt,
    required DateTime finishedAt,
    required bool queued,
    required List<AgentEvent> events,
    Object? error,
  }) async {
    final toolResults = events.whereType<AgentToolResult>().toList();
    final agentErrors = events.whereType<AgentError>().toList();
    final ok = error == null && agentErrors.isEmpty;
    final uiState = await uiStateProvider?.call();
    final uiSemantics = await uiSemanticsProvider?.call();
    final uiArtifacts = await uiArtifactsProvider?.call();
    final messageEvidence = agent.messages.map(_messageToEvidence).toList();
    final eventToolCalls = events
        .whereType<AgentToolUseStart>()
        .map((e) => {'toolName': e.toolName, 'input': e.input})
        .toList();
    final reportToolCalls = eventToolCalls.isNotEmpty
        ? eventToolCalls
        : _toolCallsFromMessages(messageEvidence);
    final eventToolResults = toolResults
        .map(
          (e) => {
            'toolName': e.toolName,
            'isError': e.isError,
            'durationMs': e.durationMs,
            'result': _truncate(e.result),
          },
        )
        .toList();
    final reportToolResults = eventToolResults.isNotEmpty
        ? eventToolResults
        : _toolResultsFromMessages(messageEvidence);
    final reportToolErrors = reportToolResults
        .where((e) => e['isError'] == true)
        .toList(growable: false);
    return {
      'runId': runId,
      'runtime': 'shared-mobile',
      'startedAt': startedAt.toIso8601String(),
      'finishedAt': finishedAt.toIso8601String(),
      'prompt': prompt,
      'ok': ok,
      'queued': queued,
      if (error != null) 'error': error.toString(),
      if (agentErrors.isNotEmpty)
        'agentErrors': agentErrors.map((e) => e.message).toList(),
      'sessionId': agent.sessionManager.currentSession?.id,
      'sessionPath': agent.sessionManager.currentSession?.filePath,
      'rawSessionAvailable': _sessionFileExists(
        agent.sessionManager.currentSession?.filePath,
      ),
      'rawLineCount': _countNonEmptyLines(
        agent.sessionManager.currentSession?.filePath,
      ),
      'eventTypes': events.map((e) => e.runtimeType.toString()).toList(),
      'toolCalls': reportToolCalls,
      'toolResults': reportToolResults,
      'toolErrors': reportToolErrors,
      'finalAssistantText': _finalAssistantText(agent.messages),
      'messageCount': agent.messages.length,
      'messages': messageEvidence,
      if (uiStateProvider != null) 'uiState': uiState,
      if (uiSemanticsProvider != null) 'uiSemantics': uiSemantics,
      'uiEvidence': _buildUiEvidence(uiState, semantics: uiSemantics),
      if (uiArtifactsProvider != null)
        'uiArtifacts': uiArtifacts?.take(20).toList(growable: false) ?? [],
      if (interactiveStateProvider != null)
        'interactiveState': await interactiveStateProvider?.call(),
    };
  }

  Future<String> _writeReport(String runId, Map<String, dynamic> report) async {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File('${dir.path}/$runId.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    return file.path;
  }

  Future<String> _writeScenarioReport(
    String runId,
    String scenarioId,
    Map<String, dynamic> report,
  ) async {
    final dir = Directory(outputDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);
    final file = File(
      '${dir.path}/$runId-${_safeFilePart(scenarioId)}-scenario.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(report),
    );
    return file.path;
  }

  void _ensureEnabled() {
    if (!enabled) {
      throw StateError(
        'Workflow automation is disabled. Enable it explicitly for local test control.',
      );
    }
  }
}

Stream<AgentEvent> _withDeadline(
  Stream<AgentEvent> stream, {
  required DateTime? deadline,
  required int? timeoutMs,
}) async* {
  if (deadline == null) {
    yield* stream;
    return;
  }
  await for (final event in stream.timeout(
    _remainingUntil(deadline),
    onTimeout: (sink) {
      sink.addError(
        TimeoutException(
          'workflow automation prompt timed out after ${timeoutMs}ms',
          Duration(milliseconds: timeoutMs ?? 0),
        ),
      );
    },
  )) {
    if (!DateTime.now().toUtc().isBefore(deadline)) {
      throw TimeoutException(
        'workflow automation prompt timed out after ${timeoutMs}ms',
        Duration(milliseconds: timeoutMs ?? 0),
      );
    }
    yield event;
  }
}

Duration _remainingUntil(DateTime deadline) {
  final remaining = deadline.difference(DateTime.now().toUtc());
  return remaining.isNegative || remaining == Duration.zero
      ? const Duration(milliseconds: 1)
      : remaining;
}

class WorkflowAutomationScenario {
  const WorkflowAutomationScenario({
    required this.id,
    required this.prompt,
    this.workflowState,
    this.cleanSession = false,
    this.minToolCalls,
    this.maxToolCalls,
    this.maxDataToolCalls,
    this.allowedTools = const [],
    this.expectTools = const [],
    this.expectToolActions = const [],
    this.maxToolActionCounts = const {},
    this.expectNoToolErrors = false,
    this.expectToolErrors = const [],
    this.expectToolResultContains = const [],
    this.expectFinalContains = const [],
    this.expectSessionContains = const [],
    this.expectUiStateKeys = const [],
    this.expectUiEvidencePaths = const [],
    this.expectUiArtifactKinds = const [],
    this.disallowTools = const [],
    this.allowPendingUserQuestion = false,
    this.autoAnswerUserQuestions = const [],
    this.timeoutMs,
  });

  final String id;
  final String prompt;
  final Object? workflowState;
  final bool cleanSession;
  final int? minToolCalls;
  final int? maxToolCalls;
  final int? maxDataToolCalls;
  final List<String> allowedTools;
  final List<String> expectTools;
  final List<String> expectToolActions;
  final Map<String, int> maxToolActionCounts;
  final bool expectNoToolErrors;
  final List<String> expectToolErrors;
  final List<String> expectToolResultContains;
  final List<String> expectFinalContains;
  final List<String> expectSessionContains;
  final List<String> expectUiStateKeys;
  final List<String> expectUiEvidencePaths;
  final List<String> expectUiArtifactKinds;
  final List<String> disallowTools;
  final bool allowPendingUserQuestion;
  final List<String> autoAnswerUserQuestions;
  final int? timeoutMs;
}

class WorkflowAutomationScenarioAssertion {
  const WorkflowAutomationScenarioAssertion({
    required this.name,
    required this.ok,
    this.expected,
    this.actual,
  });

  final String name;
  final bool ok;
  final Object? expected;
  final Object? actual;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ok': ok,
    if (expected != null) 'expected': expected,
    if (actual != null) 'actual': actual,
  };
}

class WorkflowAutomationScenarioResult {
  const WorkflowAutomationScenarioResult({
    required this.ok,
    required this.scenarioId,
    required this.run,
    required this.assertions,
    required this.scenarioReportPath,
  });

  final bool ok;
  final String scenarioId;
  final WorkflowAutomationRunResult run;
  final List<WorkflowAutomationScenarioAssertion> assertions;
  final String scenarioReportPath;

  Map<String, dynamic> toJson() => {
    'ok': ok,
    'scenarioId': scenarioId,
    'scenarioReportPath': scenarioReportPath,
    'assertions': assertions.map((a) => a.toJson()).toList(),
    'run': run.toJson(),
  };
}

class WorkflowAutomationRunResult {
  const WorkflowAutomationRunResult({
    required this.runId,
    required this.ok,
    required this.queued,
    required this.reportPath,
    required this.report,
    this.error,
  });

  final String runId;
  final bool ok;
  final bool queued;
  final String reportPath;
  final Map<String, dynamic> report;
  final String? error;

  Map<String, dynamic> toJson() => {
    'runId': runId,
    'ok': ok,
    'queued': queued,
    'reportPath': reportPath,
    if (error != null) 'error': error,
    'report': report,
  };
}

class WorkflowAutomationInProcessBridge {
  WorkflowAutomationInProcessBridge({required this.control});

  static const transport = 'in-process-bridge';

  final WorkflowAutomationControl control;

  Future<Map<String, dynamic>> health() async => {
    'ok': true,
    'enabled': control.enabled,
    'agentReady': true,
    'agentRunning': control.agent.isRunning,
    'transport': transport,
    'localOnly': true,
    'rawSocketProtocol': false,
    'webSocketCommandProtocol': false,
    'providerEndpointBypass': false,
    'recommendedExternalTransport': 'platform-device-bridge',
  };

  Future<Map<String, dynamic>> session() => control.sessionEvidence();

  Future<Map<String, dynamic>> panels() async => {
    'uiState': await control.uiState(),
    'uiEvidence': await control.uiEvidence(),
    'uiArtifacts': await control.uiArtifacts(),
  };

  Future<Map<String, dynamic>> idle({int timeoutMs = 5000}) =>
      control.waitForIdle(timeout: Duration(milliseconds: timeoutMs));

  Future<Map<String, dynamic>> reports({int limit = 20}) =>
      control.reports(limit: limit);

  Future<Map<String, dynamic>> send({required String prompt}) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('prompt is required');
    }
    return (await control.sendPrompt(trimmed)).toJson();
  }

  Future<Map<String, dynamic>> cancel({String reason = ''}) =>
      control.cancel(reason: reason);

  Future<Map<String, dynamic>> strategyLibraryAction({
    required String action,
    String? strategyId,
  }) => control.strategyLibraryAction(action: action, strategyId: strategyId);

  Future<Map<String, dynamic>> triggerMonitor({
    required String monitorId,
    int? timeoutMs,
  }) => control.triggerMonitor(
    monitorId: monitorId,
    timeout: timeoutMs == null ? null : Duration(milliseconds: timeoutMs),
  );

  Future<Map<String, dynamic>> scenario({
    required String id,
    required String prompt,
    bool cleanSession = false,
    int? minToolCalls,
    int? maxToolCalls,
    int? maxDataToolCalls,
    List<String> allowedTools = const [],
    List<String> expectTools = const [],
    bool expectNoToolErrors = false,
    List<String> expectToolErrors = const [],
    List<String> expectToolResultContains = const [],
    List<String> expectFinalContains = const [],
    List<String> expectSessionContains = const [],
    List<String> expectUiStateKeys = const [],
    List<String> expectUiEvidencePaths = const [],
    List<String> expectUiArtifactKinds = const [],
    List<String> disallowTools = const [],
    bool allowPendingUserQuestion = false,
    List<String> autoAnswerUserQuestions = const [],
    int? timeoutMs,
  }) async {
    final trimmedId = id.trim();
    final trimmedPrompt = prompt.trim();
    if (trimmedId.isEmpty || trimmedPrompt.isEmpty) {
      throw ArgumentError('id and prompt are required');
    }
    return (await control.runScenario(
      WorkflowAutomationScenario(
        id: trimmedId,
        prompt: trimmedPrompt,
        cleanSession: cleanSession,
        minToolCalls: minToolCalls,
        maxToolCalls: maxToolCalls,
        maxDataToolCalls: maxDataToolCalls,
        allowedTools: allowedTools,
        expectTools: expectTools,
        expectNoToolErrors: expectNoToolErrors,
        expectToolErrors: expectToolErrors,
        expectToolResultContains: expectToolResultContains,
        expectFinalContains: expectFinalContains,
        expectSessionContains: expectSessionContains,
        expectUiStateKeys: expectUiStateKeys,
        expectUiEvidencePaths: expectUiEvidencePaths,
        expectUiArtifactKinds: expectUiArtifactKinds,
        disallowTools: disallowTools,
        allowPendingUserQuestion: allowPendingUserQuestion,
        autoAnswerUserQuestions: autoAnswerUserQuestions,
        timeoutMs: timeoutMs,
      ),
    )).toJson();
  }
}

class WorkflowAutomationHttpHost {
  WorkflowAutomationHttpHost({required this.control, this.port = 0});

  static const transport = 'loopback-http';

  final WorkflowAutomationControl control;
  final int port;
  HttpServer? _server;

  int? get boundPort => _server?.port;
  bool get isRunning => _server != null;

  Future<int?> start() async {
    if (!control.enabled) return null;
    // Workflow automation is intentionally an app-owned loopback HTTP surface.
    // Do not replace this with a raw Socket/WebSocket command protocol.
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    unawaited(_serve(_server!));
    return _server!.port;
  }

  Future<void> close() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  Future<void> _serve(HttpServer server) async {
    await for (final request in server) {
      unawaited(_handleSafely(request));
    }
  }

  Future<void> _handleSafely(HttpRequest request) async {
    try {
      await _handle(request);
    } catch (e) {
      await _json(request, 500, {'error': e.toString()});
    }
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/health') {
      await _json(request, 200, {
        'ok': true,
        'enabled': control.enabled,
        'agentReady': true,
        'agentRunning': control.agent.isRunning,
        'transport': transport,
        'localOnly': true,
        'rawSocketProtocol': false,
        'webSocketCommandProtocol': false,
        'providerEndpointBypass': false,
      });
      return;
    }
    if (request.method == 'GET' && path == '/workflow/session') {
      await _json(request, 200, await control.sessionEvidence());
      return;
    }
    if (request.method == 'GET' && path == '/workflow/panels') {
      await _json(request, 200, {
        'uiState': await control.uiState(),
        'uiEvidence': await control.uiEvidence(),
        'uiArtifacts': await control.uiArtifacts(),
      });
      return;
    }
    if (request.method == 'GET' && path == '/workflow/interactive') {
      await _json(request, 200, await control.interactiveState());
      return;
    }
    if (request.method == 'GET' && path == '/workflow/idle') {
      final timeoutMs =
          int.tryParse(request.uri.queryParameters['timeoutMs'] ?? '') ?? 5000;
      await _json(
        request,
        200,
        await control.waitForIdle(timeout: Duration(milliseconds: timeoutMs)),
      );
      return;
    }
    if (request.method == 'GET' && path == '/workflow/reports') {
      final limit =
          int.tryParse(request.uri.queryParameters['limit'] ?? '') ?? 20;
      await _json(request, 200, await control.reports(limit: limit));
      return;
    }
    if (request.method == 'POST' && path == '/workflow/send') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = jsonDecode(body);
      final prompt = parsed is Map ? '${parsed['prompt'] ?? ''}'.trim() : '';
      if (prompt.isEmpty) {
        await _json(request, 400, {'error': 'prompt is required'});
        return;
      }
      final result = await control.sendPrompt(prompt);
      await _json(request, 200, result.toJson());
      return;
    }
    if (request.method == 'POST' && path == '/workflow/cancel') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = body.trim().isEmpty ? const {} : jsonDecode(body);
      final reason = parsed is Map ? '${parsed['reason'] ?? ''}' : '';
      await _json(request, 200, await control.cancel(reason: reason));
      return;
    }
    if (request.method == 'POST' && path == '/workflow/answer_question') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = body.trim().isEmpty ? const {} : jsonDecode(body);
      final answers = parsed is Map
          ? (_stringList(parsed['answers']).isNotEmpty
                ? _stringList(parsed['answers'])
                : ['${parsed['answer'] ?? ''}'])
          : const <String>[];
      if (answers.every((answer) => answer.trim().isEmpty)) {
        await _json(request, 400, {'error': 'answer is required'});
        return;
      }
      await _json(
        request,
        200,
        await control.answerInteractiveQuestion(answers),
      );
      return;
    }
    if (request.method == 'POST' &&
        path == '/workflow/strategy_library_action') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = body.trim().isEmpty ? const {} : jsonDecode(body);
      if (parsed is! Map) {
        await _json(request, 400, {'error': 'body must be an object'});
        return;
      }
      final action = '${parsed['action'] ?? ''}'.trim();
      if (action.isEmpty) {
        await _json(request, 400, {'error': 'action is required'});
        return;
      }
      await _json(
        request,
        200,
        await control.strategyLibraryAction(
          action: action,
          strategyId: '${parsed['strategyId'] ?? ''}'.trim().isEmpty
              ? null
              : '${parsed['strategyId'] ?? ''}'.trim(),
        ),
      );
      return;
    }
    if (request.method == 'POST' && path == '/workflow/trigger_monitor') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = body.trim().isEmpty ? const {} : jsonDecode(body);
      if (parsed is! Map) {
        await _json(request, 400, {'error': 'body must be an object'});
        return;
      }
      final monitorId = '${parsed['monitorId'] ?? parsed['id'] ?? ''}'.trim();
      if (monitorId.isEmpty) {
        await _json(request, 400, {'error': 'monitorId is required'});
        return;
      }
      await _json(
        request,
        200,
        await control.triggerMonitor(
          monitorId: monitorId,
          timeout: _optionalDurationMs(parsed['timeoutMs']),
        ),
      );
      return;
    }
    if (request.method == 'POST' && path == '/workflow/clear_session') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = body.trim().isEmpty ? const {} : jsonDecode(body);
      final reason = parsed is Map ? '${parsed['reason'] ?? ''}' : '';
      await _json(request, 200, await control.clearSession(reason: reason));
      return;
    }
    if (request.method == 'POST' && path == '/workflow/scenario') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = jsonDecode(body);
      if (parsed is! Map) {
        await _json(request, 400, {'error': 'scenario body must be an object'});
        return;
      }
      final prompt = '${parsed['prompt'] ?? ''}'.trim();
      final id = '${parsed['id'] ?? ''}'.trim();
      if (id.isEmpty || prompt.isEmpty) {
        await _json(request, 400, {'error': 'id and prompt are required'});
        return;
      }
      final result = await control.runScenario(
        WorkflowAutomationScenario(
          id: id,
          prompt: prompt,
          workflowState: parsed['workflowState'],
          cleanSession: parsed['cleanSession'] == true,
          minToolCalls: _optionalPositiveInt(parsed['minToolCalls']),
          maxToolCalls: _optionalPositiveInt(parsed['maxToolCalls']),
          maxDataToolCalls: _optionalPositiveInt(parsed['maxDataToolCalls']),
          allowedTools: _stringList(parsed['allowedTools']),
          expectTools: _stringList(parsed['expectTools']),
          expectToolActions: _stringList(parsed['expectToolActions']),
          maxToolActionCounts: _stringIntMap(parsed['maxToolActionCounts']),
          expectNoToolErrors: parsed['expectNoToolErrors'] == true,
          expectToolErrors: _stringList(parsed['expectToolErrors']),
          expectToolResultContains: _stringList(
            parsed['expectToolResultContains'],
          ),
          expectFinalContains: _stringList(parsed['expectFinalContains']),
          expectSessionContains: _stringList(parsed['expectSessionContains']),
          expectUiStateKeys: _stringList(parsed['expectUiStateKeys']),
          expectUiEvidencePaths: _stringList(parsed['expectUiEvidencePaths']),
          expectUiArtifactKinds: _stringList(parsed['expectUiArtifactKinds']),
          disallowTools: _stringList(parsed['disallowTools']),
          allowPendingUserQuestion: parsed['allowPendingUserQuestion'] == true,
          autoAnswerUserQuestions:
              _stringList(parsed['autoAnswerUserQuestions']).isNotEmpty
              ? _stringList(parsed['autoAnswerUserQuestions'])
              : parsed['autoAnswerUserQuestion'] is String
              ? [parsed['autoAnswerUserQuestion'] as String]
              : const [],
          timeoutMs: _optionalPositiveInt(parsed['timeoutMs']),
        ),
      );
      await _json(request, 200, result.toJson());
      return;
    }
    if (request.method == 'POST' && path == '/workflow/scenario_sequence') {
      final body = await utf8.decoder.bind(request).join();
      final parsed = jsonDecode(body);
      if (parsed is! Map) {
        await _json(request, 400, {
          'error': 'scenario sequence body must be an object',
        });
        return;
      }
      final id = '${parsed['id'] ?? ''}'.trim();
      final rawTurns = parsed['turns'];
      if (id.isEmpty || rawTurns is! List || rawTurns.isEmpty) {
        await _json(request, 400, {
          'error': 'id and non-empty turns are required',
        });
        return;
      }
      final turns = rawTurns
          .whereType<Map>()
          .map((turn) => Map<String, dynamic>.from(turn))
          .toList(growable: false);
      if (turns.length != rawTurns.length) {
        await _json(request, 400, {'error': 'each turn must be an object'});
        return;
      }
      final result = await control.runScenarioSequence(
        id: id,
        turns: turns,
        expectSessionContains: _stringList(parsed['expectSessionContains']),
        expectUiStateKeys: _stringList(parsed['expectUiStateKeys']),
        expectUiEvidencePaths: _stringList(parsed['expectUiEvidencePaths']),
        expectUiArtifactKinds: _stringList(parsed['expectUiArtifactKinds']),
      );
      await _json(request, 200, result);
      return;
    }
    await _json(request, 404, {'error': 'not found'});
  }
}

Future<void> _json(
  HttpRequest request,
  int status,
  Map<String, dynamic> body,
) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType.json
    ..write(jsonEncode(body));
  await request.response.close();
}

Map<String, dynamic> _messageToEvidence(Message message) {
  final json = message.toJson();
  if (json['content'] is String) {
    json['content'] = _truncate(json['content'] as String);
  }
  final toolResult = json['toolResult'];
  if (toolResult is Map && toolResult['content'] is String) {
    toolResult['content'] = _truncate(toolResult['content'] as String);
  }
  return json;
}

List<Map<String, dynamic>> _toolCallsFromMessages(
  List<Map<String, dynamic>> messages,
) {
  final calls = <Map<String, dynamic>>[];
  for (final message in messages) {
    final toolUses = message['toolUses'];
    if (toolUses is! List) continue;
    for (final rawUse in toolUses) {
      if (rawUse is! Map) continue;
      final name = '${rawUse['name'] ?? rawUse['toolName'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final input = rawUse['input'] is Map
          ? Map<String, dynamic>.from(rawUse['input'] as Map)
          : <String, dynamic>{};
      calls.add({
        if (rawUse['id'] != null) 'id': rawUse['id'],
        'toolName': name,
        'input': input,
      });
    }
  }
  return calls;
}

List<Map<String, dynamic>> _toolResultsFromMessages(
  List<Map<String, dynamic>> messages,
) {
  final results = <Map<String, dynamic>>[];
  final toolNamesById = <String, String>{};
  for (final message in messages) {
    final toolUses = message['toolUses'];
    if (toolUses is! List) continue;
    for (final rawUse in toolUses) {
      if (rawUse is! Map) continue;
      final id = '${rawUse['id'] ?? ''}'.trim();
      final name = '${rawUse['name'] ?? rawUse['toolName'] ?? ''}'.trim();
      if (id.isNotEmpty && name.isNotEmpty) toolNamesById[id] = name;
    }
  }
  for (final message in messages) {
    final toolResult = message['toolResult'];
    if (toolResult is! Map) continue;
    final toolUseId = '${toolResult['toolUseId'] ?? ''}'.trim();
    final toolName =
        (toolNamesById[toolUseId] ??
                '${toolResult['toolName'] ?? toolResult['name'] ?? ''}')
            .trim();
    results.add({
      if (toolUseId.isNotEmpty) 'toolUseId': toolUseId,
      if (toolName.isNotEmpty) 'toolName': toolName,
      'isError': toolResult['isError'] == true,
      if (toolResult['durationMs'] != null)
        'durationMs': toolResult['durationMs'],
      'result': _truncate('${toolResult['content'] ?? ''}'),
    });
  }
  return results;
}

Map<String, dynamic> _summarizeReportFile(File file) {
  final modifiedAt = file.statSync().modified.toUtc().toIso8601String();
  final name = file.uri.pathSegments.isNotEmpty
      ? file.uri.pathSegments.last
      : file.path.split(Platform.pathSeparator).last;
  try {
    final parsed = jsonDecode(file.readAsStringSync());
    if (parsed is! Map) {
      return {
        'file': name,
        'path': file.path,
        'kind': 'unknown',
        'modifiedAt': modifiedAt,
        'parseError': 'report root is not an object',
      };
    }
    final toolCalls = parsed['toolCalls'] is List
        ? parsed['toolCalls'] as List
        : const [];
    final toolErrors = parsed['toolErrors'] is List
        ? parsed['toolErrors'] as List
        : const [];
    final assertions = parsed['assertions'] is List
        ? parsed['assertions'] as List
        : const [];
    final uiArtifacts = parsed['uiArtifacts'] is List
        ? (parsed['uiArtifacts'] as List).take(20).toList(growable: false)
        : const [];
    final failedAssertions = assertions
        .whereType<Map>()
        .where((assertion) => assertion['ok'] != true)
        .map((assertion) => '${assertion['name'] ?? 'unknown'}')
        .where((name) => name.isNotEmpty)
        .take(20)
        .toList(growable: false);
    final kind =
        name.endsWith('-scenario.json') || parsed['scenarioId'] is String
        ? 'scenario'
        : 'run';
    return {
      'file': name,
      'path': file.path,
      'kind': kind,
      'modifiedAt': modifiedAt,
      'runId': parsed['runId'],
      'scenarioId': parsed['scenarioId'],
      'ok': parsed['ok'],
      'createdAt': parsed['createdAt'],
      'startedAt': parsed['startedAt'],
      'finishedAt': parsed['finishedAt'],
      'prompt': parsed['prompt'],
      'sessionId': parsed['sessionId'],
      'toolCallCount': toolCalls.length,
      'toolErrorCount': toolErrors.length,
      'assertionCount': assertions.length,
      'assertionPassCount': assertions
          .whereType<Map>()
          .where((assertion) => assertion['ok'] == true)
          .length,
      'assertionFailCount': failedAssertions.length,
      'failedAssertions': failedAssertions,
      'uiEvidence': parsed['uiEvidence'],
      'uiArtifacts': uiArtifacts,
      'uiArtifactCount': parsed['uiArtifacts'] is List
          ? (parsed['uiArtifacts'] as List).length
          : 0,
      'finalAssistantPresent':
          '${parsed['finalAssistant'] ?? parsed['finalAssistantText'] ?? ''}'
              .isNotEmpty,
    };
  } catch (e) {
    return {
      'file': name,
      'path': file.path,
      'kind': 'unknown',
      'modifiedAt': modifiedAt,
      'parseError': e.toString(),
    };
  }
}

String _finalAssistantText(List<Message> messages) {
  for (final message in messages.reversed) {
    if (message.role == Role.assistant && message.content.trim().isNotEmpty) {
      return _truncate(message.content.trim(), max: 12000);
    }
  }
  return '';
}

int _countNonEmptyLines(String? path) {
  if (path == null || path.isEmpty) return 0;
  final file = File(path);
  if (!file.existsSync()) return 0;
  return file.readAsLinesSync().where((line) => line.trim().isNotEmpty).length;
}

bool _sessionFileExists(String? path) {
  return path != null && path.isNotEmpty && File(path).existsSync();
}

String _truncate(String value, {int max = 8000}) {
  if (value.length <= max) return value;
  return '${value.substring(0, max)}...<truncated>';
}

String _runId(DateTime startedAt) =>
    'workflow-${startedAt.toIso8601String().replaceAll(RegExp(r'[:.]'), '-')}';

List<WorkflowAutomationScenarioAssertion> _evaluateScenario(
  WorkflowAutomationScenario scenario,
  WorkflowAutomationRunResult run,
) {
  final report = run.report;
  final toolCalls = (report['toolCalls'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => '${item['toolName'] ?? item['name'] ?? ''}')
      .where((item) => item.isNotEmpty)
      .toList();
  final toolActions = (report['toolCalls'] as List? ?? const [])
      .whereType<Map>()
      .map((item) {
        final toolName = '${item['toolName'] ?? item['name'] ?? ''}';
        final input = item['input'];
        final action = input is Map ? '${input['action'] ?? ''}' : '';
        if (toolName.isEmpty) return '';
        return action.isEmpty ? toolName : '$toolName.$action';
      })
      .where((item) => item.isNotEmpty)
      .toList();
  final dataToolCalls = toolCalls
      .where(
        (name) => const {
          'MarketData',
          'DataProcess',
          'DataTask',
          'Portfolio',
          'Research',
          'WindMcp',
        }.contains(name),
      )
      .toList();
  final toolErrors = (report['toolErrors'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => '${item['result'] ?? item['content'] ?? ''}')
      .where((item) => item.isNotEmpty)
      .toList();
  final toolResults = (report['toolResults'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => '${item['result'] ?? item['content'] ?? ''}')
      .where((item) => item.isNotEmpty)
      .toList();
  final finalText = '${report['finalAssistantText'] ?? ''}';
  final sessionText = jsonEncode(report['messages'] ?? const []);
  final uiState = report['uiState'];
  final uiEvidence = report['uiEvidence'];
  final uiEvidencePaths = uiEvidence is Map && uiEvidence['paths'] is List
      ? (uiEvidence['paths'] as List).map((path) => '$path').toList()
      : const <String>[];
  final uiArtifactKinds = (report['uiArtifacts'] as List? ?? const [])
      .whereType<Map>()
      .map((artifact) => '${artifact['kind'] ?? ''}')
      .where((kind) => kind.isNotEmpty)
      .toList();
  final pendingUserQuestionObserved =
      report['pendingUserQuestionObserved'] == true ||
      (report['interactiveState'] is Map &&
          (report['interactiveState'] as Map)['hasPendingUserQuestion'] ==
              true);
  final assertions = <WorkflowAutomationScenarioAssertion>[
    WorkflowAutomationScenarioAssertion(
      name: 'run.ok',
      ok: run.ok,
      expected: true,
      actual: run.ok,
    ),
    WorkflowAutomationScenarioAssertion(
      name: 'session.messages',
      ok: (report['messageCount'] as int? ?? 0) > 0,
      expected: 'non-empty',
      actual: report['messageCount'],
    ),
  ];
  for (final tool in scenario.disallowTools) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'disallowTool.$tool',
        ok: !toolCalls.contains(tool),
        expected: 'not used',
        actual: toolCalls,
      ),
    );
  }
  if (scenario.maxToolCalls != null) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'maxToolCalls.${scenario.maxToolCalls}',
        ok: toolCalls.length <= scenario.maxToolCalls!,
        expected: '<= ${scenario.maxToolCalls}',
        actual: toolCalls,
      ),
    );
  }
  if (scenario.minToolCalls != null) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'minToolCalls.${scenario.minToolCalls}',
        ok: toolCalls.length >= scenario.minToolCalls!,
        expected: '>= ${scenario.minToolCalls}',
        actual: toolCalls,
      ),
    );
  }
  if (scenario.maxDataToolCalls != null) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'maxDataToolCalls.${scenario.maxDataToolCalls}',
        ok: dataToolCalls.length <= scenario.maxDataToolCalls!,
        expected: '<= ${scenario.maxDataToolCalls}',
        actual: dataToolCalls,
      ),
    );
  }
  for (final tool in scenario.expectTools) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'tool.$tool',
        ok: toolCalls.contains(tool),
        expected: tool,
        actual: toolCalls,
      ),
    );
  }
  for (final expected in scenario.expectToolActions) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'toolAction.$expected',
        ok: _toolActionMatches(toolActions, expected),
        expected: expected,
        actual: toolActions,
      ),
    );
  }
  for (final entry in scenario.maxToolActionCounts.entries) {
    final action = entry.key;
    final maxCount = entry.value;
    final count = toolActions
        .where((actual) => _toolActionNameMatches(actual, action))
        .length;
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'maxToolActionCounts.$action',
        ok: count <= maxCount,
        expected: '<= $maxCount',
        actual: count,
      ),
    );
  }
  for (final expected in scenario.expectToolErrors) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'toolError.$expected',
        ok: toolErrors.any((error) => error.contains(expected)),
        expected: expected,
        actual: toolErrors,
      ),
    );
  }
  if (scenario.expectNoToolErrors) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'toolErrors.none',
        ok: toolErrors.isEmpty,
        expected: 'no tool errors',
        actual: toolErrors,
      ),
    );
  }
  if (scenario.allowPendingUserQuestion &&
      scenario.autoAnswerUserQuestions.isNotEmpty) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'pendingUserQuestion.observed',
        ok: pendingUserQuestionObserved,
        expected: true,
        actual:
            report['pendingUserQuestion'] ??
            report['interactiveState'] ??
            pendingUserQuestionObserved,
      ),
    );
  }
  for (final expected in scenario.expectToolResultContains) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'toolResultContains.$expected',
        ok: toolResults.any((result) => result.contains(expected)),
        expected: expected,
        actual: toolResults,
      ),
    );
  }
  for (final expected in scenario.expectFinalContains) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'finalContains.$expected',
        ok: finalText.contains(expected),
        expected: expected,
        actual: finalText,
      ),
    );
  }
  for (final expected in scenario.expectSessionContains) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'sessionContains.$expected',
        ok: sessionText.contains(expected),
        expected: expected,
        actual: sessionText,
      ),
    );
  }
  for (final key in scenario.expectUiStateKeys) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'uiState.$key',
        ok: _hasPath(uiState, key),
        expected: key,
        actual: uiState,
      ),
    );
  }
  for (final path in scenario.expectUiEvidencePaths) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'uiEvidence.$path',
        ok: uiEvidencePaths.contains(path),
        expected: path,
        actual: uiEvidencePaths,
      ),
    );
  }
  for (final kind in scenario.expectUiArtifactKinds) {
    assertions.add(
      WorkflowAutomationScenarioAssertion(
        name: 'uiArtifact.$kind',
        ok: uiArtifactKinds.contains(kind),
        expected: kind,
        actual: uiArtifactKinds,
      ),
    );
  }
  return assertions;
}

List<AgentEvent> _eventsFromReport(Map<String, dynamic> report) {
  final events = <AgentEvent>[];
  for (final call in (report['toolCalls'] as List? ?? const [])) {
    if (call is! Map) continue;
    final toolName = '${call['toolName'] ?? call['name'] ?? ''}';
    if (toolName.isEmpty) continue;
    final input = call['input'] is Map
        ? Map<String, dynamic>.from(call['input'] as Map)
        : <String, dynamic>{};
    events.add(AgentToolUseStart(toolName: toolName, input: input));
  }
  return events;
}

String? _workflowLimitError(
  List<AgentEvent> events, {
  required int? maxToolCalls,
  required int? maxDataToolCalls,
  required List<String> disallowTools,
}) {
  final disallowed = disallowTools.toSet();
  final toolCalls = <String>[];
  final dataToolCalls = <String>[];
  for (final event in events) {
    if (event is! AgentToolUseStart) continue;
    final name = event.toolName;
    toolCalls.add(name);
    if (_isDataWorkflowTool(name)) dataToolCalls.add(name);
    if (disallowed.contains(name)) {
      return 'WORKFLOW_AUTOMATION_TOOL_LIMIT: used disallowed tool $name';
    }
  }
  if (maxToolCalls != null && toolCalls.length > maxToolCalls) {
    return 'WORKFLOW_AUTOMATION_TOOL_LIMIT: exceeded maxToolCalls $maxToolCalls; counted tools: ${toolCalls.join(', ')}';
  }
  if (maxDataToolCalls != null && dataToolCalls.length > maxDataToolCalls) {
    return 'WORKFLOW_AUTOMATION_TOOL_LIMIT: exceeded maxDataToolCalls $maxDataToolCalls; counted workflow data tools: ${dataToolCalls.join(', ')}';
  }
  return null;
}

bool _isDataWorkflowTool(String name) => const {
  'MarketData',
  'DataProcess',
  'DataTask',
  'Portfolio',
  'Research',
  'WindMcp',
}.contains(name);

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

Map<String, int> _stringIntMap(Object? value) {
  if (value is! Map) return const {};
  final out = <String, int>{};
  for (final entry in value.entries) {
    final key = '${entry.key}'.trim();
    if (key.isEmpty) continue;
    final count = entry.value is num
        ? (entry.value as num).toInt()
        : int.tryParse('${entry.value}');
    if (count == null || count < 0) continue;
    out[key] = count;
  }
  return out;
}

bool _toolActionMatches(List<String> toolActions, String expected) =>
    toolActions.any((actual) => _toolActionNameMatches(actual, expected));

bool _toolActionNameMatches(String actual, String expected) {
  if (actual == expected || actual.endsWith('.$expected')) return true;
  final normalizedActual = _equivalentToolActionName(actual);
  final normalizedExpected = _equivalentToolActionName(expected);
  return normalizedActual == normalizedExpected ||
      normalizedActual.endsWith('.$normalizedExpected');
}

String _equivalentToolActionName(String value) {
  final text = value.trim();
  final action = text.contains('.') ? text.split('.').last : text;
  if (action == 'quote' || action == 'query_quote') {
    final prefix = text.contains('.')
        ? text.substring(0, text.length - action.length)
        : '';
    return '${prefix}query_quote';
  }
  return text;
}

int? _optionalPositiveInt(Object? value) {
  final parsed = value is num ? value.toInt() : int.tryParse('$value');
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

Duration? _optionalDurationMs(Object? value) {
  final parsed = _optionalPositiveInt(value);
  if (parsed == null) return null;
  final bounded = parsed.clamp(1000, 120000);
  return Duration(milliseconds: bounded);
}

bool _hasPath(Object? value, String path) {
  Object? current = value;
  for (final part in path.split('.').where((part) => part.isNotEmpty)) {
    if (current is Map) {
      if (!current.containsKey(part)) return false;
      current = current[part];
      continue;
    }
    if (current is List) {
      final index = int.tryParse(part);
      if (index == null || index < 0 || index >= current.length) return false;
      current = current[index];
      continue;
    }
    return false;
  }
  return true;
}

Map<String, dynamic> _buildUiEvidence(Object? uiState, {Object? semantics}) {
  final paths = <String>[];
  _collectUiPaths(uiState, paths: paths);
  final semanticsPaths = <String>[];
  _collectUiPaths(semantics, paths: semanticsPaths);
  return {
    'available': uiState != null,
    'kind': uiState == null ? 'none' : 'state',
    'pathCount': paths.length,
    'paths': paths,
    'snapshotAvailable': uiState != null,
    'semanticsAvailable': semantics != null,
    'semanticsPathCount': semanticsPaths.length,
    'semanticsPaths': semanticsPaths,
    ...?semantics == null ? null : {'semantics': semantics},
  };
}

void _collectUiPaths(
  Object? value, {
  required List<String> paths,
  String prefix = '',
}) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    for (final entry in entries) {
      final key = '$prefix${prefix.isEmpty ? '' : '.'}${entry.key}';
      paths.add(key);
      _collectUiPaths(entry.value, paths: paths, prefix: key);
    }
    return;
  }
  if (value is List) {
    for (var i = 0; i < value.length && i < 20; i++) {
      final key = '$prefix[$i]';
      paths.add(key);
      _collectUiPaths(value[i], paths: paths, prefix: key);
    }
  }
}

String _safeFilePart(String value) {
  final safe = value
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  if (safe.isEmpty) return 'scenario';
  return safe.length > 80 ? safe.substring(0, 80) : safe;
}
