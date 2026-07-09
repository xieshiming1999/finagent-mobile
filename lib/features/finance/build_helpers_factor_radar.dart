part of 'finagent_screen.dart';

extension _BuildHelpersFactorRadar on _FinAgentScreenState {
  void _showFactorRadarPanel() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: FactorRadarSheet(
          basePath: widget.agent.toolContext.basePath,
          onAnalyze: (row) {
            final affected = _stringList(row['affected_assets']).join(', ');
            _controller.text = [
              'Use this macro research evidence as visible analysis context. Do not treat it as a trading signal.',
              'Title: ${row['title'] ?? '-'}',
              'Family: ${row['family'] ?? '-'}',
              'Source: ${row['source_name'] ?? '-'} (${row['source_type'] ?? '-'})',
              'Source time: ${row['source_published_at'] ?? row['event_at'] ?? '-'}',
              'Fetched at: ${row['fetched_at'] ?? '-'}',
              'Affected: ${affected.isEmpty ? '-' : affected}',
              'Status: ${row['status'] ?? '-'} / ${row['failure_class'] ?? 'ok'}',
              'Reliability: ${_reliabilityLine(row)}',
              'Asset impact: ${_assetImpactLine(row)}',
              'Decision support: ${_decisionSupportLine(row)}',
              if ((row['summary']?.toString() ?? '').isNotEmpty)
                'Summary: ${row['summary']}',
            ].join('\n');
            Navigator.of(ctx).pop();
            _send();
          },
        ),
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
  String _query = '';
  String _sourceFilter = 'all';
  String _familyFilter = 'all';
  String _statusFilter = 'all';
  String _assetFilter = 'all';
  String _regionFilter = 'all';
  String _retrievalFilter = 'all';

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
    final numericSeriesCatalog =
        _result?.numericSeriesCatalog ?? const <Map<String, dynamic>>[];
    final activeRows = rows
        .where(
          (row) =>
              row['failure_class'] == null && row['status'] != 'unsupported',
        )
        .length;
    final blockedRows = rows.length - activeRows;
    final filteredRows = _filterRows(
      rows,
      query: _query,
      source: _sourceFilter,
      family: _familyFilter,
      status: _statusFilter,
      asset: _assetFilter,
      region: _regionFilter,
      retrieval: _retrievalFilter,
    );
    final groupedRows = _groupRows(filteredRows);
    final sourceOptions = _uniqueOptions(
      rows.map((row) => row['source_name']?.toString()),
    );
    final familyOptions = _uniqueOptions(
      rows.map((row) => row['family']?.toString()),
    );
    final assetOptions = _uniqueOptions(
      rows.expand((row) => _stringList(row['affected_assets'])),
    );
    final regionOptions = _uniqueOptions(
      rows.expand((row) => _stringList(row['affected_regions'])),
    );
    final retrievalOptions = _uniqueOptions(
      rows.map((row) => _retrievalMode(row)),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.factorRadar),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: _refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: l10n.refresh,
            onPressed: _refreshing ? null : _refresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.macroResearchGenerated}: ${_result?.generatedAt ?? '-'}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _FactorMetric(
                      label: l10n.macroFactorActive,
                      value: '$activeRows',
                    ),
                    const SizedBox(width: 8),
                    _FactorMetric(
                      label: l10n.macroFactorBlocked,
                      value: '$blockedRows',
                    ),
                    const SizedBox(width: 8),
                    _FactorMetric(
                      label: l10n.macroFactorSources,
                      value: '${sources.length}',
                    ),
                    const SizedBox(width: 8),
                    _FactorMetric(
                      label: l10n.macroNumericSeries,
                      value: '${numericSeriesCatalog.length}',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  decoration: InputDecoration(
                    labelText: l10n.macroResearchSearch,
                    hintText: l10n.macroResearchSearchPlaceholder,
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() => _query = value),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _FilterChipDropdown(
                      label: l10n.macroResearchFilterSource,
                      value: _sourceFilter,
                      options: sourceOptions,
                      allLabel: l10n.macroResearchFilterAll,
                      onChanged: (value) =>
                          setState(() => _sourceFilter = value),
                    ),
                    _FilterChipDropdown(
                      label: l10n.macroResearchFilterFamily,
                      value: _familyFilter,
                      options: familyOptions,
                      allLabel: l10n.macroResearchFilterAll,
                      onChanged: (value) =>
                          setState(() => _familyFilter = value),
                    ),
                    _FilterChipDropdown(
                      label: l10n.macroResearchFilterStatus,
                      value: _statusFilter,
                      options: const [
                        'active',
                        'usable',
                        'watch',
                        'blocked',
                        'unsupported',
                      ],
                      allLabel: l10n.macroResearchFilterAll,
                      onChanged: (value) =>
                          setState(() => _statusFilter = value),
                    ),
                    _FilterChipDropdown(
                      label: l10n.macroResearchFilterAsset,
                      value: _assetFilter,
                      options: assetOptions,
                      allLabel: l10n.macroResearchFilterAll,
                      onChanged: (value) =>
                          setState(() => _assetFilter = value),
                    ),
                    _FilterChipDropdown(
                      label: l10n.macroResearchFilterRegion,
                      value: _regionFilter,
                      options: regionOptions,
                      allLabel: l10n.macroResearchFilterAll,
                      onChanged: (value) =>
                          setState(() => _regionFilter = value),
                    ),
                    _FilterChipDropdown(
                      label: l10n.macroResearchFilterRetrieval,
                      value: _retrievalFilter,
                      options: retrievalOptions,
                      allLabel: l10n.macroResearchFilterAll,
                      onChanged: (value) =>
                          setState(() => _retrievalFilter = value),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.macroResearchFilterHint,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
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
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                    children: [
                      _SectionTitle(l10n.macroResearchSourceCoverage),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.macroResearchSourceStateHint,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      ...sources.take(12).map((source) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SourceStatusCard(source: source),
                        );
                      }),
                      const SizedBox(height: 8),
                      _SectionTitle(l10n.macroNumericSeries),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          l10n.macroNumericSeriesHint,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      ...numericSeriesCatalog.map((series) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _NumericSeriesCard(series: series),
                        );
                      }),
                      const SizedBox(height: 8),
                      _SectionTitle(l10n.macroResearchEvidence),
                      if (filteredRows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            l10n.macroResearchNoFilteredEvidence,
                            style: TextStyle(
                              color: cs.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      for (final entry in groupedRows.entries) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 6),
                          child: Text(
                            entry.key,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        ...entry.value.map(
                          (row) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _FactorRowCard(
                              row: row,
                              onAnalyze: () => widget.onAnalyze(row),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final String allLabel;
  final ValueChanged<String> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.allLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem(value: 'all', child: Text(allLabel)),
        ...options.map(
          (option) => DropdownMenuItem(value: option, child: Text(option)),
        ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _FilterChipDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> options;
  final String allLabel;
  final ValueChanged<String> onChanged;

  const _FilterChipDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.allLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 156,
      child: _FilterDropdown(
        label: label,
        value: value,
        options: options,
        allLabel: allLabel,
        onChanged: onChanged,
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
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
            Text(value, style: TextStyle(color: cs.onSurface, fontSize: 14)),
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

class _SourceStatusCard extends StatelessWidget {
  final Map<String, dynamic> source;

  const _SourceStatusCard({required this.source});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = source['state']?.toString() ?? '-';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  source['name']?.toString() ?? '-',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  source['detail']?.toString() ?? '-',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _chip(context, state),
        ],
      ),
    );
  }
}

class _NumericSeriesCard extends StatelessWidget {
  final Map<String, dynamic> series;

  const _NumericSeriesCard({required this.series});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final credential = series['credentialKey']?.toString();
    final status = series['status']?.toString() ?? '-';
    final provider = series['sourceName'] ?? series['provider'] ?? '-';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  series['metricName']?.toString() ??
                      series['seriesId']?.toString() ??
                      '-',
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$provider · ${series['seriesId'] ?? '-'} · ${series['frequency'] ?? '-'} · ${series['unit'] ?? '-'}',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  credential == null || credential.isEmpty
                      ? l10n.macroNoCredentialRequired
                      : '${l10n.macroCredentialKey}: $credential',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
                const SizedBox(height: 4),
                Text(
                  series['nextAction']?.toString() ?? '-',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _chip(context, status),
        ],
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
        borderRadius: BorderRadius.circular(8),
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
          const SizedBox(height: 10),
          _DetailBox(
            title: l10n.macroResearchProvenance,
            lines: [
              '${row['source_name'] ?? '-'} / ${row['source_type'] ?? '-'}',
              '${l10n.sourceTimeLabel}: ${row['source_published_at'] ?? row['event_at'] ?? '-'}',
              '${l10n.provenanceFetched}: ${row['fetched_at'] ?? '-'}',
              'evidence tier: ${_evidenceTier(row)}',
              'status: ${row['status'] ?? '-'} / ${failure ?? 'ok'}',
              '${l10n.macroResearchRetrievalMode}: ${_retrievalMode(row)}',
            ],
          ),
          const SizedBox(height: 8),
          _DetailBox(
            title: l10n.macroResearchReliability,
            lines: [
              'tier: ${_evidenceTier(row)}',
              'source type: ${_sourceType(row)}',
              'freshness: ${_freshnessStatus(row)}',
              'access: ${_accessStatus(row)}',
              'confidence: ${_confidenceLevel(row)}',
            ],
          ),
          const SizedBox(height: 8),
          _DetailBox(
            title: l10n.macroFactorAffected,
            lines: [
              _stringList(row['affected_assets']).join(', '),
              _stringList(row['affected_regions']).join(', '),
              _stringList(row['affected_sectors']).join(', '),
            ].where((line) => line.trim().isNotEmpty).toList(),
          ),
          const SizedBox(height: 8),
          _DetailBox(
            title: l10n.macroResearchAssetImpact,
            lines: [
              'impact: ${_impactDirection(row)}',
              'strategy/fund channel: ${_joinedOr(row['transmission_channels'], 'needs-linking')}',
              'linked evidence: ${_joinedOr(row['linked_macro_evidence_ids'], '-')}',
            ],
          ),
          const SizedBox(height: 8),
          _DetailBox(
            title: l10n.macroResearchChannels,
            lines: [
              _stringList(row['transmission_channels']).join(', '),
              ..._stringList(row['limitations']),
              _linkedEvidenceLine(row),
            ],
          ),
          const SizedBox(height: 8),
          _DetailBox(
            title: l10n.macroResearchDecisionSupport,
            lines: [
              'confidence effect: ${_confidenceEffect(row)}',
              'missing evidence: ${_missingEvidence(row)}',
              'next action: ${_nextEvidenceAction(row)}',
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _chip(context, row['family']),
              _chip(context, row['source_name']),
              _chip(context, row['source_type']),
              _chip(context, _evidenceTier(row)),
              _chip(context, row['status']),
              if (failure != null) _chip(context, failure),
            ],
          ),
          const SizedBox(height: 8),
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
}

class _DetailBox extends StatelessWidget {
  final String title;
  final List<String> lines;

  const _DetailBox({required this.title, required this.lines});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visibleLines = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: cs.surfaceContainerHighest.withValues(alpha: 0.38),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: cs.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          if (visibleLines.isEmpty)
            Text(
              '-',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
            )
          else
            ...visibleLines.map(
              (line) => Text(
                line,
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

Widget _chip(BuildContext context, Object? value) {
  if (value == null || value.toString().isEmpty) return const SizedBox.shrink();
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

Map<String, List<Map<String, dynamic>>> _groupRows(
  List<Map<String, dynamic>> rows,
) {
  final grouped = <String, List<Map<String, dynamic>>>{};
  for (final row in rows) {
    final family = row['family']?.toString();
    final key = family == null || family.isEmpty ? 'macro_research' : family;
    grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
  }
  return grouped;
}

List<Map<String, dynamic>> _filterRows(
  List<Map<String, dynamic>> rows, {
  required String query,
  required String source,
  required String family,
  required String status,
  required String asset,
  required String region,
  required String retrieval,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  return rows.where((row) {
    if (source != 'all' && row['source_name']?.toString() != source) {
      return false;
    }
    if (family != 'all' && row['family']?.toString() != family) return false;
    if (asset != 'all' &&
        !_stringList(row['affected_assets']).contains(asset)) {
      return false;
    }
    if (region != 'all' &&
        !_stringList(row['affected_regions']).contains(region)) {
      return false;
    }
    if (retrieval != 'all' && _retrievalMode(row) != retrieval) return false;
    if (status != 'all') {
      final effectiveStatus = row['failure_class'] != null
          ? 'blocked'
          : row['status']?.toString() ?? '';
      if (effectiveStatus != status) return false;
    }
    if (normalizedQuery.isEmpty) return true;
    final haystack = [
      row['factor_id'],
      row['family'],
      row['title'],
      row['summary'],
      row['source_name'],
      row['source_type'],
      row['status'],
      row['failure_class'],
      _retrievalMode(row),
      ..._stringList(row['affected_assets']),
      ..._stringList(row['affected_regions']),
      ..._stringList(row['affected_sectors']),
      ..._stringList(row['transmission_channels']),
    ].map((value) => value.toString().toLowerCase());
    return haystack.any((value) => value.contains(normalizedQuery));
  }).toList();
}

String _retrievalMode(Map<String, dynamic> row) {
  final retrieval = row['retrieval_test'];
  if (retrieval is Map) {
    final status = retrieval['status']?.toString().trim() ?? '';
    if (status.isNotEmpty) return status;
  }
  final failure = row['failure_class']?.toString().trim() ?? '';
  if (failure.isNotEmpty) return failure;
  final sourceType = row['source_type']?.toString().trim() ?? '';
  if (sourceType.isNotEmpty) return sourceType;
  return 'unknown';
}

String _evidenceTier(Map<String, dynamic> row) {
  final explicit = row['evidence_tier']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final sourceType = row['source_type']?.toString().toLowerCase() ?? '';
  if (RegExp(
    r'official_api|official_series|official_document',
  ).hasMatch(sourceType)) {
    return 'official_numeric_or_document';
  }
  if (RegExp(r'research|content').hasMatch(sourceType)) {
    return 'content_backed_research';
  }
  if (sourceType.contains('news')) return 'linked_news_evidence';
  if (RegExp(r'manual|licensed|fallback').hasMatch(sourceType)) {
    return 'retrieval_or_manual_evidence';
  }
  if (row['failure_class'] != null) return 'missing_or_blocked';
  return 'governed_macro_evidence';
}

String _reliabilityLine(Map<String, dynamic> row) {
  return [
    'tier=${_evidenceTier(row)}',
    'sourceType=${_sourceType(row)}',
    'freshness=${_freshnessStatus(row)}',
    'access=${_accessStatus(row)}',
    'confidence=${_confidenceLevel(row)}',
  ].join(' / ');
}

String _assetImpactLine(Map<String, dynamic> row) {
  return [
    'impact=${_impactDirection(row)}',
    'assets=${_joinedOr(row['affected_assets'], '-')}',
    'regions=${_joinedOr(row['affected_regions'], '-')}',
    'sectors=${_joinedOr(row['affected_sectors'], '-')}',
    'channels=${_joinedOr(row['transmission_channels'], '-')}',
  ].join(' / ');
}

String _decisionSupportLine(Map<String, dynamic> row) {
  return [
    'confidenceEffect=${_confidenceEffect(row)}',
    'missing=${_missingEvidence(row)}',
    'next=${_nextEvidenceAction(row)}',
  ].join(' / ');
}

String _sourceType(Map<String, dynamic> row) {
  final value = row['source_type']?.toString().trim() ?? '';
  if (value.isNotEmpty) return value;
  final tier = _evidenceTier(row);
  if (tier.contains('official_numeric')) return 'official_data';
  if (tier.contains('official')) return 'official_event';
  if (tier.contains('research')) return 'research';
  if (tier.contains('news')) return 'news';
  if (tier.contains('retrieval')) return 'retrieval-only';
  return 'macro';
}

String _accessStatus(Map<String, dynamic> row) {
  final explicit = row['access_status']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final retrieval = row['retrieval_test'];
  final value =
      [
            if (retrieval is Map) retrieval['accessStatus'],
            if (retrieval is Map) retrieval['access_class'],
            if (retrieval is Map) retrieval['status'],
            row['failure_class'],
            row['status'],
          ]
          .map((value) => value?.toString().toLowerCase() ?? '')
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');
  if (value.isEmpty) return 'public';
  if (value.contains('api-key')) return 'api-key-required';
  if (value.contains('credential') || value.contains('quota')) {
    return 'credential-gated';
  }
  if (value.contains('manual')) return 'manual-browser';
  if (value.contains('anti-bot')) return 'anti-bot';
  if (value.contains('security') || value.contains('blocked')) {
    return 'security-blocked';
  }
  if (value.contains('do-not-scrape')) return 'do-not-scrape';
  if (value.contains('licensed') || value.contains('paywall')) {
    return 'licensed-needed';
  }
  if (row['failure_class'] != null) return 'security-blocked';
  return 'public';
}

String _freshnessStatus(Map<String, dynamic> row) {
  final explicit = row['freshness_status']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final access = _accessStatus(row);
  if (RegExp(
    r'(blocked|manual|anti-bot|licensed|do-not-scrape|security)',
  ).hasMatch(access)) {
    return 'blocked';
  }
  final source = DateTime.tryParse(
    '${row['source_published_at'] ?? row['event_at'] ?? ''}',
  );
  final fetched = DateTime.tryParse('${row['fetched_at'] ?? ''}');
  if (source == null && fetched == null) return 'missing';
  if (source == null || fetched == null) return 'acceptable';
  final days = fetched.difference(source).inHours.abs() / 24;
  if (days <= 7) return 'fresh';
  if (days <= 60) return 'acceptable';
  return 'stale';
}

String _confidenceLevel(Map<String, dynamic> row) {
  final explicit = row['confidence']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final tier = _evidenceTier(row);
  final access = _accessStatus(row);
  final freshness = _freshnessStatus(row);
  if (tier.contains('missing') ||
      access != 'public' ||
      freshness == 'blocked' ||
      freshness == 'missing') {
    return 'low';
  }
  if (tier.contains('official') && freshness != 'stale') return 'high';
  if (tier.contains('research') || tier.contains('news')) return 'medium';
  return 'low';
}

String _impactDirection(Map<String, dynamic> row) {
  final explicit = row['asset_impact']?.toString().trim() ?? '';
  if (explicit.isNotEmpty) return explicit;
  final value = row['expected_direction']?.toString().toLowerCase() ?? '';
  if (RegExp(r'(positive|tailwind|利好|上行)').hasMatch(value)) {
    return 'positive tailwind';
  }
  if (RegExp(r'(negative|headwind|利空|下行)').hasMatch(value)) {
    return 'negative headwind';
  }
  if (RegExp(r'(mixed|分化|双向)').hasMatch(value)) return 'mixed';
  if (RegExp(r'(watch|monitor|观察)').hasMatch(value)) return 'watch-only';
  return _stringList(row['affected_assets']).isNotEmpty
      ? 'watch-only'
      : 'no direct relevance';
}

String _confidenceEffect(Map<String, dynamic> row) {
  final explicitField = row['confidence_effect']?.toString().trim() ?? '';
  if (explicitField.isNotEmpty) return explicitField;
  final retrieval = row['retrieval_test'];
  final explicit = retrieval is Map
      ? retrieval['confidenceEffect']?.toString().trim() ?? ''
      : '';
  if (explicit.isNotEmpty) return explicit;
  final freshness = _freshnessStatus(row);
  final access = _accessStatus(row);
  if (row['failure_class'] != null || freshness == 'missing') {
    return 'insufficient evidence';
  }
  if (access != 'public' || freshness == 'blocked' || freshness == 'stale') {
    return 'lowers confidence';
  }
  if (_evidenceTier(row).contains('official') && freshness == 'fresh') {
    return 'raises confidence';
  }
  if (_evidenceTier(row).contains('news')) return 'neutral';
  return 'mixed';
}

String _missingEvidence(Map<String, dynamic> row) {
  final explicitField = row['missing_evidence']?.toString().trim() ?? '';
  if (explicitField.isNotEmpty) return explicitField;
  final retrieval = row['retrieval_test'];
  final value = retrieval is Map
      ? retrieval['missingEvidence']?.toString().trim() ?? ''
      : '';
  if (value.isNotEmpty) return value;
  final failure = row['failure_class']?.toString().trim() ?? '';
  if (failure.isNotEmpty) return failure;
  final limitations = _stringList(row['limitations']).join('; ');
  return limitations.isEmpty ? '-' : limitations;
}

String _nextEvidenceAction(Map<String, dynamic> row) {
  final explicitField = row['next_evidence_action']?.toString().trim() ?? '';
  if (explicitField.isNotEmpty) return explicitField;
  final retrieval = row['retrieval_test'];
  final explicit = retrieval is Map
      ? (retrieval['nextAction'] ?? retrieval['next_action'])
                ?.toString()
                .trim() ??
            ''
      : '';
  if (explicit.isNotEmpty) return explicit;
  final access = _accessStatus(row);
  final freshness = _freshnessStatus(row);
  if (row['failure_class'] != null) {
    return 'do not retry automatically; inspect source boundary';
  }
  if (RegExp(
    r'(manual|anti-bot|licensed|do-not-scrape|security)',
  ).hasMatch(access)) {
    return 'manual-browser evidence or do not retry';
  }
  if (access == 'credential-gated' || access == 'api-key-required') {
    return 'configure credential then serial probe';
  }
  if (freshness == 'stale' || freshness == 'missing') {
    return 'refresh allowed source then readback';
  }
  return 'use cache/readback';
}

String _linkedEvidenceLine(Map<String, dynamic> row) {
  final linked = _stringList(row['linked_macro_evidence_ids']);
  if (linked.isEmpty) return '';
  return 'linked macro evidence: ${linked.join(', ')}';
}

List<String> _uniqueOptions(Iterable<String?> values) {
  final options = values
      .map((value) => value?.trim() ?? '')
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  options.sort();
  return options;
}

List<String> _stringList(Object? value) {
  if (value is List) return value.map((item) => item.toString()).toList();
  return const [];
}

String _joinedOr(Object? value, String fallback) {
  final joined = _stringList(value).join(', ');
  return joined.isEmpty ? fallback : joined;
}
