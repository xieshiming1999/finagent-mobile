import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'dashboard_panel_models.dart';
import 'i18n/app_localizations.dart';
import 'monitor_panel_shared.dart';

class DashboardCard extends StatefulWidget {
  final DashboardItem item;
  final bool isActive;
  final bool isBackgroundRunning;
  final bool bgFull;
  final String? thumbnailPath;
  final VoidCallback onTap;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onStartBackground;
  final VoidCallback onStopBackground;
  final VoidCallback onViewBackground;
  final VoidCallback? onMonitorToggle;

  const DashboardCard({
    super.key,
    required this.item,
    required this.isActive,
    this.isBackgroundRunning = false,
    this.bgFull = false,
    this.thumbnailPath,
    required this.onTap,
    required this.onExport,
    required this.onDelete,
    required this.onStartBackground,
    required this.onStopBackground,
    required this.onViewBackground,
    this.onMonitorToggle,
  });

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> with SingleTickerProviderStateMixin {
  Timer? _carouselTimer;
  int _carouselIndex = 0;
  late final AnimationController _runFlashCtrl;
  String? _lastRunTimeStr;

  @override
  void initState() {
    super.initState();
    _runFlashCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    _lastRunTimeStr = widget.item.monitorData?['lastRunTime'] as String?;
    _maybeStartCarousel();
  }

  @override
  void didUpdateWidget(covariant DashboardCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldType = oldWidget.item.monitorData?['displayType'];
    final newType = widget.item.monitorData?['displayType'];
    if (oldType != newType) {
      _carouselIndex = 0;
      _maybeStartCarousel();
    }
    final newRunTime = widget.item.monitorData?['lastRunTime'] as String?;
    if (newRunTime != null && newRunTime != _lastRunTimeStr) {
      _lastRunTimeStr = newRunTime;
      _runFlashCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _runFlashCtrl.dispose();
    super.dispose();
  }

  void _maybeStartCarousel() {
    _carouselTimer?.cancel();
    _carouselTimer = null;
    if (widget.item.type != DashboardItemType.monitor) return;
    if (widget.item.monitorData?['displayType'] != 'carousel') return;
    final items = widget.item.monitorData?['items'] as List?;
    if (items == null || items.length <= 1) return;
    _carouselTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      setState(() => _carouselIndex = (_carouselIndex + 1) % items.length);
    });
  }

  void _showActions() {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final isMonitor = widget.item.type == DashboardItemType.monitor;
    if (!isMonitor && widget.item.filePath == null) return;

    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMonitor) ...[
              ListTile(
                leading: Icon(widget.onMonitorToggle != null ? Icons.stop_circle_outlined : Icons.play_circle_outlined, color: cs.primary),
                title: Text((widget.item.monitorData?['enabled'] as bool? ?? true) ? l10n.stop : l10n.start),
                onTap: () {
                  Navigator.pop(context);
                  widget.onMonitorToggle?.call();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text(l10n.delete, style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete();
                },
              ),
            ] else ...[
              if (widget.isBackgroundRunning) ...[
                ListTile(
                  leading: Icon(Icons.visibility, color: cs.primary),
                  title: Text(l10n.view),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onViewBackground();
                  },
                ),
                ListTile(
                  leading: Icon(Icons.stop_circle_outlined, color: Colors.orange.shade400),
                  title: Text(l10n.stopBackground),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onStopBackground();
                  },
                ),
              ] else if (!widget.bgFull)
                ListTile(
                  leading: Icon(Icons.play_circle_outline, color: Colors.green.shade400),
                  title: Text(l10n.runInBackground),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onStartBackground();
                  },
                ),
              ListTile(
                leading: Icon(Icons.save_alt, color: cs.primary),
                title: Text(l10n.export),
                onTap: () {
                  Navigator.pop(context);
                  widget.onExport();
                },
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: cs.error),
                title: Text(l10n.delete, style: TextStyle(color: cs.error)),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDelete();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = widget.item;
    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: _showActions,
      child: Container(
        width: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: widget.isActive
              ? Border.all(color: cs.primary, width: 2)
              : item.type == DashboardItemType.monitor
                  ? Border.all(color: cs.tertiary.withValues(alpha: 0.4))
                  : Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          color: widget.isActive
              ? cs.primaryContainer.withValues(alpha: 0.3)
              : item.type == DashboardItemType.monitor
                  ? cs.tertiaryContainer.withValues(alpha: 0.15)
                  : cs.surfaceContainerLow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(4), child: SizedBox(width: 68, height: 56, child: _buildThumbnail(cs))),
                if (widget.isBackgroundRunning)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.green, border: Border.all(color: cs.surface, width: 1)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 9, height: 1.2, color: widget.isActive ? cs.primary : cs.onSurfaceVariant, fontWeight: widget.isActive ? FontWeight.w600 : FontWeight.normal)),
            ),
            if (item.type == DashboardItemType.monitor)
              Builder(
                builder: (_) {
                  final data = item.monitorData;
                  final lastRunStr = data?['lastRunTime'] as String?;
                  final lastRunTime = lastRunStr != null ? DateTime.tryParse(lastRunStr) : null;
                  final hasError = data?['hasError'] as bool? ?? false;
                  if (lastRunTime == null) return const SizedBox.shrink();
                  final baseColor = hasError ? Colors.red : Colors.green;
                  final timeStr = '${lastRunTime.hour.toString().padLeft(2, '0')}:${lastRunTime.minute.toString().padLeft(2, '0')}:${lastRunTime.second.toString().padLeft(2, '0')}';
                  return AnimatedBuilder(
                    animation: _runFlashCtrl,
                    builder: (context, child) {
                      final t = _runFlashCtrl.value;
                      final flash = t < 0.3 ? (t / 0.3) : 1.0 - ((t - 0.3) / 0.7);
                      final scale = 1.0 + flash * 0.4;
                      final color = Color.lerp(baseColor, Colors.white, flash * 0.6)!;
                      return Transform.scale(
                        scale: scale,
                        child: Text(timeStr, style: TextStyle(fontSize: 7, color: color, fontWeight: flash > 0.1 ? FontWeight.bold : FontWeight.normal)),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme cs) {
    if (widget.item.type == DashboardItemType.monitor) {
      final data = widget.item.monitorData;
      final enabled = data?['enabled'] as bool? ?? true;
      final hasError = data?['hasError'] as bool? ?? false;
      final displayType = data?['displayType'] as String? ?? 'value_card';
      if (data == null) return Center(child: Icon(Icons.monitor_heart_outlined, size: 28, color: cs.primary.withValues(alpha: 0.5)));

      final Widget content = switch (displayType) {
        'mini_chart' => _buildMiniChartThumb(cs, data),
        'status_row' => _buildStatusRowThumb(cs, data),
        'text' => _buildTextThumb(cs, data),
        'carousel' => _buildCarouselThumb(cs, data),
        _ => _buildValueCardThumb(cs, data),
      };

      return Stack(
        children: [
          content,
          Positioned(
            top: 0,
            right: 0,
            child: GestureDetector(
              onTap: widget.onMonitorToggle,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  enabled ? (hasError ? Icons.error_outline : Icons.play_circle_filled) : Icons.stop_circle_outlined,
                  size: 14,
                  color: !enabled ? Colors.grey : hasError ? Colors.red : Colors.green,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (widget.thumbnailPath != null) {
      return Image.file(File(widget.thumbnailPath!), fit: BoxFit.cover, width: 68, height: 56, errorBuilder: (_, _, _) => Center(child: Icon(Icons.article, size: 28, color: cs.primary)));
    }
    return Center(child: Icon(Icons.article, size: 28, color: cs.primary));
  }

  Widget _buildValueCardThumb(ColorScheme cs, Map<String, dynamic> data) {
    final value = data['value']?.toString() ?? '--';
    final unit = data['unit']?.toString() ?? '';
    final change = data['change'];
    final changeColor = change is num ? (change > 0 ? Colors.red : change < 0 ? Colors.green : cs.onSurfaceVariant) : cs.onSurfaceVariant;
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text('$unit$value', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (change != null)
          Text('${change is num && change > 0 ? '+' : ''}${change is num ? change.toStringAsFixed(2) : change}%', style: TextStyle(fontSize: 10, color: changeColor, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildMiniChartThumb(ColorScheme cs, Map<String, dynamic> data) {
    final series = _toDoubleList(data['series']);
    final value = data['value'];
    if (series.length < 2) return Center(child: Icon(Icons.show_chart, size: 24, color: cs.primary.withValues(alpha: 0.5)));
    final color = series.last >= series.first ? Colors.red : Colors.green;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (value != null) Text(_formatValue(value), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: cs.onSurface)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: CustomPaint(size: const Size(double.infinity, double.infinity), painter: SparklinePainter(series: series, color: color)),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusRowThumb(ColorScheme cs, Map<String, dynamic> data) {
    final items = (data['items'] as List?)?.map((e) => e as Map<String, dynamic>).take(3).toList() ?? [];
    if (items.isEmpty) return Center(child: Text('--', style: TextStyle(color: cs.onSurfaceVariant)));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Row(children: [
              Text('${item['label'] ?? ''}', style: TextStyle(fontSize: 8, color: cs.onSurfaceVariant)),
              const Spacer(),
              Text(_formatValue(item['value']), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: cs.onSurface)),
            ]),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTextThumb(ColorScheme cs, Map<String, dynamic> data) {
    final text = data['text']?.toString() ?? '--';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: cs.onSurface), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }

  Widget _buildCarouselThumb(ColorScheme cs, Map<String, dynamic> data) {
    final items = (data['items'] as List?)?.map((e) => e.toString()).toList() ?? [];
    if (items.isEmpty) return Center(child: Text('--', style: TextStyle(color: cs.onSurfaceVariant)));
    final current = items[_carouselIndex % items.length];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation), child: child),
          ),
          child: Text(current, key: ValueKey<int>(_carouselIndex), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: cs.onSurface), textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

class AddDashboardCard extends StatelessWidget {
  final VoidCallback onTap;

  const AddDashboardCard({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.3)),
          color: cs.surfaceContainerLow,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_circle_outline, size: 32, color: cs.primary.withValues(alpha: 0.6)),
            const SizedBox(height: 4),
            Text(l10n.import, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

String _formatValue(dynamic v) {
  if (v == null) return '--';
  if (v is double) return v.toStringAsFixed(2);
  if (v is int) return v.toString();
  return v.toString();
}

List<double> _toDoubleList(dynamic v) {
  if (v is! List) return [];
  return v.map((e) {
    if (e is double) return e;
    if (e is int) return e.toDouble();
    if (e is String) return double.tryParse(e) ?? 0.0;
    return 0.0;
  }).toList();
}
