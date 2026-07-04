import 'dart:convert';

import '../../../agent/message.dart';
import '../../../agent/tool.dart';
import '../../market/analysis/analysis_evidence_contract.dart';
import 'finance_workflow_state.dart';

typedef FinanceStockWatchToolCall =
    Future<ToolResult> Function(
      Tool tool,
      String toolUseId,
      Map<String, dynamic> input,
    );

class FinanceStockWatchRecovery {
  Future<String?> build({
    required List<Message> messages,
    required Tool? Function(String name) toolByName,
    required FinanceStockWatchToolCall callTool,
  }) async {
    final latestUserIndex = messages.lastIndexWhere(
      (message) => message.role == Role.user,
    );
    if (latestUserIndex < 0) return null;
    final workflowState = FinanceWorkflowState.latestFromMessages(
      messages,
      turnStartIndex: latestUserIndex,
    );
    if (!_isStockWatchlistState(workflowState)) return null;
    if (_turnUsedWatchlist(messages)) return null;

    final watchlistTool = toolByName('Watchlist');
    if (watchlistTool == null) return null;

    final evidence = _latestEvidence(messages);
    final candidates = _candidateRows(evidence);
    if (candidates.length < 3) return null;

    final addResults = <ToolResult>[];
    for (final candidate in candidates.take(3)) {
      final input = _watchlistInput(candidate, evidence);
      final result = await callTool(
        watchlistTool,
        'auto_stock_watch_add_${DateTime.now().microsecondsSinceEpoch}',
        input,
      );
      addResults.add(result);
      if (result.isError) break;
    }

    final listResult = await callTool(
      watchlistTool,
      'auto_stock_watch_list_${DateTime.now().microsecondsSinceEpoch}',
      const {'action': 'list', 'type': 'stock', 'status': 'watching'},
    );

    final lines = <String>[
      '已基于本轮已取得的治理数据完成股票候选筛选，并按用户要求写入观察池。',
      '',
      '## 已加入观察池',
      '',
    ];
    for (var i = 0; i < candidates.take(3).length; i++) {
      final row = candidates[i];
      final result = i < addResults.length ? addResults[i] : null;
      lines.add('${i + 1}. ${row.name} ${row.code}');
      lines.add(
        '   - 行情：${_fmtNum(row.price)}，涨跌幅 ${_fmtPct(row.changePct)}；来源 ${row.source}。',
      );
      lines.add('   - 触发条件：${_entryCondition(row)}');
      lines.add('   - 风控条件：跌破 ${_fmtNum(row.stopLoss)} 或热度/板块强度明显回落时移出观察。');
      lines.add(
        '   - 写入结果：${result == null ? '未返回写入结果' : result.content.split('\n').first}',
      );
    }
    lines.addAll([
      '',
      '## 数据来源与边界',
      '',
      '- 候选来源：${_sourceLine(evidence.hotRank, 'query_hot_rank')}',
      '- 行情读回：${_sourceLine(evidence.quote, 'query_quote')}',
      '- 板块/指数：${_sourceLine(evidence.sectorRank, 'query_sector_ranking')}；${_sourceLine(evidence.indexQuote, 'query_index_quote')}',
      '- 资金/估值：${_sourceLine(evidence.flowRank, 'query_flow_rank')}；${_sourceLine(evidence.valuation, 'query_stock_daily_valuation')}',
      '- 本轮工具/Provider 失败：${_failureSummary(messages)}',
      '- 观察池读回：${listResult.isError ? listResult.content : 'Watchlist(list) 已返回 watching 股票列表。'}',
      '- 结论边界：这是观察池候选，不是买入建议；本轮没有调用 XueqiuTrade、Portfolio 或真实交易路径。',
      'analysisEvidence:${jsonEncode(_analysisEvidence(candidates: candidates.take(3).toList(growable: false), evidence: evidence, listResult: listResult, failureSummary: _failureSummary(messages)))}',
    ]);
    return lines.join('\n');
  }

  Map<String, dynamic> _analysisEvidence({
    required List<_StockWatchCandidate> candidates,
    required _StockWatchEvidence evidence,
    required ToolResult listResult,
    required String failureSummary,
  }) {
    final hasQuote = _rows(evidence.quote).isNotEmpty;
    final hasHotRank = _rows(evidence.hotRank).isNotEmpty;
    final hasFlow = _rows(evidence.flowRank).isNotEmpty;
    final hasSector = _rows(evidence.sectorRank).isNotEmpty;
    final coverageStatus = hasQuote && (hasHotRank || hasFlow || hasSector)
        ? AnalysisCoverageStatus.sufficientForAnalysis
        : AnalysisCoverageStatus.partial;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.stock,
      subjectType: AnalysisSubjectType.candidateSet,
      subjectId: 'stock-watchlist-candidates',
      subjectName: 'Stock watchlist candidates',
      observedFacts: [
        'candidateCount=${candidates.length}',
        'candidates=${candidates.map((item) => '${item.code}:${item.name}:score=${item.score.toStringAsFixed(2)}').join('|')}',
        'watchlistReadback=${listResult.isError ? 'error' : 'ok'}',
        'quoteRows=${_rows(evidence.quote).length}',
        'hotRankRows=${_rows(evidence.hotRank).length}',
        'flowRows=${_rows(evidence.flowRank).length}',
        'sectorRows=${_rows(evidence.sectorRank).length}',
        'valuationRows=${_rows(evidence.valuation).length}',
      ],
      interpretations: const [
        'Stock watchlist recovery creates observation candidates only.',
        'Entry, stop, and target fields are trigger-preparation evidence, not executed strategy or trade instructions.',
      ],
      missingEvidence: [
        if (!hasQuote) 'missing:stock_quote',
        if (!hasHotRank) 'missing:hot_rank',
        if (!hasFlow) 'missing:flow_rank',
        if (!hasSector) 'missing:sector_ranking',
        'missing:position_sizing_before_trade',
        'trade_boundary:no_xueqiu_or_portfolio_mutation',
        if (failureSummary.trim().isNotEmpty && failureSummary != '无阻断性工具错误。')
          'workflow_failures:$failureSummary',
      ],
      confidence: coverageStatus == AnalysisCoverageStatus.sufficientForAnalysis
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [
          if (hasQuote)
            _text(
              evidence.quote?['source'] ?? evidence.quote?['provider'],
              fallback: 'quote readback',
            ),
          if (hasHotRank)
            _text(
              evidence.hotRank?['source'] ?? evidence.hotRank?['provider'],
              fallback: 'hot rank readback',
            ),
          if (hasFlow)
            _text(
              evidence.flowRank?['source'] ?? evidence.flowRank?['provider'],
              fallback: 'flow rank readback',
            ),
          if (hasSector)
            _text(
              evidence.sectorRank?['source'] ??
                  evidence.sectorRank?['provider'],
              fallback: 'sector readback',
            ),
          'watchlist',
        ],
        interfaceId: hasQuote ? 'stock.quote' : 'stock.hot_rank',
        canonicalSchema: hasQuote ? 'quote_snapshot' : 'hot_rank',
        canonicalTable: hasQuote ? 'quote_snapshot' : 'hot_rank',
        readbackAction: hasQuote ? 'query_quote' : 'query_hot_rank',
        sourceDataTime: _text(evidence.quote?['sourceDataTime'], fallback: ''),
        fetchedAt: _text(evidence.quote?['fetchedAt'], fallback: ''),
        cacheStatus: _text(evidence.quote?['cacheStatus'], fallback: ''),
        coverageStatus: coverageStatus,
      ),
    ).toJson();
  }

  bool _isStockWatchlistState(FinanceWorkflowState? state) {
    if (state == null) return false;
    if (state.workflowKind != FinanceWorkflowKind.stockResearch) return false;
    if (state.assetClass != FinanceAssetClass.stock) return false;
    if (state.executionMode == FinanceExecutionMode.blocked) return false;
    if (state.intentMode != FinanceIntentMode.observe &&
        state.intentMode != FinanceIntentMode.review) {
      return false;
    }
    return state.evidenceRefs.any((ref) {
      final normalized = ref.trim().toLowerCase();
      return normalized == 'watchlist' ||
          normalized == 'watchlist.add' ||
          normalized == 'stock-watchlist-candidates';
    });
  }

  bool _turnUsedWatchlist(List<Message> messages) {
    for (final message in messages) {
      final uses = message.toolUses;
      if (uses == null) continue;
      if (uses.any((use) => use.name == 'Watchlist')) return true;
    }
    return false;
  }

  _StockWatchEvidence _latestEvidence(List<Message> messages) {
    Map<String, dynamic>? quote;
    Map<String, dynamic>? hotRank;
    Map<String, dynamic>? flowRank;
    Map<String, dynamic>? sectorRank;
    Map<String, dynamic>? indexQuote;
    Map<String, dynamic>? valuation;

    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final content = result.content.trim();
      if (!content.startsWith('{')) continue;
      try {
        final decoded = jsonDecode(content);
        if (decoded is! Map<String, dynamic>) continue;
        switch (decoded['action']) {
          case 'query_quote':
            quote ??= decoded;
            break;
          case 'query_hot_rank':
            hotRank ??= decoded;
            break;
          case 'query_flow_rank':
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
        }
      } catch (_) {
        continue;
      }
    }
    return _StockWatchEvidence(
      quote: quote,
      hotRank: hotRank,
      flowRank: flowRank,
      sectorRank: sectorRank,
      indexQuote: indexQuote,
      valuation: valuation,
    );
  }

  List<_StockWatchCandidate> _candidateRows(_StockWatchEvidence evidence) {
    final byCode = <String, Map<String, dynamic>>{};
    for (final row in _rows(evidence.hotRank)) {
      final code = row['code']?.toString().trim() ?? '';
      if (code.isNotEmpty) byCode[code] = {...row};
    }
    for (final row in _rows(evidence.flowRank)) {
      final code = row['code']?.toString().trim() ?? '';
      if (code.isNotEmpty) {
        byCode.update(
          code,
          (old) => {...old, ...row},
          ifAbsent: () => {...row},
        );
      }
    }
    for (final row in _rows(evidence.quote)) {
      final code = row['code']?.toString().trim() ?? '';
      if (code.isNotEmpty) {
        byCode.update(
          code,
          (old) => {...old, ...row},
          ifAbsent: () => {...row},
        );
      }
    }

    final rows = byCode.values
        .map(_candidateFromRow)
        .whereType<_StockWatchCandidate>()
        .toList();
    rows.sort((a, b) => b.score.compareTo(a.score));
    return rows;
  }

  _StockWatchCandidate? _candidateFromRow(Map<String, dynamic> row) {
    final code = row['code']?.toString().trim() ?? '';
    if (code.isEmpty) return null;
    final price = _num(row['price'] ?? row['quote_price']);
    final changePct = _num(row['changePct'] ?? row['quote_change_pct']);
    if (price == null || price <= 0) return null;
    final name = _text(row['name'], fallback: code);
    final rank = _num(row['rank']);
    final flow = _num(row['main_net']);
    final score =
        (changePct ?? 0) +
        (rank == null ? 0 : (100 - rank).clamp(0, 100) / 10) +
        (flow == null ? 0 : flow / 1000000000);
    return _StockWatchCandidate(
      code: code,
      name: name,
      price: price,
      changePct: changePct,
      source: _text(row['source'] ?? row['quote_source'], fallback: '-'),
      sourceDataTime: _text(
        row['timestamp'] ?? row['quote_data_time'] ?? row['trade_date'],
        fallback: '-',
      ),
      fetchedAt: _text(
        row['fetchedAt'] ?? row['fetched_at'] ?? row['quote_fetched_at'],
        fallback: '-',
      ),
      score: score,
    );
  }

  Map<String, dynamic> _watchlistInput(
    _StockWatchCandidate row,
    _StockWatchEvidence evidence,
  ) {
    final target = row.price * 1.08;
    final stopLoss = row.stopLoss;
    return {
      'action': 'add',
      'symbol': row.code,
      'name': row.name,
      'type': 'stock',
      'tags': ['P0筛选', '观察候选'],
      'entryCondition': _entryCondition(row),
      'targetEntryPrice': row.price,
      'stopLoss': stopLoss,
      'targetPrice': target,
      'suggestedWeight': 0.05,
      'score': row.score.round().clamp(0, 100),
      'rating': 'watch',
      'source':
          'MarketData governed readback; quote=${_sourceLine(evidence.quote, 'query_quote')}; hot=${_sourceLine(evidence.hotRank, 'query_hot_rank')}',
    };
  }

  String _entryCondition(_StockWatchCandidate row) {
    final breakout = row.price * 1.03;
    final pullback = row.price * 0.97;
    return '回踩 ${_fmtNum(pullback)} 附近企稳，或放量突破 ${_fmtNum(breakout)} 后再观察入场；未触发前只观察。';
  }

  List<Map<String, dynamic>> _rows(Map<String, dynamic>? payload) {
    final data = payload?['data'];
    if (data is! List) return const [];
    return data
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _sourceLine(Map<String, dynamic>? payload, String label) {
    if (payload == null) return '$label 未取得';
    return 'action=${payload['action'] ?? label}; source=${payload['source'] ?? payload['provider'] ?? '-'}; cache=${payload['cacheStatus'] ?? '-'}; dataTime=${payload['sourceDataTime'] ?? '-'}; fetchedAt=${payload['fetchedAt'] ?? '-'}; count=${payload['count'] ?? '-'}';
  }

  String _failureSummary(List<Message> messages) {
    final failures = <String>[];
    for (final message in messages) {
      final result = message.toolResult;
      if (result == null || !result.isError) continue;
      failures.add(result.content.replaceAll(RegExp(r'\s+'), ' ').trim());
    }
    if (failures.isEmpty) return '无阻断性工具错误。';
    return failures.take(3).join('；');
  }

  num? _num(Object? value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.replaceAll(',', '').trim());
    return null;
  }

  String _text(Object? value, {required String fallback}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  String _fmtNum(num? value) {
    if (value == null || !value.isFinite) return '-';
    return value.toStringAsFixed(2);
  }

  String _fmtPct(num? value) {
    if (value == null || !value.isFinite) return '-';
    return '${value.toStringAsFixed(2)}%';
  }
}

class _StockWatchEvidence {
  final Map<String, dynamic>? quote;
  final Map<String, dynamic>? hotRank;
  final Map<String, dynamic>? flowRank;
  final Map<String, dynamic>? sectorRank;
  final Map<String, dynamic>? indexQuote;
  final Map<String, dynamic>? valuation;

  const _StockWatchEvidence({
    required this.quote,
    required this.hotRank,
    required this.flowRank,
    required this.sectorRank,
    required this.indexQuote,
    required this.valuation,
  });
}

class _StockWatchCandidate {
  final String code;
  final String name;
  final num price;
  final num? changePct;
  final String source;
  final String sourceDataTime;
  final String fetchedAt;
  final num score;

  const _StockWatchCandidate({
    required this.code,
    required this.name,
    required this.price,
    required this.changePct,
    required this.source,
    required this.sourceDataTime,
    required this.fetchedAt,
    required this.score,
  });

  num get stopLoss => price * 0.94;
}
