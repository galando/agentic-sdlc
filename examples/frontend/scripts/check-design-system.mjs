#!/usr/bin/env node
// frontend/scripts/check-design-system.mjs — gate 14, the design-system/brand guardrail.
//
// Minimal but real: fails on a literal hex colour anywhere under src/ OUTSIDE
// src/tokens.css, which is the one place a colour is allowed to be a raw value. A
// component that wants a new colour edits the token file — a reviewable, greppable
// change — instead of a one-off hex code drifting the visual system component by
// component. Extend this script's checks as your design system grows; the shape (scan,
// collect, report every hit with a file:line, exit non-zero) is what matters, not this
// one rule.
import { readFile, readdir } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SRC = path.join(__dirname, "..", "src");
const HEX_COLOR = /#[0-9a-fA-F]{3,8}\b/g;
const ALLOWED_FILE = path.join(SRC, "tokens.css");

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await walk(full)));
    else if (/\.(tsx?|css)$/.test(entry.name)) files.push(full);
  }
  return files;
}

async function main() {
  const files = await walk(SRC);
  let hits = 0;
  for (const file of files) {
    if (file === ALLOWED_FILE) continue;
    const text = await readFile(file, "utf8");
    const lines = text.split("\n");
    lines.forEach((line, i) => {
      const matches = line.match(HEX_COLOR);
      if (matches) {
        for (const m of matches) {
          console.error(
            `${path.relative(process.cwd(), file)}:${i + 1}: hardcoded colour ${m} — add it to src/tokens.css as a --color-* custom property instead`,
          );
          hits++;
        }
      }
    });
  }

  if (hits > 0) {
    console.error(`\ncheck-design-system: ${hits} hardcoded colour(s) found.`);
    process.exit(1);
  }
  console.log("check-design-system: clean.");
}

main();
