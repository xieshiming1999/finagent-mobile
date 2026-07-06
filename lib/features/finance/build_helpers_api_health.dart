part of 'finagent_screen.dart';

extension _BuildHelpersApiHealth on _FinAgentScreenState {
  void _showApiHealthPanel() {
    _setState(() => _apiHealthPanelVisible = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ApiHealthSheet(
        basePath: widget.agent.toolContext.basePath,
        agent: widget.agent,
        dataTaskEngine: widget.dataTaskEngine,
      ),
    ).whenComplete(() {
      if (mounted) _setState(() => _apiHealthPanelVisible = false);
    });
  }
}

class _ApiHealthSheet extends StatefulWidget {
  final String basePath;
  final Agent agent;
  final DataTaskEngine dataTaskEngine;

  const _ApiHealthSheet({
    required this.basePath,
    required this.agent,
    required this.dataTaskEngine,
  });

  @override
  State<_ApiHealthSheet> createState() => _ApiHealthSheetState();
}

class _ApiHealthSheetState extends State<_ApiHealthSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Duration _range = const Duration(minutes: 30);
  late final GoalAutomationService _goalAutomation;
  late final http.Client _runtimeProbeHttpClient;
  late final EastMoneyAdvancedFetcher _runtimeProbeAdvancedFetcher;
  late final DataManager _runtimeProbeDataManager;
  late final MarketDataActionService _runtimeProbeActionService;
  late final MarketDataSupportService _runtimeProbeSupportService;
  late final MarketRuntimeProbeService _runtimeProbeService;
  ArtifactRecord? _schemaCensusRecord;
  Object? _schemaCensusError;
  Map<String, dynamic>? _runtimeProbeStatus;
  Map<String, dynamic>? _runtimeProbeLiveStatus;
  String? _runtimeProbeError;
  bool _runtimeProbeBusy = false;

  static const _ranges = [
    (Duration(minutes: 5), '5m'),
    (Duration(minutes: 10), '10m'),
    (Duration(minutes: 30), '30m'),
    (Duration(hours: 1), '1h'),
    (Duration(days: 1), '1d'),
    (Duration(days: 7), '7d'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 6, vsync: this);
    _goalAutomation = GoalAutomationService(
      basePath: widget.basePath,
      agent: widget.agent,
      dataTaskEngine: widget.dataTaskEngine,
    );
    _runtimeProbeHttpClient = http.Client();
    _runtimeProbeAdvancedFetcher = EastMoneyAdvancedFetcher();
    _runtimeProbeDataManager = DataManager(basePath: widget.basePath);
    _runtimeProbeActionService = MarketDataActionServiceFactory.create(
      dataManager: _runtimeProbeDataManager,
      httpClient: _runtimeProbeHttpClient,
      advancedFetcher: _runtimeProbeAdvancedFetcher,
    );
    _runtimeProbeSupportService = MarketDataSupportService(
      dataManager: _runtimeProbeDataManager,
      dataTaskEngine: widget.dataTaskEngine,
    );
    _runtimeProbeService = MarketRuntimeProbeService(
      dataManager: _runtimeProbeDataManager,
      runAction:
          (
            String action,
            List<String> symbols,
            Map<String, dynamic> input,
            ToolContext context,
          ) => _runtimeProbeActionService.run(action, symbols, input, context),
      getHealth: () =>
          _runtimeProbeSupportService.dataHealth(section: 'all', limit: 200),
    );
    _refreshSchemaCensus();
    _refreshRuntimeProbeStatus();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _runtimeProbeHttpClient.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: Row(
              children: [
                Text(
                  l10n.apiHealth,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 18, color: cs.error),
                  tooltip: l10n.clear,
                  onPressed: () {
                    ApiStats.instance.clear();
                    setState(() {});
                  },
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: l10n.refresh,
                  onPressed: () {
                    _refreshSchemaCensus();
                    _refreshRuntimeProbeStatus();
                    setState(() {});
                  },
                  constraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 28,
                  ),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
          SizedBox(
            height: 32,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              children: _ranges.map((r) {
                final selected = _range == r.$1;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(r.$2, style: const TextStyle(fontSize: 11)),
                    selected: selected,
                    onSelected: (_) => setState(() => _range = r.$1),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );
              }).toList(),
            ),
          ),
          TabBar(
            controller: _tabCtrl,
            tabs: [
              Tab(text: l10n.doctorTitle),
              Tab(text: l10n.allRequests),
              Tab(text: l10n.bySource),
              Tab(text: l10n.reusableData),
              Tab(text: l10n.dataTasks),
              Tab(text: l10n.goalAutomation),
            ],
            labelStyle: const TextStyle(fontSize: 12),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildDoctor(scrollCtrl),
                _buildRequestList(scrollCtrl),
                _buildSourceSummary(scrollCtrl),
                _buildReusableData(scrollCtrl),
                _buildDataTasks(scrollCtrl),
                _buildGoalAutomation(scrollCtrl),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDoctor(ScrollController scrollCtrl) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final report = buildFinanceDoctorReport(
      basePath: widget.basePath,
      dataTaskEngine: widget.dataTaskEngine,
      apiWindow: _range,
    );
    final runtimeHealth = _runtimeProbeSupportService.dataHealth(
      section: 'summary',
      limit: 20,
    );
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(8),
      children: [
        Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _doctorSummary(report, l10n),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _doctorStatusLabel(report.status, l10n),
                  style: TextStyle(
                    fontSize: 11,
                    color: _doctorStatusColor(report.status, cs),
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        _runtimeProbeCard(l10n, cs),
        _runtimeProbeQueueCard(runtimeHealth, l10n, cs),
        _dataContractCard(l10n, cs),
        ...report.checks.map((check) => _doctorCheckCard(check, l10n, cs)),
      ],
    );
  }

  Widget _runtimeProbeCard(AppLocalizations l10n, ColorScheme cs) {
    final status = _runtimeProbeStatus;
    final summary = _runtimeProbeLiveStatus?['summary'] is Map
        ? Map<String, dynamic>.from(
            _runtimeProbeLiveStatus!['summary'] as Map<dynamic, dynamic>,
          )
        : const <String, dynamic>{};
    final running = status?['running'] == true;
    final startedAt = _formatIso(status?['startedAt']?.toString());
    final finishedAt = _formatIso(status?['finishedAt']?.toString());
    final selectedCount = status?['selectedCount']?.toString() ?? '0';
    final stateLabel = running
        ? l10n.runtimeProbeRunning
        : l10n.runtimeProbeIdle;
    final summaryText =
        '${summary['passed'] ?? 0}/${summary['total'] ?? 0} ${l10n.passedLabel}';
    final recommendedTargets = _healthRows(status?['recommendedTargets']);
    final blockedTargets = _healthRows(status?['blockedTargets']);
    final providerPacks = _healthRows(status?['providerProbePacks']);
    final topTarget = recommendedTargets.isNotEmpty
        ? recommendedTargets.first
        : null;
    final topPack = providerPacks.isNotEmpty ? providerPacks.first : null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.runtimeProbeTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  stateLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    color: running
                        ? cs.primary
                        : cs.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.lastProbeRun}: ${finishedAt ?? startedAt ?? '-'}',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            Text(
              '${l10n.selectedProbes}: $selectedCount',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            Text(
              '${l10n.runtimeProbeSummary}: $summaryText',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            Text(
              '${l10n.recommendedProbeTargets}: ${recommendedTargets.length} · ${l10n.blockedProbeTargets}: ${blockedTargets.length} · ${l10n.providerProbePacks}: ${providerPacks.length}',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.55),
              ),
            ),
            if (topTarget != null)
              Text(
                '${topTarget['probeId'] ?? '-'} · ${topTarget['provider'] ?? '-'} · ${topTarget['nextAction'] ?? topTarget['reason'] ?? '-'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.62),
                ),
              ),
            if (topPack != null)
              Text(
                '${topPack['provider'] ?? '-'} · ${topPack['status'] ?? '-'} · ${topPack['schemaClassification'] ?? '-'}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.55),
                  fontFamily: 'monospace',
                ),
              ),
            if (_runtimeProbeError != null &&
                _runtimeProbeError!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                _runtimeProbeError!,
                style: TextStyle(fontSize: 10, color: cs.error),
              ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _runtimeProbeBusy
                      ? null
                      : _refreshRuntimeProbeStatus,
                  icon: const Icon(Icons.sync, size: 16),
                  label: Text(l10n.recheckProbeState),
                ),
                FilledButton.tonalIcon(
                  onPressed: _runtimeProbeBusy
                      ? null
                      : () => _runRuntimeProbe('credential'),
                  icon: const Icon(Icons.vpn_key_outlined, size: 16),
                  label: Text(l10n.runCredentialProbes),
                ),
                FilledButton.tonalIcon(
                  onPressed: _runtimeProbeBusy
                      ? null
                      : () => _runRuntimeProbe('unstable'),
                  icon: const Icon(Icons.network_check, size: 16),
                  label: Text(l10n.runUnstableProbes),
                ),
                FilledButton.tonalIcon(
                  onPressed: _runtimeProbeBusy
                      ? null
                      : () => _runRuntimeProbe('failures'),
                  icon: const Icon(Icons.error_outline, size: 16),
                  label: Text(l10n.runFailureProbes),
                ),
                FilledButton.icon(
                  onPressed: _runtimeProbeBusy
                      ? null
                      : () => _runRuntimeProbe('all'),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: Text(l10n.runAllProbes),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _runtimeProbeQueueCard(
    Map<String, dynamic> runtimeHealth,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    final providerGaps = _healthRows(runtimeHealth['providerGapQueue']);
    final credentialRows = _healthRows(
      runtimeHealth['credentialActivationQueue'],
    );
    final policyRows = _healthRows(runtimeHealth['policyDisabledQueue']);
    final failureRows = _healthRows(runtimeHealth['failureActionQueue']);
    final total =
        providerGaps.length +
        credentialRows.length +
        policyRows.length +
        failureRows.length;
    if (total == 0) {
      return const SizedBox.shrink();
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.runtimeHealthQueues,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            if (credentialRows.isNotEmpty)
              _runtimeQueueSection(
                title: l10n.credentialQueueTitle,
                rows: credentialRows,
                cs: cs,
                l10n: l10n,
              ),
            if (providerGaps.isNotEmpty)
              _runtimeQueueSection(
                title: l10n.providerGapQueueTitle,
                rows: providerGaps,
                cs: cs,
                l10n: l10n,
              ),
            if (policyRows.isNotEmpty)
              _runtimeQueueSection(
                title: l10n.policyDisabledQueueTitle,
                rows: policyRows,
                cs: cs,
                l10n: l10n,
              ),
            if (failureRows.isNotEmpty)
              _runtimeQueueSection(
                title: l10n.failureActionQueueTitle,
                rows: failureRows,
                cs: cs,
                l10n: l10n,
              ),
          ],
        ),
      ),
    );
  }

  Widget _runtimeQueueSection({
    required String title,
    required List<Map<String, dynamic>> rows,
    required ColorScheme cs,
    required AppLocalizations l10n,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title (${rows.length})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 4),
          ...rows.take(4).map((row) => _runtimeQueueRow(row, cs, l10n)),
        ],
      ),
    );
  }

  Widget _runtimeQueueRow(
    Map<String, dynamic> row,
    ColorScheme cs,
    AppLocalizations l10n,
  ) {
    final interfaceId =
        row['interfaceId']?.toString() ?? row['family']?.toString() ?? '-';
    final provider = row['provider']?.toString() ?? 'local';
    final status =
        row['status']?.toString() ?? row['failureClass']?.toString() ?? '-';
    final liveStatus = row['liveStatus']?.toString();
    final reason =
        row['presenceReason']?.toString() ??
        row['reason']?.toString() ??
        row['error']?.toString() ??
        '-';
    final nextAction = row['nextAction']?.toString() ?? '-';
    final moveOut = row['exitCondition']?.toString() ?? _moveOutCondition(row);
    final retryPolicy = row['retryPolicy']?.toString();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$interfaceId · $provider',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            [
              status,
              if (liveStatus != null && liveStatus.isNotEmpty)
                '${l10n.runtimeProbeTitle}: $liveStatus',
            ].join(' · '),
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.whyHereLabel}: $reason',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          Text(
            '${l10n.moveOutLabel}: $moveOut',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          Text(
            '${l10n.nextAction}: $nextAction',
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.62),
            ),
          ),
          if (retryPolicy != null && retryPolicy.isNotEmpty)
            Text(
              '${l10n.retryPolicyLabel}: $retryPolicy',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.62),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataContractCard(AppLocalizations l10n, ColorScheme cs) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.dataSurfaceContract,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            _schemaCensusSummary(l10n, cs),
            const SizedBox(height: 6),
            ...financeDataContractSteps.map((step) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '#${step.order}',
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withValues(alpha: 0.45),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _contractStepTitle(step.id, l10n),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _contractStepDetail(step.id, l10n),
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _refreshSchemaCensus() {
    try {
      _schemaCensusRecord = FinanceSchemaCensusRegistry(
        widget.basePath,
      ).register(runtime: 'finagent');
      _schemaCensusError = null;
    } catch (error) {
      _schemaCensusRecord = null;
      _schemaCensusError = error;
    }
  }

  void _refreshRuntimeProbeStatus() {
    try {
      final payload = _runtimeProbeService.status(widget.basePath);
      setState(() {
        _runtimeProbeStatus = Map<String, dynamic>.from(
          (payload['status'] as Map<dynamic, dynamic>?) ??
              const <String, dynamic>{},
        );
        _runtimeProbeLiveStatus = payload['liveStatus'] is Map
            ? Map<String, dynamic>.from(
                payload['liveStatus'] as Map<dynamic, dynamic>,
              )
            : null;
        _runtimeProbeError = null;
      });
    } catch (error) {
      setState(() {
        _runtimeProbeError = '$error';
      });
    }
  }

  Future<void> _runRuntimeProbe(String mode) async {
    setState(() {
      _runtimeProbeBusy = true;
      _runtimeProbeError = null;
    });
    try {
      final context = ToolContext(
        basePath: widget.basePath,
        serviceBaseUrl: widget.agent.toolContext.serviceBaseUrl,
        skipPermissions: true,
        approvedTools: widget.agent.toolContext.approvedTools,
        taskStore: widget.agent.toolContext.taskStore,
        taskRegistry: widget.agent.toolContext.taskRegistry,
        teamRegistry: widget.agent.toolContext.teamRegistry,
      );
      final payload = await _runtimeProbeService.run(
        widget.basePath,
        context,
        mode: mode,
      );
      setState(() {
        _runtimeProbeStatus = Map<String, dynamic>.from(
          (payload['status'] as Map<dynamic, dynamic>?) ??
              const <String, dynamic>{},
        );
        _runtimeProbeLiveStatus = payload['liveStatus'] is Map
            ? Map<String, dynamic>.from(
                payload['liveStatus'] as Map<dynamic, dynamic>,
              )
            : null;
      });
    } catch (error) {
      _runtimeProbeError = '$error';
    } finally {
      if (mounted) {
        setState(() {
          _runtimeProbeBusy = false;
        });
      }
    }
  }

  String? _formatIso(String? value) {
    if (value == null || value.trim().isEmpty || value == 'null') return null;
    try {
      return _formatTime(DateTime.parse(value).toLocal());
    } catch (_) {
      return value;
    }
  }

  List<Map<String, dynamic>> _healthRows(Object? rows) {
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) {
          return row.map((key, value) => MapEntry('$key', value));
        })
        .toList(growable: false);
  }

  String _moveOutCondition(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    final gapClass = row['gapClass']?.toString() ?? '';
    if (status == 'credential-gated' || status == 'quota-gated') {
      return AppLocalizations.of(context).moveOutCredentialConfigured;
    }
    if (status == 'disabled') {
      return AppLocalizations.of(context).moveOutPolicyChange;
    }
    if (gapClass == 'serial-live-retry') {
      return AppLocalizations.of(context).moveOutTransportRecovered;
    }
    if ((row['failureClass']?.toString() ?? '').isNotEmpty) {
      return AppLocalizations.of(context).moveOutRetrySucceeded;
    }
    return AppLocalizations.of(context).moveOutImplementedOrReclassified;
  }

  Widget _schemaCensusSummary(AppLocalizations l10n, ColorScheme cs) {
    final record = _schemaCensusRecord;
    if (record == null) {
      return Text(
        '${l10n.financeSchemaCensusTitle}: ${_schemaCensusError ?? l10n.unknown}',
        style: TextStyle(fontSize: 10, color: cs.error),
      );
    }
    final total = record.metadata['total'] ?? '-';
    final reusable = record.metadata['reusable'] ?? '-';
    final fetchOnly = record.metadata['fetchOnly'] ?? '-';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.financeSchemaCensusTitle,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.financeSchemaCensusDetail,
            style: TextStyle(
              fontSize: 10,
              color: cs.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _smallMetric(l10n.schemaSurfaces, '$total', cs),
              _smallMetric(l10n.schemaReusable, '$reusable', cs),
              _smallMetric(l10n.schemaFetchOnly, '$fetchOnly', cs),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.schemaArtifactRef}: ${record.stableRef}',
            style: TextStyle(
              fontSize: 9,
              fontFamily: 'monospace',
              color: cs.onSurface.withValues(alpha: 0.55),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _smallMetric(String label, String value, ColorScheme cs) {
    return Text(
      '$label $value',
      style: TextStyle(
        fontSize: 10,
        color: cs.onSurface.withValues(alpha: 0.72),
        fontFamily: 'monospace',
      ),
    );
  }

  String _contractStepTitle(
    FinanceDataContractStepId id,
    AppLocalizations l10n,
  ) {
    switch (id) {
      case FinanceDataContractStepId.dataClass:
        return l10n.surfaceDataClassTitle;
      case FinanceDataContractStepId.cachePolicy:
        return l10n.surfaceCachePolicyTitle;
      case FinanceDataContractStepId.providerPolicy:
        return l10n.surfaceProviderPolicyTitle;
      case FinanceDataContractStepId.normalizer:
        return l10n.surfaceNormalizerTitle;
      case FinanceDataContractStepId.persistTarget:
        return l10n.surfacePersistTargetTitle;
      case FinanceDataContractStepId.readbackAction:
        return l10n.surfaceReadbackActionTitle;
      case FinanceDataContractStepId.failureSink:
        return l10n.surfaceFailureSinkTitle;
      case FinanceDataContractStepId.uiSurface:
        return l10n.surfaceUiSurfaceTitle;
    }
  }

  String _contractStepDetail(
    FinanceDataContractStepId id,
    AppLocalizations l10n,
  ) {
    switch (id) {
      case FinanceDataContractStepId.dataClass:
        return l10n.surfaceDataClassDetail;
      case FinanceDataContractStepId.cachePolicy:
        return l10n.surfaceCachePolicyDetail;
      case FinanceDataContractStepId.providerPolicy:
        return l10n.surfaceProviderPolicyDetail;
      case FinanceDataContractStepId.normalizer:
        return l10n.surfaceNormalizerDetail;
      case FinanceDataContractStepId.persistTarget:
        return l10n.surfacePersistTargetDetail;
      case FinanceDataContractStepId.readbackAction:
        return l10n.surfaceReadbackActionDetail;
      case FinanceDataContractStepId.failureSink:
        return l10n.surfaceFailureSinkDetail;
      case FinanceDataContractStepId.uiSurface:
        return l10n.surfaceUiSurfaceDetail;
    }
  }

  Widget _doctorCheckCard(
    FinanceDoctorCheck check,
    AppLocalizations l10n,
    ColorScheme cs,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _doctorCheckLabel(check.id, l10n),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  _doctorStatusLabel(check.status, l10n),
                  style: TextStyle(
                    fontSize: 10,
                    color: _doctorStatusColor(check.status, cs),
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              check.detail,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.65),
              ),
            ),
            if (check.nextStep != null) ...[
              const SizedBox(height: 3),
              Text(
                '${l10n.nextStep}: ${check.nextStep}',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildGoalAutomation(ScrollController scrollCtrl) {
    final l10n = AppLocalizations.of(context);
    final rows = _goalAutomation.list();
    final suggestions = _goalAutomation.listSuggestions();
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(8),
      itemCount: rows.length + suggestions.length + 1,
      itemBuilder: (_, index) {
        if (index == 0) {
          return _buildAutomationSuggestionHeader(suggestions);
        }
        if (index <= suggestions.length) {
          return _buildAutomationSuggestionCard(suggestions[index - 1]);
        }
        final row = rows[index - suggestions.length - 1];
        final template = Map<String, dynamic>.from(row['template'] as Map);
        final state = Map<String, dynamic>.from(row['state'] as Map);
        final activeGoal = row['activeGoal'] is Map
            ? Map<String, dynamic>.from(row['activeGoal'] as Map)
            : null;
        final workPacket = activeGoal?['workPacket'] is Map
            ? Map<String, dynamic>.from(activeGoal!['workPacket'] as Map)
            : null;
        final artifact = activeGoal?['artifact'] is Map
            ? Map<String, dynamic>.from(activeGoal!['artifact'] as Map)
            : null;
        final id = template['id'] as String;
        final parsed = GoalTemplateIdWire.parse(id);
        if (parsed == null) return const SizedBox.shrink();
        final enabled = state['enabled'] == true;
        final paused = state['paused'] == true;
        final escalation = state['escalationNeeded'] == true;
        final failureCount = state['failureCount'] as int? ?? 0;
        final lastRunAt = state['lastRunAt'] as int?;
        final lastRun = lastRunAt == null
            ? '-'
            : _formatTime(DateTime.fromMillisecondsSinceEpoch(lastRunAt));
        final nextRunAt = state['nextRunAt'] as int?;
        final nextRun = nextRunAt == null
            ? '-'
            : _formatTime(DateTime.fromMillisecondsSinceEpoch(nextRunAt));
        final now = DateTime.now().millisecondsSinceEpoch;
        final cooldown = nextRunAt != null && nextRunAt > now
            ? _formatDuration(Duration(milliseconds: nextRunAt - now))
            : '-';
        final trigger = (state['lastTrigger'] ?? '-').toString();
        final evidence =
            (state['lastTriggerEvidence'] ?? template['objective'] ?? '-')
                .toString();
        final checkpoint = state['lastCheckpoint'] == null
            ? '-'
            : _compactPath(state['lastCheckpoint'].toString());
        final last = (state['lastError'] ?? state['lastResult'] ?? '-')
            .toString();
        final workGap = workPacket == null
            ? null
            : [
                if ((workPacket['progressKind'] ?? '').toString().isNotEmpty &&
                    workPacket['progressKind'] != 'unknown')
                  '${workPacket['progressKind']}:',
                workPacket['currentGap'] ?? '-',
              ].join(' ');
        final nextAction = workPacket?['nextPrompt']?.toString();
        final taskSummary = activeGoal == null
            ? null
            : _goalTaskSummary(
                template: template,
                activeGoal: activeGoal,
                artifact: artifact,
                workPacket: workPacket,
              );
        final ledger = state['triggerLedger'];
        final decisionHistory = ledger is List
            ? ledger
                  .take(30)
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
            : <Map<String, dynamic>>[];
        final latestDecision = decisionHistory.isNotEmpty
            ? decisionHistory.first
            : null;
        final decisionText = latestDecision == null
            ? '-'
            : '${_formatTime(DateTime.fromMillisecondsSinceEpoch((latestDecision['at'] as num?)?.toInt() ?? 0))} · '
                  '${latestDecision['status'] ?? '-'} · '
                  '${latestDecision['reason'] ?? '-'}'
                  '${((latestDecision['repeatCount'] as num?)?.toInt() ?? 1) > 1 ? ' (${latestDecision['repeatCount']}x)' : ''}';
        final cs = Theme.of(context).colorScheme;
        final statusColor = escalation
            ? Colors.red
            : enabled
            ? Colors.green
            : cs.onSurface.withValues(alpha: 0.5);

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        template['title'] as String? ?? id,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Switch(
                      value: enabled,
                      onChanged: (value) {
                        _goalAutomation.setEnabled(parsed, value);
                        setState(() {});
                      },
                    ),
                  ],
                ),
                Text(
                  [
                    enabled ? l10n.enabled : l10n.disabled,
                    if (paused) l10n.paused,
                    if (escalation) l10n.escalationNeeded,
                    if (failureCount > 0) '$failureCount ${l10n.failed}',
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 10,
                    color: statusColor,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${l10n.lastRun}: $lastRun',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  '${l10n.nextRun}: $nextRun',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  '${l10n.cooldown}: $cooldown',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  '${l10n.trigger}: $trigger',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                Text(
                  '${l10n.checkpoint}: $checkpoint',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${l10n.triggerEvidence}: $evidence',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${l10n.recentDecision}: $decisionText',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (workGap != null) ...[
                  Text(
                    '${l10n.currentWorkGap}: $workGap',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.55),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (nextAction != null)
                    Text(
                      '${l10n.nextAction}: $nextAction',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.55),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
                if (taskSummary != null)
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        l10n.taskGoalView,
                        style: TextStyle(
                          fontSize: 10,
                          color: cs.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      children: taskSummary.entries.map((entry) {
                        return Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '${entry.key}: ${entry.value}',
                            style: TextStyle(
                              fontSize: 10,
                              color: cs.onSurface.withValues(alpha: 0.55),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      '${l10n.decisionHistory} (${decisionHistory.length})',
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    children: decisionHistory.isEmpty
                        ? [
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                l10n.noDecisionHistory,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurface.withValues(alpha: 0.55),
                                ),
                              ),
                            ),
                          ]
                        : decisionHistory.map((entry) {
                            final at = (entry['at'] as num?)?.toInt() ?? 0;
                            final next = (entry['nextRunAt'] as num?)?.toInt();
                            final repeats =
                                (entry['repeatCount'] as num?)?.toInt() ?? 1;
                            final repeatText = repeats > 1
                                ? ' (${repeats}x)'
                                : '';
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  [
                                    '${at == 0 ? '-' : _formatTime(DateTime.fromMillisecondsSinceEpoch(at))} · ${entry['status'] ?? '-'}$repeatText · ${entry['resolvedTrigger'] ?? '-'}',
                                    '${entry['reason'] ?? '-'}',
                                    if (entry['evidence'] != null)
                                      '${l10n.triggerEvidence}: ${entry['evidence']}',
                                    if (next != null)
                                      '${l10n.nextRun}: ${_formatTime(DateTime.fromMillisecondsSinceEpoch(next))}',
                                  ].join('\n'),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: cs.onSurface.withValues(alpha: 0.55),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                  ),
                ),
                Text(
                  '${l10n.lastResult}: $last',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.55),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        final result = _goalAutomation.runNow(parsed);
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(result.reason)));
                        setState(() {});
                      },
                      icon: const Icon(Icons.play_arrow, size: 16),
                      label: Text(l10n.runNow),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        _goalAutomation.pause(parsed, !paused);
                        setState(() {});
                      },
                      icon: Icon(
                        paused
                            ? Icons.play_circle_outline
                            : Icons.pause_circle_outline,
                        size: 16,
                      ),
                      label: Text(paused ? l10n.resume : l10n.pause),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Map<String, String> _goalTaskSummary({
    required Map<String, dynamic> template,
    required Map<String, dynamic> activeGoal,
    required Map<String, dynamic>? artifact,
    required Map<String, dynamic>? workPacket,
  }) {
    final l10n = AppLocalizations.of(context);
    final contextNeeds = _stringList(template['contextNeeds']);
    final guardrails = _stringList(template['guardrails']);
    final criteria = <String>{
      ..._stringList(artifact?['doneCriteria']),
      ..._stringList(activeGoal['successCriteria']),
    }.toList();
    final verifier = activeGoal['verifierResult'] is Map
        ? Map<String, dynamic>.from(activeGoal['verifierResult'] as Map)
        : null;
    final evidence = <String>[
      ..._stringList(workPacket?['evidence']),
      ..._stringList(verifier?['evidence']),
      if (activeGoal['contextPackPath'] != null)
        _compactPath(activeGoal['contextPackPath'].toString()),
      if (activeGoal['checkpoint'] != null)
        _compactPath(activeGoal['checkpoint'].toString()),
    ].where((item) => item.trim().isNotEmpty).take(6).toList();
    final tokenBudget = activeGoal['tokenBudget'] as int?;
    final tokensUsed = activeGoal['tokensUsed'] as int? ?? 0;
    final turnsUsed = activeGoal['turnsUsed'] as int? ?? 0;
    final maxTurns = activeGoal['maxTurns'] as int? ?? 0;
    final budget = tokenBudget != null && tokenBudget > 0
        ? '$tokensUsed/$tokenBudget tokens · $turnsUsed/$maxTurns turns'
        : '$turnsUsed/$maxTurns turns';
    return {
      l10n.objective: _firstText([
        artifact?['objective'],
        template['objective'],
      ]),
      l10n.scope: _firstText([
        artifact?['scope'],
        workPacket?['implementationScope'],
      ]),
      l10n.dataRequirements: contextNeeds.isEmpty
          ? '-'
          : contextNeeds.join('; '),
      l10n.riskBoundary: guardrails.isEmpty
          ? _firstText([artifact?['escalation']])
          : guardrails.join('; '),
      l10n.budget: budget,
      l10n.doneCriteria: criteria.isEmpty ? '-' : criteria.join('; '),
      l10n.verification: _firstText([
        artifact?['verification'],
        workPacket?['verification'],
        verifier?['reason'],
      ]),
      l10n.escalation: _firstText([
        artifact?['escalation'],
        workPacket?['escalationCondition'],
      ]),
      l10n.evidence: evidence.isEmpty ? '-' : evidence.join('; '),
    };
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _firstText(List<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '-';
  }

  Widget _buildAutomationSuggestionHeader(
    List<GoalAutomationSuggestion> suggestions,
  ) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.automationSuggestions,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: cs.onSurface.withValues(alpha: 0.75),
            ),
          ),
          if (suggestions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.noAutomationSuggestions,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.45),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAutomationSuggestionCard(GoalAutomationSuggestion suggestion) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              suggestion.title,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              '${suggestion.source} · ${suggestion.templateId.wireName}',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              suggestion.description,
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.58),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    final result = _goalAutomation.acceptSuggestion(
                      suggestion.id,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['error']?.toString() ??
                              l10n.automationSuggestionAccepted,
                        ),
                      ),
                    );
                    setState(() {});
                  },
                  icon: const Icon(Icons.check_circle_outline, size: 16),
                  label: Text(l10n.accept),
                ),
                TextButton.icon(
                  onPressed: () {
                    final result = _goalAutomation.dismissSuggestion(
                      suggestion.id,
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          result['error']?.toString() ??
                              l10n.automationSuggestionDismissed,
                        ),
                      ),
                    );
                    setState(() {});
                  },
                  icon: const Icon(Icons.do_not_disturb_on_outlined, size: 16),
                  label: Text(l10n.dismiss),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestList(ScrollController scrollCtrl) {
    final records = ApiStats.instance.getRecent(range: _range);
    if (records.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noRequests,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: records.length,
      itemBuilder: (_, i) {
        final r = records[i];
        final time =
            '${r.requestedAt.hour.toString().padLeft(2, '0')}:${r.requestedAt.minute.toString().padLeft(2, '0')}:${r.requestedAt.second.toString().padLeft(2, '0')}';
        final cs = Theme.of(context).colorScheme;
        final statusColor = r.success ? Colors.green : Colors.red;
        final urlShort = r.url.length > 60
            ? '${r.url.substring(0, 60)}...'
            : r.url;

        return ExpansionTile(
          dense: true,
          tilePadding: const EdgeInsets.symmetric(horizontal: 8),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          leading: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          title: Row(
            children: [
              Text(
                time,
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.5),
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  r.source,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: cs.primary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  urlShort,
                  style: const TextStyle(fontSize: 10),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${r.durationMs}ms',
                style: TextStyle(
                  fontSize: 10,
                  color: cs.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          children: [
            if (r.url.isNotEmpty)
              _detailRow(AppLocalizations.of(context).urlLabel, r.url),
            _detailRow(AppLocalizations.of(context).methodLabel, r.method),
            _detailRow(
              AppLocalizations.of(context).statusLabel,
              '${r.statusCode}',
            ),
            _detailRow(
              AppLocalizations.of(context).durationLabel,
              '${r.durationMs}ms',
            ),
            if (r.error != null)
              _detailRow(
                AppLocalizations.of(context).errorPrefix,
                r.error!,
                color: Colors.red,
              ),
            if (r.responseSummary != null)
              _detailRow(
                AppLocalizations.of(context).responseLabel,
                r.responseSummary!,
              ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 10, color: color),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceSummary(ScrollController scrollCtrl) {
    final summaries = ApiStats.instance.getSummary(range: _range);
    if (summaries.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context).noData,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    return ListView.builder(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(8),
      itemCount: summaries.length,
      itemBuilder: (_, i) {
        final s = summaries[i];
        final cs = Theme.of(context).colorScheme;
        final rateColor = s.failRate < 0.05
            ? Colors.green
            : s.failRate < 0.1
            ? Colors.orange
            : Colors.red;
        final rateText = '${((1 - s.failRate) * 100).toStringAsFixed(1)}%';

        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      s.source,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${s.totalRequests}${AppLocalizations.of(context).requestsSuffix}',
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: rateColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        rateText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: rateColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 1 - s.failRate,
                    backgroundColor: Colors.red.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(rateColor),
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _statChip(
                      AppLocalizations.of(context).avgShort,
                      '${s.avgLatencyMs.toStringAsFixed(0)}ms',
                    ),
                    const SizedBox(width: 8),
                    _statChip('P95', '${s.p95LatencyMs.toStringAsFixed(0)}ms'),
                    const SizedBox(width: 8),
                    _statChip('OK', '${s.successCount}', color: Colors.green),
                    const SizedBox(width: 8),
                    _statChip(
                      AppLocalizations.of(context).failShort,
                      '${s.failCount}',
                      color: s.failCount > 0 ? Colors.red : null,
                    ),
                  ],
                ),
                if (s.lastError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    s.lastError!,
                    style: const TextStyle(fontSize: 10, color: Colors.red),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReusableData(ScrollController scrollCtrl) {
    final l10n = AppLocalizations.of(context);
    final summary = ReusableDataStore(widget.basePath).reusableSummary();
    if (summary['available'] != true) {
      return Center(
        child: Text(
          l10n.noData,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    const priorityTables = [
      'quote_snapshot',
      'kline_daily',
      'stock_list',
      'fund_list',
      'fund_nav',
      'money_flow',
      'hot_rank',
      'limit_pool',
      'northbound_holding',
      'yfinance_news',
    ];
    final tableRows = priorityTables
        .map((name) => MapEntry(name, summary[name]))
        .where((entry) => entry.value is Map)
        .map(
          (entry) => MapEntry(
            entry.key,
            Map<String, dynamic>.from(entry.value as Map),
          ),
        )
        .toList();
    final sources = (summary['sources'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(8),
      children: [
        ...tableRows.map((entry) => _dataRow(entry.key, entry.value)),
        if (sources.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            l10n.bySource,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          ...sources.take(8).map((row) => _sourceDataRow(row)),
        ],
      ],
    );
  }

  Widget _buildDataTasks(ScrollController scrollCtrl) {
    final l10n = AppLocalizations.of(context);
    final tasks = widget.dataTaskEngine.list().reversed.toList();
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          l10n.noData,
          style: TextStyle(
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      );
    }
    final counts = <DataTaskStatus, int>{
      for (final status in DataTaskStatus.values)
        status: tasks.where((task) => task.status == status).length,
    };
    return ListView(
      controller: scrollCtrl,
      padding: const EdgeInsets.all(8),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _taskCountChip(l10n.all, tasks.length),
            _taskCountChip(l10n.running, counts[DataTaskStatus.running] ?? 0),
            _taskCountChip(l10n.pending, counts[DataTaskStatus.pending] ?? 0),
            _taskCountChip(l10n.failed, counts[DataTaskStatus.failed] ?? 0),
            _taskCountChip(
              l10n.completed,
              counts[DataTaskStatus.completed] ?? 0,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...tasks.take(30).map(_taskRow),
      ],
    );
  }

  Widget _taskRow(DataTask task) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final statusColor = switch (task.status) {
      DataTaskStatus.completed => Colors.green,
      DataTaskStatus.failed => Colors.red,
      DataTaskStatus.running => Colors.orange,
      DataTaskStatus.cancelled => cs.outline,
      DataTaskStatus.pending => cs.primary,
    };
    final params = const JsonEncoder().convert(task.params);
    final canCancel =
        task.status == DataTaskStatus.pending ||
        task.status == DataTaskStatus.running;
    final canRetry =
        task.status == DataTaskStatus.failed ||
        task.status == DataTaskStatus.cancelled;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.type,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _taskStatusLabel(task.status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: (task.progress.clamp(0, 100)) / 100,
              minHeight: 4,
              backgroundColor: cs.outline.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(statusColor),
            ),
            const SizedBox(height: 6),
            _detailRow(
              l10n.progressLabel,
              '${task.progress.toStringAsFixed(0)}%',
            ),
            _detailRow(l10n.createdAt, _formatTime(task.createdAt)),
            if (task.completedAt != null)
              _detailRow(l10n.completedAt, _formatTime(task.completedAt!)),
            if (params != '{}') _detailRow(l10n.params, params),
            if (task.result != null) _detailRow(l10n.result, task.result!),
            if (task.error != null)
              _detailRow(l10n.errorPrefix, task.error!, color: Colors.red),
            if (canCancel || canRetry) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Spacer(),
                  if (canCancel)
                    TextButton.icon(
                      onPressed: () {
                        widget.dataTaskEngine.cancel(task.id);
                        setState(() {});
                      },
                      icon: const Icon(Icons.stop_circle_outlined, size: 16),
                      label: Text(l10n.cancel),
                    ),
                  if (canRetry)
                    TextButton.icon(
                      onPressed: () {
                        widget.dataTaskEngine.submit(task.type, task.params);
                        setState(() {});
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text(l10n.retry),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _taskCountChip(String label, int count) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(fontSize: 11, color: cs.onSurface),
      ),
    );
  }

  String _taskStatusLabel(DataTaskStatus status) {
    final l10n = AppLocalizations.of(context);
    return switch (status) {
      DataTaskStatus.completed => l10n.completed,
      DataTaskStatus.failed => l10n.failed,
      DataTaskStatus.running => l10n.running,
      DataTaskStatus.cancelled => l10n.cancelled,
      DataTaskStatus.pending => l10n.pending,
    };
  }

  String _formatTime(DateTime time) {
    final local = time.toLocal();
    return '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _compactPath(String value) {
    final parts = value
        .split(RegExp(r'[/\\]'))
        .where((part) => part.trim().isNotEmpty)
        .toList();
    if (parts.length <= 2) return value;
    return '${parts[parts.length - 2]}/${parts.last}';
  }

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds < 0 ? 0 : duration.inSeconds;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    if (minutes > 0) return '${minutes}m ${seconds}s';
    return '${seconds}s';
  }

  Widget _dataRow(String table, Map<String, dynamic> row) {
    final l10n = AppLocalizations.of(context);
    final cs = Theme.of(context).colorScheme;
    final rows = row['rows'] ?? 0;
    final codes =
        row['codes'] ??
        row['symbols'] ??
        row['entities'] ??
        row['series'] ??
        row['categories'];
    final latest =
        row['latest'] ?? row['latest_date'] ?? row['updated_at'] ?? '-';
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    table,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${l10n.latest}: $latest',
                    style: TextStyle(
                      fontSize: 10,
                      color: cs.onSurface.withValues(alpha: 0.5),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$rows',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  codes == null ? l10n.rowsLabel : '${l10n.codesLabel}: $codes',
                  style: TextStyle(
                    fontSize: 10,
                    color: cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sourceDataRow(Map<String, dynamic> row) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${row['source'] ?? '-'}',
              style: const TextStyle(fontSize: 11),
            ),
          ),
          Text(
            '${row['rows'] ?? 0}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 120,
            child: Text(
              '${row['latest'] ?? '-'}',
              style: TextStyle(
                fontSize: 10,
                color: cs.onSurface.withValues(alpha: 0.45),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _doctorSummary(FinanceDoctorReport report, AppLocalizations l10n) {
    if (report.status == FinanceDoctorStatus.ok) {
      return l10n.doctorSummaryOk;
    }
    final critical = report.checks
        .where((check) => check.status == FinanceDoctorStatus.critical)
        .length;
    final warning = report.checks
        .where((check) => check.status == FinanceDoctorStatus.warning)
        .length;
    return '$critical ${l10n.doctorCriticalCount}, $warning ${l10n.doctorWarningCount}';
  }

  String _doctorStatusLabel(FinanceDoctorStatus status, AppLocalizations l10n) {
    return switch (status) {
      FinanceDoctorStatus.ok => l10n.doctorOk,
      FinanceDoctorStatus.warning => l10n.doctorWarning,
      FinanceDoctorStatus.critical => l10n.doctorCritical,
    };
  }

  Color _doctorStatusColor(FinanceDoctorStatus status, ColorScheme cs) {
    return switch (status) {
      FinanceDoctorStatus.ok => Colors.green,
      FinanceDoctorStatus.warning => Colors.orange,
      FinanceDoctorStatus.critical => cs.error,
    };
  }

  String _doctorCheckLabel(String id, AppLocalizations l10n) {
    return switch (id) {
      'runtime_paths' => l10n.runtimePaths,
      'memory_paths' => l10n.memoryPaths,
      'api_failures' => l10n.recentApiFailures,
      'data_tasks' => l10n.dataTasks,
      'reusable_store' => l10n.reusableStore,
      'stock_identity' => l10n.stockIdentityCache,
      'fund_identity' => l10n.fundIdentityCache,
      'quote_cache' => l10n.quoteCache,
      'kline_cache' => l10n.klineCache,
      _ => id,
    };
  }

  Widget _statChip(String label, String value, {Color? color}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(
              context,
            ).colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
