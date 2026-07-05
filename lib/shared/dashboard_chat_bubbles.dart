part of 'dashboard_chat.dart';

class _ChatBubble extends StatelessWidget {
  final ChatItem item;
  final void Function(String questionText, String optionLabel)? onSelectOption;
  final Map<String, String> collectedAnswers;
  final bool hasPendingQuestions;

  const _ChatBubble({
    required this.item,
    this.onSelectOption,
    this.collectedAnswers = const {},
    this.hasPendingQuestions = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.85;

    if (item.role == 'assistant' &&
        item.content.isEmpty &&
        (item.thinking == null || item.thinking!.isEmpty)) {
      return const SizedBox.shrink();
    }

    if (item.role == 'user_question') {
      return _UserQuestionCard(
        item: item,
        onSelectOption: onSelectOption,
        collectedAnswers: collectedAnswers,
        isActive: hasPendingQuestions,
      );
    }

    if (item.role == 'assistant') {
      return GestureDetector(
        onLongPress: () => _copyBubbleText(context, item.content),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.thinking != null && item.thinking!.isNotEmpty)
              _ThinkingBlock(text: item.thinking!),
            if (item.content.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  constraints: BoxConstraints(maxWidth: maxBubbleWidth),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _MixedContent(
                    content: item.content,
                    styleSheet: chatMarkdownStyle(context),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    if (item.role == 'tool_use') {
      final status = item.metadata?['status'] ?? 'running';
      final color = status == 'ok'
          ? Colors.green.shade400
          : status == 'error'
              ? Colors.red.shade400
              : Colors.amber.shade300;
      final icon = status == 'ok'
          ? Icons.check_circle
          : status == 'error'
              ? Icons.error
              : Icons.hourglass_top;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    item.content,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: color,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (status == 'error' && item.metadata?['error'] != null)
              Padding(
                padding: const EdgeInsets.only(left: 20, top: 2),
                child: Text(
                  '${item.metadata!['error']}',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade300),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            if (item.subEvents != null)
              for (var i = 0; i < item.subEvents!.length; i++)
                _SubEventRow(
                  event: item.subEvents![i],
                  isLast: i == item.subEvents!.length - 1,
                ),
          ],
        ),
      );
    }

    if (item.role == 'ui_widget') {
      final meta = item.metadata;
      if (meta != null) {
        final action = meta['action'] as String?;
        final params = meta['params'] as Map<String, dynamic>? ?? {};
        try {
          if (action == 'showTable') {
            final title = params['title'] as String? ?? '';
            final rawColumns = params['columns'] ?? params['headers'];
            if (rawColumns is List && rawColumns.isNotEmpty) {
              final columns = rawColumns.map((column) => '$column').toList();
              final rawRows = params['rows'];
              if (rawRows is List) {
                final rows = <List<dynamic>>[];
                for (final row in rawRows) {
                  if (row is List) {
                    rows.add(row);
                  } else if (row is Map) {
                    rows.add(columns.map((column) => row[column] ?? '').toList());
                  }
                }
                return _DataTableWidget(
                  title: title,
                  columns: columns,
                  rows: rows,
                );
              }
            }
          }
        } catch (_) {}
      }
      return const SizedBox.shrink();
    }

    if (item.role == 'recap') {
      return Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outline.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppLocalizations.of(context).recap,
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.content,
              style: TextStyle(
                fontSize: 11,
                color: cs.onSurface.withValues(alpha: 0.5),
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      );
    }

    if (item.role == 'confirm') {
      final meta = item.metadata;
      final completer = meta?['completer'] as Completer<ToolConfirmResult>?;
      final answered = meta?['answered'] == true;
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.tertiaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.tertiary.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.content,
              style: TextStyle(fontSize: 12, color: cs.onSurface),
            ),
            if (!answered && completer != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildConfirmChip(cs, l10n.allow, cs.primary, () {
                    completer.complete(const ToolConfirmResult.approve());
                    meta?['answered'] = true;
                  }),
                  const SizedBox(width: 8),
                  _buildConfirmChip(cs, l10n.alwaysAllow, cs.tertiary, () {
                    completer.complete(const ToolConfirmResult.alwaysApprove());
                    meta?['answered'] = true;
                  }),
                  const SizedBox(width: 8),
                  _buildConfirmChip(cs, l10n.deny, cs.error, () {
                    completer.complete(const ToolConfirmResult.reject());
                    meta?['answered'] = true;
                  }),
                ],
              ),
            ],
            if (answered)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '✓ ${l10n.answered}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        ),
      );
    }

    final isUser = item.role == 'user';
    return GestureDetector(
      onLongPress: () => _copyBubbleText(context, item.content),
      child: Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          decoration: BoxDecoration(
            color: isUser ? cs.primaryContainer : cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            item.content,
            style: TextStyle(fontSize: 12, color: cs.onSurface),
          ),
        ),
      ),
    );
  }
}

class _SubEventRow extends StatelessWidget {
  final SubEvent event;
  final bool isLast;

  const _SubEventRow({required this.event, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final branch = isLast ? '└─' : '├─';
    final Widget icon;
    switch (event.type) {
      case 'thinking':
        icon = Icon(Icons.psychology, size: 10, color: Colors.amber.shade400);
      case 'tool':
        if (event.status == null) {
          icon = SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.2,
              color: cs.primary,
            ),
          );
        } else if (event.status == 'error') {
          icon = Icon(Icons.error, size: 10, color: Colors.red.shade400);
        } else {
          icon = Icon(
            Icons.check_circle,
            size: 10,
            color: Colors.green.shade400,
          );
        }
      default:
        icon = Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: cs.onSurface.withValues(alpha: 0.3),
          ),
        );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Row(
        children: [
          Text(
            branch,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: cs.onSurface.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(width: 4),
          icon,
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              event.content,
              style: TextStyle(
                fontSize: 9,
                color: cs.onSurface.withValues(alpha: 0.4),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

void _copyBubbleText(BuildContext context, String text) {
  if (text.isEmpty) return;
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(AppLocalizations.of(context).copied),
      duration: const Duration(seconds: 1),
    ),
  );
}
