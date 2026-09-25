#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  URGENT_RUNNER_SCHEMA_REQUIREMENTS,
} = require('./urgent-qa-db-markers.cjs');

const REPO_ROOT = process.env.REPO_ROOT || path.join(__dirname, '..', '..', '..');
const DATABASE_DIR = process.env.DATABASE_DIR || path.join(REPO_ROOT, 'database');

function loadDatabaseSqlText() {
  if (!fs.existsSync(DATABASE_DIR)) {
    throw new Error(`database dir missing: ${DATABASE_DIR}`);
  }
  return fs
    .readdirSync(DATABASE_DIR)
    .filter((name) => name.endsWith('.sql'))
    .sort()
    .map((name) => fs.readFileSync(path.join(DATABASE_DIR, name), 'utf8'))
    .join('\n');
}

function inventoryFromSql(sqlText) {
  const tables = new Map();

  const addColumn = (table, column) => {
    const key = table.toLowerCase();
    if (!tables.has(key)) tables.set(key, new Set());
    tables.get(key).add(column.toLowerCase());
  };

  const createRe = /CREATE TABLE IF NOT EXISTS\s+`?(\w+)`?\s*\(([\s\S]*?)\)\s*ENGINE/gi;
  let m;
  while ((m = createRe.exec(sqlText)) !== null) {
    const table = m[1];
    const body = m[2];
    for (const line of body.split('\n')) {
      const col = line.trim().match(/^`?(\w+)`?\s+/);
      if (col && !/^(PRIMARY|KEY|UNIQUE|CONSTRAINT|INDEX|FOREIGN)$/i.test(col[1])) {
        addColumn(table, col[1]);
      }
    }
  }

  const alterAddRe = /ALTER TABLE\s+`?(\w+)`?\s+ADD COLUMN\s+`?(\w+)`?/gi;
  while ((m = alterAddRe.exec(sqlText)) !== null) {
    addColumn(m[1], m[2]);
  }

  const modifyRe = /ALTER TABLE\s+`?(\w+)`?\s+MODIFY COLUMN\s+`?(\w+)`?/gi;
  while ((m = modifyRe.exec(sqlText)) !== null) {
    addColumn(m[1], m[2]);
  }

  return tables;
}

function scanRunnerSourcesForBannedRefs(root) {
  const files = [
    path.join(root, 'socket-qa', 'run-urgent-contact-dispatch-matrix.mjs'),
    path.join(root, 'socket-qa', 'run-urgent-gate-false-smoke.mjs'),
    path.join(root, 'urgent-qa-db-markers.cjs'),
  ];
  const hits = [];
  for (const file of files) {
    const text = fs.readFileSync(file, 'utf8');
    if (/(?:FROM|JOIN)\s+`?notification_types`?\b/i.test(text)) hits.push(path.basename(file));
  }
  return hits;
}

const sqlText = loadDatabaseSqlText();
const inventory = inventoryFromSql(sqlText);
const missing = [];
for (const req of URGENT_RUNNER_SCHEMA_REQUIREMENTS) {
  const cols = inventory.get(req.table.toLowerCase());
  if (!cols) {
    missing.push({ table: req.table, column: '*', reason: 'table_not_in_database_migrations' });
    continue;
  }
  for (const column of req.columns) {
    if (!cols.has(column.toLowerCase())) {
      missing.push({ table: req.table, column, reason: 'column_not_in_database_migrations' });
    }
  }
}

const banned = scanRunnerSourcesForBannedRefs(__dirname);
const hasNotificationTypesTable = /CREATE TABLE IF NOT EXISTS\s+`?notification_types`?/i.test(sqlText);

const report = {
  databaseDir: DATABASE_DIR,
  productHasNotificationTypesTable: hasNotificationTypesTable,
  bannedNotificationTypesRefInRunners: banned,
  missing,
  pass: missing.length === 0 && banned.length === 0 && !hasNotificationTypesTable,
};

console.log(JSON.stringify(report, null, 2));
process.exit(report.pass ? 0 : 1);
