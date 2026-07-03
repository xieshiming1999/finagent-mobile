import 'dart:math';

import '../data_fetcher/models.dart';
import 'statistics.dart';

/// Portfolio optimization algorithms.
class PortfolioOptimizer {
  /// Equal weight allocation.
  static Map<String, double> equalWeight(List<String> symbols) {
    final w = 1.0 / symbols.length;
    return {for (final s in symbols) s: double.parse(w.toStringAsFixed(4))};
  }

  /// Risk parity: allocate inversely proportional to volatility.
  static Map<String, double> riskParity(
    Map<String, List<KlineBar>> barsBySymbol, {
    double maxWeight = 0.2,
  }) {
    final vols = <String, double>{};
    for (final entry in barsBySymbol.entries) {
      final stats = Statistics.returnStats(entry.value);
      vols[entry.key] = (stats['volatility'] as double?) ?? 1.0;
    }

    // Inverse volatility
    final invVols = vols.map((k, v) => MapEntry(k, v > 0 ? 1.0 / v : 1.0));
    final totalInvVol = invVols.values.reduce((a, b) => a + b);
    var weights = invVols.map((k, v) => MapEntry(k, v / totalInvVol));

    // Apply max weight constraint
    weights = _capWeights(weights, maxWeight);
    return weights.map(
      (k, v) => MapEntry(k, double.parse(v.toStringAsFixed(4))),
    );
  }

  /// Maximum Sharpe ratio (simplified mean-variance).
  static Map<String, double> maxSharpe(
    Map<String, List<KlineBar>> barsBySymbol, {
    double riskFreeRate = 0.02,
    double maxWeight = 0.2,
  }) {
    final returns = <String, double>{};
    final vols = <String, double>{};
    for (final entry in barsBySymbol.entries) {
      final stats = Statistics.returnStats(entry.value);
      returns[entry.key] = (stats['totalReturn'] as double?) ?? 0;
      vols[entry.key] = (stats['annualizedVolatility'] as double?) ?? 1;
    }

    // Score = return / vol (simplified Sharpe per asset)
    final scores = <String, double>{};
    for (final s in barsBySymbol.keys) {
      scores[s] = vols[s]! > 0 ? returns[s]! / vols[s]! : 0;
    }

    // Allocate proportional to score (only positive scores)
    final posScores = scores.map((k, v) => MapEntry(k, max(v, 0.0)));
    final totalScore = posScores.values.reduce((a, b) => a + b);
    Map<String, double> weights;
    if (totalScore > 0) {
      weights = posScores.map((k, v) => MapEntry(k, v / totalScore));
    } else {
      weights = equalWeight(barsBySymbol.keys.toList());
    }

    weights = _capWeights(weights, maxWeight);
    return weights.map(
      (k, v) => MapEntry(k, double.parse(v.toStringAsFixed(4))),
    );
  }

  /// Minimum variance (allocate more to lower volatility assets).
  static Map<String, double> minVariance(
    Map<String, List<KlineBar>> barsBySymbol, {
    double maxWeight = 0.2,
  }) {
    return riskParity(
      barsBySymbol,
      maxWeight: maxWeight,
    ); // Same logic for simplified version
  }

  /// Kelly criterion position sizing for a single asset.
  static double kellyFraction(
    List<KlineBar> bars, {
    double maxFraction = 0.25,
  }) {
    final stats = Statistics.returnStats(bars);
    final winRate = ((stats['winRate'] as double?) ?? 50) / 100;
    final avgGain = bars.length > 1 ? stats['totalReturn'] as double? ?? 0 : 0;
    final lossRate = 1 - winRate;
    if (lossRate <= 0 || avgGain <= 0) return 0;
    final kelly = winRate - lossRate / (avgGain / 100);
    return min(max(kelly, 0), maxFraction);
  }

  /// Cap weights: no single asset exceeds maxWeight, redistribute excess.
  static Map<String, double> _capWeights(
    Map<String, double> weights,
    double maxWeight,
  ) {
    var capped = Map<String, double>.from(weights);
    for (var iter = 0; iter < 10; iter++) {
      double excess = 0;
      int uncapped = 0;
      for (final entry in capped.entries) {
        if (entry.value > maxWeight) {
          excess += entry.value - maxWeight;
          capped[entry.key] = maxWeight;
        } else {
          uncapped++;
        }
      }
      if (excess <= 0.001 || uncapped == 0) break;
      final redistribution = excess / uncapped;
      for (final key in capped.keys.toList()) {
        if (capped[key]! < maxWeight) {
          capped[key] = capped[key]! + redistribution;
        }
      }
    }
    return capped;
  }

  /// VaR (Value at Risk) at given confidence level.
  static double valueAtRisk(List<KlineBar> bars, {double confidence = 0.95}) {
    if (bars.length < 10) return 0;
    final returns = <double>[];
    for (var i = 1; i < bars.length; i++) {
      returns.add((bars[i].close - bars[i - 1].close) / bars[i - 1].close);
    }
    returns.sort();
    final idx = ((1 - confidence) * returns.length).floor();
    return idx < returns.length
        ? -(returns[idx] * 100)
        : 0; // Return as positive percentage
  }

  /// CVaR (Conditional VaR): expected loss beyond VaR.
  static double conditionalVaR(
    List<KlineBar> bars, {
    double confidence = 0.95,
  }) {
    if (bars.length < 10) return 0;
    final returns = <double>[];
    for (var i = 1; i < bars.length; i++) {
      returns.add((bars[i].close - bars[i - 1].close) / bars[i - 1].close);
    }
    returns.sort();
    final cutoff = ((1 - confidence) * returns.length).floor();
    if (cutoff <= 0) return 0;
    double sum = 0;
    for (var i = 0; i < cutoff; i++) {
      sum += returns[i];
    }
    return -(sum / cutoff * 100);
  }

  /// Beta vs benchmark.
  static double beta(List<KlineBar> asset, List<KlineBar> benchmark) {
    final n = min(asset.length, benchmark.length);
    if (n < 10) return 1;
    final ra = <double>[], rb = <double>[];
    for (var i = 1; i < n; i++) {
      ra.add((asset[i].close - asset[i - 1].close) / asset[i - 1].close);
      rb.add(
        (benchmark[i].close - benchmark[i - 1].close) / benchmark[i - 1].close,
      );
    }
    final mb = rb.reduce((a, b) => a + b) / rb.length;
    double cov = 0, varB = 0;
    for (var i = 0; i < ra.length; i++) {
      cov += (ra[i] - ra.reduce((a, b) => a + b) / ra.length) * (rb[i] - mb);
      varB += pow(rb[i] - mb, 2);
    }
    return varB > 0 ? cov / varB : 1;
  }

  /// Black-Litterman: adjust market equilibrium weights with subjective views.
  static Map<String, double> blackLitterman(
    Map<String, List<KlineBar>> barsBySymbol,
    Map<String, double> marketWeights,
    List<Map<String, dynamic>> views, {
    double tau = 0.05,
    double maxWeight = 0.3,
  }) {
    final symbols = barsBySymbol.keys.toList();
    final n = symbols.length;
    if (n < 2 || views.isEmpty) return marketWeights;

    final vols = <double>[];
    for (final s in symbols) {
      final stats = Statistics.returnStats(barsBySymbol[s]!);
      vols.add((stats['annualizedVolatility'] as double?) ?? 0.2);
    }

    const delta = 2.5;
    final pi = List.generate(
      n,
      (i) => delta * vols[i] * vols[i] * (marketWeights[symbols[i]] ?? 1.0 / n),
    );

    final adjusted = List.generate(n, (i) => pi[i]);
    for (final view in views) {
      final asset = view['asset'] as String?;
      final expectedReturn = (view['expectedReturn'] as num?)?.toDouble();
      if (asset == null || expectedReturn == null) continue;
      final idx = symbols.indexOf(asset);
      if (idx >= 0) {
        adjusted[idx] = (1 - tau) * pi[idx] + tau * expectedReturn;
      }
    }

    final totalAdj = adjusted.where((r) => r > 0).fold(0.0, (a, b) => a + b);
    final weights = <String, double>{};
    for (var i = 0; i < n; i++) {
      weights[symbols[i]] = totalAdj > 0
          ? max(adjusted[i], 0) / totalAdj
          : 1.0 / n;
    }

    return _capWeights(
      weights,
      maxWeight,
    ).map((k, v) => MapEntry(k, double.parse(v.toStringAsFixed(4))));
  }
}
