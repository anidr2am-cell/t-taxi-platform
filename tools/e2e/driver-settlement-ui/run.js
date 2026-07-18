#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
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

const VIEWPORT = { width: 390, height: 844 };
const MANIFEST_NAME = 'driver-settlement-ui-e2e-manifest.json';

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

async function prepareSettlementPendingFixture(config, runId, auth, registry) {
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
    return registry.update(runId, {
      preparationStatus: 'ready',
      bookingFinalStatus: 'SETTLEMENT_PENDING',
      settlementStatus: due.commissionStatus,
      receiptStatus: due.receiptStatus,
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

async function approveSettlementVerified(config, fixture) {
  const booking = await getAdminBookingDetail(config, fixture);
  const settlement = await loadAdminSettlement(config, fixture);
  assertSettlementApprovalCandidate(fixture, booking, settlement, config.driverId);
  const approved = await requestJson(config, `/api/v1/admin/settlements/${fixture.bookingNumber}/approve`, {
    method: 'POST',
    headers: bearer(fixture.adminToken),
    body: JSON.stringify({}),
  });
  if (approved.commissionStatus !== 'APPROVED' || approved.status !== 'COMPLETED') {
    throw new Error('Admin API approval did not complete settlement');
  }
  return approved;
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

async function clickUnique(locator, label) {
  await locator.first().waitFor({ timeout: 25000 });
  const count = await locator.count();
  if (count !== 1) throw new Error(`${label} matched ${count} elements`);
  await locator.click();
}

function driverSettlementE2EDetailUrl(config, bookingNumber) {
  const value = String(bookingNumber || '').trim();
  if (!/^TX[0-9A-Za-z_-]+$/.test(value)) {
    throw new Error('Driver settlement UI E2E requires a valid booking number');
  }
  return `${config.frontendUrl}/driver/e2e/settlement-detail?bookingNumber=${encodeURIComponent(value)}`;
}

async function seedDriverSession(context, driverToken) {
  if (!driverToken) throw new Error('Driver settlement UI E2E requires a driver token');
  await context.addInitScript((token) => {
    window.localStorage.setItem('flutter.driver_access_token', JSON.stringify(token));
    window.localStorage.setItem('driver_access_token', token);
  }, driverToken);
}

function receiptSelectButton(page) {
  return page.getByRole('button', {
    name: /select receipt|replace receipt|choose file|송금증 선택|파일 변경|เลือกสลิปโอนเงิน|เปลี่ยนไฟล์/i,
  });
}

function receiptUploadButton(page) {
  return page.getByRole('button', {
    name: /transfer slip upload|upload receipt|송금증 업로드|อัปโหลดสลิปโอนเงิน/i,
  });
}

async function chooseReceiptFile(page, receiptPath) {
  const button = receiptSelectButton(page);
  await button.first().scrollIntoViewIfNeeded({ timeout: 15000 });
  const fileChooserPromise = page.waitForEvent('filechooser', { timeout: 15000 });
  await clickUnique(button, 'receipt select button');
  const fileChooser = await fileChooserPromise;
  await fileChooser.setFiles(receiptPath);
  return { method: 'semantic-filechooser', clicks: 1 };
}

async function uploadSelectedReceipt(page) {
  const button = receiptUploadButton(page);
  await button.first().scrollIntoViewIfNeeded({ timeout: 15000 });
  await clickUnique(button, 'receipt upload button');
  return { method: 'semantic-button', clicks: 1 };
}

async function runDriverSettlementUi(config, auth, registry, browser) {
  const runId = createRunId();
  const fixture = await prepareSettlementPendingFixture(config, runId, auth, registry);
  const context = await browser.newContext({ viewport: VIEWPORT, locale: 'en-US' });
  await seedDriverSession(context, fixture.driverToken);
  const page = await context.newPage();
  const consoleErrors = [];
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });
  page.on('pageerror', (err) => consoleErrors.push(err.message));
  try {
    await page.goto(driverSettlementE2EDetailUrl(config, fixture.bookingNumber), {
      waitUntil: 'domcontentloaded',
    });
    await waitForFlutterApp(page);
    await page.getByText(fixture.bookingNumber).first().waitFor({ timeout: 30000 });
    await screenshot(config, page, `${runId}-driver-settlement-detail-due.png`);

    const dueDetail = await loadDriverSettlement(config, fixture);
    const money = assertMoneyFields(dueDetail);
    if (
      Number(money.commission) !== Number(fixture.companyCommission) ||
      Number(money.expectedIncome) !== Number(fixture.driverExpectedIncome) ||
      Number(money.customerTotal) !== Number(fixture.customerTotal)
    ) {
      throw new Error('Driver settlement detail money values changed before UI upload');
    }
    registry.update(runId, {
      uiDisplayedMoneyVerified: true,
      uiCurrency: EXPECTED_CURRENCY,
    });

    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-driver-settlement-ui-'));
    const receiptPath = path.join(tempDir, `driver-settlement-ui-${runId}.png`);
    fs.writeFileSync(receiptPath, createSyntheticReceiptPng(runId));
    try {
      await page.mouse.wheel(0, 900);
      await waitMs(1000);
      await screenshot(config, page, `${runId}-driver-settlement-upload-section.png`);
      const fileSelection = await chooseReceiptFile(page, receiptPath);
      await waitMs(1000);
      await screenshot(
        config,
        page,
        `${runId}-driver-settlement-receipt-selected.png`,
      );
      await screenshot(config, page, `${runId}-driver-settlement-upload-button.png`);
      const uploadClick = await uploadSelectedReceipt(page);
      registry.update(runId, {
        uiFileChooserMethod: fileSelection.method,
        uiFileChooserClicks: fileSelection.clicks,
        uiUploadClickMethod: uploadClick.method,
        uiUploadClicks: uploadClick.clicks,
      });
    } finally {
      fs.rmSync(tempDir, { recursive: true, force: true });
    }
    await waitMs(3000);
    await screenshot(config, page, `${runId}-driver-settlement-receipt-submitted.png`);
    const submitted = await loadDriverSettlement(config, fixture);
    if (submitted.commissionStatus !== 'RECEIPT_SUBMITTED') {
      throw new Error(`UI upload left settlement ${submitted.commissionStatus}, expected RECEIPT_SUBMITTED`);
    }
    registry.update(runId, {
      settlementStatus: submitted.commissionStatus,
      receiptStatus: submitted.receiptStatus,
      uiUploadStatus: 'submitted',
    });
    const approved = await approveSettlementVerified(config, fixture);
    const finalDriverStatus = await loadDriverStatus(config, fixture.driverToken);
    if (finalDriverStatus.hasActiveJob === true) {
      throw new Error('Driver still has an active job after admin approval');
    }
    registry.update(runId, {
      approvalCandidateVerified: true,
      settlementStatus: approved.commissionStatus,
      receiptStatus: approved.receiptStatus,
      bookingFinalStatus: approved.status,
      driverActiveJobAfterApproval: false,
    });
    if (consoleErrors.length) throw new Error(`Browser console errors: ${consoleErrors.join('; ')}`);
    return registry.get(runId);
  } finally {
    await context.close();
    if (!config.keepFixture) await cleanupFixtureVerified(config, fixture, registry);
  }
}

function formatAmount(value) {
  return Number(value).toLocaleString('en-US', {
    maximumFractionDigits: Number(value) === Math.round(Number(value)) ? 0 : 2,
  });
}

function writeManifest(config, registry) {
  fs.mkdirSync(config.artifactDir, { recursive: true });
  const manifestPath = path.join(config.artifactDir, MANIFEST_NAME);
  const allowed = registry.records.map((record) => redact({
    runId: record.runId,
    bookingNumber: record.bookingNumber,
    uiUploadStatus: record.uiUploadStatus,
    settlementStatus: record.settlementStatus,
    receiptStatus: record.receiptStatus,
    uiDisplayedMoneyVerified: record.uiDisplayedMoneyVerified,
    uiCurrency: record.uiCurrency,
    uiFileChooserMethod: record.uiFileChooserMethod,
    uiFileChooserClicks: record.uiFileChooserClicks,
    uiUploadClickMethod: record.uiUploadClickMethod,
    uiUploadClicks: record.uiUploadClicks,
    approvalCandidateVerified: record.approvalCandidateVerified,
    bookingFinalStatus: record.bookingFinalStatus,
    preparationStatus: record.preparationStatus,
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
    const record = await runDriverSettlementUi(config, auth, registry, browser);
    console.log(
      `PASS driver settlement UI ${record.bookingNumber}; ` +
      `upload=${record.uiUploadStatus}; booking=${record.bookingFinalStatus}; ` +
      `settlement=${record.settlementStatus}; cleanup=${record.cleanupStatus}`,
    );
  } finally {
    if (browser) await browser.close().catch(() => {});
    if (registry.records.length) {
      console.log(`Redacted driver settlement UI E2E manifest: ${writeManifest(config, registry)}`);
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
  driverSettlementE2EDetailUrl,
  formatAmount,
  parseArgs,
  seedDriverSession,
  writeManifest,
};
