part of 'data_manager.dart';

extension DataManagerStatus on DataManager {
  T? getFetcher<T extends BaseFetcher>() {
    if (_exTdxFetcher is T) return _exTdxFetcher as T;
    for (final f in _registeredFetchers) {
      if (f is T) return f;
    }
    return null;
  }

  BaseFetcher? getFetcherByName(String name) {
    final lower = name.toLowerCase();
    for (final f in _registeredFetchers) {
      if (f.name.toLowerCase().contains(lower)) return f;
      if (lower == 'eastmoney' && f is EastMoneyFetcher) return f;
      if (lower == 'tdx' && f is TdxFetcher) return f;
      if (lower == 'sina' && f is SinaFetcher) return f;
      if (lower == 'tencent' && f is TencentFetcher) return f;
      if (lower == 'tushare' && f is TushareFetcher) return f;
    }
    return null;
  }

  List<String> get sourceNames =>
      _registeredFetchers.map((f) => f.name).toList();

  List<String> policySourceNames(FinanceDataTask task) {
    return _policy
        .orderFor(task, gates: _gates)
        .map(_providerLabel)
        .toList(growable: false);
  }

  Map<String, dynamic> getSourceStatus() {
    final status = <String, dynamic>{};
    for (final f in _registeredFetchers) {
      final cb = f is EastMoneyFetcher
          ? f.circuitBreaker
          : f is TdxFetcher
          ? f.circuitBreaker
          : f is TushareFetcher
          ? f.circuitBreaker
          : f is SinaFetcher
          ? f.circuitBreaker
          : f is TencentFetcher
          ? f.circuitBreaker
          : null;
      status[f.name] = {
        'priority': f.priority,
        'circuit': cb?.statusMap[f.name] ?? 'closed',
      };
    }
    status['cache'] = {
      'kline': {
        'entries': _klineCache.length,
        'hits': _klineCache.hitCount,
        'misses': _klineCache.missCount,
      },
      'flow': {
        'entries': _flowCache.length,
        'hits': _flowCache.hitCount,
        'misses': _flowCache.missCount,
      },
    };
    status[_exTdxFetcher.name] = {
      'priority': _exTdxFetcher.priority,
      'circuit':
          _exTdxFetcher.circuitBreaker.statusMap[_exTdxFetcher.name] ??
          'closed',
    };
    status['provider_policy'] = {
      'quote': policySourceNames(FinanceDataTask.quote),
      'kline': policySourceNames(FinanceDataTask.kline),
      'index_kline': policySourceNames(FinanceDataTask.indexKline),
      'money_flow': policySourceNames(FinanceDataTask.moneyFlow),
      'fundamental': policySourceNames(FinanceDataTask.fundamental),
    };
    status['storage_policy'] = {
      'quote': 'cacheFirst, refreshIfStale, liveOnly, cacheOnly',
      'kline': 'cacheFirst, refreshIfStale, liveOnly, cacheOnly',
      'note':
          'Reusable local storage is read before provider routing by resolve services; it is not a FinanceProvider.',
    };
    return status;
  }
}
