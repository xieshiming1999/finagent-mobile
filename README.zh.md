# FinAgent Mobile

本仓库同时是一个面向移动端 agent 系统的学习与研究项目。金融 workflow 是主要实验场景，用于研究移动 agent 如何在设备端结合本地上下文、受治理的数据、工具、UI surface 和人工确认，完成真实用户意图驱动的工作流。

FinAgent Mobile 是一个Flutter 移动 agent。当前主要内置领域是金融：本地市场研究、基于数据证据的分析、自选观察、仪表盘、策略复核和模拟交易工作流。

## 能力概览

- 移动 agent runtime：chat、session、memory、工具调用、WebView/dashboard 交互、审批、可恢复 workflow evidence，以及覆盖真实 UI 行为的 app-started workflow test。
- 金融数据层：受治理 quote、K-line、基金、宏观、新闻、provider health、source time 与 fetch time 分离、本地读回、cache-first reuse 和 provider failure classification。
- 市场与投资分析：市场概览、个股研究、基金研究、自选观察、宏观/新闻上下文、风险提示，以及由工具证据支撑的用户报告。
- 策略与回测：内置指标和策略、custom StrategySpec validation、backtest execution、saved strategy lifecycle、rerun evidence，以及 watchlist/monitor handoff。
- UI artifact：dashboard、生成式 WebView report、strategy view、macro evidence panel，以及解释 provider、cache、time 和 missing data 的 provenance text。
- 交易边界：支持模拟交易 workflow 和 paper evidence；真实券商执行不属于默认移动端安全边界。

## 演示

![FinAgent Mobile 仪表盘演示](docs/images/finagent-mobile.png)

## 可以询问什么

- 根据可用的本地数据或已配置的数据源，今天 A 股市场的主要驱动因素是什么，我需要关注哪些风险？
- 请使用最新可用的价格和基本面分析 600519，并说明数据来源和新鲜度。
- 请筛选盈利能力较好且估值合理的 A 股候选，并说明数据覆盖和主要风险。
- 请回测 600519 的 RSI 与成交量策略，不要保存。
- 请比较 600519 的 RSI 策略与均线策略，包括收益、回撤和数据覆盖。
- 请重新运行我已保存的 600519 策略，并说明指标为何较上次发生变化。

## 快速启动

安装 Flutter 后运行：

```bash
flutter pub get
flutter run -d macos
```

Android 设备：

```bash
flutter run -d android
```

## 运行时设置

agent 执行真实 workflow 前，需要先配置运行时设置。请通过应用设置界面或应用创建的运行时配置目录完成配置，不要把本地凭证提交进仓库。

最小模型设置包括：

- LLM provider、base URL、model 和 API key。
- 推荐默认使用具备视觉能力的模型，因为常规 agent workflow 可能需要理解 UI、截图、dashboard 或视觉证据。纯文本模型只适合不检查图像的 text-only smoke test 或纯文本 workflow。
- 当模型 provider 要求时，配置可选的 LLM HTTP user-agent header。

金融数据设置包括：

- 仅为需要使用的 provider 配置凭证。对个人研究型金融 agent 来说，最困难的通常不是 LLM 本身，而是数据：如何取得数据、验证 provider 是否返回了预期 schema、区分 source time 和 fetch time，并在再次访问外部 provider 前优先复用已验证的本地数据。
- 数据源选项，例如 Wind、Tushare、搜索 provider、雪球模拟交易、Yahoo Finance 和 TradingView。
- TDX 和 EastMoney 公开数据：实用的 A 股来源，适合 quote、K-line、sector、hot-rank、limit-pool、money-flow 和市场结构数据。传输失败和 schema 变化应进入 source-health evidence，而不是被静默 fallback 掩盖。
- Wind / AIFinMarket：如已具备 Wind AIFinMarket 访问权限，配置 `WIND_API_KEY`。它适合专业授权数据、宏观序列、文档和高级金融事实；额度、权限和失败分类应在 API health 中可见。
- Tushare：如需要支持范围内的 A 股结构化参考数据，配置从 Tushare 账户获取的 `TUSHARE_TOKEN`。部分财报或基金端点需要额外权限；没有权限或已经禁用的端点不应作为正常 workflow 暴露给 agent。
- 搜索 provider：只配置实际使用的搜索引擎。搜索结果适合研究上下文和来源发现，不应直接等同于 canonical market-data table。
- 雪球模拟交易：只为模拟交易验证配置 cookie/session。它应与真实券商执行分离，cookie 应在源码外刷新和保存。
- Yahoo Finance / yfinance-style 数据：移动端在可用时通过 Yahoo-compatible 路径取得全球 quote/history/research 数据，通常需要全局网络访问或可用代理。
- TradingView：在网络可用时作为图表和视觉增强层使用；它不是可复用数据的 canonical storage source。
- 当本地网络需要时，配置可选代理。
- 对依赖海外网站的 provider，需要全局网络访问或可用代理，尤其是 yfinance / Yahoo Finance 和 TradingView。
- 用于 session、memory、generated dashboards、local cache、provider evidence、logs 和 user-created artifacts 的运行时数据目录。

数据源对比：

| 来源组 | 最适合用途 | 主要边界 | Provenance 处理 |
|---|---|---|---|
| TDX native | A 股 quote、K-line、指数、逐笔、tick 和市场结构证据 | 公开服务器可能不可用，schema 与具体接口强相关 | 只持久化已注册 schema；保留 provider as-of time，并分类传输失败。 |
| EastMoney 公开 route | A 股/基金公开数据、板块、排名、资金流、涨跌停池和热榜 | route 和字段可能变化 | 通过代码拥有的 interface 归一化，失败证据保持可见。 |
| Wind / AIFinMarket | 授权专业数据、宏观、基本面、文档和高级金融数据 | 受 credential、quota 和 permission 约束 | 优先 cache/readback；live refresh 前展示额度和权限状态。 |
| Tushare Pro | 当前 token 有权限的 A 股结构化参考数据 | endpoint 权限随账号变化 | 禁用 unsupported endpoint，权限失败后避免反复重试。 |
| Yahoo Finance compatible route | 全球标的、跨市场上下文、history、options、actions 和 news | 需要全局网络或代理；不是 A 股主 provider | 用于全球上下文和 typed readback；不替代中国市场主数据源。 |
| 搜索和研究页面 | 叙事解释、宏观归因和来源发现 | 不自动等同于 canonical market data | 未提升为治理 schema 前，作为假设或 evidence row 使用。 |

凭证与访问方式表：

| 数据源 | 是否需要 key | 获取 / 配置位置 | 主要用途 |
|---|---|---|---|
| TDX native 公开行情 | 不需要 API key | 内置 native protocol / provider policy | A 股 quote、K-line、指数和市场结构路径；仍依赖网络和服务器可用性。 |
| EastMoney 公开数据 | 不需要 API key | 公开 EastMoney route | A 股、ETF、板块、热榜、资金流、涨跌停池等公开数据。 |
| Wind / AIFinMarket | `WIND_API_KEY` | Wind AIFinMarket / Wind 账号或门户 | 专业数据、宏观、基本面、文档和高级金融数据；受额度和权限限制。 |
| Tushare Pro | `TUSHARE_TOKEN` | Tushare 账号 -> 个人中心 -> 账号 TOKEN | A 股结构化参考数据；不同账号的 endpoint 权限不同。 |
| Yahoo Finance / yfinance-style 全球数据 | 本应用不需要 API key | 移动端 runtime 直接使用公开 Yahoo/yfinance-compatible route | 全球 quote/history/research/options/actions；通常需要全局网络或代理。 |
| TradingView 图表层 | 本应用不需要 API key | Web 访问 / embedded chart resources | 图表视觉增强，不是 canonical persisted data。 |
| Brave Search | `BRAVE_SEARCH_KEY` | Brave Search API dashboard | 研究和来源发现，不是 canonical market data。 |
| Tavily Search | `TAVILY_API_KEY` | Tavily Platform dashboard | 研究、来源发现和抽取，不是 canonical market data。 |
| FRED 宏观数据 | `FRED_API_KEY` | FRED 账号 API key 页面 | 美国官方宏观和利率序列。 |
| BLS 公开宏观数据 | 当前实现不需要 API key | BLS public API / public releases | 美国就业和通胀证据；仍受访问限制和源可用性影响。 |
| BEA 宏观数据 | `BEA_API_KEY` 或 `~/.fin_electron/bea.txt` fallback | BEA API signup | 美国国民账户和增长证据。 |
| EIA 能源数据 | `EIA_API_KEY` | EIA Open Data API registration | 能源库存和商品宏观证据。 |
| 雪球模拟交易 | `XQ_COOKIE`；可选 `XQ_PORTFOLIO` | 已登录雪球浏览器 session 和模拟组合 id/name | 只用于模拟交易验证；必须与真实券商执行分离。 |
| 公开宏观 / 研究页面 | 通常不需要 API key | 官方/公开页面；有时需要浏览器或人工验证 | 研究叙事和归因证据，直到被提升为受治理 schema。 |

服务依赖包括：

- 桌面或设备运行需要 Flutter runtime。
- 外部金融 provider 可能需要网络、凭证、额度、cookie 或 provider 账号。
- 缺少凭证应只阻断对应的受限 provider 路径；本地读回和公共数据源工作流仍应可用。

会话、仪表盘、生成报告、日志、缓存、memory、cookie 和 API key 等运行时数据应存放在仓库外部。

## 设计指南

设计指南是源码合同的一部分，并随对应代码领域出现而加入。新增或实质修改设计指南时，应在同一个源码变更 commit 中更新 `README.md` 和 `README.zh.md`，使 README 描述该历史节点的代码状态。

英文：

- `docs/design/agent/agent-design-guide.md`
- `docs/design/data-provenance/data-provenance-design-guide.md`
- `docs/design/strategy-provenance/strategy-provenance-design-guide.md`
- `docs/design/workflow-phase/workflow-phase-design-guide.md`

中文：

- `docs/design/agent/agent-design-guide.zh.md`
- `docs/design/data-provenance/data-provenance-design-guide.zh.md`
- `docs/design/strategy-provenance/strategy-provenance-design-guide.zh.md`
- `docs/design/workflow-phase/workflow-phase-design-guide.zh.md`

## 开发

本地验证：

```bash
flutter analyze
flutter test
```

如果当前快照报告继承的 lint warning，可用非 fatal analyzer pass 区分真实 analyzer error 和样式债务：

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

## 仓库结构

```text
assets/finance/ Bundled agent instructions、skills、dashboards 和 fixtures
docs/design/ 中英双语设计指南，随对应代码领域出现而加入
lib/ Flutter app、agent runtime、domain code 和 UI code
test/ Unit、widget 和 workflow-oriented regression tests
scripts/ 本地验证和维护脚本
```

## 安全边界

本项目用于研究、教育和工作流辅助，不提供投资建议。交易相关工作流必须区分模拟和真实券商路径，对外部副作用要求明确审批，并记录每个决策使用的 evidence。

不要提交 API key、cookie、token、本地代理设置、运行时 session 或生成数据。

## License

Apache License 2.0. See `LICENSE`.
