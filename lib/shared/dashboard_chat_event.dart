part of 'dashboard_chat.dart';

class EventAgentChatPanel extends StatelessWidget {
  final List<ChatItem> items;
  final ScrollController scrollController;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onSend;
  final AgentStatus? eventStatus;
  final String? eventSummary;
  final int queueLength;
  final List<PendingNotification> pendingNotifications;
  final VoidCallback? onClear;
  final VoidCallback? onCancel;
  final VoidCallback? onCompact;
  final VoidCallback? onClearQueue;
  final VoidCallback? onTogglePause;
  final bool isRunning;
  final bool isQueuePaused;
  final int droppedCount;

  const EventAgentChatPanel({
    super.key,
    required this.items,
    required this.scrollController,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.eventStatus,
    this.eventSummary,
    this.queueLength = 0,
    this.pendingNotifications = const [],
    this.onClear,
    this.onCancel,
    this.onCompact,
    this.onClearQueue,
    this.onTogglePause,
    this.isRunning = false,
    this.isQueuePaused = false,
    this.droppedCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final amberBg = isDark ? const Color(0xFF1A1400) : Colors.amber.shade50;
    final amberAccent = Colors.amber.shade700;

    return Container(
      decoration: BoxDecoration(
        color: amberBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: amberAccent.withValues(alpha: isDark ? 0.25 : 0.15),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(Icons.bolt, size: 16, color: amberAccent),
                const SizedBox(width: 4),
                Text(
                  AppLocalizations.of(context).eventLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: amberAccent,
                  ),
                ),
                const SizedBox(width: 4),
                _headerButton(
                  Icons.stop_circle_outlined,
                  l10n.cancel,
                  isRunning ? onCancel : null,
                  cs,
                ),
                _headerButton(Icons.compress, l10n.compact, onCompact, cs),
                _headerButton(
                  Icons.delete_outline,
                  l10n.clear,
                  items.isNotEmpty ? onClear : null,
                  cs,
                ),
                const Spacer(),
                Text(
                  '$queueLength',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Container(
                  width: 1,
                  height: 12,
                  color: cs.onSurface.withValues(alpha: 0.15),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                ),
                Text(
                  '$droppedCount',
                  style: TextStyle(
                    fontSize: 10,
                    color: droppedCount > 0
                        ? Colors.red.shade300
                        : cs.onSurface.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(width: 4),
                _headerButton(
                  isQueuePaused ? Icons.play_arrow : Icons.pause,
                  isQueuePaused
                      ? AppLocalizations.of(context).resume
                      : AppLocalizations.of(context).pause,
                  onTogglePause,
                  cs,
                ),
                _headerButton(
                  Icons.playlist_remove,
                  AppLocalizations.of(context).clearQueue,
                  queueLength > 0 ? onClearQueue : null,
                  cs,
                ),
              ],
            ),
          ),
          if (pendingNotifications.isNotEmpty)
            QueuePreview(
              notifications: pendingNotifications,
              amberAccent: amberAccent,
            ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.bolt,
                          size: 32,
                          color: amberAccent.withValues(alpha: 0.3),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context).eventAgentIdle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          AppLocalizations.of(context).eventPanelHelp,
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.2),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: scrollController,
                    padding: const EdgeInsets.all(8),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      return EventChatBubble(
                        item: items[i],
                        amberAccent: amberAccent,
                      );
                    },
                  ),
          ),
          EventStatusRow(
            status: eventStatus,
            summary: eventSummary,
            queueLength: queueLength,
            amberAccent: amberAccent,
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: AppLocalizations.of(context).eventAgentInputHint,
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: cs.onSurface.withValues(alpha: 0.3),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: amberAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(
                          color: amberAccent.withValues(alpha: 0.3),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: amberAccent),
                      ),
                    ),
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.send, size: 18),
                  onPressed: onSend,
                  color: amberAccent,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerButton(
    IconData icon,
    String tooltip,
    VoidCallback? onTap,
    ColorScheme cs,
  ) {
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: Icon(
            icon,
            size: 16,
            color: cs.onSurface.withValues(alpha: enabled ? 0.5 : 0.15),
          ),
        ),
      ),
    );
  }
}
