import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const tmp = mkdtempSync(join(tmpdir(), "codex-network-bootstrap-"));
const out = join(tmp, "mihomo-codex.yaml");

execFileSync(
  process.execPath,
  [
    "client/generate-mihomo-config.mjs",
    "--tokyo",
    "examples/tokyo.example.json",
    "--singapore",
    "examples/singapore.example.json",
    "--out",
    out,
  ],
  { stdio: "pipe" },
);

const yaml = readFileSync(out, "utf8");

assert.match(yaml, /name: "TOKYO-VLESS"/);
assert.match(yaml, /name: AUTO-CODEX/);
assert.match(yaml, /DOMAIN-SUFFIX,openai\.com,AUTO-CODEX/);
assert.match(yaml, /DOMAIN-SUFFIX,github\.com,AUTO-CODEX/);
assert.match(yaml, /IP-CIDR,10\.0\.0\.0\/8,DIRECT,no-resolve/);
assert.match(yaml, /server: "203\.0\.113\.10"/);
assert.match(yaml, /server: "203\.0\.113\.20"/);

console.log("generate-mihomo-config test passed");
