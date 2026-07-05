part of 'dashboard_screen.dart';

void showDashboardMonitorDetail(DashboardScreenState state, String monitorId) {
  final monitorStore = state.widget.monitorStore;
  if (monitorStore == null) return;
  final monitor = monitorStore.get(monitorId);
  if (monitor == null) return;
  showModalBottomSheet(
    context: state.context,
    isScrollControlled: true,
    builder: (sheetContext) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.85,
      builder: (sheetContext, scrollController) => MonitorDetailSheet(
        monitor: monitor,
        scrollController: scrollController,
        onToggle: (enabled) {
          state.widget.onMonitorToggle?.call(monitorId, enabled);
          Navigator.pop(sheetContext);
        },
        onDelete: () {
          state.widget.onMonitorDelete?.call(monitorId);
          Navigator.pop(sheetContext);
        },
      ),
    ),
  );
}

void refreshDashboardItems(DashboardScreenState state) {
  final persisted = state._dashboardStore?.load() ?? [];
  persisted.removeWhere(
    (item) => item.filePath != null && !File(item.filePath!).existsSync(),
  );
  state._updateState(() => state._dashboardItems = persisted);
  state._dashboardStore?.save(persisted);
}

void addDashboardItem(DashboardScreenState state, DashboardItem item) {
  state._updateState(() {
    state._dashboardItems.removeWhere((entry) => entry.id == item.id);
    state._dashboardItems.add(item);
  });
  state._dashboardStore?.save(state._dashboardItems);
}

void removeDashboardItem(DashboardScreenState state, String id) {
  state.stopBackgroundTask(id);
  final item = state._dashboardItems
      .where((entry) => entry.id == id)
      .firstOrNull;
  if (item?.filePath != null) {
    try {
      File(item!.filePath!).deleteSync();
    } catch (_) {}
  }
  state._updateState(() {
    state._dashboardItems.removeWhere((entry) => entry.id == id);
    if (state._activeDashboard?.id == id) state._activeDashboard = null;
  });
  state._dashboardStore?.save(state._dashboardItems);
}

void selectDashboardItem(DashboardScreenState state, DashboardItem item) {
  final isSame = state._activeDashboard?.id == item.id;
  if (!isSame) {
    state._updateState(() {
      state._activeDashboard = item;
      state._dashboardPanelExpanded = false;
    });
    state.widget.onDashboardChanged?.call(item);
  }
  if (item.filePath != null) {
    final file = File(item.filePath!);
    if (file.existsSync()) {
      if (state._webViewMode == WebViewMode.hidden) state.showWebView();
      debugPrint(
        '[DashboardScreen] selectDashboard: loading ${item.filePath} (${file.lengthSync()} bytes)',
      );
      state._controller?.loadHtmlString(
        state._injectBridgeIntoHtml(file.readAsStringSync()),
        baseUrl: 'file://${file.parent.path}/',
      );
      captureDashboardThumbnail(state, item);
    }
  }
  state._saveState();
}

bool startDashboardBackgroundTask(
  DashboardScreenState state,
  DashboardItem item,
) {
  if (item.filePath == null || state._bgControllers.containsKey(item.id)) {
    return false;
  }
  if (state._bgControllers.length >= state.widget.maxBackgroundTasks) {
    return false;
  }
  final file = File(item.filePath!);
  if (!file.existsSync()) return false;

  final controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted);
  state.setDashboardWebViewBackgroundColor(controller, Colors.transparent);
  controller.setNavigationDelegate(
    NavigationDelegate(
      onPageFinished: (_) => state._injectBridgeAPI(controller),
    ),
  );
  controller.loadHtmlString(
    state._injectBridgeIntoHtml(file.readAsStringSync()),
    baseUrl: 'file://${file.parent.path}/',
  );
  state._registerBridge(controller, dashboardId: item.id);
  state._bgControllers[item.id] = controller;
  state._bgRepaintKeys[item.id] = GlobalKey();
  state._persistBackgroundTasks();
  state._updateState(() {});
  return true;
}

void stopDashboardBackgroundTask(DashboardScreenState state, String id) {
  final controller = state._bgControllers.remove(id);
  state._bgRepaintKeys.remove(id);
  controller?.loadRequest(Uri.parse('about:blank'));
  if (state._viewingBgId == id) state._viewingBgId = null;
  state._persistBackgroundTasks();
  state._updateState(() {});
}

void viewDashboardBackgroundTask(DashboardScreenState state, String id) {
  if (!state._bgControllers.containsKey(id)) return;
  state._updateState(() => state._viewingBgId = id);
}

void pushDataIntoDashboard(
  DashboardScreenState state,
  String dashboardId,
  String channel,
  Map<String, dynamic> data,
) {
  WebViewController? controller;
  if (state._activeDashboard?.id == dashboardId) {
    controller = state._controller;
  } else if (state._bgControllers.containsKey(dashboardId)) {
    controller = state._bgControllers[dashboardId];
  }
  if (controller == null) return;
  final json = jsonEncode(data).replaceAll('\\', '\\\\').replaceAll("'", "\\'");
  controller.runJavaScript(
    "window.__onPush__&&window.__onPush__('$channel',$json)",
  );
}

void initDashboardScreenState(DashboardScreenState state) {
  if (state._controller != null) return;
  state._initSearchController();
  state._dashboardStore ??= DashboardStore(
    storagePath:
        '${state.widget.basePath}/memory/.${state.widget.stateKey}_dashboard_items.json',
  );
  String? savedModeName;
  String? savedActiveId;
  final stateFile = File(
    '${state.widget.basePath}/memory/.${state.widget.stateKey}_ui_state.json',
  );
  if (stateFile.existsSync()) {
    try {
      final saved =
          jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
      state._splitRatio = (saved['splitRatio'] as num?)?.toDouble() ?? 0.5;
      state._dashboardPanelExpanded =
          saved['dashboardPanelExpanded'] as bool? ?? false;
      savedModeName = saved['webViewMode'] as String?;
      savedActiveId = saved['activeDashboardId'] as String?;
    } catch (_) {}
  }
  state.refreshDashboards();
  state._initMainController();
  state._webViewMode = savedModeName != null
      ? WebViewMode.values.byName(savedModeName)
      : WebViewMode.hidden;
  if (savedActiveId != null && state._webViewMode != WebViewMode.hidden) {
    final item = state._dashboardItems
        .where((entry) => entry.id == savedActiveId)
        .firstOrNull;
    if (item != null) {
      state.selectDashboard(item);
    } else {
      state._webViewMode = WebViewMode.hidden;
    }
  }
  state._startHeartbeat();
  state._restoreBackgroundTasks();
  state.widget.monitorStore?.onChanged = () {
    if (state.mounted) state._updateState(() {});
  };
  state.widget.notificationStore?.onChanged = () {
    if (state.mounted) state._updateState(() {});
  };
  state.widget.watchlistStore?.onChanged = () {
    if (state.mounted) state._updateState(() {});
  };
}

String dashboardThumbnailDir(DashboardScreenState state) {
  final dir = '${state.widget.basePath}/memory/.dashboard_thumbnails';
  Directory(dir).createSync(recursive: true);
  return dir;
}

String dashboardThumbnailPath(DashboardScreenState state, String dashboardId) {
  final hash = dashboardId.hashCode.toUnsigned(32).toRadixString(16);
  return '${dashboardThumbnailDir(state)}/$hash.png';
}

void captureDashboardThumbnail(DashboardScreenState state, DashboardItem item) {
  Future.delayed(const Duration(seconds: 2), () {
    if (!state.mounted) return;
    try {
      final boundary =
          state._repaintBoundaryKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null || !boundary.hasSize) return;
      boundary.toImage(pixelRatio: 0.15).then((image) {
        image.toByteData(format: ui.ImageByteFormat.png).then((byteData) {
          if (byteData == null) return;
          File(
            dashboardThumbnailPath(state, item.id),
          ).writeAsBytesSync(byteData.buffer.asUint8List());
        });
      });
    } catch (_) {}
  });
}

DashboardPanel buildDashboardPanelWidget(
  DashboardScreenState state, {
  bool fillSpace = false,
  bool alwaysExpanded = false,
}) {
  final allItems = <DashboardItem>[...state._dashboardItems];
  final monitorStore = state.widget.monitorStore;
  if (monitorStore != null) {
    for (final monitor in monitorStore.monitors) {
      allItems.add(
        DashboardItem(
          id: monitor.id,
          title: monitor.name,
          type: DashboardItemType.monitor,
          monitorData: {
            if (monitor.lastResult != null) ...monitor.lastResult!,
            'enabled': monitor.enabled,
            'hasError': monitor.lastError != null,
            'displayType': monitor.displayType,
            if (monitor.lastRunTime != null)
              'lastRunTime': monitor.lastRunTime!.toIso8601String(),
          },
        ),
      );
    }
  }

  return DashboardPanel(
    items: allItems,
    activeItem: state._activeDashboard,
    expanded: alwaysExpanded || state._dashboardPanelExpanded,
    fillSpace: fillSpace,
    backgroundRunning: state._bgControllers.keys.toSet(),
    viewingBgId: state._viewingBgId,
    maxBackgroundTasks: state.widget.maxBackgroundTasks,
    thumbnailPathResolver: state.getThumbnailPath,
    onToggle: alwaysExpanded ? null : () => state.toggleDashboardPanel(),
    onFullscreen: alwaysExpanded
        ? null
        : (state._webViewMode != WebViewMode.hidden
              ? state.toggleFullscreen
              : null),
    onHideWebView: alwaysExpanded
        ? null
        : (state._webViewMode != WebViewMode.hidden ? state.hideWebView : null),
    onSelect: state.selectDashboard,
    onImport: () => state.widget.onImportHtml?.call(),
    onExport: (item) => state.widget.onExportDashboard?.call(item),
    onDelete: (item) {
      if (item.type == DashboardItemType.monitor) {
        state.widget.onMonitorDelete?.call(item.id);
      } else {
        state.removeDashboard(item.id);
      }
    },
    onReorder: (oldIndex, newIndex) {
      if (oldIndex >= state._dashboardItems.length ||
          newIndex > state._dashboardItems.length) {
        return;
      }
      state._updateState(() {
        if (newIndex > oldIndex) newIndex--;
        final item = state._dashboardItems.removeAt(oldIndex);
        state._dashboardItems.insert(newIndex, item);
      });
      state._dashboardStore?.save(state._dashboardItems);
    },
    onMonitorToggle: state.widget.onMonitorToggle,
    onMonitorTap: state._showMonitorDetail,
    onStartBackground: (item) {
      state.startBackgroundTask(item);
      state.widget.onStartBackground?.call(item);
    },
    onStopBackground: (item) {
      state.stopBackgroundTask(item.id);
      state.widget.onStopBackground?.call(item);
    },
    onViewBackground: (item) => state.viewBackgroundTask(item.id),
    onViewMain: state.viewMainWebView,
  );
}
