part of 'finagent_screen.dart';

extension _DashboardHandlers on _FinAgentScreenState {
  String? _handleDashboardQuery(
      String prefix, DashboardScreenState? state, String key) {
    if (key == '$prefix:dashboards') {
      final items = state?.dashboardItems ?? [];
      final active = state?.activeDashboard;
      return jsonEncode(items.map((i) {
        final j = i.toJson();
        j['active'] = i.id == active?.id;
        return j;
      }).toList());
    } else if (key == '$prefix:activeDashboard') {
      final active = state?.activeDashboard;
      return active != null ? jsonEncode(active.toJson()) : '{"active": null}';
    } else if (key == '$prefix:panelExpanded') {
      return jsonEncode({'expanded': state?.dashboardPanelExpanded ?? false});
    } else if (key == '$prefix:backgroundTasks') {
      final ids = state?.bgTaskIds ?? {};
      return jsonEncode({
        'running': ids.toList(),
        'count': ids.length,
        'max': 2,
        'viewingBgId': state?.viewingBgId,
      });
    }
    return null;
  }

  Future<String>? _handleDashboardControl(
      String prefix, DashboardScreenState? state,
      String action, Map<String, dynamic> params) {
    final basePath = widget.agent.toolContext.basePath;

    String resolveId(String id) => id.startsWith('/') ? id : '$basePath/$id';

    if (action == '$prefix:addPage') {
      final filePath = _dashboardFileParam(params);
      final tag = params['tag'] as String?;
      if (filePath == null) {
        return Future.value(
          jsonEncode({
            'error': AppLocalizations.of(context).missingRequiredParam('file'),
            'expected': AppLocalizations.of(context).addPageExpectedHint,
          }),
        );
      }
      final fullPath = filePath.startsWith('/') ? filePath : '$basePath/$filePath';
      final title = params['title'] as String? ?? _titleFromPath(fullPath);
      final fileExists = File(fullPath).existsSync();
      final item = DashboardItem(
        id: fullPath, title: title, filePath: fullPath,
        modified: DateTime.now(), tag: tag,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state?.addDashboard(item);
      });
      return Future.value(jsonEncode({
        'ok': true,
        'action': 'addPage',
        'id': fullPath,
        'fileExists': fileExists,
        'pageCount': (state?.dashboardItems.length ?? 0) + 1,
      }));
    } else if (action == '$prefix:openPage') {
      final filePath = _dashboardFileParam(params);
      final id = params['id'] as String?;

      // Resolve which page to open
      String? fullPath;
      if (filePath != null) {
        fullPath = filePath.startsWith('/') ? filePath : '$basePath/$filePath';
      } else if (id != null) {
        fullPath = resolveId(id);
      } else {
        return Future.value(
          jsonEncode({
            'error': AppLocalizations.of(context).missingRequiredParam('file or id'),
            'expected': AppLocalizations.of(context).openPageFileOrIdHelp,
          }),
        );
      }

      final title = params['title'] as String? ?? _titleFromPath(fullPath);

      final fileExists = File(fullPath).existsSync();
      if (!fileExists) {
        return Future.value(jsonEncode({
          'error': AppLocalizations.of(context).fileNotFoundShort(fullPath),
          'path': fullPath,
          'hint': AppLocalizations.of(context).createFileThenOpenPageHint,
        }));
      }

      final item = DashboardItem(
        id: fullPath, title: title, filePath: fullPath,
        modified: DateTime.now(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        state?.addDashboard(item);
        state?.selectDashboard(item);
      });
      return Future.value(jsonEncode({
        'ok': true,
        'action': 'openPage',
        'id': fullPath,
        'title': title,
        'webViewMode': 'split',
        'fileExists': true,
        'fileSize': File(fullPath).lengthSync(),
      }));
    } else if (action == '$prefix:closePage') {
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.closeWebView());
      return Future.value(jsonEncode({
        'ok': true,
        'action': 'closePage',
        'webViewMode': 'hidden',
      }));
    } else if (action == '$prefix:removePage') {
      final id = params['id'] as String?;
      if (id == null) {
        return Future.value(
          jsonEncode({
            'error': AppLocalizations.of(context).missingRequiredParam('id'),
            'expected': {'id': AppLocalizations.of(context).removePageIdHelp},
          }),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.removeDashboard(resolveId(id)));
      return Future.value(jsonEncode({
        'ok': true,
        'action': 'removePage',
        'id': resolveId(id),
      }));
    } else if (action == '$prefix:togglePanel') {
      final expanded = params['expanded'] as bool?;
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.toggleDashboardPanel(expanded: expanded));
      return Future.value('{"ok": true}');
    } else if (action == '$prefix:startBackground') {
      final id = params['id'] as String?;
      if (id == null) {
        return Future.value(
          jsonEncode({
            'error': AppLocalizations.of(context).missingRequiredParam('id'),
            'expected': {'id': AppLocalizations.of(context).dashboardPageIdHelp},
          }),
        );
      }
      final fullId = resolveId(id);
      final match = (state?.dashboardItems ?? []).where((i) => i.id == fullId);
      if (match.isEmpty) {
        return Future.value(
          jsonEncode({'error': AppLocalizations.of(context).dashboardNotFound}),
        );
      }
      if (state?.isBgFull == true) {
        return Future.value(
          jsonEncode({'error': AppLocalizations.of(context).backgroundSlotsFull}),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.startBackgroundTask(match.first));
      return Future.value('{"ok": true}');
    } else if (action == '$prefix:stopBackground') {
      final id = params['id'] as String?;
      if (id == null) {
        return Future.value(
          jsonEncode({
            'error': AppLocalizations.of(context).missingRequiredParam('id'),
            'expected': {'id': AppLocalizations.of(context).dashboardPageIdHelp},
          }),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.stopBackgroundTask(resolveId(id)));
      return Future.value('{"ok": true}');
    } else if (action == '$prefix:viewBackground') {
      final id = params['id'] as String?;
      if (id == null) {
        return Future.value(
          jsonEncode({
            'error': AppLocalizations.of(context).missingRequiredParam('id'),
            'expected': {'id': AppLocalizations.of(context).backgroundDashboardPageIdHelp},
          }),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.viewBackgroundTask(resolveId(id)));
      return Future.value('{"ok": true}');
    } else if (action == '$prefix:viewMain') {
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.viewMainWebView());
      return Future.value('{"ok": true}');
    } else if (action == '$prefix:pushData') {
      final id = params['id'] as String?;
      final channel = params['channel'] as String?;
      final data = params['data'] as Map<String, dynamic>?;
      if (id == null || channel == null) {
        return Future.value(
          jsonEncode({
            'error': AppLocalizations.of(context).missingRequiredParams('id and channel'),
            'expected': {
              'id': AppLocalizations.of(context).dashboardPageIdHelp,
              'channel': AppLocalizations.of(context).pushChannelNameHelp,
              'data': AppLocalizations.of(context).optionalPayloadObjectHelp,
            },
          }),
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          state?.pushDataToDashboard(resolveId(id), channel, data ?? {}));
      return Future.value('{"ok": true}');
    } else if (action == '$prefix:refreshPage' || action == 'reload') {
      WidgetsBinding.instance.addPostFrameCallback((_) => state?.refreshPage());
      return Future.value('{"ok": true, "action": "refreshPage"}');
    }
    return null;
  }

  static String _titleFromPath(String path) {
    final name = path.split('/').last;
    // Remove extension
    final base = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    // Convert snake_case/kebab-case to readable title
    return base
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  static String? _dashboardFileParam(Map<String, dynamic> params) {
    final file = params['file'];
    if (file is String && file.isNotEmpty) return file;
    final path = params['path'];
    if (path is String && path.isNotEmpty) return path;
    return null;
  }
}
