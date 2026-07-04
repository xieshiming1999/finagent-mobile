import 'dart:convert';

import '../../../agent/message.dart';
import '../../market/backtest/strategy_review_contract.dart';

class FinancePortfolioMonitorSummary {
  String? build(List<Message> messages) {
    final event = _latestPortfolioMonitorEvent(messages);
    if (event == null) return null;
    final confirmation = _latestAskUserQuestionAnswer(messages);
    if (confirmation == null && !_hasAnyToolCall(messages)) return null;

    final strategyId = _text(event['strategyId'], '-');
    final signal = _text(
      event['signal'] ?? event['status'] ?? event['state'],
      'review',
    );
    final portfolioEvidence = _map(event['portfolioEvidence']);
    final rebalanceDraft = _map(event['rebalanceDraft']);
    final positions = _positions(rebalanceDraft);
    final selectedSymbols = _selectedSymbols(portfolioEvidence, rebalanceDraft);

    return [
      '组合再平衡监控已触发：strategyId=$strategyId；signal=$signal。',
      '',
      '## 组合排序证据',
      '',
      '- 监控模板：portfolio_rebalance_monitor。',
      '- 入选标的：${selectedSymbols.isEmpty ? '-' : selectedSymbols.join('、')}。',
      '- 组合证据：${_describePortfolioEvidence(portfolioEvidence)}',
      '- 再平衡草案：${_describeRebalanceDraft(rebalanceDraft)}',
      if (positions.isNotEmpty) ...[
        '',
        '## 目标权重草案',
        '',
        ...positions.take(5).map(_positionLine),
      ],
      '',
      '## 边界',
      '',
      '- 本轮只复核 StrategySpec ranking evidence 与 rebalanceDraft，不自动调仓。',
      '- 不写入 Portfolio 交易，不调用 XueqiuTrade(buy/sell/transfer)。',
      '- 若后续准备执行模拟盘调仓，必须重新确认组合、权重、价格、金额、费用和风险边界。',
      '- 用户确认结果：${confirmation ?? '未确认；保持观察。'}',
      'strategyReview:${jsonEncode(_strategyReview(strategyId: strategyId, signal: signal, selectedSymbols: selectedSymbols, portfolioEvidence: portfolioEvidence, rebalanceDraft: rebalanceDraft, confirmation: confirmation))}',
    ].join('\n');
  }

  Map<String, dynamic> _strategyReview({
    required String strategyId,
    required String signal,
    required List<String> selectedSymbols,
    required Map<String, dynamic>? portfolioEvidence,
    required Map<String, dynamic>? rebalanceDraft,
    required String? confirmation,
  }) {
    return StrategyReviewContract(
      reviewKind: 'portfolio_rebalance_monitor',
      strategyId: strategyId,
      signal: signal,
      subjects: selectedSymbols,
      evidence: portfolioEvidence ?? const {},
      draft: rebalanceDraft ?? const {},
      boundaries: const [
        'review_only',
        'no_portfolio_mutation',
        'no_xueqiu_trade',
        'requires_explicit_confirmation_before_execution',
      ],
      confirmation: confirmation ?? '',
    ).toJson();
  }

  Map<String, dynamic>? _latestPortfolioMonitorEvent(List<Message> messages) {
    for (final message in messages.reversed) {
      if (message.role != Role.user) continue;
      final index = message.content.lastIndexOf('data:');
      if (index < 0) continue;
      final decoded = _decodeMap(message.content.substring(index + 5).trim());
      if (decoded == null ||
          decoded['template'] != 'portfolio_rebalance_monitor') {
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

  List<Map<String, dynamic>> _positions(Map<String, dynamic>? draft) {
    final positions = draft?['positions'];
    if (positions is! List) return const [];
    return positions
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<String> _selectedSymbols(
    Map<String, dynamic>? evidence,
    Map<String, dynamic>? draft,
  ) {
    final values = <Object?>[
      evidence?['selectedSymbols'],
      _map(evidence?['aggregateMetrics'])?['selectedSymbols'],
      _map(evidence?['portfolioBacktestEvidence'])?['selectedSymbols'],
      draft?['selectedSymbols'],
      _map(draft?['aggregateMetrics'])?['selectedSymbols'],
      _map(draft?['portfolioBacktestEvidence'])?['selectedSymbols'],
    ];
    for (final value in values) {
      if (value is List) {
        final symbols = value
            .map((item) => '$item'.trim())
            .where((item) => item.isNotEmpty)
            .toList();
        if (symbols.isNotEmpty) return symbols;
      }
    }
    final positions = _positions(draft);
    return positions
        .map((row) => '${row['symbol'] ?? row['code'] ?? ''}'.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _describePortfolioEvidence(Map<String, dynamic>? evidence) {
    if (evidence == null) return '-';
    final aggregate = _map(evidence['aggregateMetrics']);
    final risk =
        _map(evidence['portfolioBacktestEvidence']) ??
        _map(evidence['portfolioRiskEvidence']);
    final parts = <String>[
      'mode=${_text(evidence['mode'], '-')}',
      'selected=${_text(evidence['selectedCount'], '-')}',
    ];
    if (aggregate != null) {
      parts.add(
        'expectedReturn=${_text(aggregate['expectedReturnPct'], '-')}%',
      );
      parts.add(
        'portfolioMaxDrawdown=${_text(aggregate['portfolioMaxDrawdownPct'], '-')}%',
      );
    }
    if (risk != null) {
      parts.add('bars=${_text(risk['bars'], '-')}');
      parts.add('return=${_text(risk['portfolioReturnPct'], '-')}%');
    }
    return parts.join('；');
  }

  String _describeRebalanceDraft(Map<String, dynamic>? draft) {
    if (draft == null) return '-';
    return [
      'mode=${_text(draft['mode'], '-')}',
      'rebalanceInterval=${_text(draft['rebalanceInterval'], '-')}',
      'maxPositionWeight=${_text(draft['maxPositionWeight'], '-')}',
      'tradeBoundary=${_text(draft['tradeBoundary'], '-')}',
    ].join('；');
  }

  String _positionLine(Map<String, dynamic> position) {
    final symbol = _text(position['symbol'] ?? position['code'], '-');
    final weight = _num(position['targetWeight']);
    final weightText = weight.isFinite
        ? '${(weight * 100).toStringAsFixed(1)}%'
        : '-';
    return '- $symbol：targetWeight=$weightText；weightCapped=${_text(position['weightCapped'], 'false')}。';
  }

  String _text(Object? value, String fallback) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? fallback : text;
  }

  double _num(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? double.nan;
  }
}
