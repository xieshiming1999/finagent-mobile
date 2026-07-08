---
name: finance-report
description: |
  Quarterly / monthly financial report — masthead with KPIs, revenue and
  burn charts, P&L summary table, top-line highlights, and an outlook
  paragraph. Use when the brief mentions "financial report", "Q3 report",
  "MRR review", "P&L", or "earnings report".
triggers:
  - "financial report"
  - "finance report"
  - "quarterly report"
  - "p&l"
  - "mrr review"
  - "earnings report"
  - "financial statements"
od:
  mode: prototype
  platform: desktop
  scenario: finance
  featured: 10
  preview:
    type: html
    entry: index.html
  design_system:
    requires: true
    sections: [color, typography, layout, components]
  craft:
    requires: [rtl-and-bidi]
---

# Finance Report Skill

Produce a single-screen financial report in one self-contained HTML file.

## FinAgent runtime

- Use restrained finance styling: neutral background, high-contrast text,
  tabular numbers, one accent color, and clear positive/negative colors.
- Write full reports to `memory/pages/<report-slug>.html`, then open with
  `UIControl { action: "openPage", payload: { file: "memory/pages/<report-slug>.html" } }`.
- Do not emit `<artifact>` wrappers in chat for full reports.
- When using the bundled report dashboard template for stock, fund, market,
  strategy, or data-health analysis, pass any available
  `analysis-evidence-v1` object as `analysisEvidence` in the report config.
  The template renders this as the analysis evidence section with facts,
  interpretation, gaps, confidence, source coverage, data time, fetched time,
  cache status, and readiness. Do not hide source coverage or missing evidence
  only in prose.
- When macro context is relevant, pass governed factor rows as `macroFactors`
  or `macroFactorEvidence` in the same report config. Each row should come from
  `MarketData(action:"query_macro_factors", ...)` and preserve source name,
  source published time, fetched time, affected assets/regions/sectors,
  transmission channels, status, and confidence. Keep this section separate
  from technical, fundamental, strategy, or trade-action evidence.

## Workflow

1. **Set styling directly.** Tables, KPI cards, and chart strokes use
   restrained finance styling: neutral surfaces, one accent color, and clear
   positive/negative colors.
2. **Classify** the period (monthly / quarterly / yearly) and entity
   (company, fund, portfolio, division, or project) from the brief. If key
   facts are missing, ask, retrieve them with available tools, or clearly label
   values as `Sample` / `Assumption`; do not present invented numbers as facts.
3. **Layout** the page in this order:
   - Masthead: company / period / "Confidential — Finance" badge.
   - Headline KPI strip (4 cards): Revenue, Net new MRR, Gross margin, Cash runway.
   - Revenue trend chart (inline SVG line + area).
   - Cost breakdown chart (inline SVG bar) with a 2–3 bullet caption.
   - P&L summary table (Revenue / Gross profit / Opex / Net) with current vs prior period.
   - Top accounts table with logo placeholders, plan, ARR, status badge.
   - Outlook paragraph + footer with author + signature line.
4. **Write** one self-contained HTML doc (CSS in one inline `<style>` block).
5. **Self-check**: every number ties to a source, labelled assumption, or
   sample-data marker; deltas show direction and percentage; accent colour used
   at most twice.

## Output contract

Write the full HTML to `memory/pages/<report-slug>.html`, call UIControl
`openPage`, then summarize the report in one sentence.
