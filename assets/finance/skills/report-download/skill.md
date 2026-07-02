---
description: Download A-share or Hong Kong listed-company report PDFs by searching Xueqiu or Tonghuashun notice links, then saving the file locally.
when_to_use: User asks to download a financial report, annual report PDF, interim report, quarterly report, or wants a local copy of a company filing.
---

# Financial Report PDF Download

## Step 0: Parse the request

Extract:
- `stock_code` as required
- `year` as optional, defaulting to the latest likely report
- `report_type` as optional, defaulting to annual report

### Market identification

| Pattern | Market | Formatting | Example |
|---|---|---|---|
| 6 digits starting with `6` | Shanghai A-share | prefix `SH` | `600887` -> `SH600887` |
| 6 digits starting with `0` or `3` | Shenzhen A-share | prefix `SZ` | `300750` -> `SZ300750` |
| 1 to 5 digits | Hong Kong | pad to 5 digits | `700` -> `00700` |

### Report types

| Input | Search keyword | Typical release window |
|---|---|---|
| annual report | annual report | March to April of next year |
| interim report | interim report | August to September |
| Q1 report | first-quarter report | April |
| Q3 report | third-quarter report | October |

## Step 1: Search for the report

Use `Research`:

```text
Research(action: "search", query: "site:stockn.xueqiu.com {formatted_code} {report_keyword} {year}")
```

If the year is missing, search the current likely year first, then the previous year.

Fallbacks:
1. Tonghuashun notice site
2. search by company name
3. remove the `site:` restriction as a last resort

## Step 2: Extract the PDF link

Keep only URLs ending in `.pdf`, especially:

- `https://stockn.xueqiu.com/...pdf`
- `https://notice.10jqka.com.cn/...pdf`

## Step 3: Pick the correct report

Exclude results containing:
- summary
- audit report
- profit-distribution notice
- sustainability
- shareholder meeting
- ESG
- correction
- supplement
- opinion
- internal control

Prefer:
1. title clearly matches the target report type
2. release date closest to the expected reporting window

## Step 4: Download

```text
ReportDownload(
  url: "<PDF_URL>",
  outputPath: "memory/financeReport/{stock_code}_{report_type}_{year}/original.pdf"
)
```

## Step 5: Parse and summarize

```text
ReportParse(filePath: "memory/financeReport/{stock_code}_{report_type}_{year}/original.pdf")
```

Report back to the user with:
- success or failure
- file path
- company name
- report period
- any failure message and what to retry
