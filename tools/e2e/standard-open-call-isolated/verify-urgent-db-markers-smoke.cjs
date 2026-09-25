#!/usr/bin/env node
'use strict';

/**
 * Runs URGENT notification aggregate SQL against a disposable DB (no bookings required).
 * Set QA_DB_HOST, QA_DB_USER, QA_DB_PASSWORD, QA_DB_NAME — or SKIP_URGENT_DB_SMOKE=1.
 */

const { countUrgentNotifications } = require('./urgent-qa-db-markers.cjs');
const { formatDbError } = require('./urgent-qa-db-errors.cjs');

async function main() {
  if (process.env.SKIP_URGENT_DB_SMOKE === '1') {
    console.log(JSON.stringify({ skipped: true, reason: 'SKIP_URGENT_DB_SMOKE' }));
    process.exit(0);
  }

  const host = process.env.QA_DB_HOST;
  const user = process.env.QA_DB_USER;
  const password = process.env.QA_DB_PASSWORD;
  const database = process.env.QA_DB_NAME;
  if (!host || !user || !database) {
    console.log(JSON.stringify({
      skipped: true,
      reason: 'missing_QA_DB_HOST_or_USER_or_NAME',
      hint: 'Set QA_DB_* or SKIP_URGENT_DB_SMOKE=1',
    }));
    process.exit(0);
  }

  let mysql;
  try {
    mysql = require('mysql2/promise');
  } catch {
    console.log(JSON.stringify({ skipped: true, reason: 'mysql2_not_installed' }));
    process.exit(0);
  }

  const pool = mysql.createPool({
    host,
    user,
    password: password ?? '',
    database,
    connectionLimit: 2,
  });

  try {
    await countUrgentNotifications(pool, 0);
    console.log(JSON.stringify({ pass: true, query: 'countUrgentNotifications' }));
    process.exit(0);
  } catch (err) {
    console.log(JSON.stringify({ pass: false, ...formatDbError(err) }));
    process.exit(1);
  } finally {
    await pool.end();
  }
}

main();
