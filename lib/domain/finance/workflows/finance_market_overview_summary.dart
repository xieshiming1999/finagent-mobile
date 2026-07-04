import 'dart:convert';

import '../../../agent/message.dart';
import '../../market/analysis/analysis_evidence_contract.dart';
import 'finance_workflow_state.dart';

/// Finance-owned market overview budget summary.
///
/// The generic agent loop owns the budget guard. This class turns already
/// collected structured finance evidence into a user-facing market answer when
/// the agent attempts more broad data calls after enough evidence exists.
class FinanceMarketOverviewSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
  }) {
    if (!_hasMarketOverviewState(messages, turnStartIndex)) return null;

    Map<String, dynamic>? indexQuote;
    Map<String, dynamic>? sectorRank;
    Map<String, dynamic>? flowRank;
    Map<String, dynamic>? northboundFlow;
    Map<String, dynamic>? unusual;
    Map<String, dynamic>? coverage;
    Map<String, dynamic>? news;

    for (final message in messages.skip(turnStartIndex).toList().reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final content = result.content.trim();
      if (!content.startsWith('{')) continue;
      try {
        final decoded = _decodePayload(content);
        if (decoded == null) continue;
        switch (decoded['action']) {
          case 'query_index_quote':
            indexQuote ??= decoded;
            break;
          case 'query_sector_ranking':
            sectorRank ??= decoded;
            break;
          case 'query_flow_rank':
            flowRank ??= decoded;
            break;
          case 'query_northbound_flow':
          case 'query_northbound':
            northboundFlow ??= decoded;
            break;
          case 'query_unusual':
            unusual ??= decoded;
            break;
          case 'reusable_summary':
            coverage ??= decoded;
            break;
          case 'news':
            news ??= decoded;
            break;
        }
      } catch (_) {}
    }

    if (indexQuote == null && sectorRank == null && news == null) return null;

    final bias = _marketBias(indexQuote, sectorRank);
    final lines = <String>[
      '已达到本轮受控数据调用预算，下面直接使用已经取得的市场证据给出判断；预算拦截后的额外请求没有发出 provider 调用。',
      '',
      '## 市场判断',
      '',
      '- 结论：$bias',
      '- 操作含义：不把单日热点当成确定趋势；优先观察强势板块中的回踩确认，避免在指数或个股短线过热时追高。',
      '',
      '## 已取得证据',
      '',
      '- 指数：${_indexSummary(indexQuote)}',
      '- 热门板块：${_sectorSummary(sectorRank)}',
      '- 资金流：${_flowSummary(flowRank)}',
      '- 北向/互联互通：${_northboundSummary(northboundFlow)}',
      '- 异动股：${_unusualSummary(unusual)}',
      '- 新闻：${_newsSummary(news)}',
      '',
      '## 数据覆盖与缺口',
      '',
      '- 本地覆盖：${_coverageSummary(coverage)}',
      '- 缺口：涨停/跌停池在本轮预算前没有取得结构化结果；异动股读回为空；若要做盘中交易，需要补充更近的涨跌停池、盘口和成交额证据。',
      '- 失败/跳过：$failureSummary',
      'analysisEvidence:${jsonEncode(_marketAnalysisEvidence(indexQuote: indexQuote, sectorRank: sectorRank, flowRank: flowRank, northboundFlow: northboundFlow, unusual: unusual, news: news, coverage: coverage, bias: bias, failureSummary: failureSummary))}',
    ];
    return lines.join('\n');
  }

  Map<String, dynamic> _marketAnalysisEvidence({
    required Map<String, dynamic>? indexQuote,
    required Map<String, dynamic>? sectorRank,
    required Map<String, dynamic>? flowRank,
    required Map<String, dynamic>? northboundFlow,
    required Map<String, dynamic>? unusual,
    required Map<String, dynamic>? news,
    required Map<String, dynamic>? coverage,
    required String bias,
    required String failureSummary,
  }) {
    final sources = <String>{
      ..._sources(indexQuote),
      ..._sources(sectorRank),
      ..._sources(flowRank),
      ..._sources(northboundFlow),
      ..._sources(unusual),
      ..._sources(news),
    }.where((value) => value.trim().isNotEmpty && value != '-').toList();
    final observedFacts = <String>[
      'index=${_rowCount(indexQuote)}',
      'sector=${_rowCount(sectorRank)}',
      'flow=${_rowCount(flowRank)}',
      'northbound=${_rowCount(northboundFlow)}',
      'unusual=${_rowCount(unusual)}',
      'news=${_rowCount(news, key: 'results')}',
      'coverage=${_coverageSummary(coverage)}',
    ];
    final missingEvidence = <String>[
      if (_rowCount(indexQuote) == 0) 'missing:index_quote',
      if (_rowCount(sectorRank) == 0) 'missing:sector_ranking',
      if (_rowCount(flowRank) == 0) 'missing:flow_rank',
      if (_rowCount(northboundFlow) == 0) 'missing:northbound_flow',
      if (_rowCount(unusual) == 0) 'missing:unusual_activity',
      if (_rowCount(news, key: 'results') == 0) 'missing:finance_news',
      'missing:limit_pool_before_budget_stop',
      if (failureSummary.trim().isNotEmpty && failureSummary != 'none')
        'workflow_failures:$failureSummary',
    ];
    final primary = _primaryPayload(
      indexQuote,
      sectorRank,
      flowRank,
      northboundFlow,
      unusual,
      news,
    );
    final coverageStatus =
        _rowCount(indexQuote) > 0 &&
            (_rowCount(sectorRank) > 0 || _rowCount(flowRank) > 0)
        ? AnalysisCoverageStatus.sufficientForAnalysis
        : AnalysisCoverageStatus.partial;
    final confidence =
        coverageStatus == AnalysisCoverageStatus.sufficientForAnalysis
        ? AnalysisConfidence.medium
        : AnalysisConfidence.low;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.market,
      subjectType: AnalysisSubjectType.market,
      subjectId: 'cn-a-share-market-overview',
      subjectName: 'A-share market overview',
      observedFacts: observedFacts,
      interpretations: [bias],
      missingEvidence: missingEvidence,
      confidence: confidence,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: sources.isEmpty ? const ['local readback'] : sources,
        interfaceId: _textValue(primary?['interfaceId']),
        capabilityId: _textValue(primary?['capabilityId']),
        canonicalSchema: _textValue(primary?['canonicalSchema']),
        canonicalTable: _textValue(primary?['canonicalTable']),
        readbackAction: _textValue(
          primary?['readbackAction'] ?? primary?['action'],
        ),
        sourceDataTime: _textValue(primary?['sourceDataTime']),
        fetchedAt: _textValue(primary?['fetchedAt']),
        cacheStatus: _textValue(primary?['cacheStatus']),
        coverageStatus: coverageStatus,
      ),
    ).toJson();
  }

  List<String> _sources(Map<String, dynamic>? payload) {
    if (payload == null) return const [];
    final source = _textValue(payload['source'] ?? payload['provider']);
    final provider = _textValue(payload['provider']);
    return [source, provider].where((value) => value != '-').toList();
  }

  int _rowCount(Map<String, dynamic>? payload, {String key = 'data'}) {
    return _rows(payload, key: key).length;
  }

  Map<String, dynamic>? _primaryPayload(
    Map<String, dynamic>? indexQuote,
    Map<String, dynamic>? sectorRank,
    Map<String, dynamic>? flowRank,
    Map<String, dynamic>? northboundFlow,
    Map<String, dynamic>? unusual,
    Map<String, dynamic>? news,
  ) {
    for (final payload in [
      indexQuote,
      sectorRank,
      flowRank,
      northboundFlow,
      unusual,
      news,
    ]) {
      if (payload != null && _rowCount(payload) > 0) return payload;
    }
    return indexQuote ??
        sectorRank ??
        flowRank ??
        northboundFlow ??
        unusual ??
        news;
  }

  bool _hasMarketOverviewState(List<Message> messages, int turnStartIndex) {
    final state = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: turnStartIndex,
    );
    if (state == null) return false;
    if (state.workflowKind != FinanceWorkflowKind.marketAnalysis) return false;
    return {
          FinanceIntentMode.analysis,
          FinanceIntentMode.review,
        }.contains(state.intentMode) &&
        state.executionMode != FinanceExecutionMode.blocked;
  }

  String _marketBias(
    Map<String, dynamic>? indexQuote,
    Map<String, dynamic>? sectorRank,
  ) {
    final indexRows = _rows(indexQuote);
    final changes = indexRows
        .map((row) => _numValue(row['changePct']))
        .where((value) => value.isFinite)
        .toList();
    final avgChange = changes.isEmpty
        ? double.nan
        : changes.reduce((a, b) => a + b) / changes.length;
    final sectorRows = _rows(sectorRank);
    final positiveSectors = sectorRows
        .where((row) => _numValue(row['change_pct'] ?? row['changePct']) > 0)
        .length;
    if (avgChange.isFinite && avgChange < -2) {
      return positiveSectors >= 3
          ? '指数偏弱但局部板块仍有结构性机会，适合轻仓观察，不适合全面追涨。'
          : '指数偏弱且板块承接不足，短线应偏防守。';
    }
    if (avgChange.isFinite && avgChange > 1) {
      return '指数偏强，适合顺势观察强板块，但仍需确认资金和成交量持续性。';
    }
    return '市场整体偏震荡，重点看板块轮动、资金延续性和新闻催化是否一致。';
  }

  String _indexSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得指数读回。';
    final rows = _rows(payload);
    if (rows.isEmpty) return '${_sourceLine(payload)} 未返回指数行。';
    final text = rows
        .take(6)
        .map((row) {
          return '${_textValue(row['name'], fallback: row['code'])} ${_fmtNum(row['price'])} ${_fmtPct(row['changePct'])}';
        })
        .join('；');
    return '${_sourceLine(payload)} $text。';
  }

  String _sectorSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得板块排行。';
    final rows = _rows(payload);
    if (rows.isEmpty) return '${_sourceLine(payload)} 未返回板块行。';
    final text = rows
        .take(5)
        .map((row) {
          return '${_textValue(row['name'], fallback: row['code'])} ${_fmtPct(row['change_pct'] ?? row['changePct'])}';
        })
        .join('；');
    return '${_sourceLine(payload)} 前列板块：$text。';
  }

  String _flowSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得资金流排行。';
    final rows = _rows(payload);
    if (rows.isEmpty) return '${_sourceLine(payload)} 未返回资金流行。';
    final text = rows
        .take(5)
        .map((row) {
          final amount = _numValue(
            row['main_net'] ?? row['net_inflow'] ?? row['amount'],
          );
          final amountText = amount.isFinite
              ? '${(amount / 100000000).toStringAsFixed(2)}亿'
              : '-';
          return '${_textValue(row['name'], fallback: row['code'])} $amountText';
        })
        .join('；');
    return '${_sourceLine(payload)} 前列：$text。';
  }

  String _northboundSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得北向/互联互通读回。';
    final rows = _rows(payload);
    if (rows.isEmpty) return '${_sourceLine(payload)} 未返回行。';
    final text = rows
        .take(3)
        .map((row) {
          return '${_textValue(row['trade_date'])} ${_textValue(row['mutual_type'])} buy=${_fmtNum(row['buy_amount'])} sell=${_fmtNum(row['sell_amount'])}';
        })
        .join('；');
    return '${_sourceLine(payload)} $text。';
  }

  String _unusualSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得异动股读回。';
    final rows = _rows(payload);
    if (rows.isEmpty) return '${_sourceLine(payload)} 本地无匹配异动股行。';
    final text = rows
        .take(5)
        .map((row) {
          return '${_textValue(row['name'], fallback: row['code'])} ${_textValue(row['reason'])}';
        })
        .join('；');
    return '${_sourceLine(payload)} $text。';
  }

  String _newsSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得新闻。';
    final rows = _rows(payload, key: 'results');
    final errors = payload['errors'] is List
        ? (payload['errors'] as List).whereType<Object>().join('；')
        : '';
    if (rows.isEmpty) {
      return '${_sourceLine(payload)} 未返回新闻。${errors.isEmpty ? '' : ' 错误：$errors'}';
    }
    final text = rows
        .take(4)
        .map((row) {
          return '${_textValue(row['date'])} ${_cleanNewsTitle(_textValue(row['title']))}';
        })
        .join('；');
    return '${_sourceLine(payload)} $text。${errors.isEmpty ? '' : ' 部分来源失败：$errors'}';
  }

  String _coverageSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得 data.coverage。';
    final quote = payload['quote_snapshot'];
    final sector = payload['sector_rank'];
    final flow = payload['flow_rank'];
    final news = payload['finance_news'];
    return 'quote_snapshot=${_coveragePart(quote)}；sector_rank=${_coveragePart(sector)}；flow_rank=${_coveragePart(flow)}；finance_news=${_coveragePart(news)}。';
  }

  String _coveragePart(Object? value) {
    if (value is! Map) return '-';
    final rows = value['rows'] ?? '-';
    final latest = value['latest'] ?? '-';
    return 'rows=$rows latest=$latest';
  }

  String _sourceLine(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得';
    return 'interface=${payload['interfaceId'] ?? '-'}；source=${payload['source'] ?? payload['provider'] ?? '-'}；cache=${payload['cacheStatus'] ?? '-'}；dataTime=${payload['sourceDataTime'] ?? '-'}；fetchedAt=${payload['fetchedAt'] ?? '-'}；count=${payload['count'] ?? '-'}';
  }

  List<Map<String, dynamic>> _rows(
    Map<String, dynamic>? payload, {
    String key = 'data',
  }) {
    final rows = payload?[key];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Map<String, dynamic>? _decodePayload(String content) {
    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Some large tool results are intentionally truncated in the session
      // while preserving the leading structured fields. Recover enough
      // provenance and first rows to avoid pretending the evidence is absent.
    }
    final action = _regexValue(content, r'"action"\s*:\s*"([^"]+)"');
    if (action == null) return null;
    final rows = <Map<String, dynamic>>[];
    if (action == 'query_flow_rank') {
      for (final match in RegExp(
        r'"code"\s*:\s*"([^"]+)".{0,240}?"name"\s*:\s*"([^"]+)".{0,240}?"main_net"\s*:\s*([-0-9.]+)',
        dotAll: true,
      ).allMatches(content).take(5)) {
        rows.add({
          'code': match.group(1),
          'name': match.group(2),
          'main_net': double.tryParse(match.group(3) ?? ''),
        });
      }
    }
    return {
      'action': action,
      'interfaceId': _regexValue(content, r'"interfaceId"\s*:\s*"([^"]+)"'),
      'provider': _regexValue(content, r'"provider"\s*:\s*"([^"]+)"'),
      'cacheStatus': _regexValue(content, r'"cacheStatus"\s*:\s*"([^"]+)"'),
      'sourceDataTime': _regexValue(
        content,
        r'"sourceDataTime"\s*:\s*"([^"]+)"',
      ),
      'fetchedAt': _regexValue(content, r'"fetchedAt"\s*:\s*"([^"]+)"'),
      'count': int.tryParse(
        _regexValue(content, r'"count"\s*:\s*([0-9]+)') ?? '',
      ),
      'source': _regexValue(content, r'"source"\s*:\s*"([^"]+)"'),
      'data': rows,
      'truncated': true,
    };
  }

  String? _regexValue(String content, String pattern) {
    return RegExp(pattern, dotAll: true).firstMatch(content)?.group(1);
  }

  String _cleanNewsTitle(String value) {
    return value
        .replaceAll(RegExp(r'</?em>'), '')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

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
