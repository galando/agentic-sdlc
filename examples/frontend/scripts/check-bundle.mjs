#!/usr/bin/env node
// frontend/scripts/check-bundle.mjs — gate 19, the bundle-size budget.
//
// The one ratchet-bearing file that reads floors.yml DIRECTLY rather than going through
// a FLOORS:BEGIN/END marked block — see design.md section 7.2 point 5. It is our own
// script, so there is no third-party tool syntax to work around; the asymmetry with the
// other four floors is documented in docs/QUALITY-GATES.md.
//
// Usage:
//   node scripts/check-bundle.mjs                 # gate mode: measures, prints, exits
//                                                  #   non-zero only if calibrated AND over
//   node scripts/check-bundle.mjs --measure-only   # tools/measure-floors.sh's mode:
//                                                  #   prints just the measured KiB, silent
//                                                  #   otherwise, always exits 0
import { createReadStream, readFileSync } from "node:fs";
import { readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import zlib from "node:zlib";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// __dirname is examples/frontend/scripts — three levels up (scripts -> frontend ->
// examples -> repo root) to reach floors.yml, one more than a non-nested frontend/
// would need, because the bundled example lives under examples/ (tasks.md Task 23).
const ROOT = path.resolve(__dirname, "..", "..", "..");
const DIST = path.join(__dirname, "..", "dist");
const FLOORS_FILE = path.join(ROOT, "floors.yml");

const measureOnly = process.argv.includes("--measure-only");

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await walk(full)));
    else files.push(full);
  }
  return files;
}

function gzipSize(file) {
  return new Promise((resolve, reject) => {
    const gzip = zlib.createGzip({ level: 9 });
    let size = 0;
    createReadStream(file)
      .pipe(gzip)
      .on("data", (chunk) => {
        size += chunk.length;
      })
      .on("end", () => resolve(size))
      .on("error", reject);
  });
}

// floors.yml's own tiny reader — mirrors tools/lib/config.sh's floor_get awk fallback
// (a one-line-flow-map entry OR a multi-line calibrated block), so this script has no
// dependency on yq being installed.
function readFloor(key) {
  const text = readFileSync(FLOORS_FILE, "utf8");
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const m = line.match(new RegExp(`^ {2}${key.replace(/\./g, "\\.")}:\\s*(.*)$`));
    if (!m) continue;
    const rest = m[1].trim();
    if (rest.startsWith("{")) {
      const valueMatch = rest.match(/value:\s*([^,}]+)/);
      return valueMatch ? valueMatch[1].trim() : null;
    }
    if (rest === "") {
      for (let j = i + 1; j < lines.length && /^ {4}/.test(lines[j]); j++) {
        const vm = lines[j].match(/value:\s*(.+)$/);
        if (vm) return vm[1].trim();
      }
    }
  }
  return null;
}

async function main() {
  let files;
  try {
    files = (await walk(path.join(DIST, "assets"))).filter((f) =>
      /\.(js|css)$/.test(f),
    );
  } catch {
    console.error(
      "check-bundle: dist/assets not found — run `npm run build` first.",
    );
    process.exit(measureOnly ? 1 : 2);
  }

  let totalBytes = 0;
  for (const file of files) {
    totalBytes += await gzipSize(file);
  }
  const totalKib = totalBytes / 1024;

  if (measureOnly) {
    // tools/measure-floors.sh's write_floor expects a bare decimal on stdout — nothing
    // else, so it can be captured directly into floors.yml.
    console.log(totalKib.toFixed(2));
    return;
  }

  const floor = readFloor("frontend.bundle.total_kib");
  if (!floor || floor === "unset") {
    console.log(
      `check-bundle: measured ${totalKib.toFixed(1)} KiB gzipped. floor not yet calibrated — run tools/measure-floors.sh against your product.`,
    );
    process.exit(0);
  }

  const ceiling = Number(floor);
  console.log(
    `check-bundle: measured ${totalKib.toFixed(1)} KiB gzipped, ceiling ${ceiling} KiB.`,
  );
  if (totalKib > ceiling) {
    console.error(
      `check-bundle: FAILED — bundle grew past its ceiling (${totalKib.toFixed(1)} KiB > ${ceiling} KiB). See docs/QUALITY-GATES.md's ratchet policy: a ceiling moves down freely after a size win, and raising it needs the same written justification as lowering a coverage floor.`,
    );
    process.exit(1);
  }
}

main();
