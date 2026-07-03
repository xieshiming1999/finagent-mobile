import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

import '../../domain/market/analysis/analysis_evidence_contract.dart';

/// Market snapshot — aggregated market state from multiple data sources.
/// Persisted to file so agent can read current market regime.
class MarketSnapshot {
  final String basePath;
  late final String _filePath;

  MarketSnapshot(this.basePath) {
    _filePath = p.join(basePath, 'memory', 'market_snapshot.json');
  }

  /// Build a snapshot from raw market data
  Map<String, dynamic> build({
    required int totalStocks,
    required int upCount,
    required int downCount,
    required int limitUpCount,
    required int limitDownCount,
    required double northboundNet, // 亿
    required List<Map<String, dynamic>> topSectors,
    required Map<String, dynamic>
    indexData, // {sh: {price, changePct}, sz: {...}, cyb: {...}}
  }) {
    final flatCount = totalStocks - upCount - downCount;
    final upRatio = totalStocks > 0 ? upCount / totalStocks : 0.0;

    // Regime detection
    String regime;
    String regimeDetail;
    if (upRatio > 0.7 && limitUpCount > 30) {
      regime = 'strong_bull';
      regimeDetail = '强势上涨：涨跌比 $upCount:$downCount，$limitUpCount只涨停';
    } else if (upRatio > 0.55) {
      regime = 'bull';
      regimeDetail = '偏多：涨跌比 $upCount:$downCount';
    } else if (upRatio < 0.3 && limitDownCount > 20) {
      regime = 'strong_bear';
      regimeDetail = '强势下跌：涨跌比 $upCount:$downCount，$limitDownCount只跌停';
    } else if (upRatio < 0.45) {
      regime = 'bear';
      regimeDetail = '偏空：涨跌比 $upCount:$downCount';
    } else {
      regime = 'neutral';
      regimeDetail = '震荡：涨跌比 $upCount:$downCount';
    }

    // Northbound sentiment
    String northSentiment;
    if (northboundNet > 50) {
      northSentiment = '大幅流入 ${northboundNet.toStringAsFixed(1)}亿';
    } else if (northboundNet > 10) {
      northSentiment = '净流入 ${northboundNet.toStringAsFixed(1)}亿';
    } else if (northboundNet < -50) {
      northSentiment = '大幅流出 ${northboundNet.toStringAsFixed(1)}亿';
    } else if (northboundNet < -10) {
      northSentiment = '净流出 ${northboundNet.toStringAsFixed(1)}亿';
    } else {
      northSentiment = '基本持平 ${northboundNet.toStringAsFixed(1)}亿';
    }

    final snapshot = {
      'timestamp': DateTime.now().toIso8601String(),
      'regime': regime,
      'regime_detail': regimeDetail,
      'breadth': {
        'total': totalStocks,
        'up': upCount,
        'down': downCount,
        'flat': flatCount,
        'up_ratio': double.parse((upRatio * 100).toStringAsFixed(1)),
        'limit_up': limitUpCount,
        'limit_down': limitDownCount,
      },
      'northbound': {'net': northboundNet, 'sentiment': northSentiment},
      'indices': indexData,
      'top_sectors': topSectors.take(5).toList(),
    };
    snapshot['analysisEvidence'] = _analysisEvidence(snapshot);

    // Persist
    _save(snapshot);
    return snapshot;
  }

  /// Return a snapshot with an analysis evidence package. This upgrades older
  /// persisted snapshots without changing their original market fields.
  Map<String, dynamic> withAnalysisEvidence(Map<String, dynamic> snapshot) {
    if (snapshot['analysisEvidence'] is Map<String, dynamic>) return snapshot;
    return {...snapshot, 'analysisEvidence': _analysisEvidence(snapshot)};
  }

  /// Load the latest snapshot
  Map<String, dynamic>? load() {
    try {
      final file = File(_filePath);
      if (file.existsSync()) {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    } catch (_) {}
    return null;
  }

  void _save(Map<String, dynamic> snapshot) {
    try {
      final dir = Directory(p.dirname(_filePath));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(
        _filePath,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(snapshot));
    } catch (_) {}
  }

  Map<String, dynamic> _analysisEvidence(Map<String, dynamic> snapshot) {
    final timestamp = snapshot['timestamp']?.toString() ?? '';
    final regime = snapshot['regime']?.toString() ?? 'unknown';
    final breadth = snapshot['breadth'] is Map
        ? Map<String, dynamic>.from(snapshot['breadth'] as Map)
        : <String, dynamic>{};
    final northbound = snapshot['northbound'] is Map
        ? Map<String, dynamic>.from(snapshot['northbound'] as Map)
        : <String, dynamic>{};
    final sectors = snapshot['top_sectors'] is List
        ? List<dynamic>.from(snapshot['top_sectors'] as List)
        : const <dynamic>[];
    final missing = <String>[
      if (breadth.isEmpty) 'market_breadth',
      if (sectors.isEmpty) 'sector_leaders',
      if (northbound.isEmpty) 'northbound_flow',
      'news_context',
      'strategy_validation',
    ];

    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.market,
      subjectType: AnalysisSubjectType.market,
      subjectId: 'cn-a-share-market',
      subjectName: 'A-share market snapshot',
      observedFacts: [
        'timestamp=$timestamp',
        'regime=$regime',
        if (breadth['total'] != null) 'total=${breadth['total']}',
        if (breadth['up'] != null) 'up=${breadth['up']}',
        if (breadth['down'] != null) 'down=${breadth['down']}',
        if (breadth['limit_up'] != null) 'limitUp=${breadth['limit_up']}',
        if (breadth['limit_down'] != null) 'limitDown=${breadth['limit_down']}',
        if (northbound['net'] != null) 'northboundNet=${northbound['net']}',
        'topSectors=${sectors.length}',
      ],
      interpretations: [
        'market_regime:$regime',
        if (snapshot['regime_detail'] != null)
          'regime_detail:${snapshot['regime_detail']}',
        if (northbound['sentiment'] != null)
          'northbound:${northbound['sentiment']}',
      ],
      missingEvidence: missing,
      confidence: missing.length <= 2
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: const [
          'market_snapshot',
          'market_breadth',
          'sector_rank',
          'northbound_flow',
        ],
        interfaceId: 'market.overview',
        capabilityId: 'local.market_snapshot.aggregate',
        canonicalSchema: 'market_snapshot',
        readbackAction: 'DataProcess.market_snapshot',
        sourceDataTime: timestamp.length >= 10
            ? timestamp.substring(0, 10)
            : '',
        fetchedAt: timestamp,
        cacheStatus: 'snapshot',
        coverageStatus: missing.length <= 2
            ? AnalysisCoverageStatus.sufficientForAnalysis
            : AnalysisCoverageStatus.partial,
      ),
    ).toJson();
  }
}
