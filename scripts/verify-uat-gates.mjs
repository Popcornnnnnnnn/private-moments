#!/usr/bin/env node
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const rootDir = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const gatesPath = path.join(rootDir, "docs", "UAT-GATES.md");
const strict = process.argv.includes("--strict");

const markdown = await readFile(gatesPath, "utf8");
const gates = markdown
  .split("\n")
  .filter((line) => /^\|\s*UAT-[A-Z0-9-]+/.test(line))
  .map((line) => {
    const cells = line
      .split("|")
      .slice(1, -1)
      .map((cell) => cell.trim());
    return {
      id: cells[0] ?? "",
      status: (cells[1] ?? "").toLowerCase(),
      area: cells[2] ?? "",
      requiredEvidence: cells[3] ?? "",
    };
  });

if (gates.length === 0) {
  console.error(`No UAT gates found in ${gatesPath}`);
  process.exit(1);
}

const openGates = gates.filter((gate) => gate.status !== "closed");

console.log(`UAT gates: ${gates.length} total, ${openGates.length} open`);
for (const gate of openGates) {
  console.log(`- ${gate.id}: ${gate.area} (${gate.status})`);
}

if (strict && openGates.length > 0) {
  console.error("Release gate failed: open UAT gates remain.");
  process.exit(1);
}
