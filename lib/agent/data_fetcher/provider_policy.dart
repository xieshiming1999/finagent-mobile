enum FinanceDataTask {
  quote,
  indexQuote,
  kline,
  indexKline,
  intradayTick,
  sector,
  limitPool,
  dragonTiger,
  fundamental,
  macro,
  fund,
  moneyFlow,
}

enum FinanceProvider {
  local,
  tdx,
  eastmoneyDirect,
  akshare,
  wind,
  tushare,
  sina,
  tencent,
  yfinance,
  szse,
  tradingview,
}

class ProviderGates {
  final bool windConfigured;
  final bool windQuotaAvailable;
  final bool tushareConfigured;
  final bool tusharePermissionLikely;
  final bool allowAkshareCompatibility;
  final bool allowBroadAkshare;
  final Set<FinanceProvider> temporarilyBlockedProviders;

  const ProviderGates({
    this.windConfigured = false,
    this.windQuotaAvailable = true,
    this.tushareConfigured = false,
    this.tusharePermissionLikely = true,
    this.allowAkshareCompatibility = false,
    this.allowBroadAkshare = false,
    this.temporarilyBlockedProviders = const <FinanceProvider>{},
  });

  bool get windAvailable => windConfigured && windQuotaAvailable;
  bool get tushareAvailable => tushareConfigured && tusharePermissionLikely;
}

class ProviderPolicy {
  const ProviderPolicy();

  static const _orders = <FinanceDataTask, List<FinanceProvider>>{
    FinanceDataTask.quote: [
      FinanceProvider.tdx,
      FinanceProvider.eastmoneyDirect,
      FinanceProvider.sina,
      FinanceProvider.tencent,
    ],
    FinanceDataTask.indexQuote: [
      FinanceProvider.tdx,
      FinanceProvider.eastmoneyDirect,
      FinanceProvider.akshare,
    ],
    FinanceDataTask.kline: [
      FinanceProvider.tdx,
      FinanceProvider.eastmoneyDirect,
    ],
    FinanceDataTask.indexKline: [
      FinanceProvider.tdx,
      FinanceProvider.eastmoneyDirect,
    ],
    FinanceDataTask.intradayTick: [FinanceProvider.tdx],
    FinanceDataTask.sector: [
      FinanceProvider.eastmoneyDirect,
      FinanceProvider.akshare,
      FinanceProvider.tdx,
    ],
    FinanceDataTask.limitPool: [
      FinanceProvider.eastmoneyDirect,
      FinanceProvider.akshare,
    ],
    FinanceDataTask.dragonTiger: [FinanceProvider.eastmoneyDirect],
    FinanceDataTask.fundamental: [
      FinanceProvider.wind,
      FinanceProvider.tushare,
      FinanceProvider.eastmoneyDirect,
      FinanceProvider.tdx,
    ],
    FinanceDataTask.macro: [
      FinanceProvider.wind,
      FinanceProvider.tushare,
      FinanceProvider.akshare,
    ],
    FinanceDataTask.fund: [
      FinanceProvider.eastmoneyDirect,
      FinanceProvider.akshare,
      FinanceProvider.wind,
    ],
    FinanceDataTask.moneyFlow: [
      FinanceProvider.eastmoneyDirect,
      FinanceProvider.akshare,
      FinanceProvider.wind,
    ],
  };

  List<FinanceProvider> orderFor(
    FinanceDataTask task, {
    ProviderGates gates = const ProviderGates(),
    List<FinanceProvider> preferredProviders = const <FinanceProvider>[],
  }) {
    final base = _orders[task] ?? const <FinanceProvider>[];
    final allowed = base
        .where((provider) {
          if (gates.temporarilyBlockedProviders.contains(provider)) {
            return false;
          }
          if (provider == FinanceProvider.wind) return gates.windAvailable;
          if (provider == FinanceProvider.tushare) {
            return gates.tushareAvailable;
          }
          if (provider == FinanceProvider.akshare) {
            return gates.allowAkshareCompatibility;
          }
          return true;
        })
        .toList(growable: false);
    if (preferredProviders.isEmpty) return allowed;

    final preferred = preferredProviders
        .where((provider) => allowed.contains(provider))
        .toList(growable: false);
    return preferred.isNotEmpty ? preferred : allowed;
  }

  List<FinanceProvider> normalizeProviders(Object? value) {
    final raw = switch (value) {
      final List<Object?> list => list.map((item) => item.toString()),
      final String text => _parseProviderString(text),
      _ => const Iterable<String>.empty(),
    };
    final providers = <FinanceProvider>[];
    final seen = <FinanceProvider>{};
    for (final item in raw) {
      final provider = _normalizeProviderName(item);
      if (provider == null || seen.contains(provider)) continue;
      seen.add(provider);
      providers.add(provider);
    }
    return providers;
  }

  bool requiresSerialCalls(FinanceProvider provider) {
    return provider == FinanceProvider.akshare ||
        provider == FinanceProvider.eastmoneyDirect ||
        provider == FinanceProvider.sina ||
        provider == FinanceProvider.tencent ||
        provider == FinanceProvider.wind ||
        provider == FinanceProvider.tushare ||
        provider == FinanceProvider.szse ||
        provider == FinanceProvider.tradingview;
  }

  bool isBroadAkshareAllowed(ProviderGates gates) => gates.allowBroadAkshare;

  Iterable<String> _parseProviderString(String value) {
    final text = value.trim();
    if (text.isEmpty) return const [];
    return text
        .split(RegExp(r'(?:->|→|,|\s+)'))
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty);
  }

  FinanceProvider? _normalizeProviderName(String value) {
    switch (value.trim().toLowerCase()) {
      case 'local':
        return FinanceProvider.local;
      case 'tdx':
        return FinanceProvider.tdx;
      case 'eastmoney':
      case 'eastmoneydirect':
      case 'eastmoney_direct':
        return FinanceProvider.eastmoneyDirect;
      case 'akshare':
        return FinanceProvider.akshare;
      case 'wind':
        return FinanceProvider.wind;
      case 'tushare':
        return FinanceProvider.tushare;
      case 'sina':
        return FinanceProvider.sina;
      case 'tencent':
        return FinanceProvider.tencent;
      case 'yahoo':
      case 'yfinance':
        return FinanceProvider.yfinance;
      case 'szse':
        return FinanceProvider.szse;
      case 'tradingview':
        return FinanceProvider.tradingview;
      default:
        return null;
    }
  }
}
