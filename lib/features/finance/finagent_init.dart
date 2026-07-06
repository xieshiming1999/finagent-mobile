part of 'finagent_screen.dart';

extension _FinAgentInit on _FinAgentScreenState {
  void _initEventAgent() {
    final basePath = widget.agent.toolContext.basePath;
    final locale = Localizations.localeOf(context);

    _eventRuntime = createAgentRuntime(
      basePath: basePath,
      serverUrl: '',
      featurePrompt: eventAgentPromptForLocale(
        'FinAgent',
        locale,
        finagentPromptForLocale(locale),
      ),
      featureId: 'fin_event',
      sessionsDir: '$basePath/sessions/_event',
      skipPermissions: true,
      batchDrainQueue: true,
      enableWatchlistRefresher: false,
      excludeTools: const {},
      agentRole: 'event',
      llmClient: widget.agent.client,
    );

    _eventRuntime.webViewTool.registerHandler('fin', _handleFinWebView);

    widget.environmentTool.uiStateProvider = () {
      final s = _dash;
      return {
        'webViewMode': s?.webViewMode.name ?? 'hidden',
        'activeDashboard': s?.activeDashboard?.title,
        'activeDashboardFile': s?.activeDashboard?.filePath,
        'dashboardCount': s?.dashboardItems.length ?? 0,
        'backgroundTasks': s?.bgTaskCount ?? 0,
        'viewingBackgroundId': s?.viewingBgId,
      };
    };

    widget.webViewTool.registerHandler('search', _handleSearchWebView);
    widget.webViewTool.registerHandler('fin', _handleFinWebView);

    _eventRuntime.uiQueryTool.handler = (key) async {
      final r = _handleDashboardQuery('fin', _dash, key);
      return r ??
          json.encode({'error': AppLocalizations.of(context).unknownKey(key)});
    };
    _eventRuntime.uiControlTool.handler = (action, params) async {
      final l10n = AppLocalizations.of(context);
      if (action.endsWith(':selectDashboard') || action.endsWith(':navigate')) {
        return '${l10n.errorPrefix}: ${l10n.eventAgentCannotUseAction(action)}';
      }
      final r = _handleDashboardControl('fin', _dash, action, params);
      return r != null ? await r : l10n.actionNotSupportedInEventAgent(action);
    };
    _eventRuntime.askUserQuestionTool.handler = _handleAskUser;

    widget.monitorScheduler.onAlert = (id, msg) => triggerMonitorAlertHaptic();

    final sharedStore = widget.notificationStore;
    _eventRuntime.agent.findTool<UINotifyTool>()?.store = sharedStore;
    _eventRuntime.monitorScheduler.notificationStore = sharedStore;

    widget.monitorScheduler.onAgentMessage = (name, message, data) {
      final l10n = AppLocalizations.of(context);
      final fullMsg = l10n.monitorNotificationPrompt(
        name,
        message,
        dataJson: data.isNotEmpty ? json.encode(data) : null,
      );
      log('EventAgent', 'Monitor event from $name');
      _eventRuntime.agent.notificationQueue.enqueue(
        PendingNotification(prompt: fullMsg, source: 'monitor'),
      );
    };
  }
}
