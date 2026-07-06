part of 'finagent_screen.dart';

extension _BuildHelpersToolbar on _FinAgentScreenState {
  Widget _buildToolbar() {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? _buildVerticalToolbar() : _buildHorizontalToolbar();
  }

  Widget _buildHorizontalToolbar() {
    final ds = _dash;
    final scope = FeatureSwitchScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final activeTab = ds?.activeTabIndex ?? 0;

    Widget tabIcon(
      int index,
      IconData icon,
      IconData activeIcon, {
      bool hasBadge = false,
      Color? activeColor,
      bool isProcessing = false,
    }) {
      final selected = activeTab == index;
      final Color color;
      final IconData effectiveIcon;
      if (selected) {
        color = activeColor ?? cs.primary;
        effectiveIcon = activeIcon;
      } else if (isProcessing) {
        color = Colors.blue;
        effectiveIcon = activeIcon;
      } else {
        color = cs.onSurface.withValues(alpha: 0.5);
        effectiveIcon = icon;
      }
      final iconWidget = Icon(effectiveIcon, size: 20, color: color);
      return IconButton(
        icon: hasBadge ? Badge(smallSize: 6, child: iconWidget) : iconWidget,
        onPressed: () => ds?.tabController.animateTo(index),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: EdgeInsets.zero,
      );
    }

    return SizedBox(
      height: 40,
      child: Row(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, size: 18),
            tooltip: l10n.general,
            position: PopupMenuPosition.under,
            offset: const Offset(0, 8),
            onSelected: (value) {
              if (value == 'settings') scope?.onOpenSettings();
              if (value == 'history') _showHistoryPanel();
              if (value == 'session') _showSessionPanel();
              if (value == 'api_health') _showApiHealthPanel();
              if (value == 'import_report') _importReport();
              if (value == 'import_dashboard') _importHtml();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'import_report',
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf, size: 18),
                  title: Text(l10n.importFinancialReport),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import_dashboard',
                child: ListTile(
                  leading: const Icon(Icons.dashboard_customize, size: 18),
                  title: Text(l10n.importDashboard),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: const Icon(Icons.history, size: 18),
                  title: Text(l10n.history),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'session',
                child: ListTile(
                  leading: const Icon(Icons.restore, size: 18),
                  title: Text(l10n.session),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'api_health',
                child: ListTile(
                  leading: const Icon(Icons.monitor_heart, size: 18),
                  title: Text(l10n.apiHealth),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: const Icon(Icons.settings, size: 18),
                  title: Text(l10n.settings),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (ds != null) ...[
            tabIcon(0, Icons.chat_bubble_outline, Icons.chat_bubble),
            tabIcon(1, Icons.star_border, Icons.star),
            tabIcon(
              2,
              Icons.bolt_outlined,
              Icons.bolt,
              hasBadge: _eventNeedsAttention,
              activeColor: Colors.amber.shade700,
              isProcessing: _eventStatus != null,
            ),
            tabIcon(3, Icons.account_tree_outlined, Icons.account_tree),
            tabIcon(4, Icons.dashboard_outlined, Icons.dashboard),
          ],
          const Spacer(),
          ..._dashboardToolbarButtons(ds),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildVerticalToolbar() {
    final ds = _dash;
    final scope = FeatureSwitchScope.of(context);
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final activeTab = ds?.activeTabIndex ?? 0;

    Widget tabIcon(
      int index,
      IconData icon,
      IconData activeIcon, {
      bool hasBadge = false,
      Color? activeColor,
      bool isProcessing = false,
    }) {
      final selected = activeTab == index;
      final Color color;
      final IconData effectiveIcon;
      if (selected) {
        color = activeColor ?? cs.primary;
        effectiveIcon = activeIcon;
      } else if (isProcessing) {
        color = Colors.blue;
        effectiveIcon = activeIcon;
      } else {
        color = cs.onSurface.withValues(alpha: 0.5);
        effectiveIcon = icon;
      }
      final iconWidget = Icon(effectiveIcon, size: 20, color: color);
      return IconButton(
        icon: hasBadge ? Badge(smallSize: 6, child: iconWidget) : iconWidget,
        onPressed: () => ds?.tabController.animateTo(index),
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
      );
    }

    return Container(
      width: 38,
      color: cs.surface,
      child: Column(
        children: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, size: 18),
            tooltip: l10n.general,
            position: PopupMenuPosition.under,
            offset: const Offset(38, -38),
            onSelected: (value) {
              if (value == 'settings') scope?.onOpenSettings();
              if (value == 'history') _showHistoryPanel();
              if (value == 'session') _showSessionPanel();
              if (value == 'api_health') _showApiHealthPanel();
              if (value == 'import_report') _importReport();
              if (value == 'import_dashboard') _importHtml();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'import_report',
                child: ListTile(
                  leading: const Icon(Icons.picture_as_pdf, size: 18),
                  title: Text(l10n.importFinancialReport),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'import_dashboard',
                child: ListTile(
                  leading: const Icon(Icons.dashboard_customize, size: 18),
                  title: Text(l10n.importDashboard),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'history',
                child: ListTile(
                  leading: const Icon(Icons.history, size: 18),
                  title: Text(l10n.history),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'session',
                child: ListTile(
                  leading: const Icon(Icons.restore, size: 18),
                  title: Text(l10n.session),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'api_health',
                child: ListTile(
                  leading: const Icon(Icons.monitor_heart, size: 18),
                  title: Text(l10n.apiHealth),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  leading: const Icon(Icons.settings, size: 18),
                  title: Text(l10n.settings),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
            padding: EdgeInsets.zero,
          ),
          const Divider(height: 1),
          tabIcon(0, Icons.chat_bubble_outline, Icons.chat_bubble),
          tabIcon(1, Icons.star_border, Icons.star),
          tabIcon(
            2,
            Icons.bolt_outlined,
            Icons.bolt,
            hasBadge: _eventNeedsAttention,
            activeColor: Colors.amber.shade700,
          ),
          tabIcon(3, Icons.account_tree_outlined, Icons.account_tree),
          tabIcon(4, Icons.dashboard_outlined, Icons.dashboard),
          const Spacer(),
          ..._verticalWebViewButtons(ds),
        ],
      ),
    );
  }

  List<Widget> _verticalWebViewButtons(DashboardScreenState? ds) {
    final l10n = AppLocalizations.of(context);
    if ((ds?.webViewMode ?? WebViewMode.hidden) == WebViewMode.hidden) {
      return [];
    }
    return [
      IconButton(
        icon: const Icon(Icons.refresh, size: 18),
        tooltip: l10n.refresh,
        onPressed: () => ds?.refreshPage(),
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
      ),
      IconButton(
        icon: Icon(
          ds?.webViewMode == WebViewMode.fullscreen
              ? Icons.fullscreen_exit
              : Icons.fullscreen,
          size: 18,
        ),
        tooltip: ds?.webViewMode == WebViewMode.fullscreen
            ? l10n.exitFullscreen
            : l10n.fullscreen,
        onPressed: () => _setState(() => ds?.toggleFullscreen()),
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
      ),
      IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: l10n.close,
        onPressed: () => _setState(() => ds?.closeWebView()),
        constraints: const BoxConstraints(minWidth: 38, minHeight: 38),
        padding: EdgeInsets.zero,
      ),
    ];
  }

  List<Widget> _dashboardToolbarButtons(DashboardScreenState? ds) {
    final l10n = AppLocalizations.of(context);
    return [
      if (widget.notificationStore.unreadCount > 0)
        IconButton(
          icon: Badge(
            label: Text(
              '${widget.notificationStore.unreadCount}',
              style: const TextStyle(fontSize: 9),
            ),
            child: const Icon(Icons.notifications_outlined, size: 18),
          ),
          onPressed: () async {
            await ds?.showNotificationCenter(context);
            if (mounted) _setState(() {});
          },
        ),
      if ((ds?.webViewMode ?? WebViewMode.hidden) != WebViewMode.hidden) ...[
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: l10n.refresh,
          onPressed: () => ds?.refreshPage(),
        ),
        IconButton(
          icon: Icon(
            ds?.webViewMode == WebViewMode.fullscreen
                ? Icons.fullscreen_exit
                : Icons.fullscreen,
            size: 18,
          ),
          tooltip: ds?.webViewMode == WebViewMode.fullscreen
              ? l10n.exitFullscreen
              : l10n.fullscreen,
          onPressed: () => _setState(() => ds?.toggleFullscreen()),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 18),
          tooltip: l10n.close,
          onPressed: () => _setState(() => ds?.closeWebView()),
        ),
      ],
    ];
  }
}
