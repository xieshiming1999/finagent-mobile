# FinAgent Mobile

This repository is also a study and research project on agent systems running on mobile devices. The finance workflows are the main testbed for exploring how a mobile agent can use local context, governed data, tools, UI surfaces, and human approval to complete real user workflows on-device.

FinAgent Mobile is a Flutter mobile agent. Its primary bundled domain is finance: local market research, data-backed analysis, watchlists, dashboards, strategy review, and simulated-trading workflows.

## Quick Start

Install Flutter, then run:

```bash
flutter pub get
flutter run -d macos
```

For Android:

```bash
flutter run -d android
```

## Runtime Settings

The app needs runtime settings before the agent can run real workflows. Configure them in the app settings UI or in the runtime configuration directory created by the app. Do not commit local credentials.

Minimum model settings:

- LLM provider, base URL, model, and API key.
- Recommended default: a vision-capable model for normal agent workflows, because UI/screenshot/dashboard and visual evidence workflows may need image understanding. Use a text-only model only for text-only smoke tests or workflows that do not inspect images.
- Optional LLM HTTP user-agent header when the selected provider requires one.

Finance data settings:

- Provider credentials only for providers you intend to use.
- Data source options such as Wind, Tushare, search providers, Xueqiu simulated trading, yfinance/Yahoo Finance, and TradingView.
- Optional local proxy settings when your network requires them.
- Global web access or a working proxy for providers that depend on overseas web services, especially yfinance/Yahoo Finance and TradingView.
- Runtime data directory for sessions, memory, generated dashboards, local cache, provider evidence, logs, and user-created artifacts.

Service dependencies:

- Flutter runtime for desktop or device execution.
- External finance providers may require network access, credentials, quota, cookies, or provider accounts.
- Missing credentials should block only the credentialed provider path; local readback and public-source workflows should remain usable.

Runtime data such as sessions, dashboards, generated reports, logs, cache, memory, cookies, and API keys belongs outside this repository.

## Design Guides

Design guides are part of the source contract. They are added as the corresponding code domains appear. When a design guide is added or materially changed, update both `README.md` and `README.zh.md` in the same source-change commit so the README describes the code at that point in history.

English:

- `docs/design/agent/agent-design-guide.md`

Chinese:

- `docs/design/agent/agent-design-guide.zh.md`

## Development

Validate locally:

```bash
flutter analyze
flutter test
```

If this snapshot reports inherited lint warnings, use a non-fatal analyzer pass to separate real analyzer errors from style debt:

```bash
flutter analyze --no-fatal-infos --no-fatal-warnings
```

## Repository Layout

```text
assets/finance/ Bundled agent instructions, skills, dashboards, and fixtures
docs/design/ Bilingual design guides, added as the related code domains appear
lib/ Flutter app, agent runtime, domain code, and UI code
test/ Unit, widget, and workflow-oriented regression tests
scripts/ Developer scripts for local validation and maintenance
```

## Safety Boundary

This project is for research, education, and workflow assistance. It does not provide investment advice. Trading-related workflows must keep simulated and real broker paths separate, require explicit approval for side effects, and record the evidence used for each decision.

Do not commit API keys, cookies, tokens, local proxy settings, runtime sessions, or generated data into this repository.

## License

Apache License 2.0. See `LICENSE`.
