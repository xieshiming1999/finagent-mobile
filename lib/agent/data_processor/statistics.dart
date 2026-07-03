import 'dart:math';

import '../data_fetcher/models.dart';

/// Statistical analysis on price data.
class Statistics {
  /// Calculate return statistics.
  static Map<String, dynamic> returnStats(List<KlineBar> bars) {
    if (bars.length < 2) return {};
    final returns = <double>[];
    for (var i = 1; i < bars.length; i++) {
      returns.add(
        (bars[i].close - bars[i - 1].close) / bars[i - 1].close * 100,
      );
    }

    final avgReturn = returns.reduce((a, b) => a + b) / returns.length;
    final variance =
        returns.map((r) => pow(r - avgReturn, 2)).reduce((a, b) => a + b) /
        returns.length;
    final volatility = sqrt(variance);
    final annualizedVol = volatility * sqrt(252);

    // Sharpe ratio (risk-free rate ~ 2%)
    final annualizedReturn = avgReturn * 252;
    final sharpe = annualizedVol > 0
        ? (annualizedReturn - 2) / annualizedVol
        : 0;

    // Max drawdown
    var peak = bars.first.close;
    var maxDD = 0.0;
    for (final bar in bars) {
      if (bar.close > peak) peak = bar.close;
      final dd = (peak - bar.close) / peak * 100;
      if (dd > maxDD) maxDD = dd;
    }

    // Win rate
    final upDays = returns.where((r) => r > 0).length;
    final winRate = returns.isNotEmpty ? upDays / returns.length * 100 : 0;

    // Percentile position
    final sorted = bars.map((b) => b.close).toList()..sort();
    final percentile = sorted.indexOf(bars.last.close) / sorted.length * 100;

    return {
      'totalReturn': _r2(
        (bars.last.close - bars.first.close) / bars.first.close * 100,
      ),
      'avgDailyReturn': _r2(avgReturn),
      'volatility': _r2(volatility),
      'annualizedVolatility': _r2(annualizedVol),
      'sharpeRatio': _r2(sharpe.toDouble()),
      'maxDrawdown': _r2(maxDD),
      'winRate': _r2(winRate.toDouble()),
      'percentile': _r2(percentile),
      'high': sorted.last,
      'low': sorted.first,
      'bars': bars.length,
    };
  }

  /// Price correlation between two stocks.
  static double correlation(List<KlineBar> a, List<KlineBar> b) {
    final n = min(a.length, b.length);
    if (n < 10) return 0;
    final ra = <double>[], rb = <double>[];
    for (var i = 1; i < n; i++) {
      ra.add((a[i].close - a[i - 1].close) / a[i - 1].close);
      rb.add((b[i].close - b[i - 1].close) / b[i - 1].close);
    }
    final ma = ra.reduce((a, b) => a + b) / ra.length;
    final mb = rb.reduce((a, b) => a + b) / rb.length;
    var cov = 0.0, va = 0.0, vb = 0.0;
    for (var i = 0; i < ra.length; i++) {
      cov += (ra[i] - ma) * (rb[i] - mb);
      va += pow(ra[i] - ma, 2);
      vb += pow(rb[i] - mb, 2);
    }
    final denom = sqrt(va * vb);
    return denom > 0 ? cov / denom : 0;
  }

  static double _r2(double v) => double.parse(v.toStringAsFixed(2));
}
