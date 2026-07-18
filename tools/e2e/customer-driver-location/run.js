#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const {
  ACTIVE_STATUSES,
  E2E_MARKER,
  NetworkAudit,
  TERMINAL_STATUSES,
  assertCleanupCandidate,
  buildBookingPayload,
  buildConfig,
  createRunId,
  loadEnvFile,
  mergeEnv,
  redact,
} = require('./core');

function parseArgs(argv = process.argv.slice(2)) {
  return {
    dryRun: argv.includes('--dry-run'),
    headed: argv.includes('--headed'),
    keepFixture: argv.includes('--keep-fixture'),
    project: valueAfter(argv, '--project') || 'chromium',
    grep: valueAfter(argv, '--grep') || '',
  };
}

function valueAfter(argv, name) {
  const direct = argv.find((arg) => arg.startsWith(`${name}=`));
  if (direct) return direct.slice(name.length + 1);
  const index = argv.indexOf(name);
  return index >= 0 ? argv[index + 1] : '';
}

function apiUrl(config, pathName) {
  return `${config.backendUrl}${pathName}`;
}

async function requestJson(config, pathName, options = {}) {
  const response = await fetch(apiUrl(config, pathName), {
    ...options,
    headers: {
      accept: 'application/json',
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok) {
    const safe = redact(body);
    throw new Error(`${pathName} failed HTTP ${response.status}: ${JSON.stringify(safe)}`);
  }
  return body?.data ?? body;
}

async function login(config, email, password) {
  const data = await requestJson(config, '/api/v1/auth/login', {
    method: 'POST',
    body: JSON.stringify({ email, password }),
  });
  if (!data?.accessToken) throw new Error('Login response did not contain accessToken');
  return data;
}

function bearer(token) {
  return { authorization: `Bearer ${token}` };
}

async function prepareFixture(config, runId) {
  const admin = await login(config, config.adminEmail, config.adminPassword);
  const driver = await login(config, config.driverEmail, config.driverPassword);
  const payload = buildBookingPayload(runId, config.customerPhone);

  const booking = await requestJson(config, '/api/v1/bookings', {
    method: 'POST',
    body: JSON.stringify(payload),
  });
  const bookingNumber = booking.bookingNumber;
  if (!bookingNumber) throw new Error('Booking creation did not return bookingNumber');

  const lookup = await requestJson(config, '/api/v1/public/bookings/lookup', {
    method: 'POST',
    body: JSON.stringify({ bookingNumber, phone: config.customerPhone }),
  });

  await requestJson(config, `/api/v1/admin/bookings/${bookingNumber}/assign-driver`, {
    method: 'POST',
    headers: bearer(admin.accessToken),
    body: JSON.stringify({
      driverId: config.driverId,
      assignmentReason: `${E2E_MARKER} ${runId}`,
    }),
  });

  return {
    runId,
    bookingNumber,
    bookingId: lookup.bookingId || lookup.id || booking.bookingId || booking.id,
    guestAccessToken: lookup.guestAccessToken,
    customerPhone: config.customerPhone,
    customerName: payload.customer.name,
    marker: payload.additionalRequests,
    adminToken: admin.accessToken,
    driverToken: driver.accessToken,
  };
}

async function cleanupFixture(config, fixture) {
  if (!fixture) return;
  assertCleanupCandidate(fixture);
  await requestJson(config, '/api/v1/admin/bookings/archive', {
    method: 'POST',
    headers: bearer(fixture.adminToken),
    body: JSON.stringify({
      bookingNumbers: [fixture.bookingNumber],
      reason: 'TEST_DATA',
    }),
  });
}

async function transitionDriver(config, fixture, action) {
  await requestJson(config, `/api/v1/driver/bookings/${fixture.bookingNumber}/${action}`, {
    method: 'POST',
    headers: bearer(fixture.driverToken),
    body: JSON.stringify({ reason: `${E2E_MARKER} ${fixture.runId}` }),
  });
}

async function sendLocation(config, fixture, latitude, longitude, recordedAt = new Date()) {
  await requestJson(config, '/api/v1/driver/location', {
    method: 'POST',
    headers: bearer(fixture.driverToken),
    body: JSON.stringify({
      latitude,
      longitude,
      accuracyMeters: 8,
      heading: 90,
      speedMetersPerSecond: 0,
      recordedAt: recordedAt.toISOString(),
    }),
  });
}

async function openLookupPage(config, fixture, args) {
  const { chromium, firefox, webkit } = require('@playwright/test');
  const browserType = { chromium, firefox, webkit }[args.project] || chromium;
  const browser = await browserType.launch({ headless: !args.headed });
  const contexts = [];
  try {
    for (const viewport of [
      { width: 360, height: 800 },
      { width: 390, height: 844 },
      { width: 430, height: 932 },
      { width: 1280, height: 800 },
    ]) {
      const context = await browser.newContext({
        viewport,
        locale: 'en-US',
      });
      contexts.push(context);
      const audit = new NetworkAudit();
      const page = await context.newPage();
      const consoleErrors = [];
      page.on('console', (message) => {
        if (['error'].includes(message.type())) {
          consoleErrors.push(message.text());
        }
      });
      page.on('pageerror', (err) => consoleErrors.push(err.message));
      page.on('request', (request) => {
        const url = request.url();
        if (url.includes('/api/v1/') || url.includes('/socket.io')) {
          audit.recordRequest(url, request.method());
        }
      });

      await page.goto(`${config.frontendUrl}/booking/lookup`, { waitUntil: 'networkidle' });
      const fields = page.getByRole('textbox');
      await fields.nth(0).fill(fixture.bookingNumber);
      await fields.nth(1).fill(fixture.customerPhone);
      await page.getByRole('button', { name: /find booking|find|lookup|search/i }).click();
      await page.waitForResponse((response) => response.url().includes('/api/v1/public/bookings/lookup'));
      await page.waitForTimeout(1200);
      audit.assertLocationPollingObserved();
      audit.assertNoRepeatedGuestLookup(1);

      await transitionDriver(config, fixture, 'start-route');
      await sendLocation(config, fixture, 12.9236, 100.8825);
      await page.waitForTimeout(config.pollIntervalMs + 1500);
      await sendLocation(config, fixture, 12.9241, 100.8831);
      await page.waitForTimeout(1500);
      audit.assertNoRepeatedGuestLookup(1);

      await transitionDriver(config, fixture, 'arrive');
      await page.waitForTimeout(1000);
      await transitionDriver(config, fixture, 'mark-picked-up');
      await page.waitForTimeout(1000);
      await transitionDriver(config, fixture, 'end-trip');
      await page.waitForTimeout(config.pollIntervalMs + 1500);

      if (consoleErrors.length) {
        throw new Error(`Browser console errors at ${viewport.width}px: ${consoleErrors.join('; ')}`);
      }
      console.log(`PASS browser viewport ${viewport.width}x${viewport.height}`);
    }
  } finally {
    await Promise.allSettled(contexts.map((context) => context.close()));
    await browser.close();
  }
}

async function main() {
  const args = parseArgs();
  const env = mergeEnv(loadEnvFile(), process.env);
  if (args.headed) env.TRIDE_E2E_HEADED = '1';
  if (args.keepFixture) env.TRIDE_E2E_KEEP_FIXTURE = '1';
  const config = buildConfig(env, { requireSecrets: !args.dryRun });
  const runId = createRunId();
  const dryRunSummary = redact({
    runId,
    target: config.target,
    frontendUrl: config.frontendUrl,
    backendUrl: config.backendUrl,
    adminEmail: config.adminEmail,
    driverEmail: config.driverEmail,
    driverId: config.driverId,
    customerPhone: config.customerPhone,
    activeStatuses: [...ACTIVE_STATUSES],
    terminalStatuses: [...TERMINAL_STATUSES],
  });

  if (args.dryRun) {
    console.log(JSON.stringify({ dryRun: true, ...dryRunSummary }, null, 2));
    return;
  }

  fs.mkdirSync(config.artifactDir, { recursive: true });
  let fixture;
  try {
    fixture = await prepareFixture(config, runId);
    await openLookupPage(config, fixture, args);
  } finally {
    if (fixture && !args.keepFixture) {
      await cleanupFixture(config, fixture);
      console.log(`Cleanup archived test fixture for ${fixture.runId}`);
    } else if (fixture) {
      const markerPath = path.join(config.artifactDir, `${fixture.runId}-fixture.json`);
      fs.writeFileSync(markerPath, `${JSON.stringify(redact(fixture), null, 2)}\n`);
      console.log(`Fixture kept for debugging. Redacted marker: ${markerPath}`);
    }
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(redact(err.message));
    process.exit(1);
  });
}

module.exports = {
  cleanupFixture,
  main,
  parseArgs,
  prepareFixture,
  sendLocation,
  transitionDriver,
};
