#!/usr/bin/env node
import { readFileSync, readdirSync } from "fs";
import { join, relative } from "path";
import { fileURLToPath } from "url";

const __dirname = fileURLToPath(new URL(".", import.meta.url));
const ROOT = join(__dirname, "..");
const SCAN_DIRS = [
  join(ROOT, "src", "modules"),
  join(ROOT, "src", "design-system"),
];
const PATTERN = /text-\[\d+px\]/;
const EXTENSIONS = new Set([".ts", ".tsx", ".js", ".jsx", ".css"]);

function walk(dir) {
  const files = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...walk(full));
    } else {
      const ext = entry.name.slice(entry.name.lastIndexOf("."));
      if (EXTENSIONS.has(ext)) files.push(full);
    }
  }
  return files;
}

const violations = [];

for (const dir of SCAN_DIRS) {
  for (const file of walk(dir)) {
    const lines = readFileSync(file, "utf8").split("\n");
    for (let i = 0; i < lines.length; i++) {
      if (PATTERN.test(lines[i])) {
        violations.push(`${relative(ROOT, file)}:${i + 1}`);
      }
    }
  }
}

if (violations.length > 0) {
  console.error("Ad-hoc font sizes found (use semantic text-* utilities):");
  for (const v of violations) {
    console.error(v);
  }
  process.exit(1);
}

console.log("Typography check passed.");
