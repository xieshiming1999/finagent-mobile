import 'dart:math';

class Candle {
  final String date;
  final double open, high, low, close;
  final double volume;
  final double? turnoverRate;
  Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.volume = 0,
    this.turnoverRate,
  });
}

class Trade {
  final String entryDate, exitDate;
  final double entryPrice, exitPrice;
  double returnPct = 0;
  Trade({
    required this.entryDate,
    required this.entryPrice,
    required this.exitDate,
    required this.exitPrice,
  });
}

// ─── Indicators ───

List<double?> calcEMA(List<double> closes, int period) {
  final result = List<double?>.filled(closes.length, null);
  if (closes.length < period) return result;
  final k = 2.0 / (period + 1);
  double sum = 0;
  for (var i = 0; i < period; i++) {
    sum += closes[i];
  }
  result[period - 1] = sum / period;
  for (var i = period; i < closes.length; i++) {
    result[i] = closes[i] * k + result[i - 1]! * (1 - k);
  }
  return result;
}

List<double?> calcSMA(List<double> closes, int period) {
  final result = List<double?>.filled(closes.length, null);
  if (closes.length < period) return result;
  double sum = 0;
  for (var i = 0; i < period; i++) {
    sum += closes[i];
  }
  result[period - 1] = sum / period;
  for (var i = period; i < closes.length; i++) {
    sum += closes[i] - closes[i - period];
    result[i] = sum / period;
  }
  return result;
}

List<double?> calcRSI(List<double> closes, {int period = 14}) {
  final result = List<double?>.filled(closes.length, null);
  if (closes.length < period + 1) return result;
  double avgGain = 0, avgLoss = 0;
  for (var i = 1; i <= period; i++) {
    final diff = closes[i] - closes[i - 1];
    if (diff > 0) {
      avgGain += diff;
    } else {
      avgLoss -= diff;
    }
  }
  avgGain /= period;
  avgLoss /= period;
  result[period] = avgLoss == 0 ? 100.0 : 100 - (100 / (1 + avgGain / avgLoss));
  for (var i = period + 1; i < closes.length; i++) {
    final diff = closes[i] - closes[i - 1];
    final gain = diff > 0 ? diff : 0.0;
    final loss = diff < 0 ? -diff : 0.0;
    avgGain = (avgGain * (period - 1) + gain) / period;
    avgLoss = (avgLoss * (period - 1) + loss) / period;
    result[i] = avgLoss == 0 ? 100.0 : 100 - (100 / (1 + avgGain / avgLoss));
  }
  return result;
}

({List<double?> upper, List<double?> middle, List<double?> lower})
calcBollinger(List<double> closes, {int period = 20, double stdMult = 2.0}) {
  final n = closes.length;
  final upper = List<double?>.filled(n, null);
  final middle = calcSMA(closes, period);
  final lower = List<double?>.filled(n, null);
  for (var i = period - 1; i < n; i++) {
    final m = middle[i]!;
    double sumSq = 0;
    for (var j = i - period + 1; j <= i; j++) {
      sumSq += (closes[j] - m) * (closes[j] - m);
    }
    final std = sqrt(sumSq / period);
    upper[i] = m + stdMult * std;
    lower[i] = m - stdMult * std;
  }
  return (upper: upper, middle: middle, lower: lower);
}

({List<double?> macd, List<double?> signal, List<double?> histogram}) calcMACD(
  List<double> closes, {
  int fast = 12,
  int slow = 26,
  int signalPeriod = 9,
}) {
  final n = closes.length;
  final emaFast = calcEMA(closes, fast);
  final emaSlow = calcEMA(closes, slow);
  final macdLine = List<double?>.filled(n, null);
  final macdOnly = <double>[];
  final macdIndices = <int>[];
  for (var i = 0; i < n; i++) {
    if (emaFast[i] != null && emaSlow[i] != null) {
      macdLine[i] = emaFast[i]! - emaSlow[i]!;
      macdOnly.add(macdLine[i]!);
      macdIndices.add(i);
    }
  }
  final sigEma = calcEMA(macdOnly, signalPeriod);
  final signal = List<double?>.filled(n, null);
  final histogram = List<double?>.filled(n, null);
  for (var j = 0; j < macdOnly.length; j++) {
    if (sigEma[j] != null) {
      final origI = macdIndices[j];
      signal[origI] = sigEma[j];
      histogram[origI] = macdLine[origI]! - sigEma[j]!;
    }
  }
  return (macd: macdLine, signal: signal, histogram: histogram);
}

List<double?> calcATR(
  List<double> highs,
  List<double> lows,
  List<double> closes, {
  int period = 14,
}) {
  final n = closes.length;
  final result = List<double?>.filled(n, null);
  if (n < period + 1) return result;
  final trs = <double>[];
  for (var i = 1; i < n; i++) {
    trs.add(
      [
        highs[i] - lows[i],
        (highs[i] - closes[i - 1]).abs(),
        (lows[i] - closes[i - 1]).abs(),
      ].reduce(max),
    );
  }
  double atr = 0;
  for (var i = 0; i < period; i++) {
    atr += trs[i];
  }
  atr /= period;
  result[period] = atr;
  for (var i = period + 1; i < n; i++) {
    atr = (atr * (period - 1) + trs[i - 1]) / period;
    result[i] = atr;
  }
  return result;
}

List<int?> calcSupertrend(
  List<double> highs,
  List<double> lows,
  List<double> closes, {
  int atrPeriod = 10,
  double multiplier = 3.0,
}) {
  final n = closes.length;
  final atr = calcATR(highs, lows, closes, period: atrPeriod);
  final direction = List<int?>.filled(n, null);
  double? prevUpper, prevLower;
  int? prevDir;
  for (var i = 1; i < n; i++) {
    if (atr[i] == null) continue;
    final hl2 = (highs[i] + lows[i]) / 2;
    var u = hl2 + multiplier * atr[i]!;
    var l = hl2 - multiplier * atr[i]!;
    if (prevUpper != null) {
      if (closes[i - 1] < prevUpper) u = min(u, prevUpper);
      if (closes[i - 1] > prevLower!) l = max(l, prevLower);
    }
    if (prevDir == null) {
      direction[i] = closes[i] > u ? 1 : -1;
    } else if (prevDir == 1) {
      direction[i] = closes[i] >= l ? 1 : -1;
    } else {
      direction[i] = closes[i] <= u ? -1 : 1;
    }
    prevUpper = u;
    prevLower = l;
    prevDir = direction[i];
  }
  return direction;
}

({List<double?> upper, List<double?> lower}) calcDonchian(
  List<double> highs,
  List<double> lows, {
  int period = 20,
}) {
  final n = highs.length;
  final upper = List<double?>.filled(n, null);
  final lower = List<double?>.filled(n, null);
  for (var i = period - 1; i < n; i++) {
    double hi = highs[i], lo = lows[i];
    for (var j = i - period + 1; j < i; j++) {
      if (highs[j] > hi) hi = highs[j];
      if (lows[j] < lo) lo = lows[j];
    }
    upper[i] = hi;
    lower[i] = lo;
  }
  return (upper: upper, lower: lower);
}
