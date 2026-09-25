'use strict';

// Assert URGENT gate=false smoke JSON (UF-login + UF).
const fs = require('node:fs');
const path = process.argv[2];
if (!path) {
  console.error('usage: node assert-urgent-gate-false-smoke.cjs <smoke.json>');
  process.exit(2);
}
let report;
try {
  report = JSON.parse(fs.readFileSync(path, 'utf8'));
} catch {
  console.error(JSON.stringify({ ok: false, reason: 'invalid_json', path }));
  process.exit(1);
}
const required = ['UF-login', 'UF'];
const failed = required.filter((id) => !report.cases?.[id]?.ok);
if (!report.pass || failed.length) {
  console.error(JSON.stringify({
    ok: false,
    pass: report.pass,
    failedCases: failed,
    fatal: report.fatal ?? null,
  }));
  process.exit(1);
}
console.log(JSON.stringify({ ok: true, cases: required, executedAt: report.executedAt }));
process.exit(0);
