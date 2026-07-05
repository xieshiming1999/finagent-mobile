import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../agent/monitor.dart';
import 'i18n/app_localizations.dart';
import 'monitor_detail_sheet.dart';
import 'monitor_panel_cards.dart';
import 'monitor_panel_shared.dart';

/// Panel displaying all active monitors as native Flutter widgets.
/// Renders based on Monitor.lastResult structure.
class MonitorPanel extends StatelessWidget {
  final MonitorStore store;
  final void Function(String monitorId)? onTap;
  final void Function(String monitorId, bool enabled)? onToggle;
  final void Function(String monitorId)? onDelete;

  const MonitorPanel({
    super.key,
    required this.store,
    this.onTap,
    this.onToggle,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final monitors = store.monitors;
    if (monitors.isEmpty) return const SizedBox.shrink();

    final allAlerts = <String>[];
    for (final monitor in monitors) {
      if (!monitor.enabled) continue;
      final alerts = monitor.lastResult?['alerts'];
      if (alerts is List) {
        for (final alert in alerts) {
          allAlerts.add('${monitor.name}: $alert');
        }
      }
    }

    final items = _buildPanelItems(monitors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.label != null) {
                return _GroupLabelChip(label: item.label!);
              }
              final monitor = item.monitor!;
              return GestureDetector(
                onTap: () {
                  if (monitor.hasUnreadAlert) {
                    store.clearAlert(monitor.id);
                  }
                  onTap?.call(monitor.id);
                  _showDetailSheet(context, monitor);
                },
                onLongPress: () => _showContextMenu(context, monitor),
                child: Opacity(
                  opacity: monitor.enabled ? 1.0 : 0.5,
                  child: _AlertBadge(
                    show: monitor.hasUnreadAlert,
                    child: _buildMonitorWidget(monitor),
                  ),
                ),
              );
            },
          ),
        ),
        if (allAlerts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: AlertListWidget(alerts: allAlerts),
          ),
      ],
    );
  }

  List<_PanelItem> _buildPanelItems(List<Monitor> monitors) {
    final ungrouped = monitors.where((monitor) => monitor.groupId == null).toList();
    final grouped = <String, List<Monitor>>{};
    for (final monitor in monitors.where((monitor) => monitor.groupId != null)) {
      (grouped[monitor.groupId!] ??= []).add(monitor);
    }

    final items = <_PanelItem>[];
    for (final monitor in ungrouped) {
      items.add(_PanelItem.monitor(monitor));
    }
    for (final entry in grouped.entries) {
      final label = entry.value.first.groupName ?? entry.key;
      items.add(_PanelItem.groupLabel(label));
      for (final monitor in entry.value) {
        items.add(_PanelItem.monitor(monitor));
      }
    }
    return items;
  }

  void _showContextMenu(BuildContext context, Monitor monitor) {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                monitor.enabled
                    ? Icons.stop_circle_outlined
                    : Icons.play_circle_outlined,
              ),
              title: Text(monitor.enabled ? l10n.stop : l10n.start),
              onTap: () {
                Navigator.pop(sheetContext);
                onToggle?.call(monitor.id, !monitor.enabled);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(sheetContext);
                onDelete?.call(monitor.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showDetailSheet(BuildContext context, Monitor monitor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.85,
        builder: (sheetContext, scrollController) => MonitorDetailSheet(
          monitor: monitor,
          scrollController: scrollController,
          onToggle: (enabled) {
            onToggle?.call(monitor.id, enabled);
            Navigator.pop(sheetContext);
          },
          onDelete: () {
            onDelete?.call(monitor.id);
            Navigator.pop(sheetContext);
          },
        ),
      ),
    );
  }

  Widget _buildMonitorWidget(Monitor monitor) {
    final result = monitor.lastResult;
    if (result == null) {
      return MonitorLoadingCard(name: monitor.name, error: monitor.lastError);
    }

    return switch (monitor.displayType) {
      'mini_chart' => MiniChartCard(
          label: result['label'] as String? ?? monitor.name,
          series: toMonitorDoubleList(result['series']),
          value: toMonitorDouble(result['value']),
        ),
      'status_row' => StatusRowCard(
          items: (result['items'] as List?)
                  ?.map((entry) => entry as Map<String, dynamic>)
                  .toList() ??
              [],
        ),
      'text' => TextCard(text: result['text']?.toString() ?? '--'),
      'carousel' => CarouselCard(
          items:
              (result['items'] as List?)?.map((entry) => entry.toString()).toList() ??
                  [],
        ),
      'watchlist' => WatchlistCard(
          title: result['title'] as String? ?? monitor.name,
          rows: (result['rows'] as List?)
                  ?.map((entry) => entry as Map<String, dynamic>)
                  .toList() ??
              [],
        ),
      _ => ValueCard(
          label: result['label'] as String? ?? monitor.name,
          value: formatMonitorValue(result['value']),
          change: toMonitorDouble(result['change']),
          unit: result['unit'] as String? ?? '',
          hasError: monitor.lastError != null,
        ),
    };
  }
}

/// Trigger haptic feedback for monitor alerts.
/// Called by UI layer from MonitorScheduler.onAlert callback.
void triggerMonitorAlertHaptic() {
  HapticFeedback.heavyImpact();
}

class _PanelItem {
  final Monitor? monitor;
  final String? label;

  _PanelItem.monitor(Monitor value)
      : monitor = value,
        label = null;

  _PanelItem.groupLabel(String value)
      : monitor = null,
        label = value;
}

class _GroupLabelChip extends StatelessWidget {
  final String label;

  const _GroupLabelChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w500,
            fontSize: 10,
          ),
        ),
      ),
    );
  }
}

class _AlertBadge extends StatelessWidget {
  final bool show;
  final Widget child;

  const _AlertBadge({required this.show, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          top: -4,
          right: -4,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: Colors.red,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 1.5,
              ),
            ),
            child: const Center(
              child: Text(
                '!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
