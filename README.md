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

- Provider credentials only for providers you intend to use. A personal research finance agent usually fails first on data access, not on the LLM: the hard work is retrieving data, proving the provider returned the expected schema, preserving source time separately from fetch time, and reusing verified local rows before spending another external call.
- Data source options should be treated as governed provider paths, not anonymous fallback blobs. Configure only the providers used by your workflow.
- TDX and EastMoney public data: practical A-share sources for quote, K-line, sector, hot-rank, limit-pool, money-flow, and related market structure data. Treat transport failures and provider schema changes as source-health evidence, not silent fallbacks.
- Wind / AIFinMarket: configure `WIND_API_KEY` only if you have access from Wind AIFinMarket. Use it for licensed professional data, macro series, documents, and advanced finance facts; quota and permission limits are provider-owned and should be visible in API health.
- Tushare: configure `TUSHARE_TOKEN` from a Tushare account when you need supported A-share reference data. Some statement/fund endpoints require extra permissions; unsupported or permission-gated endpoints should stay disabled instead of being advertised as normal workflows.
- Optional local proxy settings when your network requires them.
- Runtime data directory for sessions, memory, generated dashboards, local cache, provider evidence, logs, and user-created artifacts.

Data-source comparison:

| Source group | Best use | Main boundary | Provenance treatment |
|---|---|---|---|
| TDX native | A-share quote, K-line, index, transactions, tick, and market-structure evidence | Public servers can be unavailable or schema-specific | Persist only registered schemas; preserve provider as-of time and classify transport failures. |
| EastMoney public routes | A-share/fund public data, sectors, rankings, money flow, limit pools, and hot lists | Route and field names can drift | Normalize through code-owned interfaces and keep failure evidence visible. |
| Wind / AIFinMarket | Licensed professional, macro, fundamental, document, and advanced finance data | Credential, quota, and permission gated | Prefer cache/readback first; expose quota and permission status before live refresh. |
| Tushare Pro | Structured A-share reference data when the token has permission | Endpoint permissions vary by account | Disable unsupported endpoints and avoid retry loops after permission failure. |
| Yahoo Finance compatible routes | Global instruments, cross-market context, history, options, actions, and news | Needs global web access or proxy; not an A-share primary source | Use for global context and typed readbacks; do not replace primary China-market providers. |
| Search and research pages | Narrative explanation, macro attribution, and source discovery | Not automatically canonical market data | Treat as hypothesis/evidence rows unless promoted to a governed schema. |

Credential and access matrix:

| Data source | Key required | Where to get / configure | Main use |
|---|---|---|---|
| TDX native public market data | No API key | Bundled native protocol/provider policy | A-share quote, K-line, index and market-structure paths; network/server availability still matters. |
| EastMoney public data | No API key | Public EastMoney routes | A-share, ETF, sector, hot-rank, flow, limit-pool and related public data. |
| Wind / AIFinMarket | `WIND_API_KEY` | Wind AIFinMarket / Wind account or portal | Professional, macro, fundamental, document and advanced finance data; quota and permission gated. |
| Tushare Pro | `TUSHARE_TOKEN` | Tushare account -> personal center -> account token | Structured A-share reference data; endpoint permissions vary by account. |

Service dependencies:

- Flutter runtime for desktop or device execution.
- External finance providers may require network access, credentials, quota, cookies, or provider accounts.
- Missing credentials should block only the credentialed provider path; local readback and public-source workflows should remain usable.

Runtime data such as sessions, dashboards, generated reports, logs, cache, memory, cookies, and API keys belongs outside this repository.

## Design Guides

Design guides are part of the source contract. They are added as the corresponding code domains appear. When a design guide is added or materially changed, update both `README.md` and `README.zh.md` in the same source-change commit so the README describes the code at that point in history.

English:

- `docs/design/agent/agent-design-guide.md`
- `docs/design/data-provenance/data-provenance-design-guide.md`
- `docs/design/workflow-phase/workflow-phase-design-guide.md`

Chinese:

- `docs/design/agent/agent-design-guide.zh.md`
- `docs/design/data-provenance/data-provenance-design-guide.zh.md`
- `docs/design/workflow-phase/workflow-phase-design-guide.zh.md`

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
