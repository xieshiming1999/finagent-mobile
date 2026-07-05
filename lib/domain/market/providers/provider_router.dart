import '../../../agent/data_fetcher/base_fetcher.dart';
import '../../../agent/data_fetcher/models.dart';
import '../../../agent/data_fetcher/provider_policy.dart';

typedef ProviderCall<T> = Future<T> Function(BaseFetcher fetcher);
typedef ProviderIsUsable<T> = bool Function(T result);

class ProviderRouteResult<T> {
  final T data;
  final String source;

  const ProviderRouteResult({required this.data, required this.source});
}

class ProviderRouter {
  final ProviderPolicy policy;
  final ProviderGates Function() gates;
  final BaseFetcher? Function(FinanceProvider provider) fetcherForProvider;

  const ProviderRouter({
    required this.policy,
    required this.gates,
    required this.fetcherForProvider,
  });

  Future<ProviderRouteResult<T>> run<T>({
    required FinanceDataTask task,
    required ProviderCall<T> call,
    required ProviderIsUsable<T> isUsable,
    required String emptyMessage,
    required String failureMessage,
    List<FinanceProvider> preferredProviders = const <FinanceProvider>[],
  }) async {
    final errors = <String>[];
    for (final provider in policy.orderFor(
      task,
      gates: gates(),
      preferredProviders: preferredProviders,
    )) {
      final fetcher = fetcherForProvider(provider);
      if (fetcher == null) continue;
      try {
        final result = await call(fetcher);
        if (isUsable(result)) {
          return ProviderRouteResult(data: result, source: fetcher.name);
        }
        errors.add('${fetcher.name}: $emptyMessage');
      } catch (e) {
        errors.add('${fetcher.name}: $e');
        if (_shouldStop(e)) break;
      }
    }
    throw DataFetchError('$failureMessage: ${errors.join('; ')}');
  }

  bool _shouldStop(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('permission') ||
        message.contains('权限') ||
        message.contains('rate limit') ||
        message.contains('frequency') ||
        message.contains('参数') ||
        message.contains('invalid argument');
  }
}
