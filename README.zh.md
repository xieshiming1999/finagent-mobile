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

- 仅为需要使用的 provider 配置凭证。
- 数据源选项，例如 Wind、Tushare、搜索 provider、雪球模拟交易、yfinance / Yahoo Finance 和 TradingView。
- 当本地网络需要时，配置可选代理。
- 对依赖海外网站的 provider，需要全局网络访问或可用代理，尤其是 yfinance / Yahoo Finance 和 TradingView。
- 用于 session、memory、generated dashboards、local cache、provider evidence、logs 和 user-created artifacts 的运行时数据目录。

服务依赖包括：

- 桌面或设备运行需要 Flutter runtime。
- 外部金融 provider 可能需要网络、凭证、额度、cookie 或 provider 账号。
- 缺少凭证应只阻断对应的受限 provider 路径；本地读回和公共数据源工作流仍应可用。

会话、仪表盘、生成报告、日志、缓存、memory、cookie 和 API key 等运行时数据应存放在仓库外部。

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
