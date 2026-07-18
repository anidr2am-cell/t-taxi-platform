#!/usr/bin/env node
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const zlib = require('node:zlib');
const {
  E2E_MARKER,
  FixturePreparationError,
  FixtureRegistry,
  assertCleanupCandidate,
  assertUrlAllowed,
  buildBookingPayload,
  buildConfig,
  createRunId,
  extractGuestAccess,
  loadEnvFile,
  mergeEnv,
  redact,
  serializeSafeError,
} = require('./core');

const EXPECTED_COMMISSION_AMOUNT = 200;
const EXPECTED_CURRENCY = 'THB';

function parseArgs(argv = process.argv.slice(2)) {
  return {
    dryRun: argv.includes('--dry-run'),
    keepFixture: argv.includes('--keep-fixture'),
  };
}

function apiUrl(config, pathName) {
  return `${config.backendUrl}${pathName}`;
}

function bearer(token) {
  return { authorization: `Bearer ${token}` };
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
  assertE2EEmail('Admin email', config.adminEmail);
  assertE2EEmail('Driver email', config.driverEmail);
  assertFakeCustomerPhone(config.customerPhone);
  const admin = await login(config, config.adminEmail, config.adminPassword);
  const driver = await login(config, config.driverEmail, config.driverPassword);
  const [adminMe, driverMe, initialDriverStatus] = await Promise.all([
    loadMe(config, admin.accessToken),
    loadMe(config, driver.accessToken),
    loadDriverStatus(config, driver.accessToken),
  ]);
  const adminRole = String(adminMe?.role || adminMe?.user?.role || '').toUpperCase();
  if (!adminRole.includes('ADMIN')) throw new Error('Configured admin account is not an admin role');
  const driverRole = String(driverMe?.role || driverMe?.user?.role || '').toUpperCase();
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
  return {
    adminToken: admin.accessToken,
    driverToken: driver.accessToken,
  };
}

async function prepareFixture(config, runId, auth, registry) {
  const payload = buildBookingPayload(runId, config.customerPhone);
  const fixture = registry.add({
    runId,
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
    extractGuestAccess(lookup);

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
    throw new FixturePreparationError(`Fixture preparation failed for ${runId}`, updated, err);
  }
}

async function getAdminBookingDetail(config, fixture) {
  return requestJson(config, `/api/v1/admin/bookings/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.adminToken),
  });
}

function assertSettlementCleanupCandidate(record, serverBooking) {
  assertCleanupCandidate(record);
  const serverBookingNumber = String(serverBooking?.bookingNumber || serverBooking?.booking_number || '');
  if (serverBookingNumber !== record.bookingNumber) {
    throw new Error(`Cleanup refused booking number mismatch for ${record.runId}`);
  }
  const serverCustomerName = String(serverBooking?.customer?.name || serverBooking?.customerName || '');
  if (!serverCustomerName.startsWith('[E2E]') || !serverCustomerName.includes(record.runId)) {
    throw new Error(`Cleanup refused customer mismatch for ${record.runId}`);
  }
  const marker = [
    serverBooking?.specialRequests,
    serverBooking?.additionalRequests,
    serverBooking?.luggage?.specialItems,
    serverBooking?.requestMarker,
  ].filter(Boolean).join(' ');
  if (!marker.includes(E2E_MARKER) || !marker.includes(record.runId)) {
    throw new Error(`Cleanup refused marker mismatch for ${record.runId}`);
  }
  return true;
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

async function transitionDriver(config, fixture, action) {
  return requestJson(config, `/api/v1/driver/bookings/${fixture.bookingNumber}/${action}`, {
    method: 'POST',
    headers: bearer(fixture.driverToken),
    body: JSON.stringify({ reason: `${E2E_MARKER} ${fixture.runId}` }),
  });
}

async function loadDriverSettlement(config, fixture) {
  return requestJson(config, `/api/v1/driver/settlements/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.driverToken),
  });
}

async function loadAdminSettlement(config, fixture) {
  return requestJson(config, `/api/v1/admin/settlements/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.adminToken),
  });
}

async function approveSettlement(config, fixture) {
  return requestJson(config, `/api/v1/admin/settlements/${fixture.bookingNumber}/approve`, {
    method: 'POST',
    headers: bearer(fixture.adminToken),
    body: JSON.stringify({}),
  });
}

async function waitForBookingStatus(config, fixture, expectedStatus, timeoutMs = 20000) {
  const started = Date.now();
  let lastStatus = null;
  while (Date.now() - started < timeoutMs) {
    const booking = await getAdminBookingDetail(config, fixture);
    lastStatus = booking.status || lastStatus;
    if (lastStatus === expectedStatus) return booking;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Timed out waiting for ${expectedStatus}; last status was ${lastStatus}`);
}

function assertMoneyFields(settlement) {
  const customerTotal = Number(settlement.customerTotalAmount ?? settlement.customerPaymentAmount);
  const commission = Number(settlement.companyCommissionAmount ?? settlement.commissionAmount);
  const expectedIncome = Number(settlement.driverExpectedIncomeAmount);
  if (!Number.isFinite(customerTotal) || customerTotal <= 0) {
    throw new Error('Settlement customer total amount is missing or invalid');
  }
  if (!Number.isFinite(commission) || commission !== EXPECTED_COMMISSION_AMOUNT) {
    throw new Error(`Settlement commission amount was ${commission}, expected ${EXPECTED_COMMISSION_AMOUNT}`);
  }
  if (!Number.isFinite(expectedIncome) || expectedIncome !== customerTotal - commission) {
    throw new Error('Settlement driver expected income does not match backend money fields');
  }
  if (settlement.currency !== EXPECTED_CURRENCY
    || settlement.customerTotalCurrency !== EXPECTED_CURRENCY
    || settlement.companyCommissionCurrency !== EXPECTED_CURRENCY
    || settlement.driverExpectedIncomeCurrency !== EXPECTED_CURRENCY) {
    throw new Error('Settlement currency fields must all be THB');
  }
  return { customerTotal, commission, expectedIncome };
}

function crc32(buffer) {
  let crc = 0xffffffff;
  for (const byte of buffer) {
    crc ^= byte;
    for (let i = 0; i < 8; i += 1) {
      crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
    }
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngChunk(type, data) {
  const typeBuffer = Buffer.from(type, 'ascii');
  const length = Buffer.alloc(4);
  length.writeUInt32BE(data.length, 0);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuffer, data])), 0);
  return Buffer.concat([length, typeBuffer, data, crc]);
}

function createSyntheticReceiptPng(runId) {
  const width = 1;
  const height = 1;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.from([0, 255, 255, 255, 255]);
  const text = Buffer.from(`Comment\0E2E TEST RECEIPT\nNOT A REAL PAYMENT\n${runId}`, 'latin1');
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr),
    pngChunk('tEXt', text),
    pngChunk('IDAT', zlib.deflateSync(raw)),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

async function uploadReceipt(config, fixture) {
  const bytes = createSyntheticReceiptPng(fixture.runId);
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-settlement-e2e-'));
  const tempPath = path.join(tempDir, `settlement-e2e-receipt-${fixture.runId}.png`);
  fs.writeFileSync(tempPath, bytes);
  try {
    const form = new FormData();
    form.append('file', new Blob([bytes], { type: 'image/png' }), path.basename(tempPath));
    const result = await requestMultipart(
      config,
      `/api/v1/driver/settlements/${fixture.bookingNumber}/receipt`,
      form,
      { headers: bearer(fixture.driverToken) },
    );
    return result;
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function assertSettlementStatus(settlement, expected, label) {
  if (settlement.commissionStatus !== expected) {
    throw new Error(`${label} commissionStatus was ${settlement.commissionStatus}, expected ${expected}`);
  }
}

async function runLifecycle(config, auth, registry) {
  const runId = createRunId();
  const fixture = await prepareFixture(config, runId, auth, registry);

  await transitionDriver(config, fixture, 'start-route');
  await waitForBookingStatus(config, fixture, 'ON_ROUTE');
  await transitionDriver(config, fixture, 'arrive');
  await waitForBookingStatus(config, fixture, 'DRIVER_ARRIVED');
  await transitionDriver(config, fixture, 'mark-picked-up');
  await waitForBookingStatus(config, fixture, 'PICKED_UP');
  registry.update(runId, { pickedUp: true });

  await transitionDriver(config, fixture, 'end-trip');
  await waitForBookingStatus(config, fixture, 'SETTLEMENT_PENDING');
  registry.update(runId, { bookingFinalStatus: 'SETTLEMENT_PENDING' });

  const due = await loadDriverSettlement(config, fixture);
  assertSettlementStatus(due, 'DUE', 'Driver due settlement');
  const money = assertMoneyFields(due);
  registry.update(runId, {
    settlementStatus: due.commissionStatus,
    receiptStatus: due.receiptStatus,
    customerTotal: money.customerTotal,
    companyCommission: money.commission,
    driverExpectedIncome: money.expectedIncome,
  });

  const uploaded = await uploadReceipt(config, fixture);
  assertSettlementStatus(uploaded, 'RECEIPT_SUBMITTED', 'Uploaded driver settlement');
  if (uploaded.receiptStatus !== 'RECEIPT_SUBMITTED' || !uploaded.receiptFileId) {
    throw new Error('Receipt upload did not return submitted receipt metadata');
  }
  registry.update(runId, {
    settlementStatus: uploaded.commissionStatus,
    receiptStatus: uploaded.receiptStatus,
    receiptUploadStatus: 'submitted',
  });

  const adminDetail = await loadAdminSettlement(config, fixture);
  assertSettlementStatus(adminDetail, 'RECEIPT_SUBMITTED', 'Admin settlement detail');
  if (adminDetail.canApprove !== true || !adminDetail.receiptMetadata) {
    throw new Error('Admin settlement detail did not expose approvable receipt metadata');
  }

  const approved = await approveSettlement(config, fixture);
  assertSettlementStatus(approved, 'APPROVED', 'Admin approved settlement');
  if (approved.status !== 'COMPLETED') {
    throw new Error(`Approved booking status was ${approved.status}, expected COMPLETED`);
  }
  await waitForBookingStatus(config, fixture, 'COMPLETED');
  const finalDriverStatus = await loadDriverStatus(config, fixture.driverToken);
  if (finalDriverStatus.hasActiveJob === true) {
    throw new Error('Driver still has an active job after settlement approval');
  }
  registry.update(runId, {
    settlementStatus: approved.commissionStatus,
    receiptStatus: approved.receiptStatus,
    approvalStatus: 'approved',
    bookingFinalStatus: 'COMPLETED',
    driverActiveJobAfterApproval: false,
  });

  return registry.get(runId);
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
    const error = new Error('One or more settlement E2E fixtures failed cleanup');
    error.failures = failures;
    throw error;
  }
}

function writeManifest(config, registry, name = 'settlement-lifecycle-e2e-manifest.json') {
  fs.mkdirSync(config.artifactDir, { recursive: true });
  const manifestPath = path.join(config.artifactDir, name);
  const allowed = registry.records.map((record) => redact({
    runId: record.runId,
    bookingNumber: record.bookingNumber,
    settlementStatus: record.settlementStatus,
    receiptStatus: record.receiptStatus,
    approvalStatus: record.approvalStatus,
    bookingFinalStatus: record.bookingFinalStatus,
    preparationStatus: record.preparationStatus,
    preparationError: record.preparationError,
    cleanupStatus: record.cleanupStatus,
    cleanupError: record.cleanupError,
  }));
  fs.writeFileSync(manifestPath, `${JSON.stringify(allowed, null, 2)}\n`);
  return manifestPath;
}

function buildRunFailure(primaryError, cleanupError) {
  const error = new Error('Settlement lifecycle E2E failed');
  error.name = 'SettlementE2ERunFailure';
  error.primaryError = primaryError ? serializeSafeError(primaryError) : null;
  error.cleanupErrors = cleanupError ? serializeSafeError(cleanupError).cleanupErrors || [serializeSafeError(cleanupError)] : [];
  return error;
}

async function main() {
  const args = parseArgs();
  const env = mergeEnv(loadEnvFile(), process.env);
  if (args.keepFixture) env.TRIDE_E2E_KEEP_FIXTURE = '1';
  const config = buildConfig(env, { requireSecrets: !args.dryRun });
  const dryRunSummary = redact({
    dryRun: true,
    target: config.target,
    frontendHost: config.frontendHost,
    backendHost: config.backendHost,
    hardAllowedHosts: config.allowedHosts,
    adminEmail: config.adminEmail,
    driverEmail: config.driverEmail,
    driverId: config.driverId,
    customerPhone: config.customerPhone,
    marker: E2E_MARKER,
    expectedCommissionAmount: EXPECTED_COMMISSION_AMOUNT,
    expectedCurrency: EXPECTED_CURRENCY,
  });
  if (args.dryRun) {
    console.log(JSON.stringify(dryRunSummary, null, 2));
    return;
  }

  const registry = new FixtureRegistry();
  let primaryError = null;
  let cleanupError = null;
  try {
    const auth = await authenticateAndPreflight(config);
    await runLifecycle(config, auth, registry);
  } catch (err) {
    primaryError = err;
  } finally {
    if (!config.keepFixture) {
      try {
        await cleanupPendingFixtures(config, registry);
      } catch (err) {
        cleanupError = err;
      }
    }
    if (config.keepFixture || registry.records.length) {
      const manifestPath = writeManifest(config, registry);
      console.log(`Redacted settlement E2E manifest: ${manifestPath}`);
    }
  }
  if (primaryError || cleanupError) throw buildRunFailure(primaryError, cleanupError);
  const record = registry.records[0];
  console.log(
    `PASS settlement lifecycle ${record.bookingNumber}; ` +
    `booking=${record.bookingFinalStatus}; settlement=${record.settlementStatus}; ` +
    `receipt=${record.receiptStatus}; cleanup=${record.cleanupStatus}`,
  );
}

if (require.main === module) {
  main().catch((err) => {
    console.error(JSON.stringify(serializeSafeError(err), null, 2));
    process.exit(1);
  });
}

module.exports = {
  EXPECTED_COMMISSION_AMOUNT,
  EXPECTED_CURRENCY,
  assertMoneyFields,
  assertSettlementCleanupCandidate,
  buildRunFailure,
  createSyntheticReceiptPng,
  parseArgs,
  prepareFixture,
  runLifecycle,
  writeManifest,
};
