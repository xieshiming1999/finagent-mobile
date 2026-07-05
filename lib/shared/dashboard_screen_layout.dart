part of 'dashboard_screen.dart';

Widget buildDashboardWebView(DashboardScreenState state) {
  final mainStack = Stack(
    children: [
      RepaintBoundary(
        key: state._repaintBoundaryKey,
        child: WebViewWidget(controller: state._controller!),
      ),
      if (state._searchVisible && state._searchController != null)
        Positioned.fill(
          child: RepaintBoundary(
            key: state._searchRepaintBoundaryKey,
            child: WebViewWidget(controller: state._searchController!),
          ),
        ),
    ],
  );

  return Stack(
    children: [
      Offstage(offstage: state._viewingBgId != null, child: mainStack),
      if (state._viewingBgId != null &&
          state._bgControllers.containsKey(state._viewingBgId))
        Positioned.fill(
          child: RepaintBoundary(
            key: state._bgRepaintKeys[state._viewingBgId]!,
            child: WebViewWidget(
              controller: state._bgControllers[state._viewingBgId]!,
            ),
          ),
        ),
      for (final entry in state._bgControllers.entries)
        if (entry.key != state._viewingBgId)
          Offstage(
            offstage: true,
            child: SizedBox(
              width: 1,
              height: 1,
              child: WebViewWidget(controller: entry.value),
            ),
          ),
    ],
  );
}

Widget buildDashboardAgentTab(
  DashboardScreenState state,
  BuildContext context,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context);
  return Column(
    children: [
      if (state.widget.chatHeader != null) state.widget.chatHeader!,
      Expanded(
        child: state.widget.items.isEmpty
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 28,
                      color: colorScheme.primary.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      l10n.waitingForInput,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              )
            : DashboardChatList(
                items: state.widget.items,
                onSelectOption: state.widget.onSelectOption,
                collectedAnswers: state.widget.collectedAnswers,
                hasPendingQuestions: state.widget.hasPendingQuestions,
              ),
      ),
      DashboardStatusBar(
        agentStatus: state.widget.agentStatus,
        turnSummary: state.widget.turnSummary,
        contextInfo: state.widget.contextInfo,
      ),
      TaskListWidget(tasks: state.widget.tasks),
    ],
  );
}

Widget buildDashboardWatchlistTab(DashboardScreenState state) {
  if (state.widget.watchlistStore == null) {
    return Builder(
      builder: (context) => Center(
        child: Text(AppLocalizations.of(context).watchlistNotAvailable),
      ),
    );
  }
  return WatchlistPanel(
    store: state.widget.watchlistStore!,
    onAnalyze: state.widget.onWatchlistAnalyze,
  );
}

Widget buildDashboardEventTab(
  DashboardScreenState state,
  BuildContext context,
) {
  final eventItems = state.widget.eventItems;
  final l10n = AppLocalizations.of(context);
  if (eventItems == null) {
    return Center(
      child: Text(
        l10n.noEventAgent,
        style: const TextStyle(color: Colors.grey),
      ),
    );
  }

  final colorScheme = Theme.of(context).colorScheme;
  final amberAccent = Colors.amber.shade700;
  return ValueListenableBuilder<int>(
    valueListenable: state.widget.eventPanelNotifier ?? ValueNotifier<int>(0),
    builder: (context, _, child) => Column(
      children: [
        Expanded(
          child: eventItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.bolt,
                        size: 28,
                        color: amberAccent.withValues(alpha: 0.3),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.eventAgentIdle,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: eventItems.length,
                  itemBuilder: (_, index) => EventChatBubble(
                    item: eventItems[index],
                    amberAccent: amberAccent,
                  ),
                ),
        ),
        if (state.widget.eventStatus != null ||
            state.widget.eventSummary != null)
          EventStatusRow(
            status: state.widget.eventStatus,
            summary: state.widget.eventSummary,
            queueLength: state.widget.eventQueueLength,
            amberAccent: amberAccent,
          ),
      ],
    ),
  );
}

Widget buildDashboardStrategyTab(
  DashboardScreenState state,
  BuildContext context,
) {
  final handler = state.widget.onStrategyAction;
  if (handler == null) {
    return Center(
      child: Text(AppLocalizations.of(context).strategyLibraryNotAvailable),
    );
  }
  return StrategyLibraryPanel(
    basePath: state.widget.basePath,
    onAction: handler,
    onCreateStrategy: state.widget.onCreateStrategy,
  );
}

Widget buildDashboardPanelTab(
  DashboardScreenState state,
  BuildContext context,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context);
  final monitorCount = state.widget.monitorStore?.monitors.length ?? 0;
  final totalCount = state._dashboardItems.length + monitorCount;
  return Column(
    children: [
      Expanded(
        child: state._buildPanel(fillSpace: true, alwaysExpanded: true),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Icon(
              Icons.dashboard_outlined,
              size: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(width: 4),
            Text(
              l10n.dashboardItemsSummary(
                totalCount,
                state._dashboardItems.length,
                monitorCount,
              ),
              style: TextStyle(
                fontSize: 10,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

Widget buildDashboardInputArea(DashboardScreenState state) {
  if (state._activeTabIndex == 0) {
    return DashboardInputBar(
      controller: state.widget.controller,
      focusNode: state.widget.focusNode,
      onSend: state.widget.onSend,
      hintText: state.widget.hintText,
      onCancel: state.widget.isLoading ? state.widget.onCancel : null,
      onBackground: state.widget.isLoading ? state.widget.onBackground : null,
    );
  }
  if (state._activeTabIndex == 2 && state.widget.eventController != null) {
    return DashboardInputBar(
      controller: state.widget.eventController!,
      focusNode: state.widget.eventFocusNode ?? FocusNode(),
      onSend: state.widget.onEventSend ?? () {},
      hintText: AppLocalizations.of(state.context).eventAgentInputHint,
      onCancel: state.widget.isEventRunning ? state.widget.onEventCancel : null,
    );
  }
  return const SizedBox.shrink();
}

Widget buildDashboardScreenBody(
  DashboardScreenState state,
  BuildContext context,
) {
  if (state._webViewMode == WebViewMode.hidden || state._controller == null) {
    return Column(
      children: [
        Expanded(child: buildDashboardTabViews(state)),
        buildDashboardInputArea(state),
      ],
    );
  }

  final webView = state._buildWebView();
  if (state._webViewMode == WebViewMode.fullscreen) {
    return webView;
  }

  final colorScheme = Theme.of(context).colorScheme;
  return LayoutBuilder(
    builder: (context, constraints) {
      final isLandscape = constraints.maxWidth > constraints.maxHeight;
      final maxDim = isLandscape ? constraints.maxWidth : constraints.maxHeight;
      final webSize = (maxDim * state._splitRatio).clamp(40.0, maxDim * 0.9);

      Widget divider() => GestureDetector(
        onVerticalDragUpdate: isLandscape
            ? null
            : (details) => state._updateState(() {
                state._splitRatio =
                    ((state._splitRatio * maxDim + details.delta.dy) / maxDim)
                        .clamp(0.1, 0.9);
              }),
        onVerticalDragEnd: isLandscape ? null : (_) => state._saveState(),
        onHorizontalDragUpdate: isLandscape
            ? (details) => state._updateState(() {
                state._splitRatio =
                    ((state._splitRatio * maxDim + details.delta.dx) / maxDim)
                        .clamp(0.1, 0.9);
              })
            : null,
        onHorizontalDragEnd: isLandscape ? (_) => state._saveState() : null,
        child: Container(
          width: isLandscape ? 16 : double.infinity,
          height: isLandscape ? double.infinity : 16,
          color: Colors.transparent,
          child: Center(
            child: Container(
              width: isLandscape ? 3 : 32,
              height: isLandscape ? 32 : 3,
              decoration: BoxDecoration(
                color: colorScheme.outline.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(1.5),
              ),
            ),
          ),
        ),
      );

      final bottomPane = Column(
        children: [
          Expanded(child: buildDashboardTabViews(state)),
          buildDashboardInputArea(state),
        ],
      );

      return isLandscape
          ? Row(
              children: [
                SizedBox(width: webSize, child: webView),
                divider(),
                Expanded(child: bottomPane),
              ],
            )
          : Column(
              children: [
                SizedBox(height: webSize, child: webView),
                divider(),
                Expanded(child: bottomPane),
              ],
            );
    },
  );
}

Widget buildDashboardTabViews(DashboardScreenState state) {
  return TabBarView(
    controller: state._tabController,
    children: [
      buildDashboardAgentTab(state, state.context),
      buildDashboardWatchlistTab(state),
      buildDashboardEventTab(state, state.context),
      buildDashboardStrategyTab(state, state.context),
      buildDashboardPanelTab(state, state.context),
    ],
  );
}
