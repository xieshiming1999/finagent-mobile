part of 'finagent_screen.dart';

extension _EventHandler on _FinAgentScreenState {
  void _listenToStream(Stream<AgentEvent> stream) {
    _subscription?.cancel();
    _subscription = stream.listen((event) {
      _setState(() => _handleEvent(event));
      _scrollToBottom();
    });
  }

  void _handleEvent(AgentEvent event) {
    final l10n = AppLocalizations.of(context);
    switch (event) {
      case AgentTextDelta(:final text):
        _lastAssistant().content += text;
        _agentStatus?.onTokenReceived();

      case AgentToolConfirmRequest(
        :final toolName,
        :final input,
        :final completer,
      ):
        _showToolConfirmDialog(toolName, input, completer);

      case AgentToolUseStart(:final toolName, :final input):
        _agentStatus?.onToolStart(
          toolName,
          _summarizeToolInput(toolName, input),
        );
        _agentStatus?.trackMemory(toolName, input);
        _items.add(
          ChatItem(
            role: 'tool_use',
            content: '$toolName(${_summarizeToolInput(toolName, input)})',
            metadata: {'status': 'running'},
          ),
        );

      case AgentToolResult(
        :final toolName,
        :final result,
        :final isError,
        :final durationMs,
      ):
        _agentStatus?.onToolEnd(durationMs);
        for (var i = _items.length - 1; i >= 0; i--) {
          if (_items[i].role == 'tool_use' &&
              _items[i].metadata?['status'] == 'running') {
            _items[i].metadata!['status'] = isError ? 'error' : 'ok';
            if (isError) _items[i].metadata!['error'] = result;
            break;
          }
        }
        if (!isError && toolName == 'UIControl') {
          final parsed = _tryParseUIControl(result);
          if (parsed != null)
            _items.add(
              ChatItem(role: 'ui_widget', content: result, metadata: parsed),
            );
        }
      // Let the next text delta create a visible assistant bubble after the
      // tool boundary. Pre-creating blank bubbles makes long tool loops look
      // like the agent produced no output.

      case AgentDone():
        _isLoading = false;
        if (_items.isNotEmpty &&
            _items.last.role == 'assistant' &&
            _items.last.content.isEmpty) {
          _items.removeLast();
        }
        if (_agentStatus != null) {
          _statusTimer?.cancel();
          _agentStatus = null;
        }

      case AgentThinking(:final text):
        if (_items.isEmpty || _items.last.role != 'assistant') {
          _items.add(ChatItem(role: 'assistant', content: '', thinking: ''));
        }
        _items.last.thinking = (_items.last.thinking ?? '') + text;
        if (_agentStatus != null) _agentStatus!.verb = l10n.thinking;

      case AgentError(:final message):
        _items.add(
          ChatItem(
            role: 'tool_result',
            content: '${l10n.errorPrefix}: $message',
          ),
        );
        _isLoading = false;
        _statusTimer?.cancel();
        _agentStatus = null;

      case AgentCommandOutput(:final text):
        _items.add(ChatItem(role: 'assistant', content: text));

      case AgentSessionCleared():
        _items.clear();

      case AgentSessionResumed():
        _items.clear();
        _restoreSession();

      case AgentCompacted(:final preCompactCount, :final postCompactCount):
        _items.add(
          ChatItem(
            role: 'tool_result',
            content: l10n.compactedSummary(preCompactCount, postCompactCount),
          ),
        );

      case AgentBackgrounded(:final taskId):
        _items.add(
          ChatItem(
            role: 'tool_result',
            content: l10n.backgroundTaskSummary(taskId),
          ),
        );
        _isLoading = false;

      case AgentSessionList(:final prompt, :final sessions, :final completer):
        _showSessionPicker(prompt, sessions, completer);

      case AgentStreamStart():
        _agentStatus = AgentStatus(
          verb: localizedRandomSpinnerVerb(isChinese: l10n.isChinese),
        )..contextWindow = widget.agent.contextWindow;
        _turnSummary = null;
        _summaryTimer?.cancel();
        _statusTimer?.cancel();
        _statusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) _setState(() {});
        });

      case AgentUsage(:final promptTokens, :final completionTokens):
        _agentStatus?.onUsage(promptTokens, completionTokens);

      case AgentTurnComplete(
        :final durationMs,
        :final toolCallCount,
        :final promptTokens,
        :final completionTokens,
      ):
        _statusTimer?.cancel();
        final parts = <String>[
          '${localizedRandomTurnCompleteVerb(isChinese: l10n.isChinese)} ${formatDuration(durationMs)}',
          if (toolCallCount > 0) l10n.toolCallsText(toolCallCount),
          if (promptTokens + completionTokens > 0)
            l10n.tokenCountText(formatTokens(promptTokens + completionTokens)),
        ];
        _turnSummary = parts.join(' · ');
        _agentStatus = null;
        _summaryTimer?.cancel();
        _summaryTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _setState(() => _turnSummary = null);
        });

      case AgentToolProgress(:final output):
        for (var i = _items.length - 1; i >= 0; i--) {
          if (_items[i].role == 'tool_use' &&
              _items[i].metadata?['status'] == null) {
            _items[i].subEvents ??= [];
            final subs = _items[i].subEvents!;
            final type = output.startsWith('thinking:')
                ? 'thinking'
                : output.startsWith('tool:')
                ? 'tool'
                : 'result';
            final content = output.replaceFirst(
              RegExp(r'^(thinking|tool|result): ?'),
              '',
            );
            if (type == 'result') {
              for (var j = subs.length - 1; j >= 0; j--) {
                if (subs[j].type == 'tool' && subs[j].status == null) {
                  subs[j].status = content.startsWith('error') ? 'error' : 'ok';
                  break;
                }
              }
            } else {
              if (subs.isNotEmpty && subs.last.type == 'thinking')
                subs.removeLast();
              subs.add(SubEvent(type: type, content: content));
            }
            break;
          }
        }

      case AgentToolCallStreaming(:final toolName):
        _agentStatus?.verb = l10n.generating;
        _agentStatus?.currentTool = toolName;

      case AgentOutputChars(:final chars):
        _agentStatus?.onTokenReceived(chars: chars);

      case AgentTasksChanged(:final tasks):
        _tasks = tasks;

      case AgentSuggestion():
        break;

      case AgentNotificationReceived():
        break;
    }
  }

  void _handleEventAgentEvent(AgentEvent event) {
    final l10n = AppLocalizations.of(context);
    switch (event) {
      case AgentNotificationReceived(:final prompt):
        log('EventAgent', 'Notification received (${prompt.length} chars)');
        _eventItems.add(ChatItem(role: 'notification', content: prompt));
        _eventPanelNotifier.value++;
        // Show brief status in main chat's status bar
        _turnSummary = l10n.eventNewMessageSummary();
        _summaryTimer?.cancel();
        _summaryTimer = Timer(const Duration(seconds: 3), () {
          if (mounted && _turnSummary == l10n.eventNewMessageSummary()) {
            _setState(() => _turnSummary = null);
          }
        });

      case AgentStreamStart():
        log('EventAgent', 'LLM turn started');
        _eventStatus = AgentStatus(verb: l10n.eventLabel);
        _eventTurnSummary = null;
        _eventSummaryTimer?.cancel();
        _eventStatusTimer?.cancel();
        _eventStatusTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) _setState(() {});
          _eventPanelNotifier.value++;
        });

      case AgentTextDelta(:final text):
        _lastAssistantOf(_eventItems).content += text;
        _eventStatus?.onTokenReceived();

      case AgentThinking(:final text):
        if (_eventItems.isEmpty || _eventItems.last.role != 'assistant') {
          _eventItems.add(
            ChatItem(role: 'assistant', content: '', thinking: ''),
          );
        }
        _eventItems.last.thinking = (_eventItems.last.thinking ?? '') + text;
        if (_eventStatus != null) _eventStatus!.verb = l10n.thinking;

      case AgentToolUseStart(:final toolName, :final input):
        _eventStatus?.onToolStart(
          toolName,
          _summarizeToolInput(toolName, input),
        );
        _eventStatus?.onTokenReceived();
        _eventItems.add(
          ChatItem(
            role: 'tool_use',
            content: '$toolName(${_summarizeToolInput(toolName, input)})',
            metadata: {'status': 'running'},
          ),
        );

      case AgentToolResult(:final result, :final isError, :final durationMs):
        _eventStatus?.onToolEnd(durationMs);
        for (var i = _eventItems.length - 1; i >= 0; i--) {
          if (_eventItems[i].role == 'tool_use' &&
              _eventItems[i].metadata?['status'] == 'running') {
            _eventItems[i].metadata!['status'] = isError ? 'error' : 'ok';
            if (isError) _eventItems[i].metadata!['error'] = result;
            break;
          }
        }
        _eventItems.add(ChatItem(role: 'assistant', content: ''));

      case AgentUsage(:final promptTokens, :final completionTokens):
        _eventStatus?.promptTokens += promptTokens;
        _eventStatus?.completionTokens += completionTokens;
      case AgentOutputChars(:final chars):
        _eventStatus?.onTokenReceived(chars: chars);
      case AgentToolCallStreaming(:final toolName):
        _eventStatus?.verb = l10n.generating;
        _eventStatus?.currentTool = toolName;

      case AgentTurnComplete(
        :final durationMs,
        :final toolCallCount,
        :final promptTokens,
        :final completionTokens,
      ):
        _eventStatusTimer?.cancel();
        _eventStatus = null;
        final parts = <String>[
          l10n.eventDoneSummary(formatDuration(durationMs)),
          if (toolCallCount > 0) l10n.toolCallsText(toolCallCount),
          if (promptTokens + completionTokens > 0)
            l10n.tokenCountText(formatTokens(promptTokens + completionTokens)),
        ];
        _eventTurnSummary = parts.join(' · ');
        _eventSummaryTimer?.cancel();
        _eventSummaryTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) _setState(() => _eventTurnSummary = null);
        });
        _eventPanelNotifier.value++;

      case AgentDone():
        _eventStatusTimer?.cancel();
        _eventStatus = null;
        if (_eventItems.isNotEmpty &&
            _eventItems.last.role == 'assistant' &&
            _eventItems.last.content.isEmpty) {
          _eventItems.removeLast();
        }
        for (final item in _eventItems) {
          if (item.role == 'tool_use' &&
              item.metadata?['status'] == 'running') {
            item.metadata!['status'] = 'ok';
          }
        }

      case AgentError(:final message):
        log('EventAgent', 'ERROR $message');
        debugPrint('[EventAgent] Error: $message');
        _eventStatusTimer?.cancel();
        _eventStatus = null;
        for (final item in _eventItems) {
          if (item.role == 'tool_use' &&
              item.metadata?['status'] == 'running') {
            item.metadata!['status'] = 'error';
          }
        }
        _eventItems.add(
          ChatItem(
            role: 'tool_result',
            content: '${l10n.errorPrefix}: $message',
          ),
        );

      case AgentToolConfirmRequest(:final completer):
        completer.complete(const ToolConfirmResult.approve());

      case AgentCommandOutput(:final text):
        _eventItems.add(ChatItem(role: 'assistant', content: text));

      case AgentCompacted(:final preCompactCount, :final postCompactCount):
        _eventItems.add(
          ChatItem(
            role: 'tool_result',
            content: l10n.compactedSummary(preCompactCount, postCompactCount),
          ),
        );

      case AgentSessionCleared():
        _eventItems.clear();

      case AgentSessionResumed():
        _eventItems.clear();
        _restoreEventSession();

      case AgentToolProgress(:final output):
        for (var i = _eventItems.length - 1; i >= 0; i--) {
          if (_eventItems[i].role == 'tool_use' &&
              _eventItems[i].metadata?['status'] == null) {
            _eventItems[i].subEvents ??= [];
            final subs = _eventItems[i].subEvents!;
            final type = output.startsWith('thinking:')
                ? 'thinking'
                : output.startsWith('tool:')
                ? 'tool'
                : 'result';
            final content = output.replaceFirst(
              RegExp(r'^(thinking|tool|result): ?'),
              '',
            );
            if (type == 'result') {
              for (var j = subs.length - 1; j >= 0; j--) {
                if (subs[j].type == 'tool' && subs[j].status == null) {
                  subs[j].status = content.startsWith('error') ? 'error' : 'ok';
                  break;
                }
              }
            } else {
              if (subs.isNotEmpty && subs.last.type == 'thinking')
                subs.removeLast();
              subs.add(SubEvent(type: type, content: content));
            }
            break;
          }
        }

      case AgentTasksChanged():
        break;

      default:
        break;
    }
  }

  ChatItem _lastAssistantOf(List<ChatItem> items) {
    if (items.isNotEmpty && items.last.role == 'assistant') {
      return items.last;
    }
    final item = ChatItem(role: 'assistant', content: '');
    items.add(item);
    return item;
  }

  ChatItem _lastAssistant() {
    if (_items.isNotEmpty && _items.last.role == 'assistant') {
      return _items.last;
    }
    final item = ChatItem(role: 'assistant', content: '');
    _items.add(item);
    return item;
  }

  void _restoreEventSession() {
    final pendingTools = <String, int>{};
    for (final msg in _eventRuntime.agent.messages) {
      switch (msg.role) {
        case Role.user:
          if (!msg.isCompactSummary) {
            _eventItems.add(
              ChatItem(role: 'notification', content: msg.content),
            );
          }
        case Role.assistant:
          if (msg.content.isNotEmpty) {
            _eventItems.add(ChatItem(role: 'assistant', content: msg.content));
          }
          for (final tu in msg.toolUses ?? <ToolUse>[]) {
            _eventItems.add(
              ChatItem(
                role: 'tool_use',
                content:
                    '${tu.name}(${_summarizeToolInput(tu.name, tu.input)})',
                metadata: {'status': 'running'},
              ),
            );
            pendingTools[tu.id] = _eventItems.length - 1;
          }
        case Role.tool:
          if (msg.toolResult != null) {
            final idx = pendingTools.remove(msg.toolResult!.toolUseId);
            if (idx != null && idx < _eventItems.length) {
              _eventItems[idx].metadata?['status'] = msg.toolResult!.isError
                  ? 'error'
                  : 'ok';
            }
          }
      }
    }
    for (final idx in pendingTools.values) {
      if (idx < _eventItems.length) _eventItems[idx].metadata?['status'] = 'ok';
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Map<String, dynamic>? _tryParseUIControl(String result) {
    try {
      final parsed = json.decode(result) as Map<String, dynamic>;
      if (parsed.containsKey('action')) return parsed;
    } catch (_) {}
    return null;
  }
}
