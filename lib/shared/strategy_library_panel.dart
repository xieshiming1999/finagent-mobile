import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/market/backtest/strategy_artifact_contract.dart';
import 'i18n/app_localizations.dart';
import 'strategy_library_model.dart';

class StrategyLibraryPanel extends StatefulWidget {
  final String basePath;
  final void Function(String action, StrategyLibraryItem item) onAction;
  final VoidCallback? onCreateStrategy;

  const StrategyLibraryPanel({
    super.key,
    required this.basePath,
    required this.onAction,
    this.onCreateStrategy,
  });

  @override
  State<StrategyLibraryPanel> createState() => _StrategyLibraryPanelState();
}

class _StrategyLibraryPanelState extends State<StrategyLibraryPanel> {
  List<StrategyLibraryItem> _items = [];
  String? _error;
  DateTime? _modified;
  String _typeFilter = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant StrategyLibraryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.basePath != widget.basePath) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final stats = _StrategyLibraryStats.fromItems(_items);
    final paths = strategyArtifactPaths(widget.basePath);
    final visibleItems = _typeFilter == 'all'
        ? _items
        : _items
              .where((item) => item.strategyType == _typeFilter)
              .toList(growable: false);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            children: [
              Text(
                l10n.strategyLibrary,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              _badge(cs, '${_items.length}'),
              const Spacer(),
              _chipButton(
                cs,
                l10n.strategyLibraryCreate,
                widget.onCreateStrategy,
              ),
              const SizedBox(width: 6),
              _chipButton(cs, l10n.refresh, _load),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _summaryPill(cs, l10n.strategyRerun, '${stats.runnable}'),
                _summaryPill(
                  cs,
                  l10n.strategyReadEvidence,
                  '${stats.observedOnly}',
                ),
                _summaryPill(cs, l10n.strategyTypeStock, '${stats.stock}'),
                _summaryPill(cs, l10n.strategyTypeFund, '${stats.fund}'),
                _summaryPill(
                  cs,
                  l10n.strategyTypePortfolio,
                  '${stats.portfolio}',
                ),
                _summaryPill(cs, l10n.strategyTypeEtf, '${stats.etf}'),
                _summaryPill(
                  cs,
                  l10n.strategyCreateMonitor,
                  '${stats.monitorReady}',
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _filterChip(cs, 'all', l10n.strategyTypeAll),
                _filterChip(
                  cs,
                  StrategyLibraryItem.stockStrategy,
                  l10n.strategyTypeStock,
                ),
                _filterChip(
                  cs,
                  StrategyLibraryItem.fundStrategy,
                  l10n.strategyTypeFund,
                ),
                _filterChip(
                  cs,
                  StrategyLibraryItem.portfolioStrategy,
                  l10n.strategyTypePortfolio,
                ),
                _filterChip(
                  cs,
                  StrategyLibraryItem.etfMarketStrategy,
                  l10n.strategyTypeEtf,
                ),
                _filterChip(
                  cs,
                  StrategyLibraryItem.unknownStrategy,
                  l10n.strategyTypeUnknown,
                ),
              ],
            ),
          ),
        ),
        if (_modified != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                l10n.strategyLibraryUpdatedAt(
                  MaterialLocalizations.of(context).formatShortDate(_modified!),
                ),
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: _contractTile(
                  cs,
                  l10n.strategyArtifactContract,
                  strategyArtifactContract,
                  l10n.strategyArtifactContractHint,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _contractTile(
                  cs,
                  l10n.strategyLibraryPath,
                  l10n.strategyArtifactCanonical,
                  paths.libraryPath,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _contractTile(
                  cs,
                  l10n.strategyItemDir,
                  l10n.strategyArtifactPerItem,
                  paths.itemDir,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _error != null
              ? _errorView(cs, l10n)
              : _items.isEmpty
              ? _emptyView(cs, l10n)
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: visibleItems.length,
                  itemBuilder: (_, index) => _strategyCard(visibleItems[index]),
                ),
        ),
      ],
    );
  }

  Widget _emptyView(ColorScheme cs, AppLocalizations l10n) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        l10n.strategyLibraryEmpty,
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.onSurface.withValues(alpha: 0.45)),
      ),
    ),
  );

  Widget _errorView(ColorScheme cs, AppLocalizations l10n) => Center(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Text(
        '${l10n.statusError}: $_error',
        textAlign: TextAlign.center,
        style: TextStyle(color: cs.error),
      ),
    ),
  );

  Widget _strategyCard(StrategyLibraryItem item) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.strategyId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: cs.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                _statusPill(cs, item.status, item.runnable),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _infoChip(cs, l10n.strategyAssetClass, item.assetClass),
                _infoChip(
                  cs,
                  l10n.strategyType,
                  _strategyTypeLabel(l10n, item.strategyType),
                ),
                _infoChip(
                  cs,
                  l10n.strategySymbols,
                  item.symbols.isEmpty ? '-' : item.symbols.join(', '),
                ),
                _infoChip(cs, l10n.strategyEvidenceAction, item.evidenceAction),
              ],
            ),
            const SizedBox(height: 8),
            _infoBlock(
              cs,
              l10n.strategyEvidenceSummary,
              item.evidenceSummary.isEmpty ? '-' : item.evidenceSummary,
            ),
            const SizedBox(height: 6),
            _infoBlock(
              cs,
              l10n.strategyDataSummary,
              item.dataSummary.isEmpty ? '-' : item.dataSummary,
            ),
            if (item.riskRewardSummary.isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoBlock(
                cs,
                l10n.strategyRiskRewardSummary,
                item.riskRewardSummary,
              ),
            ],
            if (item.assumptionSummary.isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoBlock(
                cs,
                l10n.strategyAssumptionSummary,
                item.assumptionSummary,
              ),
            ],
            if (item.updatedAt.isNotEmpty) ...[
              const SizedBox(height: 6),
              _infoBlock(cs, l10n.lastUpdatedShort, item.updatedAt),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _actionButton(
                  cs,
                  item.runnable
                      ? l10n.strategyRerun
                      : l10n.strategyReadEvidence,
                  () => _sendAction(item.runnable ? 'rerun' : 'read', item),
                ),
                _actionButton(
                  cs,
                  l10n.strategyAddWatch,
                  () => _sendAction('watch', item),
                ),
                _actionButton(
                  cs,
                  l10n.strategyCreateMonitor,
                  () => _sendAction('monitor', item),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _chipButton(ColorScheme cs, String label, VoidCallback? onTap) =>
      TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );

  Widget _filterChip(ColorScheme cs, String value, String label) {
    final selected = _typeFilter == value;
    return ChoiceChip(
      selected: selected,
      label: Text(label, style: const TextStyle(fontSize: 11)),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _typeFilter = value),
      selectedColor: cs.primary.withValues(alpha: 0.14),
      backgroundColor: cs.surfaceContainerHighest,
      side: BorderSide(color: cs.outline.withValues(alpha: 0.12)),
      labelStyle: TextStyle(color: selected ? cs.primary : cs.onSurface),
    );
  }

  Widget _actionButton(ColorScheme cs, String label, VoidCallback onTap) =>
      OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 30),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );

  Widget _badge(ColorScheme cs, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: cs.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: cs.primary,
      ),
    ),
  );

  Widget _summaryPill(ColorScheme cs, String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
    ),
    child: Text(
      '$label: $value',
      style: TextStyle(
        fontSize: 11,
        color: cs.onSurface.withValues(alpha: 0.7),
      ),
    ),
  );

  Widget _contractTile(
    ColorScheme cs,
    String label,
    String value,
    String detail,
  ) => Tooltip(
    message: detail,
    child: Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    ),
  );

  Widget _statusPill(ColorScheme cs, String status, bool runnable) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: runnable
          ? Colors.green.withValues(alpha: 0.12)
          : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      status.isEmpty ? '-' : status,
      style: TextStyle(
        fontSize: 10,
        color: runnable ? Colors.green.shade700 : cs.onSurface,
      ),
    ),
  );

  Widget _infoChip(ColorScheme cs, String label, String value) => Container(
    constraints: const BoxConstraints(maxWidth: 180),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
        Text(
          value.isEmpty ? '-' : value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );

  Widget _infoBlock(ColorScheme cs, String label, String value) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: cs.surface,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: cs.outline.withValues(alpha: 0.12)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: cs.onSurface.withValues(alpha: 0.45),
          ),
        ),
        const SizedBox(height: 2),
        Text(value.isEmpty ? '-' : value, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );

  void _sendAction(String action, StrategyLibraryItem item) {
    widget.onAction(action, item);
  }

  String _strategyTypeLabel(AppLocalizations l10n, String type) {
    switch (type) {
      case StrategyLibraryItem.stockStrategy:
        return l10n.strategyTypeStock;
      case StrategyLibraryItem.fundStrategy:
        return l10n.strategyTypeFund;
      case StrategyLibraryItem.portfolioStrategy:
        return l10n.strategyTypePortfolio;
      case StrategyLibraryItem.etfMarketStrategy:
        return l10n.strategyTypeEtf;
      default:
        return l10n.strategyTypeUnknown;
    }
  }

  void _load() {
    try {
      final file = File(_storePath);
      if (!file.existsSync()) {
        setState(() {
          _items = [];
          _error = null;
          _modified = null;
        });
        return;
      }
      final decoded = jsonDecode(file.readAsStringSync());
      final items = parseStrategyLibraryRows(decoded);
      setState(() {
        _items = items;
        _error = null;
        _modified = file.lastModifiedSync();
      });
    } catch (error) {
      setState(() {
        _items = [];
        _error = '$error';
        _modified = null;
      });
    }
  }

  String get _storePath => readableStrategyLibraryPath(widget.basePath);
}

class _StrategyLibraryStats {
  final int runnable;
  final int observedOnly;
  final int stock;
  final int fund;
  final int portfolio;
  final int etf;
  final int unknown;
  final int monitorReady;

  const _StrategyLibraryStats({
    required this.runnable,
    required this.observedOnly,
    required this.stock,
    required this.fund,
    required this.portfolio,
    required this.etf,
    required this.unknown,
    required this.monitorReady,
  });

  factory _StrategyLibraryStats.fromItems(List<StrategyLibraryItem> items) {
    var runnable = 0;
    var observedOnly = 0;
    var stock = 0;
    var fund = 0;
    var portfolio = 0;
    var etf = 0;
    var unknown = 0;
    var monitorReady = 0;
    for (final item in items) {
      if (item.runnable) {
        runnable += 1;
      } else {
        observedOnly += 1;
      }
      switch (item.strategyType) {
        case StrategyLibraryItem.stockStrategy:
          stock += 1;
          break;
        case StrategyLibraryItem.fundStrategy:
          fund += 1;
          break;
        case StrategyLibraryItem.portfolioStrategy:
          portfolio += 1;
          break;
        case StrategyLibraryItem.etfMarketStrategy:
          etf += 1;
          break;
        default:
          unknown += 1;
          break;
      }
      if (item.runnable || item.status == 'observed') monitorReady += 1;
    }
    return _StrategyLibraryStats(
      runnable: runnable,
      observedOnly: observedOnly,
      stock: stock,
      fund: fund,
      portfolio: portfolio,
      etf: etf,
      unknown: unknown,
      monitorReady: monitorReady,
    );
  }
}
