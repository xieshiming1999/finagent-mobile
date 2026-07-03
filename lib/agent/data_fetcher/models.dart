/// Standardized financial data models.
library;

class StockQuote {
  final String code;
  final String? timestamp;
  final String? fetchedAt;
  final String name;
  final double price;
  final double change;
  final double changePct;
  final double open;
  final double high;
  final double low;
  final double prevClose;
  final double volume;
  final double amount;
  final double? pe;
  final double? pb;
  final double? marketCap;
  final double? turnoverRate;
  final String source;

  StockQuote({
    required this.code,
    this.timestamp,
    this.fetchedAt,
    required this.name,
    required this.price,
    required this.change,
    required this.changePct,
    required this.open,
    required this.high,
    required this.low,
    required this.prevClose,
    required this.volume,
    required this.amount,
    this.pe,
    this.pb,
    this.marketCap,
    this.turnoverRate,
    required this.source,
  });

  Map<String, dynamic> toJson() => {
    'code': code,
    if (timestamp != null) 'timestamp': timestamp,
    if (fetchedAt != null) 'fetchedAt': fetchedAt,
    'name': name,
    'price': price,
    'change': change,
    'changePct': changePct,
    'open': open,
    'high': high,
    'low': low,
    'prevClose': prevClose,
    'volume': volume,
    'amount': amount,
    if (pe != null) 'pe': pe,
    if (pb != null) 'pb': pb,
    if (marketCap != null) 'marketCap': marketCap,
    if (turnoverRate != null) 'turnoverRate': turnoverRate,
    'source': source,
  };
}

class KlineBar {
  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double volume;
  final double amount;
  final double? changePct;
  final double? turnoverRate;

  KlineBar({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
    this.amount = 0,
    this.changePct,
    this.turnoverRate,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'open': open,
    'high': high,
    'low': low,
    'close': close,
    'volume': volume,
    'amount': amount,
    if (changePct != null) 'changePct': changePct,
    if (turnoverRate != null) 'turnoverRate': turnoverRate,
  };
}

class MoneyFlow {
  final String date;
  final double mainNetInflow;
  final double smallNetInflow;
  final double mediumNetInflow;
  final double largeNetInflow;
  final double superLargeNetInflow;
  final double? closePrice;
  final double? changePct;

  MoneyFlow({
    required this.date,
    required this.mainNetInflow,
    required this.smallNetInflow,
    required this.mediumNetInflow,
    required this.largeNetInflow,
    required this.superLargeNetInflow,
    this.closePrice,
    this.changePct,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'mainNetInflow': mainNetInflow,
    'smallNetInflow': smallNetInflow,
    'mediumNetInflow': mediumNetInflow,
    'largeNetInflow': largeNetInflow,
    'superLargeNetInflow': superLargeNetInflow,
    if (closePrice != null) 'closePrice': closePrice,
    if (changePct != null) 'changePct': changePct,
  };
}

class DataFetchError implements Exception {
  final String message;
  DataFetchError(this.message);
  @override
  String toString() => 'DataFetchError: $message';
}

// ─── ExQuote (扩展行情) Models ───

class ExStock {
  final int category;
  final String code;

  ExStock({required this.category, required this.code});

  Map<String, dynamic> toJson() => {'category': category, 'code': code};
}

class ExKlineBar {
  final String date;
  final double open;
  final double high;
  final double low;
  final double close;
  final double amount;
  final int volume;

  ExKlineBar({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.amount,
    required this.volume,
  });

  Map<String, dynamic> toJson() => {
    'date': date,
    'open': open,
    'high': high,
    'low': low,
    'close': close,
    'amount': amount,
    'volume': volume,
  };
}

class ExQuoteData {
  final int category;
  final String code;
  final String name;
  final double preClose;
  final double open;
  final double high;
  final double low;
  final double close;
  final double settlement;
  final double preSettlement;
  final int vol;
  final int openPosition;
  final int addPosition;
  final int holdPosition;
  final double amount;
  final List<ExLevel> bidLevels;
  final List<ExLevel> askLevels;

  ExQuoteData({
    required this.category,
    required this.code,
    required this.name,
    required this.preClose,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    this.settlement = 0,
    this.preSettlement = 0,
    required this.vol,
    this.openPosition = 0,
    this.addPosition = 0,
    this.holdPosition = 0,
    required this.amount,
    this.bidLevels = const [],
    this.askLevels = const [],
  });

  Map<String, dynamic> toJson() => {
    'category': category,
    'code': code,
    'name': name,
    'preClose': preClose,
    'open': open,
    'high': high,
    'low': low,
    'close': close,
    'settlement': settlement,
    'preSettlement': preSettlement,
    'vol': vol,
    'openPosition': openPosition,
    'addPosition': addPosition,
    'holdPosition': holdPosition,
    'amount': amount,
    'bid': bidLevels.map((l) => l.toJson()).toList(),
    'ask': askLevels.map((l) => l.toJson()).toList(),
  };
}

class ExLevel {
  final double price;
  final int vol;

  ExLevel({required this.price, required this.vol});

  Map<String, dynamic> toJson() => {'price': price, 'vol': vol};
}

class ExCategoryItem {
  final int category;
  final String name;
  final String abbr;

  ExCategoryItem({
    required this.category,
    required this.name,
    required this.abbr,
  });

  Map<String, dynamic> toJson() => {
    'category': category,
    'name': name,
    'abbr': abbr,
  };
}

class ExListItem {
  final int category;
  final String code;
  final String name;

  ExListItem({required this.category, required this.code, required this.name});

  Map<String, dynamic> toJson() => {
    'category': category,
    'code': code,
    'name': name,
  };
}
