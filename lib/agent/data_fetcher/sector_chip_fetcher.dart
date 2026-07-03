import 'dart:convert';

import 'package:http/http.dart' as http;

import 'http_utils.dart';
import 'models.dart';

/// EastMoney sector/board ranking + chip distribution APIs.
class EastMoneySectorFetcher {
  final _rateLimiter = RateLimiter();

  /// Get sector/board rankings (板块排名).
  /// boardType: 'industry' (行业板块), 'concept' (概念板块), 'area' (地域板块)
  Future<List<Map<String, dynamic>>> getSectorRanking({
    String boardType = 'industry',
  }) async {
    final fs = switch (boardType) {
      'concept' => 'm:90 t:3 f:!50',
      'area' => 'm:90 t:1 f:!50',
      _ => 'm:90 t:2 f:!50', // industry
    };

    final response = await fetchWithRetry(
      'https://push2delay.eastmoney.com/api/qt/clist/get',
      queryParams: {
        'pn': '1', 'pz': '100', 'po': '1', 'np': '1',
        'ut': 'bd1d9ddb04089700cf9c27f6f7426281',
        'fltt': '2', 'invt': '2',
        'fid': 'f3', // sort by changePct
        'fs': fs,
        'fields': 'f2,f3,f4,f8,f12,f14,f104,f105,f128,f140,f141',
      },
      rateLimiter: _rateLimiter,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final diff = (json['data'] as Map?)?['diff'] as List? ?? [];

    return diff
        .map((item) {
          if (item is! Map) return <String, dynamic>{};
          return <String, dynamic>{
            'code': '${item['f12'] ?? ''}',
            'name': '${item['f14'] ?? ''}',
            'changePct': _d(item['f3']),
            'changeAmount': _d(item['f4']),
            'turnoverRate': _d(item['f8']),
            'upCount': item['f104'] ?? 0,
            'downCount': item['f105'] ?? 0,
            'leadingStock': '${item['f140'] ?? ''}',
            'leadingChangePct': _d(item['f141']),
          };
        })
        .where((m) => m['code'] != '')
        .toList();
  }

  /// Get sector constituent stocks (板块成分股).
  Future<List<StockQuote>> getSectorStocks(String sectorCode) async {
    final response = await fetchWithRetry(
      'https://push2delay.eastmoney.com/api/qt/clist/get',
      queryParams: {
        'pn': '1',
        'pz': '200',
        'po': '1',
        'np': '1',
        'ut': 'bd1d9ddb04089700cf9c27f6f7426281',
        'fltt': '2',
        'invt': '2',
        'fid': 'f3',
        'fs': 'b:$sectorCode f:!50',
        'fields': 'f2,f3,f4,f5,f6,f7,f8,f9,f12,f14,f15,f16,f17,f18,f20,f23',
      },
      rateLimiter: _rateLimiter,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final diff = (json['data'] as Map?)?['diff'] as List? ?? [];

    return diff
        .map((item) {
          if (item is! Map) return null;
          final code = '${item['f12'] ?? ''}';
          if (code.isEmpty) return null;
          return StockQuote(
            code: code,
            name: '${item['f14'] ?? ''}',
            price: _d(item['f2']),
            change: _d(item['f4']),
            changePct: _d(item['f3']),
            open: _d(item['f17']),
            high: _d(item['f15']),
            low: _d(item['f16']),
            prevClose: _d(item['f18']),
            volume: _d(item['f5']),
            amount: _d(item['f6']),
            pe: _dn(item['f9']),
            pb: _dn(item['f23']),
            turnoverRate: _dn(item['f8']),
            marketCap: _dn(item['f20']),
            source: '东方财富',
          );
        })
        .whereType<StockQuote>()
        .toList();
  }

  /// Get chip distribution (筹码分布) for a stock.
  Future<Map<String, dynamic>> getChipDistribution(String code) async {
    final response = await fetchWithRetry(
      'https://datacenter-web.eastmoney.com/api/data/v1/get',
      queryParams: {
        'reportName': 'RPT_F10_CHIP_DISTRIBUTION',
        'columns': 'ALL',
        'filter': '(SECURITY_CODE="$code")',
        'pageNumber': '1',
        'pageSize': '1',
        'sortColumns': 'TRADE_DATE',
        'sortTypes': '-1',
        'source': 'WEB',
        'client': 'WEB',
      },
      rateLimiter: _rateLimiter,
    );

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final result = json['result'] as Map<String, dynamic>?;
    final data = result?['data'] as List?;

    if (data == null || data.isEmpty) {
      // Fallback: use daily kline to estimate chip distribution
      return await _estimateChipFromKline(code);
    }

    final chip = data.first as Map<String, dynamic>;
    return {
      'code': code,
      'date': chip['TRADE_DATE'],
      'avgCost': _dn(chip['AVG_COST']),
      'profitRatio': _dn(chip['PROFIT_RATIO']),
      'concentration70': _dn(chip['CONCENTRATION_70']),
      'concentration90': _dn(chip['CONCENTRATION_90']),
      'source': '东方财富',
    };
  }

  /// Estimate chip distribution from recent K-line volume distribution.
  Future<Map<String, dynamic>> _estimateChipFromKline(String code) async {
    final secId = code.startsWith('6') ? '1.$code' : '0.$code';
    http.Response response;
    try {
      response = await fetchWithRetry(
        'https://push2his.eastmoney.com/api/qt/stock/kline/get',
        queryParams: {
          'fields1': 'f1,f2,f3,f4,f5,f6',
          'fields2': 'f51,f52,f53,f54,f55,f56,f57',
          'ut': '7eea3edcaed734bea9cbfc24409ed989',
          'klt': '101',
          'fqt': '1',
          'secid': secId,
          'beg': _daysAgo(60),
          'end': '20500101',
        },
        rateLimiter: _rateLimiter,
      );
    } catch (e) {
      return {
        'code': code,
        'error': 'chip fallback kline unavailable: $e',
        'source': '东方财富(估算失败)',
      };
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final klines = (json['data'] as Map?)?['klines'] as List? ?? [];

    if (klines.isEmpty) return {'code': code, 'error': 'no data'};

    // Estimate: weighted average cost using volume
    double totalVolPrice = 0, totalVol = 0;
    double currentPrice = 0;
    for (final line in klines) {
      final parts = '$line'.split(',');
      if (parts.length < 6) continue;
      final close = double.tryParse(parts[2]) ?? 0;
      final vol = double.tryParse(parts[5]) ?? 0;
      totalVolPrice += close * vol;
      totalVol += vol;
      currentPrice = close;
    }

    final avgCost = totalVol > 0 ? totalVolPrice / totalVol : currentPrice;
    final profitRatio = avgCost > 0
        ? (currentPrice - avgCost) / avgCost * 100
        : 0;

    return {
      'code': code,
      'avgCost': double.parse(avgCost.toStringAsFixed(2)),
      'profitRatio': double.parse(profitRatio.toStringAsFixed(2)),
      'currentPrice': currentPrice,
      'method': 'estimated_from_60d_kline',
      'source': '东方财富(估算)',
    };
  }

  String _daysAgo(int days) {
    final d = DateTime.now().subtract(Duration(days: days));
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }
}

double _d(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
double? _dn(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
