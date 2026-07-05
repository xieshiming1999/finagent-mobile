import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../agent/agent_status.dart';
import '../agent/bridge/bridge_js.dart';
import '../agent/monitor.dart';
import '../agent/notification_queue.dart';
import '../agent/ui_notification.dart';
import '../agent/watchlist.dart';
import '../features/finance/chat_models.dart';
import 'api_config.dart';
import 'dashboard_chat.dart';
import 'dashboard_panel.dart';
import 'dashboard_panel_models.dart';
import 'i18n/app_localizations.dart';
import 'monitor_detail_sheet.dart';
import 'notification_center.dart';
import 'strategy_library_panel.dart';
import 'strategy_library_model.dart';
import 'task_list_widget.dart';
import 'watchlist_panel.dart';

part 'dashboard_screen_bridge.dart';
part 'dashboard_screen_dashboards.dart';
part 'dashboard_screen_layout.dart';

enum WebViewMode { hidden, split, fullscreen }

class DashboardScreen extends StatefulWidget {
  final List<ChatItem> items;
  final bool isLoading;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final AgentStatus? agentStatus;
  final String? turnSummary;
  final String? contextInfo;
  final List<Map<String, dynamic>> tasks;
  final String basePath;
  final String stateKey;
  final String hintText;
  final int maxBackgroundTasks;
  final VoidCallback? onCancel;
  final VoidCallback? onCompact;
  final VoidCallback? onClear;
  final VoidCallback? onBackground;
  final Future<String> Function(String message)? onBridgeMessage;
  final VoidCallback? onImportHtml;
  final ValueChanged<DashboardItem>? onExportDashboard;
  final ValueChanged<DashboardItem>? onStartBackground;
  final ValueChanged<DashboardItem>? onStopBackground;
  final void Function(DashboardItem?)? onDashboardChanged;
  final Widget? chatHeader;
  final MonitorStore? monitorStore;
  final WatchlistStore? watchlistStore;
  final void Function(String symbol)? onWatchlistAnalyze;
  final void Function(String action, StrategyLibraryItem item)?
  onStrategyAction;
  final VoidCallback? onCreateStrategy;
  final void Function(String monitorId, bool enabled)? onMonitorToggle;
  final void Function(String monitorId)? onMonitorDelete;
  final UINotificationStore? notificationStore;

  // Event Agent params (all optional for backward compatibility)
  final List<ChatItem>? eventItems;
  final TextEditingController? eventController;
  final FocusNode? eventFocusNode;
  final VoidCallback? onEventSend;
  final AgentStatus? eventStatus;
  final String? eventSummary;
  final int eventQueueLength;
  final List<PendingNotification> eventPendingNotifications;
  final bool isEventRunning;
  final bool isEventQueuePaused;
  final int eventDroppedCount;
  final bool eventNeedsAttention;
  final VoidCallback? onEventCancel;
  final VoidCallback? onEventCompact;
  final VoidCallback? onEventClear;
  final VoidCallback? onEventClearQueue;
  final VoidCallback? onEventTogglePause;
  final ValueNotifier<int>? eventPanelNotifier;

  // AskUserQuestion support
  final void Function(String questionText, String optionLabel)? onSelectOption;
  final Map<String, String> collectedAnswers;
  final bool hasPendingQuestions;

  const DashboardScreen({
    super.key,
    required this.items,
    required this.isLoading,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.agentStatus,
    this.turnSummary,
    this.contextInfo,
    this.tasks = const [],
    required this.basePath,
    this.stateKey = 'dashboard',
    this.hintText = '',
    this.maxBackgroundTasks = 2,
    this.onCancel,
    this.onCompact,
    this.onClear,
    this.onBackground,
    this.onBridgeMessage,
    this.onImportHtml,
    this.onExportDashboard,
    this.onStartBackground,
    this.onStopBackground,
    this.onDashboardChanged,
    this.chatHeader,
    this.monitorStore,
    this.watchlistStore,
    this.onWatchlistAnalyze,
    this.onStrategyAction,
    this.onCreateStrategy,
    this.onMonitorToggle,
    this.onMonitorDelete,
    this.notificationStore,
    this.eventItems,
    this.eventController,
    this.eventFocusNode,
    this.onEventSend,
    this.eventStatus,
    this.eventSummary,
    this.eventQueueLength = 0,
    this.eventPendingNotifications = const [],
    this.isEventRunning = false,
    this.isEventQueuePaused = false,
    this.eventDroppedCount = 0,
    this.eventNeedsAttention = false,
    this.onEventCancel,
    this.onEventCompact,
    this.onEventClear,
    this.onEventClearQueue,
    this.onEventTogglePause,
    this.eventPanelNotifier,
    this.onSelectOption,
    this.collectedAnswers = const {},
    this.hasPendingQuestions = false,
  });

  @override
  State<DashboardScreen> createState() => DashboardScreenState();
}

class DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  WebViewController? _controller;
  WebViewController? _searchController;
  bool _chatExpanded = false;
  bool _searchVisible = false;
  WebViewMode _webViewMode = WebViewMode.hidden;
  bool _chatCollapsed = false;
  final _repaintBoundaryKey = GlobalKey();
  final _searchRepaintBoundaryKey = GlobalKey();

  String _webviewUserAgent = ApiConfigStore.defaultBrowserUserAgent;
  double _splitRatio = 0.5;

  List<DashboardItem> _dashboardItems = [];
  DashboardItem? _activeDashboard;
  bool _dashboardPanelExpanded = false;
  DashboardStore? _dashboardStore;

  final Map<String, WebViewController> _bgControllers = {};
  final Map<String, GlobalKey> _bgRepaintKeys = {};
  String? _viewingBgId;
  Timer? _heartbeatTimer;

  late final TabController _tabController =
      TabController(length: 5, vsync: this)..addListener(() {
        if (_tabController.index != _activeTabIndex) {
          setState(() => _activeTabIndex = _tabController.index);
        }
      });
  int _activeTabIndex = 0;

  // ─── Public API ───

  List<DashboardItem> get dashboardItems => _dashboardItems;
  DashboardItem? get activeDashboard => _activeDashboard;
  bool get dashboardPanelExpanded => _dashboardPanelExpanded;
  String? get viewingBgId => _viewingBgId;
  int get bgTaskCount => _bgControllers.length;
  bool get isBgFull => _bgControllers.length >= widget.maxBackgroundTasks;
  Set<String> get bgTaskIds => _bgControllers.keys.toSet();

  WebViewController? get controller => _controller;
  WebViewController? get searchController => _searchController;
  GlobalKey get repaintBoundaryKey => _repaintBoundaryKey;
  GlobalKey get searchRepaintBoundaryKey => _searchRepaintBoundaryKey;
  bool get chatExpanded => _chatExpanded;
  bool get searchVisible => _searchVisible;
  double get splitRatio => _splitRatio;
  WebViewMode get webViewMode => _webViewMode;
  bool get chatCollapsed => _chatCollapsed;
  int get activeTabIndex => _activeTabIndex;
  TabController get tabController => _tabController;
  void _updateState(VoidCallback fn) => setState(fn);

  void switchToEventTab() => _tabController.animateTo(2);

  String? getThumbnailPath(String dashboardId) {
    final path = _thumbnailPath(dashboardId);
    return File(path).existsSync() ? path : null;
  }

  void toggleChat() => setState(() => _chatExpanded = !_chatExpanded);
  void toggleSearch() => setState(() => _searchVisible = !_searchVisible);
  void showSearch() => setState(() => _searchVisible = true);
  void hideSearch() => setState(() => _searchVisible = false);
  void showWebView() {
    setState(() => _webViewMode = WebViewMode.split);
    _saveState();
  }

  void hideWebView() {
    setState(() => _webViewMode = WebViewMode.hidden);
    _saveState();
  }

  void closeWebView() {
    _controller?.loadHtmlString('<html><body></body></html>');
    final hadDashboard = _activeDashboard != null;
    _activeDashboard = null;
    setState(() => _webViewMode = WebViewMode.hidden);
    _saveState();
    if (hadDashboard) widget.onDashboardChanged?.call(null);
  }

  /// Reload the active page from file (not just re-render cached HTML).
  void refreshPage() {
    final item = _activeDashboard;
    if (item == null || item.filePath == null) {
      _controller?.reload();
      return;
    }
    final file = File(item.filePath!);
    if (!file.existsSync()) {
      _controller?.reload();
      return;
    }
    _controller?.loadHtmlString(
      _injectBridgeIntoHtml(file.readAsStringSync()),
      baseUrl: 'file://${file.parent.path}/',
    );
  }

  void toggleFullscreen() {
    setState(() {
      _webViewMode = _webViewMode == WebViewMode.fullscreen
          ? WebViewMode.split
          : WebViewMode.fullscreen;
    });
    _saveState();
  }

  void toggleChatCollapse() => setState(() => _chatCollapsed = !_chatCollapsed);

  void toggleDashboardPanel({bool? expanded}) => setState(() {
    _dashboardPanelExpanded = expanded ?? !_dashboardPanelExpanded;
    _saveState();
  });

  Future<void> showNotificationCenter(BuildContext context) {
    final ns = widget.notificationStore;
    if (ns == null) return Future.value();
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (ctx, scrollController) => NotificationCenterSheet(
          store: ns,
          onClose: () => Navigator.pop(ctx),
        ),
      ),
    );
  }

  void _showMonitorDetail(String monitorId) =>
      showDashboardMonitorDetail(this, monitorId);
  void refreshDashboards() => refreshDashboardItems(this);
  void addDashboard(DashboardItem item) => addDashboardItem(this, item);
  void removeDashboard(String id) => removeDashboardItem(this, id);
  void selectDashboard(DashboardItem item) => selectDashboardItem(this, item);

  // ─── Background WebView Pool ───

  bool startBackgroundTask(DashboardItem item) =>
      startDashboardBackgroundTask(this, item);
  void stopBackgroundTask(String id) => stopDashboardBackgroundTask(this, id);
  void viewBackgroundTask(String id) => viewDashboardBackgroundTask(this, id);

  void viewMainWebView() => setState(() => _viewingBgId = null);

  // ─── Data Push ───

  void pushDataToDashboard(
    String dashboardId,
    String channel,
    Map<String, dynamic> data,
  ) => pushDataIntoDashboard(this, dashboardId, channel, data);

  // ─── Lifecycle ───

  void init() => initDashboardScreenState(this);

  @override
  void dispose() {
    _heartbeatTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadWebviewUserAgent();
    WidgetsBinding.instance.addPostFrameCallback((_) => init());
  }

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items.length > oldWidget.items.length && !_chatExpanded) {
      _chatExpanded = true;
    }
  }

  // ─── Private ───

  Future<void> _loadWebviewUserAgent() async {
    final store = ApiConfigStore();
    await store.load();
    if (!mounted) return;
    final userAgent = store.webviewUserAgent;
    if (userAgent == _webviewUserAgent) return;
    setState(() => _webviewUserAgent = userAgent);
    unawaited(_controller?.setUserAgent(userAgent));
    unawaited(_searchController?.setUserAgent(userAgent));
  }

  void _saveState() {
    try {
      final f = File(
        '${widget.basePath}/memory/.${widget.stateKey}_ui_state.json',
      );
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(
        jsonEncode({
          'splitRatio': _splitRatio,
          'dashboardPanelExpanded': _dashboardPanelExpanded,
          'webViewMode': _webViewMode.name,
          'activeDashboardId': _activeDashboard?.id,
        }),
      );
    } catch (_) {}
  }

  void _initMainController() {
    if (_controller != null) return;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_webviewUserAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) => _injectErrorHandler(_controller!),
          onWebResourceError: (err) => debugPrint(
            '[DashboardScreen] Error: ${err.errorCode} '
            '${err.description}',
          ),
        ),
      )
      ..loadRequest(Uri.parse('about:blank'));
    setDashboardWebViewBackgroundColor(_controller!, Colors.black);
    _registerBridge(_controller!, dashboardId: '_active');
  }

  void _initSearchController() {
    if (_searchController != null) return;
    _searchController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(_webviewUserAgent)
      ..loadRequest(Uri.parse('about:blank'));
    setDashboardWebViewBackgroundColor(_searchController!, Colors.black);
    _registerBridge(_searchController!);
  }

  void _registerBridge(WebViewController ctrl, {String? dashboardId}) =>
      registerDashboardBridge(this, ctrl, dashboardId: dashboardId);
  void _injectErrorHandler(WebViewController ctrl) =>
      injectDashboardErrorHandler(this, ctrl);
  void _injectBridgeAPI(WebViewController ctrl) =>
      injectDashboardBridgeApi(ctrl);
  String _injectBridgeIntoHtml(String html) =>
      injectBridgeIntoDashboardHtml(html);

  void setDashboardWebViewBackgroundColor(
    WebViewController controller,
    Color color,
  ) {
    if (Platform.isMacOS) return;
    unawaited(
      controller.setBackgroundColor(color).catchError((Object error) {
        debugPrint('[DashboardScreen] setBackgroundColor skipped: $error');
      }),
    );
  }

  // ─── Background Heartbeat ───

  void _startHeartbeat() => startDashboardHeartbeat(this);

  // ─── Background Task Persistence ───

  String get _bgPersistPath =>
      '${widget.basePath}/memory/.background_tasks_${widget.stateKey}.json';

  void _persistBackgroundTasks() => persistBackgroundTasks(this);
  void _restoreBackgroundTasks() => restoreBackgroundTasks(this);

  // ─── Thumbnail Capture ───

  String _thumbnailPath(String dashboardId) =>
      dashboardThumbnailPath(this, dashboardId);
  DashboardPanel _buildPanel({
    bool fillSpace = false,
    bool alwaysExpanded = false,
  }) => buildDashboardPanelWidget(
    this,
    fillSpace: fillSpace,
    alwaysExpanded: alwaysExpanded,
  );
  Widget _buildWebView() => buildDashboardWebView(this);

  // ─── Build ───

  @override
  Widget build(BuildContext context) => buildDashboardScreenBody(this, context);
}
