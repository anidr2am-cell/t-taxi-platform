#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const {
  ACTIVE_STATUSES,
  E2E_MARKER,
  FixturePreparationError,
  FixtureRegistry,
  NetworkAudit,
  TERMINAL_STATUSES,
  assertServerCleanupCandidate,
  buildBookingPayload,
  buildConfig,
  createRunId,
  createViewportRunId,
  extractGuestAccess,
  loadEnvFile,
  mergeEnv,
  redact,
  serializeSafeError,
} = require('./core');

const VIEWPORTS = [
  { width: 360, height: 800 },
  { width: 390, height: 844 },
  { width: 430, height: 932 },
  { width: 1280, height: 800 },
];

function parseArgs(argv = process.argv.slice(2)) {
  return {
    dryRun: argv.includes('--dry-run'),
    headed: argv.includes('--headed'),
    keepFixture: argv.includes('--keep-fixture'),
    project: valueAfter(argv, '--project') || 'chromium',
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

function bearer(token) {
  return { authorization: `Bearer ${token}` };
}

function guestAccess(token) {
  return { 'X-Guest-Access-Token': token };
}

function assertE2EEmail(label, email) {
  const local = String(email || '').split('@')[0].toLowerCase();
  if (!local.includes('e2e') && !local.includes('test')) {
    throw new Error(`${label} must be a staging E2E/test account`);
  }
}

function assertFakeCustomerPhone(phone) {
  if (!/^\+?660{6,}\d+$/.test(String(phone || ''))) {
    throw new Error('TRIDE_E2E_CUSTOMER_PHONE must be a clearly fake Thai staging number');
  }
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

async function loadMe(config, accessToken) {
  return requestJson(config, '/api/v1/auth/me', {
    method: 'GET',
    headers: bearer(accessToken),
  });
}

async function loadDriverStatus(config, driverToken) {
  return requestJson(config, '/api/v1/driver/status', {
    method: 'GET',
    headers: bearer(driverToken),
  });
}

async function authenticateAndPreflight(config) {
  assertE2EEmail('Admin email', config.adminEmail);
  assertE2EEmail('Driver email', config.driverEmail);
  assertFakeCustomerPhone(config.customerPhone);

  const admin = await login(config, config.adminEmail, config.adminPassword);
  const driver = await login(config, config.driverEmail, config.driverPassword);
  const [adminMe, driverMe, driverStatus] = await Promise.all([
    loadMe(config, admin.accessToken),
    loadMe(config, driver.accessToken),
    loadDriverStatus(config, driver.accessToken),
  ]);

  const adminRole = String(adminMe?.role || adminMe?.user?.role || '').toUpperCase();
  if (!adminRole.includes('ADMIN')) {
    throw new Error('Configured admin account is not an admin role');
  }
  const driverRole = String(driverMe?.role || driverMe?.user?.role || '').toUpperCase();
  if (driverRole !== 'DRIVER') {
    throw new Error('Configured driver account is not a driver role');
  }
  if (Number(driverStatus.driverId) !== Number(config.driverId)) {
    throw new Error('TRIDE_E2E_DRIVER_ID does not match the logged-in driver account');
  }
  if (driverStatus.active !== true) {
    throw new Error('Configured E2E driver is not active');
  }
  if (driverStatus.hasActiveJob === true) {
    throw new Error('Configured E2E driver already has an active job; no fixture will be created');
  }

  return {
    adminToken: admin.accessToken,
    driverToken: driver.accessToken,
  };
}

async function prepareFixture(config, runId, auth, registry, viewport) {
  const payload = buildBookingPayload(runId, config.customerPhone);
  const fixture = registry.add({
    runId,
    viewport: `${viewport.width}x${viewport.height}`,
    bookingNumber: null,
    customerName: payload.customer.name,
    marker: payload.additionalRequests,
    adminToken: auth.adminToken,
    driverToken: auth.driverToken,
    customerPhone: config.customerPhone,
  });

  try {
    const booking = await requestJson(config, '/api/v1/bookings', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    const bookingNumber = booking.bookingNumber;
    if (!bookingNumber) throw new Error('Booking creation did not return bookingNumber');
    registry.update(runId, { bookingNumber });

    const lookup = await requestJson(config, '/api/v1/public/bookings/lookup', {
      method: 'POST',
      body: JSON.stringify({ bookingNumber, phone: config.customerPhone }),
    });
    const bookingId = lookup.bookingId || lookup.id || booking.bookingId || booking.id;
    if (!bookingId) throw new Error('Guest lookup response did not contain bookingId');
    const guestAccessResult = extractGuestAccess(lookup);
    registry.update(runId, {
      bookingId,
      guestAccessToken: guestAccessResult.token,
      guestAccessExpiresAt: guestAccessResult.expiresAt,
    });

    await requestJson(config, `/api/v1/admin/bookings/${bookingNumber}/assign-driver`, {
      method: 'POST',
      headers: bearer(auth.adminToken),
      body: JSON.stringify({
        driverId: config.driverId,
        assignmentReason: `${E2E_MARKER} ${runId}`,
      }),
    });

    return registry.update(runId, { preparationStatus: 'ready' });
  } catch (err) {
    const updated = registry.update(runId, {
      preparationStatus: 'failed',
      preparationError: serializeSafeError(err).message,
    });
    throw new FixturePreparationError(
      `Fixture preparation failed for ${runId}`,
      updated,
      err,
    );
  }
}

async function getAdminBookingDetail(config, fixture) {
  return requestJson(config, `/api/v1/admin/bookings/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.adminToken),
  });
}

async function cleanupFixtureVerified(config, fixture, registry) {
  if (!fixture?.bookingNumber) return;
  const serverBooking = await getAdminBookingDetail(config, fixture);
  assertServerCleanupCandidate(fixture, serverBooking);
  await requestJson(config, '/api/v1/admin/bookings/archive', {
    method: 'POST',
    headers: bearer(fixture.adminToken),
    body: JSON.stringify({
      bookingNumbers: [fixture.bookingNumber],
      reason: 'TEST_DATA',
    }),
  });
  registry.markArchived(fixture.runId);
}

async function transitionDriver(config, fixture, action) {
  const result = await requestJson(config, `/api/v1/driver/bookings/${fixture.bookingNumber}/${action}`, {
    method: 'POST',
    headers: bearer(fixture.driverToken),
    body: JSON.stringify({ reason: `${E2E_MARKER} ${fixture.runId}` }),
  });
  return result;
}

async function sendLocation(config, fixture, latitude, longitude, recordedAt = new Date()) {
  return requestJson(config, '/api/v1/driver/location', {
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

async function getGuestDriverLocation(config, fixture) {
  return requestJson(config, `/api/v1/public/bookings/${fixture.bookingId}/driver-location`, {
    method: 'GET',
    headers: guestAccess(fixture.guestAccessToken),
  });
}

async function waitForGuestStatus(config, fixture, expectedStatus, timeoutMs = 20000) {
  const started = Date.now();
  let lastStatus = null;
  while (Date.now() - started < timeoutMs) {
    const result = await getGuestDriverLocation(config, fixture);
    lastStatus = result.bookingStatus || lastStatus;
    if (lastStatus === expectedStatus) return result;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Timed out waiting for ${expectedStatus}; last status was ${lastStatus}`);
}

async function fillLookupForm(page, fixture) {
  const bookingInput = page.getByLabel(/booking number/i);
  const phoneInput = page.getByLabel(/phone/i);
  if ((await bookingInput.count()) > 0 && (await phoneInput.count()) > 0) {
    await bookingInput.fill(fixture.bookingNumber);
    await phoneInput.fill(fixture.customerPhone);
    return;
  }
  const fields = page.getByRole('textbox');
  await fields.nth(0).fill(fixture.bookingNumber);
  await fields.nth(1).fill(fixture.customerPhone);
}

async function submitLookup(page, fixture) {
  const lookupWait = page.waitForResponse(
    (response) => response.url().includes('/api/v1/public/bookings/lookup'),
    { timeout: 20000 },
  );
  await page.getByRole('button', { name: /find booking|find|lookup|search/i }).click();
  const response = await lookupWait;
  if (response.status() !== 200) {
    throw new Error(`Guest lookup returned HTTP ${response.status()}`);
  }
  const body = await response.json();
  const data = body?.data ?? body;
  if (data?.bookingNumber !== fixture.bookingNumber) {
    throw new Error(`Guest lookup booking mismatch for ${fixture.runId}`);
  }
  if (response.url().includes('guestAccessToken')) {
    throw new Error('Guest lookup leaked token in URL');
  }
}

async function expectNoHorizontalOverflow(page) {
  const overflow = await page.evaluate(() => ({
    html: document.documentElement.scrollWidth,
    body: document.body.scrollWidth,
    width: window.innerWidth,
  }));
  if (overflow.html > overflow.width || overflow.body > overflow.width) {
    throw new Error(`Horizontal overflow detected: ${JSON.stringify(overflow)}`);
  }
}

async function assertNoRawKeys(page) {
  const text = await page.locator('body').innerText();
  if (/customer_driver_location_|track_driver_|guest_lookup_/.test(text)) {
    throw new Error('Raw localization key is visible in the customer UI');
  }
}

async function assertDomDoesNotExposeInternalIds(page, fixture) {
  const text = await page.locator('body').innerText();
  const forbidden = [
    String(fixture.driverToken || ''),
    String(fixture.guestAccessToken || ''),
    'driverId',
    'userId',
    'assignmentId',
  ].filter((value) => value && value.length > 2);
  const leaked = forbidden.find((value) => text.includes(value));
  if (leaked) throw new Error(`Internal identifier or token leaked into DOM for ${fixture.runId}`);
}

function escapeRegExp(value) {
  return String(value).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

function driverMarkerLocator(page, fixture) {
  const displayName = fixture.driverDisplayName || 'Driver';
  return page.getByRole('button', {
    name: new RegExp(`^${escapeRegExp(displayName)}$`, 'i'),
  });
}

async function assertAssignedWaiting(page, audit, fixture) {
  await page.getByText(/Driver location/i).first().waitFor({ timeout: 20000 });
  await page.getByText(/assigned|live location after the driver starts/i).first().waitFor({ timeout: 20000 });
  await page.getByText(/Driver location sharing/i).waitFor({ state: 'detached', timeout: 5000 }).catch(() => {
    throw new Error('DRIVER_ASSIGNED displayed live sharing before ON_ROUTE');
  });
  audit.assertLocationPollingObserved(1);
  audit.assertNoRepeatedGuestLookup(1);
  audit.assertWebSocketConnectionLimit(0);
  await assertNoRawKeys(page);
  await assertDomDoesNotExposeInternalIds(page, fixture);
  await expectNoHorizontalOverflow(page);
}

async function assertOnRouteMap(page, fixture) {
  await page.getByText(/Driver location sharing/i).first().waitFor({ timeout: 25000 });
  await page.getByText(/on the way|pickup location/i).first().waitFor({ timeout: 25000 });
  await driverMarkerLocator(page, fixture).first().waitFor({ timeout: 25000 });
  await page.getByText(/Last update/i).first().waitFor({ timeout: 10000 });
  await page.getByRole('button', { name: /Open in map/i }).first().waitFor({ timeout: 10000 });
  await assertDomDoesNotExposeInternalIds(page, fixture);
  await expectNoHorizontalOverflow(page);
}

async function assertSingleMarker(page, fixture) {
  const markers = driverMarkerLocator(page, fixture);
  const count = await markers.count();
  if (count !== 1) {
    throw new Error(`Expected exactly one driver marker, found ${count}`);
  }
}

async function assertStatusCopy(page, pattern, label) {
  await page.getByText(pattern).first().waitFor({ timeout: 25000 }).catch(() => {
    throw new Error(`${label} status copy was not visible`);
  });
}

async function assertTerminalUiRemoved(page, audit, fixture, terminalAt, pollIntervalMs) {
  await page.getByText(/Driver location sharing/i).waitFor({ state: 'detached', timeout: 25000 }).catch(() => {
    throw new Error('Terminal state did not remove live driver location UI');
  });
  await driverMarkerLocator(page, fixture).waitFor({ state: 'detached', timeout: 25000 }).catch(() => {
    throw new Error('Terminal state did not remove driver marker');
  });
  await page.waitForTimeout(1200);
  audit.assertNoGuestLocationAfter(terminalAt, pollIntervalMs + 3000);
  await expectNoHorizontalOverflow(page);
}

async function runViewportScenario({ browser, config, viewport, auth, registry }) {
  const runId = createViewportRunId(createRunId(), viewport);
  let fixture;
  const context = await browser.newContext({ viewport, locale: 'en-US' });
  const audit = new NetworkAudit();
  try {
    try {
      fixture = await prepareFixture(config, runId, auth, registry, viewport);
    } catch (err) {
      fixture = err.fixture || registry.get(runId);
      throw err;
    }
    const page = await context.newPage();
    const consoleErrors = [];
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('pageerror', (err) => consoleErrors.push(err.message));
    page.on('request', (request) => {
      const url = request.url();
      if (url.includes('/api/v1/') || url.includes('/socket.io')) {
        audit.recordRequest(url, request.method(), request.headers());
      }
    });
    page.on('websocket', (socket) => {
      audit.recordWebSocket(socket.url());
      socket.on('close', () => audit.recordWebSocketClosed(socket.url()));
    });

    await page.goto(`${config.frontendUrl}/booking/lookup`, { waitUntil: 'networkidle' });
    await fillLookupForm(page, fixture);
    await submitLookup(page, fixture);
    await assertAssignedWaiting(page, audit, fixture);

    await transitionDriver(config, fixture, 'start-route');
    await waitForGuestStatus(config, fixture, 'ON_ROUTE');
    await sendLocation(config, fixture, 12.9236, 100.8825);
    await page.waitForTimeout(config.pollIntervalMs + 1500);
    await sendLocation(config, fixture, 12.9241, 100.8831);
    await page.waitForTimeout(config.pollIntervalMs + 1500);
    const locationSnapshot = await getGuestDriverLocation(config, fixture);
    if (locationSnapshot.driver?.displayName) {
      fixture.driverDisplayName = locationSnapshot.driver.displayName;
    }
    audit.assertLocationPollingObserved(2);
    audit.assertGuestLocationInterval({ expectedMs: config.pollIntervalMs });
    audit.assertStableGuestTokenFingerprint();
    audit.assertNoRepeatedGuestLookup(1);
    audit.assertWebSocketConnectionLimit(1);
    await assertOnRouteMap(page, fixture);
    await assertSingleMarker(page, fixture);

    await transitionDriver(config, fixture, 'arrive');
    await waitForGuestStatus(config, fixture, 'DRIVER_ARRIVED');
    await assertStatusCopy(page, /arrived|pickup location/i, 'DRIVER_ARRIVED');
    await assertSingleMarker(page, fixture);
    audit.assertWebSocketConnectionLimit(1);

    await transitionDriver(config, fixture, 'mark-picked-up');
    await waitForGuestStatus(config, fixture, 'PICKED_UP');
    await assertStatusCopy(page, /in progress|trip/i, 'PICKED_UP');
    await assertSingleMarker(page, fixture);
    audit.assertWebSocketConnectionLimit(1);

    await transitionDriver(config, fixture, 'end-trip');
    await waitForGuestStatus(config, fixture, 'SETTLEMENT_PENDING');
    const terminalAt = Date.now();
    await page.waitForTimeout(config.pollIntervalMs + 1500);
    await assertTerminalUiRemoved(page, audit, fixture, terminalAt, config.pollIntervalMs);

    if (consoleErrors.length) {
      throw new Error(`Browser console errors at ${viewport.width}px: ${consoleErrors.join('; ')}`);
    }
    console.log(`PASS viewport ${viewport.width}x${viewport.height}; socket reconnects=${audit.socketReconnectCount()}`);
  } finally {
    await context.close();
    if (fixture) {
      if (config.keepFixture) {
        registry.markKept(fixture.runId);
      } else {
        try {
          await cleanupFixtureVerified(config, fixture, registry);
        } catch (err) {
          registry.markCleanupFailed(fixture.runId, err);
          throw err;
        }
      }
    }
  }
}

async function cleanupPendingFixtures(config, registry) {
  const failures = [];
  for (const record of registry.pendingCleanup()) {
    try {
      await cleanupFixtureVerified(config, record, registry);
    } catch (err) {
      registry.markCleanupFailed(record.runId, err);
      failures.push({
        runId: record.runId,
        bookingNumber: record.bookingNumber,
        error: serializeSafeError(err).message,
      });
    }
  }
  if (failures.length) {
    const error = new AggregateError(
      failures.map((failure) => new Error(`${failure.runId}: ${failure.error}`)),
      'One or more E2E fixture cleanup attempts failed',
    );
    error.failures = failures;
    throw error;
  }
}

function buildRunFailure(primaryError, cleanupError) {
  const error = new Error('Customer location E2E failed');
  error.name = 'E2ERunFailure';
  error.primaryError = primaryError ? serializeSafeError(primaryError) : null;
  error.cleanupErrors = cleanupError?.failures ?? (
    cleanupError ? [serializeSafeError(cleanupError)] : []
  );
  return error;
}

function writeManifest(config, registry, name = 'customer-location-e2e-manifest.json') {
  fs.mkdirSync(config.artifactDir, { recursive: true });
  const markerPath = path.join(config.artifactDir, name);
  fs.writeFileSync(markerPath, `${JSON.stringify(registry.manifest(), null, 2)}\n`);
  return markerPath;
}

async function openBrowser(args) {
  const { chromium, firefox, webkit } = require('@playwright/test');
  const browserType = { chromium, firefox, webkit }[args.project] || chromium;
  return browserType.launch({ headless: !args.headed });
}

async function main() {
  const args = parseArgs();
  const env = mergeEnv(loadEnvFile(), process.env);
  if (args.headed) env.TRIDE_E2E_HEADED = '1';
  if (args.keepFixture) env.TRIDE_E2E_KEEP_FIXTURE = '1';
  const config = buildConfig(env, { requireSecrets: !args.dryRun });
  const baseRunId = createRunId();
  const dryRunSummary = redact({
    dryRun: true,
    baseRunId,
    target: config.target,
    frontendHost: config.frontendHost,
    backendHost: config.backendHost,
    hardAllowedHosts: config.allowedHosts,
    adminEmail: config.adminEmail,
    driverEmail: config.driverEmail,
    driverId: config.driverId,
    customerPhone: config.customerPhone,
    viewports: VIEWPORTS.map((viewport) => `${viewport.width}x${viewport.height}`),
    activeStatuses: [...ACTIVE_STATUSES],
    terminalStatuses: [...TERMINAL_STATUSES],
  });

  if (args.dryRun) {
    console.log(JSON.stringify(dryRunSummary, null, 2));
    return;
  }

  const registry = new FixtureRegistry();
  let primaryError = null;
  let cleanupError = null;
  let browser = null;
  try {
    const auth = await authenticateAndPreflight(config);
    browser = await openBrowser(args);
    for (const viewport of VIEWPORTS) {
      const currentStatus = await loadDriverStatus(config, auth.driverToken);
      if (currentStatus.hasActiveJob === true) {
        throw new Error(`E2E driver has an active job before viewport ${viewport.width}x${viewport.height}`);
      }
      await runViewportScenario({ browser, config, viewport, auth, registry });
    }
  } catch (err) {
    primaryError = err;
  } finally {
    if (browser) {
      try {
        await browser.close();
      } catch (err) {
        primaryError = primaryError || err;
      }
    }
    if (!config.keepFixture) {
      try {
        await cleanupPendingFixtures(config, registry);
      } catch (err) {
        cleanupError = err;
      }
    }
    if (config.keepFixture || registry.records.length) {
      const markerPath = writeManifest(config, registry);
      console.log(`Redacted E2E manifest: ${markerPath}`);
    }
  }
  if (primaryError || cleanupError) {
    throw buildRunFailure(primaryError, cleanupError);
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(JSON.stringify(serializeSafeError(err), null, 2));
    process.exit(1);
  });
}

module.exports = {
  authenticateAndPreflight,
  buildRunFailure,
  cleanupFixtureVerified,
  cleanupPendingFixtures,
  fillLookupForm,
  main,
  parseArgs,
  prepareFixture,
  runViewportScenario,
  sendLocation,
  submitLookup,
  transitionDriver,
  waitForGuestStatus,
};
