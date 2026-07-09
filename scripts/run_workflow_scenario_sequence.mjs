#!/usr/bin/env node
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { request } from "node:http";
import { basename, join, resolve } from "node:path";

const args = parseArgs(process.argv.slice(2));
const port = Number(args.port ?? process.env.FINAGENT_WORKFLOW_AUTOMATION_PORT ?? 39274);
const scenarioFile = resolve(String(args.file ?? "reports/evaluation/finance_agent_quant_strategy_p2_full_app_scenarios_2026_06_28.json"));
const scenarioId = args.scenario ? String(args.scenario) : undefined;
const outDir = resolve(String(args.out ?? "reports/evaluation/workflow_runs"));

if (!Number.isFinite(port) || port <= 0) fail("A valid --port or FINAGENT_WORKFLOW_AUTOMATION_PORT is required.");
if (!existsSync(scenarioFile)) fail(`Scenario file not found: ${scenarioFile}`);

const catalog = JSON.parse(readFileSync(scenarioFile, "utf-8"));
const scenarios = Array.isArray(catalog.scenarios) ? catalog.scenarios : [];
const selected = scenarioId ? scenarios.filter((scenario) => scenario.id === scenarioId) : scenarios;
if (selected.length === 0) fail(`No scenarios selected from ${scenarioFile}${scenarioId ? ` for ${scenarioId}` : ""}.`);

const health = await getJson("/health");
if (!health.enabled) {
  fail(`FinAgent workflow automation endpoint is not enabled on 127.0.0.1:${port}. health=${JSON.stringify(health)}`);
}

mkdirSync(outDir, { recursive: true });
const runStamp = new Date().toISOString().replace(/[:.]/g, "-");
const summaries = [];

for (const scenario of selected) {
  const scenarioTurns = Array.isArray(scenario.turns) && scenario.turns.length
    ? scenario.turns
    : [scenario];
  if (!scenarioTurns[0]?.prompt) fail(`Scenario ${scenario.id} must contain at least one prompt turn.`);
  let cleanSessionResult = null;
  if (args["clean-session"] || scenario.cleanSession === true) {
    console.log(`Clearing FinAgent workflow session before ${scenario.id}`);
    cleanSessionResult = await postJson("/workflow/clear_session", { reason: `scenario:${scenario.id}` });
  }
  const turnResults = [];
  for (let index = 0; index < scenarioTurns.length; index++) {
    const runtimeTurn = mergeRuntimeOverride(
      scenarioTurns[index],
      scenario.runtimeOverrides?.finagent,
      scenarioTurns[index]?.turnId,
    );
    const turnId = runtimeTurn.turnId ?? `turn-${index + 1}`;
    const payload = {
      id: `${scenario.id}:${turnId}`,
      prompt: runtimeTurn.prompt,
      workflowState: runtimeTurn.workflowState,
      cleanSession: false,
      maxToolCalls: runtimeTurn.maxToolCalls,
      maxDataToolCalls: runtimeTurn.maxDataToolCalls,
      disallowTools: runtimeTurn.disallowTools,
      expectTools: runtimeTurn.expectTools,
      expectToolActions: runtimeTurn.expectToolActions,
      maxToolActionCounts: runtimeTurn.maxToolActionCounts,
      expectNoToolErrors: runtimeTurn.expectNoToolErrors,
      expectToolErrors: runtimeTurn.expectToolErrors,
      expectToolResultContains: runtimeTurn.expectToolResultContains,
      expectFinalContains: runtimeTurn.expectFinalContains,
      expectSessionContains: [
        ...(index === scenarioTurns.length - 1 ? scenario.expectSessionContains ?? [] : []),
        ...(runtimeTurn.expectSessionContains ?? []),
      ],
      expectUiStateKeys: runtimeTurn.expectUiStateKeys,
      expectUiEvidencePaths: runtimeTurn.expectUiEvidencePaths,
      expectUiArtifactKinds: runtimeTurn.expectUiArtifactKinds,
      allowPendingUserQuestion: runtimeTurn.allowPendingUserQuestion,
      autoAnswerUserQuestions: runtimeTurn.autoAnswerUserQuestions,
      autoAnswerUserQuestion: runtimeTurn.autoAnswerUserQuestion,
      timeoutMs: runtimeTurn.timeoutMs,
    };
    console.log(`Running ${payload.id} through http://127.0.0.1:${port}/workflow/scenario`);
    const result = await postJson("/workflow/scenario", payload);
    turnResults.push({ turn: runtimeTurn, result });
  }
  const result = {
    ok: turnResults.every((item) => item.result?.ok === true),
    turns: turnResults.map((item, index) => ({
      turnId: item.turn.turnId ?? `turn-${index + 1}`,
      turnIndex: index,
      ok: Boolean(item.result?.ok),
      ...item.result,
    })),
  };
  const review = buildReview(scenario, turnResults, result, cleanSessionResult);
  const jsonPath = join(outDir, `${runStamp}-${safeFilePart(scenario.id)}-finagent.json`);
  const mdPath = join(outDir, `${runStamp}-${safeFilePart(scenario.id)}-finagent.md`);
  writeFileSync(jsonPath, JSON.stringify({ scenario, result, review }, null, 2), "utf-8");
  writeFileSync(mdPath, renderReviewMarkdown({ scenario, result, review, jsonPath }), "utf-8");
  summaries.push({ scenarioId: scenario.id, ok: result.ok, turns: turnResults.length, jsonPath, mdPath });
  console.log(`Wrote ${mdPath}`);
}

function mergeRuntimeOverride(turn, override, turnId) {
  if (!override || typeof override !== "object") return turn;
  const turnOverride = Array.isArray(override.turns)
    ? override.turns.find((item) => item?.turnId && item.turnId === turnId)
    : null;
  const scalarOverride = Object.fromEntries(Object.entries(override).filter(([key]) => key !== "turns"));
  const merged = { ...turn, ...scalarOverride, ...(turnOverride ?? {}) };
  if (Array.isArray(turn.disallowTools) || Array.isArray(merged.disallowTools)) {
    const base = Array.isArray(turn.disallowTools) ? turn.disallowTools : [];
    const replacement = Array.isArray(merged.disallowTools) ? merged.disallowTools : base;
    const allow = new Set(Array.isArray(merged.allowTools) ? merged.allowTools : []);
    merged.disallowTools = replacement.filter((tool) => !allow.has(tool));
  }
  return merged;
}

const indexPath = join(outDir, `${runStamp}-finagent-index.json`);
writeFileSync(
  indexPath,
  JSON.stringify({ source: basename(scenarioFile), port, generatedAt: new Date().toISOString(), summaries }, null, 2),
  "utf-8",
);
console.log(`Wrote ${indexPath}`);

function buildReview(scenario, turnResults, result, cleanSessionResult) {
  const firstReport = turnResults[0]?.result?.run?.report ?? {};
  return {
    reviewRequired: true,
    scenarioId: scenario.id,
    ok: Boolean(result.ok),
    scenarioReportPath: result.scenarioReportPath ?? null,
    assertionFailures: turnResults.flatMap(({ turn, result: turnResult }, index) =>
      Array.isArray(turnResult.assertions)
        ? turnResult.assertions
            .filter((assertion) => assertion?.ok !== true)
            .map((assertion) => ({
              ...assertion,
              turnId: turn.turnId ?? `turn-${index + 1}`,
            }))
        : [],
    ),
    reviewCriteria: scenario.reviewCriteria ?? [],
    sessionHygiene: {
      requestedCleanSession: Boolean(cleanSessionResult),
      cleanSessionResult,
      scenarioSessionId: firstReport.sessionId ?? null,
    },
    turns: turnResults.map(({ turn, result: turnResult }, index) => {
      const report = turnResult.run?.report ?? {};
      const toolCalls = Array.isArray(report.toolCalls) ? report.toolCalls : [];
      const toolErrors = Array.isArray(report.toolErrors) ? report.toolErrors : [];
      return {
        turnId: turn.turnId ?? `turn-${index + 1}`,
        prompt: turn.prompt,
        ok: Boolean(turnResult.ok),
        finalAssistant: report.finalAssistantText ?? "",
        toolNames: [...new Set(toolCalls.map((tool) => tool.toolName ?? tool.name).filter(Boolean))],
        toolCallCount: toolCalls.length,
        toolErrorCount: toolErrors.length,
        panelEvidenceAvailable: report.uiState != null,
        uiArtifactKinds: (report.uiArtifacts ?? []).map((artifact) => artifact.kind),
        reportPath: turnResult.run?.reportPath ?? null,
      };
    }),
  };
}

function renderReviewMarkdown({ scenario, result, review, jsonPath }) {
  const priority = scenario.priority ?? "P0";
  const lines = [
    `# Workflow Review: ${scenario.id} / FinAgent`,
    "",
    `Generated: ${new Date().toISOString()}`,
    `Runtime: finagent`,
    `Priority: ${scenario.priority ?? "unknown"}`,
    `Result: ${result.ok ? "ok" : "needs review/fix"}`,
    `Scenario report: ${result.scenarioReportPath ?? "-"}`,
    `Raw JSON: ${jsonPath}`,
    `Session hygiene: ${review.sessionHygiene?.requestedCleanSession ? "clean session requested" : "continuation/default session"}; session=${review.sessionHygiene?.scenarioSessionId ?? "-"}`,
    "",
    "## Purpose",
    "",
    scenario.purpose ?? "",
    "",
    "## Review Criteria",
    "",
    ...(review.reviewCriteria.length ? review.reviewCriteria.map((item) => `- ${item}`) : ["- No explicit review criteria supplied."]),
    "",
    "## Assertion Failures",
    "",
    ...(review.assertionFailures.length
      ? review.assertionFailures.map((item) => `- ${item.name ?? "unknown"}: expected ${JSON.stringify(item.expected)} actual ${JSON.stringify(item.actual)}`)
      : ["- None recorded by the automation endpoint."]),
    "",
    "## Turns",
    "",
  ];
  for (const turn of review.turns) {
    lines.push(
      `### ${turn.turnId ?? "turn"}`,
      "",
      `Prompt: ${turn.prompt ?? ""}`,
      `Status: ${turn.ok ? "ok" : "needs review/fix"}`,
      `Tools: ${turn.toolNames?.length ? turn.toolNames.join(", ") : "-"}`,
      `Tool calls: ${turn.toolCallCount ?? 0}`,
      `Tool errors: ${turn.toolErrorCount ?? 0}`,
      `Panel evidence: ${turn.panelEvidenceAvailable ? "yes" : "no"}`,
      `UI artifacts: ${turn.uiArtifactKinds?.length ? turn.uiArtifactKinds.join(", ") : "-"}`,
      `Report: ${turn.reportPath ?? "-"}`,
      "",
      "Agent final answer:",
      "",
      "```text",
      trimForMarkdown(String(turn.finalAssistant ?? ""), 6000),
      "```",
      "",
    );
  }
  lines.push(
    "## Reviewer Decision",
    "",
    "- [ ] Agent content addresses the user intent.",
    "- [ ] Tool/environment interactions are appropriate.",
    "- [ ] API/provider failures are visible.",
    "- [ ] Agent-reported issues were verified against tool results, local data, UI state, or logs.",
    "- [ ] Confirmed app/agent/harness/data/UI defects were fixed or root-caused with a next action.",
    "- [ ] UI/session evidence supports the answer.",
    `- [ ] Case can be marked verified in the ${priority} ledger.`,
    "",
  );
  return `${lines.join("\n")}\n`;
}

async function getJson(path) {
  return requestJson("GET", path);
}

async function postJson(path, body) {
  return requestJson("POST", path, body);
}

function requestJson(method, path, body) {
  const payload = body == null ? null : JSON.stringify(body);
  return new Promise((resolve, reject) => {
    const req = request(
      {
        hostname: "127.0.0.1",
        port,
        path,
        method,
        headers: payload
          ? {
              "content-type": "application/json",
              "content-length": Buffer.byteLength(payload),
            }
          : undefined,
        timeout: 15 * 60_000,
      },
      (res) => {
        const chunks = [];
        res.setEncoding("utf8");
        res.on("data", (chunk) => chunks.push(chunk));
        res.on("end", () => {
          const text = chunks.join("");
          if ((res.statusCode ?? 500) < 200 || (res.statusCode ?? 500) >= 300) {
            reject(new Error(`${path} failed ${res.statusCode}: ${text}`));
            return;
          }
          try {
            resolve(text ? JSON.parse(text) : null);
          } catch (err) {
            reject(err);
          }
        });
      },
    );
    req.on("timeout", () => {
      req.destroy(new Error(`${path} timed out waiting for workflow response`));
    });
    req.on("error", reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function parseArgs(argv) {
  const parsed = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!arg.startsWith("--")) continue;
    const key = arg.slice(2);
    const next = argv[i + 1];
    if (!next || next.startsWith("--")) parsed[key] = true;
    else {
      parsed[key] = next;
      i += 1;
    }
  }
  return parsed;
}

function trimForMarkdown(value, max) {
  return value.length > max ? `${value.slice(0, max)}\n...` : value;
}

function safeFilePart(value) {
  return String(value).replace(/[^a-zA-Z0-9._-]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 80) || "scenario";
}

function fail(message) {
  console.error(message);
  process.exit(1);
}
