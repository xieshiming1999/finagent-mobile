# Output-Only API Interfaces

Generated from the code-owned shared_mobile_finagent finance output-only API contract. Use this table for useful non-persisted workflows and diagnostics.

Contract version: 2026-06-18

| Interface | Schema | Unknown schema policy | Providers by priority | Normalizers |
|---|---|---|---|---|
| `market.optimize_params` | `strategy_parameter_optimization_result` 2026-06-27 | reject-normal-workflow | 1. local:normalized-output-only | `code-owned backtest optimizer over governed K-line evidence; returns bounded bestParams/bestResult/results and overfit note` |
| `provider.diagnostic` | `provider_diagnostic_result` 2026-06-18 | reject-normal-workflow | 1. sina:not-supported<br>2. tencent:not-supported | `mobile normal workflow uses governed MarketData interfaces or runtime_probe; no generic raw diagnostic executor`<br>`mobile normal workflow uses governed MarketData interfaces or runtime_probe; no generic raw diagnostic executor` |
| `provider.reference_dataset` | `provider_reference_dataset_result` 2026-06-23 | reject-normal-workflow | 1. akshare:not-supported | `desktop Python sidecar reference envelope only` |
| `market.intraday_ohlcv_bars` | `intraday_ohlcv_bar_result` 2026-06-23 | reject-normal-workflow | 1. sina:supported | `normalizeSinaIntradayOhlcvBars` |
| `stock.transaction_count` | `stock_transaction_count_result` 2026-06-23 | reject-normal-workflow | 1. sina:supported | `normalizeSinaStockTransactionCount` |
| `fund.dividend_factor` | `fund_dividend_factor_result` 2026-06-23 | reject-normal-workflow | 1. sina:supported | `normalizeSinaFundDividendFactor` |
| `fund.etf_daily_ohlcv_bars` | `fund_etf_daily_ohlcv_bar_result` 2026-06-23 | reject-normal-workflow | 1. sina:not-supported<br>2. akshare:not-supported<br>3. tencent:not-supported | `native decoder not implemented`<br>`desktop Python sidecar decoder only`<br>`Electron direct Tencent output-only route only; mobile native adapter not implemented` |
| `market.classification_nodes` | `market_classification_node_result` 2026-06-23 | reject-normal-workflow | 1. sina:supported | `normalizeSinaClassificationNodes` |
| `stock.esg_rating_multi_agency` | `stock_esg_rating_multi_agency_result` 2026-06-23 | reject-normal-workflow | 1. sina:supported | `normalizeSinaEsgRatePage` |

Provider parameters are routing constraints. They do not bypass the interface, normalizer, failure classification, provenance, or non-persistence policy.

Output-only means known schema with no canonical reusable table. Unknown provider output must be rejected, routed through a bounded diagnostic envelope, or fail an audit/probe until a code-owned interface/normalizer is added.

## Knowledge Records

| API | Interface | Provider | Endpoint/action | Required params | Optional params | Response fields | Retry / recovery |
|---|---|---|---|---|---|---|---|
| `sina.provider_diagnostic` | `provider.diagnostic` | sina | `Sina finance provider diagnostic` | `endpoint` | `code`, `params` | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.sampleRows`, `row.sampleColumns` | Mobile does not expose generic Sina provider diagnostics; use governed MarketData interfaces, runtime_probe, or explicit WebFetch diagnostics outside normal data workflow. |
| `tencent.provider_diagnostic` | `provider.diagnostic` | tencent | `Tencent finance provider diagnostic` | `endpoint` | `code`, `params` | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.sampleRows`, `row.sampleColumns` | Mobile does not expose generic Tencent provider diagnostics; use governed MarketData interfaces, runtime_probe, or explicit WebFetch diagnostics outside normal data workflow. |
| `akshare.sina.reference_dataset` | `provider.reference_dataset` | akshare | `akshare/*_sina` | `functionName` | `params`, `limit` | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.functionName`, `row.rowCount`, `row.sampleColumns`, `row.sampleRows` | Use only as bounded known-schema evidence; promote only after a requirement-level interface, normalizer, storage, readback, and tests exist. |
| `sina.intraday_ohlcv_bars` | `market.intraday_ohlcv_bars` | sina | `CN_MarketData.getKLineData?scale=5` | `symbol` | `scale`, `datalen` | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.time`, `row.open`, `row.high`, `row.low`, `row.close`, `row.volume` | Normal workflow uses governed market.intraday_ohlcv_bars via sina_intraday_ohlcv_bars and query_intraday_ohlcv_bars; use this envelope only for bounded diagnostics. |
| `sina.stock_transaction_count` | `stock.transaction_count` | sina | `CN_Bill.GetBillListCount` | `symbol` | `date`, `pageSize` | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.symbol`, `row.date`, `row.count`, `row.pageSize`, `row.estimatedPages` | Use only as bounded pagination evidence for stock.transactions; do not persist as transaction rows. |
| `sina.fund_dividend_factor` | `fund.dividend_factor` | sina | `FundPage fundEtfFactorInfoService` | `symbol` | `limit` | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.date`, `row.dividend`, `row.factor` | Normal workflow uses governed fund.dividend_factor via fund_dividend_factor refresh and query_fund_dividend_factor readback; use this envelope only for bounded diagnostics. |
| `sina.stock_classify_nodes` | `market.classification_nodes` | sina | `Market_Center.getHQNodes` | - | - | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.name`, `row.code`, `row.parent` | Use only as bounded classification evidence; broad per-node expansion must be a deliberate batch workflow. |
| `sina.stock_esg_rate_page` | `stock.esg_rating_multi_agency` | sina | `EsgService.getEsgStocks?page=1&num=<bounded>` | - | `page`, `limit` | `ok`, `action`, `interfaceId`, `schemaId`, `data`, `provenance`, `row.symbol`, `row.market`, `row.agency`, `row.agencyName`, `row.esgScore`, `row.esgDate`, `row.remark` | Use bounded pages for evidence; full ESG collection is a batch job and should not be a normal lightweight probe. |
