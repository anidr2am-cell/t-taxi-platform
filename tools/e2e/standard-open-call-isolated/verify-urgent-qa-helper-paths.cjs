#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const ROOT = process.env.VERIFY_ROOT
  ? path.resolve(process.env.VERIFY_ROOT)
  : __dirname;
const SUITE_SH = path.join(ROOT, 'run-urgent-isolated-suite.sh');
const RUNNERS = [
  path.join(ROOT, 'socket-qa', 'run-urgent-contact-dispatch-matrix.mjs'),
  path.join(ROOT, 'socket-qa', 'run-urgent-gate-false-smoke.mjs'),
];

const BACKEND_DEST_PREFIX = '/srv/tride/backend/';
const REQUIRED_HELPERS = ['urgent-qa-db-markers.cjs', 'urgent-qa-db-errors.cjs'];

function parseRunnerRequires(filePath) {
  const text = fs.readFileSync(filePath, 'utf8');
  const re = /requireBackend\('\.\/([^']+)'\)/g;
  const mods = new Set();
  let m;
  while ((m = re.exec(text)) !== null) mods.add(m[1]);
  return mods;
}

function parseSuiteCopies(suiteText) {
  const copies = new Map();
  const patterns = [
    /docker cp "\$QA\/([^"]+)" "\$c:([^"]+)"/g,
    /urgent_docker_cp_required "\$QA" "\$c" ([^\s]+) ([^\s]+)/g,
  ];
  for (const re of patterns) {
    let m;
    while ((m = re.exec(suiteText)) !== null) {
      copies.set(m[1], m[2]);
    }
  }
  return copies;
}

const suiteText = fs.readFileSync(SUITE_SH, 'utf8');
const copies = parseSuiteCopies(suiteText);
const runnerRequires = new Map();
for (const runner of RUNNERS) {
  runnerRequires.set(path.basename(runner), parseRunnerRequires(runner));
}

const mismatches = [];
for (const helper of REQUIRED_HELPERS) {
  const expectedDest = `${BACKEND_DEST_PREFIX}${helper}`;
  const dest = copies.get(helper);
  if (!dest) {
    mismatches.push({ helper, issue: 'missing_docker_cp_in_copy_qa_scripts' });
    continue;
  }
  if (dest !== expectedDest) {
    mismatches.push({ helper, issue: 'copy_dest_mismatch', expected: expectedDest, actual: dest });
  }
}

for (const [runnerName, mods] of runnerRequires) {
  for (const helper of REQUIRED_HELPERS) {
    if (mods.has(helper) && !copies.has(helper)) {
      mismatches.push({ runner: runnerName, helper, issue: 'runner_requires_uncopied_module' });
    }
    if (mods.has(helper) && copies.get(helper) !== `${BACKEND_DEST_PREFIX}${helper}`) {
      mismatches.push({ runner: runnerName, helper, issue: 'runner_require_path_not_at_backend_root' });
    }
  }
}

function smokeExportsInTempDir() {
  const smokeBase = process.env.VERIFY_SMOKE_TMP
    ? path.resolve(process.env.VERIFY_SMOKE_TMP)
    : os.tmpdir();
  const tmp = fs.mkdtempSync(path.join(smokeBase, 'urgent-qa-helpers-'));
  for (const name of ['urgent-qa-pickup.cjs', 'urgent-qa-db-markers.cjs', 'urgent-qa-db-errors.cjs']) {
    fs.copyFileSync(path.join(ROOT, name), path.join(tmp, name));
  }
  const markers = require(path.join(tmp, 'urgent-qa-db-markers.cjs'));
  const errors = require(path.join(tmp, 'urgent-qa-db-errors.cjs'));
  const fnChecks = [
    ['urgent-qa-db-markers.cjs', 'fetchUrgentDbMarkers', markers.fetchUrgentDbMarkers],
    ['urgent-qa-db-markers.cjs', 'countUrgentNotifications', markers.countUrgentNotifications],
    ['urgent-qa-db-errors.cjs', 'formatFatalDbError', errors.formatFatalDbError],
    ['urgent-qa-db-errors.cjs', 'formatDbError', errors.formatDbError],
    ['urgent-qa-db-errors.cjs', 'formatFatalRunnerError', errors.formatFatalRunnerError],
    ['urgent-qa-db-errors.cjs', 'classifyFatalRunnerError', errors.classifyFatalRunnerError],
  ];
  const bad = fnChecks.filter(([, , fn]) => typeof fn !== 'function');
  const classifyFails = runFatalClassifyChecks(errors);
  fs.rmSync(tmp, { recursive: true, force: true });
  return [
    ...bad.map(([file, exp]) => ({ file, export: exp, issue: 'not_a_function_in_temp_smoke' })),
    ...classifyFails,
  ];
}

function runFatalClassifyChecks(errors) {
  const secret = 'SuperSecretQaPw-TEST-ONLY-NOT-REAL';
  const fails = [];
  const missing = new Error(`Missing QA driver password: ${secret}`);
  missing.code = 'QA_PASSWORD_MISSING';
  const missingOut = errors.formatFatalRunnerError(missing, 'gate_false_smoke');
  if (!String(missingOut).startsWith('qa_password_missing:')) {
    fails.push({ issue: 'password_missing_not_classified' });
  }
  if (String(missingOut).includes(secret)) {
    fails.push({ issue: 'password_leaked_in_fatal' });
  }

  const generic = new Error(`boom ${secret}`);
  const genericOut = errors.formatFatalRunnerError(generic, 'gate_false_smoke');
  if (String(genericOut).startsWith('db_error:')) {
    fails.push({ issue: 'generic_error_misclassified_as_db' });
  }
  if (String(genericOut).includes(secret)) {
    fails.push({ issue: 'secret_leaked_in_runtime_fatal' });
  }

  const dbErr = new Error("Table 'tride_qa_admin.notifications' doesn't exist");
  dbErr.errno = 1146;
  dbErr.code = 'ER_NO_SUCH_TABLE';
  const dbOut = errors.formatFatalRunnerError(dbErr, 'gate_false_smoke');
  if (!String(dbOut).startsWith('db_error:')) {
    fails.push({ issue: 'mysql_error_not_db_error' });
  }
  return fails;
}

const smokeFailures = smokeExportsInTempDir();

const report = {
  requiredHelpers: REQUIRED_HELPERS,
  runnerRequireBackendRoot: BACKEND_DEST_PREFIX,
  copyQaScriptsDestinations: Object.fromEntries(
    REQUIRED_HELPERS.map((h) => [h, copies.get(h) ?? null]),
  ),
  mismatches,
  smokeFailures,
  pass: mismatches.length === 0 && smokeFailures.length === 0,
};

console.log(JSON.stringify(report, null, 2));
process.exit(report.pass ? 0 : 1);
