part of 'finagent_screen.dart';

extension _UIHandlers on _FinAgentScreenState {
  void _registerUIHandlers() {
    widget.uiQueryTool.handler = (key) async {
      final r = _handleDashboardQuery('fin', _dash, key);
      return r ??
          json.encode({'error': AppLocalizations.of(context).unknownKey(key)});
    };

    widget.uiControlTool.handler = (action, params) async {
      final panelId = params['id'] ?? params['panelId'] ?? params['panelType'];
      if (action == 'openPanel' && panelId == 'api_health') {
        _showApiHealthPanel();
        return json.encode({
          'ok': true,
          'action': 'openPanel',
          'panel': 'api_health',
          'title': AppLocalizations.of(context).apiHealth,
          'observed': true,
        });
      }
      if (action == 'openPanel' && panelId == 'history') {
        final count = widget.agent.sessionManager.listHistoryFiles().length;
        _showHistoryPanel();
        return json.encode({
          'ok': count > 0,
          'action': 'openPanel',
          'panel': 'history',
          'title': AppLocalizations.of(context).history,
          'observed': count > 0,
          'historyFiles': count,
        });
      }
      if (action == 'openPanel' && panelId == 'session') {
        final count = widget.agent.sessionManager.listHistory().length;
        _showSessionPanel();
        return json.encode({
          'ok': count > 0,
          'action': 'openPanel',
          'panel': 'session',
          'title': AppLocalizations.of(context).session,
          'observed': count > 0,
          'sessions': count,
        });
      }
      // Map new page actions + legacy dashboard actions to prefixed ones
      final mapped = switch (action) {
        'openPage' || 'navigate' || 'addDashboard' => 'fin:openPage',
        'addPage' => 'fin:addPage',
        'closePage' => 'fin:closePage',
        'removePage' || 'removeDashboard' => 'fin:removePage',
        'selectDashboard' => 'fin:openPage',
        'togglePanel' => 'fin:togglePanel',
        _ => action,
      };
      final r = _handleDashboardControl('fin', _dash, mapped, params);
      if (r != null) return await r;
      return _handleChatUIControl(action, params);
    };

    widget.askUserQuestionTool.handler = _handleAskUser;
  }

  String _handleChatUIControl(String action, Map<String, dynamic> params) {
    if (action == 'showQuote') {
      final data = params['data'] as Map<String, dynamic>? ?? params;
      _items.add(
        ChatItem(
          role: 'ui_widget',
          content: '',
          metadata: {
            'action': 'showQuote',
            'params': {'data': data},
          },
        ),
      );
      _setState(() {});
      return json.encode({
        'ok': true,
        'action': 'showQuote',
        'rendered': true,
        'position': 'inline chat message #${_items.length}',
        'fields': data.keys.toList(),
        'symbol': data['ts_code'] ?? data['symbol'] ?? 'unknown',
      });
    }
    if (action == 'showTable') {
      final data = params['data'];
      final title = params['title'] as String? ?? '';
      final columns = params['columns'] as List?;
      final rows = data is List ? data : [];
      _items.add(
        ChatItem(
          role: 'ui_widget',
          content: '',
          metadata: {
            'action': 'showTable',
            'params': {'title': title, 'data': data},
          },
        ),
      );
      _setState(() {});
      return json.encode({
        'ok': true,
        'action': 'showTable',
        'rendered': true,
        'position': 'inline chat message #${_items.length}',
        'title': title,
        'columns': columns?.length ?? 'auto',
        'rows': rows.length,
      });
    }
    if (action == 'showChart') {
      final dataFile = params['dataFile'] as String?;
      if (dataFile == null || dataFile.isEmpty) {
        return json.encode({
          'error': AppLocalizations.of(context).showChartRequiresDataFile,
        });
      }
      final basePath = widget.agent.toolContext.basePath;
      final path = dataFile.startsWith('/') ? dataFile : '$basePath/$dataFile';
      final file = File(path);
      debugPrint(
        '[UIControl] showChart: dataFile=$dataFile, resolved=$path, exists=${file.existsSync()}',
      );
      if (!file.existsSync()) {
        return json.encode({
          'error': AppLocalizations.of(context).dataFileNotFound(path),
          'hint': AppLocalizations.of(context).showChartCreateJsonHint,
        });
      }
      try {
        final content = file.readAsStringSync();
        final fileData = json.decode(content) as Map<String, dynamic>;

        // Validate and normalize data format
        Map<String, dynamic> normalizedData;
        final columns = fileData['columns'] as List?;
        final data = fileData['data'] as List?;

        if (data == null || data.isEmpty) {
          return json.encode({
            'error': AppLocalizations.of(context).showChartDataMissing,
            'hint': AppLocalizations.of(context).showChartDataArrayHint,
            'actualKeys': fileData.keys.toList(),
          });
        }

        if (columns != null && columns.isNotEmpty) {
          // Tushare format: {columns: [...], data: [[...], ...]} — use as is
          normalizedData = fileData;
        } else if (data.first is Map) {
          // Object array format: {data: [{date:..., open:..., ...}, ...]} — convert to Tushare format
          final firstRow = data.first as Map<String, dynamic>;
          final derivedColumns = firstRow.keys.toList();
          final derivedRows = data.map((row) {
            if (row is Map<String, dynamic>) {
              return derivedColumns.map((col) => row[col]).toList();
            }
            return row;
          }).toList();
          normalizedData = {
            ...fileData,
            'columns': derivedColumns,
            'data': derivedRows,
          };
        } else {
          // Unknown format
          return json.encode({
            'error': AppLocalizations.of(
              context,
            ).showChartDataFormatUnrecognized,
            'hint': AppLocalizations.of(context).showChartExpectedFormatsHint,
            'actualKeys': fileData.keys.toList(),
            'dataType': data.first.runtimeType.toString(),
          });
        }

        debugPrint(
          '[UIControl] showChart: parsed OK, keys=${fileData.keys.toList()}, columns=${(normalizedData['columns'] as List?)?.length}, rows=${(normalizedData['data'] as List?)?.length}',
        );
        _items.add(
          ChatItem(
            role: 'ui_widget',
            content: 'chart',
            metadata: {
              'action': 'showChart',
              'params': {...params, '_fileData': normalizedData},
            },
          ),
        );
        _setState(() {});
        final normColumns = normalizedData['columns'] as List?;
        final normRows = normalizedData['data'] as List?;
        return json.encode({
          'ok': true,
          'action': 'showChart',
          'rendered': true,
          'position': 'inline chat message #${_items.length}',
          'dataFile': path,
          'fileSize': '${(content.length / 1024).toStringAsFixed(1)} KB',
          'columns': normColumns?.length ?? 0,
          'rows': normRows?.length ?? 0,
          'columnNames': normColumns?.take(8).toList(),
        });
      } catch (e) {
        debugPrint('[UIControl] showChart: parse error: $e');
        return json.encode({
          'error': AppLocalizations.of(context).failedToParseDataFile(e),
          'hint': AppLocalizations.of(context).showChartJsonHint,
        });
      }
    }
    if (action == 'showHtml') {
      final html = params['html'] as String? ?? '';
      _items.add(
        ChatItem(
          role: 'ui_widget',
          content: '',
          metadata: {
            'action': 'showHtml',
            'params': {'html': html},
          },
        ),
      );
      _setState(() {});
      return json.encode({
        'ok': true,
        'action': 'showHtml',
        'rendered': true,
        'position': 'inline chat message #${_items.length}',
        'htmlLength': html.length,
        'preview': html.length > 100 ? '${html.substring(0, 100)}...' : html,
      });
    }
    return json.encode({
      'error': AppLocalizations.of(context).unknownAction(action),
      'available': [
        'showQuote',
        'showTable',
        'showChart',
        'showHtml',
        'addPage',
        'openPage',
        'closePage',
        'removePage',
      ],
    });
  }

  Future<Map<String, String>> _handleAskUser(
    List<UserQuestion> questions,
  ) async {
    final completer = Completer<Map<String, String>>();
    _setState(() {
      _pendingQuestions = questions;
      _questionCompleter = completer;
      _currentQuestionIndex = 0;
      _collectedAnswers.clear();
      _items.add(
        ChatItem(
          role: 'user_question',
          content: '',
          metadata: {
            'questions': questions
                .map(
                  (q) => {
                    'question': q.question,
                    'options': q.options
                        .map(
                          (o) => {
                            'label': o.label,
                            'description': o.description,
                          },
                        )
                        .toList(),
                  },
                )
                .toList(),
          },
        ),
      );
    });
    try {
      return await completer.future;
    } finally {
      _setState(() {
        _pendingQuestions = null;
        _questionCompleter = null;
      });
    }
  }

  void _sendToEventAgent() {
    final text = _eventController.text.trim();
    if (text.isEmpty) return;
    _eventController.clear();

    _setState(() {
      _eventItems.add(ChatItem(role: 'user', content: text));
    });

    _eventRuntime.agent.notificationQueue.enqueue(
      PendingNotification(
        prompt: text,
        priority: NotificationPriority.now,
        source: 'user_input',
      ),
    );
  }

  void _interceptCronForEventAgent() {
    widget.agent.cronScheduler?.onFire = (task) {
      _eventRuntime.agent.notificationQueue.enqueue(
        PendingNotification(prompt: task.prompt, source: 'cron'),
      );
      log(
        'EventAgent',
        'Cron fire → event agent: ${task.prompt.length > 60 ? '${task.prompt.substring(0, 60)}...' : task.prompt}',
      );
    };
  }
}
