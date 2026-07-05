part of 'dashboard_chat.dart';

class EventStatusRow extends StatelessWidget {
  final AgentStatus? status;
  final String? summary;
  final int queueLength;
  final Color amberAccent;

  const EventStatusRow({
    super.key,
    required this.status,
    required this.summary,
    required this.queueLength,
    required this.amberAccent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textColor = cs.onSurface.withValues(alpha: 0.5);

    if (status == null && summary != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          children: [
            Icon(Icons.check_circle, size: 10, color: amberAccent),
            const SizedBox(width: 6),
            Text(summary!, style: TextStyle(fontSize: 10, color: amberAccent)),
          ],
        ),
      );
    }

    if (status == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: amberAccent,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${status!.verb}...',
            style: TextStyle(fontSize: 10, color: textColor),
          ),
          if (status!.currentTool != null) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                status!.currentTool!,
                style: TextStyle(fontSize: 10, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          Text(
            '${status!.elapsedMs ~/ 1000}s',
            style: TextStyle(fontSize: 10, color: textColor),
          ),
        ],
      ),
    );
  }
}

class QueuePreview extends StatefulWidget {
  final List<PendingNotification> notifications;
  final Color amberAccent;

  const QueuePreview({
    super.key,
    required this.notifications,
    required this.amberAccent,
  });

  @override
  State<QueuePreview> createState() => _QueuePreviewState();
}

class _QueuePreviewState extends State<QueuePreview> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final count = widget.notifications.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            color: widget.amberAccent.withValues(alpha: 0.08),
            child: Row(
              children: [
                Icon(Icons.queue, size: 12, color: widget.amberAccent),
                const SizedBox(width: 6),
                Text(
                  l10n.queuePendingSummary(count),
                  style: TextStyle(fontSize: 10, color: widget.amberAccent),
                ),
                const Spacer(),
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 14,
                  color: widget.amberAccent,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            constraints: const BoxConstraints(maxHeight: 120),
            color: cs.surface.withValues(alpha: 0.5),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              itemCount: count,
              itemBuilder: (_, i) {
                final notification = widget.notifications[i];
                final tag = notification.source ?? l10n.eventSourceTag;
                final preview = notification.prompt.length > 80
                    ? '${notification.prompt.substring(0, 80)}...'
                    : notification.prompt;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: widget.amberAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            fontSize: 8,
                            color: widget.amberAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          preview.replaceAll('\n', ' '),
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class EventChatBubble extends StatelessWidget {
  final ChatItem item;
  final Color amberAccent;

  const EventChatBubble({
    super.key,
    required this.item,
    required this.amberAccent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.85;

    if (item.role == 'assistant' &&
        item.content.isEmpty &&
        (item.thinking == null || item.thinking!.isEmpty)) {
      return const SizedBox.shrink();
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
                    color: amberAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: amberAccent.withValues(alpha: 0.15),
                    ),
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

    if (item.role == 'notification') {
      return Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: amberAccent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: amberAccent.withValues(alpha: 0.25)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.bolt, size: 14, color: amberAccent),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                item.content,
                style: TextStyle(
                  fontSize: 11,
                  color: cs.onSurface.withValues(alpha: 0.7),
                ),
                maxLines: 6,
                overflow: TextOverflow.ellipsis,
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
              : amberAccent;
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
          ],
        ),
      );
    }

    if (item.role == 'tool_result') {
      final analysisEvidence = _analysisEvidenceFromContent(item.content);
      if (analysisEvidence != null) {
        return _AnalysisEvidenceBubble(
          evidence: analysisEvidence,
          amberAccent: amberAccent,
        );
      }
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          decoration: BoxDecoration(
            color: cs.errorContainer.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            item.content,
            style: TextStyle(fontSize: 12, color: cs.onErrorContainer),
          ),
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

class _AnalysisEvidenceBubble extends StatelessWidget {
  final _AnalysisEvidenceView evidence;
  final Color amberAccent;

  const _AnalysisEvidenceBubble({
    required this.evidence,
    required this.amberAccent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.85,
        ),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: amberAccent.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    evidence.subjectLabel,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  evidence.confidence,
                  style: TextStyle(fontSize: 10, color: amberAccent),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${evidence.kind} · ${evidence.strategyReadiness}',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 6),
            _EvidenceSection(title: 'Observed', rows: evidence.observedFacts),
            _EvidenceSection(
              title: 'Interpretation',
              rows: evidence.interpretations,
            ),
            _EvidenceSection(
              title: 'Missing',
              rows: evidence.missingEvidence,
              muted: true,
            ),
            if (evidence.coverageLine.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                evidence.coverageLine,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.48),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _EvidenceSection extends StatelessWidget {
  final String title;
  final List<String> rows;
  final bool muted;

  const _EvidenceSection({
    required this.title,
    required this.rows,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = muted
        ? cs.onSurface.withValues(alpha: 0.48)
        : cs.onSurface.withValues(alpha: 0.68);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 9,
              letterSpacing: 0.3,
              color: cs.onSurface.withValues(alpha: 0.45),
            ),
          ),
          if (rows.isEmpty)
            Text('-', style: TextStyle(fontSize: 10, color: color))
          else
            ...rows.take(4).map(
                  (row) => Text(
                    row,
                    style: TextStyle(fontSize: 10, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
        ],
      ),
    );
  }
}

class _AnalysisEvidenceView {
  final String kind;
  final String subjectLabel;
  final List<String> observedFacts;
  final List<String> interpretations;
  final List<String> missingEvidence;
  final String confidence;
  final String strategyReadiness;
  final String coverageLine;

  const _AnalysisEvidenceView({
    required this.kind,
    required this.subjectLabel,
    required this.observedFacts,
    required this.interpretations,
    required this.missingEvidence,
    required this.confidence,
    required this.strategyReadiness,
    required this.coverageLine,
  });
}

_AnalysisEvidenceView? _analysisEvidenceFromContent(String content) {
  try {
    final decoded = jsonDecode(content);
    if (decoded is! Map) return null;
    final evidence = decoded['analysisEvidence'] is Map
        ? decoded['analysisEvidence'] as Map
        : decoded;
    if (evidence['contract'] != 'analysis-evidence-v1') return null;
    final subject = evidence['subject'] is Map ? evidence['subject'] as Map : {};
    final coverage = evidence['sourceCoverage'] is Map
        ? evidence['sourceCoverage'] as Map
        : {};
    final id = '${subject['id'] ?? ''}';
    final name = '${subject['name'] ?? ''}';
    final type = '${subject['type'] ?? ''}';
    final sources = _stringList(coverage['sources']);
    final coverageParts = <String>[
      if (sources.isNotEmpty) 'sources: ${sources.join(', ')}',
      if ('${coverage['interfaceId'] ?? ''}'.isNotEmpty)
        'interface: ${coverage['interfaceId']}',
      if ('${coverage['canonicalTable'] ?? ''}'.isNotEmpty)
        'table: ${coverage['canonicalTable']}',
      if ('${coverage['readbackAction'] ?? ''}'.isNotEmpty)
        'readback: ${coverage['readbackAction']}',
      if ('${coverage['sourceDataTime'] ?? ''}'.isNotEmpty)
        'data: ${coverage['sourceDataTime']}',
      if ('${coverage['fetchedAt'] ?? ''}'.isNotEmpty)
        'fetched: ${coverage['fetchedAt']}',
      if ('${coverage['cacheStatus'] ?? ''}'.isNotEmpty)
        'cache: ${coverage['cacheStatus']}',
      if ('${coverage['coverageStatus'] ?? ''}'.isNotEmpty)
        'coverage: ${coverage['coverageStatus']}',
    ];
    return _AnalysisEvidenceView(
      kind: '${evidence['kind'] ?? 'analysis'}',
      subjectLabel: name.isNotEmpty && id.isNotEmpty && name != id
          ? '$name ($id)'
          : id.isNotEmpty
              ? id
              : name.isNotEmpty
                  ? name
                  : type.isNotEmpty
                      ? type
                      : '-',
      observedFacts: _stringList(evidence['observedFacts']),
      interpretations: _stringList(evidence['interpretations']),
      missingEvidence: _stringList(evidence['missingEvidence']),
      confidence: '${evidence['confidence'] ?? '-'}',
      strategyReadiness: '${evidence['strategyReadiness'] ?? 'analysis_only'}',
      coverageLine: coverageParts.join(' · '),
    );
  } catch (_) {
    return null;
  }
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return value.map((item) => '$item').where((item) => item.isNotEmpty).toList();
}
