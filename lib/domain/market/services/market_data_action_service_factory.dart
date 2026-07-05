import 'package:http/http.dart' as http;

import '../../../agent/data_fetcher/data_manager.dart';
import '../../../agent/data_fetcher/eastmoney_advanced_fetcher.dart';
import '../providers/data_api_interface_router.dart';
import 'backtest_market_data_service.dart';
import 'eastmoney_advanced_service.dart';
import 'eastmoney_market_data_service.dart';
import 'earnings_market_data_service.dart';
import 'extdx_market_data_service.dart';
import 'market_data_action_service.dart';
import 'market_data_backtest_action_service.dart';
import 'market_data_market_action_service.dart';
import 'market_data_query_action_service.dart';
import 'market_data_resolve_service.dart';
import 'market_data_tdx_action_service.dart';
import 'market_data_tushare_action_service.dart';
import 'margin_trading_market_data_service.dart';
import 'tdx_market_data_service.dart';
import 'tradingview_market_data_service.dart';
import 'yahoo_market_data_service.dart';

class MarketDataActionServiceFactory {
  static MarketDataActionService create({
    required DataManager dataManager,
    required http.Client httpClient,
    required EastMoneyAdvancedFetcher advancedFetcher,
  }) {
    final router = DataApiInterfaceRouter(
      runtimeBasePathProvider: () => dataManager.basePath,
    );
    return MarketDataActionService(
      dataManager: dataManager,
      query: MarketDataQueryActionService(dataManager: dataManager),
      market: MarketDataMarketActionService(
        dataManager: dataManager,
        resolveService: MarketDataResolveService(dataManager: dataManager),
        eastmoneyAdvanced: EastmoneyAdvancedService(
          dataManager: dataManager,
          fetcher: advancedFetcher,
          router: router,
        ),
        eastmoney: EastmoneyMarketDataService(dataManager: dataManager),
        earnings: EarningsMarketDataService(
          dataManager: dataManager,
          httpClient: httpClient,
        ),
        marginTrading: MarginTradingMarketDataService(
          dataManager: dataManager,
          httpClient: httpClient,
        ),
        tradingview: TradingviewMarketDataService(httpClient: httpClient),
        yahoo: YahooMarketDataService(
          dataManager: dataManager,
          httpClient: httpClient,
          router: router,
        ),
      ),
      tdx: MarketDataTdxActionService(
        dataManager: dataManager,
        tdx: TdxMarketDataService(dataManager: dataManager),
        exTdx: ExTdxMarketDataService(dataManager: dataManager),
        router: router,
      ),
      backtest: MarketDataBacktestActionService(
        dataManager: dataManager,
        backtest: BacktestMarketDataService(
          dataManager: dataManager,
          yahooMarketDataService: YahooMarketDataService(
            dataManager: dataManager,
            httpClient: httpClient,
            router: router,
          ),
        ),
      ),
      tushare: MarketDataTushareActionService(dataManager: dataManager),
    );
  }
}
