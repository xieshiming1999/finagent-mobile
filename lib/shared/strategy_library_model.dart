class StrategyLibraryItem {
  static const stockStrategy = 'stock_strategy';
  static const fundStrategy = 'fund_strategy';
  static const portfolioStrategy = 'portfolio_strategy';
  static const etfMarketStrategy = 'etf_market_strategy';
  static const unknownStrategy = 'unknown_strategy';

  final String strategyId;
  final String name;
  final String status;
  final String assetClass;
  final String strategyType;
  final List<String> symbols;
  final String updatedAt;
  final String evidenceAction;
  final String evidenceSummary;
  final String dataSummary;
  final String riskRewardSummary;
  final String assumptionSummary;

  const StrategyLibraryItem({
    required this.strategyId,
    required this.name,
    required this.status,
    required this.assetClass,
    this.strategyType = unknownStrategy,
    required this.symbols,
    required this.updatedAt,
    required this.evidenceAction,
    this.evidenceSummary = '',
    this.dataSummary = '',
    this.riskRewardSummary = '',
    this.assumptionSummary = '',
  });

  bool get runnable => status == 'backtested';

  static StrategyLibraryItem? fromJson(Map<dynamic, dynamic> row) {
    final spec = _firstMap(row['strategySpec'], row['spec']);
    final evidence = _firstMap(row['backtestEvidence'], row['evidence']);
    final summary = _asMap(row['dataAndAssumptionSummary']);
    final strategyId = _string(row['strategyId']).isNotEmpty
        ? _string(row['strategyId'])
        : _string(spec['id']);
    if (strategyId.isEmpty) return null;
    final symbols = _extractSymbols(spec, row);
    final status = _string(row['status']).isNotEmpty
        ? _string(row['status'])
        : 'unknown';
    final assetClass = _string(row['assetClass']).isNotEmpty
        ? _string(row['assetClass'])
        : _string(spec['assetClass']).isNotEmpty
        ? _string(spec['assetClass'])
        : (_string(spec['market']).isNotEmpty
              ? _string(spec['market'])
              : _inferAssetClass(symbols));
    final evidenceAction = _string(row['evidenceAction']).isNotEmpty
        ? _string(row['evidenceAction'])
        : _string(evidence['action']);
    return StrategyLibraryItem(
      strategyId: strategyId,
      name: _string(row['name']).isNotEmpty
          ? _string(row['name'])
          : _string(spec['name']).isNotEmpty
          ? _string(spec['name'])
          : strategyId,
      status: status,
      assetClass: assetClass,
      strategyType:
          _normalizeStrategyType(row['strategyType']) ??
          _inferStrategyType(
            row: row,
            spec: spec,
            evidence: evidence,
            summary: summary,
            status: status,
            assetClass: assetClass,
            evidenceAction: evidenceAction,
            symbols: symbols,
          ),
      symbols: symbols,
      updatedAt: _string(row['updatedAt']),
      evidenceAction: evidenceAction,
      evidenceSummary: _summarizeEvidence(evidence, summary),
      dataSummary: _summarizeDataEvidence(evidence, summary),
      riskRewardSummary: _summarizeRiskReward(evidence, summary),
      assumptionSummary: _summarizeAssumptions(spec, summary),
    );
  }

  static Map<dynamic, dynamic> _asMap(Object? value) =>
      value is Map ? value : const {};

  static Map<dynamic, dynamic> _firstMap(Object? first, [Object? second]) {
    final primary = _asMap(first);
    if (primary.isNotEmpty) return primary;
    return _asMap(second);
  }

  static Map<dynamic, dynamic> _firstMapOf(Iterable<Object?> values) {
    for (final value in values) {
      final mapped = _asMap(value);
      if (mapped.isNotEmpty) return mapped;
    }
    return const {};
  }

  static String _string(Object? value) => value is String ? value.trim() : '';

  static String? _normalizeStrategyType(Object? value) {
    final text = _string(value);
    switch (text) {
      case stockStrategy:
      case fundStrategy:
      case portfolioStrategy:
      case etfMarketStrategy:
      case unknownStrategy:
        return text;
    }
    return null;
  }

  static String _inferStrategyType({
    required Map<dynamic, dynamic> row,
    required Map<dynamic, dynamic> spec,
    required Map<dynamic, dynamic> evidence,
    required Map<dynamic, dynamic> summary,
    required String status,
    required String assetClass,
    required String evidenceAction,
    required List<String> symbols,
  }) {
    final normalizedAssetClass = assetClass.toLowerCase();
    if (status == 'ranked' ||
        evidenceAction == 'custom_strategy_rank' ||
        _hasAnyMap(summary, [
          'portfolioEvidence',
          'rebalanceDraft',
          'portfolioValidation',
        ]) ||
        _hasAnyMap(evidence, [
          'portfolioEvidence',
          'rebalanceDraft',
          'portfolioValidation',
        ])) {
      return portfolioStrategy;
    }
    final fundRisk = _asMap(summary['fundRiskEvidence']);
    final pricingBasis = _string(fundRisk['pricingBasis']).toLowerCase();
    final specType = _string(spec['type']).toLowerCase();
    if (normalizedAssetClass == 'etf' ||
        normalizedAssetClass == 'listed_fund' ||
        pricingBasis == 'listed_fund' ||
        pricingBasis == 'etf' ||
        specType == etfMarketStrategy) {
      return etfMarketStrategy;
    }
    if (normalizedAssetClass == 'fund' ||
        evidenceAction == 'custom_strategy_observe' ||
        evidenceAction == 'custom_strategy_fund_backtest' ||
        _hasAnyMap(summary, ['fundCoverageEvidence', 'fundRiskEvidence'])) {
      return fundStrategy;
    }
    if (normalizedAssetClass == 'stock' ||
        symbols.any((symbol) => RegExp(r'^\d{6}$').hasMatch(symbol))) {
      return stockStrategy;
    }
    return unknownStrategy;
  }

  static bool _hasAnyMap(Map<dynamic, dynamic> record, List<String> keys) =>
      keys.any((key) => _asMap(record[key]).isNotEmpty);

  static List<String> _extractSymbols(
    Map<dynamic, dynamic> spec, [
    Map<dynamic, dynamic> row = const {},
  ]) {
    final values = <String>[];
    final rowSymbols = row['symbols'];
    if (rowSymbols is List) {
      values.addAll(rowSymbols.map(_string).where((value) => value.isNotEmpty));
    }
    for (final key in ['symbol', 'code']) {
      final value = _string(spec[key]);
      if (value.isNotEmpty) values.add(value);
    }
    for (final key in ['symbols', 'codes']) {
      final list = spec[key];
      if (list is List) {
        values.addAll(list.map(_string).where((value) => value.isNotEmpty));
      }
    }
    final universe = spec['universe'];
    if (universe is Map && universe['symbols'] is List) {
      values.addAll(
        (universe['symbols'] as List)
            .map(_string)
            .where((value) => value.isNotEmpty),
      );
    }
    return values.toSet().toList(growable: false);
  }

  static String _inferAssetClass(List<String> symbols) =>
      symbols.any((symbol) => RegExp(r'^\d{6}$').hasMatch(symbol))
      ? 'stock'
      : 'unknown';

  static String _summarizeEvidence(
    Map<dynamic, dynamic> evidence, [
    Map<dynamic, dynamic> summary = const {},
  ]) {
    final parts = <String>[];
    final metrics = _asMap(evidence['metrics']);
    _addNumberPart(parts, 'return', metrics['totalReturnPct'], '%');
    _addNumberPart(parts, 'maxDD', metrics['maxDrawdownPct'], '%');
    _addNumberPart(parts, 'sharpe', metrics['sharpe']);
    final fundRisk = _asMap(summary['fundRiskEvidence']);
    _addNumberPart(parts, 'fundMaxDD', fundRisk['worstDrawdownPct'], '%');
    _addNumberPart(parts, 'fundVol', fundRisk['maxVolatilityPct'], '%');
    _addNumberPart(
      parts,
      'sevenDayYield',
      fundRisk['averageSevenDayYield'],
      '%',
    );
    _addNumberPart(
      parts,
      'fundGTP',
      fundRisk['gainToPainRatio'] ?? fundRisk['averageGainToPainRatio'],
    );
    _addNumberPart(
      parts,
      'fundOmega',
      fundRisk['omegaRatio'] ?? fundRisk['averageOmegaRatio'],
    );
    _addNumberPart(
      parts,
      'fundTail',
      fundRisk['tailRatio'] ?? fundRisk['averageTailRatio'],
    );
    final signal = _string(evidence['signal']);
    if (signal.isNotEmpty) parts.add('signal=$signal');
    final status = _string(evidence['status']);
    if (status.isNotEmpty) parts.add('status=$status');
    return parts.join(' · ');
  }

  static String _summarizeDataEvidence(
    Map<dynamic, dynamic> evidence, [
    Map<dynamic, dynamic> summary = const {},
  ]) {
    final dataEvidence = _asMap(evidence['dataEvidence']);
    final fundCoverage = _asMap(summary['fundCoverageEvidence']);
    final fundRisk = _asMap(summary['fundRiskEvidence']);
    final parts = <String>[];
    for (final key in [
      'source',
      'provider',
      'cacheStatus',
      'sourceDataTime',
      'fetchedAt',
    ]) {
      final value = _string(dataEvidence[key]).isNotEmpty
          ? _string(dataEvidence[key])
          : _string(evidence[key]);
      if (value.isNotEmpty) parts.add('$key=$value');
    }
    final bars = _number(dataEvidence['bars']) ?? _number(evidence['bars']);
    if (bars != null) parts.add('bars=${_formatNumber(bars)}');
    final coverage = _string(fundCoverage['status']);
    if (coverage.isNotEmpty) parts.add('fundCoverage=$coverage');
    final pricingBasis = _string(fundRisk['pricingBasis']);
    if (pricingBasis.isNotEmpty) parts.add('pricingBasis=$pricingBasis');
    return parts.join(' · ');
  }

  static String _summarizeRiskReward(
    Map<dynamic, dynamic> evidence, [
    Map<dynamic, dynamic> summary = const {},
  ]) {
    final riskReward = _firstMap(
      evidence['riskRewardEvidence'],
      summary['riskRewardEvidence'],
    );
    final portfolioQuality = _firstMapOf([
      evidence['portfolioReturnQualityEvidence'],
      summary['portfolioReturnQualityEvidence'],
      _asMap(evidence['portfolioEvidence'])['portfolioReturnQualityEvidence'],
      _asMap(summary['portfolioEvidence'])['portfolioReturnQualityEvidence'],
    ]);
    final parts = <String>[];
    _addNumberPart(parts, 'trades', riskReward['completedTrades']);
    _addNumberPart(parts, 'wins', riskReward['winningTrades']);
    _addNumberPart(parts, 'losses', riskReward['losingTrades']);
    _addNumberPart(parts, 'payoff', riskReward['payoffRatio']);
    _addNumberPart(parts, 'profitFactor', riskReward['profitFactor']);
    _addNumberPart(parts, 'expectancy', riskReward['expectancyPct'], '%');
    _addNumberPart(
      parts,
      'portfolioReturn',
      portfolioQuality['annualizedReturnPct'],
      '%',
    );
    _addNumberPart(
      parts,
      'portfolioVol',
      portfolioQuality['annualizedVolatilityPct'],
      '%',
    );
    _addNumberPart(parts, 'portfolioSharpe', portfolioQuality['sharpeRatio']);
    _addNumberPart(parts, 'portfolioSortino', portfolioQuality['sortinoRatio']);
    _addNumberPart(parts, 'portfolioCalmar', portfolioQuality['calmarRatio']);
    _addNumberPart(parts, 'portfolioGTP', portfolioQuality['gainToPainRatio']);
    return parts.join(' · ');
  }

  static String _summarizeAssumptions(
    Map<dynamic, dynamic> spec, [
    Map<dynamic, dynamic> summary = const {},
  ]) {
    final parts = <String>[];
    final positionSizing = _firstMap(
      summary['positionSizing'],
      spec['positionSizing'],
    );
    final sizingType = _string(positionSizing['type']);
    if (sizingType.isNotEmpty) parts.add('sizing=$sizingType');
    _addNumberPart(parts, 'fraction', positionSizing['value']);
    _addNumberPart(parts, 'riskPct', positionSizing['riskPct']);
    _addNumberPart(parts, 'maxPosition', positionSizing['maxPositionPct']);
    _addNumberPart(parts, 'kellyScale', positionSizing['kellyScale']);
    final fees = _asMap(summary['feesAndSlippage']);
    _addNumberPart(parts, 'commission', fees['commissionPct'], '%');
    _addNumberPart(parts, 'slippage', fees['slippagePct'], '%');
    return parts.join(' · ');
  }

  static void _addNumberPart(
    List<String> parts,
    String label,
    Object? value, [
    String suffix = '',
  ]) {
    final number = _number(value);
    if (number == null) return;
    parts.add('$label=${_formatNumber(number)}$suffix');
  }

  static double? _number(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static String _formatNumber(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
}

List<StrategyLibraryItem> parseStrategyLibraryRows(Object? decoded) {
  final rows = decoded is List ? decoded : const [];
  return rows
      .whereType<Map>()
      .map((row) => StrategyLibraryItem.fromJson(row))
      .whereType<StrategyLibraryItem>()
      .toList(growable: false);
}
