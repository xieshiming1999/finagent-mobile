part of 'finagent_screen.dart';

extension _BuildHelpersFactorRadar on _FinAgentScreenState {
  void _showFactorRadarPanel() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => FactorRadarSheet(
        basePath: widget.agent.toolContext.basePath,
        onAnalyze: (row) {
          final affected = _stringList(row['affected_assets']).join(', ');
          _controller.text = [
            'Use this macro factor as visible analysis evidence. Do not treat it as a trading signal.',
            'Title: ${row['title'] ?? '-'}',
            'Family: ${row['family'] ?? '-'}',
            'Source: ${row['source_name'] ?? '-'} (${row['source_type'] ?? '-'})',
            'Source time: ${row['source_published_at'] ?? row['event_at'] ?? '-'}',
            'Fetched at: ${row['fetched_at'] ?? '-'}',
            'Affected: ${affected.isEmpty ? '-' : affected}',
            'Status: ${row['status'] ?? '-'} / ${row['failure_class'] ?? 'ok'}',
            if ((row['summary']?.toString() ?? '').isNotEmpty)
              'Summary: ${row['summary']}',
          ].join('\n');
          Navigator.of(ctx).pop();
          _send();
        },
      ),
    );
  }
}

class FactorRadarSheet extends StatefulWidget {
  final String basePath;
  final ValueChanged<Map<String, dynamic>> onAnalyze;
  final MacroFactorRadarService? service;

  const FactorRadarSheet({
    super.key,
    required this.basePath,
    required this.onAnalyze,
    this.service,
  });

  @override
  State<FactorRadarSheet> createState() => _FactorRadarSheetState();
}

class _FactorRadarSheetState extends State<FactorRadarSheet> {
  late final ReusableDataStore _store;
  MacroFactorRadarService? _service;
  MacroFactorRadarResult? _result;
  String? _error;
  bool _loading = true;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _store = ReusableDataStore(widget.basePath);
    if (widget.service != null) {
      _service = widget.service;
      _load();
      return;
    }
    _init();
  }

  Future<void> _init() async {
    final config = ApiConfigStore();
    await config.load();
    _service = MacroFactorRadarService(store: _store, apiConfig: config);
    _load();
  }

  void _load() {
    try {
      final result = _service?.read();
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = result?.error;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    try {
      final result = await _service?.refresh();
      if (!mounted) return;
      setState(() {
        _result = result;
        _error = result?.error;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final rows = _result?.rows ?? const <Map<String, dynamic>>[];
    final sources = _result?.sources ?? const <Map<String, dynamic>>[];
    final activeRows = rows
        .where(
          (row) =>
              row['failure_class'] == null && row['status'] != 'unsupported',
        )
        .length;
    final blockedRows = rows.length - activeRows;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.76,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
            child: Row(
              children: [
                Icon(Icons.radar_outlined, size: 18, color: cs.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.factorRadar,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: _refreshing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  tooltip: l10n.refresh,
                  onPressed: _refreshing ? null : _refresh,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _FactorMetric(
                  label: l10n.macroFactorSources,
                  value: '${sources.length}',
                ),
                const SizedBox(width: 8),
                _FactorMetric(
                  label: l10n.macroFactorActive,
                  value: '$activeRows',
                ),
                const SizedBox(width: 8),
                _FactorMetric(
                  label: l10n.macroFactorBlocked,
                  value: '$blockedRows',
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 12, color: cs.error),
              ),
            ),
          Expanded(
            child: _loading
                ? Center(child: Text(l10n.macroFactorLoading))
                : rows.isEmpty
                ? Center(child: Text(l10n.macroFactorEmpty))
                : ListView.separated(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(12),
                    itemBuilder: (_, index) => _FactorRowCard(
                      row: rows[index],
                      onAnalyze: () => widget.onAnalyze(rows[index]),
                    ),
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 8),
                    itemCount: rows.length,
                  ),
          ),
        ],
      ),
    );
  }
}

class _FactorMetric extends StatelessWidget {
  final String label;
  final String value;

  const _FactorMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: cs.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: TextStyle(color: cs.onSurface, fontSize: 13)),
            Text(
              label,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactorRowCard extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback onAnalyze;

  const _FactorRowCard({required this.row, required this.onAnalyze});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final failure = row['failure_class']?.toString();
    final color = failure != null
        ? Colors.amber.shade700
        : row['severity'] == 'high'
        ? cs.error
        : cs.primary;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 5, right: 8),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              Expanded(
                child: Text(
                  row['title']?.toString() ?? '-',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            row['summary']?.toString() ?? '-',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip(context, row['family']),
              _chip(context, row['source_name']),
              _chip(context, row['source_type']),
              _chip(context, row['status']),
              if (failure != null) _chip(context, failure),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.sourceTimeLabel}: ${row['source_published_at'] ?? row['event_at'] ?? '-'} · ${l10n.provenanceFetched}: ${row['fetched_at'] ?? '-'}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
          Text(
            '${l10n.macroFactorAffected}: ${_stringList(row['affected_assets']).join(', ')}',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAnalyze,
              icon: const Icon(Icons.psychology_alt_outlined, size: 16),
              label: Text(l10n.macroFactorSendToAgent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, Object? value) {
    if (value == null || value.toString().isEmpty)
      return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: cs.surfaceContainerHighest,
      ),
      child: Text(
        value.toString(),
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
      ),
    );
  }
}

List<String> _stringList(Object? value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  return const [];
}
