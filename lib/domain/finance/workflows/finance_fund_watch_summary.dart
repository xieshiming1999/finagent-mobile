import 'dart:convert';

import '../../../agent/message.dart';
import '../../market/analysis/analysis_evidence_contract.dart';

/// Finance-owned fund watchlist budget summary.
///
/// This helper summarizes a successful fund/ETF Watchlist(add) plus
/// Watchlist(list) readback and nearby fund evidence. The generic agent loop
/// delegates here instead of carrying fund watchlist prose and fund metadata
/// inference directly.
class FinanceFundWatchSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
  }) {
    final toolUsesById = <String, ToolUse>{};
    for (final message in messages.skip(turnStartIndex)) {
      final uses = message.toolUses;
      if (uses == null) continue;
      for (final use in uses) {
        toolUsesById[use.id] = use;
      }
    }

    ToolUse? addUse;
    String? addResult;
    Map<String, dynamic>? listPayload;
    Map<String, dynamic>? fundList;
    Map<String, dynamic>? fundPerformance;
    Map<String, dynamic>? fundNav;

    for (final message in messages.skip(turnStartIndex)) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final use = toolUsesById[result.toolUseId];
      if (use == null) continue;
      final content = result.content.trim();
      if (use.name == 'Watchlist' && use.input['action'] == 'add') {
        final type = _textValue(use.input['type']).toLowerCase();
        if (type == 'fund' || type == 'etf') {
          addUse = use;
          addResult = content;
        }
      } else if (use.name == 'Watchlist' && use.input['action'] == 'list') {
        final decoded = _decodeJsonMap(content);
        if (decoded != null) listPayload = decoded;
      } else if (use.name == 'MarketData') {
        final decoded = _decodeJsonMap(content);
        if (decoded == null) continue;
        switch (decoded['action']) {
          case 'query_fund_list':
          case 'fund_list':
            fundList ??= decoded;
            break;
          case 'query_fund_performance':
          case 'fund_performance':
            fundPerformance ??= decoded;
            break;
          case 'query_fund_nav':
          case 'fund_nav':
            fundNav ??= decoded;
            break;
        }
      }
    }

    if (addUse == null || listPayload == null) return null;
    final symbol = _textValue(addUse.input['symbol'] ?? addUse.input['code']);
    if (symbol.isEmpty) return null;
    final items = _mapRows(listPayload['items']);
    final addId = _watchlistAddedId(addResult);
    final selected =
        (addId == null
            ? null
            : items
                  .where((row) => _textValue(row['id']) == addId)
                  .firstOrNull) ??
        items.reversed
            .where((row) => _textValue(row['symbol'] ?? row['code']) == symbol)
            .firstOrNull;
    if (selected == null) return null;

    final identity = _fundIdentityForSymbol(fundList, symbol);
    final performance = _fundPerformanceForSymbol(fundPerformance, symbol);
    final navSummary = _fundNavSeriesForSymbol(fundNav, symbol);
    final explicitName = _textValue(selected['name'] ?? addUse.input['name']);
    final identityName = identity == null ? '' : _fundName(identity);
    final name = explicitName.isNotEmpty
        ? explicitName
        : (identityName.isNotEmpty ? identityName : symbol);
    final type = identity == null
        ? 'fund_list 未提供结构化类型字段'
        : _textValue(identity['fund_type'], fallback: 'fund_list 未提供结构化类型字段');
    final sourceDataTime = _textValue(
      performance?['metric_date'] ?? navSummary?['endDate'],
      fallback:
          fundPerformance?['sourceDataTime'] ?? fundNav?['sourceDataTime'],
    );
    final fetchedAt = _textValue(
      performance?['fetched_at'] ?? navSummary?['fetchedAt'],
      fallback: fundPerformance?['fetchedAt'] ?? fundNav?['fetchedAt'],
    );
    final provider = _textValue(
      performance?['provider'] ?? navSummary?['source'],
      fallback:
          fundPerformance?['provider'] ??
          fundPerformance?['source'] ??
          fundNav?['source'],
    );
    final entryCondition = _textValue(
      selected['entryCondition'] ?? addUse.input['entryCondition'],
      fallback: '观察条件已写入 Watchlist，需结合后续 NAV 更新触发。',
    );
    final targetEntry = _textValue(
      selected['targetEntryPrice'] ??
          selected['priceAtAdd'] ??
          addUse.input['targetEntryPrice'],
      fallback: '未写入固定目标 NAV',
    );
    final stopLoss = _textValue(
      selected['stopLoss'] ?? addUse.input['stopLoss'],
      fallback: '未写入固定止损 NAV',
    );

    return [
      '已达到本轮受控数据调用预算，下面直接使用已经取得的基金观察池证据作答；预算拦截后的额外请求没有发出 provider 调用。',
      '',
      '## 已加入基金观察池',
      '',
      '- 选择对象：$name $symbol。',
      '- 基金类型：$type。',
      '- 观察条件：$entryCondition',
      '- 目标观察 NAV：$targetEntry；暂停/止损观察位：$stopLoss。',
      '',
      '## 写入与读回',
      '',
      '- Watchlist(add)：${addResult ?? '已成功写入。'}',
      '- Watchlist(list)：count=${listPayload['count'] ?? items.length}；读回 item=${jsonEncode(selected)}。',
      '',
      '## 数据依据',
      '',
      '- 基金身份：${_fundEvidenceSummary(fundList, 'fund_list')}',
      '- 业绩读回：${_fundEvidenceSummary(fundPerformance, 'fund_performance')}',
      '- NAV 读回：${_fundEvidenceSummary(fundNav, 'fund_nav')}',
      '- 本次选中基金业绩：${_fundPerformanceLine(performance)}',
      '- 本次选中基金 NAV：${_fundNavLine(navSummary)}',
      '- 数据时间：$sourceDataTime；获取时间：$fetchedAt；来源：$provider；缓存状态：${fundPerformance?['cacheStatus'] ?? fundNav?['cacheStatus'] ?? '-'}。',
      '',
      '## 边界',
      '',
      '- 这是基金定投/买入观察条件，不是立即买入或交易指令。',
      '- 本轮没有调用 XueqiuTrade，没有执行真实或模拟买入。',
      '- 普通基金使用净值、阶段收益和回撤观察；不使用股票盘口、K 线形态或个股资金流信号替代基金判断。',
      '- 本轮失败/跳过：$failureSummary',
      'analysisEvidence:${jsonEncode(_analysisEvidence(symbol: symbol, name: name, fundType: type, selected: selected, fundList: fundList, fundPerformance: fundPerformance, fundNav: fundNav, performance: performance, navSummary: navSummary, entryCondition: entryCondition, targetEntry: targetEntry, stopLoss: stopLoss, sourceDataTime: sourceDataTime, fetchedAt: fetchedAt, provider: provider, failureSummary: failureSummary))}',
    ].join('\n');
  }

  Map<String, dynamic> _analysisEvidence({
    required String symbol,
    required String name,
    required String fundType,
    required Map<String, dynamic> selected,
    required Map<String, dynamic>? fundList,
    required Map<String, dynamic>? fundPerformance,
    required Map<String, dynamic>? fundNav,
    required Map<String, dynamic>? performance,
    required Map<String, dynamic>? navSummary,
    required String entryCondition,
    required String targetEntry,
    required String stopLoss,
    required String sourceDataTime,
    required String fetchedAt,
    required String provider,
    required String failureSummary,
  }) {
    final hasFundList = _mapRows(fundList?['data']).isNotEmpty;
    final hasPerformance =
        performance != null || _mapRows(fundPerformance?['data']).isNotEmpty;
    final hasNav = navSummary != null || _mapRows(fundNav?['data']).isNotEmpty;
    final coverageStatus = hasFundList && (hasPerformance || hasNav)
        ? AnalysisCoverageStatus.sufficientForAnalysis
        : AnalysisCoverageStatus.partial;
    final sources = <String>{
      _textValue(fundList?['source'] ?? fundList?['provider']),
      _textValue(fundPerformance?['source'] ?? fundPerformance?['provider']),
      _textValue(fundNav?['source'] ?? fundNav?['provider']),
      provider,
      'watchlist',
    }.where((value) => value.isNotEmpty && value != '-').toList();
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.fund,
      subjectType: AnalysisSubjectType.fund,
      subjectId: symbol,
      subjectName: name,
      observedFacts: [
        'fundType=$fundType',
        'entryCondition=$entryCondition',
        'targetEntry=$targetEntry',
        'stopLoss=$stopLoss',
        'watchlistItem=${jsonEncode(selected)}',
        'fundListRows=${_mapRows(fundList?['data']).length}',
        'performanceRows=${_mapRows(fundPerformance?['data']).length}',
        'navRows=${_mapRows(fundNav?['data']).length}',
      ],
      interpretations: const [
        'Fund watchlist add is observation evidence only.',
        'Fund buy/定投 decisions require separate risk preference, fee, drawdown, size, and confirmation evidence.',
      ],
      missingEvidence: [
        if (!hasFundList) 'missing:fund_identity',
        if (!hasPerformance) 'missing:fund_performance',
        if (!hasNav) 'missing:fund_nav_history',
        'missing:user_risk_preference_before_trade',
        'trade_boundary:no_xueqiu_or_portfolio_mutation',
        if (failureSummary.trim().isNotEmpty && failureSummary != 'none')
          'workflow_failures:$failureSummary',
      ],
      confidence: coverageStatus == AnalysisCoverageStatus.sufficientForAnalysis
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: AnalysisSourceCoverage(
        sources: sources,
        interfaceId: hasNav
            ? 'fund.nav_history'
            : (hasPerformance ? 'fund.performance' : 'fund.identity_list'),
        capabilityId: _textValue(
          fundNav?['capabilityId'] ??
              fundPerformance?['capabilityId'] ??
              fundList?['capabilityId'],
        ),
        canonicalSchema: hasNav
            ? 'fund_nav'
            : (hasPerformance ? 'fund_performance_metrics' : 'fund_list'),
        canonicalTable: hasNav
            ? 'fund_nav'
            : (hasPerformance ? 'fund_performance_metrics' : 'fund_list'),
        readbackAction: hasNav
            ? 'query_fund_nav'
            : (hasPerformance ? 'query_fund_performance' : 'query_fund_list'),
        sourceDataTime: sourceDataTime == '-' ? '' : sourceDataTime,
        fetchedAt: fetchedAt == '-' ? '' : fetchedAt,
        cacheStatus: _textValue(
          fundPerformance?['cacheStatus'] ?? fundNav?['cacheStatus'],
        ),
        coverageStatus: coverageStatus,
      ),
    ).toJson();
  }

  Map<String, dynamic>? _decodeJsonMap(String content) {
    if (!content.trimLeft().startsWith('{')) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _watchlistAddedId(String? text) {
    if (text == null) return null;
    return RegExp(r'\(id:\s*([^,\s)]+)').firstMatch(text)?.group(1);
  }

  Map<String, dynamic>? _fundIdentityForSymbol(
    Map<String, dynamic>? payload,
    String symbol,
  ) {
    return _mapRows(payload?['data']).where((row) {
      final code = _textValue(row['code']).replaceAll('.OF', '');
      return code == symbol;
    }).firstOrNull;
  }

  Map<String, dynamic>? _fundPerformanceForSymbol(
    Map<String, dynamic>? payload,
    String symbol,
  ) {
    return _mapRows(payload?['data']).map(_normalizeFundCandidateRow).where((
      row,
    ) {
      final code = _textValue(row['code']).replaceAll('.OF', '');
      return code == symbol;
    }).firstOrNull;
  }

  Map<String, dynamic>? _fundNavSeriesForSymbol(
    Map<String, dynamic>? payload,
    String symbol,
  ) {
    final series = _mapRows(payload?['seriesSummary']).where((row) {
      final code = _textValue(row['code']).replaceAll('.OF', '');
      return code == symbol;
    }).firstOrNull;
    if (series != null) return series;
    final rows = _mapRows(payload?['data']).where((row) {
      final code = _textValue(row['code']).replaceAll('.OF', '');
      return code == symbol;
    }).toList();
    if (rows.isEmpty) return null;
    final first = rows.first;
    final last = rows.last;
    return {
      'rows': rows.length,
      'startDate': first['date'],
      'endDate': last['date'],
      'startNav': first['nav'],
      'endNav': last['nav'],
      'source': last['source'],
      'fetchedAt': last['fetched_at'],
    };
  }

  Map<String, dynamic> _normalizeFundCandidateRow(Map<String, dynamic> row) {
    final raw = row['raw_json'];
    if (raw is! String || !raw.trim().startsWith('{')) return row;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return row;
      return {
        ...row,
        if (_textValue(row['name']).isEmpty || _textValue(row['name']) == '-')
          'name': decoded['name'],
        'return_1y': row['return_1y'] ?? decoded['return_1y'],
        'return_2y': row['return_2y'] ?? decoded['return_2y'],
        'return_3y': row['return_3y'] ?? decoded['return_3y'],
        'return_6m': row['return_6m'] ?? decoded['return_6m'],
        'return_ytd': row['return_ytd'] ?? decoded['return_ytd'],
      };
    } catch (_) {
      return row;
    }
  }

  List<Map<String, dynamic>> _mapRows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _fundName(Map<String, dynamic> row) {
    final direct = _textValue(row['name']);
    if (direct.isNotEmpty) return direct;
    final raw = row['raw_json'];
    if (raw is String && raw.trim().startsWith('{')) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          return _textValue(decoded['name']);
        }
      } catch (_) {
        return '';
      }
    }
    return '';
  }

  String _fundEvidenceSummary(Map<String, dynamic>? payload, String label) {
    if (payload == null) return '$label 未取得。';
    final count = payload['count'] ?? '-';
    final source = payload['source'] ?? payload['provider'] ?? '-';
    final cache = payload['cacheStatus'] ?? payload['cacheDecision'] ?? '-';
    final time = payload['sourceDataTime'] ?? payload['fetchedAt'] ?? '-';
    return '$label count=$count；source=$source；cache=$cache；time=$time。';
  }

  String _fundPerformanceLine(Map<String, dynamic>? row) {
    if (row == null) return '未取得选中基金的阶段业绩行。';
    return 'NAV ${_fmtNum(row['nav'])}；近1周 ${_fmtPct(row['return_1w'])}；近1月 ${_fmtPct(row['return_1m'])}；近6月 ${_fmtPct(row['return_6m'])}；近1年 ${_fmtPct(row['return_1y'])}；近3年 ${_fmtPct(row['return_3y'])}。';
  }

  String _fundNavLine(Map<String, dynamic>? row) {
    if (row == null) return '未取得选中基金的 NAV 序列读回。';
    final ret = row['cumulativeReturnPct'] == null
        ? ''
        : '；区间收益 ${_fmtPct(row['cumulativeReturnPct'])}';
    final dd = row['maxDrawdownPct'] == null
        ? ''
        : '；最大回撤 ${_fmtPct(row['maxDrawdownPct'])}';
    return 'rows=${row['rows'] ?? '-'}；窗口 ${row['startDate'] ?? '-'}~${row['endDate'] ?? '-'}；期初 NAV ${_fmtNum(row['startNav'])}；期末 NAV ${_fmtNum(row['endNav'])}$ret$dd。';
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
