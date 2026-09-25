#!/usr/bin/env node
'use strict';

/**
 * Run inside QA API container: -w /srv/tride/backend
 * Same require paths as socket-qa URGENT runners (requireBackend('./…')).
 */

const path = require('node:path');

const BACKEND_ROOT = (process.env.SOCKET_BACKEND_ROOT || '/srv/tride/backend').replace(/\\/g, '/');

const SPECS = [
  {
    file: 'urgent-qa-db-markers.cjs',
    functions: ['fetchUrgentDbMarkers', 'countUrgentNotifications', 'countUrgentIdempotencyKeys'],
  },
  {
    file: 'urgent-qa-db-errors.cjs',
    functions: [
      'formatFatalDbError',
      'formatDbError',
      'formatFatalRunnerError',
      'classifyFatalRunnerError',
    ],
  },
];

function safeRequireError(err) {
  return {
    code: err?.code ?? null,
    kind: err?.code === 'MODULE_NOT_FOUND' ? 'module_not_found' : 'require_failed',
  };
}

const report = {
  backendRoot: BACKEND_ROOT,
  scope: 'urgent_qa_helpers_container',
  checks: [],
  pass: true,
};

for (const spec of SPECS) {
  const abs = path.join(BACKEND_ROOT, spec.file);
  let mod;
  try {
    // eslint-disable-next-line import/no-dynamic-require, global-require
    mod = require(abs);
  } catch (err) {
    report.pass = false;
    report.checks.push({ file: spec.file, require: safeRequireError(err) });
    continue;
  }
  for (const name of spec.functions) {
    const ok = typeof mod[name] === 'function';
    report.checks.push({ file: spec.file, export: name, type: typeof mod[name], ok });
    if (!ok) report.pass = false;
  }
}

console.log(JSON.stringify(report));
process.exit(report.pass ? 0 : 1);
