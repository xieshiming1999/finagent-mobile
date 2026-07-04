import 'dart:convert';

import '../../../agent/message.dart';
import '../../market/analysis/analysis_evidence_contract.dart';

class FinanceFundMonitorSummary {
  String? build(List<Message> messages) {
    final event = _latestFundMonitorEvent(messages);
    if (event == null) return null;
    final confirmation = _latestAskUserQuestionAnswer(messages);
    if (confirmation == null && !_hasAnyToolCall(messages)) return null;

    final strategyId = _text(event['strategyId'], '-');
    final code = _text(
      event['code'] ?? event['fundCode'] ?? event['symbol'],
      '-',
    );
    final signal = _text(
      event['signal'] ?? event['status'] ?? event['state'],
      'review',
    );
    final value = _num(event['value'] ?? event['nav']);
    final monitorDraft = _map(event['monitorDraft']);
    final dcaObservation = _map(event['dcaObservation']);

    return [
      '基金观察监控已触发：strategyId=$strategyId；fund=$code；signal=$signal。',
      '',
      '## 基金观察证据',
      '',
      '- 监控模板：fund_rule_monitor；最新净值/观测值：${_format(value)}。',
      '- 观察规则：${_describe(monitorDraft)}',
      '- 定投观察：${_describe(dcaObservation)}',
      '',
      '## 边界',
      '',
      '- 本轮只进入基金观察复核，不申购、不赎回、不写入雪球模拟盘或 Portfolio 交易。',
      '- 基金策略应继续使用 NAV/yield、回撤、波动、定投节奏等基金数据合同，不使用股票 K 线信号。',
      '- 用户确认结果：${confirmation ?? '未确认；保持观察。'}',
      'analysisEvidence:${jsonEncode(_analysisEvidence(strategyId: strategyId, code: code, signal: signal, value: value, monitorDraft: monitorDraft, dcaObservation: dcaObservation, confirmation: confirmation))}',
    ].join('\n');
  }

  Map<String, dynamic> _analysisEvidence({
    required String strategyId,
    required String code,
    required String signal,
    required double value,
    required Map<String, dynamic>? monitorDraft,
    required Map<String, dynamic>? dcaObservation,
    required String? confirmation,
  }) {
    return AnalysisEvidencePackage(
      kind: AnalysisEvidenceKind.fund,
      subjectType: AnalysisSubjectType.fund,
      subjectId: code,
      subjectName: code,
      observedFacts: [
        'strategyId=$strategyId',
        'signal=$signal',
        'observedValue=${_format(value)}',
        'monitorDraft=${_describe(monitorDraft)}',
        'dcaObservation=${_describe(dcaObservation)}',
        'confirmation=${confirmation ?? 'pending'}',
      ],
      interpretations: const [
        'Fund monitor trigger is observation/review evidence only.',
        'Fund strategy review should use fund NAV/yield, drawdown, volatility, and DCA cadence contracts.',
      ],
      missingEvidence: const [
        'missing:live_fund_nav_readback_if_not_in_event_payload',
        'missing:fee_size_drawdown_manager_context_before_trade',
        'trade_boundary:no_subscription_redemption_or_simulated_trade',
      ],
      confidence: AnalysisConfidence.low,
      strategyReadiness: AnalysisStrategyReadiness.analysisOnly,
      sourceCoverage: const AnalysisSourceCoverage(
        sources: ['fund_rule_monitor event payload'],
        interfaceId: 'fund.monitor_event',
        readbackAction: 'monitor_trigger',
        coverageStatus: AnalysisCoverageStatus.partial,
      ),
    ).toJson();
  }

  Map<String, dynamic>? _latestFundMonitorEvent(List<Message> messages) {
    for (final message in messages.reversed) {
      if (message.role != Role.user) continue;
      final index = message.content.lastIndexOf('data:');
      if (index < 0) continue;
      final decoded = _decodeMap(message.content.substring(index + 5).trim());
      if (decoded == null || decoded['template'] != 'fund_rule_monitor') {
        continue;
      }
      return decoded;
    }
    return null;
  }

  String? _latestAskUserQuestionAnswer(List<Message> messages) {
    final askIds = <String>{};
    for (final message in messages) {
      for (final use in message.toolUses ?? const []) {
        if (use.name == 'AskUserQuestion') askIds.add(use.id);
      }
    }
    for (final message in messages.reversed) {
      final result = message.toolResult;
      if (result == null ||
          result.isError ||
          !askIds.contains(result.toolUseId)) {
        continue;
      }
      final decoded = _decodeMap(result.content.trim());
      if (decoded != null) {
        return _text(
          decoded['answer'] ??
              decoded['selected'] ??
              decoded['choice'] ??
              decoded['response'],
          result.content.trim(),
        );
      }
      return result.content.trim();
    }
    return null;
  }

  bool _hasAnyToolCall(List<Message> messages) {
    return messages.any((message) => (message.toolUses ?? const []).isNotEmpty);
  }

  Map<String, dynamic>? _decodeMap(String content) {
    if (!content.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _map(Object? value) {
    return value is Map ? Map<String, dynamic>.from(value) : null;
  }

  String _text(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? double.nan;
  }

  String _format(double value) {
    return value.isFinite ? value.toStringAsFixed(4) : '-';
  }

  String _describe(Map<String, dynamic>? value) {
    if (value == null) return '-';
    final entries = value.entries
        .where((entry) => entry.value is! Map && entry.value is! List)
        .take(6)
        .map((entry) => '${entry.key}=${entry.value}')
        .toList();
    return entries.isNotEmpty ? entries.join('；') : jsonEncode(value);
  }
}
