part of 'finagent_screen.dart';

extension _BuildHelpersSessions on _FinAgentScreenState {
  void _showHistoryPanel() {
    final l10n = AppLocalizations.of(context);
    final files = widget.agent.sessionManager.listHistoryFiles();

    if (files.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noHistoryYet)));
      return;
    }

    _setState(() => _historyPanelVisible = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? files
                : files
                      .where(
                        (file) =>
                            file.source.toLowerCase().contains(q) ||
                            _formatHistoryDate(
                              file.date,
                            ).toLowerCase().contains(q) ||
                            (file.preview ?? '').toLowerCase().contains(q),
                      )
                      .toList();
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.58,
              maxChildSize: 0.9,
              builder: (ctx, scrollCtrl) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.history,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: l10n.searchHistory,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text(l10n.noResults))
                        : ListView.builder(
                            controller: scrollCtrl,
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final file = filtered[i];
                              return ListTile(
                                title: Text(
                                  '${_formatHistoryDate(file.date)} · ${file.source}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                                subtitle: file.preview == null
                                    ? null
                                    : Text(
                                        file.preview!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                trailing: const Icon(
                                  Icons.chevron_right,
                                  size: 18,
                                ),
                                dense: true,
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _loadHistoryFile(file.filePath);
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) _setState(() => _historyPanelVisible = false);
    });
  }

  void _showSessionPanel() {
    final l10n = AppLocalizations.of(context);
    final sessions = widget.agent.sessionManager.listHistory();

    if (sessions.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.noSessionsToResume)));
      return;
    }

    _setState(() => _sessionPanelVisible = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        var selected = sessions.first;
        var preview = _loadChatItemsFromJsonl(selected.filePath);
        var collapsed = false;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final q = query.trim().toLowerCase();
            final filtered = q.isEmpty
                ? sessions
                : sessions
                      .where(
                        (session) =>
                            [
                              session.title,
                              session.firstPrompt,
                              session.filePath.split('/').last,
                              _formatHistoryDate(session.createdAt),
                            ].any(
                              (value) =>
                                  (value ?? '').toLowerCase().contains(q),
                            ),
                      )
                      .toList();
            final stats = _chatStats(preview);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.72,
              maxChildSize: 0.95,
              builder: (ctx, scrollCtrl) => Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.session,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      l10n.resumeArchivesCurrent,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 18),
                        hintText: l10n.searchSessions,
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  SizedBox(
                    height: 168,
                    child: filtered.isEmpty
                        ? Center(child: Text(l10n.noResults))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (_, i) {
                              final session = filtered[i];
                              final isSelected =
                                  session.filePath == selected.filePath;
                              return ListTile(
                                selected: isSelected,
                                title: Text(
                                  _sessionTitle(
                                    session.filePath,
                                    title: session.title,
                                    firstPrompt: session.firstPrompt,
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  _formatHistoryDate(session.createdAt),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: TextButton.icon(
                                  icon: const Icon(Icons.play_arrow, size: 16),
                                  label: Text(l10n.resume),
                                  onPressed: () {
                                    Navigator.pop(ctx);
                                    _resumeSession(session.filePath);
                                  },
                                ),
                                dense: true,
                                onTap: () => setSheetState(() {
                                  selected = session;
                                  preview = _loadChatItemsFromJsonl(
                                    session.filePath,
                                  );
                                  collapsed = false;
                                }),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(12),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.sessionPreview,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (preview.isNotEmpty)
                              TextButton.icon(
                                onPressed: () =>
                                    setSheetState(() => collapsed = !collapsed),
                                icon: Icon(
                                  collapsed
                                      ? Icons.expand_more
                                      : Icons.expand_less,
                                  size: 16,
                                ),
                                label: Text(
                                  collapsed ? l10n.expand : l10n.collapse,
                                ),
                              ),
                          ],
                        ),
                        Text(
                          l10n.readOnlyPreview,
                          style: TextStyle(
                            fontSize: 10,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _previewMetric(
                              context,
                              l10n.userMessages,
                              stats.user,
                            ),
                            _previewMetric(
                              context,
                              l10n.assistantMessages,
                              stats.assistant,
                            ),
                            _previewMetric(
                              context,
                              l10n.toolMessages,
                              stats.tool,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (preview.isEmpty)
                          Text(
                            l10n.noSessionPreview,
                            style: const TextStyle(fontSize: 12),
                          )
                        else if (!collapsed)
                          ...preview
                              .take(80)
                              .map((item) => _previewBubble(context, item)),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      if (mounted) _setState(() => _sessionPanelVisible = false);
    });
  }

  void _resumeSession(String filePath) {
    _setState(() {
      _items.clear();
      _isLoading = true;
    });
    _listenToStream(widget.agent.run('/resume $filePath'));
  }

  void _loadHistoryFile(String filePath) {
    _showHistoryViewer(filePath);
  }

  void _showHistoryViewer(String filePath) {
    final items = _loadChatItemsFromJsonl(filePath);
    final name = filePath.split('/').last.replaceAll('.jsonl', '');
    final l10n = AppLocalizations.of(context);
    var collapsed = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final stats = _chatStats(items);
          return DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.68,
            maxChildSize: 0.92,
            builder: (ctx, scrollCtrl) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (items.isNotEmpty)
                        TextButton.icon(
                          onPressed: () =>
                              setSheetState(() => collapsed = !collapsed),
                          icon: Icon(
                            collapsed ? Icons.expand_more : Icons.expand_less,
                            size: 16,
                          ),
                          label: Text(collapsed ? l10n.expand : l10n.collapse),
                        ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 20),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _previewMetric(context, l10n.userMessages, stats.user),
                      _previewMetric(
                        context,
                        l10n.assistantMessages,
                        stats.assistant,
                      ),
                      _previewMetric(context, l10n.toolMessages, stats.tool),
                    ],
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? Center(child: Text(l10n.emptySession))
                      : collapsed
                      ? Center(child: Text(l10n.tapToExpand))
                      : ListView.builder(
                          controller: scrollCtrl,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: items.length,
                          itemBuilder: (_, i) =>
                              _previewBubble(context, items[i]),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showToolConfirmDialog(
    String toolName,
    Map<String, dynamic> input,
    Completer<ToolConfirmResult> completer,
  ) {
    final summary = _summarizeToolInput(toolName, input);
    _setState(() {
      _items.add(
        ChatItem(
          role: 'confirm',
          content: AppLocalizations.of(
            context,
          ).toolRequiresConfirmation(toolName, summary),
          metadata: {'toolName': toolName, 'completer': completer},
        ),
      );
    });
  }

  void _showSessionPicker(
    String prompt,
    List<SessionSummary> sessions,
    Completer<String?> completer,
  ) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(padding: const EdgeInsets.all(16), child: Text(prompt)),
            for (final s in sessions)
              ListTile(
                title: Text(s.title ?? s.id),
                subtitle: Text(s.createdAt.toString().substring(0, 10)),
                onTap: () {
                  Navigator.pop(ctx);
                  completer.complete(s.filePath);
                },
              ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                completer.complete(null);
              },
              child: Text(l10n.cancel),
            ),
          ],
        ),
      ),
    );
  }

  String _summarizeToolInput(String toolName, Map<String, dynamic> input) {
    return summarizeToolInput(toolName, input);
  }

  String _formatHistoryDate(DateTime date) {
    final local = date.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
