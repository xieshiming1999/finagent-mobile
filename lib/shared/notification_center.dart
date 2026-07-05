import 'package:flutter/material.dart';

import '../agent/ui_notification.dart';
import 'i18n/app_localizations.dart';

/// Notification center panel — shows alert/notify items with unread badge.
class NotificationCenterSheet extends StatelessWidget {
  final UINotificationStore store;
  final VoidCallback? onClose;

  const NotificationCenterSheet({
    super.key,
    required this.store,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final items = store.items;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Row(
            children: [
              Text(l10n.notificationCenter, style: theme.textTheme.titleMedium),
              if (store.unreadCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.error,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${store.unreadCount}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
              const Spacer(),
              if (store.unreadCount > 0)
                TextButton(
                  onPressed: () => store.markAllRead(),
                  child: Text(l10n.markAllRead, style: const TextStyle(fontSize: 12)),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: onClose ?? () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // List
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.all(32),
            child: Text(l10n.noNotifications, style: const TextStyle(color: Colors.grey)),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final n = items[index];
                return _NotificationTile(
                  notification: n,
                  onTap: () => store.markRead(n.id),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _NotificationTile extends StatelessWidget {
  final UINotification notification;
  final VoidCallback onTap;

  const _NotificationTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final n = notification;
    final isAlert = n.severity == NotificationSeverity.alert;

    return ListTile(
      dense: true,
      leading: Icon(
        isAlert ? Icons.warning_amber_rounded : Icons.info_outline,
        color: isAlert ? theme.colorScheme.error : theme.colorScheme.primary,
        size: 20,
      ),
      title: Text(
        n.title,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
        ),
      ),
      subtitle: Text(
        n.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _formatTime(l10n, n.timestamp),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (!n.isRead)
            Container(
              margin: const EdgeInsets.only(top: 4),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: theme.colorScheme.error,
                shape: BoxShape.circle,
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  String _formatTime(AppLocalizations l10n, DateTime t) {
    final now = DateTime.now();
    final diff = now.difference(t);
    if (diff.inMinutes < 1) return l10n.justNow;
    if (diff.inMinutes < 60) return '${diff.inMinutes}${l10n.minutesAgo}';
    if (diff.inHours < 24) return '${diff.inHours}${l10n.hoursAgo}';
    return '${t.month}/${t.day} ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// Badge icon button for toolbar — shows unread count.
class NotificationBadgeButton extends StatelessWidget {
  final UINotificationStore store;
  final VoidCallback onTap;

  const NotificationBadgeButton({
    super.key,
    required this.store,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final count = store.unreadCount;
    return IconButton(
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text('$count', style: const TextStyle(fontSize: 10)),
        child: const Icon(Icons.notifications_outlined, size: 22),
      ),
      onPressed: onTap,
      tooltip: AppLocalizations.of(context).notificationCenter,
    );
  }
}
