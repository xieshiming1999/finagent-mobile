import 'dart:convert';

import '../../../agent/message.dart';

class FinancePresetBacktestEvidenceSummary {
  String? build({
    required List<Message> messages,
    required int turnStartIndex,
  }) {
    final rows = <_PresetBacktestEvidence>[];
    for (final message in messages.skip(turnStartIndex)) {
      final result = message.toolResult;
      if (result == null || result.isError) continue;
      final payload = _decodeMap(result.content);
      if (payload == null || payload['action'] != 'backtest') continue;
      final cost = _text(payload['cost_assumption'] ?? payload['cost_model']);
      if (cost == null) continue;
      rows.add(
        _PresetBacktestEvidence(
          symbol: _text(payload['symbol']) ?? '-',
          strategy: _text(payload['strategy'] ?? payload['mode']) ?? '-',
          start: _text(payload['actualStartDate']),
          end: _text(payload['actualEndDate']),
          bars: _text(payload['bars']),
          trades: _text(payload['total_trades']),
          returnPct: _text(payload['total_return_pct']),
          drawdownPct: _text(payload['max_drawdown_pct']),
          cost: cost,
        ),
      );
    }
    if (rows.isEmpty) return null;

    final lines = <String>[
      '## 回测成本假设与证据边界',
      '',
      for (final row in rows)
        '- ${row.symbol} / ${row.strategy}: 成本假设 ${row.cost}；窗口 ${row.windowText}；交易 ${row.trades ?? '-'}；收益 ${row.returnPct ?? '-'}%；最大回撤 ${row.drawdownPct ?? '未返回'}。',
    ];
    return lines.join('\n');
  }

  Map<String, dynamic>? _decodeMap(String content) {
    final text = content.trim();
    if (!text.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  String? _text(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }
}

class _PresetBacktestEvidence {
  final String symbol;
  final String strategy;
  final String? start;
  final String? end;
  final String? bars;
  final String? trades;
  final String? returnPct;
  final String? drawdownPct;
  final String cost;

  const _PresetBacktestEvidence({
    required this.symbol,
    required this.strategy,
    required this.start,
    required this.end,
    required this.bars,
    required this.trades,
    required this.returnPct,
    required this.drawdownPct,
    required this.cost,
  });

  String get windowText {
    final range = start != null && end != null ? '$start ~ $end' : '未返回';
    return bars == null ? range : '$range，$bars 根';
  }
}
