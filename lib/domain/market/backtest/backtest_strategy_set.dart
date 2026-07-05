import 'dart:math';

import 'backtest_core.dart';
import 'backtest_strategies.dart';

const strategyMap = {
  'rsi': strategyRSI,
  'rsi_conservative': strategyRSIConservative,
  'bollinger': strategyBollinger,
  'boll_tight': strategyBollingerTight,
  'macd': strategyMACD,
  'ema_cross': strategyEMACross,
  'supertrend': strategySupertrend,
  'donchian': strategyDonchian,
  'kdj': strategyKDJ,
  'ma_golden_cross': strategyMAGoldenCross,
  'volume_breakout': strategyVolumeBreakout,
  'dual_thrust': strategyDualThrust,
  'adx_emerging': strategyADXEmerging,
  'mean_reversion': strategyMeanReversion,
  'turtle_breakout': strategyTurtleBreakout,
};

List<Trade> strategyRSIConservative(List<Candle> candles) =>
    strategyRSI(candles, oversold: 25, overbought: 75);

List<Trade> strategyBollingerTight(List<Candle> candles) =>
    strategyBollinger(candles, stdMult: 1.5);

// ─── A-Share Strategies ───

List<Trade> strategyKDJ(List<Candle> candles, {int period = 9}) {
  final trades = <Trade>[];
  if (candles.length < period + 1) return trades;

  double prevK = 50, prevD = 50;
  bool inPosition = false;
  int entryIdx = 0;

  for (var i = period - 1; i < candles.length; i++) {
    var high = candles[i].high, low = candles[i].low;
    for (var j = i - period + 1; j < i; j++) {
      if (candles[j].high > high) high = candles[j].high;
      if (candles[j].low < low) low = candles[j].low;
    }
    final rsv = high == low
        ? 50.0
        : (candles[i].close - low) / (high - low) * 100;
    final k = 2 / 3 * prevK + 1 / 3 * rsv;
    final d = 2 / 3 * prevD + 1 / 3 * k;
    final j = 3 * k - 2 * d;

    if (!inPosition && j < 0 && k > d && prevK <= prevD) {
      inPosition = true;
      entryIdx = i;
    } else if (inPosition && (j > 100 || (k < d && prevK >= prevD))) {
      trades.add(
        Trade(
            entryDate: candles[entryIdx].date,
            entryPrice: candles[entryIdx].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          )
          ..returnPct =
              (candles[i].close - candles[entryIdx].close) /
              candles[entryIdx].close *
              100,
      );
      inPosition = false;
    }
    prevK = k;
    prevD = d;
  }
  return trades;
}

List<Trade> strategyMAGoldenCross(
  List<Candle> candles, {
  int shortPeriod = 5,
  int longPeriod = 20,
}) {
  final trades = <Trade>[];
  final closes = candles.map((c) => c.close).toList();
  final maShort = calcEMA(closes, shortPeriod);
  final maLong = calcEMA(closes, longPeriod);

  bool inPosition = false;
  int entryIdx = 0;

  for (var i = longPeriod; i < candles.length; i++) {
    if (maShort[i] == null ||
        maLong[i] == null ||
        maShort[i - 1] == null ||
        maLong[i - 1] == null) {
      continue;
    }
    final goldenCross =
        maShort[i - 1]! <= maLong[i - 1]! && maShort[i]! > maLong[i]!;
    final deathCross =
        maShort[i - 1]! >= maLong[i - 1]! && maShort[i]! < maLong[i]!;

    if (!inPosition && goldenCross) {
      inPosition = true;
      entryIdx = i;
    } else if (inPosition && deathCross) {
      trades.add(
        Trade(
            entryDate: candles[entryIdx].date,
            entryPrice: candles[entryIdx].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          )
          ..returnPct =
              (candles[i].close - candles[entryIdx].close) /
              candles[entryIdx].close *
              100,
      );
      inPosition = false;
    }
  }
  return trades;
}

List<Trade> strategyVolumeBreakout(
  List<Candle> candles, {
  int lookback = 20,
  double volMultiple = 1.5,
}) {
  final trades = <Trade>[];
  if (candles.length < lookback + 1) return trades;

  bool inPosition = false;
  int entryIdx = 0;

  for (var i = lookback; i < candles.length; i++) {
    // Average volume of last N days
    var avgVol = 0.0;
    var highestPrice = 0.0;
    for (var j = i - lookback; j < i; j++) {
      avgVol += candles[j].volume;
      if (candles[j].high > highestPrice) highestPrice = candles[j].high;
    }
    avgVol /= lookback;

    final volumeBreakout = candles[i].volume > avgVol * volMultiple;
    final priceBreakout = candles[i].close > highestPrice;

    if (!inPosition && volumeBreakout && priceBreakout) {
      inPosition = true;
      entryIdx = i;
    } else if (inPosition) {
      // Exit: price drops below entry -5% or after 10 days
      final holdDays = i - entryIdx;
      final loss =
          (candles[i].close - candles[entryIdx].close) /
          candles[entryIdx].close *
          100;
      if (loss < -5 || holdDays >= 10) {
        trades.add(
          Trade(
            entryDate: candles[entryIdx].date,
            entryPrice: candles[entryIdx].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          )..returnPct = loss,
        );
        inPosition = false;
      }
    }
  }
  return trades;
}
// ─── Additional Strategies (from PandoraTrader/Qbot/abu) ───

/// Dual Thrust (PandoraTrader): breakout on range-based bands
List<Trade> strategyDualThrust(
  List<Candle> candles, {
  int days = 4,
  double k1 = 0.5,
  double k2 = 0.5,
}) {
  final trades = <Trade>[];
  if (candles.length < days + 1) return trades;
  bool inLong = false, inShort = false;
  int entryIdx = 0;

  for (var i = days; i < candles.length; i++) {
    double hh = candles[i - days].high, hc = candles[i - days].close;
    double lc = candles[i - days].close, ll = candles[i - days].low;
    for (var j = i - days + 1; j < i; j++) {
      if (candles[j].high > hh) hh = candles[j].high;
      if (candles[j].close > hc) hc = candles[j].close;
      if (candles[j].close < lc) lc = candles[j].close;
      if (candles[j].low < ll) ll = candles[j].low;
    }
    final range = max(hh - lc, hc - ll);
    final upper = candles[i].open + k1 * range;
    final lower = candles[i].open - k2 * range;

    if (!inLong && !inShort && candles[i].high >= upper) {
      inLong = true;
      entryIdx = i;
    } else if (!inLong && !inShort && candles[i].low <= lower) {
      inShort = true;
      entryIdx = i;
    } else if (inLong && candles[i].low <= lower) {
      trades.add(
        Trade(
            entryDate: candles[entryIdx].date,
            entryPrice: candles[entryIdx].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          )
          ..returnPct =
              (candles[i].close - candles[entryIdx].close) /
              candles[entryIdx].close *
              100,
      );
      inLong = false;
    } else if (inShort && candles[i].high >= upper) {
      trades.add(
        Trade(
            entryDate: candles[entryIdx].date,
            entryPrice: candles[entryIdx].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          )
          ..returnPct =
              (candles[entryIdx].close - candles[i].close) /
              candles[entryIdx].close *
              100,
      );
      inShort = false;
    }
  }
  return trades;
}

/// ADX Emerging Trend (Qbot): enter when ADX is low but rising + EMA alignment
List<Trade> strategyADXEmerging(
  List<Candle> candles, {
  int adxPeriod = 14,
  double adxThreshold = 25,
}) {
  final trades = <Trade>[];
  final closes = candles.map((c) => c.close).toList();
  final ema13 = calcEMA(closes, 13), ema55 = calcEMA(closes, 55);
  final highs = candles.map((c) => c.high).toList();
  final lows = candles.map((c) => c.low).toList();

  // Simplified ADX calculation
  final adxVals = List<double?>.filled(candles.length, null);
  final trs = List<double>.filled(candles.length, 0);
  final pdm = List<double>.filled(candles.length, 0);
  final mdm = List<double>.filled(candles.length, 0);
  for (var i = 1; i < candles.length; i++) {
    trs[i] = [
      highs[i] - lows[i],
      (highs[i] - closes[i - 1]).abs(),
      (lows[i] - closes[i - 1]).abs(),
    ].reduce(max);
    final up = highs[i] - highs[i - 1], dn = lows[i - 1] - lows[i];
    pdm[i] = (up > dn && up > 0) ? up : 0;
    mdm[i] = (dn > up && dn > 0) ? dn : 0;
  }
  double atr = 0, aPdm = 0, aMdm = 0;
  for (var i = 1; i <= adxPeriod && i < candles.length; i++) {
    atr += trs[i];
    aPdm += pdm[i];
    aMdm += mdm[i];
  }
  double prevDx = 0;
  for (var i = adxPeriod; i < candles.length; i++) {
    if (i > adxPeriod) {
      atr = atr - atr / adxPeriod + trs[i];
      aPdm = aPdm - aPdm / adxPeriod + pdm[i];
      aMdm = aMdm - aMdm / adxPeriod + mdm[i];
    }
    final pdi = atr != 0 ? aPdm / atr * 100 : 0.0,
        mdi = atr != 0 ? aMdm / atr * 100 : 0.0;
    final dx = (pdi + mdi) != 0 ? (pdi - mdi).abs() / (pdi + mdi) * 100 : 0.0;
    adxVals[i] = i == adxPeriod
        ? dx
        : (prevDx * (adxPeriod - 1) + dx) / adxPeriod;
    prevDx = adxVals[i]!;
  }

  bool inPosition = false;
  int entryIdx = 0;
  for (var i = adxPeriod + 1; i < candles.length; i++) {
    if (adxVals[i] == null ||
        adxVals[i - 1] == null ||
        ema13[i] == null ||
        ema55[i] == null) {
      continue;
    }
    final adxRising = adxVals[i]! > adxVals[i - 1]!;
    final adxLow = adxVals[i]! <= adxThreshold;
    final emaAligned = ema13[i]! > ema55[i]!;

    if (!inPosition && adxLow && adxRising && emaAligned) {
      inPosition = true;
      entryIdx = i;
    } else if (inPosition && (adxVals[i]! > 50 || !emaAligned)) {
      trades.add(
        Trade(
            entryDate: candles[entryIdx].date,
            entryPrice: candles[entryIdx].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          )
          ..returnPct =
              (candles[i].close - candles[entryIdx].close) /
              candles[entryIdx].close *
              100,
      );
      inPosition = false;
    }
  }
  return trades;
}

/// Mean Reversion (abu-inspired): buy when price drops N% from MA, sell when back to MA
List<Trade> strategyMeanReversion(
  List<Candle> candles, {
  int maPeriod = 20,
  double deviationPct = 3,
}) {
  final trades = <Trade>[];
  final closes = candles.map((c) => c.close).toList();
  final ma = calcSMA(closes, maPeriod);
  bool inPosition = false;
  int entryIdx = 0;

  for (var i = maPeriod; i < candles.length; i++) {
    if (ma[i] == null) continue;
    final bias = (closes[i] - ma[i]!) / ma[i]! * 100;
    if (!inPosition && bias < -deviationPct) {
      inPosition = true;
      entryIdx = i;
    } else if (inPosition && bias > 0) {
      trades.add(
        Trade(
            entryDate: candles[entryIdx].date,
            entryPrice: candles[entryIdx].close,
            exitDate: candles[i].date,
            exitPrice: candles[i].close,
          )
          ..returnPct =
              (candles[i].close - candles[entryIdx].close) /
              candles[entryIdx].close *
              100,
      );
      inPosition = false;
    }
  }
  return trades;
}

/// Turtle Breakout (abu): N-day high entry, N/2-day low exit
List<Trade> strategyTurtleBreakout(
  List<Candle> candles, {
  int entryPeriod = 20,
  int exitPeriod = 10,
}) {
  final trades = <Trade>[];
  bool inPosition = false;
  int entryIdx = 0;

  for (var i = entryPeriod; i < candles.length; i++) {
    double entryHigh = candles[i - entryPeriod].high;
    for (var j = i - entryPeriod + 1; j < i; j++) {
      if (candles[j].high > entryHigh) entryHigh = candles[j].high;
    }

    if (!inPosition && candles[i].close > entryHigh) {
      inPosition = true;
      entryIdx = i;
    } else if (inPosition) {
      final ep = min(exitPeriod, i - entryIdx);
      double exitLow = candles[i].low;
      for (var j = max(i - ep, entryIdx); j < i; j++) {
        if (candles[j].low < exitLow) exitLow = candles[j].low;
      }
      if (candles[i].close < exitLow) {
        trades.add(
          Trade(
              entryDate: candles[entryIdx].date,
              entryPrice: candles[entryIdx].close,
              exitDate: candles[i].date,
              exitPrice: candles[i].close,
            )
            ..returnPct =
                (candles[i].close - candles[entryIdx].close) /
                candles[entryIdx].close *
                100,
        );
        inPosition = false;
      }
    }
  }
  return trades;
}
