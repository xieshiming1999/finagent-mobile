import 'dart:math';
import '../data_fetcher/models.dart';

/// Factor definition for scoring
class FactorDef {
  final String name;
  final String display;
  final String category;
  final bool higherIsBetter;
  FactorDef(this.name, this.display, this.category, this.higherIsBetter);
}

final stockFactors = <String, FactorDef>{
  'pe': FactorDef('pe', 'PE(动态)', 'valuation', false),
  'pb': FactorDef('pb', 'PB', 'valuation', false),
  'marketCap': FactorDef('marketCap', '总市值(亿)', 'size', true),
  'turnoverRate': FactorDef('turnoverRate', '换手率(%)', 'momentum', true),
  'changePct': FactorDef('changePct', '涨跌幅(%)', 'momentum', true),
  'volume': FactorDef('volume', '成交量', 'momentum', true),
  'amount': FactorDef('amount', '成交额', 'momentum', true),
  'price': FactorDef('price', '股价', 'price', false),
  // Fundamental factors (requires separate data fetch)
  'roe': FactorDef('roe', 'ROE(%)', 'profitability', true),
  'grossMargin': FactorDef('grossMargin', '毛利率(%)', 'profitability', true),
  'netMargin': FactorDef('netMargin', '净利率(%)', 'profitability', true),
  'debtRatio': FactorDef('debtRatio', '资产负债率(%)', 'quality', false),
  'revenueYoy': FactorDef('revenueYoy', '营收同比(%)', 'growth', true),
  'profitYoy': FactorDef('profitYoy', '净利同比(%)', 'growth', true),
  'dividendYield': FactorDef('dividendYield', '股息率(%)', 'valuation', true),
  'peg': FactorDef('peg', 'PEG', 'valuation', false),
};

/// Extended stock data with optional fundamental fields
class StockData {
  final StockQuote quote;
  double? roe;
  double? grossMargin;
  double? netMargin;
  double? debtRatio;
  double? revenueYoy;
  double? profitYoy;
  double? dividendYield;
  double? peg;
  double? compositeScore;

  StockData(this.quote);

  double? getField(String field) => switch (field) {
    'price' => quote.price,
    'changePct' => quote.changePct,
    'volume' => quote.volume,
    'amount' => quote.amount,
    'pe' => quote.pe,
    'pb' => quote.pb,
    'marketCap' => quote.marketCap,
    'turnoverRate' => quote.turnoverRate,
    'roe' => roe,
    'grossMargin' => grossMargin,
    'netMargin' => netMargin,
    'debtRatio' => debtRatio,
    'revenueYoy' => revenueYoy,
    'profitYoy' => profitYoy,
    'dividendYield' => dividendYield,
    'peg' => peg,
    'compositeScore' => compositeScore,
    _ => null,
  };
}

/// Stock screening: filter + score + sort
class StockScreener {
  /// Screen stocks from quotes with gate conditions
  static List<StockQuote> screen(
    List<StockQuote> quotes,
    List<ScreenCondition> conditions, {
    String? sortBy,
    bool descending = true,
    int limit = 20,
  }) {
    var result = quotes
        .where((q) => conditions.every((c) => c.matches(q)))
        .toList();
    if (sortBy != null) {
      result.sort((a, b) {
        final va = StockData(a).getField(sortBy);
        final vb = StockData(b).getField(sortBy);
        if (va == null && vb == null) return 0;
        if (va == null) return 1;
        if (vb == null) return -1;
        return descending ? vb.compareTo(va) : va.compareTo(vb);
      });
    }
    return result.take(limit).toList();
  }

  /// Advanced screening with scoring
  static List<StockData> screenWithScore(
    List<StockQuote> quotes,
    List<ScreenCondition> conditions, {
    Map<String, double>? weights,
    String normalize = 'rank',
    String? sortBy,
    bool descending = true,
    int limit = 20,
  }) {
    var data = quotes.map((q) => StockData(q)).toList();

    // Apply gates
    data = data
        .where(
          (d) => conditions.every((c) {
            final v = d.getField(c.field);
            if (v == null) return false;
            return c.matchesValue(v);
          }),
        )
        .toList();

    // Compute composite score if weights provided
    if (weights != null && weights.isNotEmpty) {
      _computeScores(data, weights, normalize);
    }

    // Sort
    final sortField =
        sortBy ?? (weights != null ? 'compositeScore' : 'marketCap');
    data.sort((a, b) {
      final va = a.getField(sortField);
      final vb = b.getField(sortField);
      if (va == null && vb == null) return 0;
      if (va == null) return 1;
      if (vb == null) return -1;
      return descending ? vb.compareTo(va) : va.compareTo(vb);
    });

    return data.take(limit).toList();
  }

  /// Compute weighted composite scores
  static void _computeScores(
    List<StockData> data,
    Map<String, double> weights,
    String normalize,
  ) {
    if (data.isEmpty) return;
    final totalWeight = weights.values.fold(0.0, (a, b) => a + b);
    if (totalWeight <= 0) return;

    for (final d in data) {
      double score = 0;
      for (final entry in weights.entries) {
        final factor = entry.key;
        final weight = entry.value / totalWeight;
        final val = d.getField(factor);
        if (val == null) continue;

        final fdef = stockFactors[factor];
        final ascending = fdef?.higherIsBetter ?? true;

        double normalized;
        if (normalize == 'rank') {
          // Percentile rank within the dataset
          final allVals =
              data.map((x) => x.getField(factor)).whereType<double>().toList()
                ..sort();
          final rank = allVals.indexOf(val);
          normalized = ascending
              ? rank / max(allVals.length - 1, 1)
              : 1 - rank / max(allVals.length - 1, 1);
        } else {
          // Min-max normalization
          final allVals = data
              .map((x) => x.getField(factor))
              .whereType<double>()
              .toList();
          final mn = allVals.reduce(min);
          final mx = allVals.reduce(max);
          normalized = mx > mn ? (val - mn) / (mx - mn) : 0.5;
          if (!ascending) normalized = 1 - normalized;
        }
        score += normalized * weight;
      }
      d.compositeScore = (score * 100).roundToDouble();
    }
  }

  /// Fair value estimation using PE median method
  static Map<String, dynamic> fairValue({
    required double currentPrice,
    required double eps,
    required double growthRate,
    required List<double> peHistory,
  }) {
    if (eps <= 0 || peHistory.isEmpty) {
      return {'error': 'Insufficient data for fair value calculation'};
    }

    final sorted = List<double>.from(peHistory)..sort();
    final peMedian = sorted[sorted.length ~/ 2];
    final pe25 = sorted[(sorted.length * 0.25).floor()];
    final pe75 = sorted[(sorted.length * 0.75).floor()];

    final projectedEps = eps * (1 + growthRate);
    final fairPrice = peMedian * projectedEps;
    final conservativePrice = pe25 * projectedEps;
    final optimisticPrice = pe75 * projectedEps;

    return {
      'current_price': currentPrice,
      'eps': double.parse(eps.toStringAsFixed(4)),
      'growth_rate': double.parse(growthRate.toStringAsFixed(4)),
      'projected_eps': double.parse(projectedEps.toStringAsFixed(4)),
      'pe_median': double.parse(peMedian.toStringAsFixed(2)),
      'pe_25th': double.parse(pe25.toStringAsFixed(2)),
      'pe_75th': double.parse(pe75.toStringAsFixed(2)),
      'fair_price': double.parse(fairPrice.toStringAsFixed(2)),
      'conservative_price': double.parse(conservativePrice.toStringAsFixed(2)),
      'optimistic_price': double.parse(optimisticPrice.toStringAsFixed(2)),
      'margin_of_safety': currentPrice > 0
          ? double.parse(
              ((fairPrice - currentPrice) / currentPrice).toStringAsFixed(4),
            )
          : 0.0,
    };
  }

  /// List available screening factors
  static List<Map<String, String>> listFactors() {
    return stockFactors.entries.map((e) {
      return {
        'name': e.key,
        'display': e.value.display,
        'category': e.value.category,
        'direction': e.value.higherIsBetter
            ? 'higher_is_better'
            : 'lower_is_better',
      };
    }).toList();
  }
}

class ScreenCondition {
  final String field;
  final String op;
  final double value;
  final double? value2;

  ScreenCondition({
    required this.field,
    required this.op,
    required this.value,
    this.value2,
  });

  bool matches(StockQuote q) {
    final v = StockData(q).getField(field);
    if (v == null) return false;
    return matchesValue(v);
  }

  bool matchesValue(double v) => switch (op) {
    '>' => v > value,
    '<' => v < value,
    '>=' => v >= value,
    '<=' => v <= value,
    '==' => v == value,
    '!=' => v != value,
    'between' => value2 != null && v >= value && v <= value2!,
    _ => false,
  };

  factory ScreenCondition.fromJson(Map<String, dynamic> json) =>
      ScreenCondition(
        field: json['field'] as String,
        op: json['op'] as String,
        value: (json['value'] as num).toDouble(),
        value2: json['value2'] != null
            ? (json['value2'] as num).toDouble()
            : null,
      );
}
