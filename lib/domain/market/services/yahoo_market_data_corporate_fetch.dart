import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../agent/tool_context.dart';
import '../repositories/yahoo_market_data_repository.dart';
import 'yahoo_market_data_support.dart';

class YahooMarketDataCorporateFetch {
  final YahooMarketDataRepository _repository;
  final YahooMarketDataSupport _support;
  final http.Client _httpClient;

  YahooMarketDataCorporateFetch({
    required YahooMarketDataRepository repository,
    required YahooMarketDataSupport support,
    required http.Client httpClient,
  }) : _repository = repository,
       _support = support,
       _httpClient = httpClient;

  Future<Map<String, dynamic>> options(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final query = <String, String>{};
    final expiry = input['expiry'] ?? input['date'];
    final expiryUnix = _support.yahooUnixFromDate(expiry);
    if (expiryUnix != null) query['date'] = '$expiryUnix';
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v7/finance/options/$symbol',
      query,
    );
    const gateKey = 'options';
    final openGate = _support.yahooGateMessage(
      gateKey,
      'Yahoo Finance options',
    );
    if (openGate != null) {
      _support.recordApi(uri, 0, 0, success: false, error: openGate);
      throw StateError(openGate);
    }
    final sw = Stopwatch()..start();
    try {
      final response = await _httpClient
          .get(uri, headers: _support.requestHeaders)
          .timeout(const Duration(seconds: 15));
      sw.stop();
      _support.recordApi(
        uri,
        response.statusCode,
        sw.elapsedMilliseconds,
        success: response.statusCode == 200,
        error: response.statusCode == 200
            ? null
            : 'HTTP ${response.statusCode}',
      );
      if (response.statusCode != 200) {
        _support.recordYahooGate(
          gateKey,
          'Yahoo Finance options',
          response.statusCode,
        );
        throw StateError(
          _support.yahooHttpFailure(
            'Yahoo Finance options',
            response.statusCode,
          ),
        );
      }
      _support.clearYahooGate(gateKey);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = json['optionChain']?['result'] as List?;
      if (result == null || result.isEmpty) {
        throw StateError('no Yahoo option data for $symbol');
      }
      final root = result.first as Map<String, dynamic>;
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      final expiryRows = (root['expirationDates'] as List? ?? const [])
          .map(
            (date) => {
              'symbol': symbol.toUpperCase(),
              'expiry_date': _support.yahooDateFromUnix(date),
              'source': 'yahoo',
              'updated_at': updatedAt,
            },
          )
          .where((row) => '${row['expiry_date']}'.isNotEmpty)
          .toList();
      final options = root['options'] as List? ?? const [];
      final contractRows = <Map<String, dynamic>>[];
      for (final chain in options.whereType<Map>()) {
        final chainExpiry = _support.yahooDateFromUnix(chain['expirationDate']);
        contractRows.addAll(
          _support.optionRows(
            symbol,
            'call',
            chainExpiry,
            chain['calls'] as List? ?? const [],
            updatedAt,
          ),
        );
        contractRows.addAll(
          _support.optionRows(
            symbol,
            'put',
            chainExpiry,
            chain['puts'] as List? ?? const [],
            updatedAt,
          ),
        );
      }

      _repository.saveOptionExpiries(context, expiryRows);
      _repository.saveOptionContracts(context, contractRows);
      return {
        'action': 'yahoo_options',
        'symbol': symbol.toUpperCase(),
        'source': 'Yahoo Finance',
        'persisted': expiryRows.isNotEmpty || contractRows.isNotEmpty,
        'tables': const [
          'yfinance_option_expiries',
          'yfinance_option_contracts',
        ],
        'expiryCount': expiryRows.length,
        'contractCount': contractRows.length,
        'expiries': expiryRows,
        'contracts': contractRows.take(_support.inputLimit(input, 50)).toList(),
      };
    } catch (e) {
      if (sw.isRunning) sw.stop();
      _support.recordApi(
        uri,
        0,
        sw.elapsedMilliseconds,
        success: false,
        error: '$e',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> actions(
    String symbol,
    Map<String, dynamic> input,
    ToolContext context,
  ) async {
    final period = '${input['period'] ?? input['range'] ?? '5y'}';
    final uri = Uri.https(
      'query1.finance.yahoo.com',
      '/v8/finance/chart/$symbol',
      {'range': period, 'interval': '1d', 'events': 'div,splits,capitalGains'},
    );
    const gateKey = 'actions';
    final openGate = _support.yahooGateMessage(
      gateKey,
      'Yahoo Finance actions',
    );
    if (openGate != null) {
      _support.recordApi(uri, 0, 0, success: false, error: openGate);
      throw StateError(openGate);
    }
    final sw = Stopwatch()..start();
    try {
      final response = await _httpClient
          .get(uri, headers: _support.requestHeaders)
          .timeout(const Duration(seconds: 15));
      sw.stop();
      _support.recordApi(
        uri,
        response.statusCode,
        sw.elapsedMilliseconds,
        success: response.statusCode == 200,
        error: response.statusCode == 200
            ? null
            : 'HTTP ${response.statusCode}',
      );
      if (response.statusCode != 200) {
        _support.recordYahooGate(
          gateKey,
          'Yahoo Finance actions',
          response.statusCode,
        );
        throw StateError(
          _support.yahooHttpFailure(
            'Yahoo Finance actions',
            response.statusCode,
          ),
        );
      }
      _support.clearYahooGate(gateKey);
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final result = json['chart']?['result'] as List?;
      if (result == null || result.isEmpty) {
        throw StateError('no Yahoo corporate action data for $symbol');
      }
      final events =
          (result.first as Map<String, dynamic>)['events']
              as Map<String, dynamic>? ??
          const {};
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      final rows = <Map<String, dynamic>>[
        ..._support.corporateActionRows(
          symbol,
          'dividend',
          events['dividends'],
          updatedAt,
        ),
        ..._support.corporateActionRows(
          symbol,
          'split',
          events['splits'],
          updatedAt,
        ),
        ..._support.corporateActionRows(
          symbol,
          'capital_gains',
          events['capitalGains'] ?? events['capital_gains'],
          updatedAt,
        ),
      ];
      _repository.saveCorporateActions(context, rows);
      return {
        'action': 'yahoo_actions',
        'symbol': symbol.toUpperCase(),
        'source': 'Yahoo Finance',
        'period': period,
        'persisted': rows.isNotEmpty,
        'tables': rows.isEmpty
            ? const []
            : const ['yfinance_corporate_actions'],
        'count': rows.length,
        'data': rows,
      };
    } catch (e) {
      if (sw.isRunning) sw.stop();
      _support.recordApi(
        uri,
        0,
        sw.elapsedMilliseconds,
        success: false,
        error: '$e',
      );
      rethrow;
    }
  }

  Future<Map<String, dynamic>> earnings(
    String symbol,
    ToolContext context,
  ) async {
    final uri = Uri.parse(
      'https://query1.finance.yahoo.com/v10/finance/quoteSummary/$symbol?modules=incomeStatementHistory,balanceSheetHistory,cashflowStatementHistory,defaultKeyStatistics,financialData,summaryProfile,assetProfile,recommendationTrend,institutionOwnership,fundOwnership,majorHoldersBreakdown,insiderTransactions',
    );
    const gateKey = 'quoteSummary';
    final openGate = _support.yahooGateMessage(gateKey, 'Yahoo Finance');
    if (openGate != null) {
      _support.recordApi(uri, 0, 0, success: false, error: openGate);
      throw StateError(openGate);
    }
    final sw = Stopwatch()..start();
    try {
      final resp = await _httpClient.get(uri, headers: _support.requestHeaders);
      sw.stop();
      _support.recordApi(
        uri,
        resp.statusCode,
        sw.elapsedMilliseconds,
        success: resp.statusCode == 200,
        error: resp.statusCode == 200 ? null : 'HTTP ${resp.statusCode}',
      );
      if (resp.statusCode != 200) {
        _support.recordYahooGate(gateKey, 'Yahoo Finance', resp.statusCode);
        throw StateError(
          _support.yahooHttpFailure('Yahoo Finance', resp.statusCode),
        );
      }
      _support.clearYahooGate(gateKey);
      final json = jsonDecode(resp.body);
      final result = json['quoteSummary']?['result'] as List?;
      if (result == null || result.isEmpty) {
        throw StateError('no financial data for $symbol');
      }
      final data = result.first as Map<String, dynamic>;
      final keyStats =
          data['defaultKeyStatistics'] as Map<String, dynamic>? ?? const {};
      final financialData =
          data['financialData'] as Map<String, dynamic>? ?? const {};
      final summaryProfile =
          data['summaryProfile'] as Map<String, dynamic>? ?? const {};
      final assetProfile =
          data['assetProfile'] as Map<String, dynamic>? ?? const {};
      final income =
          data['incomeStatementHistory']?['incomeStatementHistory'] as List? ??
          const [];
      final balance =
          data['balanceSheetHistory']?['balanceSheetStatements'] as List? ??
          const [];
      final cashflow =
          data['cashflowStatementHistory']?['cashflowStatements'] as List? ??
          const [];
      final recommendations =
          data['recommendationTrend']?['trend'] as List? ?? const [];
      final institutionalHolders =
          data['institutionOwnership']?['ownershipList'] as List? ?? const [];
      final fundHolders =
          data['fundOwnership']?['ownershipList'] as List? ?? const [];
      final majorHoldersBreakdown =
          data['majorHoldersBreakdown'] as Map<String, dynamic>? ?? const {};
      final insiderTransactions =
          data['insiderTransactions']?['transactions'] as List? ?? const [];

      final updatedAt = DateTime.now().toUtc().toIso8601String();
      _repository.saveProfileFields(
        context,
        _support.profileRows(symbol, {
          ...keyStats,
          ...financialData,
          ...summaryProfile,
          ...assetProfile,
        }, updatedAt),
      );
      _repository.saveStatementItems(context, [
        ..._support.statementRows(symbol, 'income', income, updatedAt),
        ..._support.statementRows(symbol, 'balance_sheet', balance, updatedAt),
        ..._support.statementRows(symbol, 'cash_flow', cashflow, updatedAt),
      ]);
      _repository.saveRecommendations(
        context,
        _support.recommendationRows(symbol, recommendations, updatedAt),
      );
      _repository.saveHolders(context, [
        ..._support.holderRows(
          symbol,
          'institutional',
          institutionalHolders,
          updatedAt,
        ),
        ..._support.holderRows(symbol, 'fund', fundHolders, updatedAt),
        ..._support.majorHolderRows(symbol, majorHoldersBreakdown, updatedAt),
      ]);
      _repository.saveInsiderTransactions(
        context,
        _support.insiderRows(symbol, insiderTransactions, updatedAt),
      );

      final periods = income.take(4).map((stmt) {
        final s = stmt as Map<String, dynamic>;
        String val(String key) {
          final v = s[key]?['raw'];
          return v == null
              ? '—'
              : (v is num && v.abs() > 1e9
                    ? '${(v / 1e9).toStringAsFixed(2)}B'
                    : v is num && v.abs() > 1e6
                    ? '${(v / 1e6).toStringAsFixed(1)}M'
                    : '$v');
        }

        return {
          'period': s['endDate']?['fmt'] ?? '',
          'revenue': val('totalRevenue'),
          'netProfit': val('netIncome'),
          'grossProfit': val('grossProfit'),
          'operatingIncome': val('operatingIncome'),
          'eps': val('dilutedEPS'),
        };
      }).toList();

      return {
        'action': 'earnings',
        'symbol': symbol,
        'source': 'yahoo',
        'pe': keyStats['trailingPE']?['raw'],
        'pb': keyStats['priceToBook']?['raw'],
        'enterpriseValue': keyStats['enterpriseValue']?['fmt'],
        'periods': periods,
        'ingestion': {
          'persisted': true,
          'tables': [
            'yfinance_profile_fields',
            'yfinance_statement_items',
            'yfinance_recommendations',
            'yfinance_holders',
            'yfinance_insider_transactions',
          ],
        },
      };
    } catch (e) {
      if (sw.isRunning) sw.stop();
      _support.recordApi(
        uri,
        0,
        sw.elapsedMilliseconds,
        success: false,
        error: '$e',
      );
      rethrow;
    }
  }
}
