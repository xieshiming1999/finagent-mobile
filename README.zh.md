# FinAgent Mobile

本仓库同时是一个面向移动端 agent 系统的学习与研究项目。金融 workflow 是主要实验场景，用于研究移动 agent 如何在设备端结合本地上下文、受治理的数据、工具、UI surface 和人工确认，完成真实用户意图驱动的工作流。

FinAgent Mobile 是一个Flutter 移动 agent。当前主要内置领域是金融：本地市场研究、基于数据证据的分析、自选观察、仪表盘、策略复核和模拟交易工作流。

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
- 数据源应被视为受治理的 provider path，而不是匿名 fallback blob。只配置当前 workflow 实际使用的 provider。
- TDX 和 EastMoney 公开数据：实用的 A 股来源，适合 quote、K-line、sector、hot-rank、limit-pool、money-flow 和市场结构数据。传输失败和 schema 变化应进入 source-health evidence，而不是被静默 fallback 掩盖。
- 当本地网络需要时，配置可选代理。
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

中文：

- `docs/design/agent/agent-design-guide.zh.md`
- `docs/design/data-provenance/data-provenance-design-guide.zh.md`

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
