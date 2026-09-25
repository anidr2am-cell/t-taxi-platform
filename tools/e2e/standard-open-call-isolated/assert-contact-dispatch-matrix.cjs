// Assert matrix JSON: exit 0 only when pass=true and cases A,B,C are ok.
const fs = require('node:fs');
const path = process.argv[2];
if (!path) {
  console.error('usage: node assert-contact-dispatch-matrix.cjs <matrix.json>');
  process.exit(2);
}
let report;
try {
  report = JSON.parse(fs.readFileSync(path, 'utf8'));
} catch (e) {
  console.error(JSON.stringify({ ok: false, reason: 'invalid_json', path }));
  process.exit(1);
}
const required = ['A', 'B', 'C'];
const missing = required.filter((id) => !report.cases?.[id]?.ok);
if (!report.pass || missing.length) {
  console.error(JSON.stringify({
    ok: false,
    pass: report.pass,
    missingOrFailedCases: missing.length ? missing : required.filter((id) => !report.cases?.[id]?.ok),
    fatal: report.fatal ?? null,
  }));
  process.exit(1);
}
console.log(JSON.stringify({ ok: true, cases: required, executedAt: report.executedAt }));
process.exit(0);
