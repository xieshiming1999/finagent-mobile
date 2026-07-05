part of 'dashboard_chat.dart';

class _DataTableWidget extends StatelessWidget {
  final String title;
  final List<String> columns;
  final List<List<dynamic>> rows;

  const _DataTableWidget({
    required this.title,
    required this.columns,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columnSpacing: 16,
              headingRowHeight: 28,
              dataRowMinHeight: 24,
              dataRowMaxHeight: 28,
              columns: columns
                  .map(
                    (column) => DataColumn(
                      label: Text(
                        column,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              rows: rows
                  .take(20)
                  .map(
                    (row) => DataRow(
                      cells: row
                          .map(
                            (cell) => DataCell(
                              Text(
                                '$cell',
                                style: const TextStyle(fontSize: 10),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  )
                  .toList(),
            ),
          ),
          if (rows.length > 20)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
              child: Text(
                AppLocalizations.of(context).moreRowsText(rows.length - 20),
                style: TextStyle(
                  fontSize: 9,
                  color: cs.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

final _htmlFenceRe = RegExp(r'```html\s*\n([\s\S]*?)```', multiLine: true);
final _htmlFenceStartRe = RegExp(r'```html\s*\n', multiLine: true);

class _MixedContent extends StatelessWidget {
  final String content;
  final MarkdownStyleSheet styleSheet;

  const _MixedContent({required this.content, required this.styleSheet});

  @override
  Widget build(BuildContext context) {
    final contracts = _financeContractsFromContent(content);
    final visibleContent = _stripFinanceContractLines(content);
    if (!_htmlFenceRe.hasMatch(visibleContent)) {
      final openMatch = _htmlFenceStartRe.firstMatch(visibleContent);
      if (openMatch != null) {
        final before = visibleContent.substring(0, openMatch.start).trim();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (before.isNotEmpty)
              MarkdownBody(
                data: before,
                styleSheet: styleSheet,
                selectable: true,
                shrinkWrap: true,
              ),
            const _PendingHtmlBlock(),
            ...contracts,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (visibleContent.isNotEmpty)
            MarkdownBody(
              data: visibleContent,
              styleSheet: styleSheet,
              selectable: true,
              shrinkWrap: true,
            ),
          ...contracts,
        ],
      );
    }

    final segments = <_Segment>[];
    var lastEnd = 0;
    for (final match in _htmlFenceRe.allMatches(visibleContent)) {
      if (match.start > lastEnd) {
        final md = visibleContent.substring(lastEnd, match.start).trim();
        if (md.isNotEmpty) segments.add(_Segment(md, false));
      }
      segments.add(_Segment(match.group(1)!.trim(), true));
      lastEnd = match.end;
    }
    if (lastEnd < visibleContent.length) {
      final md = visibleContent.substring(lastEnd).trim();
      if (md.isNotEmpty) {
        final openMatch = _htmlFenceStartRe.firstMatch(md);
        if (openMatch != null) {
          final before = md.substring(0, openMatch.start).trim();
          if (before.isNotEmpty) segments.add(_Segment(before, false));
          segments.add(_Segment('', true, pending: true));
        } else {
          segments.add(_Segment(md, false));
        }
      }
    }

    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...segments.map((segment) {
          if (!segment.isHtml) {
            return MarkdownBody(
              data: segment.text,
              styleSheet: styleSheet,
              selectable: true,
              shrinkWrap: true,
            );
          }
          if (segment.pending) return const _PendingHtmlBlock();
          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(8),
            ),
            clipBehavior: Clip.antiAlias,
            child: HtmlWidget(
              segment.text,
              textStyle: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
          );
        }),
        ...contracts,
      ],
    );
  }
}

List<Widget> _financeContractsFromContent(String content) {
  final cards = <Widget>[];
  for (final line in content.split('\n')) {
    if (line.startsWith('strategyReview:')) {
      final payload = _decodeContractLine(line, 'strategyReview:');
      if (payload?['contract'] == 'strategy-review-v1') {
        cards.add(
          _FinanceContractCard(
            title: '${payload!['strategyId'] ?? '-'}',
            subtitle:
                '${payload['reviewKind'] ?? 'strategy_review'} · ${payload['signal'] ?? '-'}',
            badge: 'strategy review',
            rows: [
              _contractRow('Subjects', payload['subjects']),
              _contractRow('Boundaries', payload['boundaries']),
              if ('${payload['confirmation'] ?? ''}'.isNotEmpty)
                _contractRow('Confirmation', payload['confirmation']),
            ],
          ),
        );
      }
    }
    if (line.startsWith('tradePrep:')) {
      final payload = _decodeContractLine(line, 'tradePrep:');
      if (payload?['contract'] == 'trade-prep-v1') {
        final sizing = payload!['sizing'] is Map
            ? payload['sizing'] as Map
            : {};
        cards.add(
          _FinanceContractCard(
            title: '${payload['symbol'] ?? '-'}',
            subtitle:
                '${payload['prepKind'] ?? 'trade_prep'} · ${payload['signal'] ?? '-'}',
            badge: 'trade prep',
            rows: [
              _contractRow('Strategy', payload['strategyId']),
              _contractRow('Sizing', [
                if (sizing['budget'] != null) 'budget ${sizing['budget']}',
                if (sizing['referencePrice'] != null)
                  'price ${sizing['referencePrice']}',
                if (sizing['shares'] != null) 'shares ${sizing['shares']}',
                if (sizing['amount'] != null) 'amount ${sizing['amount']}',
              ]),
              _contractRow('Boundaries', payload['boundaries']),
              if ('${payload['confirmation'] ?? ''}'.isNotEmpty)
                _contractRow('Confirmation', payload['confirmation']),
            ],
          ),
        );
      }
    }
  }
  return cards;
}

Map<String, dynamic>? _decodeContractLine(String line, String prefix) {
  try {
    final decoded = jsonDecode(line.substring(prefix.length));
    return decoded is Map<String, dynamic> ? decoded : null;
  } catch (_) {
    return null;
  }
}

String _stripFinanceContractLines(String content) {
  return content
      .split('\n')
      .where(
        (line) =>
            !line.startsWith('analysisEvidence:') &&
            !line.startsWith('strategyReview:') &&
            !line.startsWith('tradePrep:'),
      )
      .join('\n')
      .trim();
}

String _contractRow(String label, Object? value) {
  final rendered = value is List ? value.join(', ') : '${value ?? '-'}';
  return '$label: ${rendered.isEmpty ? '-' : rendered}';
}

class _FinanceContractCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final List<String> rows;

  const _FinanceContractCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(badge, style: TextStyle(fontSize: 10, color: cs.primary)),
            ],
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 4),
          ...rows.map(
            (row) => Text(
              row,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.68),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Segment {
  final String text;
  final bool isHtml;
  final bool pending;

  const _Segment(this.text, this.isHtml, {this.pending = false});
}

class _PendingHtmlBlock extends StatelessWidget {
  const _PendingHtmlBlock();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
        border: Border.all(color: cs.outline.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        AppLocalizations.of(context).renderingHtml,
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
    );
  }
}

Widget _buildConfirmChip(
  ColorScheme cs,
  String label,
  Color color,
  VoidCallback onTap,
) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}
