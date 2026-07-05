class MarketIndexDefinition {
  final String code;
  final String name;
  final String market;
  final String interfaceId;
  final bool unambiguousBareCode;

  const MarketIndexDefinition({
    required this.code,
    required this.name,
    required this.market,
    this.interfaceId = 'index.quote',
    this.unambiguousBareCode = false,
  });
}

const coreCnMarketIndexes = <MarketIndexDefinition>[
  MarketIndexDefinition(code: '000001', name: '上证指数', market: 'SH'),
  MarketIndexDefinition(
    code: '399001',
    name: '深证成指',
    market: 'SZ',
    unambiguousBareCode: true,
  ),
  MarketIndexDefinition(
    code: '399006',
    name: '创业板指',
    market: 'SZ',
    unambiguousBareCode: true,
  ),
  MarketIndexDefinition(code: '000300', name: '沪深300', market: 'CSI'),
  MarketIndexDefinition(code: '000905', name: '中证500', market: 'CSI'),
  MarketIndexDefinition(code: '000852', name: '中证1000', market: 'CSI'),
  MarketIndexDefinition(code: '000688', name: '科创50', market: 'SH'),
  MarketIndexDefinition(code: '000016', name: '上证50', market: 'SH'),
  MarketIndexDefinition(
    code: '399005',
    name: '中小板指',
    market: 'SZ',
    unambiguousBareCode: true,
  ),
];

final coreCnMarketIndexCodes = List<String>.unmodifiable(
  coreCnMarketIndexes.map((index) => index.code),
);

final coreCnMarketIndexCodeSet = Set<String>.unmodifiable(
  coreCnMarketIndexes.map((index) => index.code),
);

final coreCnMarketIndexNameByCode = Map<String, String>.unmodifiable({
  for (final index in coreCnMarketIndexes) index.code: index.name,
});

final coreCnMarketIndexMarketByCode = Map<String, String>.unmodifiable({
  for (final index in coreCnMarketIndexes) index.code: index.market,
});

final unambiguousCoreCnMarketIndexCodes = Set<String>.unmodifiable(
  coreCnMarketIndexes
      .where((index) => index.unambiguousBareCode)
      .map((index) => index.code),
);

String coreCnMarketIndexDisplayName(String code) {
  return coreCnMarketIndexNameByCode[code] ?? code;
}

String coreCnMarketIndexQualifiedSymbol(String code) {
  final market = coreCnMarketIndexMarketByCode[code];
  if (market == 'SZ') return 'SZ$code';
  if (market == 'SH' || market == 'CSI') return 'SH$code';
  return code;
}

bool coreCnMarketIndexHasPlausiblePrice(String code, num price) {
  if (!coreCnMarketIndexCodeSet.contains(code)) return true;
  return price > 100 && price < 100000;
}
