import 'package:flutter/material.dart';

import 'i18n/app_localizations.dart';

class TaskListWidget extends StatelessWidget {
  final List<Map<String, dynamic>> tasks;

  const TaskListWidget({super.key, required this.tasks});

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) return const SizedBox.shrink();

    final active = tasks.where((t) => t['status'] != 'completed').toList();
    if (active.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final completed = tasks.where((t) => t['status'] == 'completed').length;
    final total = tasks.length;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.checklist, size: 12, color: cs.primary),
              const SizedBox(width: 4),
              Text(l10n.tasksProgress(completed, total),
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: cs.onSurface.withValues(alpha: 0.7))),
            ],
          ),
          const SizedBox(height: 4),
          for (final task in active)
            _buildTaskRow(task, cs),
        ],
      ),
    );
  }

  Widget _buildTaskRow(Map<String, dynamic> task, ColorScheme cs) {
    final status = task['status'] as String? ?? 'pending';
    final subject = task['subject'] as String? ?? '';

    final (icon, color, style) = switch (status) {
      'completed' => (
        Icon(Icons.check_circle, size: 11, color: Colors.green.shade400),
        cs.onSurface.withValues(alpha: 0.35),
        const TextStyle(decoration: TextDecoration.lineThrough),
      ),
      'in_progress' => (
        SizedBox(width: 11, height: 11, child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary)),
        cs.onSurface.withValues(alpha: 0.8),
        const TextStyle(fontWeight: FontWeight.w600),
      ),
      _ => (
        Icon(Icons.radio_button_unchecked, size: 11, color: cs.onSurface.withValues(alpha: 0.3)),
        cs.onSurface.withValues(alpha: 0.5),
        const TextStyle(),
      ),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 5),
          Expanded(child: Text(subject,
              style: TextStyle(fontSize: 10, color: color).merge(style),
              overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}
