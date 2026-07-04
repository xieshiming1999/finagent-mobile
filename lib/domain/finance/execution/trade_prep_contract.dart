class TradePrepContract {
  final String prepKind;
  final String strategyId;
  final String signal;
  final String symbol;
  final Map<String, dynamic> sizing;
  final Map<String, dynamic> evidence;
  final Map<String, dynamic> previews;
  final List<String> boundaries;
  final String confirmation;

  const TradePrepContract({
    required this.prepKind,
    required this.strategyId,
    required this.signal,
    required this.symbol,
    this.sizing = const {},
    this.evidence = const {},
    this.previews = const {},
    this.boundaries = const [],
    this.confirmation = '',
  });

  Map<String, dynamic> toJson() => {
    'contract': 'trade-prep-v1',
    'prepKind': prepKind,
    'strategyId': strategyId,
    'signal': signal,
    'symbol': symbol,
    'sizing': sizing,
    'evidence': evidence,
    'previews': previews,
    'boundaries': boundaries,
    if (confirmation.isNotEmpty) 'confirmation': confirmation,
  };
}
