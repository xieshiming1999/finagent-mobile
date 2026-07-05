import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/reusable_data_store.dart';
import '../../../agent/tool_context.dart';
import '../providers/data_api_interface_contract.dart';
import '../providers/tradingview_market_provider.dart';

class TradingviewMarketDataService {
  final TradingviewMarketProvider _provider;

  TradingviewMarketDataService({
    TradingviewMarketProvider? provider,
    http.Client? httpClient,
  }) : _provider =
           provider ?? HttpTradingviewMarketProvider(httpClient: httpClient);

  Future<Map<String, dynamic>> scan(
    List<String> symbols,
    Map<String, dynamic> input,
    ToolContext? context,
  ) async {
    final indicators =
        (input['indicators'] as List?)?.cast<String>() ?? _kDefaultIndicators;
    final timeframe = (input['timeframe'] as String? ?? '1d').toLowerCase();
    final data = await _provider.readScan(
      symbols,
      indicators: indicators,
      timeframe: timeframe,
    );
    const contract = DataApiInterfaceContract();
    final interface = contract.getInterface('market.screening');
    if (interface == null) {
      throw StateError('market.screening data API interface is not registered');
    }
    final capability = interface.capabilities.first;
    final fetchedAt = DateTime.now().toUtc().toIso8601String();
    final rows = data
        .map(
          (row) => {
            'symbol': '${row['symbol'] ?? ''}',
            'name': row['name'],
            'market': row['market'],
            'rank': row['rank'],
            'score':
                row['score'] ?? row['composite_score'] ?? row['Recommend.All'],
            'fields': row,
          },
        )
        .toList();
    if (context != null) {
      ReusableDataStore(context.basePath).saveMarketScreeningSnapshots(
        provider: capability.provider.name,
        capabilityId: capability.id,
        sourceAction: 'scan',
        universe: symbols,
        filters: {'indicators': indicators, 'timeframe': timeframe},
        sort: const {},
        rows: rows.cast<Map<String, dynamic>>(),
        fetchedAt: fetchedAt,
        screenedAt: fetchedAt,
      );
    }
    return {
      'ok': true,
      'action': 'scan',
      'interfaceId': interface.id,
      'capabilityId': capability.id,
      'schemaId': interface.canonicalSchema,
      'status': data.isEmpty ? 'empty' : 'success',
      'failureClass': 'success',
      'provider': capability.provider.name,
      'source': 'TradingView',
      'warnings': const <String>[],
      'timeframe': timeframe,
      'count': data.length,
      'indicators': indicators,
      'universe': symbols,
      'data': data,
      'rows': rows,
      'persistencePolicy': 'persistable',
      'provenance': {
        'interfaceId': interface.id,
        'capabilityId': capability.id,
        'provider': capability.provider.name,
        'schemaId': interface.canonicalSchema,
        'canonicalTable': capability.canonicalTable,
        'persistencePolicy': 'persistable',
        'cacheStatus': context == null
            ? 'not-persisted-no-context'
            : 'provider-hit',
        'cacheDecision': context == null
            ? 'provider fetch returned screening_result rows but no ToolContext was available, so market_screening_snapshot persistence was skipped'
            : 'provider fetch returned screening_result rows and persisted them to market_screening_snapshot for same-runtime readback',
        'sourceAction': 'scan',
        'fetchedAt': fetchedAt,
      },
    };
  }
}

const _kDefaultIndicators = [
  'close',
  'open',
  'high',
  'low',
  'volume',
  'RSI',
  'MACD.macd',
  'MACD.signal',
  'BB.upper',
  'BB.lower',
  'EMA20',
  'EMA50',
  'SMA20',
  'SMA50',
  'ADX',
  'Stoch.K',
  'Stoch.D',
  'Recommend.All',
  'Recommend.MA',
  'Recommend.Other',
];
