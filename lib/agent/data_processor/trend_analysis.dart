// ignore_for_file: curly_braces_in_flow_control_structures

import '../data_fetcher/models.dart';

/// Support/Resistance level detection, trend analysis, price position.
class TrendAnalysis {
  /// Detect support and resistance levels from K-line data.
  static Map<String, dynamic> supportResistance(
    List<KlineBar> bars, {
    int lookback = 60,
  }) {
    final recent = bars.length > lookback
        ? bars.sublist(bars.length - lookback)
        : bars;
    final highs = recent.map((b) => b.high).toList()..sort();
    final lows = recent.map((b) => b.low).toList()..sort();

    // Find clusters of highs/lows as support/resistance
    final resistance = _findClusters(highs.reversed.toList(), threshold: 0.02);
    final support = _findClusters(lows, threshold: 0.02);

    final price = bars.last.close;
    final nearestResistance = resistance.where((r) => r > price).toList();
    final nearestSupport = support.where((s) => s < price).toList();

    return {
      'price': price,
      'resistance': nearestResistance.take(3).map((r) => _r2(r)).toList(),
      'support': nearestSupport.reversed.take(3).map((s) => _r2(s)).toList(),
      'distanceToResistance': nearestResistance.isNotEmpty
          ? _r2((nearestResistance.first - price) / price * 100)
          : null,
      'distanceToSupport': nearestSupport.isNotEmpty
          ? _r2((price - nearestSupport.last) / price * 100)
          : null,
    };
  }

  /// Detect current trend direction.
  static Map<String, dynamic> trendDetection(List<KlineBar> bars) {
    if (bars.length < 60)
      return {'trend': 'unknown', 'reason': 'insufficient data'};

    final ma5 = _lastMA(bars, 5);
    final ma10 = _lastMA(bars, 10);
    final ma20 = _lastMA(bars, 20);
    final ma60 = _lastMA(bars, 60);
    final price = bars.last.close;

    // MA alignment
    final bullishAlignment = ma5 > ma10 && ma10 > ma20 && ma20 > ma60;
    final bearishAlignment = ma5 < ma10 && ma10 < ma20 && ma20 < ma60;

    // Price position relative to MAs
    final aboveAll =
        price > ma5 && price > ma10 && price > ma20 && price > ma60;
    final belowAll =
        price < ma5 && price < ma10 && price < ma20 && price < ma60;

    // Recent change (20-day)
    final recent20 = bars.sublist(bars.length - 20);
    final change20 =
        (price - recent20.first.close) / recent20.first.close * 100;

    // Determine trend
    String trend;
    String strength;
    final reasons = <String>[];

    if (bullishAlignment && aboveAll) {
      trend = 'strong_up';
      strength = 'strong';
      reasons.add('MA多头排列');
      reasons.add('价格在所有均线上方');
    } else if (bullishAlignment || aboveAll) {
      trend = 'up';
      strength = 'moderate';
      if (bullishAlignment) reasons.add('MA多头排列');
      if (aboveAll) reasons.add('价格在均线上方');
    } else if (bearishAlignment && belowAll) {
      trend = 'strong_down';
      strength = 'strong';
      reasons.add('MA空头排列');
      reasons.add('价格在所有均线下方');
    } else if (bearishAlignment || belowAll) {
      trend = 'down';
      strength = 'moderate';
      if (bearishAlignment) reasons.add('MA空头排列');
      if (belowAll) reasons.add('价格在均线下方');
    } else {
      trend = 'sideways';
      strength = 'weak';
      reasons.add('均线纠缠');
    }

    return {
      'trend': trend,
      'strength': strength,
      'reasons': reasons,
      'change20d': _r2(change20),
      'priceVsMA': {
        'ma5': _r2(ma5),
        'ma10': _r2(ma10),
        'ma20': _r2(ma20),
        'ma60': _r2(ma60),
      },
      'maAlignment': bullishAlignment
          ? 'bullish'
          : bearishAlignment
          ? 'bearish'
          : 'mixed',
    };
  }

  /// Bias analysis (乖离率).
  static Map<String, dynamic> biasAnalysis(List<KlineBar> bars) {
    if (bars.length < 20) return {};
    final price = bars.last.close;
    final ma5 = _lastMA(bars, 5);
    final ma10 = _lastMA(bars, 10);
    final ma20 = _lastMA(bars, 20);

    final bias5 = (price - ma5) / ma5 * 100;
    final bias10 = (price - ma10) / ma10 * 100;
    final bias20 = (price - ma20) / ma20 * 100;

    String status;
    if (bias20 > 10) {
      status = 'severely_overbought';
    } else if (bias20 > 5)
      status = 'overbought';
    else if (bias20 < -10)
      status = 'severely_oversold';
    else if (bias20 < -5)
      status = 'oversold';
    else
      status = 'normal';

    return {
      'bias5': _r2(bias5),
      'bias10': _r2(bias10),
      'bias20': _r2(bias20),
      'status': status,
    };
  }

  /// Volume analysis.
  static Map<String, dynamic> volumeAnalysis(List<KlineBar> bars) {
    if (bars.length < 25) return {};
    final recent5 = bars.sublist(bars.length - 5);
    final prev20 = bars.sublist(bars.length - 25, bars.length - 5);

    final avgVol5 = recent5.map((b) => b.volume).reduce((a, b) => a + b) / 5;
    final avgVol20 = prev20.map((b) => b.volume).reduce((a, b) => a + b) / 20;
    final volRatio = avgVol20 > 0 ? avgVol5 / avgVol20 : 1;

    final todayVol = bars.last.volume;
    final todayRatio = avgVol20 > 0 ? todayVol / avgVol20 : 1;

    String pattern;
    if (todayRatio > 3) {
      pattern = 'extreme_volume';
    } else if (todayRatio > 2)
      pattern = 'heavy_volume';
    else if (todayRatio > 1.5)
      pattern = 'above_average';
    else if (todayRatio < 0.5)
      pattern = 'very_light';
    else if (todayRatio < 0.7)
      pattern = 'light';
    else
      pattern = 'normal';

    // Price-volume divergence
    final priceUp = bars.last.close > bars[bars.length - 2].close;
    final volUp = todayRatio > 1;
    String divergence;
    if (priceUp && volUp) {
      divergence = 'price_up_vol_up';
    } else if (priceUp && !volUp)
      divergence = 'price_up_vol_down';
    else if (!priceUp && volUp)
      divergence = 'price_down_vol_up';
    else
      divergence = 'price_down_vol_down';

    return {
      'todayVolume': todayVol,
      'avg5d': _r2(avgVol5),
      'avg20d': _r2(avgVol20),
      'ratioVs20d': _r2(todayRatio.toDouble()),
      'ratio5dVs20d': _r2(volRatio.toDouble()),
      'pattern': pattern,
      'divergence': divergence,
    };
  }

  static List<double> _findClusters(
    List<double> sorted, {
    double threshold = 0.02,
  }) {
    final clusters = <double>[];
    var i = 0;
    while (i < sorted.length) {
      final center = sorted[i];
      var sum = center;
      var count = 1;
      var j = i + 1;
      while (j < sorted.length &&
          (sorted[j] - center).abs() / center < threshold) {
        sum += sorted[j];
        count++;
        j++;
      }
      if (count >= 2) clusters.add(sum / count);
      i = j;
    }
    return clusters;
  }

  static double _lastMA(List<KlineBar> bars, int period) {
    if (bars.length < period) return bars.last.close;
    var sum = 0.0;
    for (var i = bars.length - period; i < bars.length; i++) {
      sum += bars[i].close;
    }
    return sum / period;
  }

  static double _r2(double v) => double.parse(v.toStringAsFixed(2));
}
