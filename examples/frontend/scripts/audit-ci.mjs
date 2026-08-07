#!/usr/bin/env node
// frontend/scripts/audit-ci.mjs — gate 12, the fast dependency CVE gate.
//
// Fails on any HIGH or CRITICAL advisory across the whole dependency tree, production
// and development alike, except entries explicitly allowlisted in
// frontend/audit-allowlist.json with a written exposure analysis. An all-or-nothing
// `npm audit --audit-level=high` is the wrong shape here: one unfixable advisory would
// force the bar down for everything else. Keeping the bar high and making each
// exception a named, reviewable decision is what this script is for.
//
// It also FAILS when an allowlisted advisory disappears from the audit output — the
// same "no stale exceptions" ratchet as the architecture freeze store and the
// accessibility baseline (docs/QUALITY-GATES.md).
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ALLOWLIST_FILE = path.join(__dirname, "..", "audit-allowlist.json");

async function loadAllowlist() {
  try {
    const text = await readFile(ALLOWLIST_FILE, "utf8");
    return JSON.parse(text);
  } catch (e) {
    if (e.code === "ENOENT") return [];
    throw e;
  }
}

function runAudit() {
  // `npm audit --json` exits non-zero when it finds ANYTHING, including low-severity —
  // that is expected and not itself a failure signal here; we parse the JSON and decide.
  const result = spawnSync("npm", ["audit", "--json"], { encoding: "utf8" });
  if (!result.stdout) {
    console.error("audit-ci: npm audit produced no output.");
    console.error(result.stderr || "");
    process.exit(2);
  }
  return JSON.parse(result.stdout);
}

async function main() {
  const allowlist = await loadAllowlist();
  // Normalize to strings: npm audit's JSON reports advisory `source` as a number, and
  // JSON.parse on the allowlist file preserves whatever type was written there — mixing
  // numbers and strings makes Set membership fail silently (1109537 !== "1109537"),
  // which would make a real allowlist entry look stale by construction.
  const allowedIds = new Set(allowlist.map((e) => String(e.id)));
  const audit = runAudit();

  const vulnerabilities = audit.vulnerabilities ?? {};
  const highOrCritical = [];
  for (const [pkg, info] of Object.entries(vulnerabilities)) {
    if (info.severity === "high" || info.severity === "critical") {
      const ids = (info.via ?? [])
        .filter((v) => typeof v === "object" && v.source)
        .map((v) => String(v.source));
      highOrCritical.push({ pkg, severity: info.severity, ids: ids.length ? ids : [pkg] });
    }
  }

  let failed = false;

  for (const { pkg, severity, ids } of highOrCritical) {
    const isAllowed = ids.some((id) => allowedIds.has(id)) || allowedIds.has(pkg);
    if (!isAllowed) {
      console.error(
        `audit-ci: UNALLOWLISTED ${severity} advisory in ${pkg} (${ids.join(", ")}). Add an entry to frontend/audit-allowlist.json with a written exposure analysis, or fix the dependency.`,
      );
      failed = true;
    }
  }

  const stillPresentIds = new Set(highOrCritical.flatMap((h) => h.ids));
  for (const entry of allowlist) {
    if (!stillPresentIds.has(String(entry.id))) {
      console.error(
        `audit-ci: STALE allowlist entry '${entry.id}' — the advisory it excused no longer appears in the audit. Remove it from frontend/audit-allowlist.json; a stale exception is not allowed to accumulate.`,
      );
      failed = true;
    }
  }

  if (failed) process.exit(1);
  console.log(
    `audit-ci: clean — ${highOrCritical.length} high/critical advisory(ies), all allowlisted; ${allowlist.length} allowlist entry(ies), none stale.`,
  );
}

main();
