#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const { createRequire } = require('node:module');
const {
  E2E_MARKER,
  FixturePreparationError,
  FixtureRegistry,
  buildBookingPayload,
  buildConfig,
  createRunId,
  loadEnvFile,
  mergeEnv,
  redact,
  serializeSafeError,
} = require('../settlement-lifecycle/core');
const {
  EXPECTED_COMMISSION_AMOUNT,
  EXPECTED_CURRENCY,
  assertMoneyFields,
  assertSettlementApprovalCandidate,
  assertSettlementCleanupCandidate,
  createSyntheticReceiptPng,
} = require('../settlement-lifecycle/run');

const VIEWPORT = { width: 960, height: 800 };
const MANIFEST_NAME = 'admin-settlement-ui-e2e-manifest.json';

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
    throw new Error(`${pathName} failed HTTP ${response.status}: ${JSON.stringify(redact(body))}`);
  }
  return body?.data ?? body;
}

async function requestMultipart(config, pathName, form, options = {}) {
  const response = await fetch(apiUrl(config, pathName), {
    ...options,
    method: options.method || 'POST',
    headers: {
      accept: 'application/json',
      ...(options.headers || {}),
    },
    body: form,
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(`${pathName} failed HTTP ${response.status}: ${JSON.stringify(redact(body))}`);
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

async function ensureDriverOnline(config, driverToken, currentStatus) {
  if (currentStatus?.online === true && currentStatus?.status === 'AVAILABLE') return currentStatus;
  if (currentStatus?.hasActiveJob === true) return currentStatus;
  await requestJson(config, '/api/v1/driver/online', {
    method: 'POST',
    headers: bearer(driverToken),
  });
  return loadDriverStatus(config, driverToken);
}

async function authenticateAndPreflight(config) {
  const admin = await login(config, config.adminEmail, config.adminPassword);
  const driver = await login(config, config.driverEmail, config.driverPassword);
  const [adminMe, driverMe, initialDriverStatus] = await Promise.all([
    loadMe(config, admin.accessToken),
    loadMe(config, driver.accessToken),
    loadDriverStatus(config, driver.accessToken),
  ]);
  const adminRole = String(adminMe?.role || adminMe?.user?.role || '').toUpperCase();
  const driverRole = String(driverMe?.role || driverMe?.user?.role || '').toUpperCase();
  if (!adminRole.includes('ADMIN')) throw new Error('Configured admin account is not an admin role');
  if (driverRole !== 'DRIVER') throw new Error('Configured driver account is not a driver role');
  if (Number(initialDriverStatus.driverId) !== Number(config.driverId)) {
    throw new Error('TRIDE_E2E_DRIVER_ID does not match the logged-in driver account');
  }
  if (initialDriverStatus.active !== true) throw new Error('Configured E2E driver is not active');
  if (initialDriverStatus.hasActiveJob === true) {
    throw new Error('Configured E2E driver already has an active job; no fixture will be created');
  }
  const driverStatus = await ensureDriverOnline(config, driver.accessToken, initialDriverStatus);
  if (driverStatus.online !== true || driverStatus.status !== 'AVAILABLE') {
    throw new Error('Configured E2E driver could not be prepared as online and available');
  }
  return { adminToken: admin.accessToken, driverToken: driver.accessToken };
}

async function prepareReceiptSubmittedFixture(config, runId, auth, registry) {
  const payload = buildBookingPayload(runId, config.customerPhone);
  const fixture = registry.add({
    runId,
    viewport: `${VIEWPORT.width}x${VIEWPORT.height}`,
    bookingNumber: null,
    customerName: payload.customer.name,
    marker: payload.additionalRequests,
    adminToken: auth.adminToken,
    driverToken: auth.driverToken,
  });
  try {
    const booking = await requestJson(config, '/api/v1/bookings', {
      method: 'POST',
      body: JSON.stringify(payload),
    });
    if (!booking.bookingNumber) throw new Error('Booking creation did not return bookingNumber');
    registry.update(runId, { bookingNumber: booking.bookingNumber });
    await requestJson(config, `/api/v1/admin/bookings/${booking.bookingNumber}/assign-driver`, {
      method: 'POST',
      headers: bearer(auth.adminToken),
      body: JSON.stringify({
        driverId: config.driverId,
        assignmentReason: `${E2E_MARKER} ${runId}`,
      }),
    });
    for (const action of ['start-route', 'arrive', 'mark-picked-up', 'end-trip']) {
      await requestJson(config, `/api/v1/driver/bookings/${booking.bookingNumber}/${action}`, {
        method: 'POST',
        headers: bearer(auth.driverToken),
        body: JSON.stringify({ reason: `${E2E_MARKER} ${runId}` }),
      });
    }
    const due = await loadDriverSettlement(config, fixture);
    if (due.commissionStatus !== 'DUE') {
      throw new Error(`Driver settlement status was ${due.commissionStatus}, expected DUE`);
    }
    const money = assertMoneyFields(due);
    const uploaded = await uploadReceipt(config, fixture);
    if (uploaded.commissionStatus !== 'RECEIPT_SUBMITTED' || uploaded.receiptStatus !== 'RECEIPT_SUBMITTED') {
      throw new Error('Receipt upload did not move settlement to RECEIPT_SUBMITTED');
    }
    if (!uploaded.receiptFileId && !uploaded.receiptMetadata) {
      throw new Error('Receipt upload did not return receipt metadata');
    }
    return registry.update(runId, {
      preparationStatus: 'ready',
      bookingFinalStatus: 'SETTLEMENT_PENDING',
      settlementStatus: uploaded.commissionStatus,
      receiptStatus: uploaded.receiptStatus,
      receiptUploadStatus: 'submitted',
      customerTotal: money.customerTotal,
      companyCommission: money.commission,
      driverExpectedIncome: money.expectedIncome,
    });
  } catch (err) {
    const updated = registry.update(runId, {
      preparationStatus: 'failed',
      preparationError: serializeSafeError(err).message,
    });
    throw new FixturePreparationError(`Fixture preparation failed for ${runId}`, updated, err);
  }
}

async function loadDriverSettlement(config, fixture) {
  return requestJson(config, `/api/v1/driver/settlements/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.driverToken),
  });
}

async function getAdminBookingDetail(config, fixture) {
  return requestJson(config, `/api/v1/admin/bookings/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.adminToken),
  });
}

async function loadAdminSettlement(config, fixture) {
  return requestJson(config, `/api/v1/admin/settlements/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.adminToken),
  });
}

async function uploadReceipt(config, fixture) {
  const bytes = createSyntheticReceiptPng(fixture.runId);
  const form = new FormData();
  form.append('file', new Blob([bytes], { type: 'image/png' }), `admin-settlement-ui-${fixture.runId}.png`);
  return requestMultipart(config, `/api/v1/driver/settlements/${fixture.bookingNumber}/receipt`, form, {
    headers: bearer(fixture.driverToken),
  });
}

async function cleanupFixtureVerified(config, fixture, registry) {
  if (!fixture?.bookingNumber) return;
  const serverBooking = await getAdminBookingDetail(config, fixture);
  assertSettlementCleanupCandidate(fixture, serverBooking);
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

async function openBrowser(args) {
  let playwright;
  try {
    playwright = require('@playwright/test');
  } catch (_) {
    const backendRequire = createRequire(path.join(__dirname, '..', '..', '..', 'backend', 'package.json'));
    playwright = backendRequire('@playwright/test');
  }
  const { chromium, firefox, webkit } = playwright;
  const browserType = { chromium, firefox, webkit }[args.project] || chromium;
  return browserType.launch({ headless: !args.headed });
}

async function waitForFlutterApp(page) {
  await page.waitForFunction(() => Boolean(
    document.querySelector('flt-glass-pane') ||
    document.querySelector('flutter-view') ||
    document.querySelector('[role="application"]') ||
    document.querySelector('flt-semantics-placeholder'),
  ), null, { timeout: 30000 });
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) {
    await placeholder.first().click({ force: true }).catch(() => {});
  }
}

async function waitMs(ms) {
  await new Promise((resolve) => setTimeout(resolve, ms));
}

async function screenshot(config, page, name) {
  fs.mkdirSync(config.artifactDir, { recursive: true });
  await page.screenshot({
    path: path.join(config.artifactDir, name),
    fullPage: true,
  }).catch(() => {});
}

async function seedAdminToken(page, token) {
  await page.addInitScript((accessToken) => {
    window.localStorage.setItem('flutter.admin_access_token', JSON.stringify(accessToken));
  }, token);
}

function adminSettlementE2EDetailUrl(config, bookingNumber) {
  const value = String(bookingNumber || '').trim();
  if (!/^TX[0-9A-Za-z_-]+$/.test(value)) {
    throw new Error('Admin settlement UI E2E requires a valid booking number');
  }
  return `${config.frontendUrl}/admin/e2e/settlement-detail?bookingNumber=${encodeURIComponent(value)}`;
}

async function clickUnique(locator, label) {
  await locator.first().waitFor({ timeout: 25000 });
  const count = await locator.count();
  if (count !== 1) throw new Error(`${label} matched ${count} elements`);
  await locator.click();
}

async function clickApproveWithConfirmation(page, config, fixture) {
  const approveResponsePromise = page.waitForResponse(
    (response) => response.url().includes(`/api/v1/admin/settlements/${fixture.bookingNumber}/approve`)
      && response.request().method() === 'POST',
    { timeout: 30000 },
  );
  await screenshot(config, page, `${fixture.runId}-admin-settlement-detail-before-approve.png`);
  await clickUnique(page.getByRole('button', { name: /^Approve$/ }), 'admin approve button');
  await screenshot(config, page, `${fixture.runId}-admin-settlement-confirm-dialog.png`);
  await clickUnique(page.getByRole('dialog').getByRole('button', { name: /^Approve$/ }), 'admin approve confirmation button');
  const response = await approveResponsePromise;
  if (!response.ok()) {
    throw new Error(`Admin UI approve failed HTTP ${response.status()}`);
  }
  return response;
}

async function runAdminSettlementUi(config, auth, registry, browser) {
  const runId = createRunId();
  const fixture = await prepareReceiptSubmittedFixture(config, runId, auth, registry);
  const booking = await getAdminBookingDetail(config, fixture);
  const settlement = await loadAdminSettlement(config, fixture);
  assertSettlementApprovalCandidate(fixture, booking, settlement, config.driverId);
  const money = assertMoneyFields(settlement);
  registry.update(runId, {
    approvalCandidateVerified: true,
    adminCommissionStatusBeforeUi: settlement.commissionStatus,
    adminReceiptStatusBeforeUi: settlement.receiptStatus,
    adminCanApproveBeforeUi: settlement.canApprove === true,
    uiCurrency: settlement.currency || EXPECTED_CURRENCY,
    customerTotal: money.customerTotal,
    companyCommission: money.commission,
    driverExpectedIncome: money.expectedIncome,
  });

  const context = await browser.newContext({ viewport: VIEWPORT, locale: 'en-US' });
  const page = await context.newPage();
  const consoleErrors = [];
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });
  page.on('pageerror', (err) => consoleErrors.push(err.message));
  try {
    await seedAdminToken(page, auth.adminToken);
    await page.goto(adminSettlementE2EDetailUrl(config, fixture.bookingNumber), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutterApp(page);
    await waitMs(3000);
    await screenshot(config, page, `${runId}-admin-settlement-detail-loaded.png`);
    await clickApproveWithConfirmation(page, config, fixture);
    await waitMs(3000);
    await screenshot(config, page, `${runId}-admin-settlement-detail-approved.png`);

    const approvedBooking = await getAdminBookingDetail(config, fixture);
    const approvedSettlement = await loadAdminSettlement(config, fixture);
    if (approvedBooking.status !== 'COMPLETED') {
      throw new Error(`Admin UI approval left booking ${approvedBooking.status}, expected COMPLETED`);
    }
    if (approvedSettlement.commissionStatus !== 'APPROVED') {
      throw new Error(
        `Admin UI approval left settlement ${approvedSettlement.commissionStatus}, expected APPROVED`,
      );
    }
    const finalDriverStatus = await loadDriverStatus(config, fixture.driverToken);
    if (finalDriverStatus.hasActiveJob === true) {
      throw new Error('Driver still has an active job after admin UI approval');
    }
    registry.update(runId, {
      uiApprovalStatus: 'approved',
      settlementStatus: approvedSettlement.commissionStatus,
      receiptStatus: approvedSettlement.receiptStatus,
      bookingFinalStatus: approvedBooking.status,
      driverActiveJobAfterApproval: false,
    });
    if (consoleErrors.length) throw new Error(`Browser console errors: ${consoleErrors.join('; ')}`);
    return registry.get(runId);
  } finally {
    await context.close();
    if (!config.keepFixture) await cleanupFixtureVerified(config, fixture, registry);
  }
}

function writeManifest(config, registry) {
  fs.mkdirSync(config.artifactDir, { recursive: true });
  const manifestPath = path.join(config.artifactDir, MANIFEST_NAME);
  const allowed = registry.records.map((record) => redact({
    runId: record.runId,
    bookingNumber: record.bookingNumber,
    receiptUploadStatus: record.receiptUploadStatus,
    approvalCandidateVerified: record.approvalCandidateVerified,
    adminCommissionStatusBeforeUi: record.adminCommissionStatusBeforeUi,
    adminReceiptStatusBeforeUi: record.adminReceiptStatusBeforeUi,
    adminCanApproveBeforeUi: record.adminCanApproveBeforeUi,
    uiApprovalStatus: record.uiApprovalStatus,
    settlementStatus: record.settlementStatus,
    receiptStatus: record.receiptStatus,
    bookingFinalStatus: record.bookingFinalStatus,
    driverActiveJobAfterApproval: record.driverActiveJobAfterApproval,
    preparationStatus: record.preparationStatus,
    preparationError: record.preparationError,
    cleanupStatus: record.cleanupStatus,
    cleanupError: record.cleanupError,
  }));
  fs.writeFileSync(manifestPath, `${JSON.stringify(allowed, null, 2)}\n`);
  return manifestPath;
}

async function main() {
  const args = parseArgs();
  const env = mergeEnv(loadEnvFile(), process.env);
  if (args.headed) env.TRIDE_E2E_HEADED = '1';
  if (args.keepFixture) env.TRIDE_E2E_KEEP_FIXTURE = '1';
  const config = buildConfig(env, { requireSecrets: !args.dryRun });
  const dryRunSummary = redact({
    dryRun: true,
    target: config.target,
    frontendHost: config.frontendHost,
    backendHost: config.backendHost,
    driverId: config.driverId,
    viewport: `${VIEWPORT.width}x${VIEWPORT.height}`,
    marker: E2E_MARKER,
    expectedCommissionAmount: EXPECTED_COMMISSION_AMOUNT,
    expectedCurrency: EXPECTED_CURRENCY,
    requiresLocalE2eRoute: 'TRIDE_ENABLE_E2E_ROUTES=true',
  });
  if (args.dryRun) {
    console.log(JSON.stringify(dryRunSummary, null, 2));
    return;
  }

  const registry = new FixtureRegistry();
  let browser;
  try {
    const auth = await authenticateAndPreflight(config);
    browser = await openBrowser(args);
    const record = await runAdminSettlementUi(config, auth, registry, browser);
    console.log(
      `PASS admin settlement UI ${record.bookingNumber}; ` +
      `approval=${record.uiApprovalStatus}; booking=${record.bookingFinalStatus}; ` +
      `settlement=${record.settlementStatus}; cleanup=${record.cleanupStatus}`,
    );
  } finally {
    if (browser) await browser.close().catch(() => {});
    if (registry.records.length) {
      console.log(`Redacted admin settlement UI E2E manifest: ${writeManifest(config, registry)}`);
    }
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(JSON.stringify(serializeSafeError(err), null, 2));
    process.exit(1);
  });
}

module.exports = {
  MANIFEST_NAME,
  VIEWPORT,
  adminSettlementE2EDetailUrl,
  parseArgs,
  writeManifest,
};
