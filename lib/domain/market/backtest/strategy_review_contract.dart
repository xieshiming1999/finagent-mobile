class StrategyReviewContract {
  final String reviewKind;
  final String strategyId;
  final String signal;
  final List<String> subjects;
  final Map<String, dynamic> evidence;
  final Map<String, dynamic> draft;
  final List<String> boundaries;
  final String confirmation;

  const StrategyReviewContract({
    required this.reviewKind,
    required this.strategyId,
    required this.signal,
    this.subjects = const [],
    this.evidence = const {},
    this.draft = const {},
    this.boundaries = const [],
    this.confirmation = '',
  });

  Map<String, dynamic> toJson() => {
    'contract': 'strategy-review-v1',
    'reviewKind': reviewKind,
    'strategyId': strategyId,
    'signal': signal,
    'subjects': subjects,
    'evidence': evidence,
    'draft': draft,
    'boundaries': boundaries,
    if (confirmation.isNotEmpty) 'confirmation': confirmation,
  };
}
