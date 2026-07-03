// ignore_for_file: curly_braces_in_flow_control_structures

/// Fundamental scoring system — ported from TradingAgents-CN.
/// Deterministic rule-based scoring for A-share stocks.
class FundamentalScorer {
  /// Score a stock based on fundamental metrics. Returns 0-10 score + details.
  static Map<String, dynamic> score({
    required double pe,
    required double pb,
    double? roe,
    double? netMargin,
    double? debtRatio,
    double? revenueGrowth,
    String? industry,
    String? board, // 主板/创业板/科创板
  }) {
    double total = 0;
    final details = <String, dynamic>{};

    // PE scoring
    if (pe > 0 && pe < 15) {
      total += 2.0;
      details['pe_score'] = 2.0;
      details['pe_note'] = '低估值';
    } else if (pe > 0 && pe < 25) {
      total += 1.0;
      details['pe_score'] = 1.0;
      details['pe_note'] = '合理估值';
    } else if (pe > 50) {
      total -= 1.0;
      details['pe_score'] = -1.0;
      details['pe_note'] = '高估值';
    } else {
      details['pe_score'] = 0;
    }

    // PB scoring
    if (pb > 0 && pb < 1.5) {
      total += 1.0;
      details['pb_score'] = 1.0;
      details['pb_note'] = '低PB';
    } else if (pb > 0 && pb < 3) {
      total += 0.5;
      details['pb_score'] = 0.5;
    } else if (pb > 5) {
      total -= 0.5;
      details['pb_score'] = -0.5;
      details['pb_note'] = '高PB';
    } else {
      details['pb_score'] = 0;
    }

    // ROE scoring
    if (roe != null) {
      if (roe > 15) {
        total += 1.5;
        details['roe_score'] = 1.5;
        details['roe_note'] = '优秀盈利能力';
      } else if (roe > 10) {
        total += 1.0;
        details['roe_score'] = 1.0;
      } else if (roe > 5) {
        total += 0.5;
        details['roe_score'] = 0.5;
      } else {
        details['roe_score'] = 0;
      }
    }

    // Net margin scoring
    if (netMargin != null) {
      if (netMargin > 20) {
        total += 1.0;
        details['margin_score'] = 1.0;
        details['margin_note'] = '高利润率';
      } else if (netMargin > 10) {
        total += 0.5;
        details['margin_score'] = 0.5;
      } else {
        details['margin_score'] = 0;
      }
    }

    // Debt ratio scoring
    if (debtRatio != null) {
      if (debtRatio > 70) {
        total -= 1.0;
        details['debt_score'] = -1.0;
        details['debt_note'] = '高负债风险';
        details['risk_level'] = '较高';
      } else if (debtRatio > 50) {
        details['debt_score'] = 0;
        details['risk_level'] = '中等';
      } else {
        total += 0.5;
        details['debt_score'] = 0.5;
        details['risk_level'] = '较低';
      }
    }

    // Revenue growth scoring
    if (revenueGrowth != null) {
      if (revenueGrowth > 30) {
        total += 1.5;
        details['growth_score'] = 1.5;
        details['growth_note'] = '高速增长';
      } else if (revenueGrowth > 15) {
        total += 1.0;
        details['growth_score'] = 1.0;
      } else if (revenueGrowth > 0) {
        total += 0.5;
        details['growth_score'] = 0.5;
      } else {
        total -= 0.5;
        details['growth_score'] = -0.5;
        details['growth_note'] = '营收下滑';
      }
    }

    // Industry bonus
    if (industry != null) {
      final techIndustries = [
        '科技',
        '软件',
        '互联网',
        '芯片',
        '半导体',
        '新能源',
        'AI',
        '人工智能',
      ];
      final defIndustries = ['银行', '保险', '房地产'];
      if (techIndustries.any((t) => industry.contains(t))) {
        total += 1.0;
        details['industry_score'] = 1.0;
      } else if (defIndustries.any((t) => industry.contains(t))) {
        total -= 0.5;
        details['industry_score'] = -0.5;
      }
    }

    // Board risk
    if (board != null) {
      if (board.contains('创业板') || board.contains('科创板')) {
        details['board_risk'] = '较高(涨跌停±20%)';
      } else if (board.contains('ST')) {
        total -= 2.0;
        details['board_risk'] = '极高(ST)';
      }
    }

    // Clamp to 0-10
    total = total.clamp(0, 10);

    // Investment advice
    String advice;
    if (total >= 7.5) {
      advice = '买入';
    } else if (total >= 6.0)
      advice = '观望';
    else if (total >= 4.0)
      advice = '谨慎';
    else
      advice = '回避';

    return {
      'totalScore': double.parse(total.toStringAsFixed(1)),
      'advice': advice,
      'details': details,
    };
  }

  /// A-share market rules reference.
  static Map<String, dynamic> getMarketRules(String market) {
    return switch (market.toLowerCase()) {
      'cn' || 'a' || 'ashare' => {
        'tradingModel': 'T+1',
        'priceLimit': {
          'normal': '±10%',
          'st': '±5%',
          'chuangye': '±20%',
          'kechuang': '±20%',
        },
        'lotSize': 100,
        'commission': '0.03% (min ¥5) + 0.1% stamp duty (sell only)',
        'shortSelling': 'Not supported for retail',
        'tradingHours': '09:30-11:30, 13:00-15:00 (Beijing)',
        'settlement': 'T+1',
      },
      'hk' => {
        'tradingModel': 'T+0',
        'priceLimit': 'None',
        'lotSize': 'varies by stock',
        'commission': '0.03% + 0.13% stamp',
        'shortSelling': 'Supported (140% margin)',
        'tradingHours': '09:30-16:00 (HK)',
      },
      'us' => {
        'tradingModel': 'T+0',
        'priceLimit': 'None (circuit breaker at ±7%/13%/20% for indices)',
        'lotSize': 1,
        'commission': '0%',
        'shortSelling': 'Supported (PDT rule, 25K min)',
        'tradingHours': '09:30-16:00 (Eastern), pre/after hours available',
      },
      _ => {'error': 'Unknown market: $market'},
    };
  }
}
