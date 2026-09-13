#!/usr/bin/env node
/**
 * Coverage headroom signal — report-only, never fails the build.
 *
 * The frontend coverage gate only says pass or fail. It reads
 * vitest.config.js's `thresholds` and fails when a measured value
 * drops below its floor. Anything above the floor looks identical whether
 * there is 0.02 points of margin left or 2 points — both print green.
 *
 * That hid a real loss upstream: a dependency bump rewrote one module from 4
 * functions to 14, three of them untested, and dropped the functions floor's
 * headroom from 0.67 points to 0.25 in one merged pull request. The gate
 * stayed green and nobody noticed for a week.
 *
 * WHAT THIS PRINTS: for each floor in vitest.config.js, the measured value,
 * the floor, and the gap between them in two units — percentage points and
 * uncovered items (how many more things could go untested before the floor
 * trips). A floor is marked THIN when fewer than 0.5 points OR fewer than 3
 * items of margin are left — whichever reading is smaller, since either one
 * alone can miss a thin margin the other would have caught.
 *
 * Each row also prints the measured sample as `covered/total`, so a reader
 * can tell a full suite run from a partial one instead of trusting the
 * percentage alone.
 *
 * WHY BOTH UNITS: percentage points read the same at every suite size, so a
 * reviewer cannot tell from points alone how many actual functions or lines
 * that margin represents. Items answer the question a reviewer actually has:
 * "how many more untested things can this PR add before the gate goes red?"
 *
 * WHY IT NEVER FAILS: this is a measurement, not a gate — the coverage
 * threshold check in vitest.config.js already owns pass/fail. Every read here
 * is wrapped; a missing report, a malformed one, or a config with no
 * thresholds block is a plain sentence and exit 0, never a crash.
 *
 * WHY IT READS THE CONFIG AS TEXT rather than importing vitest.config.js:
 * importing a vitest config from a plain node script can crash on a runtime
 * invariant, and a crash on the one code path that must never fail would
 * defeat the whole point. tools/render-floors.sh rewrites the same block as
 * text, so a text scan is also the reading that matches what the ratchet
 * actually renders.
 *
 * Exit codes:
 *   0 — always. See "WHY IT NEVER FAILS" above.
 *
 * Usage:  npm run test:coverage -- --run   (writes coverage/coverage-summary.json)
 *         npm run check:coverage-headroom
 */
import { readFileSync, appendFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = path.resolve(__dirname, '..', 'vitest.config.js');
const SUMMARY_PATH = path.resolve(__dirname, '..', 'coverage', 'coverage-summary.json');

/** A floor is THIN when either reading falls under its limit — the smaller reading wins. */
const THIN_POINTS = 0.5;
const THIN_ITEMS = 3;

/**
 * Pull every `name: number` pair out of the `thresholds: { ... }` block in a
 * vitest config source string, in the order they appear. Returns null when
 * there is no thresholds block (or it holds no readable pairs) — a missing
 * floor is never assumed or invented.
 *
 * Fails closed on a nested brace or a comment inside the block (a per-glob
 * threshold object is a documented vitest option, and a comment can hold a
 * stray number) rather than guess: this is a text scan, not a parser, so a
 * later `name: number` pair inside either one would silently overwrite a
 * real floor with a wrong one. A missing row is visible; a wrong row is not
 *.
 */
export function parseThresholds(configSource) {
  const block = configSource.match(/thresholds:\s*\{([^}]*)\}/);
  if (!block) return null;
  if (/\{|\/\/|\/\*/.test(block[1])) return null;

  const thresholds = {};
  for (const [, name, value] of block[1].matchAll(/(\w+)\s*:\s*(\d+(?:\.\d+)?)/g)) {
    thresholds[name] = Number(value);
  }
  return Object.keys(thresholds).length > 0 ? thresholds : null;
}

/**
 * One row per metric that is both a parsed floor and present in the coverage
 * summary's `total` block, in the order the floors were declared. This
 * intersection is what keeps a summary-only metric (e.g. `branchesTrue`) and
 * a floor the summary never measured both out of the report.
 *
 * `pct` is taken straight from the summary rather than recomputed, because it
 * is the exact number the coverage gate itself compares against the floor.
 * `items` is how many more things could go uncovered before the percentage
 * falls under the floor — negative once the floor is already missed.
 */
export function headroomRows(totals, thresholds) {
  const rows = [];
  for (const [metric, floor] of Object.entries(thresholds)) {
    const measured = totals[metric];
    // A corrupt summary can hold `null` (or any non-object) for a metric
    // instead of the usual { pct, covered, total } shape. Skip it the same
    // way an absent metric is skipped, so a malformed entry never crashes
    // main() from outside its try/catch blocks (this loop has none of its
    // own).
    if (measured === undefined || measured === null || typeof measured !== 'object') continue;

    const { pct, covered, total } = measured;
    // A metric with 0 measured items reports pct as the string "Unknown"
    // (istanbul/v8's convention for "nothing to divide by"), not a number.
    // There is no headroom to report on a metric nothing exercised.
    if (typeof pct !== 'number') continue;

    const points = pct - floor;
    const items = Math.floor(covered - (floor / 100) * total);
    const state = points < THIN_POINTS || items < THIN_ITEMS ? 'THIN' : 'OK';
    rows.push({ metric, pct, floor, covered, total, points, items, state });
  }
  return rows;
}

/** `+2.12` / `-0.86` — the sign is explicit for a positive margin, implicit (from toFixed) for a negative one. */
const signedPoints = (points) => `${points >= 0 ? '+' : ''}${points.toFixed(2)} pts`;

/** `+46 items` / `+1 item` / `-6 items` — singular only for exactly 1 (positive or negative). */
const signedItems = (items) => {
  const unit = Math.abs(items) === 1 ? 'item' : 'items';
  return `${items >= 0 ? '+' : ''}${items} ${unit}`;
};

/**
 * Render the headroom rows as one fixed-width text block, used verbatim in
 * the job log, the job summary and (for the THIN rows) the warning text.
 */
export function formatReport(rows) {
  const lines = ['Coverage headroom — frontend floors (measured vs. the floors in vitest.config.js)'];

  for (const row of rows) {
    const mark = row.state === 'THIN' ? 'THIN' : '    ';
    const pctFloor = `${row.pct.toFixed(2)}% / ${row.floor}`;
    const sample = `${row.covered}/${row.total}`;
    lines.push(
      `  ${mark} ${row.metric.padEnd(11)} ${pctFloor.padEnd(14)}${sample.padStart(9)}   ` +
        `${signedPoints(row.points).padStart(11)}  ${signedItems(row.items).padStart(10)}`
    );
  }

  lines.push('');
  lines.push('  THIN = less than 0.5 points, or fewer than 3 items, of margin left.');
  lines.push('  One more untested item in a THIN row can turn the coverage gate red.');
  return lines.join('\n') + '\n';
}

/** One `::warning::` GitHub Actions annotation per THIN row, naming the metric and both margins. */
export function warningLines(rows) {
  return rows
    .filter((row) => row.state === 'THIN')
    .map(
      (row) =>
        `::warning::Coverage headroom for "${row.metric}" is thin: ` +
        `${signedPoints(row.points)} / ${signedItems(row.items)} above the ${row.floor} floor.`
    );
}

/**
 * Read the floors and the coverage summary, print the report, and always
 * return 0. Reading, the environment and writing are injectable, so most
 * tests drive this without touching the real filesystem. Two things are not
 * injected: the call that appends to the job summary uses `appendFileSync`
 * directly, and the defaults are the real ones, so the tests that cover the
 * job-summary branch write to a temporary file and the test that calls this
 * with no arguments uses the real defaults.
 */
export function main({
  readFileFn = readFileSync,
  env = process.env,
  write = (text) => process.stdout.write(text),
} = {}) {
  let configSource;
  try {
    configSource = readFileFn(CONFIG_PATH, 'utf8');
  } catch {
    write(`No vitest config found at ${CONFIG_PATH} — cannot read the coverage floors.\n`);
    return 0;
  }

  const thresholds = parseThresholds(configSource);
  if (!thresholds) {
    write(
      'Could not read coverage floors from vitest.config.js: no readable `thresholds` block ' +
        'found. Skipping the headroom report — no floor is invented or assumed.\n'
    );
    return 0;
  }

  let summaryRaw;
  try {
    summaryRaw = readFileFn(SUMMARY_PATH, 'utf8');
  } catch {
    write(
      `No coverage summary found at ${SUMMARY_PATH}.\n` +
        'Run `npm run test:coverage -- --run` first to produce one.\n'
    );
    return 0;
  }

  let summary;
  try {
    summary = JSON.parse(summaryRaw);
  } catch {
    write(`The coverage summary at ${SUMMARY_PATH} could not be read: it is not valid JSON.\n`);
    return 0;
  }

  const totals = summary.total;
  if (!totals) {
    write('The coverage summary has no `total` block to report on.\n');
    return 0;
  }

  const rows = headroomRows(totals, thresholds);
  const report = formatReport(rows);
  write(report);

  const stepSummaryPath = env.GITHUB_STEP_SUMMARY;
  if (stepSummaryPath) {
    try {
      appendFileSync(stepSummaryPath, `\n## Coverage headroom\n\n\`\`\`\n${report}\`\`\`\n`);
    } catch {
      // The job summary is a convenience copy of the same text. Losing it
      // must never take the log output or the exit code down with it.
    }
  }

  for (const line of warningLines(rows)) {
    write(`${line}\n`);
  }

  return 0;
}

// Run only when invoked directly (not when imported by a test).
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exit(main());
}
