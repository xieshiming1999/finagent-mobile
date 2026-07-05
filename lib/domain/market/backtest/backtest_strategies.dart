import 'dart:math';

import 'backtest_core.dart';

// ─── Strategies ───

List<Trade> strategyRSI(
  List<Candle> candles, {
  int period = 14,
  double oversold = 40,
  double overbought = 60,
}) {
  final closes = candles.map((c) => c.close).toList();
  final rsi = calcRSI(closes, period: period);
  final trades = <Trade>[];
  Trade? open;
  for (var i = 1; i < candles.length; i++) {
    if (rsi[i] == null) continue;
    if (open == null && rsi[i]! < oversold) {
      open = Trade(
        entryDate: candles[i].date,
        entryPrice: closes[i],
        exitDate: '',
        exitPrice: 0,
      );
    } else if (open != null && rsi[i]! > overbought) {
      trades.add(
        Trade(
          entryDate: open.entryDate,
          entryPrice: open.entryPrice,
          exitDate: candles[i].date,
          exitPrice: closes[i],
        ),
      );
      open = null;
    }
  }
  if (open != null) {
    trades.add(
      Trade(
        entryDate: open.entryDate,
        entryPrice: open.entryPrice,
        exitDate: candles.last.date,
        exitPrice: candles.last.close,
      ),
    );
  }
  return trades;
}

List<Trade> strategyBollinger(
  List<Candle> candles, {
  int period = 20,
  double stdMult = 2.0,
}) {
  final closes = candles.map((c) => c.close).toList();
  final bb = calcBollinger(closes, period: period, stdMult: stdMult);
  final trades = <Trade>[];
  Trade? open;
  for (var i = 1; i < candles.length; i++) {
    if (bb.lower[i] == null) continue;
    if (open == null && closes[i] < bb.lower[i]!) {
      open = Trade(
        entryDate: candles[i].date,
        entryPrice: closes[i],
        exitDate: '',
        exitPrice: 0,
      );
    } else if (open != null && closes[i] > bb.middle[i]!) {
      trades.add(
        Trade(
          entryDate: open.entryDate,
          entryPrice: open.entryPrice,
          exitDate: candles[i].date,
          exitPrice: closes[i],
        ),
      );
      open = null;
    }
  }
  if (open != null) {
    trades.add(
      Trade(
        entryDate: open.entryDate,
        entryPrice: open.entryPrice,
        exitDate: candles.last.date,
        exitPrice: candles.last.close,
      ),
    );
  }
  return trades;
}

List<Trade> strategyMACD(
  List<Candle> candles, {
  int fast = 12,
  int slow = 26,
  int signal = 9,
}) {
  final closes = candles.map((c) => c.close).toList();
  final m = calcMACD(closes, fast: fast, slow: slow, signalPeriod: signal);
  final trades = <Trade>[];
  Trade? open;
  for (var i = 1; i < candles.length; i++) {
    if (m.macd[i] == null ||
        m.signal[i] == null ||
        m.macd[i - 1] == null ||
        m.signal[i - 1] == null) {
      continue;
    }
    if (open == null &&
        m.macd[i - 1]! < m.signal[i - 1]! &&
        m.macd[i]! >= m.signal[i]!) {
      open = Trade(
        entryDate: candles[i].date,
        entryPrice: closes[i],
        exitDate: '',
        exitPrice: 0,
      );
    } else if (open != null &&
        m.macd[i - 1]! > m.signal[i - 1]! &&
        m.macd[i]! <= m.signal[i]!) {
      trades.add(
        Trade(
          entryDate: open.entryDate,
          entryPrice: open.entryPrice,
          exitDate: candles[i].date,
          exitPrice: closes[i],
        ),
      );
      open = null;
    }
  }
  if (open != null) {
    trades.add(
      Trade(
        entryDate: open.entryDate,
        entryPrice: open.entryPrice,
        exitDate: candles.last.date,
        exitPrice: candles.last.close,
      ),
    );
  }
  return trades;
}

List<Trade> strategyEMACross(
  List<Candle> candles, {
  int fastPeriod = 20,
  int slowPeriod = 50,
}) {
  final closes = candles.map((c) => c.close).toList();
  final emaFast = calcEMA(closes, fastPeriod);
  final emaSlow = calcEMA(closes, slowPeriod);
  final trades = <Trade>[];
  Trade? open;
  for (var i = 1; i < candles.length; i++) {
    if (emaFast[i] == null ||
        emaSlow[i] == null ||
        emaFast[i - 1] == null ||
        emaSlow[i - 1] == null) {
      continue;
    }
    if (open == null &&
        emaFast[i - 1]! < emaSlow[i - 1]! &&
        emaFast[i]! >= emaSlow[i]!) {
      open = Trade(
        entryDate: candles[i].date,
        entryPrice: closes[i],
        exitDate: '',
        exitPrice: 0,
      );
    } else if (open != null &&
        emaFast[i - 1]! > emaSlow[i - 1]! &&
        emaFast[i]! <= emaSlow[i]!) {
      trades.add(
        Trade(
          entryDate: open.entryDate,
          entryPrice: open.entryPrice,
          exitDate: candles[i].date,
          exitPrice: closes[i],
        ),
      );
      open = null;
    }
  }
  if (open != null) {
    trades.add(
      Trade(
        entryDate: open.entryDate,
        entryPrice: open.entryPrice,
        exitDate: candles.last.date,
        exitPrice: candles.last.close,
      ),
    );
  }
  return trades;
}

List<Trade> strategySupertrend(
  List<Candle> candles, {
  int atrPeriod = 10,
  double multiplier = 3.0,
}) {
  final highs = candles.map((c) => c.high).toList();
  final lows = candles.map((c) => c.low).toList();
  final closes = candles.map((c) => c.close).toList();
  final dir = calcSupertrend(
    highs,
    lows,
    closes,
    atrPeriod: atrPeriod,
    multiplier: multiplier,
  );
  final trades = <Trade>[];
  Trade? open;
  for (var i = 1; i < candles.length; i++) {
    if (dir[i] == null || dir[i - 1] == null) continue;
    if (open == null && dir[i - 1] == -1 && dir[i] == 1) {
      open = Trade(
        entryDate: candles[i].date,
        entryPrice: closes[i],
        exitDate: '',
        exitPrice: 0,
      );
    } else if (open != null && dir[i - 1] == 1 && dir[i] == -1) {
      trades.add(
        Trade(
          entryDate: open.entryDate,
          entryPrice: open.entryPrice,
          exitDate: candles[i].date,
          exitPrice: closes[i],
        ),
      );
      open = null;
    }
  }
  if (open != null) {
    trades.add(
      Trade(
        entryDate: open.entryDate,
        entryPrice: open.entryPrice,
        exitDate: candles.last.date,
        exitPrice: candles.last.close,
      ),
    );
  }
  return trades;
}

List<Trade> strategyDonchian(List<Candle> candles, {int period = 20}) {
  final highs = candles.map((c) => c.high).toList();
  final lows = candles.map((c) => c.low).toList();
  final closes = candles.map((c) => c.close).toList();
  final dc = calcDonchian(highs, lows, period: period);
  final trades = <Trade>[];
  Trade? open;
  for (var i = 1; i < candles.length; i++) {
    if (dc.upper[i] == null || dc.upper[i - 1] == null) continue;
    if (open == null && highs[i - 1] > dc.upper[i - 1]!) {
      open = Trade(
        entryDate: candles[i].date,
        entryPrice: closes[i],
        exitDate: '',
        exitPrice: 0,
      );
    } else if (open != null && closes[i] < dc.lower[i]!) {
      trades.add(
        Trade(
          entryDate: open.entryDate,
          entryPrice: open.entryPrice,
          exitDate: candles[i].date,
          exitPrice: closes[i],
        ),
      );
      open = null;
    }
  }
  if (open != null) {
    trades.add(
      Trade(
        entryDate: open.entryDate,
        entryPrice: open.entryPrice,
        exitDate: candles.last.date,
        exitPrice: candles.last.close,
      ),
    );
  }
  return trades;
}

// ─── Metrics ───

Map<String, dynamic> calcMetrics(
  List<Trade> trades, {
  double commissionPct = 0.1,
  double slippagePct = 0.05,
  double stampTaxPct = 0.1,
  int annFactor = 252,
}) {
  if (trades.isEmpty) {
    return {
      'total_trades': 0,
      'total_return_pct': 0.0,
      'win_rate_pct': 0.0,
      'note': 'No trades generated',
    };
  }

  // Cost: commission on buy+sell, slippage on buy+sell, stamp tax on sell only
  final costPct = (commissionPct + slippagePct) * 2 + stampTaxPct;
  for (final t in trades) {
    final gross = (t.exitPrice - t.entryPrice) / t.entryPrice * 100;
    t.returnPct = gross - costPct;
  }

  final winners = trades.where((t) => t.returnPct > 0).toList();
  final losers = trades.where((t) => t.returnPct <= 0).toList();
  final winRate = winners.length / trades.length;
  final avgGain = winners.isEmpty
      ? 0.0
      : winners.map((t) => t.returnPct).reduce((a, b) => a + b) /
            winners.length;
  final avgLoss = losers.isEmpty
      ? 0.0
      : losers.map((t) => t.returnPct).reduce((a, b) => a + b) / losers.length;

  double capital = 10000.0;
  double peak = capital;
  double maxDd = 0;
  final equityCurve = <Map<String, dynamic>>[
    {'date': 'start', 'equity': capital, 'drawdown_pct': 0.0},
  ];
  for (final t in trades) {
    capital *= (1 + t.returnPct / 100);
    if (capital > peak) peak = capital;
    final dd = (peak - capital) / peak * 100;
    if (dd > maxDd) maxDd = dd;
    equityCurve.add({
      'date': t.exitDate,
      'equity': double.parse(capital.toStringAsFixed(2)),
      'drawdown_pct': double.parse((-dd).toStringAsFixed(2)),
    });
  }
  final totalReturn = (capital - 10000) / 10000 * 100;

  final sumWins = winners.isEmpty
      ? 0.0
      : winners.map((t) => t.returnPct).reduce((a, b) => a + b);
  final sumLosses = losers.isEmpty
      ? 0.0
      : losers.map((t) => t.returnPct).reduce((a, b) => a + b).abs();
  final profitFactor = sumLosses == 0 ? double.infinity : sumWins / sumLosses;

  final returns = trades.map((t) => t.returnPct).toList();
  final meanR = returns.reduce((a, b) => a + b) / returns.length;
  double sumSq = 0;
  for (final r in returns) {
    sumSq += (r - meanR) * (r - meanR);
  }
  final stdR = returns.length > 1 ? sqrt(sumSq / (returns.length - 1)) : 0.0;
  final riskFree = 0.04 / annFactor;
  final sharpe = stdR == 0
      ? 0.0
      : (meanR / 100 - riskFree) / (stdR / 100) * sqrt(annFactor.toDouble());
  final calmar = maxDd == 0 ? 0.0 : totalReturn / maxDd;
  final expectancy = winRate * avgGain + (1 - winRate) * avgLoss;

  // SQN (System Quality Number) — Van Tharp
  final sqn = trades.length >= 10 && stdR > 0
      ? sqrt(trades.length.toDouble()) * (meanR / stdR)
      : 0.0;

  double r(double v) => double.parse(v.toStringAsFixed(2));

  return {
    'total_trades': trades.length,
    'winners': winners.length,
    'losers': losers.length,
    'win_rate_pct': r(winRate * 100),
    'total_return_pct': r(totalReturn),
    'avg_gain_pct': r(avgGain),
    'avg_loss_pct': r(avgLoss),
    'max_drawdown_pct': r(-maxDd),
    'profit_factor': profitFactor.isInfinite ? 'Infinity' : r(profitFactor),
    'sharpe_ratio': r(sharpe),
    'calmar_ratio': r(calmar),
    'sqn': r(sqn),
    'expectancy_pct': r(expectancy),
    'cost_model':
        'commission=$commissionPct‰ + slippage=$slippagePct‰ + stamp_tax=$stampTaxPct‰ (sell)',
    'best_trade_pct': r(trades.map((t) => t.returnPct).reduce(max)),
    'worst_trade_pct': r(trades.map((t) => t.returnPct).reduce(min)),
    'equity_curve': equityCurve,
  };
}
