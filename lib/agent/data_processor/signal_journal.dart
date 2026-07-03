import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Persistent signal journal — tracks agent-generated buy/sell signals over time.
class SignalJournal {
  final String basePath;
  late final String _filePath;
  List<Map<String, dynamic>> _signals = [];

  SignalJournal(this.basePath) {
    _filePath = p.join(basePath, 'memory', 'signal_journal.json');
    _load();
  }

  void _load() {
    try {
      final file = File(_filePath);
      if (file.existsSync()) {
        _signals = (jsonDecode(file.readAsStringSync()) as List)
            .cast<Map<String, dynamic>>();
      }
    } catch (_) {}
  }

  void _save() {
    try {
      final dir = Directory(p.dirname(_filePath));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      File(
        _filePath,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_signals));
    } catch (_) {}
  }

  /// Record a new signal
  void record({
    required String code,
    required String name,
    required String signal, // 'buy' | 'sell' | 'hold'
    required String strategy,
    required double price,
    String? reason,
    Map<String, dynamic>? indicators,
  }) {
    _signals.add({
      'id': DateTime.now().millisecondsSinceEpoch,
      'date': DateTime.now().toIso8601String().substring(0, 10),
      'time': DateTime.now().toIso8601String().substring(11, 19),
      'code': code,
      'name': name,
      'signal': signal,
      'strategy': strategy,
      'price': price,
      'reason': reason,
      'indicators': indicators,
      'outcome': null, // filled later by trackOutcome
    });
    if (_signals.length > 1000) {
      _signals = _signals.sublist(_signals.length - 1000);
    }
    _save();
  }

  /// Update outcome for a previous signal (after N days)
  void trackOutcome(int signalId, double currentPrice) {
    final signal = _signals.firstWhere(
      (s) => s['id'] == signalId,
      orElse: () => {},
    );
    if (signal.isEmpty) return;
    final entryPrice = signal['price'] as double? ?? 0;
    if (entryPrice <= 0) return;
    signal['outcome'] = {
      'current_price': currentPrice,
      'return_pct': ((currentPrice - entryPrice) / entryPrice * 100)
          .toStringAsFixed(2),
      'tracked_at': DateTime.now().toIso8601String().substring(0, 10),
    };
    _save();
  }

  /// Get recent signals
  List<Map<String, dynamic>> recent({
    int limit = 20,
    String? code,
    String? signal,
  }) {
    var result = List<Map<String, dynamic>>.from(_signals.reversed);
    if (code != null) result = result.where((s) => s['code'] == code).toList();
    if (signal != null) {
      result = result.where((s) => s['signal'] == signal).toList();
    }
    return result.take(limit).toList();
  }

  /// Get accuracy stats
  Map<String, dynamic> stats() {
    final withOutcome = _signals.where((s) => s['outcome'] != null).toList();
    if (withOutcome.isEmpty) return {'total': _signals.length, 'tracked': 0};

    final buySignals = withOutcome.where((s) => s['signal'] == 'buy').toList();
    final sellSignals = withOutcome
        .where((s) => s['signal'] == 'sell')
        .toList();

    int buyCorrect = 0;
    for (final s in buySignals) {
      final ret =
          double.tryParse(s['outcome']['return_pct']?.toString() ?? '0') ?? 0;
      if (ret > 0) buyCorrect++;
    }

    int sellCorrect = 0;
    for (final s in sellSignals) {
      final ret =
          double.tryParse(s['outcome']['return_pct']?.toString() ?? '0') ?? 0;
      if (ret < 0) sellCorrect++;
    }

    return {
      'total': _signals.length,
      'tracked': withOutcome.length,
      'buy_signals': buySignals.length,
      'buy_correct': buyCorrect,
      'buy_accuracy': buySignals.isEmpty
          ? 0
          : (buyCorrect / buySignals.length * 100).round(),
      'sell_signals': sellSignals.length,
      'sell_correct': sellCorrect,
      'sell_accuracy': sellSignals.isEmpty
          ? 0
          : (sellCorrect / sellSignals.length * 100).round(),
    };
  }
}
