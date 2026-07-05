class AnalysisEvidenceKind {
  static const market = 'market_analysis';
  static const stock = 'stock_analysis';
  static const fund = 'fund_analysis';
  static const sector = 'sector_analysis';
  static const flow = 'flow_analysis';
  static const valuation = 'valuation_analysis';
  static const risk = 'risk_analysis';
  static const news = 'news_analysis';
  static const dashboard = 'dashboard_analysis';
  static const candidateResearch = 'candidate_research';

  static const values = <String>{
    market,
    stock,
    fund,
    sector,
    flow,
    valuation,
    risk,
    news,
    dashboard,
    candidateResearch,
  };

  static bool isValid(String value) => values.contains(value);
}

class AnalysisSubjectType {
  static const market = 'market';
  static const stock = 'stock';
  static const fund = 'fund';
  static const etf = 'etf';
  static const sector = 'sector';
  static const index = 'index';
  static const flow = 'flow';
  static const news = 'news';
  static const dashboard = 'dashboard';
  static const candidateSet = 'candidate_set';
  static const fundNavMover = 'fund_nav_mover';

  static const values = <String>{
    market,
    stock,
    fund,
    etf,
    sector,
    index,
    flow,
    news,
    dashboard,
    candidateSet,
    fundNavMover,
  };

  static bool isValid(String value) => values.contains(value);
}

class AnalysisConfidence {
  static const low = 'low';
  static const medium = 'medium';
  static const high = 'high';

  static const values = <String>{low, medium, high};

  static bool isValid(String value) => values.contains(value);
}

class AnalysisStrategyReadiness {
  static const analysisOnly = 'analysis_only';
  static const candidate = 'candidate';
  static const strategyReady = 'strategy_ready';

  static const values = <String>{analysisOnly, candidate, strategyReady};

  static bool isValid(String value) => values.contains(value);
}

class AnalysisCoverageStatus {
  static const none = 'none';
  static const partial = 'partial';
  static const sufficientForAnalysis = 'sufficient_for_analysis';
  static const sufficientForTechnical = 'sufficient_for_technical';

  static const values = <String>{
    none,
    partial,
    sufficientForAnalysis,
    sufficientForTechnical,
  };

  static bool isValid(String value) => values.contains(value);
}

class AnalysisEvidencePackage {
  final String kind;
  final String subjectType;
  final String subjectId;
  final String subjectName;
  final List<String> observedFacts;
  final List<String> interpretations;
  final List<String> missingEvidence;
  final String confidence;
  final String strategyReadiness;
  final AnalysisSourceCoverage sourceCoverage;

  const AnalysisEvidencePackage({
    required this.kind,
    required this.subjectType,
    required this.subjectId,
    this.subjectName = '',
    this.observedFacts = const [],
    this.interpretations = const [],
    this.missingEvidence = const [],
    this.confidence = 'medium',
    this.strategyReadiness = 'analysis_only',
    required this.sourceCoverage,
  }) : assert(
         kind == AnalysisEvidenceKind.market ||
             kind == AnalysisEvidenceKind.stock ||
             kind == AnalysisEvidenceKind.fund ||
             kind == AnalysisEvidenceKind.sector ||
             kind == AnalysisEvidenceKind.flow ||
             kind == AnalysisEvidenceKind.valuation ||
             kind == AnalysisEvidenceKind.risk ||
             kind == AnalysisEvidenceKind.news ||
             kind == AnalysisEvidenceKind.dashboard ||
             kind == AnalysisEvidenceKind.candidateResearch,
         'Unknown analysis evidence kind',
       ),
       assert(
         subjectType == AnalysisSubjectType.market ||
             subjectType == AnalysisSubjectType.stock ||
             subjectType == AnalysisSubjectType.fund ||
             subjectType == AnalysisSubjectType.etf ||
             subjectType == AnalysisSubjectType.sector ||
             subjectType == AnalysisSubjectType.index ||
             subjectType == AnalysisSubjectType.flow ||
             subjectType == AnalysisSubjectType.news ||
             subjectType == AnalysisSubjectType.dashboard ||
             subjectType == AnalysisSubjectType.candidateSet ||
             subjectType == AnalysisSubjectType.fundNavMover,
         'Unknown analysis subject type',
       ),
       assert(
         confidence == AnalysisConfidence.low ||
             confidence == AnalysisConfidence.medium ||
             confidence == AnalysisConfidence.high,
         'Unknown analysis confidence',
       ),
       assert(
         strategyReadiness == AnalysisStrategyReadiness.analysisOnly ||
             strategyReadiness == AnalysisStrategyReadiness.candidate ||
             strategyReadiness == AnalysisStrategyReadiness.strategyReady,
         'Unknown analysis strategy readiness',
       );

  Map<String, dynamic> toJson() => {
    'contract': 'analysis-evidence-v1',
    'kind': kind,
    'subject': {
      'type': subjectType,
      'id': subjectId,
      if (subjectName.isNotEmpty) 'name': subjectName,
    },
    'observedFacts': observedFacts,
    'interpretations': interpretations,
    'missingEvidence': missingEvidence,
    'confidence': confidence,
    'strategyReadiness': strategyReadiness,
    'sourceCoverage': sourceCoverage.toJson(),
  };
}

class AnalysisSourceCoverage {
  final List<String> sources;
  final String interfaceId;
  final String capabilityId;
  final String canonicalSchema;
  final String canonicalTable;
  final String readbackAction;
  final String sourceDataTime;
  final String fetchedAt;
  final String cacheStatus;
  final String coverageStatus;

  const AnalysisSourceCoverage({
    this.sources = const [],
    this.interfaceId = '',
    this.capabilityId = '',
    this.canonicalSchema = '',
    this.canonicalTable = '',
    this.readbackAction = '',
    this.sourceDataTime = '',
    this.fetchedAt = '',
    this.cacheStatus = '',
    this.coverageStatus = 'partial',
  }) : assert(
         coverageStatus == AnalysisCoverageStatus.none ||
             coverageStatus == AnalysisCoverageStatus.partial ||
             coverageStatus == AnalysisCoverageStatus.sufficientForAnalysis ||
             coverageStatus == AnalysisCoverageStatus.sufficientForTechnical,
         'Unknown analysis coverage status',
       );

  Map<String, dynamic> toJson() => {
    'sources': sources,
    if (interfaceId.isNotEmpty) 'interfaceId': interfaceId,
    if (capabilityId.isNotEmpty) 'capabilityId': capabilityId,
    if (canonicalSchema.isNotEmpty) 'canonicalSchema': canonicalSchema,
    if (canonicalTable.isNotEmpty) 'canonicalTable': canonicalTable,
    if (readbackAction.isNotEmpty) 'readbackAction': readbackAction,
    if (sourceDataTime.isNotEmpty) 'sourceDataTime': sourceDataTime,
    if (fetchedAt.isNotEmpty) 'fetchedAt': fetchedAt,
    if (cacheStatus.isNotEmpty) 'cacheStatus': cacheStatus,
    'coverageStatus': coverageStatus,
  };
}
