// Assert URGENT gate=true matrix JSON (cases UA–UE).
const fs = require('node:fs');
const path = process.argv[2];
if (!path) {
  console.error('usage: node assert-urgent-contact-dispatch-matrix.cjs <matrix.json>');
  process.exit(2);
}
let report;
try {
  report = JSON.parse(fs.readFileSync(path, 'utf8'));
} catch {
  console.error(JSON.stringify({ ok: false, reason: 'invalid_json', path }));
  process.exit(1);
}
const required = ['UA', 'UB', 'UC', 'UD', 'UE'];
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
