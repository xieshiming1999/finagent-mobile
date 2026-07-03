// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:convert';
import 'dart:io';

import '../../domain/market/services/market_data_resolve_service.dart';

/// AI Backtest Validator: tracks analysis accuracy by comparing
/// past recommendations against actual price movements.
class AIBacktestValidator {
  final MarketDataResolveService _resolveService;
  final String _basePath;

  AIBacktestValidator(this._resolveService, this._basePath);

  String get _filePath => '$_basePath/memory/.ai_backtest.json';

  /// Record an analysis recommendation for later validation.
  void recordAnalysis({
    required String symbol,
    required String direction, // bullish / bearish / neutral
    required double priceAtAnalysis,
    String? targetPrice,
    String? stopLoss,
    String? timeframe, // short / medium / long
    String? strategy,
    String? summary,
  }) {
    final records = _loadRecords();
    records.add({
      'symbol': symbol,
      'direction': direction,
      'priceAtAnalysis': priceAtAnalysis,
      'targetPrice': targetPrice,
      'stopLoss': stopLoss,
      'timeframe': timeframe ?? 'short',
      'strategy': strategy,
      'summary': summary,
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'validated': false,
    });
    _saveRecords(records);
  }

  /// Validate all unvalidated records against actual price movements.
  /// [onValidated] is called for each validated record with (strategy, isCorrect, actualReturn, reflection).
  Future<Map<String, dynamic>> validate({
    void Function(
      String strategy,
      bool isCorrect,
      double actualReturn,
      String reflection,
    )?
    onValidated,
  }) async {
    final records = _loadRecords();
    final unvalidated = records.where((r) => r['validated'] != true).toList();
    if (unvalidated.isEmpty)
      return {'message': 'No pending validations', 'total': records.length};

    var correct = 0, incorrect = 0, pending = 0;

    for (final record in unvalidated) {
      final symbol = record['symbol'] as String;
      final direction = record['direction'] as String;
      final priceAt = (record['priceAtAnalysis'] as num).toDouble();
      final date = record['date'] as String;
      final timeframe = record['timeframe'] as String? ?? 'short';

      // Check if enough time has passed
      final analysisDate = DateTime.tryParse(date);
      if (analysisDate == null) continue;
      final daysSince = DateTime.now().difference(analysisDate).inDays;
      final minDays = switch (timeframe) {
        'short' => 5,
        'medium' => 20,
        'long' => 60,
        _ => 5,
      };

      if (daysSince < minDays) {
        pending++;
        continue;
      }

      try {
        final r = await _resolveService.resolveKline(symbol, startDate: date);
        if (r.bars.isEmpty) continue;

        final bars = r.bars;
        final currentPrice = bars.last.close;
        final actualChange = (currentPrice - priceAt) / priceAt * 100;

        // Alpha vs benchmark (沪深300 ETF)
        double? alpha;
        try {
          final benchR = await _resolveService.resolveKline(
            '510300',
            startDate: date,
          );
          if (benchR.bars.length >= 2) {
            final benchStart = benchR.bars.first.close;
            final benchEnd = benchR.bars.last.close;
            final benchChange = (benchEnd - benchStart) / benchStart * 100;
            alpha = actualChange - benchChange;
          }
        } catch (_) {}

        bool isCorrect;
        if (direction == 'bullish') {
          isCorrect = actualChange > 0;
        } else if (direction == 'bearish')
          isCorrect = actualChange < 0;
        else
          isCorrect = actualChange.abs() < 5;

        record['validated'] = true;
        record['actualChange'] = double.parse(actualChange.toStringAsFixed(2));
        record['alpha'] = alpha != null
            ? double.parse(alpha.toStringAsFixed(2))
            : null;
        record['currentPrice'] = currentPrice;
        record['isCorrect'] = isCorrect;
        record['validatedDate'] = DateTime.now().toIso8601String().substring(
          0,
          10,
        );
        record['reflection'] = _generateReflection(
          record,
          actualChange,
          isCorrect,
        );

        if (isCorrect) {
          correct++;
        } else {
          incorrect++;
        }

        if (onValidated != null) {
          final strategy = record['strategy'] as String? ?? 'unknown';
          onValidated(
            strategy,
            isCorrect,
            actualChange,
            record['reflection'] as String? ?? '',
          );
        }
      } catch (_) {
        pending++;
      }
    }

    _saveRecords(records);

    // Calculate overall accuracy
    final allValidated = records.where((r) => r['validated'] == true).toList();
    final totalCorrect = allValidated
        .where((r) => r['isCorrect'] == true)
        .length;
    final totalValidated = allValidated.length;
    final accuracy = totalValidated > 0
        ? totalCorrect / totalValidated * 100
        : 0;

    // Strategy breakdown
    final strategyStats = <String, Map<String, int>>{};
    for (final r in allValidated) {
      final strategy = r['strategy'] as String? ?? 'unknown';
      strategyStats.putIfAbsent(strategy, () => {'correct': 0, 'total': 0});
      strategyStats[strategy]!['total'] =
          strategyStats[strategy]!['total']! + 1;
      if (r['isCorrect'] == true)
        strategyStats[strategy]!['correct'] =
            strategyStats[strategy]!['correct']! + 1;
    }

    return {
      'action': 'ai_backtest',
      'thisRun': {
        'correct': correct,
        'incorrect': incorrect,
        'pending': pending,
      },
      'overall': {
        'totalAnalyses': records.length,
        'validated': totalValidated,
        'correct': totalCorrect,
        'accuracy': double.parse(accuracy.toStringAsFixed(1)),
      },
      'byStrategy': strategyStats.map(
        (k, v) => MapEntry(k, {
          'total': v['total'],
          'correct': v['correct'],
          'accuracy': v['total']! > 0
              ? double.parse(
                  (v['correct']! / v['total']! * 100).toStringAsFixed(1),
                )
              : 0,
        }),
      ),
      'recentValidations': allValidated.reversed.take(10).toList(),
      'reflections': _collectReflections(records),
    };
  }

  String _generateReflection(
    Map<String, dynamic> record,
    double actualChange,
    bool isCorrect,
  ) {
    final symbol = record['symbol'];
    final direction = record['direction'];
    final strategy = record['strategy'] ?? 'unknown';
    final pct = actualChange >= 0
        ? '+${actualChange.toStringAsFixed(1)}%'
        : '${actualChange.toStringAsFixed(1)}%';
    final result = isCorrect ? '正确' : '错误';

    final directionCall = '方向判断$result($direction→实际$pct)。';
    final String thesisCheck;
    final String lesson;

    if (direction == 'bullish') {
      thesisCheck = isCorrect ? '策略$strategy的看多逻辑得到验证。' : '看多论点未兑现,实际走势相反。';
      lesson = isCorrect
          ? '教训:该策略在类似条件下有效,可继续使用。'
          : '教训:需重新审视是否忽视了下行风险信号或高估了上涨动力。';
    } else if (direction == 'bearish') {
      thesisCheck = isCorrect ? '策略$strategy的看空逻辑得到验证。' : '看空论点未兑现,标的逆势上涨。';
      lesson = isCorrect
          ? '教训:风险识别准确,类似信号可作为减仓依据。'
          : '教训:可能低估了多头力量或忽视了催化剂,需关注反转信号。';
    } else {
      thesisCheck = isCorrect ? '中性判断合理,标的确实横盘震荡。' : '中性判断失误,标的出现明显趋势($pct)。';
      lesson = isCorrect ? '教训:震荡期不宜追涨杀跌,观望策略有效。' : '教训:需提升趋势识别灵敏度,关注突破信号。';
    }

    return '$symbol: $directionCall$thesisCheck$lesson';
  }

  List<String> _collectReflections(List<Map<String, dynamic>> records) {
    return records
        .where((r) => r['reflection'] != null)
        .map((r) => r['reflection'] as String)
        .toList()
        .reversed
        .take(10)
        .toList();
  }

  /// Get summary without running validation.
  Map<String, dynamic> getSummary() {
    final records = _loadRecords();
    final validated = records.where((r) => r['validated'] == true).toList();
    final pending = records.where((r) => r['validated'] != true).length;
    final correct = validated.where((r) => r['isCorrect'] == true).length;
    final accuracy = validated.isNotEmpty
        ? correct / validated.length * 100
        : 0;

    return {
      'total': records.length,
      'validated': validated.length,
      'pending': pending,
      'correct': correct,
      'accuracy': double.parse(accuracy.toStringAsFixed(1)),
    };
  }

  List<Map<String, dynamic>> _loadRecords() {
    final file = File(_filePath);
    if (!file.existsSync()) return [];
    try {
      return (jsonDecode(file.readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  void _saveRecords(List<Map<String, dynamic>> records) {
    final file = File(_filePath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(jsonEncode(records));
  }
}
