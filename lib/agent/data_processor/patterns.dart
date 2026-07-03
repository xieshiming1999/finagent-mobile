import 'dart:math' show min, max;

import '../data_fetcher/models.dart';

/// K-line pattern recognition — 40+ candlestick patterns.
class PatternRecognition {
  /// Detect single-bar patterns on the last candle.
  static List<Map<String, dynamic>> _singleBar(List<KlineBar> bars) {
    if (bars.length < 2) return [];
    final patterns = <Map<String, dynamic>>[];
    final c = bars.last;
    final p = bars[bars.length - 2];
    final body = (c.close - c.open).abs();
    final range = c.high - c.low;
    if (range <= 0) return patterns;
    final lower = min(c.open, c.close) - c.low;
    final upper = c.high - max(c.open, c.close);
    final isUp = c.close > c.open;

    // Hammer (锤子线)
    if (lower > body * 2 && upper < body * 0.3) {
      patterns.add(_p('hammer', c, 'bullish', '锤子线：下影线长,看涨反转'));
    }
    // Inverted Hammer (倒锤线)
    if (upper > body * 2 && lower < body * 0.3 && c.close < p.close) {
      patterns.add(_p('inverted_hammer', c, 'bullish', '倒锤线：下跌后出现,潜在反转'));
    }
    // Shooting Star (射击之星)
    if (upper > body * 2 && lower < body * 0.3 && c.close > p.close) {
      patterns.add(_p('shooting_star', c, 'bearish', '射击之星：上涨后出现,看跌反转'));
    }
    // Hanging Man (上吊线)
    if (lower > body * 2 && upper < body * 0.3 && c.close > p.close) {
      patterns.add(_p('hanging_man', c, 'bearish', '上吊线：上涨后锤子形态,看跌'));
    }
    // Doji (十字星)
    if (body / range < 0.1) {
      if (lower > range * 0.3 && upper < range * 0.1) {
        patterns.add(_p('dragonfly_doji', c, 'bullish', '蜻蜓十字：下影线长,看涨'));
      } else if (upper > range * 0.3 && lower < range * 0.1) {
        patterns.add(_p('gravestone_doji', c, 'bearish', '墓碑十字：上影线长,看跌'));
      } else {
        patterns.add(_p('doji', c, 'neutral', '十字星：多空均衡'));
      }
    }
    // Long body (大阳/大阴)
    if (body / range > 0.7) {
      if (isUp) {
        patterns.add(_p('long_white', c, 'bullish', '大阳线：强势上涨'));
      } else {
        patterns.add(_p('long_black', c, 'bearish', '大阴线：强势下跌'));
      }
    }
    // Spinning Top (纺锤线)
    if (body / range > 0.1 &&
        body / range < 0.3 &&
        lower > body &&
        upper > body) {
      patterns.add(_p('spinning_top', c, 'neutral', '纺锤线：犹豫不决'));
    }
    // Marubozu (光头光脚)
    if (upper < body * 0.05 && lower < body * 0.05 && body > 0) {
      if (isUp) {
        patterns.add(_p('white_marubozu', c, 'bullish', '光头光脚阳线：极度强势'));
      } else {
        patterns.add(_p('black_marubozu', c, 'bearish', '光头光脚阴线：极度弱势'));
      }
    }
    // Belt Hold (捉腰带)
    if (isUp && lower < body * 0.05 && upper > body * 0.3) {
      patterns.add(_p('bullish_belt_hold', c, 'bullish', '看涨捉腰带：低开高收'));
    }
    if (!isUp && upper < body * 0.05 && lower > body * 0.3) {
      patterns.add(_p('bearish_belt_hold', c, 'bearish', '看跌捉腰带：高开低收'));
    }
    return patterns;
  }

  /// Detect two-bar patterns.
  static List<Map<String, dynamic>> _twoBar(List<KlineBar> bars) {
    if (bars.length < 3) return [];
    final patterns = <Map<String, dynamic>>[];
    final c = bars.last;
    final p = bars[bars.length - 2];

    // Bullish Engulfing (看涨吞没)
    if (p.close < p.open &&
        c.close > c.open &&
        c.close > p.open &&
        c.open < p.close) {
      patterns.add(_p('bullish_engulfing', c, 'bullish', '看涨吞没：阳线包含前阴线'));
    }
    // Bearish Engulfing (看跌吞没)
    if (p.close > p.open &&
        c.close < c.open &&
        c.open > p.close &&
        c.close < p.open) {
      patterns.add(_p('bearish_engulfing', c, 'bearish', '看跌吞没：阴线包含前阳线'));
    }
    // Bullish Harami (看涨孕线)
    if (p.close < p.open &&
        c.close > c.open &&
        c.open > p.close &&
        c.close < p.open) {
      patterns.add(_p('bullish_harami', c, 'bullish', '看涨孕线：阴线后小阳线'));
    }
    // Bearish Harami (看跌孕线)
    if (p.close > p.open &&
        c.close < c.open &&
        c.close > p.open &&
        c.open < p.close) {
      patterns.add(_p('bearish_harami', c, 'bearish', '看跌孕线：阳线后小阴线'));
    }
    // Piercing (刺穿/曙光初现)
    if (p.close < p.open &&
        c.close > c.open &&
        c.open < p.low &&
        c.close > (p.open + p.close) / 2 &&
        c.close < p.open) {
      patterns.add(_p('piercing', c, 'bullish', '曙光初现：低开后收至前阴线中部以上'));
    }
    // Dark Cloud (乌云盖顶)
    if (p.close > p.open &&
        c.close < c.open &&
        c.open > p.high &&
        c.close < (p.open + p.close) / 2 &&
        c.close > p.open) {
      patterns.add(_p('dark_cloud', c, 'bearish', '乌云盖顶：高开后跌至前阳线中部以下'));
    }
    // Tweezer Top (镊子顶)
    if ((p.high - c.high).abs() / p.high < 0.002 &&
        p.close > p.open &&
        c.close < c.open) {
      patterns.add(_p('tweezer_top', c, 'bearish', '镊子顶：双高点相同,看跌'));
    }
    // Tweezer Bottom (镊子底)
    if ((p.low - c.low).abs() / p.low < 0.002 &&
        p.close < p.open &&
        c.close > c.open) {
      patterns.add(_p('tweezer_bottom', c, 'bullish', '镊子底：双低点相同,看涨'));
    }
    // Gap Up / Gap Down
    if (c.low > p.high) patterns.add(_p('gap_up', c, 'bullish', '跳空高开'));
    if (c.high < p.low) patterns.add(_p('gap_down', c, 'bearish', '跳空低开'));
    // On Neck (颈线)
    if (p.close < p.open &&
        c.close > c.open &&
        (c.close - p.low).abs() / p.low < 0.003) {
      patterns.add(_p('on_neck', c, 'bearish', '颈线：反弹仅到前低,空头延续'));
    }
    return patterns;
  }

  /// Detect three-bar patterns.
  static List<Map<String, dynamic>> _threeBar(List<KlineBar> bars) {
    if (bars.length < 5) return [];
    final patterns = <Map<String, dynamic>>[];
    final b = bars.sublist(bars.length - 5);

    // Three White Soldiers (三连阳/三兵)
    if (b[2].close > b[2].open &&
        b[3].close > b[3].open &&
        b[4].close > b[4].open &&
        b[3].close > b[2].close &&
        b[4].close > b[3].close) {
      patterns.add(_p('three_white_soldiers', b[4], 'bullish', '三兵：连续三根阳线递增'));
    }
    // Three Black Crows (三只乌鸦)
    if (b[2].close < b[2].open &&
        b[3].close < b[3].open &&
        b[4].close < b[4].open &&
        b[3].close < b[2].close &&
        b[4].close < b[3].close) {
      patterns.add(_p('three_black_crows', b[4], 'bearish', '三只乌鸦：连续三根阴线递减'));
    }
    // Morning Star (早晨之星)
    final body0 = (b[2].close - b[2].open).abs();
    final body1 = (b[3].close - b[3].open).abs();
    if (b[2].close < b[2].open &&
        body0 > body1 * 2 &&
        b[4].close > b[4].open &&
        b[4].close > (b[2].open + b[2].close) / 2) {
      patterns.add(
        _p('morning_star', b[4], 'bullish', '早晨之星：三K线看涨反转', confidence: 75),
      );
    }
    // Evening Star (黄昏之星)
    if (b[2].close > b[2].open &&
        body0 > body1 * 2 &&
        b[4].close < b[4].open &&
        b[4].close < (b[2].open + b[2].close) / 2) {
      patterns.add(
        _p('evening_star', b[4], 'bearish', '黄昏之星：三K线看跌反转', confidence: 75),
      );
    }
    // Three Inside Up (三内部上涨)
    if (b[2].close < b[2].open &&
        b[3].close > b[3].open &&
        b[3].open > b[2].close &&
        b[3].close < b[2].open &&
        b[4].close > b[2].open) {
      patterns.add(_p('three_inside_up', b[4], 'bullish', '三内部上涨：孕线后突破'));
    }
    // Three Inside Down (三内部下跌)
    if (b[2].close > b[2].open &&
        b[3].close < b[3].open &&
        b[3].close > b[2].open &&
        b[3].open < b[2].close &&
        b[4].close < b[2].open) {
      patterns.add(_p('three_inside_down', b[4], 'bearish', '三内部下跌：孕线后破位'));
    }
    // Three Outside Up
    if (b[2].close < b[2].open &&
        b[3].close > b[3].open &&
        b[3].close > b[2].open &&
        b[3].open < b[2].close &&
        b[4].close > b[3].close) {
      patterns.add(_p('three_outside_up', b[4], 'bullish', '三外部上涨：吞没后继续'));
    }
    // Three Outside Down
    if (b[2].close > b[2].open &&
        b[3].close < b[3].open &&
        b[3].open > b[2].close &&
        b[3].close < b[2].open &&
        b[4].close < b[3].close) {
      patterns.add(_p('three_outside_down', b[4], 'bearish', '三外部下跌：吞没后继续'));
    }
    // Rising Three Methods (上升三法)
    if (b[0].close > b[0].open &&
        b[4].close > b[4].open &&
        b[4].close > b[0].close &&
        b[1].close < b[1].open &&
        b[2].close < b[2].open &&
        b[3].close < b[3].open &&
        b[1].low > b[0].low &&
        b[3].high < b[0].high) {
      patterns.add(_p('rising_three', b[4], 'bullish', '上升三法：大阳+三小阴+大阳突破'));
    }
    // Falling Three Methods (下降三法)
    if (b[0].close < b[0].open &&
        b[4].close < b[4].open &&
        b[4].close < b[0].close &&
        b[1].close > b[1].open &&
        b[2].close > b[2].open &&
        b[3].close > b[3].open &&
        b[1].high < b[0].high &&
        b[3].low > b[0].low) {
      patterns.add(_p('falling_three', b[4], 'bearish', '下降三法：大阴+三小阳+大阴破位'));
    }
    // Abandoned Baby (弃婴)
    if (b[2].close < b[2].open &&
        b[4].close > b[4].open &&
        b[3].high < b[2].low &&
        b[3].high < b[4].low) {
      patterns.add(
        _p(
          'bullish_abandoned_baby',
          b[4],
          'bullish',
          '看涨弃婴：跳空十字后反转',
          confidence: 80,
        ),
      );
    }
    if (b[2].close > b[2].open &&
        b[4].close < b[4].open &&
        b[3].low > b[2].high &&
        b[3].low > b[4].high) {
      patterns.add(
        _p(
          'bearish_abandoned_baby',
          b[4],
          'bearish',
          '看跌弃婴：跳空十字后反转',
          confidence: 80,
        ),
      );
    }
    // One Yang Three Yin (一阳穿三阴)
    final yang = b[4];
    if (yang.close > yang.open &&
        b[1].close < b[1].open &&
        b[2].close < b[2].open &&
        b[3].close < b[3].open &&
        yang.close > b[1].open) {
      patterns.add(_p('one_yang_three_yin', yang, 'bullish', '一阳穿三阴：强势反转'));
    }
    return patterns;
  }

  /// Detect multi-bar structural patterns (double top/bottom).
  static List<Map<String, dynamic>> _structural(
    List<KlineBar> bars, {
    int lookback = 40,
  }) {
    final patterns = <Map<String, dynamic>>[];
    if (bars.length < lookback) return patterns;
    final recent = bars.sublist(bars.length - lookback);
    final highs = recent.map((b) => b.high).toList();
    final lows = recent.map((b) => b.low).toList();

    // Double Top
    final maxH = highs.reduce((a, b) => a > b ? a : b);
    final peaks = <int>[];
    for (var i = 2; i < highs.length - 2; i++) {
      if (highs[i] > highs[i - 1] &&
          highs[i] > highs[i + 1] &&
          highs[i] > maxH * 0.95) {
        peaks.add(i);
      }
    }
    if (peaks.length >= 2 && (peaks.last - peaks.first) > 5) {
      if ((highs[peaks.first] - highs[peaks.last]).abs() / highs[peaks.first] <
          0.03) {
        patterns.add(
          _p('double_top', recent.last, 'bearish', '双顶形态', confidence: 70),
        );
      }
    }

    // Double Bottom
    final minL = lows.reduce((a, b) => a < b ? a : b);
    final troughs = <int>[];
    for (var i = 2; i < lows.length - 2; i++) {
      if (lows[i] < lows[i - 1] &&
          lows[i] < lows[i + 1] &&
          lows[i] < minL * 1.05) {
        troughs.add(i);
      }
    }
    if (troughs.length >= 2 && (troughs.last - troughs.first) > 5) {
      if ((lows[troughs.first] - lows[troughs.last]).abs() /
              lows[troughs.first] <
          0.03) {
        patterns.add(
          _p('double_bottom', recent.last, 'bullish', '双底形态', confidence: 70),
        );
      }
    }

    // Head and Shoulders (头肩顶)
    if (peaks.length >= 3) {
      final left = highs[peaks[0]],
          head = highs[peaks[1]],
          right = highs[peaks[2]];
      if (head > left && head > right && (left - right).abs() / left < 0.05) {
        patterns.add(
          _p(
            'head_shoulders_top',
            recent.last,
            'bearish',
            '头肩顶：经典看跌反转形态',
            confidence: 65,
          ),
        );
      }
    }
    if (troughs.length >= 3) {
      final left = lows[troughs[0]],
          head = lows[troughs[1]],
          right = lows[troughs[2]];
      if (head < left && head < right && (left - right).abs() / left < 0.05) {
        patterns.add(
          _p(
            'head_shoulders_bottom',
            recent.last,
            'bullish',
            '头肩底：经典看涨反转形态',
            confidence: 65,
          ),
        );
      }
    }

    return patterns;
  }

  /// Detect all patterns (40+ types).
  static List<Map<String, dynamic>> detectAll(List<KlineBar> bars) {
    final all = <Map<String, dynamic>>[];
    all.addAll(_singleBar(bars));
    all.addAll(_twoBar(bars));
    all.addAll(_threeBar(bars));
    all.addAll(_structural(bars));
    return all;
  }

  /// Legacy detect — basic patterns only.
  static List<Map<String, dynamic>> detect(List<KlineBar> bars) =>
      detectAll(bars);

  static Map<String, dynamic> _p(
    String pattern,
    KlineBar bar,
    String signal,
    String description, {
    int confidence = 60,
  }) => {
    'pattern': pattern,
    'date': bar.date,
    'signal': signal,
    'confidence': confidence,
    'description': description,
  };
}
