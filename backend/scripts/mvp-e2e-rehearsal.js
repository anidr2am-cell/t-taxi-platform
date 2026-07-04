#!/usr/bin/env node
/**
 * Run MVP manual E2E rehearsal against local/staging DB + HTTP routes.
 *
 * Prerequisites:
 *   - MySQL migrated
 *   - npm run seed:mvp-demo (for seeded status spot-checks)
 *
 * Usage:
 *   node scripts/mvp-e2e-rehearsal.js
 *   node scripts/mvp-e2e-rehearsal.js --service-only
 */
const path = require('path');

function parseArgs(argv) {
  return { serviceOnly: argv.includes('--service-only') };
}

async function main() {
  require('dotenv').config({
    path: path.join(__dirname, '../.env'),
    override: true,
  });

  if (process.env.NODE_ENV === 'production') {
    throw new Error('mvp-e2e-rehearsal.js must not run in production');
  }

  const args = parseArgs(process.argv.slice(2));
  const { DEMO_ADMIN, DEMO_DRIVER } = require('./mvpDemo/fixtures');
  const { runMvpE2eRehearsal, formatReport } = require('./mvpDemo/rehearsal');
  const container = require('../src/helpers/container');
  const database = require('../src/config/database');
  const app = args.serviceOnly ? null : require('../src/app');

  const pool = database.pool;
  const [adminRows] = await pool.query(
    `
      SELECT id, email, role
      FROM users
      WHERE email = ? AND deleted_at IS NULL
      LIMIT 1
    `,
    [DEMO_ADMIN.email],
  );
  const [driverRows] = await pool.query(
    `
      SELECT d.id AS driverId, d.user_id AS userId, d.phone
      FROM drivers d
      INNER JOIN users u ON u.id = d.user_id
      WHERE u.email = ? AND d.deleted_at IS NULL AND u.deleted_at IS NULL
      LIMIT 1
    `,
    [DEMO_DRIVER.email],
  );

  const report = await runMvpE2eRehearsal({
    pool,
    bookingService: container.get('bookingService'),
    adminDispatchService: container.get('adminDispatchService'),
    driverTripFlowService: container.get('driverTripFlowService'),
    guestBookingLookupService: container.get('guestBookingLookupService'),
    adminUser: adminRows[0] ?? null,
    driver: driverRows[0] ?? null,
    app,
  });

  console.log(formatReport(report));
  if (!report.passed) {
    process.exitCode = 1;
  }
}

if (require.main === module) {
  main()
    .catch((err) => {
      console.error(`Rehearsal failed: ${err.message}`);
      process.exit(1);
    })
    .finally(async () => {
      const database = require('../src/config/database');
      await database.pool.end();
    });
}

module.exports = { main, parseArgs };
