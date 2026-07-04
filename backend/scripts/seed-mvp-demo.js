#!/usr/bin/env node
/**
 * Seed MVP demo admin, driver, and status-scenario bookings (local/staging only).
 *
 * Examples:
 *   node scripts/seed-mvp-demo.js
 *   node scripts/seed-mvp-demo.js --scenarios=PENDING,DRIVER_ASSIGNED,COMPLETED
 *   node scripts/seed-mvp-demo.js --skip-bookings
 */
const path = require('path');

function parseArgs(argv) {
  const args = {
    skipAdmin: false,
    skipDriver: false,
    skipBookings: false,
    scenarios: null,
  };

  for (const item of argv) {
    if (item === '--skip-admin') args.skipAdmin = true;
    else if (item === '--skip-driver') args.skipDriver = true;
    else if (item === '--skip-bookings') args.skipBookings = true;
    else if (item.startsWith('--scenarios=')) {
      args.scenarios = item.slice('--scenarios='.length);
    } else if (item.startsWith('--')) {
      throw new Error(`Unknown option: ${item}`);
    }
  }

  return args;
}

async function applyScenarioSteps({
  scenario,
  bookingNumber,
  adminUser,
  driver,
  services,
}) {
  const actor = { id: adminUser.id, role: adminUser.role };
  const {
    adminDispatchService,
    driverTripFlowService,
    bookingStatusService,
  } = services;

  for (const step of scenario.steps) {
    if (step === 'assign') {
      await adminDispatchService.assignDriver(
        bookingNumber,
        { driverId: driver.driverId, assignmentReason: 'MVP demo seed' },
        adminUser,
      );
      continue;
    }

    if (step === 'onRoute') {
      await driverTripFlowService.startOnRoute(driver.userId, bookingNumber);
      continue;
    }

    if (step === 'arrived') {
      await driverTripFlowService.markArrived(driver.userId, bookingNumber);
      continue;
    }

    if (step === 'complete') {
      await driverTripFlowService.completeTrip(driver.userId, bookingNumber);
      continue;
    }

    if (step === 'cancel') {
      await bookingStatusService.transition(
        bookingNumber,
        { status: scenario.status, reason: 'MVP demo seed cancelled' },
        actor,
      );
    }
  }
}

async function main() {
  require('dotenv').config({
    path: path.join(__dirname, '../.env'),
    override: true,
  });

  if (process.env.NODE_ENV === 'production') {
    throw new Error('seed-mvp-demo.js must not run in production');
  }

  const args = parseArgs(process.argv.slice(2));
  const {
    DEMO_ADMIN,
    DEMO_DRIVER,
    STATUS_SCENARIOS,
    buildBookingPayload,
    customerPhoneForIndex,
    parseScenarioFilter,
  } = require('./mvpDemo/fixtures');
  const { upsertDemoAdmin, upsertDemoDriver } = require('./mvpDemo/accounts');
  const container = require('../src/helpers/container');
  const database = require('../src/config/database');

  const pool = database.pool;
  const bookingService = container.get('bookingService');
  const adminDispatchService = container.get('adminDispatchService');
  const driverTripFlowService = container.get('driverTripFlowService');
  const bookingStatusService = container.get('bookingStatusService');

  const summary = {
    admin: null,
    driver: null,
    bookings: [],
  };

  if (!args.skipAdmin) {
    summary.admin = await upsertDemoAdmin(pool);
    console.log(`Admin ready: ${DEMO_ADMIN.email} (${summary.admin.role})`);
  } else {
    const [rows] = await pool.query(
      `
        SELECT id, email, role
        FROM users
        WHERE email = ? AND deleted_at IS NULL
        LIMIT 1
      `,
      [DEMO_ADMIN.email],
    );
    summary.admin = rows[0] ?? null;
    if (!summary.admin) {
      throw new Error('Admin user missing. Run without --skip-admin first.');
    }
    console.log(`Using existing admin: ${summary.admin.email}`);
  }

  if (!args.skipDriver) {
    summary.driver = await upsertDemoDriver(pool);
    console.log(`Driver ready: ${DEMO_DRIVER.phone} / ${DEMO_DRIVER.email}`);
  } else {
    const [rows] = await pool.query(
      `
        SELECT d.id AS driverId, d.user_id AS userId, d.phone, u.email
        FROM drivers d
        INNER JOIN users u ON u.id = d.user_id
        WHERE u.email = ? AND d.deleted_at IS NULL AND u.deleted_at IS NULL
        LIMIT 1
      `,
      [DEMO_DRIVER.email],
    );
    summary.driver = rows[0] ?? null;
    if (!summary.driver) {
      throw new Error('Driver missing. Run without --skip-driver first.');
    }
    console.log(`Using existing driver: ${summary.driver.phone}`);
  }

  if (args.skipBookings) {
    printSummary(summary, DEMO_ADMIN, DEMO_DRIVER);
    return;
  }

  const scenarios = parseScenarioFilter(args.scenarios);
  if (!scenarios.length) {
    throw new Error('No matching scenarios. Check --scenarios value.');
  }

  for (let index = 0; index < scenarios.length; index += 1) {
    const scenario = scenarios[index];
    const customerPhone = customerPhoneForIndex(index);
    const customerName = `MVP Guest ${scenario.status}`;
    const payload = buildBookingPayload({
      customerName,
      customerPhone,
      label: scenario.status,
    });

    const created = await bookingService.createBooking(payload, null);
    await applyScenarioSteps({
      scenario,
      bookingNumber: created.bookingNumber,
      adminUser: summary.admin,
      driver: summary.driver,
      services: {
        adminDispatchService,
        driverTripFlowService,
        bookingStatusService,
      },
    });

    summary.bookings.push({
      status: scenario.status,
      bookingNumber: created.bookingNumber,
      customerName,
      customerPhone,
      guestAccessToken: created.guestAccessToken ?? null,
    });

    console.log(`Booking ${created.bookingNumber} → ${scenario.status}`);
  }

  printSummary(summary, DEMO_ADMIN, DEMO_DRIVER);
}

function printSummary(summary, adminDefaults, driverDefaults) {
  console.log('\n=== MVP demo seed summary ===');
  console.log(`Admin login (email): ${adminDefaults.email} / ${adminDefaults.password}`);
  console.log(`Driver login (phone): ${driverDefaults.phone} / ${driverDefaults.password}`);
  console.log('\nGuest lookup (bookingNumber + phone):');
  for (const booking of summary.bookings) {
    console.log(
      `  ${booking.status.padEnd(16)} ${booking.bookingNumber}  ${booking.customerPhone}`,
    );
  }
  console.log('\nSee docs/MVP_DEV_SETUP.md and docs/MVP_MANUAL_E2E_CHECKLIST.md');
}

if (require.main === module) {
  main()
    .catch((err) => {
      console.error(`Failed: ${err.message}`);
      process.exit(1);
    })
    .finally(async () => {
      const database = require('../src/config/database');
      await database.pool.end();
    });
}

module.exports = {
  applyScenarioSteps,
  parseArgs,
};
