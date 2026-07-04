import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

enum StrategyType { stockPicking, stockTrading, fundPicking, fundTrading }

/// A strategy = an executable workflow the agent uses internally.
/// Not user-facing config — agent picks and runs strategies when deciding what to buy/sell.
class Strategy {
  final String id;
  String name;
  String description;
  StrategyType type;
  String source; // agent / imported / self-evolved / preset
  DateTime createdAt;
  DateTime? updatedAt;

  List<WorkflowStep> steps;

  int timesUsed;
  int timesCorrect;
  double get winRate => timesUsed > 0 ? timesCorrect / timesUsed : 0;
  List<StrategyExecution> recentExecutions;

  Strategy({
    String? id,
    required this.name,
    this.description = '',
    required this.type,
    this.source = 'preset',
    DateTime? createdAt,
    this.updatedAt,
    this.steps = const [],
    this.timesUsed = 0,
    this.timesCorrect = 0,
    this.recentExecutions = const [],
  }) : id = id ?? _genId(name),
       createdAt = createdAt ?? DateTime.now();

  static String _genId(String name) => md5
      .convert(utf8.encode('$name${DateTime.now().microsecondsSinceEpoch}'))
      .toString()
      .substring(0, 8);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'type': type.name,
    'source': source,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    'steps': steps.map((s) => s.toJson()).toList(),
    'timesUsed': timesUsed,
    'timesCorrect': timesCorrect,
    'winRate': (winRate * 100).toStringAsFixed(1),
    'recentExecutions': recentExecutions.map((e) => e.toJson()).toList(),
  };

  factory Strategy.fromJson(Map<String, dynamic> j) => Strategy(
    id: j['id'] as String?,
    name: j['name'] as String? ?? '',
    description: j['description'] as String? ?? '',
    type: StrategyType.values.firstWhere(
      (t) => t.name == j['type'],
      orElse: () => StrategyType.stockTrading,
    ),
    source: j['source'] as String? ?? 'preset',
    createdAt: DateTime.tryParse(j['createdAt'] as String? ?? ''),
    updatedAt: DateTime.tryParse(j['updatedAt'] as String? ?? ''),
    steps:
        (j['steps'] as List?)
            ?.map((e) => WorkflowStep.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
    timesUsed: (j['timesUsed'] as num?)?.toInt() ?? 0,
    timesCorrect: (j['timesCorrect'] as num?)?.toInt() ?? 0,
    recentExecutions:
        (j['recentExecutions'] as List?)
            ?.map((e) => StrategyExecution.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [],
  );
}

/// One step in a strategy workflow — maps to a tool call + evaluation logic.
class WorkflowStep {
  String description; // "检查MA多头排列"
  String toolName; // "DataProcess"
  String action; // "indicators" / "score_technical" / "volume" / "support"
  Map<String, dynamic> params;
  String
  checkLogic; // "price_vs_ma20 == above" / "score >= 70" / "volume_ratio > 1.5"
  String reasoning; // "趋势向上是入场前提"
  bool required; // must pass to proceed, vs contributes to score

  WorkflowStep({
    this.description = '',
    this.toolName = 'DataProcess',
    this.action = '',
    this.params = const {},
    this.checkLogic = '',
    this.reasoning = '',
    this.required = false,
  });

  Map<String, dynamic> toJson() => {
    'description': description,
    'toolName': toolName,
    'action': action,
    'params': params,
    'checkLogic': checkLogic,
    'reasoning': reasoning,
    'required': required,
  };

  factory WorkflowStep.fromJson(Map<String, dynamic> j) => WorkflowStep(
    description: j['description'] as String? ?? '',
    toolName: j['toolName'] as String? ?? 'DataProcess',
    action: j['action'] as String? ?? '',
    params: j['params'] as Map<String, dynamic>? ?? {},
    checkLogic: j['checkLogic'] as String? ?? '',
    reasoning: j['reasoning'] as String? ?? '',
    required: j['required'] as bool? ?? false,
  );
}

/// Record of one strategy execution against a symbol.
class StrategyExecution {
  DateTime executedAt;
  String symbol;
  List<StepResult> stepResults;
  String decision; // buy / skip / watch
  String reasoning; // full reasoning chain (markdown)
  double score; // 0-100 综合评分

  // Filled later by ai_validate
  bool? wasCorrect;
  double? actualReturn;
  String? reflection;

  StrategyExecution({
    DateTime? executedAt,
    this.symbol = '',
    this.stepResults = const [],
    this.decision = 'skip',
    this.reasoning = '',
    this.score = 0,
    this.wasCorrect,
    this.actualReturn,
    this.reflection,
  }) : executedAt = executedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
    'executedAt': executedAt.toIso8601String(),
    'symbol': symbol,
    'decision': decision,
    'reasoning': reasoning,
    'score': score,
    'stepResults': stepResults.map((s) => s.toJson()).toList(),
    'wasCorrect': wasCorrect,
    'actualReturn': actualReturn,
    'reflection': reflection,
  };

  factory StrategyExecution.fromJson(Map<String, dynamic> j) =>
      StrategyExecution(
        executedAt: DateTime.tryParse(j['executedAt'] as String? ?? ''),
        symbol: j['symbol'] as String? ?? '',
        decision: j['decision'] as String? ?? 'skip',
        reasoning: j['reasoning'] as String? ?? '',
        score: (j['score'] as num?)?.toDouble() ?? 0,
        stepResults:
            (j['stepResults'] as List?)
                ?.map((e) => StepResult.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
        wasCorrect: j['wasCorrect'] as bool?,
        actualReturn: (j['actualReturn'] as num?)?.toDouble(),
        reflection: j['reflection'] as String?,
      );
}

/// Result of executing one workflow step.
class StepResult {
  String stepDescription;
  bool passed;
  String observation; // "MA5(165.2) > MA10(162.8) > MA20(158.5), 多头排列确认"
  Map<String, dynamic>? rawData;

  StepResult({
    this.stepDescription = '',
    this.passed = false,
    this.observation = '',
    this.rawData,
  });

  Map<String, dynamic> toJson() => {
    'stepDescription': stepDescription,
    'passed': passed,
    'observation': observation,
  };

  factory StepResult.fromJson(Map<String, dynamic> j) => StepResult(
    stepDescription: j['stepDescription'] as String? ?? '',
    passed: j['passed'] as bool? ?? false,
    observation: j['observation'] as String? ?? '',
  );
}

/// Typed decision output from strategy execution.
/// Downstream tools (Portfolio, XueqiuTrade, Watchlist) consume this programmatically.
class StrategyDecision {
  final String symbol;
  final String strategyId;
  final String strategyName;
  final String decision; // buy / watch / skip
  final double score; // 0-100
  final double? suggestedEntry;
  final double? stopLoss; // ATR-based
  final double? targetPrice; // ATR-based
  final double? positionPct; // risk-based sizing (0.05-0.30)
  final String reasoning; // full markdown chain
  final StrategyExecution execution;

  StrategyDecision({
    required this.symbol,
    required this.strategyId,
    required this.strategyName,
    required this.decision,
    required this.score,
    this.suggestedEntry,
    this.stopLoss,
    this.targetPrice,
    this.positionPct,
    required this.reasoning,
    required this.execution,
  });

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'strategyId': strategyId,
    'strategyName': strategyName,
    'decision': decision,
    'score': score,
    if (suggestedEntry != null) 'suggestedEntry': suggestedEntry,
    if (stopLoss != null) 'stopLoss': stopLoss,
    if (targetPrice != null) 'targetPrice': targetPrice,
    if (positionPct != null) 'positionPct': positionPct,
    'reasoning': reasoning,
  };
}

/// Persistent store for strategies.
class StrategyStore {
  final List<Strategy> strategies = [];
  String _filePath = '';

  void load(String basePath) {
    _filePath = '$basePath/memory/strategies.json';
    final file = File(_filePath);
    if (!file.existsSync()) {
      _loadPresets();
      return;
    }
    try {
      final list = jsonDecode(file.readAsStringSync()) as List;
      strategies.addAll(
        list.map((e) => Strategy.fromJson(e as Map<String, dynamic>)),
      );
    } catch (_) {
      _loadPresets();
    }
  }

  void save() {
    if (_filePath.isEmpty) return;
    final file = File(_filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(strategies.map((s) => s.toJson()).toList()),
    );
  }

  void add(Strategy s) {
    strategies.add(s);
    save();
  }

  void remove(String id) {
    strategies.removeWhere((s) => s.id == id);
    save();
  }

  Strategy? get(String id) => strategies.where((s) => s.id == id).firstOrNull;
  Strategy? getByName(String name) =>
      strategies.where((s) => s.name == name).firstOrNull;
  Strategy? getByIdOrName(String value) =>
      get(value) ?? getByName(value);
  List<Strategy> getByType(StrategyType type) =>
      strategies.where((s) => s.type == type).toList();

  List<Strategy> topStrategies({int n = 3, StrategyType? type}) {
    var list = type != null ? getByType(type) : strategies.toList();
    list = list.where((s) => s.timesUsed >= 3).toList();
    list.sort((a, b) => b.winRate.compareTo(a.winRate));
    return list.take(n).toList();
  }

  void recordExecution(String id, StrategyExecution exec) {
    final s = get(id);
    if (s == null) return;
    s.timesUsed++;
    s.recentExecutions = [...s.recentExecutions, exec];
    if (s.recentExecutions.length > 10) {
      s.recentExecutions = s.recentExecutions.sublist(
        s.recentExecutions.length - 10,
      );
    }
    s.updatedAt = DateTime.now();
    save();
  }

  void recordValidation(
    String id, {
    required bool correct,
    double? actualReturn,
    String? reflection,
  }) {
    final s = get(id);
    if (s == null) return;
    if (correct) s.timesCorrect++;
    if (s.recentExecutions.isNotEmpty) {
      final last = s.recentExecutions.last;
      last.wasCorrect = correct;
      last.actualReturn = actualReturn;
      last.reflection = reflection;
    }
    s.updatedAt = DateTime.now();
    save();
  }

  String summary() {
    if (strategies.isEmpty) return '无策略';
    final buf = StringBuffer();
    for (final s in strategies) {
      final wr = s.timesUsed > 0
          ? '${(s.winRate * 100).toStringAsFixed(0)}%'
          : '未验证';
      buf.writeln('- ${s.name} (${s.type.name}): $wr [${s.timesUsed}次]');
    }
    return buf.toString();
  }

  void _loadPresets() {
    strategies.addAll(_presetStrategies);
    save();
  }
}

// ─── Preset Strategies ───────────────────────────────────────────────────────

final List<Strategy> _presetStrategies = [
  Strategy(
    id: 'preset_01',
    name: '缩量回踩',
    description: '趋势上涨中缩量回调到均线支撑位买入，适合中短线',
    type: StrategyType.stockTrading,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: 'MA多头排列',
        action: 'indicators',
        checkLogic: 'price_vs_ma20 == above && price_vs_ma10 == above',
        reasoning: '趋势向上是入场前提，MA5>MA10>MA20确认多头',
        required: true,
      ),
      WorkflowStep(
        description: '回踩均线支撑',
        action: 'support',
        checkLogic: 'nearest_support_distance_pct < 3',
        reasoning: '价格接近均线支撑（偏离<3%），入场位置好',
        required: true,
      ),
      WorkflowStep(
        description: '缩量确认',
        action: 'volume',
        checkLogic: 'volume_trend == decreasing',
        reasoning: '回调伴随缩量说明非恐慌性下跌，是洗盘而非出货',
        required: false,
      ),
      WorkflowStep(
        description: 'RSI未超买',
        action: 'indicators',
        params: {'period': 14},
        checkLogic: 'rsi < 70',
        reasoning: 'RSI未进入超买区，仍有上涨空间',
        required: false,
      ),
    ],
  ),
  Strategy(
    id: 'preset_02',
    name: '价值成长',
    description: '低估值+高ROE+资金流入的综合选股，适合中长线',
    type: StrategyType.stockPicking,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: '估值合理',
        action: 'factors',
        checkLogic: 'pe > 0 && pe < 30 && pb < 5',
        reasoning: 'PE<30排除高估值泡沫，PB<5排除资产虚胖',
        required: true,
      ),
      WorkflowStep(
        description: 'ROE趋势',
        action: 'factors',
        checkLogic: 'roe > 12',
        reasoning: 'ROE>12%说明公司赚钱能力强，护城河可能存在',
        required: true,
      ),
      WorkflowStep(
        description: '资金面',
        action: 'volume',
        checkLogic: 'net_inflow > 0',
        reasoning: '主力资金净流入说明大资金认可当前价位',
        required: false,
      ),
      WorkflowStep(
        description: '技术评分',
        action: 'score_technical',
        checkLogic: 'score >= 60',
        reasoning: '技术面至少不差(≥60分)，避免买在下跌趋势中',
        required: false,
      ),
    ],
  ),
  Strategy(
    id: 'preset_03',
    name: '突破放量',
    description: '创新高伴随放量突破，动量型交易策略',
    type: StrategyType.stockTrading,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: '创近期新高',
        action: 'indicators',
        checkLogic: 'close >= high_20d',
        reasoning: '突破20日高点说明多方力量强势，有望开启新一轮上涨',
        required: true,
      ),
      WorkflowStep(
        description: '放量确认',
        action: 'volume',
        checkLogic: 'volume_ratio > 1.5',
        reasoning: '量比>1.5说明突破有资金支持，非虚假突破',
        required: true,
      ),
      WorkflowStep(
        description: '趋势确认',
        action: 'indicators',
        checkLogic: 'price_vs_ma20 == above',
        reasoning: 'MA20上方确认中期趋势向上',
        required: false,
      ),
      WorkflowStep(
        description: 'MACD动能',
        action: 'indicators',
        checkLogic: 'macd_histogram > 0',
        reasoning: 'MACD柱线为正说明动能向上',
        required: false,
      ),
    ],
  ),
  Strategy(
    id: 'preset_04',
    name: '低估定投',
    description: '基于PE百分位的基金定投策略，低估时加投',
    type: StrategyType.fundPicking,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: 'PE百分位低估',
        action: 'factors',
        checkLogic: 'pe_percentile < 30',
        reasoning: 'PE处于历史30%分位以下，说明估值偏低有安全边际',
        required: true,
      ),
      WorkflowStep(
        description: '规模适中',
        action: 'factors',
        checkLogic: 'fund_size >= 2 && fund_size <= 100',
        reasoning: '规模2-100亿：太小流动性差，太大船大难掉头',
        required: false,
      ),
      WorkflowStep(
        description: '回撤可控',
        action: 'factors',
        checkLogic: 'max_drawdown < 25',
        reasoning: '最大回撤<25%，说明基金经理风控能力尚可',
        required: false,
      ),
      WorkflowStep(
        description: '长期业绩',
        action: 'factors',
        checkLogic: 'return_3y_rank_pct < 25',
        reasoning: '近3年排名前1/4，说明长期alpha能力存在',
        required: false,
      ),
    ],
  ),
  Strategy(
    id: 'preset_05',
    name: '高旗形整理',
    description: '强动量后极度收敛缩量，经典趋势中继形态，适合追强势股回调',
    type: StrategyType.stockTrading,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: '前期强动量(40日涨>40%)',
        action: 'indicators',
        checkLogic: 'close >= high_40d * 0.95',
        reasoning: '股价接近40日高点，说明前期有强势上涨动能',
        required: true,
      ),
      WorkflowStep(
        description: '近期收敛(振幅收窄)',
        action: 'support',
        checkLogic: 'nearest_support_distance_pct < 5',
        reasoning: '价格在窄幅区间整理，多空达到暂时平衡，蓄势待突破',
        required: true,
      ),
      WorkflowStep(
        description: '缩量整理',
        action: 'volume',
        checkLogic: 'volume_trend == decreasing',
        reasoning: '整理伴随缩量说明筹码锁定良好，非出货',
        required: true,
      ),
      WorkflowStep(
        description: '趋势未破',
        action: 'indicators',
        checkLogic: 'price_vs_ma20 == above',
        reasoning: '仍在MA20上方，中期趋势未破坏',
        required: false,
      ),
    ],
  ),
  Strategy(
    id: 'preset_06',
    name: '海龟突破',
    description: '经典趋势跟踪策略，突破N日高点入场，ATR管理仓位和止损',
    type: StrategyType.stockTrading,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: '突破20日高点',
        action: 'indicators',
        checkLogic: 'close >= high_20d',
        reasoning: '收盘价突破20日最高价，新高确认趋势延续',
        required: true,
      ),
      WorkflowStep(
        description: 'MA20上方确认趋势',
        action: 'indicators',
        checkLogic: 'price_vs_ma20 == above',
        reasoning: '中期均线上方确认不是下跌反弹中的假突破',
        required: true,
      ),
      WorkflowStep(
        description: '放量支持',
        action: 'volume',
        checkLogic: 'volume_ratio > 1.2',
        reasoning: '突破时量能高于平均水平，资金认可突破有效性',
        required: false,
      ),
      WorkflowStep(
        description: 'RSI动能充足',
        action: 'indicators',
        checkLogic: 'rsi < 70',
        reasoning: 'RSI未极端超买，仍有上涨空间，不是最后一冲',
        required: false,
      ),
    ],
  ),
  Strategy(
    id: 'preset_07',
    name: '均值回归',
    description: '超跌反弹策略，价格跌至布林带下轨附近时逆势买入，适合震荡市',
    type: StrategyType.stockTrading,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: 'RSI超卖',
        action: 'indicators',
        checkLogic: 'rsi < 30',
        reasoning: 'RSI<30进入超卖区，短期下跌过度有修复需求',
        required: true,
      ),
      WorkflowStep(
        description: '接近均线支撑',
        action: 'support',
        checkLogic: 'nearest_support_distance_pct < 3',
        reasoning: '价格接近MA20/MA60等关键均线支撑，有技术性买盘',
        required: true,
      ),
      WorkflowStep(
        description: '缩量企稳',
        action: 'volume',
        checkLogic: 'volume_trend == decreasing',
        reasoning: '下跌末端缩量说明抛压衰竭，卖方力量枯竭',
        required: false,
      ),
      WorkflowStep(
        description: '基本面无硬伤',
        action: 'factors',
        checkLogic: 'pe > 0 && pe < 50',
        reasoning: 'PE为正且<50排除亏损股和极端高估值，确保是正常回调非基本面崩塌',
        required: false,
      ),
    ],
  ),
  Strategy(
    id: 'preset_08',
    name: 'CTA双均线',
    description: '经典CTA趋势跟踪策略，快均线上穿慢均线做多，适合期货和趋势明确的品种',
    type: StrategyType.stockTrading,
    source: 'preset',
    steps: [
      WorkflowStep(
        description: 'MA5上穿MA20(金叉)',
        action: 'indicators',
        checkLogic: 'price_vs_ma20 == above && price_vs_ma10 == above',
        reasoning: '短期均线在长期均线上方，趋势转多确认',
        required: true,
      ),
      WorkflowStep(
        description: 'MACD柱线为正',
        action: 'indicators',
        checkLogic: 'macd_histogram > 0',
        reasoning: 'MACD柱线由负转正确认动能方向转多',
        required: true,
      ),
      WorkflowStep(
        description: '放量确认',
        action: 'volume',
        checkLogic: 'volume_ratio > 1.3',
        reasoning: '金叉伴随放量说明资金参与度高，突破有效',
        required: false,
      ),
      WorkflowStep(
        description: 'RSI处于强势区间',
        action: 'indicators',
        checkLogic: 'rsi < 70',
        reasoning: 'RSI在50-70强势区间，趋势可持续而非末端',
        required: false,
      ),
    ],
  ),
];
