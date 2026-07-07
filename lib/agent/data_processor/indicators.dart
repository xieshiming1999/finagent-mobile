// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';

import '../data_fetcher/models.dart';

/// Technical indicator calculations on KlineBar data.
class Indicators {
  /// Simple Moving Average
  static List<double?> sma(List<KlineBar> bars, int period) {
    final result = List<double?>.filled(bars.length, null);
    for (var i = period - 1; i < bars.length; i++) {
      var sum = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        sum += bars[j].close;
      }
      result[i] = sum / period;
    }
    return result;
  }

  /// Exponential Moving Average
  static List<double?> ema(List<KlineBar> bars, int period) {
    final result = List<double?>.filled(bars.length, null);
    if (bars.length < period) return result;
    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += bars[i].close;
    }
    result[period - 1] = sum / period;
    final k = 2.0 / (period + 1);
    for (var i = period; i < bars.length; i++) {
      result[i] = bars[i].close * k + result[i - 1]! * (1 - k);
    }
    return result;
  }

  /// RSI (Relative Strength Index)
  static List<double?> rsi(List<KlineBar> bars, {int period = 14}) {
    final result = List<double?>.filled(bars.length, null);
    if (bars.length < period + 1) return result;
    var avgGain = 0.0, avgLoss = 0.0;
    for (var i = 1; i <= period; i++) {
      final diff = bars[i].close - bars[i - 1].close;
      if (diff > 0) {
        avgGain += diff;
      } else {
        avgLoss -= diff;
      }
    }
    avgGain /= period;
    avgLoss /= period;
    result[period] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
    for (var i = period + 1; i < bars.length; i++) {
      final diff = bars[i].close - bars[i - 1].close;
      avgGain = (avgGain * (period - 1) + (diff > 0 ? diff : 0)) / period;
      avgLoss = (avgLoss * (period - 1) + (diff < 0 ? -diff : 0)) / period;
      result[i] = avgLoss == 0 ? 100 : 100 - 100 / (1 + avgGain / avgLoss);
    }
    return result;
  }

  /// MACD (DIF, DEA, Histogram)
  static ({List<double?> dif, List<double?> dea, List<double?> hist}) macd(
    List<KlineBar> bars, {
    int fast = 12,
    int slow = 26,
    int signal = 9,
  }) {
    final emaFast = ema(bars, fast);
    final emaSlow = ema(bars, slow);
    final dif = List<double?>.filled(bars.length, null);
    for (var i = 0; i < bars.length; i++) {
      if (emaFast[i] != null && emaSlow[i] != null)
        dif[i] = emaFast[i]! - emaSlow[i]!;
    }
    // DEA = EMA of DIF
    final dea = List<double?>.filled(bars.length, null);
    final firstDif = dif.indexWhere((d) => d != null);
    if (firstDif < 0) return (dif: dif, dea: dea, hist: dif);
    dea[firstDif] = dif[firstDif];
    final k = 2.0 / (signal + 1);
    for (var i = firstDif + 1; i < bars.length; i++) {
      if (dif[i] != null && dea[i - 1] != null) {
        dea[i] = dif[i]! * k + dea[i - 1]! * (1 - k);
      }
    }
    final hist = List<double?>.filled(bars.length, null);
    for (var i = 0; i < bars.length; i++) {
      if (dif[i] != null && dea[i] != null) hist[i] = (dif[i]! - dea[i]!) * 2;
    }
    return (dif: dif, dea: dea, hist: hist);
  }

  /// Bollinger Bands
  static ({List<double?> upper, List<double?> mid, List<double?> lower}) boll(
    List<KlineBar> bars, {
    int period = 20,
    double multiplier = 2,
  }) {
    final mid = sma(bars, period);
    final upper = List<double?>.filled(bars.length, null);
    final lower = List<double?>.filled(bars.length, null);
    for (var i = period - 1; i < bars.length; i++) {
      var sumSq = 0.0;
      for (var j = i - period + 1; j <= i; j++) {
        sumSq += pow(bars[j].close - mid[i]!, 2);
      }
      final std = sqrt(sumSq / period);
      upper[i] = mid[i]! + multiplier * std;
      lower[i] = mid[i]! - multiplier * std;
    }
    return (upper: upper, mid: mid, lower: lower);
  }

  /// KDJ
  static ({List<double?> k, List<double?> d, List<double?> j}) kdj(
    List<KlineBar> bars, {
    int period = 9,
  }) {
    final kList = List<double?>.filled(bars.length, null);
    final dList = List<double?>.filled(bars.length, null);
    final jList = List<double?>.filled(bars.length, null);
    double prevK = 50, prevD = 50;
    for (var i = period - 1; i < bars.length; i++) {
      var high = bars[i].high, low = bars[i].low;
      for (var j = i - period + 1; j < i; j++) {
        if (bars[j].high > high) high = bars[j].high;
        if (bars[j].low < low) low = bars[j].low;
      }
      final rsv = high == low
          ? 50.0
          : (bars[i].close - low) / (high - low) * 100;
      final k = 2 / 3 * prevK + 1 / 3 * rsv;
      final d = 2 / 3 * prevD + 1 / 3 * k;
      kList[i] = k;
      dList[i] = d;
      jList[i] = 3 * k - 2 * d;
      prevK = k;
      prevD = d;
    }
    return (k: kList, d: dList, j: jList);
  }

  /// ATR (Average True Range)
  static List<double?> atr(List<KlineBar> bars, {int period = 14}) {
    final result = List<double?>.filled(bars.length, null);
    if (bars.length < 2) return result;
    final tr = List<double>.filled(bars.length, 0);
    tr[0] = bars[0].high - bars[0].low;
    for (var i = 1; i < bars.length; i++) {
      tr[i] = [
        bars[i].high - bars[i].low,
        (bars[i].high - bars[i - 1].close).abs(),
        (bars[i].low - bars[i - 1].close).abs(),
      ].reduce(max);
    }
    if (bars.length < period) return result;
    var sum = 0.0;
    for (var i = 0; i < period; i++) {
      sum += tr[i];
    }
    result[period - 1] = sum / period;
    for (var i = period; i < bars.length; i++) {
      result[i] = (result[i - 1]! * (period - 1) + tr[i]) / period;
    }
    return result;
  }

  /// Calculate all common indicators and return latest values.
  static Map<String, dynamic> summary(List<KlineBar> bars) {
    if (bars.isEmpty) return {};
    final last = bars.length - 1;
    final ma5 = sma(bars, 5);
    final ma10 = sma(bars, 10);
    final ma20 = sma(bars, 20);
    final ma60 = sma(bars, 60);
    final rsiVal = rsi(bars);
    final macdVal = macd(bars);
    final bollVal = boll(bars);
    final kdjVal = kdj(bars);
    final atrVal = atr(bars);

    return {
      'price': bars[last].close,
      'date': bars[last].date,
      'ma5': _r(ma5[last]),
      'ma10': _r(ma10[last]),
      'ma20': _r(ma20[last]),
      'ma60': _r(ma60[last]),
      'rsi': _r(rsiVal[last]),
      'macd_dif': _r(macdVal.dif[last]),
      'macd_dea': _r(macdVal.dea[last]),
      'macd_hist': _r(macdVal.hist[last]),
      'boll_upper': _r(bollVal.upper[last]),
      'boll_mid': _r(bollVal.mid[last]),
      'boll_lower': _r(bollVal.lower[last]),
      'kdj_k': _r(kdjVal.k[last]),
      'kdj_d': _r(kdjVal.d[last]),
      'kdj_j': _r(kdjVal.j[last]),
      'atr': _r(atrVal[last]),
      'macd_cross': _macdCross(macdVal),
      'price_vs_ma20': ma20[last] != null
          ? (bars[last].close > ma20[last]! ? 'above' : 'below')
          : null,
      'interpretations': _interpret(
        bars[last].close,
        ma5[last],
        ma10[last],
        ma20[last],
        ma60[last],
        rsiVal[last],
        macdVal,
        kdjVal,
        last,
      ),
    };
  }

  static Map<String, String> _interpret(
    double price,
    double? ma5,
    double? ma10,
    double? ma20,
    double? ma60,
    double? rsiV,
    dynamic macdV,
    dynamic kdjV,
    int last,
  ) {
    final m = <String, String>{};
    if (ma5 != null && ma10 != null && ma20 != null) {
      if (ma5 > ma10 && ma10 > ma20) {
        m['ma'] = '均线多头排列,趋势向上';
      } else if (ma5 < ma10 && ma10 < ma20)
        m['ma'] = '均线空头排列,趋势向下';
      else
        m['ma'] = '均线纠缠,方向不明';
    }
    if (ma5 != null) {
      final bias = (price - ma5) / ma5 * 100;
      if (bias > 5) {
        m['bias'] = '偏离MA5达${bias.toStringAsFixed(1)}%,短期追高风险';
      } else if (bias < -5)
        m['bias'] = '偏离MA5达${bias.toStringAsFixed(1)}%,短期超跌';
    }
    if (rsiV != null) {
      if (rsiV > 80) {
        m['rsi'] = 'RSI ${rsiV.toStringAsFixed(0)} 严重超买,注意回调风险';
      } else if (rsiV > 70)
        m['rsi'] = 'RSI ${rsiV.toStringAsFixed(0)} 超买区域,谨慎追涨';
      else if (rsiV < 20)
        m['rsi'] = 'RSI ${rsiV.toStringAsFixed(0)} 严重超卖,可能反弹';
      else if (rsiV < 30)
        m['rsi'] = 'RSI ${rsiV.toStringAsFixed(0)} 超卖区域,关注反转信号';
      else if (rsiV >= 40 && rsiV <= 60)
        m['rsi'] = 'RSI ${rsiV.toStringAsFixed(0)} 中性区域';
    }
    final cross = _macdCross(macdV);
    if (cross == 'golden_cross') {
      m['macd'] = 'MACD金叉,短期动能转多';
    } else if (cross == 'death_cross')
      m['macd'] = 'MACD死叉,短期动能转空';
    final j = kdjV.j[last] as double?;
    if (j != null) {
      if (j > 100) {
        m['kdj'] = 'KDJ J值${j.toStringAsFixed(0)}超买,短期可能回调';
      } else if (j < 0)
        m['kdj'] = 'KDJ J值${j.toStringAsFixed(0)}超卖,短期可能反弹';
    }
    return m;
  }

  /// 100-point technical scoring.
  /// 趋势30 + 乖离20 + 量能15 + 支撑10 + MACD15 + RSI10
  static Map<String, dynamic> technicalScore(List<KlineBar> bars) {
    if (bars.length < 30) return {'score': 0, 'signal': 'insufficient_data'};
    final last = bars.length - 1;
    final ma5v = sma(bars, 5);
    final ma10v = sma(bars, 10);
    final ma20v = sma(bars, 20);
    final ma60v = sma(bars, 60);
    final rsiV = rsi(bars);
    final macdV = macd(bars);
    final price = bars[last].close;

    var score = 0;
    final details = <String, dynamic>{};

    // 趋势 (30分)
    final m5 = ma5v[last],
        m10 = ma10v[last],
        m20 = ma20v[last],
        m60 = ma60v[last];
    int trend = 0;
    if (m5 != null && m10 != null && m20 != null) {
      if (m60 != null && m5 > m10 && m10 > m20 && m20 > m60) {
        trend = 30;
        details['trend'] = 'strong_bull';
      } else if (m5 > m10 && m10 > m20) {
        trend = 26;
        details['trend'] = 'bull';
      } else if (m5 > m20) {
        trend = 18;
        details['trend'] = 'weak_bull';
      } else if ((m5 - m20).abs() / m20 < 0.02) {
        trend = 12;
        details['trend'] = 'consolidation';
      } else if (m5 < m20 && m5 > m10) {
        trend = 8;
        details['trend'] = 'weak_bear';
      } else if (m5 < m10 && m10 < m20) {
        trend = 4;
        details['trend'] = 'bear';
      } else {
        trend = 0;
        details['trend'] = 'strong_bear';
      }
    }
    score += trend;

    // 乖离率 (20分) — 不追高
    int bias = 0;
    if (m5 != null && m5 > 0) {
      final biasV = (price - m5) / m5 * 100;
      if (biasV <= 0 && biasV >= -3) {
        bias = 20;
      } else if (biasV > 0 && biasV <= 2) {
        bias = 16;
      } else if (biasV > 2 && biasV <= 5) {
        bias = 10;
      } else if (biasV > 5) {
        bias = 4;
      } else {
        bias = 12;
      }
      details['bias'] = double.parse(biasV.toStringAsFixed(1));
    }
    score += bias;

    // 量能 (15分)
    int vol = 0;
    final recent5Vol =
        bars
            .sublist(bars.length - 5)
            .map((b) => b.volume)
            .reduce((a, b) => a + b) /
        5;
    final prev20Vol = bars.length > 25
        ? bars
                  .sublist(bars.length - 25, bars.length - 5)
                  .map((b) => b.volume)
                  .reduce((a, b) => a + b) /
              20
        : recent5Vol;
    final volRatio = prev20Vol > 0 ? recent5Vol / prev20Vol : 1.0;
    if (volRatio < 0.7 && price > (m5 ?? 0)) {
      vol = 15;
      details['volume'] = 'shrink_pullback';
    } else if (volRatio > 1.5 && bars[last].close > bars[last].open) {
      vol = 12;
      details['volume'] = 'heavy_up';
    } else if (volRatio > 1.5 && bars[last].close < bars[last].open) {
      vol = 0;
      details['volume'] = 'heavy_down';
    } else {
      vol = 8;
      details['volume'] = 'normal';
    }
    score += vol;

    // 支撑 (10分)
    int support = 0;
    if (m5 != null && (price - m5).abs() / m5 < 0.02) {
      support += 5;
    }
    if (m10 != null && (price - m10).abs() / m10 < 0.02) {
      support += 5;
    }
    details['support'] = support;
    score += support;

    // MACD (15分)
    int macdScore = 0;
    final dif = macdV.dif[last], hist = macdV.hist[last];
    final cross = _macdCross(macdV);
    if (cross == 'golden_cross' && (dif ?? 0) > 0) {
      macdScore = 15;
      details['macd'] = 'golden_above_zero';
    } else if (cross == 'golden_cross') {
      macdScore = 12;
      details['macd'] = 'golden_cross';
    } else if ((hist ?? 0) > 0 && (dif ?? 0) > 0) {
      macdScore = 10;
      details['macd'] = 'bullish';
    } else if (cross == 'death_cross') {
      macdScore = 0;
      details['macd'] = 'death_cross';
    } else {
      macdScore = 6;
      details['macd'] = 'neutral';
    }
    score += macdScore;

    // RSI (10分)
    int rsiScore = 0;
    final r = rsiV[last];
    if (r != null) {
      if (r < 30) {
        rsiScore = 10;
        details['rsi_zone'] = 'oversold';
      } else if (r < 40) {
        rsiScore = 8;
        details['rsi_zone'] = 'near_oversold';
      } else if (r <= 60) {
        rsiScore = 6;
        details['rsi_zone'] = 'neutral';
      } else if (r <= 70) {
        rsiScore = 4;
        details['rsi_zone'] = 'near_overbought';
      } else {
        rsiScore = 0;
        details['rsi_zone'] = 'overbought';
      }
    }
    score += rsiScore;

    final signal = score >= 80
        ? 'strong_buy'
        : score >= 65
        ? 'buy'
        : score >= 50
        ? 'hold'
        : score >= 35
        ? 'wait'
        : 'sell';

    return {
      'score': score,
      'signal': signal,
      'breakdown': {
        'trend': trend,
        'bias': bias,
        'volume': vol,
        'support': support,
        'macd': macdScore,
        'rsi': rsiScore,
      },
      'details': details,
    };
  }

  static double? _r(double? v) =>
      v != null ? double.parse(v.toStringAsFixed(2)) : null;

  static String? _macdCross(
    ({List<double?> dif, List<double?> dea, List<double?> hist}) m,
  ) {
    if (m.hist.length < 2) return null;
    final curr = m.hist[m.hist.length - 1];
    final prev = m.hist[m.hist.length - 2];
    if (curr == null || prev == null) return null;
    if (prev <= 0 && curr > 0) return 'golden_cross';
    if (prev >= 0 && curr < 0) return 'death_cross';
    return null;
  }

  // ─── Extended Indicators (vnpy ArrayManager alignment) ───

  /// Weighted Moving Average
  static List<double?> wma(List<KlineBar> bars, int period) {
    final result = List<double?>.filled(bars.length, null);
    for (var i = period - 1; i < bars.length; i++) {
      double sum = 0, weightSum = 0;
      for (var j = 0; j < period; j++) {
        final w = (period - j).toDouble();
        sum += bars[i - j].close * w;
        weightSum += w;
      }
      result[i] = sum / weightSum;
    }
    return result;
  }

  /// Williams %R
  static List<double?> williamsR(List<KlineBar> bars, {int period = 14}) {
    final result = List<double?>.filled(bars.length, null);
    for (var i = period - 1; i < bars.length; i++) {
      double hh = bars[i].high, ll = bars[i].low;
      for (var j = i - period + 1; j < i; j++) {
        if (bars[j].high > hh) hh = bars[j].high;
        if (bars[j].low < ll) ll = bars[j].low;
      }
      result[i] = hh != ll ? (hh - bars[i].close) / (hh - ll) * -100 : 0;
    }
    return result;
  }

  /// Commodity Channel Index
  static List<double?> cci(List<KlineBar> bars, {int period = 20}) {
    final result = List<double?>.filled(bars.length, null);
    for (var i = period - 1; i < bars.length; i++) {
      double sum = 0;
      for (var j = i - period + 1; j <= i; j++) {
        sum += (bars[j].high + bars[j].low + bars[j].close) / 3;
      }
      final tp = (bars[i].high + bars[i].low + bars[i].close) / 3;
      final mean = sum / period;
      double madSum = 0;
      for (var j = i - period + 1; j <= i; j++) {
        madSum += ((bars[j].high + bars[j].low + bars[j].close) / 3 - mean)
            .abs();
      }
      final mad = madSum / period;
      result[i] = mad != 0 ? (tp - mean) / (0.015 * mad) : 0;
    }
    return result;
  }

  /// Money Flow Index
  static List<double?> mfi(List<KlineBar> bars, {int period = 14}) {
    final result = List<double?>.filled(bars.length, null);
    if (bars.length < period + 1) return result;
    for (var i = period; i < bars.length; i++) {
      double posFlow = 0, negFlow = 0;
      for (var j = i - period + 1; j <= i; j++) {
        final tp = (bars[j].high + bars[j].low + bars[j].close) / 3;
        final prevTp =
            (bars[j - 1].high + bars[j - 1].low + bars[j - 1].close) / 3;
        final rawMf = tp * bars[j].volume;
        if (tp > prevTp) {
          posFlow += rawMf;
        } else if (tp < prevTp)
          negFlow += rawMf;
      }
      result[i] = negFlow != 0 ? 100 - 100 / (1 + posFlow / negFlow) : 100;
    }
    return result;
  }

  /// Average Directional Index
  static ({List<double?> adx, List<double?> plusDi, List<double?> minusDi}) adx(
    List<KlineBar> bars, {
    int period = 14,
  }) {
    final n = bars.length;
    final adxR = List<double?>.filled(n, null);
    final plusDi = List<double?>.filled(n, null);
    final minusDi = List<double?>.filled(n, null);
    if (n < period + 1) return (adx: adxR, plusDi: plusDi, minusDi: minusDi);

    final tr = List<double>.filled(n, 0);
    final plusDm = List<double>.filled(n, 0);
    final minusDm = List<double>.filled(n, 0);
    for (var i = 1; i < n; i++) {
      tr[i] = [
        bars[i].high - bars[i].low,
        (bars[i].high - bars[i - 1].close).abs(),
        (bars[i].low - bars[i - 1].close).abs(),
      ].reduce(max);
      final up = bars[i].high - bars[i - 1].high;
      final down = bars[i - 1].low - bars[i].low;
      plusDm[i] = (up > down && up > 0) ? up : 0;
      minusDm[i] = (down > up && down > 0) ? down : 0;
    }

    double atr = 0, aPlusDm = 0, aMinusDm = 0;
    for (var i = 1; i <= period; i++) {
      atr += tr[i];
      aPlusDm += plusDm[i];
      aMinusDm += minusDm[i];
    }

    double prevDx = 0;
    for (var i = period; i < n; i++) {
      if (i > period) {
        atr = atr - atr / period + tr[i];
        aPlusDm = aPlusDm - aPlusDm / period + plusDm[i];
        aMinusDm = aMinusDm - aMinusDm / period + minusDm[i];
      }
      final pdi = atr != 0 ? aPlusDm / atr * 100 : 0.0;
      final mdi = atr != 0 ? aMinusDm / atr * 100 : 0.0;
      plusDi[i] = pdi;
      minusDi[i] = mdi;
      final dx = (pdi + mdi) != 0 ? (pdi - mdi).abs() / (pdi + mdi) * 100 : 0.0;
      if (i == period) {
        adxR[i] = dx;
        prevDx = dx;
      } else {
        adxR[i] = (prevDx * (period - 1) + dx) / period;
        prevDx = adxR[i]!;
      }
    }
    return (adx: adxR, plusDi: plusDi, minusDi: minusDi);
  }

  /// Parabolic SAR
  static List<double?> sar(
    List<KlineBar> bars, {
    double acceleration = 0.02,
    double maxAccel = 0.2,
  }) {
    final n = bars.length;
    final result = List<double?>.filled(n, null);
    if (n < 2) return result;

    bool isLong = bars[1].close > bars[0].close;
    double af = acceleration;
    double ep = isLong ? bars[0].high : bars[0].low;
    double sarVal = isLong ? bars[0].low : bars[0].high;

    for (var i = 1; i < n; i++) {
      result[i] = sarVal;
      if (isLong) {
        if (bars[i].high > ep) {
          ep = bars[i].high;
          af = min(af + acceleration, maxAccel);
        }
        sarVal += af * (ep - sarVal);
        sarVal = min(sarVal, min(bars[i].low, bars[i - 1].low));
        if (bars[i].low < sarVal) {
          isLong = false;
          sarVal = ep;
          ep = bars[i].low;
          af = acceleration;
        }
      } else {
        if (bars[i].low < ep) {
          ep = bars[i].low;
          af = min(af + acceleration, maxAccel);
        }
        sarVal += af * (ep - sarVal);
        sarVal = max(sarVal, max(bars[i].high, bars[i - 1].high));
        if (bars[i].high > sarVal) {
          isLong = true;
          sarVal = ep;
          ep = bars[i].high;
          af = acceleration;
        }
      }
    }
    return result;
  }

  /// On-Balance Volume
  static List<double?> obv(List<KlineBar> bars) {
    final result = List<double?>.filled(bars.length, null);
    if (bars.isEmpty) return result;
    result[0] = bars[0].volume;
    for (var i = 1; i < bars.length; i++) {
      if (bars[i].close > bars[i - 1].close) {
        result[i] = result[i - 1]! + bars[i].volume;
      } else if (bars[i].close < bars[i - 1].close)
        result[i] = result[i - 1]! - bars[i].volume;
      else
        result[i] = result[i - 1];
    }
    return result;
  }

  /// VWAP (Volume Weighted Average Price) - cumulative
  static List<double?> vwap(List<KlineBar> bars) {
    final result = List<double?>.filled(bars.length, null);
    double cumVol = 0, cumVP = 0;
    for (var i = 0; i < bars.length; i++) {
      final tp = (bars[i].high + bars[i].low + bars[i].close) / 3;
      cumVP += tp * bars[i].volume;
      cumVol += bars[i].volume;
      result[i] = cumVol > 0 ? cumVP / cumVol : tp;
    }
    return result;
  }

  /// Rate of Change
  static List<double?> roc(List<KlineBar> bars, {int period = 12}) {
    final result = List<double?>.filled(bars.length, null);
    for (var i = period; i < bars.length; i++) {
      result[i] = bars[i - period].close != 0
          ? (bars[i].close - bars[i - period].close) /
                bars[i - period].close *
                100
          : 0;
    }
    return result;
  }

  /// Momentum
  static List<double?> momentum(List<KlineBar> bars, {int period = 10}) {
    final result = List<double?>.filled(bars.length, null);
    for (var i = period; i < bars.length; i++) {
      result[i] = bars[i].close - bars[i - period].close;
    }
    return result;
  }

  /// Donchian Channel
  static ({List<double?> upper, List<double?> lower}) donchian(
    List<KlineBar> bars, {
    int period = 20,
  }) {
    final upper = List<double?>.filled(bars.length, null);
    final lower = List<double?>.filled(bars.length, null);
    for (var i = period - 1; i < bars.length; i++) {
      double hh = bars[i].high, ll = bars[i].low;
      for (var j = i - period + 1; j < i; j++) {
        if (bars[j].high > hh) hh = bars[j].high;
        if (bars[j].low < ll) ll = bars[j].low;
      }
      upper[i] = hh;
      lower[i] = ll;
    }
    return (upper: upper, lower: lower);
  }

  /// Keltner Channel
  static ({List<double?> upper, List<double?> lower}) keltner(
    List<KlineBar> bars, {
    int period = 20,
    double multiplier = 1.5,
  }) {
    final mid = ema(bars, period);
    final atrVals = atr(bars, period: period);
    final upper = List<double?>.filled(bars.length, null);
    final lower = List<double?>.filled(bars.length, null);
    for (var i = 0; i < bars.length; i++) {
      if (mid[i] != null && atrVals[i] != null) {
        upper[i] = mid[i]! + multiplier * atrVals[i]!;
        lower[i] = mid[i]! - multiplier * atrVals[i]!;
      }
    }
    return (upper: upper, lower: lower);
  }

  /// Aroon Oscillator
  static ({List<double?> up, List<double?> down, List<double?> osc}) aroon(
    List<KlineBar> bars, {
    int period = 25,
  }) {
    final up = List<double?>.filled(bars.length, null);
    final down = List<double?>.filled(bars.length, null);
    final osc = List<double?>.filled(bars.length, null);
    for (var i = period; i < bars.length; i++) {
      int maxIdx = 0, minIdx = 0;
      double maxVal = bars[i - period].high, minVal = bars[i - period].low;
      for (var j = 1; j <= period; j++) {
        if (bars[i - period + j].high >= maxVal) {
          maxVal = bars[i - period + j].high;
          maxIdx = j;
        }
        if (bars[i - period + j].low <= minVal) {
          minVal = bars[i - period + j].low;
          minIdx = j;
        }
      }
      up[i] = maxIdx / period * 100;
      down[i] = minIdx / period * 100;
      osc[i] = up[i]! - down[i]!;
    }
    return (up: up, down: down, osc: osc);
  }

  /// Stochastic Oscillator (full: %K and %D)
  static ({List<double?> k, List<double?> d}) stochastic(
    List<KlineBar> bars, {
    int kPeriod = 14,
    int dPeriod = 3,
  }) {
    final k = List<double?>.filled(bars.length, null);
    final d = List<double?>.filled(bars.length, null);
    for (var i = kPeriod - 1; i < bars.length; i++) {
      double hh = bars[i].high, ll = bars[i].low;
      for (var j = i - kPeriod + 1; j < i; j++) {
        if (bars[j].high > hh) hh = bars[j].high;
        if (bars[j].low < ll) ll = bars[j].low;
      }
      k[i] = hh != ll ? (bars[i].close - ll) / (hh - ll) * 100 : 50;
    }
    // %D = SMA of %K
    for (var i = kPeriod - 1 + dPeriod - 1; i < bars.length; i++) {
      double sum = 0;
      int count = 0;
      for (var j = i - dPeriod + 1; j <= i; j++) {
        if (k[j] != null) {
          sum += k[j]!;
          count++;
        }
      }
      d[i] = count > 0 ? sum / count : null;
    }
    return (k: k, d: d);
  }

  /// Accumulation/Distribution Line
  static List<double?> ad(List<KlineBar> bars) {
    final result = List<double?>.filled(bars.length, null);
    if (bars.isEmpty) return result;
    double adl = 0;
    for (var i = 0; i < bars.length; i++) {
      final hl = bars[i].high - bars[i].low;
      final clv = hl != 0
          ? ((bars[i].close - bars[i].low) - (bars[i].high - bars[i].close)) /
                hl
          : 0;
      adl += clv * bars[i].volume;
      result[i] = adl;
    }
    return result;
  }

  /// Extended summary with all new indicators
  static Map<String, dynamic> extendedSummary(List<KlineBar> bars) {
    final base = summary(bars);
    if (bars.length < 30) return base;
    final last = bars.length - 1;

    final williamsVal = williamsR(bars);
    final cciVal = cci(bars);
    final mfiVal = mfi(bars);
    final adxVal = adx(bars);
    final sarVal = sar(bars);
    final obvVal = obv(bars);
    final vwapVal = vwap(bars);
    final rocVal = roc(bars);
    final aroonVal = aroon(bars);
    final stochVal = stochastic(bars);
    final keltnerVal = keltner(bars);
    final donchianVal = donchian(bars);

    base['williams_r'] = _r(williamsVal[last]);
    base['cci'] = _r(cciVal[last]);
    base['mfi'] = _r(mfiVal[last]);
    base['adx'] = _r(adxVal.adx[last]);
    base['plus_di'] = _r(adxVal.plusDi[last]);
    base['minus_di'] = _r(adxVal.minusDi[last]);
    base['sar'] = _r(sarVal[last]);
    base['obv'] = obvVal[last];
    base['vwap'] = _r(vwapVal[last]);
    base['roc'] = _r(rocVal[last]);
    base['aroon_up'] = _r(aroonVal.up[last]);
    base['aroon_down'] = _r(aroonVal.down[last]);
    base['aroon_osc'] = _r(aroonVal.osc[last]);
    base['stoch_k'] = _r(stochVal.k[last]);
    base['stoch_d'] = _r(stochVal.d[last]);
    base['keltner_upper'] = _r(keltnerVal.upper[last]);
    base['keltner_lower'] = _r(keltnerVal.lower[last]);
    base['donchian_upper'] = _r(donchianVal.upper[last]);
    base['donchian_lower'] = _r(donchianVal.lower[last]);

    return base;
  }
}
