import '../../../agent/data_fetcher/provider_policy.dart';

enum CachePolicyMode { cacheFirst, refreshIfStale, liveOnly, cacheOnly }

class CachePolicy {
  final CachePolicyMode mode;
  final Duration quoteMaxAge;
  final int klineMinRows;

  const CachePolicy({
    this.mode = CachePolicyMode.cacheFirst,
    this.quoteMaxAge = const Duration(seconds: 15),
    this.klineMinRows = 10,
  });

  bool get shouldReadCache => mode != CachePolicyMode.liveOnly;

  bool get shouldFetchAfterMiss => mode != CachePolicyMode.cacheOnly;

  bool get shouldFetchAfterHit => mode == CachePolicyMode.refreshIfStale;

  static CachePolicy forTask(
    FinanceDataTask task, {
    CachePolicyMode? mode,
    Duration? quoteMaxAge,
    int? klineMinRows,
  }) {
    final defaults = switch (task) {
      FinanceDataTask.fund => const CachePolicy(
        mode: CachePolicyMode.refreshIfStale,
        quoteMaxAge: Duration(days: 1),
      ),
      FinanceDataTask.kline ||
      FinanceDataTask.indexKline => const CachePolicy(klineMinRows: 10),
      _ => const CachePolicy(),
    };
    return CachePolicy(
      mode: mode ?? defaults.mode,
      quoteMaxAge: quoteMaxAge ?? defaults.quoteMaxAge,
      klineMinRows: klineMinRows ?? defaults.klineMinRows,
    );
  }

  static CachePolicy fromInput(
    Map<String, dynamic> input, {
    FinanceDataTask task = FinanceDataTask.quote,
  }) {
    final raw = input['cachePolicy'] ?? input['readPreference'];
    final mode = switch (raw?.toString()) {
      'liveOnly' || 'live-only' => CachePolicyMode.liveOnly,
      'cacheOnly' || 'cache-only' => CachePolicyMode.cacheOnly,
      'refreshIfStale' || 'refresh-if-stale' => CachePolicyMode.refreshIfStale,
      _ => null,
    };
    return CachePolicy.forTask(task, mode: mode);
  }
}
