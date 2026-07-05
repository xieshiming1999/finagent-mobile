import 'package:flutter/material.dart';
import '../agent/monitor.dart';
import 'i18n/app_localizations.dart';
import 'monitor_panel_shared.dart';
class MonitorDetailSheet extends StatelessWidget {
  final Monitor monitor;
  final ScrollController scrollController;
  final void Function(bool enabled) onToggle;
  final VoidCallback onDelete;
  const MonitorDetailSheet({
    super.key,
    required this.monitor,
    required this.scrollController,
    required this.onToggle,
    required this.onDelete,
  });
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final result = monitor.lastResult;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(monitor.name, style: theme.textTheme.titleLarge),
                  if (monitor.groupName != null)
                    Text(
                      monitor.groupName!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                ],
              ),
            ),
            _StatusChip(monitor: monitor),
          ],
        ),
        if (monitor.userPrompt != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.format_quote,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    monitor.userPrompt!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (monitor.description != null) ...[
          const SizedBox(height: 8),
          Text(
            monitor.description!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 4),
        Text(
          '${l10n.updateEveryMinutes} ${monitor.interval.inMinutes} ${l10n.minutesUnit} | ${monitor.displayType}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (monitor.lastRunTime != null)
          Text(
            '${l10n.lastUpdated}: ${monitor.lastRunTime!.toIso8601String().substring(11, 19)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const Divider(height: 24),
        Text(l10n.latestResult, style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        if (result != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildResultView(context, theme, result),
          )
        else if (monitor.lastError != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              monitor.lastError!,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          )
        else
          Text(l10n.noDataYet),
        if (monitor.condition != null && monitor.condition!.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.alertConditions, style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.notifications_active,
                  size: 14,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    monitor.condition!,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (monitor.alertMessage != null && monitor.alertMessage!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    monitor.alertMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 16),
        _CollapsibleScript(script: monitor.script),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => onToggle(!monitor.enabled),
                icon: Icon(
                  monitor.enabled
                      ? Icons.stop_circle_outlined
                      : Icons.play_circle_outlined,
                ),
                label: Text(monitor.enabled ? l10n.stop : l10n.start),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                label: Text(l10n.delete, style: const TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResultView(BuildContext context, ThemeData theme, Map<String, dynamic> result) {
    if (result['rows'] is List) {
      return _buildWatchlistTable(context, theme, result);
    }

    final entries = result.entries.where((entry) => entry.key != 'alerts').toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 80,
                  child: Text(
                    entry.key,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    entry.value is List
                        ? '[${(entry.value as List).length} ${AppLocalizations.of(context).itemsSuffix}]'
                        : entry.value.toString(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (result['alerts'] is List && (result['alerts'] as List).isNotEmpty) ...[
          const SizedBox(height: 8),
          ...((result['alerts'] as List).map((alert) => Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 14,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    alert.toString(),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ],
              ))),
        ],
      ],
    );
  }

  Widget _buildWatchlistTable(BuildContext context, ThemeData theme, Map<String, dynamic> result) {
    final l10n = AppLocalizations.of(context);
    final rows =
        (result['rows'] as List).map((entry) => entry as Map<String, dynamic>).toList();
    final alerts = result['alerts'] as List? ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  l10n.name,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  l10n.price,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  l10n.changePct,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final row in rows) _buildWatchlistRow(theme, row),
        if (alerts.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final alert in alerts)
            Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 14,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    alert.toString(),
                    style: TextStyle(
                      color: theme.colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ],
    );
  }

  Widget _buildWatchlistRow(ThemeData theme, Map<String, dynamic> row) {
    final change = toMonitorDouble(row['change']) ?? 0;
    final color = change > 0
        ? Colors.red
        : change < 0
            ? Colors.green
            : theme.colorScheme.onSurface;
    final signal = row['signal']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Row(
              children: [
                if (signal.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      signal == 'up'
                          ? Icons.arrow_upward
                          : signal == 'down'
                              ? Icons.arrow_downward
                              : Icons.error_outline,
                      size: 12,
                      color: signal == 'up'
                          ? Colors.red
                          : signal == 'down'
                              ? Colors.green
                              : theme.colorScheme.error,
                    ),
                  ),
                Expanded(
                  child: Text(
                    row['name']?.toString() ?? '',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              formatMonitorValue(row['price']),
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${change > 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final Monitor monitor;

  const _StatusChip({required this.monitor});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final (label, color) = monitor.enabled
        ? monitor.lastError != null
            ? (l10n.statusError, Colors.red)
            : (l10n.statusRunning, Colors.green)
        : (l10n.statusStopped, Colors.grey);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _CollapsibleScript extends StatefulWidget {
  final String script;

  const _CollapsibleScript({required this.script});

  @override
  State<_CollapsibleScript> createState() => _CollapsibleScriptState();
}

class _CollapsibleScriptState extends State<_CollapsibleScript> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Row(
            children: [
              Text(AppLocalizations.of(context).script, style: theme.textTheme.titleSmall),
              const SizedBox(width: 4),
              Icon(
                _expanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
        if (_expanded) ...[
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              widget.script,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ],
    );
  }
}
