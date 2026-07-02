---
description: Build an auto-refreshing monitor dashboard with threshold warnings and durable background monitoring.
when_to_use: User asks for a price monitor, alert panel, auto-refreshing dashboard, or a long-running background monitor.
---

Build a visual monitor dashboard from the monitor template. For durable background monitoring, use `MonitorCreate`. Do not rely on mobile-only background page behavior.

## Template

Use `bundle/dashboards/monitor/template.html`. It already includes:
- interval polling with `setInterval`
- state indicators
- threshold checks plus automatic agent notification
- an activity log panel

## Creation flow

1. Read `bundle/dashboards/monitor/template.html`
2. Update `{{TITLE}}`, `CONFIG.monitors[]`, and `CONFIG.interval`
3. Write `memory/dashboards/<name>-monitor.html`
4. Open it with `UIControl`
5. Use `MonitorCreate` for durable monitoring logic

If you edit an already-open monitor dashboard HTML file, call `WebView(action: "refresh")` to re-read the file. For live updates, prefer Bridge or `UIControl pushData` so the page state stays intact.

## Example CONFIG

```js
var CONFIG = {
  interval: 30000,
  monitors: [
    {
      id: 'stock_600519',
      label: 'Kweichow Moutai',
      unit: 'CNY',
      apiUrl: '', // data-backed FinAgent monitors should use MonitorCreate templates, not provider URLs
      apiParams: {},
      extract: function(resp) {
        return null;
      },
      threshold: function(val, prevVal) {
        if (val == null) return { status: 'warn', message: 'No requirement-level monitor data route configured' };
        if (val > 2000) return { status: 'error', message: 'Moutai broke above 2000, now ' + val };
        if (val < 1800) return { status: 'warn', message: 'Moutai fell below 1800, now ' + val };
        return { status: 'ok' };
      }
    }
  ]
};
```

Important: FinAgent has no backend server. Do not put public provider URLs into
normal monitoring dashboards. Use `MonitorCreate` templates for data-backed
stock/fund monitors, or create a dashboard that consumes already persisted
memory/data artifacts.

## Threshold behavior

When `threshold()` returns `warn` or `error`:
1. the state indicator changes color
2. the activity log records the event
3. `Bridge.sendToAgent(message, data)` notifies the agent
4. the event agent can decide what to do next

## Background operation

Use:

```text
MonitorCreate(...)
```

Use monitor APIs to inspect and manage status rather than relying on desktop-only background-page controls.

## Common use cases

- stock-price alerts
- index-level alerts
- buy or sell target reminders
- commodity or oil-price checks

## Pre-run check

Before starting a long-running monitor, check available memory through `Environment`. If available memory is below 500MB, warn the user.

## Design rules

- dark theme `#131722`
- state colors: green, yellow, red
- avoid intervals below 10 seconds
- store files under `memory/dashboards/`
- use a `-monitor` suffix in the filename
