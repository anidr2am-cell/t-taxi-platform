#!/usr/bin/env node
/**
 * Apply migration 61 (if needed) and verify contact lookup uses the phone-digits index.
 *
 * Usage (from backend/):
 *   node scripts/verify-contact-lookup-index.js
 *   node scripts/verify-contact-lookup-index.js --skip-migration
 *   node scripts/verify-contact-lookup-index.js --self-test
 *
 * Requires DB_* env (loads backend/.env when present).
 */
const path = require('path');
const fs = require('fs');
const mysql = require('mysql2/promise');

const rootDir = path.resolve(__dirname, '..');
const envPath = path.join(rootDir, '.env');
if (fs.existsSync(envPath)) {
  require('dotenv').config({ path: envPath });
}

const skipMigration = process.argv.includes('--skip-migration');
const selfTest = process.argv.includes('--self-test');

async function createConnection() {
  return mysql.createConnection({
    host: process.env.DB_HOST || '127.0.0.1',
    port: Number(process.env.DB_PORT || 3306),
    user: process.env.DB_USER,
    password: process.env.DB_PASSWORD,
    database: process.env.DB_NAME,
  });
}

async function hasBookingsColumn(conn, columnName) {
  const [rows] = await conn.query(
    `
      SELECT 1 AS present
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'bookings'
        AND COLUMN_NAME = ?
    `,
    [columnName],
  );
  return rows.length > 0;
}

async function applyMigration(conn) {
  if (!(await hasBookingsColumn(conn, 'is_archived'))) {
    throw new Error(
      'bookings.is_archived is missing; apply migration 39 before migration 61',
    );
  }

  const [columns] = await conn.query(
    `
      SELECT 1 AS present
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'bookings'
        AND COLUMN_NAME = 'customer_phone_digits'
    `,
  );
  if (columns.length === 0) {
    await conn.query(`
      ALTER TABLE bookings
        ADD COLUMN customer_phone_digits VARCHAR(30)
        GENERATED ALWAYS AS (REGEXP_REPLACE(customer_phone, '[^0-9]', '')) STORED
        AFTER customer_phone
    `);
    console.log('Added customer_phone_digits generated column.');
  }

  const [legacyIndex] = await conn.query(
    `
      SELECT 1 AS present
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'bookings'
        AND INDEX_NAME = 'idx_bookings_contact_lookup'
    `,
  );
  if (legacyIndex.length > 0) {
    await conn.query('ALTER TABLE bookings DROP INDEX idx_bookings_contact_lookup');
    console.log('Dropped legacy idx_bookings_contact_lookup index.');
  }

  const [newIndex] = await conn.query(
    `
      SELECT 1 AS present
      FROM information_schema.STATISTICS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'bookings'
        AND INDEX_NAME = 'idx_bookings_contact_lookup_phone_digits'
    `,
  );
  if (newIndex.length === 0) {
    await conn.query(`
      ALTER TABLE bookings
        ADD INDEX idx_bookings_contact_lookup_phone_digits (
          customer_phone_digits,
          is_archived,
          deleted_at
        )
    `);
    console.log('Added idx_bookings_contact_lookup_phone_digits index.');
  }
}

async function assertExplainUsesIndex(conn, { tableName, indexName, explainSql, params }) {
  const [plan] = await conn.query(explainSql, params);
  console.log(`\nEXPLAIN (${tableName}):`);
  console.table(plan);

  const targetRow = plan.find((row) => row.table === tableName) || plan[0];
  const type = String(targetRow?.type ?? '').toUpperCase();
  const key = targetRow?.key ?? null;

  if (type === 'ALL') {
    throw new Error(`Expected index usage on ${tableName}, got type=${type}, key=${key}`);
  }
  if (key !== indexName) {
    throw new Error(`Expected ${indexName}, got type=${type}, key=${key}`);
  }

  console.log(`OK: ${tableName} access type=${type}, key=${key}`);
}

async function runSelfTest(conn) {
  const tableName = 'zz_contact_lookup_explain_probe';
  await conn.query(`DROP TABLE IF EXISTS ${tableName}`);
  await conn.query(`
    CREATE TABLE ${tableName} (
      id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
      customer_phone VARCHAR(30) NOT NULL,
      customer_phone_digits VARCHAR(30)
        GENERATED ALWAYS AS (REGEXP_REPLACE(customer_phone, '[^0-9]', '')) STORED,
      is_archived TINYINT NOT NULL DEFAULT 0,
      deleted_at DATETIME NULL DEFAULT NULL,
      scheduled_pickup_at DATETIME NULL DEFAULT NULL,
      PRIMARY KEY (id),
      KEY idx_bookings_contact_lookup_phone_digits (
        customer_phone_digits,
        is_archived,
        deleted_at
      )
    ) ENGINE=InnoDB
  `);
  await conn.query(
    `
      INSERT INTO ${tableName} (customer_phone, is_archived, deleted_at, scheduled_pickup_at)
      VALUES
        ('+66 81 234 5678', 0, NULL, '2026-07-01 09:30:00'),
        ('66812345678', 0, NULL, '2026-06-01 09:30:00'),
        ('66812345679', 0, NULL, '2026-05-01 09:30:00')
    `,
  );

  try {
    await assertExplainUsesIndex(conn, {
      tableName,
      indexName: 'idx_bookings_contact_lookup_phone_digits',
      explainSql: `
        EXPLAIN
        SELECT b.id
        FROM ${tableName} b
        WHERE b.customer_phone_digits = ?
          AND b.deleted_at IS NULL
          AND b.is_archived = 0
        ORDER BY b.scheduled_pickup_at DESC
        LIMIT ?
      `,
      params: ['66812345678', 20],
    });
  } finally {
    await conn.query(`DROP TABLE IF EXISTS ${tableName}`);
  }
}

async function runBookingsExplain(conn) {
  const [columns] = await conn.query(
    `
      SELECT COLUMN_NAME, EXTRA
      FROM information_schema.COLUMNS
      WHERE TABLE_SCHEMA = DATABASE()
        AND TABLE_NAME = 'bookings'
        AND COLUMN_NAME = 'customer_phone_digits'
    `,
  );
  if (columns.length === 0) {
    throw new Error('customer_phone_digits column is missing on bookings');
  }
  console.log('Column:', columns[0].COLUMN_NAME, columns[0].EXTRA || '');

  const [indexes] = await conn.query(
    `
      SHOW INDEX FROM bookings
      WHERE Key_name = 'idx_bookings_contact_lookup_phone_digits'
    `,
  );
  if (indexes.length === 0) {
    throw new Error('idx_bookings_contact_lookup_phone_digits index is missing on bookings');
  }
  console.log('Index columns:', indexes.map((row) => row.Column_name).join(', '));

  await assertExplainUsesIndex(conn, {
    tableName: 'bookings',
    indexName: 'idx_bookings_contact_lookup_phone_digits',
    explainSql: `
      EXPLAIN
      SELECT b.id
      FROM bookings b
      WHERE b.customer_phone_digits = ?
        AND b.deleted_at IS NULL
        AND b.is_archived = 0
      ORDER BY b.scheduled_pickup_at DESC
      LIMIT ?
    `,
    params: ['66812345678', 20],
  });
}

async function main() {
  const conn = await createConnection();

  try {
    if (selfTest) {
      await runSelfTest(conn);
      return;
    }

    if (!skipMigration) {
      await applyMigration(conn);
      console.log('Migration 61 objects verified/applied.');
    }

    await runBookingsExplain(conn);
  } finally {
    await conn.end();
  }
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
