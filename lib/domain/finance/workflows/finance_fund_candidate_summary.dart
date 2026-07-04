import 'dart:convert';

import '../../../agent/message.dart';
import '../../market/analysis/analysis_evidence_contract.dart';

/// Finance-owned fund candidate budget summary.
///
/// This keeps fund candidate scoring and generated fund prose out of the
/// generic agent loop. The summary consumes structured tool output only;
/// provider-specific payload parsing belongs below the data normalizer boundary.
class FinanceFundCandidateSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
    required String failureSummary,
  }) {
    Map<String, dynamic>? fundList;
    Map<String, dynamic>? fundScreen;
    Map<String, dynamic>? fundPerformance;
    Map<String, dynamic>? fundNav;
    Map<String, dynamic>? coverage;
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
          case 'fund_screen':
            candidateContractSeen = true;
            fundScreen ??= decoded;
            break;
          case 'fund_list':
            fundList ??= decoded;
            break;
          case 'fund_performance':
          case 'query_fund_performance':
            candidateContractSeen = true;
            fundPerformance ??= decoded;
            break;
          case 'query_fund_nav':
            fundNav ??= decoded;
            break;
          case 'reusable_summary':
            coverage ??= decoded;
            break;
        }
      } catch (_) {}
    }

    final structuredCandidates = _fundCandidateRows(
      fundScreen,
      fundPerformance,
    );
    if (!candidateContractSeen) return null;

    final displayCandidates = structuredCandidates
        .take(3)
        .toList(growable: false);
    final comparisonFunds = _mapRows(
      fundList?['data'],
    ).take(4).toList(growable: false);
    if (displayCandidates.isEmpty && comparisonFunds.length >= 2) {
      return _buildFundComparisonSummary(
        funds: comparisonFunds,
        fundList: fundList,
        fundPerformance: fundPerformance,
        fundNav: fundNav,
        coverage: coverage,
        failureSummary: failureSummary,
      );
    }

    final lines = <String>[
      '已达到本轮受控数据调用预算，下面直接使用已经取得的基金证据给出观察候选；未继续调用更多 provider，也未加入观察池或触发交易。',
      '',
      '## 基金关注候选',
      '',
    ];
    if (displayCandidates.isEmpty) {
      lines.add('本轮基金候选合同已执行，但没有返回可用候选行；因此不能给出具体基金名单。');
      lines.add('');
    } else if (displayCandidates.length < 3) {
      lines.add(
        '本轮结构化筛选只返回 ${displayCandidates.length} 个可用候选，因此覆盖度偏低；以下结果只能作为有限样本观察，不应视为完整基金池筛选。',
      );
      lines.add('');
    }
    for (var i = 0; i < displayCandidates.length; i++) {
      final row = displayCandidates[i];
      final name = _textValue(_fundName(row), fallback: '-');
      final code = _textValue(row['code'], fallback: '-');
      final type = _textValue(
        row['fund_type'],
        fallback: 'fund_list 未提供结构化类型字段',
      );
      lines.add('${i + 1}. $name $code');
      lines.add('   - 类型：$type。');
      lines.add(
        '   - 证据：近1年 ${_fmtPct(row['return_1y'])}，近3年 ${_fmtPct(row['return_3y'])}，近6月 ${_fmtPct(row['return_6m'])}，今年以来 ${_fmtPct(row['return_ytd'])}。',
      );
      lines.add(
        '   - 数据时间：${_textValue(row['metric_date'], fallback: fundScreen?['sourceDataTime'] ?? fundPerformance?['sourceDataTime'])}；来源：${_textValue(row['provider'], fallback: fundScreen?['source'] ?? fundPerformance?['source'] ?? 'local fund_performance_metrics')}；缓存状态：${fundScreen?['cacheStatus'] ?? fundPerformance?['cacheStatus'] ?? '-'}；获取时间：${_textValue(row['fetched_at'], fallback: fundScreen?['fetchedAt'] ?? fundPerformance?['fetchedAt'])}。',
      );
    }
    lines.addAll([
      '',
      '## 数据来源与覆盖',
      '',
      '- 筛选结果：${_fundEvidenceSummary(fundScreen, 'fund_screen')}',
      '- 基金列表：${_fundEvidenceSummary(fundList, 'fund_list')}',
      '- 业绩指标：${_fundEvidenceSummary(fundPerformance, 'fund_performance')}',
      '- NAV 明细：${_fundEvidenceSummary(fundNav, 'fund_nav')}',
      '- 本地覆盖：${_fundCoverageSummary(coverage)}',
      '',
      '## 结论边界',
      '',
      '- 本回答是基金观察候选，不是买入建议。',
      '- ${_fundCategoryBoundary(displayCandidates)}普通基金用净值和阶段收益；货币基金应使用万份收益/七日年化，不能套用普通净值逻辑。',
      '- 本轮没有使用股票 K 线形态、资金流或个股买卖信号替代基金评价。',
      '- 后续进入买入或定投前，需要补充费率、规模、回撤、持仓、基金经理稳定性和个人风险偏好。',
      '- 本轮失败/跳过：$failureSummary',
    ]);
    lines.addAll([
      '',
      'analysisEvidence:${jsonEncode(_fundCandidateAnalysisEvidence(candidates: displayCandidates, fundScreen: fundScreen, fundList: fundList, fundPerformance: fundPerformance, fundNav: fundNav, coverage: coverage, failureSummary: failureSummary))}',
    ]);
    return lines.join('\n');
  }

  String _buildFundComparisonSummary({
    required List<Map<String, dynamic>> funds,
    required Map<String, dynamic>? fundList,
    required Map<String, dynamic>? fundPerformance,
    required Map<String, dynamic>? fundNav,
    required Map<String, dynamic>? coverage,
    required String failureSummary,
  }) {
    final lines = <String>[
      '已达到本轮受控数据调用预算，下面直接使用已经取得的基金身份、净值和收益证据完成对比；未继续调用更多 provider，也未加入观察池或触发交易。',
      '',
      '## 基金对比结论',
      '',
    ];
    for (var i = 0; i < funds.length; i++) {
      final row = funds[i];
      final code = _textValue(row['code'], fallback: '-');
      final name = _textValue(_fundName(row), fallback: code);
      final category = _textValue(
        row['fund_category'] ?? row['fundCategory'] ?? row['fund_type'],
        fallback: 'unknown',
      );
      lines.add('${i + 1}. $name $code');
      lines.add('   - 结构化类别：$category。');
      lines.add(
        '   - 评价口径：${category == 'money' ? '货币基金应看万份收益/七日年化，不按普通 NAV 涨跌评价。' : '普通基金应看 NAV、阶段收益、回撤和持仓风险。'}',
      );
    }
    lines.addAll([
      '',
      '## 证据与充分性',
      '',
      '- 基金身份：${_fundEvidenceSummary(fundList, 'fund_list')}',
      '- 普通净值：${_fundEvidenceSummary(fundNav, 'fund_nav')}',
      '- 业绩指标：${_fundEvidenceSummary(fundPerformance, 'fund_performance')}',
      '- 本地覆盖：${_fundCoverageSummary(coverage)}',
      '- 货币基金收益：若已调用 query_fund_money_yield，使用万份收益/七日年化作为货币基金证据；普通 NAV 缺失不代表货币基金数据失败。',
      '',
      '## 长期观察建议',
      '',
      '- 如果目标是观察权益市场波动和主动管理基金表现，优先观察普通/混合基金，但必须补充回撤、持仓集中度、基金经理和费率证据。',
      '- 如果目标是现金管理或利率环境观察，优先观察货币基金的万份收益与七日年化变化，不应与普通基金 NAV 收益直接相除比较。',
      '- 本轮不执行买入、观察池写入或监控创建。',
      '- 本轮失败/跳过：$failureSummary',
      '',
      'analysisEvidence:${jsonEncode(_fundCandidateAnalysisEvidence(candidates: funds, fundScreen: null, fundList: fundList, fundPerformance: fundPerformance, fundNav: fundNav, coverage: coverage, failureSummary: failureSummary))}',
    ]);
    return lines.join('\n');
  }

  String _fundCategoryBoundary(List<Map<String, dynamic>> candidates) {
    final categories = candidates
        .map(
          (row) => _textValue(
            row['fund_category'] ?? row['fundCategory'] ?? row['fund_type'],
          ),
        )
        .where((value) => value.isNotEmpty && value != '-')
        .toSet()
        .toList(growable: false);
    if (categories.isEmpty) return '本轮候选未返回结构化基金类别；';
    return '本轮候选结构化类别：${categories.join('、')}；';
  }

  List<Map<String, dynamic>> _fundCandidateRows(
    Map<String, dynamic>? fundScreen,
    Map<String, dynamic>? fundPerformance,
  ) {
    final screenRows = _mapRows(fundScreen?['candidates']);
    if (screenRows.length >= 3) return screenRows;
    final performanceRows = _mapRows(
      fundPerformance?['data'],
    ).map(_normalizeFundCandidateRow).where(_validFundCandidateRow).toList();
    performanceRows.sort(
      (a, b) => _fundCandidateScore(b).compareTo(_fundCandidateScore(a)),
    );
    return performanceRows.take(8).toList(growable: false);
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

  bool _validFundCandidateRow(Map<String, dynamic> row) {
    final code = _textValue(row['code']);
    if (!RegExp(r'^\d{6}$').hasMatch(code)) return false;
    final name = _fundName(row);
    if (name.isEmpty) return false;
    return [
      row['return_1y'],
      row['return_3y'],
      row['return_6m'],
      row['return_ytd'],
    ].any((value) => _numValue(value).isFinite);
  }

  double _fundCandidateScore(Map<String, dynamic> row) {
    double value(Object? input) {
      final parsed = _numValue(input);
      return parsed.isFinite ? parsed : 0;
    }

    return value(row['return_1y']) * 0.35 +
        value(row['return_3y']) * 0.25 +
        value(row['return_6m']) * 0.25 +
        value(row['return_ytd']) * 0.15;
  }

  Map<String, dynamic> _fundCandidateAnalysisEvidence({
    required List<Map<String, dynamic>> candidates,
    required Map<String, dynamic>? fundScreen,
    required Map<String, dynamic>? fundList,
    required Map<String, dynamic>? fundPerformance,
    required Map<String, dynamic>? fundNav,
    required Map<String, dynamic>? coverage,
    required String failureSummary,
  }) {
    final codes = candidates
        .map((row) => _textValue(row['code']))
        .where((code) => code.isNotEmpty && code != '-')
        .toList(growable: false);
    final sourcePayload = fundScreen ?? fundPerformance ?? fundList;
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.candidateResearch,
      subjectType: AnalysisSubjectType.candidateSet,
      subjectId: codes.join(','),
      subjectName: 'fund candidate set',
      observedFacts: [
        'candidateCount=${candidates.length}',
        if (codes.isNotEmpty) 'topCandidates=${codes.join(',')}',
        if (fundScreen != null) 'fund_screen:available',
        if (fundPerformance != null) 'fund_performance:available',
        if (fundList != null) 'fund_list:available',
        if (fundNav != null) 'fund_nav:available',
      ],
      interpretations: [
        'fund_candidates:observation_only',
        'candidate_selection:bounded_budget_summary',
        'fund_signals:not_stock_technical_proxy',
      ],
      missingEvidence: [
        if (fundNav == null) 'fund_nav_confirmation',
        'fee_confirmation',
        'fund_size_confirmation',
        'drawdown_confirmation',
        'holding_concentration_confirmation',
        'fund_manager_stability_confirmation',
        'user_risk_preference',
        'strategy_validation',
        if (failureSummary.trim().isNotEmpty && failureSummary.trim() != 'none')
          'visible_failures:$failureSummary',
      ],
      confidence: candidates.length >= 3
          ? AnalysisConfidence.medium
          : AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.candidate,
      sourceCoverage: AnalysisSourceCoverage(
        sources: [
          _textValue(
            sourcePayload?['source'] ?? sourcePayload?['provider'],
            fallback: 'local fund data',
          ),
        ],
        interfaceId: _textValue(
          sourcePayload?['interfaceId'],
          fallback: 'fund.candidate_research',
        ),
        capabilityId: _textValue(
          sourcePayload?['capabilityId'],
          fallback: 'local.cache',
        ),
        canonicalSchema: _textValue(
          sourcePayload?['canonicalSchema'],
          fallback: 'fund_performance_metrics',
        ),
        canonicalTable: _textValue(
          sourcePayload?['canonicalTable'],
          fallback: 'fund_performance_metrics',
        ),
        readbackAction: _textValue(
          sourcePayload?['action'],
          fallback: 'fund_candidate_summary',
        ),
        sourceDataTime: _textValue(
          sourcePayload?['sourceDataTime'] ?? sourcePayload?['latest'],
        ),
        fetchedAt: _textValue(sourcePayload?['fetchedAt']),
        cacheStatus: _textValue(sourcePayload?['cacheStatus']),
        coverageStatus: coverage != null || fundScreen != null
            ? AnalysisCoverageStatus.sufficientForAnalysis
            : AnalysisCoverageStatus.partial,
      ),
    ).toJson();
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

  String _fundCoverageSummary(Map<String, dynamic>? payload) {
    if (payload == null) return '未取得 data.coverage。';
    final nav = payload['fund_nav'];
    final holding = payload['fund_holding'];
    if (nav is Map || holding is Map) {
      final navRows = nav is Map ? nav['rows'] : '-';
      final navCodes = nav is Map ? nav['codes'] : '-';
      final navLatest = nav is Map ? nav['latest'] : '-';
      final holdingRows = holding is Map ? holding['rows'] : '-';
      return 'fund_nav rows=$navRows codes=$navCodes latest=$navLatest；fund_holding rows=$holdingRows。';
    }
    return 'data.coverage 已返回，但未包含可摘要 fund_nav/fund_holding 字段。';
  }

  List<Map<String, dynamic>> _mapRows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _textValue(Object? value, {String fallback = ''}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  double _numValue(Object? value) {
    if (value is num) return value.toDouble();
    if (value == null) return double.nan;
    final text = value.toString().trim().replaceAll('%', '');
    return double.tryParse(text) ?? double.nan;
  }

  String _fmtPct(Object? value) {
    final parsed = _numValue(value);
    if (!parsed.isFinite) return '-';
    return '${parsed.toStringAsFixed(2)}%';
  }
}
