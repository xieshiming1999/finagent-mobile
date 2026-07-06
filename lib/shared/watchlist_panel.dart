// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';

import '../agent/watchlist.dart';
import 'i18n/app_localizations.dart';

class WatchlistPanel extends StatefulWidget {
  final WatchlistStore store;
  final void Function(String symbol)? onAnalyze;

  const WatchlistPanel({super.key, required this.store, this.onAnalyze});

  @override
  State<WatchlistPanel> createState() => _WatchlistPanelState();
}

class _WatchlistPanelState extends State<WatchlistPanel> {
  final Set<String> _expandedGroups = {};

  @override
  void initState() {
    super.initState();
    widget.store.onChanged = () {
      if (mounted) setState(() {});
    };
    if (widget.store.groups.isNotEmpty)
      _expandedGroups.add(widget.store.groups.first.id);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final groups = widget.store.groups;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text(
                l10n.watchlist,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const Spacer(),
              _chipButton(cs, l10n.createNew, () => _showAddGroupDialog(cs)),
            ],
          ),
        ),
        Expanded(
          child: groups.isEmpty
              ? Center(
                  child: Text(
                    l10n.noWatchlists,
                    style: TextStyle(
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: groups.length,
                  itemBuilder: (_, i) => _buildGroup(groups[i], cs),
                ),
        ),
      ],
    );
  }

  Widget _buildGroup(WatchlistGroup group, ColorScheme cs) {
    final l10n = AppLocalizations.of(context);
    final expanded = _expandedGroups.contains(group.id);
    final items = widget.store.getByGroup(group.id);
    final watching = items.where((i) => i.status == 'watching').toList();
    final entered = items.where((i) => i.status == 'entered').toList();
    final exited = items.where((i) => i.status == 'exited').toList();
    final typeLabel = switch (group.type) {
      'fund' => l10n.fund,
      _ => l10n.stock,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      color: cs.surfaceContainerHighest,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() {
              if (expanded) {
                _expandedGroups.remove(group.id);
              } else {
                _expandedGroups.add(group.id);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    group.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _badge(cs, '${watching.length}', cs.primary),
                  if (entered.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge(cs, l10n.enteredCount(entered.length), Colors.green),
                  ],
                  if (exited.isNotEmpty) ...[
                    const SizedBox(width: 4),
                    _badge(cs, l10n.exitedCount(exited.length), cs.outline),
                  ],
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _showAddItemDialog(cs, group),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.add, size: 16, color: cs.primary),
                    ),
                  ),
                  PopupMenuButton<String>(
                    iconSize: 16,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    onSelected: (v) {
                      if (v == 'delete')
                        setState(() => widget.store.removeGroup(group.id));
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          l10n.deleteList,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            if (watching.isNotEmpty) _buildSection(l10n.watching, watching, cs),
            if (entered.isNotEmpty) _buildSection(l10n.entered, entered, cs),
            if (exited.isNotEmpty)
              _buildSection(l10n.exited, exited, cs, collapsed: true),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '${l10n.emptyListPrompt} $typeLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(
    String title,
    List<WatchlistItem> items,
    ColorScheme cs, {
    bool collapsed = false,
  }) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: Text(
            l10n.watchlistSectionTitle(title, items.length),
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        if (!collapsed) ...items.map((item) => _buildItem(item, cs)),
        if (collapsed)
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 8),
            child: Text(
              AppLocalizations.of(context).tapToExpand,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildItem(WatchlistItem item, ColorScheme cs) {
    final l10n = AppLocalizations.of(context);
    final isUp = (item.changePct ?? 0) >= 0;
    final priceColor = isUp ? Colors.red : Colors.green;
    final hasName =
        item.name.trim().isNotEmpty && item.name.trim() != item.symbol;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            hasName ? item.name : item.symbol,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                          if (hasName) ...[
                            const SizedBox(width: 6),
                            Text(
                              item.symbol,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.tags.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Wrap(
                            spacing: 4,
                            children: item.tags
                                .map(
                                  (t) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: cs.primary.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      t,
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      item.currentPrice?.toStringAsFixed(2) ?? '—',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: priceColor,
                      ),
                    ),
                    if (item.changePct != null)
                      Text(
                        '${isUp ? "+" : ""}${item.changePct!.toStringAsFixed(2)}%',
                        style: TextStyle(fontSize: 11, color: priceColor),
                      ),
                  ],
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 18,
                    color: cs.onSurface.withValues(alpha: 0.45),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                  onSelected: (value) {
                    if (value == 'analyze') widget.onAnalyze?.call(item.symbol);
                    if (value == 'delete')
                      setState(() => widget.store.removeItem(item.id));
                  },
                  itemBuilder: (_) => [
                    if (item.status != 'exited')
                      PopupMenuItem(
                        value: 'analyze',
                        child: Row(
                          children: [
                            const Icon(Icons.auto_awesome, size: 16),
                            const SizedBox(width: 8),
                            Text(l10n.aiAnalysis),
                          ],
                        ),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          const Icon(Icons.delete_outline, size: 16),
                          const SizedBox(width: 8),
                          Text(l10n.delete),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (item.status == 'watching' && item.entryCondition != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l10n.condition}: ${item.entryCondition}  ${item.targetEntryPrice != null ? "${l10n.target}: ${item.targetEntryPrice}" : ""}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            if (item.status == 'entered')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.enteredPositionSummary(
                    buyAtLabel: l10n.buyAt,
                    actualEntryPrice: item.actualEntryPrice?.toStringAsFixed(2),
                    stopLossValue: item.stopLoss?.toString(),
                    stopLossLabel: l10n.stopLoss,
                    targetValue: item.targetPrice?.toString(),
                    targetLabel: l10n.target,
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            if (item.status == 'exited' && item.profitPct != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.exitedPositionSummary(
                    profitPct:
                        '${item.profitPct! >= 0 ? "+" : ""}${item.profitPct!.toStringAsFixed(1)}%',
                    actualEntryPrice: item.actualEntryPrice?.toString(),
                    exitPrice: item.exitPrice?.toString(),
                  ),
                  style: TextStyle(
                    fontSize: 11,
                    color: item.profitPct! >= 0 ? Colors.green : Colors.red,
                  ),
                ),
              ),
            if (item.score != null || item.rating != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Row(
                  children: [
                    if (item.score != null)
                      Text(
                        l10n.scoreText(item.score!),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: cs.primary,
                        ),
                      ),
                    if (item.rating != null) ...[
                      const SizedBox(width: 6),
                      Text(
                        item.rating!,
                        style: TextStyle(fontSize: 11, color: cs.tertiary),
                      ),
                    ],
                  ],
                ),
              ),
            if (item.analysisResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  item.analysisResult!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddItemDialog(ColorScheme cs, WatchlistGroup group) {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    var suggestions = <WatchlistAssetSuggestion>[];
    WatchlistAssetSuggestion? selected;
    final typeLabel = switch (group.type) {
      'fund' => l10n.assetCodeLabel(l10n.fund),
      _ => l10n.assetCodeLabel(l10n.stock),
    };
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('${l10n.addToGroup} ${group.name}'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: InputDecoration(
                    hintText: typeLabel,
                    helperText: l10n.codeExampleText('600519 / 000001'),
                  ),
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  onChanged: (value) {
                    setDialogState(() {
                      selected = null;
                      suggestions = widget.store.searchCachedAssets(
                        value,
                        type: group.type,
                      );
                    });
                  },
                ),
                if (suggestions.isNotEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 180),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: suggestions.length,
                      itemBuilder: (_, index) {
                        final item = suggestions[index];
                        final secondary = [item.code, item.market, item.company]
                            .whereType<String>()
                            .where((v) => v.isNotEmpty)
                            .join(' · ');
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            item.name.isNotEmpty ? item.name : item.code,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: secondary.isEmpty
                              ? null
                              : Text(
                                  secondary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () {
                            setDialogState(() {
                              selected = item;
                              ctrl.text = item.code;
                              suggestions = const [];
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                final symbol = (selected?.code ?? ctrl.text).trim();
                if (symbol.isNotEmpty) {
                  widget.store.addItem(
                    WatchlistItem(
                      groupId: group.id,
                      symbol: symbol,
                      name: selected?.name ?? '',
                      type: group.type,
                      source: 'user',
                    ),
                  );
                  setState(() {});
                }
                Navigator.pop(ctx);
              },
              child: Text(l10n.add),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddGroupDialog(ColorScheme cs) {
    final l10n = AppLocalizations.of(context);
    final ctrl = TextEditingController();
    String selectedType = 'stock';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.createWatchlist),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'stock', label: Text(l10n.stock)),
                  ButtonSegment(value: 'fund', label: Text(l10n.fund)),
                  ButtonSegment(value: 'custom', label: Text(l10n.custom)),
                ],
                selected: {selectedType},
                onSelectionChanged: (v) {
                  setDialogState(() {
                    selectedType = v.first;
                    if (selectedType == 'stock') {
                      ctrl.text = '${l10n.watchlist}${l10n.stock}';
                    } else if (selectedType == 'fund')
                      ctrl.text = '${l10n.watchlist}${l10n.fund}';
                    else
                      ctrl.text = '';
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                decoration: InputDecoration(hintText: l10n.listName),
                autofocus: true,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (ctrl.text.trim().isNotEmpty) {
                  widget.store.addGroup(
                    WatchlistGroup(name: ctrl.text.trim(), type: selectedType),
                  );
                  setState(() {});
                }
                Navigator.pop(ctx);
              },
              child: Text(l10n.create),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipButton(ColorScheme cs, String label, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(label, style: TextStyle(fontSize: 12, color: cs.primary)),
        ),
      );

  Widget _badge(ColorScheme cs, String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: TextStyle(fontSize: 10, color: color)),
  );
}
