import '../data_fetcher/models.dart';
import 'indicators.dart';

/// Signal direction.
enum SignalDirection { long, short, flat }

/// Trading signal with direction, confidence, and source.
class Signal {
  final String symbol;
  final SignalDirection direction;
  final double confidence; // 0-1
  final double magnitude; // expected return magnitude
  final String source;
  final String reason;

  Signal({
    required this.symbol,
    required this.direction,
    required this.confidence,
    this.magnitude = 0,
    required this.source,
    this.reason = '',
  });

  Map<String, dynamic> toJson() => {
    'symbol': symbol,
    'direction': direction.name,
    'confidence': double.parse(confidence.toStringAsFixed(2)),
    'magnitude': double.parse(magnitude.toStringAsFixed(4)),
    'source': source,
    if (reason.isNotEmpty) 'reason': reason,
  };
}

/// Signal generator: produces signals from indicators and factors.
class SignalGenerator {
  /// Generate indicator-based signals for a stock.
  static List<Signal> fromIndicators(String symbol, List<KlineBar> bars) {
    if (bars.length < 30) return [];
    final signals = <Signal>[];
    final last = bars.length - 1;

    // RSI
    final rsiVals = Indicators.rsi(bars);
    if (rsiVals[last] != null) {
      final rsi = rsiVals[last]!;
      if (rsi < 30) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.long,
            confidence: (30 - rsi) / 30,
            source: 'RSI',
            reason: 'RSI=${rsi.toStringAsFixed(1)} 超卖',
          ),
        );
      }
      if (rsi > 70) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.short,
            confidence: (rsi - 70) / 30,
            source: 'RSI',
            reason: 'RSI=${rsi.toStringAsFixed(1)} 超买',
          ),
        );
      }
    }

    // MACD cross
    final macd = Indicators.macd(bars);
    if (macd.hist.length >= 2 &&
        macd.hist[last] != null &&
        macd.hist[last - 1] != null) {
      if (macd.hist[last - 1]! <= 0 && macd.hist[last]! > 0) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.long,
            confidence: 0.7,
            source: 'MACD',
            reason: 'MACD金叉',
          ),
        );
      }
      if (macd.hist[last - 1]! >= 0 && macd.hist[last]! < 0) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.short,
            confidence: 0.7,
            source: 'MACD',
            reason: 'MACD死叉',
          ),
        );
      }
    }

    // KDJ
    final kdj = Indicators.kdj(bars);
    if (kdj.j[last] != null) {
      if (kdj.j[last]! < 0) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.long,
            confidence: 0.6,
            source: 'KDJ',
            reason: 'KDJ J值=${kdj.j[last]!.toStringAsFixed(1)} 超卖',
          ),
        );
      }
      if (kdj.j[last]! > 100) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.short,
            confidence: 0.6,
            source: 'KDJ',
            reason: 'KDJ J值=${kdj.j[last]!.toStringAsFixed(1)} 超买',
          ),
        );
      }
    }

    // MA alignment
    final ma5 = Indicators.sma(bars, 5);
    final ma20 = Indicators.sma(bars, 20);
    if (ma5[last] != null && ma20[last] != null) {
      if (ma5[last]! > ma20[last]! && bars[last].close > ma5[last]!) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.long,
            confidence: 0.5,
            source: 'MA',
            reason: '价格在MA5之上且MA5>MA20',
          ),
        );
      }
      if (ma5[last]! < ma20[last]! && bars[last].close < ma5[last]!) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.short,
            confidence: 0.5,
            source: 'MA',
            reason: '价格在MA5之下且MA5<MA20',
          ),
        );
      }
    }

    // Volume surge
    if (bars.length > 25) {
      final avgVol =
          bars
              .sublist(last - 20, last)
              .map((b) => b.volume)
              .reduce((a, b) => a + b) /
          20;
      if (bars[last].volume > avgVol * 2 &&
          bars[last].close > bars[last - 1].close) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.long,
            confidence: 0.6,
            source: 'Volume',
            reason: '放量上涨(${(bars[last].volume / avgVol).toStringAsFixed(1)}倍)',
          ),
        );
      }
    }

    // ADX trend strength
    final adxVals = Indicators.adx(bars);
    if (adxVals.adx[last] != null && adxVals.adx[last]! > 25) {
      if (adxVals.plusDi[last]! > adxVals.minusDi[last]!) {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.long,
            confidence: 0.5,
            source: 'ADX',
            reason: 'ADX=${adxVals.adx[last]!.toStringAsFixed(0)} +DI>-DI 强势趋势',
          ),
        );
      } else {
        signals.add(
          Signal(
            symbol: symbol,
            direction: SignalDirection.short,
            confidence: 0.5,
            source: 'ADX',
            reason: 'ADX=${adxVals.adx[last]!.toStringAsFixed(0)} -DI>+DI 弱势趋势',
          ),
        );
      }
    }

    return signals;
  }

  /// Aggregate multiple signals into a composite score.
  static Map<String, dynamic> aggregate(List<Signal> signals) {
    if (signals.isEmpty) {
      return {'direction': 'flat', 'confidence': 0, 'signals': []};
    }

    double longScore = 0, shortScore = 0;
    for (final s in signals) {
      if (s.direction == SignalDirection.long) longScore += s.confidence;
      if (s.direction == SignalDirection.short) shortScore += s.confidence;
    }
    final total = longScore + shortScore;
    final netScore = total > 0 ? (longScore - shortScore) / total : 0;

    String direction;
    String strength;
    if (netScore > 0.3) {
      direction = 'long';
      strength = netScore > 0.6 ? 'strong' : 'moderate';
    } else if (netScore < -0.3) {
      direction = 'short';
      strength = netScore < -0.6 ? 'strong' : 'moderate';
    } else {
      direction = 'flat';
      strength = 'weak';
    }

    return {
      'direction': direction,
      'strength': strength,
      'netScore': double.parse(netScore.toStringAsFixed(2)),
      'longScore': double.parse(longScore.toStringAsFixed(2)),
      'shortScore': double.parse(shortScore.toStringAsFixed(2)),
      'signalCount': signals.length,
      'signals': signals.map((s) => s.toJson()).toList(),
    };
  }
}
