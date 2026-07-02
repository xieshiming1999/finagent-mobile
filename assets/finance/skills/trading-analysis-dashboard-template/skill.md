---
name: trading-analysis-dashboard-template
description: |
  Professional trading analysis dashboard template (single-file HTML) with
  light/dark theme switch, dense market panels, chart interactions, demo/live
  playback, and command palette behavior.
  Use when users ask for a Wall-Street-style analytics terminal, trading cockpit,
  or high-tech financial dashboard template with realistic data layout.
triggers:
  - "trading analysis dashboard template"
  - "wall street dashboard template"
  - "financial terminal template"
  - "trading cockpit template"
  - "analytics terminal template"
  - "wall street style board"
  - "high-tech finance dashboard template"
od:
  mode: template
  platform: desktop
  scenario: live-artifacts
  preview:
    type: html
    entry: index.html
    reload: debounce-100
  design_system:
    requires: true
    sections: [color, typography, layout, components]
  outputs:
    primary: memory/pages/<dashboard-slug>.html
  capabilities_required:
    - file_write
---

# Trading Analysis Dashboard Template

Produce a premium, data-dense, Wall-Street style trading dashboard as a self-contained HTML artifact.

## FinAgent runtime

The Skill tool does not change the current directory. Use these full paths:

- Template: `bundle/skills/trading-analysis-dashboard-template/assets/template.html`
- Checklist: `bundle/skills/trading-analysis-dashboard-template/references/checklist.md`

Write the finished dashboard to `memory/pages/<dashboard-slug>.html`, then
open it with
`UIControl { action: "openPage", payload: { file: "memory/pages/<dashboard-slug>.html" } }`.
When iterating on an already-open dashboard file, call
`WebView { action: "refresh" }` after writing the file so the WebView reloads
the file from disk. Use `WebView { action: "query" }` or page JS for runtime
display tweaks that should preserve page state; `reload` is only native browser
reload.
Do not write `index.html` at the base path and do not emit `<artifact>`
wrappers in chat.

Use restrained finance styling: neutral background, high-contrast text,
tabular numbers, one accent color, and clear positive/negative colors.

## Resource map

```text
trading-analysis-dashboard-template/
├── skill.md
├── assets/
│   └── template.html
├── references/
│   └── checklist.md
```

## Workflow

1. Map typography/color/layout into CSS variables using restrained finance styling.
2. Use `bundle/skills/trading-analysis-dashboard-template/assets/template.html`
   as the seed and write the finished page to `memory/pages/<dashboard-slug>.html`.
3. Personalize headings, instrument names, and numeric labels to the user brief.
4. Preserve interaction fidelity:
   - Light/Dark mode switch
   - Live/Demo mode
   - Chart hover crosshair and tooltip
   - Click-to-focus chart (floating modal style)
   - Keyboard command palette (`/`)
5. Keep output single-file HTML (inline CSS + inline JS, no framework dependency).
6. Keep placeholders honest (`—` or neutral labels) where real numbers are unknown.
7. Validate against `bundle/skills/trading-analysis-dashboard-template/references/checklist.md` before opening.

## Output contract

Write the full HTML to `memory/pages/<dashboard-slug>.html`, call UIControl
`openPage` for first display, or WebView `refresh` after edits to an already-open
file, then summarize the dashboard in one sentence.
