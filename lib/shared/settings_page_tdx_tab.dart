import 'package:flutter/material.dart';

import '../agent/data_fetcher/tdx_fetcher.dart';
import 'i18n/app_localizations.dart';

class TdxSettingsTab extends StatelessWidget {
  const TdxSettingsTab({
    super.key,
    required this.tdxProbing,
    required this.tdxServers,
    required this.tdxAddCtrl,
    required this.onProbe,
    required this.onAdd,
  });

  final bool tdxProbing;
  final List<TdxServerEntry> tdxServers;
  final TextEditingController tdxAddCtrl;
  final VoidCallback onProbe;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(
              l10n.tdxServers,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const Spacer(),
            if (tdxProbing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              FilledButton.icon(
                onPressed: onProbe,
                icon: const Icon(Icons.network_check, size: 16),
                label: Text(l10n.testConnection),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          _summaryText(context),
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 8),
        if (tdxServers.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              l10n.noTdxServers,
              style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
            ),
          )
        else
          ..._sortedServers().asMap().entries.map(
            (e) => _buildTdxServerRow(context, e.value, cs),
          ),
        const SizedBox(height: 12),
        Text(
          l10n.addServersHelp,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: tdxAddCtrl,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 16),
            label: Text(l10n.add),
          ),
        ),
      ],
    );
  }

  String _summaryText(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final reachable = tdxServers.where((s) => s.reachable == true).length;
    final unreachable = tdxServers.where((s) => s.reachable == false).length;
    final untested = tdxServers.where((s) => s.reachable == null).length;
    return l10n.tdxServerSummary(
      total: tdxServers.length,
      reachable: reachable,
      unreachable: unreachable,
      untested: untested,
    );
  }

  List<TdxServerEntry> _sortedServers() {
    final sorted = List<TdxServerEntry>.from(tdxServers);
    sorted.sort((a, b) {
      final aScore = a.reachable == true ? 0 : (a.reachable == null ? 1 : 2);
      final bScore = b.reachable == true ? 0 : (b.reachable == null ? 1 : 2);
      if (aScore != bScore) return aScore.compareTo(bScore);
      return (a.latency ?? 9999).compareTo(b.latency ?? 9999);
    });
    return sorted;
  }

  Widget _buildTdxServerRow(
    BuildContext context,
    TdxServerEntry server,
    ColorScheme cs,
  ) {
    final l10n = AppLocalizations.of(context);
    final statusColor = server.reachable == true
        ? Colors.green
        : server.reachable == false
        ? Colors.red
        : Colors.grey;
    final statusText = server.reachable == true
        ? '${server.latency ?? '?'}ms'
        : server.reachable == false
        ? l10n.unreachable
        : l10n.untested;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${server.host}:${server.port}',
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                color: server.reachable == false
                    ? cs.onSurface.withValues(alpha: 0.3)
                    : null,
              ),
            ),
          ),
          if (server.name.isNotEmpty)
            Text(
              server.name,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                fontSize: 10,
                color: statusColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
