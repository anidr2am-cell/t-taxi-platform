/**
 * MVP manual E2E rehearsal — service + HTTP checks against real DB (dev/staging only).
 */
const request = require('supertest');
const BOOKING_STATUS = require('../../src/constants/reservationStatus');
const {
  STATUS_SCENARIOS,
  buildBookingPayload,
  customerPhoneForIndex,
  DEMO_ADMIN,
  DEMO_DRIVER,
} = require('./fixtures');

function stepResult(name, ok, detail = null) {
  return { name, ok, detail };
}

async function login(requestFn, credentials) {
  const body = credentials.email
    ? { email: credentials.email, password: credentials.password }
    : { phone: credentials.phone, password: credentials.password };
  const res = await requestFn.post('/api/v1/auth/login').send(body);
  if (res.status !== 200) {
    throw new Error(`Login failed (${res.status}): ${res.body?.message ?? 'unknown'}`);
  }
  return res.body.data.accessToken;
}

async function guestLookupHttp(requestFn, bookingNumber, phone) {
  const res = await requestFn
    .post('/api/v1/public/bookings/lookup')
    .send({ bookingNumber, phone });
  if (res.status !== 200) {
    throw new Error(`Guest lookup failed (${res.status}): ${res.body?.message ?? 'unknown'}`);
  }
  return res.body.data;
}

async function guestLookupService(guestBookingLookupService, bookingNumber, phone) {
  return guestBookingLookupService.lookup({ bookingNumber, phone });
}

async function findLatestSeededBookings(pool) {
  const bookings = [];
  for (let index = 0; index < STATUS_SCENARIOS.length; index += 1) {
    const scenario = STATUS_SCENARIOS[index];
    const phone = customerPhoneForIndex(index);
    const [rows] = await pool.query(
      `
        SELECT booking_number, status, customer_phone
        FROM bookings
        WHERE customer_phone = ? AND deleted_at IS NULL
        ORDER BY created_at DESC
        LIMIT 1
      `,
      [phone],
    );
    if (!rows.length) {
      bookings.push({ scenario: scenario.status, phone, missing: true });
    } else {
      bookings.push({
        scenario: scenario.status,
        phone,
        bookingNumber: rows[0].booking_number,
        dbStatus: rows[0].status,
      });
    }
  }
  return bookings;
}

async function verifySeededLookups({
  pool,
  guestBookingLookupService,
  requestFn,
  useHttp,
}) {
  const seeded = await findLatestSeededBookings(pool);
  const steps = [];

  for (const row of seeded) {
    const label = `seed lookup ${row.scenario}`;
    if (row.missing) {
      steps.push(stepResult(label, false, `No booking for ${row.phone} — run seed:mvp-demo`));
      continue;
    }

    try {
      const lookup = useHttp
        ? await guestLookupHttp(requestFn, row.bookingNumber, row.phone)
        : await guestLookupService(guestBookingLookupService, row.bookingNumber, row.phone);

      const statusOk = lookup.status === row.scenario;
      const dbOk = row.dbStatus === row.scenario;
      steps.push(stepResult(
        label,
        statusOk && dbOk,
        statusOk && dbOk
          ? `${row.bookingNumber} → ${lookup.status}`
          : `expected ${row.scenario}, lookup=${lookup.status}, db=${row.dbStatus}`,
      ));
    } catch (err) {
      steps.push(stepResult(label, false, err.message));
    }
  }

  return steps;
}

function uniqueRehearsalPhone() {
  const suffix = String(Date.now()).slice(-8);
  return `+6681${suffix.slice(0, 8)}`;
}

async function runHappyPath({
  pool,
  bookingService,
  adminDispatchService,
  driverTripFlowService,
  guestBookingLookupService,
  adminUser,
  driver,
  requestFn,
  useHttp,
}) {
  const steps = [];
  const customerPhone = uniqueRehearsalPhone();
  const payload = buildBookingPayload({
    customerName: 'MVP E2E Rehearsal',
    customerPhone,
    label: 'E2E happy path',
  });

  let bookingNumber;
  try {
    if (useHttp) {
      const res = await requestFn.post('/api/v1/bookings').send(payload);
      if (res.status !== 201) {
        throw new Error(`Create booking HTTP ${res.status}: ${res.body?.message ?? 'unknown'}`);
      }
      bookingNumber = res.body.data.bookingNumber;
    } else {
      const created = await bookingService.createBooking(payload, null);
      bookingNumber = created.bookingNumber;
    }
    steps.push(stepResult('happy path create booking', true, bookingNumber));
  } catch (err) {
    steps.push(stepResult('happy path create booking', false, err.message));
    return steps;
  }

  const assertLookup = async (expectedStatus, label) => {
    try {
      const lookup = useHttp
        ? await guestLookupHttp(requestFn, bookingNumber, customerPhone)
        : await guestLookupService(guestBookingLookupService, bookingNumber, customerPhone);
      const ok = lookup.status === expectedStatus;
      steps.push(stepResult(label, ok, ok ? lookup.status : `expected ${expectedStatus}, got ${lookup.status}`));
      return ok;
    } catch (err) {
      steps.push(stepResult(label, false, err.message));
      return false;
    }
  };

  await assertLookup(BOOKING_STATUS.PENDING, 'happy path guest lookup PENDING');

  try {
    if (useHttp) {
      const adminToken = await login(requestFn, { email: DEMO_ADMIN.email, password: DEMO_ADMIN.password });
      const assignRes = await requestFn
        .post(`/api/v1/admin/bookings/${bookingNumber}/assign-driver`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ driverId: driver.driverId, assignmentReason: 'MVP E2E rehearsal' });
      if (assignRes.status !== 200) {
        throw new Error(`Assign HTTP ${assignRes.status}: ${assignRes.body?.message ?? 'unknown'}`);
      }
    } else {
      await adminDispatchService.assignDriver(
        bookingNumber,
        { driverId: driver.driverId, assignmentReason: 'MVP E2E rehearsal' },
        adminUser,
      );
    }
    steps.push(stepResult('happy path admin assign', true, bookingNumber));
  } catch (err) {
    steps.push(stepResult('happy path admin assign', false, err.message));
    return steps;
  }

  await assertLookup(BOOKING_STATUS.DRIVER_ASSIGNED, 'happy path guest lookup DRIVER_ASSIGNED');

  const driverActions = [
    { fn: 'startOnRoute', route: 'start-route', status: BOOKING_STATUS.ON_ROUTE, label: 'ON_ROUTE' },
    { fn: 'markArrived', route: 'arrive', status: BOOKING_STATUS.DRIVER_ARRIVED, label: 'DRIVER_ARRIVED' },
    { fn: 'completeTrip', route: 'complete', status: BOOKING_STATUS.COMPLETED, label: 'COMPLETED' },
  ];

  let driverToken = null;
  if (useHttp) {
    try {
      driverToken = await login(requestFn, { phone: DEMO_DRIVER.phone, password: DEMO_DRIVER.password });
    } catch (err) {
      steps.push(stepResult('happy path driver login', false, err.message));
      return steps;
    }
  }

  for (const action of driverActions) {
    try {
      if (useHttp) {
        const res = await requestFn
          .post(`/api/v1/driver/bookings/${bookingNumber}/${action.route}`)
          .set('Authorization', `Bearer ${driverToken}`);
        if (res.status !== 200) {
          throw new Error(`${action.route} HTTP ${res.status}: ${res.body?.message ?? 'unknown'}`);
        }
        if (res.body.data?.status && res.body.data.status !== action.status) {
          throw new Error(`expected ${action.status}, got ${res.body.data.status}`);
        }
      } else {
        await driverTripFlowService[action.fn](driver.userId, bookingNumber);
      }
      steps.push(stepResult(`happy path driver ${action.label}`, true, bookingNumber));
      await assertLookup(action.status, `happy path guest lookup ${action.label}`);
    } catch (err) {
      steps.push(stepResult(`happy path driver ${action.label}`, false, err.message));
      return steps;
    }
  }

  try {
    if (useHttp) {
      const detailRes = await requestFn
        .get(`/api/v1/driver/bookings/${bookingNumber}`)
        .set('Authorization', `Bearer ${driverToken}`);
      if (detailRes.status !== 200) {
        throw new Error(`Driver detail HTTP ${detailRes.status}`);
      }
      const hasActions = detailRes.body.data?.allowedActions?.length > 0;
      steps.push(stepResult('happy path driver detail terminal', !hasActions, hasActions ? 'actions still shown' : 'read-only'));
    } else {
      const [rows] = await pool.query(
        'SELECT status FROM bookings WHERE booking_number = ? LIMIT 1',
        [bookingNumber],
      );
      steps.push(stepResult(
        'happy path final DB status',
        rows[0]?.status === BOOKING_STATUS.COMPLETED,
        rows[0]?.status ?? 'missing',
      ));
    }
  } catch (err) {
    steps.push(stepResult('happy path terminal check', false, err.message));
  }

  return steps;
}

async function runMvpE2eRehearsal(deps) {
  const {
    pool,
    bookingService,
    adminDispatchService,
    driverTripFlowService,
    guestBookingLookupService,
    adminUser,
    driver,
    app = null,
  } = deps;

  const requestFn = app ? request(app) : null;
  const useHttp = Boolean(app);

  const steps = [];

  if (!adminUser) {
    steps.push(stepResult('demo admin present', false, 'Run seed:mvp-demo first'));
    return summarize(steps);
  }
  if (!driver) {
    steps.push(stepResult('demo driver present', false, 'Run seed:mvp-demo first'));
    return summarize(steps);
  }

  steps.push(stepResult('demo admin present', true, adminUser.email));
  steps.push(stepResult('demo driver present', true, driver.phone ?? DEMO_DRIVER.phone));

  const seedSteps = await verifySeededLookups({
    pool,
    guestBookingLookupService,
    requestFn,
    useHttp,
  });
  steps.push(...seedSteps);

  const happySteps = await runHappyPath({
    pool,
    bookingService,
    adminDispatchService,
    driverTripFlowService,
    guestBookingLookupService,
    adminUser,
    driver,
    requestFn,
    useHttp,
  });
  steps.push(...happySteps);

  return summarize(steps);
}

function summarize(steps) {
  const failed = steps.filter((s) => !s.ok);
  return {
    passed: failed.length === 0,
    total: steps.length,
    failedCount: failed.length,
    steps,
  };
}

function formatReport(report) {
  const lines = ['=== MVP E2E rehearsal ===', ''];
  for (const step of report.steps) {
    const mark = step.ok ? 'PASS' : 'FAIL';
    const detail = step.detail ? ` — ${step.detail}` : '';
    lines.push(`[${mark}] ${step.name}${detail}`);
  }
  lines.push('');
  lines.push(report.passed
    ? `All ${report.total} checks passed.`
    : `${report.failedCount} of ${report.total} checks failed.`);
  return lines.join('\n');
}

module.exports = {
  runMvpE2eRehearsal,
  findLatestSeededBookings,
  formatReport,
  stepResult,
};
