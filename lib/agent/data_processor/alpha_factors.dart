// ignore_for_file: curly_braces_in_flow_control_structures
import 'dart:math';

import '../data_fetcher/models.dart';

/// Alpha158 factor library — ported from vnpy/Qlib.
/// Computes 158+ quantitative factors from OHLCV data.
/// Factors are computed over windows [5, 10, 20, 30, 60].
class AlphaFactors {
  static const _windows = [5, 10, 20, 30, 60];

  // ─── Time-Series Operators ───

  static List<double> _closes(List<KlineBar> bars) =>
      bars.map((b) => b.close).toList();
  static List<double> _highs(List<KlineBar> bars) =>
      bars.map((b) => b.high).toList();
  static List<double> _lows(List<KlineBar> bars) =>
      bars.map((b) => b.low).toList();
  static List<double> _volumes(List<KlineBar> bars) =>
      bars.map((b) => b.volume).toList();

  static double _tsDelay(List<double> data, int idx, int w) =>
      idx >= w ? data[idx - w] : double.nan;

  static double _tsMean(List<double> data, int idx, int w) {
    if (idx < w - 1) return double.nan;
    double s = 0;
    int c = 0;
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!data[j].isNaN) {
        s += data[j];
        c++;
      }
    }
    return c > 0 ? s / c : double.nan;
  }

  static double _tsStd(List<double> data, int idx, int w) {
    if (idx < w - 1) return double.nan;
    final mean = _tsMean(data, idx, w);
    if (mean.isNaN) return double.nan;
    double s = 0;
    int c = 0;
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!data[j].isNaN) {
        s += pow(data[j] - mean, 2);
        c++;
      }
    }
    return c > 1 ? sqrt(s / c) : 0;
  }

  static double _tsMax(List<double> data, int idx, int w) {
    if (idx < w - 1) return double.nan;
    double m = double.negativeInfinity;
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!data[j].isNaN && data[j] > m) m = data[j];
    }
    return m.isInfinite ? double.nan : m;
  }

  static double _tsMin(List<double> data, int idx, int w) {
    if (idx < w - 1) return double.nan;
    double m = double.infinity;
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!data[j].isNaN && data[j] < m) m = data[j];
    }
    return m.isInfinite ? double.nan : m;
  }

  static int _tsArgMax(List<double> data, int idx, int w) {
    if (idx < w - 1) return -1;
    int mi = idx - w + 1;
    double mv = data[mi];
    for (var j = mi + 1; j <= idx; j++) {
      if (!data[j].isNaN && data[j] >= mv) {
        mv = data[j];
        mi = j;
      }
    }
    return mi - (idx - w + 1);
  }

  static int _tsArgMin(List<double> data, int idx, int w) {
    if (idx < w - 1) return -1;
    int mi = idx - w + 1;
    double mv = data[mi];
    for (var j = mi + 1; j <= idx; j++) {
      if (!data[j].isNaN && data[j] <= mv) {
        mv = data[j];
        mi = j;
      }
    }
    return mi - (idx - w + 1);
  }

  static double _tsRank(List<double> data, int idx, int w) {
    if (idx < w - 1) return double.nan;
    final val = data[idx];
    if (val.isNaN) return double.nan;
    int below = 0, total = 0;
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!data[j].isNaN) {
        total++;
        if (data[j] < val) below++;
      }
    }
    return total > 0 ? below / total : double.nan;
  }

  static double _tsQuantile(List<double> data, int idx, int w, double q) {
    if (idx < w - 1) return double.nan;
    final vals = <double>[];
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!data[j].isNaN) vals.add(data[j]);
    }
    if (vals.isEmpty) return double.nan;
    vals.sort();
    final pos = q * (vals.length - 1);
    final lo = pos.floor(), hi = pos.ceil();
    return lo == hi ? vals[lo] : vals[lo] + (vals[hi] - vals[lo]) * (pos - lo);
  }

  static double _tsCorr(List<double> a, List<double> b, int idx, int w) {
    if (idx < w - 1) return double.nan;
    double sa = 0, sb = 0, sab = 0, sa2 = 0, sb2 = 0;
    int n = 0;
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!a[j].isNaN && !b[j].isNaN) {
        sa += a[j];
        sb += b[j];
        sab += a[j] * b[j];
        sa2 += a[j] * a[j];
        sb2 += b[j] * b[j];
        n++;
      }
    }
    if (n < 3) return double.nan;
    final num = n * sab - sa * sb;
    final den = sqrt((n * sa2 - sa * sa) * (n * sb2 - sb * sb));
    return den > 0 ? num / den : 0;
  }

  static double _tsSlope(List<double> data, int idx, int w) {
    if (idx < w - 1) return double.nan;
    double sx = 0, sy = 0, sxy = 0, sx2 = 0;
    int n = 0;
    for (var j = idx - w + 1; j <= idx; j++) {
      if (!data[j].isNaN) {
        final x = n.toDouble();
        sx += x;
        sy += data[j];
        sxy += x * data[j];
        sx2 += x * x;
        n++;
      }
    }
    if (n < 2) return double.nan;
    final den = n * sx2 - sx * sx;
    return den != 0 ? (n * sxy - sx * sy) / den : 0;
  }

  // ─── K-line Pattern Features (9) ───

  static Map<String, double> klineFeatures(KlineBar bar) {
    final o = bar.open, h = bar.high, l = bar.low, c = bar.close;
    final hl = h - l;
    return {
      'kmid': o != 0 ? (c - o) / o : 0,
      'klen': o != 0 ? hl / o : 0,
      'kmid2': hl != 0 ? (c - o) / hl : 0,
      'kup': o != 0 ? (h - max(o, c)) / o : 0,
      'kup2': hl != 0 ? (h - max(o, c)) / hl : 0,
      'klow': o != 0 ? (min(o, c) - l) / o : 0,
      'klow2': hl != 0 ? (min(o, c) - l) / hl : 0,
      'ksft': o != 0 ? (c * 2 - h - l) / o : 0,
      'ksft2': hl != 0 ? (c * 2 - h - l) / hl : 0,
    };
  }

  // ─── Factor Computation (30 families x 5 windows) ───

  /// Compute all Alpha158 factors for the last bar. Returns ~158 named values.
  static Map<String, double> compute(List<KlineBar> bars) {
    if (bars.length < 61) return {};
    final result = <String, double>{};
    final close = _closes(bars);
    final high = _highs(bars);
    final low = _lows(bars);
    final vol = _volumes(bars);
    final logVol = vol.map((v) => v > 0 ? log(v + 1) : 0.0).toList();
    final last = bars.length - 1;

    // K-line features
    final kf = klineFeatures(bars[last]);
    result.addAll(kf);

    // Price-relative features
    result['open_close'] = close[last] != 0 ? bars[last].open / close[last] : 1;
    result['high_close'] = close[last] != 0 ? bars[last].high / close[last] : 1;
    result['low_close'] = close[last] != 0 ? bars[last].low / close[last] : 1;

    // Factor families across windows
    for (final w in _windows) {
      if (last < w) continue;
      final c = close[last];
      if (c == 0) continue;

      // Returns from close
      final delayed = _tsDelay(close, last, w);
      result['roc_$w'] = delayed != 0 && !delayed.isNaN
          ? delayed / c
          : double.nan;
      result['ma_$w'] = _tsMean(close, last, w) / c;
      result['std_$w'] = _tsStd(close, last, w) / c;
      result['beta_$w'] = _tsSlope(close, last, w) / c;
      result['max_$w'] = _tsMax(high, last, w) / c;
      result['min_$w'] = _tsMin(low, last, w) / c;
      result['qtlu_$w'] = _tsQuantile(close, last, w, 0.8) / c;
      result['qtld_$w'] = _tsQuantile(close, last, w, 0.2) / c;
      result['rank_$w'] = _tsRank(close, last, w);

      // RSV (stochastic)
      final maxH = _tsMax(high, last, w);
      final minL = _tsMin(low, last, w);
      result['rsv_$w'] = (maxH - minL) != 0 ? (c - minL) / (maxH - minL) : 0.5;

      // Argmax/Argmin
      final imax = _tsArgMax(high, last, w);
      final imin = _tsArgMin(low, last, w);
      result['imax_$w'] = w > 0 ? imax / w : 0;
      result['imin_$w'] = w > 0 ? imin / w : 0;
      result['imxd_$w'] = w > 0 ? (imax - imin) / w : 0;

      // Correlation: close vs log(volume)
      result['corr_$w'] = _tsCorr(close, logVol, last, w);

      // Up/down frequency
      int up = 0, down = 0;
      for (var j = last - w + 1; j <= last; j++) {
        if (j > 0) {
          if (close[j] > close[j - 1]) {
            up++;
          } else if (close[j] < close[j - 1])
            down++;
        }
      }
      result['cntp_$w'] = w > 0 ? up / w : 0;
      result['cntn_$w'] = w > 0 ? down / w : 0;
      result['cntd_$w'] = result['cntp_$w']! - result['cntn_$w']!;

      // Sum of positive/negative moves
      double sump = 0, sumn = 0;
      for (var j = last - w + 1; j <= last; j++) {
        if (j > 0) {
          final d = close[j] - close[j - 1];
          if (d > 0) {
            sump += d;
          } else {
            sumn += d.abs();
          }
        }
      }
      final total = sump + sumn;
      result['sump_$w'] = total > 0 ? sump / total : 0.5;
      result['sumn_$w'] = total > 0 ? sumn / total : 0.5;
      result['sumd_$w'] = result['sump_$w']! - result['sumn_$w']!;

      // Volume factors
      result['vma_$w'] = vol[last] != 0 ? _tsMean(vol, last, w) / vol[last] : 1;
      result['vstd_$w'] = vol[last] != 0 ? _tsStd(vol, last, w) / vol[last] : 0;
    }

    // Remove NaN values
    result.removeWhere((_, v) => v.isNaN || v.isInfinite);
    return result;
  }

  /// Compute factors and return as a flat summary with factor count.
  static Map<String, dynamic> summary(List<KlineBar> bars) {
    final factors = compute(bars);
    return {
      'factorCount': factors.length,
      'factors': factors.map(
        (k, v) => MapEntry(k, double.parse(v.toStringAsFixed(4))),
      ),
    };
  }

  /// List all factor names (without computing).
  static List<String> factorNames() {
    final names = <String>[];
    names.addAll([
      'kmid',
      'klen',
      'kmid2',
      'kup',
      'kup2',
      'klow',
      'klow2',
      'ksft',
      'ksft2',
    ]);
    names.addAll(['open_close', 'high_close', 'low_close']);
    for (final w in _windows) {
      for (final f in [
        'roc',
        'ma',
        'std',
        'beta',
        'max',
        'min',
        'qtlu',
        'qtld',
        'rank',
        'rsv',
        'imax',
        'imin',
        'imxd',
        'corr',
        'cntp',
        'cntn',
        'cntd',
        'sump',
        'sumn',
        'sumd',
        'vma',
        'vstd',
      ]) {
        names.add('${f}_$w');
      }
    }
    return names;
  }
}
