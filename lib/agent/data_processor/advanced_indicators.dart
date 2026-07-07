import 'dart:math';

import '../data_fetcher/models.dart';

/// Advanced technical indicators used by strategy and analysis workflows.

class AdvancedIndicators {
  // ─── Ichimoku Cloud ───

  static ({
    List<double?> tenkan,
    List<double?> kijun,
    List<double?> spanA,
    List<double?> spanB,
    List<double?> chikou,
  })
  ichimoku(
    List<KlineBar> bars, {
    int tenkanPeriod = 9,
    int kijunPeriod = 26,
    int senkouBPeriod = 52,
    int displacement = 26,
  }) {
    final n = bars.length;
    final tenkan = List<double?>.filled(n, null);
    final kijun = List<double?>.filled(n, null);
    final spanA = List<double?>.filled(n + displacement, null);
    final spanB = List<double?>.filled(n + displacement, null);
    final chikou = List<double?>.filled(n, null);

    for (var i = 0; i < n; i++) {
      if (i >= tenkanPeriod - 1) {
        tenkan[i] =
            (_rollHigh(bars, i, tenkanPeriod) +
                _rollLow(bars, i, tenkanPeriod)) /
            2;
      }
      if (i >= kijunPeriod - 1) {
        kijun[i] =
            (_rollHigh(bars, i, kijunPeriod) + _rollLow(bars, i, kijunPeriod)) /
            2;
      }
      if (tenkan[i] != null &&
          kijun[i] != null &&
          i + displacement < spanA.length) {
        spanA[i + displacement] = (tenkan[i]! + kijun[i]!) / 2;
      }
      if (i >= senkouBPeriod - 1 && i + displacement < spanB.length) {
        spanB[i + displacement] =
            (_rollHigh(bars, i, senkouBPeriod) +
                _rollLow(bars, i, senkouBPeriod)) /
            2;
      }
      if (i >= displacement) chikou[i - displacement] = bars[i].close;
    }
    return (
      tenkan: tenkan,
      kijun: kijun,
      spanA: spanA.sublist(0, n),
      spanB: spanB.sublist(0, n),
      chikou: chikou,
    );
  }

  // ─── Pivot Points (3 variants) ───

  static Map<String, double> pivotPoints(KlineBar prevBar) {
    final h = prevBar.high, l = prevBar.low, c = prevBar.close;
    final p = (h + l + c) / 3;
    return {
      'p': p,
      's1': 2 * p - h,
      'r1': 2 * p - l,
      's2': p - (h - l),
      'r2': p + (h - l),
      's3': l - 2 * (h - p),
      'r3': h + 2 * (p - l),
    };
  }

  static Map<String, double> fibonacciPivot(KlineBar prevBar) {
    final h = prevBar.high, l = prevBar.low, c = prevBar.close;
    final p = (h + l + c) / 3;
    final r = h - l;
    return {
      'p': p,
      's1': p - 0.382 * r,
      'r1': p + 0.382 * r,
      's2': p - 0.618 * r,
      'r2': p + 0.618 * r,
      's3': p - r,
      'r3': p + r,
    };
  }

  static Map<String, double> demarkPivot(KlineBar prevBar) {
    final h = prevBar.high,
        l = prevBar.low,
        c = prevBar.close,
        o = prevBar.open;
    final x = c < o
        ? h + 2 * l + c
        : c > o
        ? 2 * h + l + c
        : h + l + 2 * c;
    return {'p': x / 4, 's1': x / 2 - h, 'r1': x / 2 - l};
  }

  // ─── RSRS (Qbot A-share timing indicator) ───

  static ({List<double?> score, List<double?> slope, List<double?> rsq}) rsrs(
    List<KlineBar> bars, {
    int window = 18,
    int normWindow = 600,
  }) {
    final n = bars.length;
    final score = List<double?>.filled(n, null);
    final slopeList = List<double?>.filled(n, null);
    final rsqList = List<double?>.filled(n, null);

    for (var i = window - 1; i < n; i++) {
      // OLS: high ~ low over window
      double sx = 0, sy = 0, sxy = 0, sx2 = 0;
      for (var j = i - window + 1; j <= i; j++) {
        sx += bars[j].low;
        sy += bars[j].high;
        sxy += bars[j].low * bars[j].high;
        sx2 += bars[j].low * bars[j].low;
      }
      final denom = window * sx2 - sx * sx;
      if (denom == 0) continue;
      final slope = (window * sxy - sx * sy) / denom;
      slopeList[i] = slope;

      // R²
      final meanY = sy / window;
      double ssRes = 0, ssTot = 0;
      final intercept = (sy - slope * sx) / window;
      for (var j = i - window + 1; j <= i; j++) {
        final predicted = intercept + slope * bars[j].low;
        ssRes += pow(bars[j].high - predicted, 2);
        ssTot += pow(bars[j].high - meanY, 2);
      }
      final rsq = ssTot > 0 ? 1 - ssRes / ssTot : 0.0;
      rsqList[i] = rsq;

      // Z-score normalize slope over normWindow
      if (i >= normWindow) {
        final slopes = <double>[];
        for (var j = i - normWindow + 1; j <= i; j++) {
          if (slopeList[j] != null) slopes.add(slopeList[j]!);
        }
        if (slopes.length > 2) {
          final mean = slopes.reduce((a, b) => a + b) / slopes.length;
          final std = sqrt(
            slopes.map((s) => pow(s - mean, 2)).reduce((a, b) => a + b) /
                slopes.length,
          );
          score[i] = std > 0 ? (slope - mean) / std * rsq : 0;
        }
      }
    }
    return (score: score, slope: slopeList, rsq: rsqList);
  }

  // ─── TSI (True Strength Index) ───

  static List<double?> tsi(
    List<KlineBar> bars, {
    int longPeriod = 25,
    int shortPeriod = 13,
  }) {
    final n = bars.length;
    final result = List<double?>.filled(n, null);
    if (n < 2) return result;

    final pc = List<double>.filled(n, 0); // price change
    final apc = List<double>.filled(n, 0); // abs price change
    for (var i = 1; i < n; i++) {
      pc[i] = bars[i].close - bars[i - 1].close;
      apc[i] = pc[i].abs();
    }

    final ema1 = _emaDouble(pc, longPeriod);
    final ema2 = _emaDouble(ema1, shortPeriod);
    final aEma1 = _emaDouble(apc, longPeriod);
    final aEma2 = _emaDouble(aEma1, shortPeriod);

    for (var i = 0; i < n; i++) {
      if (aEma2[i] != 0) result[i] = 100 * ema2[i] / aEma2[i];
    }
    return result;
  }

  // ─── Vortex Indicator ───

  static ({List<double?> vip, List<double?> vim}) vortex(
    List<KlineBar> bars, {
    int period = 14,
  }) {
    final n = bars.length;
    final vip = List<double?>.filled(n, null);
    final vim = List<double?>.filled(n, null);
    if (n < period + 1) return (vip: vip, vim: vim);

    for (var i = period; i < n; i++) {
      double vmPlus = 0, vmMinus = 0, tr = 0;
      for (var j = i - period + 1; j <= i; j++) {
        vmPlus += (bars[j].high - bars[j - 1].low).abs();
        vmMinus += (bars[j].low - bars[j - 1].high).abs();
        tr += [
          bars[j].high - bars[j].low,
          (bars[j].high - bars[j - 1].close).abs(),
          (bars[j].low - bars[j - 1].close).abs(),
        ].reduce(max);
      }
      vip[i] = tr > 0 ? vmPlus / tr : 0;
      vim[i] = tr > 0 ? vmMinus / tr : 0;
    }
    return (vip: vip, vim: vim);
  }

  // ─── KST (Know Sure Thing) ───

  static ({List<double?> kst, List<double?> signal}) kst(
    List<KlineBar> bars, {
    int signalPeriod = 9,
  }) {
    final n = bars.length;
    final kstVals = List<double?>.filled(n, null);
    final signalVals = List<double?>.filled(n, null);

    final roc10 = _roc(bars, 10),
        roc15 = _roc(bars, 15),
        roc20 = _roc(bars, 20),
        roc30 = _roc(bars, 30);
    final sma10_10 = _smaDouble(roc10, 10), sma10_15 = _smaDouble(roc15, 10);
    final sma10_20 = _smaDouble(roc20, 10), sma10_30 = _smaDouble(roc30, 15);

    for (var i = 0; i < n; i++) {
      if (sma10_10[i] != null &&
          sma10_15[i] != null &&
          sma10_20[i] != null &&
          sma10_30[i] != null) {
        kstVals[i] =
            1 * sma10_10[i]! +
            2 * sma10_15[i]! +
            3 * sma10_20[i]! +
            4 * sma10_30[i]!;
      }
    }
    // Signal = SMA of KST
    for (var i = signalPeriod - 1; i < n; i++) {
      double sum = 0;
      int count = 0;
      for (var j = i - signalPeriod + 1; j <= i; j++) {
        if (kstVals[j] != null) {
          sum += kstVals[j]!;
          count++;
        }
      }
      if (count > 0) signalVals[i] = sum / count;
    }
    return (kst: kstVals, signal: signalVals);
  }

  // ─── Hurst Exponent ───

  static double? hurst(List<KlineBar> bars, {int minLag = 2, int maxLag = 20}) {
    if (bars.length < maxLag + 10) return null;
    final prices = bars
        .map((b) => bars[0].close > 0 ? log(b.close) : b.close)
        .toList();
    final lags = <double>[], taus = <double>[];

    for (var lag = minLag; lag <= maxLag; lag++) {
      final diffs = <double>[];
      for (var i = lag; i < prices.length; i++) {
        diffs.add(prices[i] - prices[i - lag]);
      }
      if (diffs.length < 2) continue;
      final mean = diffs.reduce((a, b) => a + b) / diffs.length;
      final std = sqrt(
        diffs.map((d) => pow(d - mean, 2)).reduce((a, b) => a + b) /
            diffs.length,
      );
      if (std > 0) {
        lags.add(log(lag.toDouble()) / ln10);
        taus.add(log(std) / ln10);
      }
    }
    if (lags.length < 3) return null;

    // Linear fit: taus = slope * lags + intercept
    final n = lags.length;
    double sx = 0, sy = 0, sxy = 0, sx2 = 0;
    for (var i = 0; i < n; i++) {
      sx += lags[i];
      sy += taus[i];
      sxy += lags[i] * taus[i];
      sx2 += lags[i] * lags[i];
    }
    final slope = (n * sxy - sx * sy) / (n * sx2 - sx * sx);
    return 2 * slope; // H = 2 * slope
  }

  // ─── Shift Distance (趋势度, abu) ───

  static double shiftDistance(List<KlineBar> bars) {
    if (bars.length < 2) return 1;
    double journey = 0;
    for (var i = 1; i < bars.length; i++) {
      journey += (bars[i].close - bars[i - 1].close).abs();
    }
    final displacement = (bars.last.close - bars.first.close).abs();
    return journey > 0
        ? displacement / journey
        : 0; // 1 = perfect trend, 0 = choppy
  }

  // ─── Golden Ratio Levels (abu) ───

  static Map<String, double> goldenLevels(List<KlineBar> bars) {
    final prices = bars.map((b) => b.close).toList()..sort();
    final low = prices.first, high = prices.last;
    final range = high - low;
    return {
      'low': low,
      'high': high,
      'fib_236': low + range * 0.236,
      'fib_382': low + range * 0.382,
      'fib_500': low + range * 0.500,
      'fib_618': low + range * 0.618,
      'fib_786': low + range * 0.786,
      'ext_1272': low + range * 1.272,
      'ext_1618': low + range * 1.618,
    };
  }

  // ─── Helpers ───

  static double _rollHigh(List<KlineBar> bars, int idx, int period) {
    double h = bars[idx].high;
    for (var j = idx - period + 1; j < idx; j++) {
      if (bars[j].high > h) h = bars[j].high;
    }
    return h;
  }

  static double _rollLow(List<KlineBar> bars, int idx, int period) {
    double l = bars[idx].low;
    for (var j = idx - period + 1; j < idx; j++) {
      if (bars[j].low < l) l = bars[j].low;
    }
    return l;
  }

  static List<double> _emaDouble(List<double> data, int period) {
    final result = List<double>.filled(data.length, 0);
    if (data.length < period) return result;
    double sum = 0;
    for (var i = 0; i < period; i++) {
      sum += data[i];
    }
    result[period - 1] = sum / period;
    final k = 2.0 / (period + 1);
    for (var i = period; i < data.length; i++) {
      result[i] = data[i] * k + result[i - 1] * (1 - k);
    }
    return result;
  }

  static List<double?> _roc(List<KlineBar> bars, int period) {
    final r = List<double?>.filled(bars.length, null);
    for (var i = period; i < bars.length; i++) {
      r[i] = bars[i - period].close != 0
          ? (bars[i].close - bars[i - period].close) /
                bars[i - period].close *
                100
          : 0;
    }
    return r;
  }

  static List<double?> _smaDouble(List<double?> data, int period) {
    final r = List<double?>.filled(data.length, null);
    for (var i = period - 1; i < data.length; i++) {
      double s = 0;
      int c = 0;
      for (var j = i - period + 1; j <= i; j++) {
        if (data[j] != null) {
          s += data[j]!;
          c++;
        }
      }
      if (c > 0) r[i] = s / c;
    }
    return r;
  }
}
