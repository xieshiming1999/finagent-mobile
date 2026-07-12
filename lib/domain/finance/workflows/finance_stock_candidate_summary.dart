import 'dart:convert';

import '../../../agent/message.dart';
import '../../market/analysis/analysis_evidence_contract.dart';
import 'finance_macro_evidence_summary.dart';

/// Finance-owned stock candidate budget summary.
///
/// The generic agent loop delegates here when a bounded finance workflow needs
/// to answer from already-collected stock evidence instead of issuing more
/// provider or file-inspection calls.
class FinanceStockCandidateSummary {
  final FinanceMacroEvidenceSummary _macroEvidenceSummary =
      FinanceMacroEvidenceSummary();

  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
  }) {
    Map<String, dynamic>? quote;
    Map<String, dynamic>? hotRank;
    Map<String, dynamic>? flowRank;
    Map<String, dynamic>? sectorRank;
    Map<String, dynamic>? indexQuote;
    Map<String, dynamic>? valuation;
    Map<String, dynamic>? kline;
    Map<String, dynamic>? moneyFlow;
    var candidateContractSeen = false;

    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final content = result.content.trim();
      if (!content.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) continue;
        switch (decoded['action']) {
          case 'quote':
          case 'query_quote':
            candidateContractSeen = true;
            quote ??= decoded;
            break;
          case 'query_hot_rank':
            candidateContractSeen = true;
            hotRank ??= decoded;
            break;
          case 'query_flow_rank':
            candidateContractSeen = true;
            flowRank ??= decoded;
            break;
          case 'query_sector_ranking':
            sectorRank ??= decoded;
            break;
          case 'query_index_quote':
            indexQuote ??= decoded;
            break;
          case 'query_stock_daily_valuation':
            valuation ??= decoded;
            break;
          case 'kline':
          case 'query_kline':
            kline ??= decoded;
            break;
          case 'query_money_flow':
            moneyFlow ??= decoded;
            break;
        }
      } catch (_) {
        continue;
      }
    }
    if (!candidateContractSeen) return null;

    final candidatePayload = quote ?? hotRank ?? flowRank;
    if (candidatePayload == null) return null;
    final quoteRows = (candidatePayload['data'] is List)
        ? candidatePayload['data'] as List
        : const [];
    final candidates =
        quoteRows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .where(
              (row) => (row['code']?.toString().trim().isNotEmpty ?? false),
            )
            .toList()
          ..sort(
            (a, b) => _candidateScore(
              b,
              candidatePayload['action'],
            ).compareTo(_candidateScore(a, candidatePayload['action'])),
          );
    final displayCandidates = candidates.take(3).toList(growable: false);
    final distinctCodes = candidates
        .map((row) => row['code']?.toString().trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet();
    final hasSingleStockAnalysisEvidence =
        distinctCodes.length == 1 &&
        (kline != null || valuation != null || moneyFlow != null);
    final macroEvidence = _macroEvidenceSummary.collect(
      messages,
      turnStartIndex,
    );
    if (hasSingleStockAnalysisEvidence && displayCandidates.isNotEmpty) {
      return _singleStockAnalysisSummary(
        row: displayCandidates.first,
        quote: candidatePayload,
        valuation: valuation,
        kline: kline,
        moneyFlow: moneyFlow,
        macroEvidence: macroEvidence,
        failureSummary: failureSummary,
      );
    }

    final hotCodes = _rankCodes(hotRank);
    final flowCodes = _rankCodes(flowRank);
    final lines = <String>[
      '已达到本轮受控数据调用预算，下面直接使用已经取得的证据给出观察候选；未继续调用更多 provider，也未加入观察池或触发交易。',
      '',
    ];
    if (macroEvidence.hasMacroEvidence) {
      lines.addAll(_macroEvidenceSummary.buildSection(macroEvidence));
      lines.add('');
    }
    lines.addAll(['## 观察候选', '']);
    if (displayCandidates.isEmpty) {
      lines.add('本轮候选合同已执行，但没有返回可用候选行；因此不能给出具体股票名单。');
      lines.add('');
    } else if (displayCandidates.length < 3) {
      lines.add(
        '本轮结构化候选合同只返回 ${displayCandidates.length} 个可用候选，因此覆盖度偏低；以下结果只能作为有限样本观察。',
      );
      lines.add('');
    }
    for (var i = 0; i < displayCandidates.length; i++) {
      final row = displayCandidates[i];
      final code = row['code']?.toString() ?? '-';
      final name = _textValue(row['name'], fallback: code);
      final price = _fmtNum(row['price'] ?? row['quote_price']);
      final changePct = _fmtPct(row['changePct'] ?? row['quote_change_pct']);
      final source = _textValue(
        row['source'],
        fallback: candidatePayload['source'],
      );
      final dataTime = _textValue(
        row['timestamp'] ?? row['quote_data_time'] ?? row['trade_date'],
        fallback: candidatePayload['sourceDataTime'],
      );
      final fetchedAt = _textValue(
        row['fetchedAt'] ?? row['fetched_at'] ?? row['quote_fetched_at'],
        fallback: candidatePayload['fetchedAt'],
      );
      final tags = <String>[
        if (hotCodes.contains(code)) '热度榜',
        if (flowCodes.contains(code)) '资金流榜',
      ];
      lines.add('${i + 1}. $name $code');
      lines.add(
        price == '-' && changePct == '-'
            ? '   - 行情：本轮排名行未携带可用价格/涨跌幅，需下一步用 query_quote 补齐。'
            : '   - 行情：$price，涨跌幅 $changePct。',
      );
      lines.add(
        '   - 来源：$source；数据时间：$dataTime；获取时间：$fetchedAt；缓存状态：${candidatePayload['cacheStatus'] ?? '-'}。',
      );
      lines.add(
        '   - 理由：${tags.isEmpty ? '来自本轮候选行情池' : tags.join(' + ')}，按已取得行情涨跌幅排序；仍需后续补充基本面、持续资金流和止损位。',
      );
    }
    lines.addAll([
      '',
      '## 市场与覆盖',
      '',
      '- 指数：${_indexSummary(indexQuote)}',
      '- 板块：${_sectorSummary(sectorRank)}',
      '- 热度：${_sourceLine(hotRank)}',
      '- 资金流：${_sourceLine(flowRank)}',
      '- K线：${_klineBudgetSummary(kline)}',
      '- 估值/基本面：${_valuationBudgetSummary(valuation)}',
      '- 个股资金流：${_moneyFlowBudgetSummary(moneyFlow)}',
      '',
      '## 结论边界',
      '',
      '- 本回答是观察候选，不是买入建议。',
      if (macroEvidence.hasMacroEvidence)
        '- 宏观证据只作为观察条件和失效条件；不能直接变成买入、卖出或仓位信号。',
      '- 已使用 governed MarketData readback/cache-first 证据；预算拦截后的额外请求没有发出 provider 调用。',
      '- 本轮失败/跳过：$failureSummary',
      '- 若要进入下一步，应选择一个候选，再设计入场、止损、止盈和观察条件，并由用户确认是否写入观察池。',
    ]);
    lines.addAll([
      '',
      'analysisEvidence:${jsonEncode(_candidateAnalysisEvidence(candidates: displayCandidates, candidatePayload: candidatePayload, hotRank: hotRank, flowRank: flowRank, sectorRank: sectorRank, indexQuote: indexQuote, valuation: valuation, kline: kline, moneyFlow: moneyFlow, failureSummary: failureSummary))}',
    ]);
    return lines.join('\n');
  }

  double _candidateScore(Map<String, dynamic> row, Object? action) {
    final change = _numValue(row['changePct'] ?? row['quote_change_pct']);
    final rank = _numValue(row['rank']);
    final flow = _numValue(row['main_net']);
    if (action == 'query_hot_rank' && rank.isFinite) return 10000 - rank;
    if (action == 'query_flow_rank' && flow.isFinite) {
      return flow / 100000000;
    }
    if (change.isFinite) return change;
    if (rank.isFinite) return 10000 - rank;
    if (flow.isFinite) return flow / 100000000;
    return 0;
  }

  Set<String> _rankCodes(Map<String, dynamic>? payload) {
    final rows = payload?['data'];
    if (rows is! List) return const {};
    return rows
        .whereType<Map>()
        .map((row) => row['code']?.toString().trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toSet();
  }

  String _sourceLine(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得。';
    return 'action=${payload['action'] ?? '-'}；source=${payload['source'] ?? payload['provider'] ?? '-'}；cache=${payload['cacheStatus'] ?? '-'}；dataTime=${payload['sourceDataTime'] ?? '-'}；fetchedAt=${payload['fetchedAt'] ?? '-'}；count=${payload['count'] ?? '-'}.';
  }

  String _sectorSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得。';
    final rows = payload['data'];
    if (rows is! List || rows.isEmpty) return '${_sourceLine(payload)} 未返回板块行。';
    final top = rows
        .whereType<Map>()
        .take(3)
        .map((row) {
          return '${row['name'] ?? row['code'] ?? '-'} ${_fmtPct(row['change_pct'] ?? row['changePct'])}';
        })
        .join('；');
    return '${_sourceLine(payload)} 前列板块：$top。';
  }

  String _indexSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得。';
    final rows = payload['data'];
    if (rows is! List || rows.isEmpty) return '${_sourceLine(payload)} 未返回指数行。';
    final top = rows
        .whereType<Map>()
        .take(4)
        .map((row) {
          return '${row['name'] ?? row['code'] ?? '-'} ${_fmtNum(row['price'])} ${_fmtPct(row['changePct'])}';
        })
        .join('；');
    return '${_sourceLine(payload)} $top。';
  }

  String _klineBudgetSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得。';
    final rows = payload['data'];
    if (rows is! List || rows.isEmpty) {
      final latest = payload['latest5'];
      if (latest is List && latest.isNotEmpty) {
        final range = _textValue(payload['range']);
        return '${_sourceLine(payload)} symbol=${payload['symbol'] ?? '-'}；窗口=${range.isEmpty ? '-' : range}；bars=${payload['bars'] ?? latest.length}；latestRows=${latest.length}。';
      }
      return '${_sourceLine(payload)} 未返回K线行。';
    }
    final first = rows.first;
    final last = rows.last;
    final start = first is Map ? first['date'] : '-';
    final end = last is Map ? last['date'] : '-';
    return '${_sourceLine(payload)} symbol=${payload['symbol'] ?? '-'}；窗口=$start~$end；bars=${payload['count'] ?? rows.length}。';
  }

  String _valuationBudgetSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得。';
    final rows = payload['data'];
    if (rows is! List || rows.isEmpty) return '${_sourceLine(payload)} 未返回估值行。';
    return '${_sourceLine(payload)} 当前仅返回 ${rows.length} 行，不能代表全市场估值筛选覆盖。';
  }

  String _moneyFlowBudgetSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得。';
    final count = payload['count'];
    return '${_sourceLine(payload)} ${count == 0 ? '本轮候选个股资金流读回为空，不能作为支持理由。' : '已取得个股资金流读回。'}';
  }

  String _singleStockAnalysisSummary({
    required Map<String, dynamic> row,
    required Map<String, dynamic> quote,
    required Map<String, dynamic>? valuation,
    required Map<String, dynamic>? kline,
    required Map<String, dynamic>? moneyFlow,
    required MacroEvidence macroEvidence,
    required String failureSummary,
  }) {
    final code = row['code']?.toString() ?? '-';
    final name = _textValue(row['name'], fallback: code);
    final price = _fmtNum(row['price'] ?? row['quote_price']);
    final changePct = _fmtPct(row['changePct'] ?? row['quote_change_pct']);
    final source = _textValue(row['source'], fallback: quote['source']);
    final dataTime = _textValue(
      row['timestamp'] ?? row['quote_data_time'] ?? row['trade_date'],
      fallback: quote['sourceDataTime'],
    );
    final fetchedAt = _textValue(
      row['fetchedAt'] ?? row['fetched_at'] ?? row['quote_fetched_at'],
      fallback: quote['fetchedAt'],
    );
    final lines = <String>[
      '已达到本轮受控数据调用预算，下面直接使用已经取得的单股分析证据作答；未继续调用更多 provider，也未触发交易。',
      '',
      '## $name $code 分析摘要',
      '',
      '- 行情：$price，涨跌幅 $changePct。',
      '- 行情来源：$source；数据时间：$dataTime；获取时间：$fetchedAt；缓存状态：${quote['cacheStatus'] ?? '-'}。',
      '- K线：${_klineBudgetSummary(kline)}',
      '- 估值/基本面：${_valuationBudgetSummary(valuation)}',
      '- 资金流：${_moneyFlowBudgetSummary(moneyFlow)}',
      '- 风险：${_singleStockRiskSummary(valuation: valuation, kline: kline, moneyFlow: moneyFlow, failureSummary: failureSummary)}',
      if (macroEvidence.hasMacroEvidence || macroEvidence.newsLines.isNotEmpty)
        ..._singleStockMacroLines(macroEvidence),
      '',
      '## 结论边界',
      '',
      '- 本回答是单股研究摘要，不是买入建议。',
      '- 已使用 governed MarketData readback/cache-first 证据；预算拦截后的额外请求没有发出 provider 调用。',
      '- 本轮失败/跳过：$failureSummary',
      '- 若要进入交易或观察池，需要单独给出入场、止损、止盈和仓位规则，并由用户确认。',
      '',
      'analysisEvidence:${jsonEncode(_singleStockAnalysisEvidence(row: row, quote: quote, valuation: valuation, kline: kline, moneyFlow: moneyFlow, failureSummary: failureSummary))}',
    ];
    return lines.join('\n');
  }

  String _singleStockRiskSummary({
    required Map<String, dynamic>? valuation,
    required Map<String, dynamic>? kline,
    required Map<String, dynamic>? moneyFlow,
    required String failureSummary,
  }) {
    final risks = <String>[
      if (valuation == null ||
          _isEmptyRows(valuation['data']) ||
          (valuation['count'] is num && (valuation['count'] as num) == 0))
        '估值/基本面证据不足',
      if (kline == null) '技术面K线证据不足',
      if (moneyFlow == null ||
          _isEmptyRows(moneyFlow['data']) ||
          (moneyFlow['count'] is num && (moneyFlow['count'] as num) == 0))
        '资金流证据不足',
      if (failureSummary.trim().isNotEmpty && failureSummary.trim() != 'none')
        '存在已披露失败或跳过项',
    ];
    if (risks.isEmpty) {
      return '本轮核心证据齐备，但仍需结合仓位、止损和后续验证，不能直接视为买入信号。';
    }
    return '${risks.join('；')}；因此本回答只能作为研究摘要，不能作为交易指令。';
  }

  bool _isEmptyRows(Object? value) => value is! List || value.isEmpty;

  List<String> _singleStockMacroLines(MacroEvidence evidence) {
    return [
      '',
      '## 宏观、政策与新闻证据',
      '',
      '- 官方事实：${evidence.factorLines.isNotEmpty ? evidence.factorLines.take(3).join('；') : '本轮没有命中可复用官方宏观因子；这表示官方宏观事实证据缺失，不表示宏观因素无关。'}',
      '- 研究观点：${evidence.contentLines.isNotEmpty ? evidence.contentLines.take(3).join('；') : evidence.sourceLines.isNotEmpty ? evidence.sourceLines.take(3).join('；') : '本轮没有内容级研究观点读回；来源目录不能替代报告正文。'}',
      '- 新闻线索：${evidence.newsLines.isNotEmpty ? evidence.newsLines.take(3).join('；') : '本轮没有可用新闻读回；新闻缺失不能替代官方或研究证据。'}',
      '- 可靠性/新鲜度/访问：${evidence.reliabilityLines.isNotEmpty ? evidence.reliabilityLines.take(4).join('；') : '证据等级、新鲜度或访问状态缺失。'}',
      '- 资产影响：${evidence.assetImpactLines.isNotEmpty ? evidence.assetImpactLines.take(4).join('；') : '尚未把宏观证据稳定链接到该股票、行业或策略口径。'}',
      '- 置信度影响：${evidence.decisionLines.isNotEmpty ? evidence.decisionLines.take(4).join('；') : '缺少高等级官方事实和内容级研究证据时，单股结论置信度应下调。'}',
      '- 缺失证据：${evidence.missingLines.isNotEmpty ? evidence.missingLines.take(4).join('；') : '仍需核对官方数据、研究正文、行业/公司基本面与资金面证据。'}',
    ];
  }

  Map<String, dynamic> _singleStockAnalysisEvidence({
    required Map<String, dynamic> row,
    required Map<String, dynamic> quote,
    required Map<String, dynamic>? valuation,
    required Map<String, dynamic>? kline,
    required Map<String, dynamic>? moneyFlow,
    required String failureSummary,
  }) {
    final code = row['code']?.toString().trim() ?? '';
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.stock,
      subjectType: AnalysisSubjectType.stock,
      subjectId: code,
      subjectName: _textValue(row['name'], fallback: code),
      observedFacts: [
        'quote=available',
        if (kline != null) 'kline=available',
        if (valuation != null) 'valuation=available',
        if (moneyFlow != null) 'money_flow=available',
      ],
      interpretations: [
        'single_stock_analysis:bounded_budget_summary',
        'trade_action:not_requested',
      ],
      missingEvidence: [
        if (valuation == null) 'valuation_confirmation',
        if (kline == null) 'technical_kline_confirmation',
        if (moneyFlow == null) 'money_flow_confirmation',
        'strategy_validation',
        'user_confirmed_trade_plan',
        if (failureSummary.trim().isNotEmpty && failureSummary.trim() != 'none')
          'visible_failures:$failureSummary',
      ],
      confidence: kline != null && valuation != null
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [_textValue(quote['source'], fallback: 'local')],
        interfaceId: _textValue(quote['interfaceId'], fallback: 'stock.quote'),
        capabilityId: _textValue(quote['capabilityId'], fallback: 'local.cache'),
        canonicalSchema: _textValue(
          quote['canonicalSchema'],
          fallback: 'quote_snapshot',
        ),
        canonicalTable: _textValue(
          quote['canonicalTable'],
          fallback: 'quote_snapshot',
        ),
        readbackAction: _textValue(quote['action'], fallback: 'query_quote'),
        sourceDataTime: _textValue(quote['sourceDataTime']),
        fetchedAt: _textValue(quote['fetchedAt']),
        cacheStatus: _textValue(quote['cacheStatus']),
        coverageStatus: kline != null || valuation != null || moneyFlow != null
            ? AnalysisCoverageStatus.sufficientForAnalysis
            : AnalysisCoverageStatus.partial,
      ),
    ).toJson();
  }

  Map<String, dynamic> _candidateAnalysisEvidence({
    required List<Map<String, dynamic>> candidates,
    required Map<String, dynamic> candidatePayload,
    required Map<String, dynamic>? hotRank,
    required Map<String, dynamic>? flowRank,
    required Map<String, dynamic>? sectorRank,
    required Map<String, dynamic>? indexQuote,
    required Map<String, dynamic>? valuation,
    required Map<String, dynamic>? kline,
    required Map<String, dynamic>? moneyFlow,
    required String failureSummary,
  }) {
    final codes = candidates
        .map((row) => row['code']?.toString().trim() ?? '')
        .where((code) => code.isNotEmpty)
        .toList(growable: false);
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.candidateResearch,
      subjectType: AnalysisSubjectType.candidateSet,
      subjectId: codes.join(','),
      subjectName: 'stock candidate set',
      observedFacts: [
        'candidateCount=${candidates.length}',
        if (codes.isNotEmpty) 'topCandidates=${codes.join(',')}',
        'sourceAction=${candidatePayload['action'] ?? '-'}',
        'sourceCount=${candidatePayload['count'] ?? candidates.length}',
      ],
      interpretations: [
        'stock_candidates:observation_only',
        'candidate_selection:bounded_budget_summary',
        if (hotRank != null) 'hot_rank:available',
        if (flowRank != null) 'flow_rank:available',
        if (sectorRank != null) 'sector_context:available',
        if (indexQuote != null) 'market_index_context:available',
      ],
      missingEvidence: [
        if (valuation == null) 'valuation_confirmation',
        if (kline == null) 'technical_kline_confirmation',
        if (moneyFlow == null) 'single_stock_money_flow_confirmation',
        'position_size_context',
        'user_selected_candidate',
        'strategy_validation',
        if (failureSummary.trim().isNotEmpty && failureSummary.trim() != 'none')
          'visible_failures:$failureSummary',
      ],
      confidence: candidates.length >= 3
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.candidate,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [_textValue(candidatePayload['source'], fallback: 'local')],
        interfaceId: _textValue(
          candidatePayload['interfaceId'],
          fallback: _interfaceForAction(candidatePayload['action']),
        ),
        capabilityId: _textValue(
          candidatePayload['capabilityId'],
          fallback: 'local.cache',
        ),
        canonicalSchema: _textValue(
          candidatePayload['canonicalSchema'],
          fallback: _schemaForAction(candidatePayload['action']),
        ),
        canonicalTable: _textValue(
          candidatePayload['canonicalTable'],
          fallback: _tableForAction(candidatePayload['action']),
        ),
        readbackAction: _textValue(
          candidatePayload['action'],
          fallback: 'candidate_summary',
        ),
        sourceDataTime: _textValue(candidatePayload['sourceDataTime']),
        fetchedAt: _textValue(candidatePayload['fetchedAt']),
        cacheStatus: _textValue(candidatePayload['cacheStatus']),
        coverageStatus: candidates.length >= 3
            ? AnalysisCoverageStatus.sufficientForAnalysis
            : AnalysisCoverageStatus.partial,
      ),
    ).toJson();
  }

  String _interfaceForAction(Object? action) {
    switch (action) {
      case 'query_quote':
        return 'stock.quote';
      case 'query_hot_rank':
        return 'stock.hot_rank';
      case 'query_flow_rank':
        return 'stock.flow_rank';
      default:
        return 'stock.candidate_research';
    }
  }

  String _schemaForAction(Object? action) {
    switch (action) {
      case 'query_quote':
        return 'quote_snapshot';
      case 'query_hot_rank':
        return 'hot_rank';
      case 'query_flow_rank':
        return 'flow_rank';
      default:
        return 'candidate_research';
    }
  }

  String _tableForAction(Object? action) => _schemaForAction(action);

  String _textValue(Object? value, {Object? fallback}) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
    final fallbackText = fallback?.toString().trim() ?? '';
    return fallbackText.isNotEmpty && fallbackText != 'null'
        ? fallbackText
        : '-';
  }

  double _numValue(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? double.negativeInfinity;
  }

  String _fmtNum(Object? value) {
    final n = _numValue(value);
    if (!n.isFinite) return '-';
    return n == n.roundToDouble() ? n.toStringAsFixed(0) : n.toStringAsFixed(2);
  }

  String _fmtPct(Object? value) {
    final n = _numValue(value);
    if (!n.isFinite) return '-';
    return '${n.toStringAsFixed(2)}%';
  }
}
