import 'package:flutter/material.dart';

import 'dashboard_panel_card.dart';
import 'dashboard_panel_models.dart';
import 'i18n/app_localizations.dart';

class DashboardPanel extends StatefulWidget {
  final List<DashboardItem> items;
  final DashboardItem? activeItem;
  final bool expanded;
  final bool fillSpace;
  final Set<String> backgroundRunning;
  final String? viewingBgId;
  final VoidCallback? onToggle;
  final ValueChanged<DashboardItem> onSelect;
  final VoidCallback onImport;
  final ValueChanged<DashboardItem> onExport;
  final ValueChanged<DashboardItem> onDelete;
  final ValueChanged<DashboardItem> onStartBackground;
  final ValueChanged<DashboardItem> onStopBackground;
  final ValueChanged<DashboardItem> onViewBackground;
  final VoidCallback onViewMain;
  final VoidCallback? onFullscreen;
  final VoidCallback? onHideWebView;
  final int maxBackgroundTasks;
  final String? Function(String dashboardId)? thumbnailPathResolver;
  final void Function(int oldIndex, int newIndex)? onReorder;
  /// Callback for toggling monitor enabled state. Called with (monitorId, newEnabled).
  final void Function(String monitorId, bool enabled)? onMonitorToggle;
  /// Callback when a monitor card is tapped (show detail sheet).
  final void Function(String monitorId)? onMonitorTap;
  /// Optional widget shown in panel header (e.g. notification badge).
  final Widget? headerTrailing;

  const DashboardPanel({
    super.key,
    required this.items,
    this.activeItem,
    required this.expanded,
    this.fillSpace = false,
    this.backgroundRunning = const {},
    this.viewingBgId,
    this.onToggle,
    required this.onSelect,
    required this.onImport,
    required this.onExport,
    required this.onDelete,
    required this.onStartBackground,
    required this.onStopBackground,
    required this.onViewBackground,
    required this.onViewMain,
    this.onFullscreen,
    this.onHideWebView,
    this.maxBackgroundTasks = 2,
    this.thumbnailPathResolver,
    this.onReorder,
    this.onMonitorToggle,
    this.onMonitorTap,
    this.headerTrailing,
  });

  @override
  State<DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends State<DashboardPanel> {
  String? _activeTag;

  List<DashboardItem> get _filteredItems {
    if (_activeTag == null) return widget.items;
    return widget.items.where((i) => i.tag == _activeTag).toList();
  }

  Set<String> get _allTags {
    final tags = <String>{};
    for (final item in widget.items) {
      if (item.tag != null && item.tag!.isNotEmpty) tags.add(item.tag!);
    }
    return tags;
  }

  Widget _buildCard(DashboardItem item) {
    final isRunning = widget.backgroundRunning.contains(item.id);
    return DashboardCard(
      item: item,
      isActive: item.id == widget.activeItem?.id,
      isBackgroundRunning: isRunning,
      thumbnailPath: widget.thumbnailPathResolver?.call(item.id),
      onTap: item.type == DashboardItemType.monitor
          ? () => widget.onMonitorTap?.call(item.id)
          : () => widget.onSelect(item),
      onExport: () => widget.onExport(item),
      onDelete: () => widget.onDelete(item),
      onStartBackground: () => widget.onStartBackground(item),
      onStopBackground: () => widget.onStopBackground(item),
      onViewBackground: () => widget.onViewBackground(item),
      onMonitorToggle: item.type == DashboardItemType.monitor
          ? () {
              final enabled = item.monitorData?['enabled'] as bool? ?? true;
              widget.onMonitorToggle?.call(item.id, !enabled);
            }
          : null,
      bgFull: widget.backgroundRunning.length >= widget.maxBackgroundTasks,
    );
  }

  Widget _buildTagChips(ColorScheme cs) {
    final tags = _allTags;
    if (tags.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 28,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _tagChip(cs, null, AppLocalizations.of(context).all),
          for (final tag in tags) _tagChip(cs, tag, tag),
        ],
      ),
    );
  }

  Widget _tagChip(ColorScheme cs, String? tag, String label) {
    final selected = _activeTag == tag;
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: GestureDetector(
        onTap: () => setState(() => _activeTag = tag),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            color: selected ? cs.primary : cs.surfaceContainerHigh,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: selected ? cs.onPrimary : cs.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final items = _filteredItems;

    return Column(
      mainAxisSize: (widget.fillSpace && widget.expanded)
          ? MainAxisSize.max
          : MainAxisSize.min,
      children: [
        // Collapse handle — hidden in tab mode (onToggle == null)
        if (widget.onToggle != null)
        GestureDetector(
          onTap: widget.onToggle,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            color: cs.surface,
            child: Row(
              children: [
                Icon(Icons.dashboard, size: 14, color: cs.primary),
                const SizedBox(width: 4),
                Text(
                  '${widget.items.length} ${l10n.dashboardsUnit}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
                if (widget.backgroundRunning.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Colors.green,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '${widget.backgroundRunning.length} ${l10n.backgroundShort}',
                    style: TextStyle(fontSize: 10, color: Colors.green.shade400),
                  ),
                ],
                if (widget.headerTrailing != null) ...[
                  const SizedBox(width: 4),
                  widget.headerTrailing!,
                ],
                const Spacer(),
                if (widget.viewingBgId != null)
                  GestureDetector(
                    onTap: widget.onViewMain,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: cs.primaryContainer,
                      ),
                      child: Text(
                        '← ${l10n.mainView}',
                        style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                if (widget.viewingBgId != null) const SizedBox(width: 8),
                if (widget.onHideWebView != null || widget.onFullscreen != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      color: cs.surfaceContainerHighest,
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (widget.onFullscreen != null)
                        GestureDetector(
                          onTap: widget.onFullscreen,
                          child: Icon(Icons.fullscreen, size: 16, color: cs.onSurfaceVariant),
                        ),
                      if (widget.onHideWebView != null && widget.onFullscreen != null)
                        const SizedBox(width: 4),
                      if (widget.onHideWebView != null)
                        GestureDetector(
                          onTap: widget.onHideWebView,
                          child: Icon(Icons.close, size: 14, color: cs.onSurfaceVariant),
                        ),
                    ]),
                  ),
                if (widget.onHideWebView != null || widget.onFullscreen != null)
                  const SizedBox(width: 6),
                if (widget.onToggle != null)
                Icon(
                  widget.expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
        // Tag filter chips
        if (widget.expanded) _buildTagChips(cs),
        // Card strip
        if (widget.expanded)
          widget.fillSpace
              ? Expanded(
                  child: GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 90,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 76 / 100,
                    ),
                    itemCount: items.length + 1,
                    itemBuilder: (context, index) {
                      if (index < items.length) return _buildCard(items[index]);
                      return AddDashboardCard(onTap: widget.onImport);
                    },
                  ),
                )
              : SizedBox(
                  height: 110,
                  child: ReorderableListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    itemCount: items.length + 1,
                    buildDefaultDragHandles: false,
                    onReorderItem: (oldIndex, newIndex) {
                      if (oldIndex >= items.length || newIndex > items.length) return;
                      widget.onReorder?.call(oldIndex, newIndex);
                    },
                    proxyDecorator: (child, index, animation) => Material(
                      color: Colors.transparent,
                      child: child,
                    ),
                    itemBuilder: (context, index) {
                      if (index < items.length) {
                        return ReorderableDragStartListener(
                          key: ValueKey(items[index].id),
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _buildCard(items[index]),
                          ),
                        );
                      }
                      return Padding(
                        key: const ValueKey('_add'),
                        padding: EdgeInsets.zero,
                        child: AddDashboardCard(onTap: widget.onImport),
                      );
                    },
                  ),
                ),
      ],
    );
  }
}
