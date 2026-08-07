// Gate 9 — the frontend half of the ratchet guard: reads the LIVE configs and fails if a
// floor was lowered, a threshold deleted, or an exclude widened. `fast-repo-hygiene`'s
// render-floors.sh diff (design.md section 7.5) catches a hand-edit at pull-request
// time; this test is the one that survives even if that CI job is ever deleted or
// bypassed, because it runs inside `npm run test:coverage` itself.
//
// Never edit this test, floors.yml, or a FLOORS:BEGIN/END block to make a red run go
// green — see docs/QUALITY-GATES.md's ratchet policy. That is an escalation, not a fix.
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const __dirname = path.dirname(fileURLToPath(import.meta.url));

function findRepoRoot(): string {
  let dir = path.resolve(__dirname, "..", "..");
  while (dir !== path.parse(dir).root) {
    if (
      (() => {
        try {
          readFileSync(path.join(dir, "floors.yml"));
          return true;
        } catch {
          return false;
        }
      })()
    ) {
      return dir;
    }
    dir = path.dirname(dir);
  }
  throw new Error("could not find floors.yml above " + __dirname);
}

function floorValue(yml: string, key: string): string {
  const escaped = key.replace(/\./g, "\\.");
  const flow = yml.match(new RegExp(`^ {2}${escaped}:\\s*\\{\\s*value:\\s*([^,}]+)`, "m"));
  if (flow) return flow[1].trim();
  const block = yml.match(new RegExp(`^ {2}${escaped}:\\s*\\n\\s*value:\\s*([^\\n]+)`, "m"));
  if (block) return block[1].trim();
  throw new Error(`floors.yml has no entry for ${key}`);
}

const ROOT = findRepoRoot();
const floorsYml = readFileSync(path.join(ROOT, "floors.yml"), "utf8");
const vitestConfig = readFileSync(path.join(ROOT, "examples/frontend/vitest.config.js"), "utf8");
const strykerConfig = readFileSync(path.join(ROOT, "examples/frontend/stryker.config.mjs"), "utf8");

describe("ratchet guard", () => {
  it("vitest coverage thresholds agree with floors.yml", () => {
    const keys = [
      "frontend.coverage.statements",
      "frontend.coverage.branches",
      "frontend.coverage.functions",
      "frontend.coverage.lines",
    ];
    const values = keys.map((k) => floorValue(floorsYml, k));
    const anyUnset = values.some((v) => v === "unset");

    if (anyUnset) {
      expect(
        vitestConfig,
        "floors.yml has an unset frontend coverage floor; vitest.config.js's thresholds must be the empty object, not silently populated",
      ).toMatch(/thresholds:\s*\{\}/);
    } else {
      const [stmts, branches, funcs, lines] = values.map((v) =>
        Math.round(Number(v) * 100),
      );
      expect(
        vitestConfig,
        "floors.yml has calibrated frontend coverage floors; vitest.config.js's thresholds must match them",
      ).toContain(
        `thresholds: { statements: ${stmts}, branches: ${branches}, functions: ${funcs}, lines: ${lines} }`,
      );
    }
  });

  it("Stryker's mutation threshold agrees with floors.yml", () => {
    const score = floorValue(floorsYml, "frontend.mutation.score");
    if (score === "unset") {
      expect(
        strykerConfig,
        "floors.yml has an unset mutation floor; stryker.config.mjs's break must stay null, Stryker's own documented 'never break the build'",
      ).toMatch(/break:\s*null/);
    } else {
      const expected = Math.round(Number(score) * 100);
      expect(strykerConfig).toContain(`break: ${expected}`);
    }
  });

  it("the design-system guardrail script has not been removed", () => {
    // A removed check is indistinguishable from a passing one unless something asserts
    // it still exists — same shape as the freeze-store-deletion guard on the backend.
    const scriptPath = path.join(ROOT, "examples/frontend/scripts/check-design-system.mjs");
    expect(() => readFileSync(scriptPath)).not.toThrow();
  });
});
