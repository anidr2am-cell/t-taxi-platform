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
} = require('../settlement-lifecycle/run');

const MANIFEST_NAME = 'settlement-rejection-resubmission-e2e-manifest.json';
const REJECTION_REASON = 'E2E synthetic receipt is intentionally unreadable';

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

async function prepareSettlementPendingFixture(config, runId, auth, registry) {
  const payload = buildBookingPayload(runId, config.customerPhone);
  const fixture = registry.add({
    runId,
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

async function getAdminBookingDetail(config, fixture) {
  return requestJson(config, `/api/v1/admin/bookings/${fixture.bookingNumber}`, {
    method: 'GET',
    headers: bearer(fixture.adminToken),
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

async function rejectSettlement(config, fixture, reason = REJECTION_REASON) {
  return requestJson(config, `/api/v1/admin/settlements/${fixture.bookingNumber}/reject`, {
    method: 'POST',
    headers: bearer(fixture.adminToken),
    body: JSON.stringify({ reason }),
  });
}

async function approveSettlement(config, fixture) {
  return requestJson(config, `/api/v1/admin/settlements/${fixture.bookingNumber}/approve`, {
    method: 'POST',
    headers: bearer(fixture.adminToken),
    body: JSON.stringify({}),
  });
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

function createSyntheticReceiptPng(runId, version) {
  const width = 1;
  const height = 1;
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8;
  ihdr[9] = 6;
  const raw = Buffer.from([0, 255, 255, 255, 255]);
  const text = Buffer.from(
    `Comment\0E2E TEST RECEIPT ${version}\nNOT A REAL PAYMENT\n${runId}`,
    'latin1',
  );
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    pngChunk('IHDR', ihdr),
    pngChunk('tEXt', text),
    pngChunk('IDAT', zlib.deflateSync(raw)),
    pngChunk('IEND', Buffer.alloc(0)),
  ]);
}

async function uploadReceipt(config, fixture, version) {
  const bytes = createSyntheticReceiptPng(fixture.runId, version);
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-settlement-reupload-e2e-'));
  const tempPath = path.join(tempDir, `settlement-reupload-${version}-${fixture.runId}.png`);
  fs.writeFileSync(tempPath, bytes);
  try {
    const form = new FormData();
    form.append('file', new Blob([bytes], { type: 'image/png' }), path.basename(tempPath));
    return requestMultipart(config, `/api/v1/driver/settlements/${fixture.bookingNumber}/receipt`, form, {
      headers: bearer(fixture.driverToken),
    });
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

function receiptFileId(settlement) {
  const value = settlement?.receiptFileId;
  return value == null ? null : Number(value);
}

function assertRejectedDriverView(settlement) {
  if (settlement.commissionStatus !== 'REJECTED') {
    throw new Error(`Driver settlement status was ${settlement.commissionStatus}, expected REJECTED`);
  }
  if (settlement.receiptStatus !== 'REJECTED') {
    throw new Error(`Driver receipt status was ${settlement.receiptStatus}, expected REJECTED`);
  }
  if (settlement.rejectionReason !== REJECTION_REASON) {
    throw new Error('Driver settlement did not expose the expected rejection reason');
  }
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

async function runRejectionResubmission(config, auth, registry) {
  const runId = createRunId();
  const fixture = await prepareSettlementPendingFixture(config, runId, auth, registry);
  try {
    const v1 = await uploadReceipt(config, fixture, 'V1');
    if (v1.commissionStatus !== 'RECEIPT_SUBMITTED' || v1.receiptStatus !== 'RECEIPT_SUBMITTED') {
      throw new Error('V1 receipt upload did not submit settlement');
    }
    const v1FileId = receiptFileId(v1);
    if (!Number.isFinite(v1FileId)) throw new Error('V1 receipt did not expose receiptFileId');
    registry.update(runId, {
      v1ReceiptStatus: v1.receiptStatus,
      v1ReceiptFileId: v1FileId,
      settlementStatus: v1.commissionStatus,
      receiptStatus: v1.receiptStatus,
    });

    const rejected = await rejectSettlement(config, fixture);
    if (rejected.commissionStatus !== 'REJECTED' || rejected.receiptStatus !== 'REJECTED') {
      throw new Error('Admin reject did not mark settlement rejected');
    }
    if (rejected.receiptFileId != null || rejected.receiptMetadata != null) {
      throw new Error('Rejected settlement still exposes an active receipt');
    }
    if (rejected.rejectionReason !== REJECTION_REASON) {
      throw new Error('Admin reject did not retain the rejection reason');
    }
    const driverRejected = await loadDriverSettlement(config, fixture);
    assertRejectedDriverView(driverRejected);
    registry.update(runId, {
      settlementStatus: rejected.commissionStatus,
      receiptStatus: rejected.receiptStatus,
      rejectionReasonVerified: true,
      oldReceiptInactive: true,
    });

    const v2 = await uploadReceipt(config, fixture, 'V2');
    if (v2.commissionStatus !== 'RECEIPT_SUBMITTED' || v2.receiptStatus !== 'RECEIPT_SUBMITTED') {
      throw new Error('V2 receipt upload did not resubmit settlement');
    }
    const v2FileId = receiptFileId(v2);
    if (!Number.isFinite(v2FileId)) throw new Error('V2 receipt did not expose receiptFileId');
    if (v2FileId === v1FileId) throw new Error('V2 receipt reused the rejected V1 file ID');
    if (v2.rejectionReason != null) throw new Error('V2 resubmission still exposes rejection reason');
    const adminAfterResubmit = await loadAdminSettlement(config, fixture);
    if (adminAfterResubmit.canApprove !== true) {
      throw new Error('Admin cannot approve after V2 receipt resubmission');
    }
    if (receiptFileId(adminAfterResubmit) !== v2FileId) {
      throw new Error('Admin settlement does not reference the active V2 receipt');
    }
    registry.update(runId, {
      v2ReceiptStatus: v2.receiptStatus,
      v2ReceiptFileId: v2FileId,
      settlementStatus: v2.commissionStatus,
      receiptStatus: v2.receiptStatus,
      canApproveAfterResubmission: true,
    });

    const approvalBooking = await getAdminBookingDetail(config, fixture);
    assertSettlementApprovalCandidate(fixture, approvalBooking, adminAfterResubmit, config.driverId);
    const approved = await approveSettlement(config, fixture);
    if (approved.status !== 'COMPLETED' || approved.commissionStatus !== 'APPROVED') {
      throw new Error('Admin approval after resubmission did not complete settlement');
    }
    const finalDriverStatus = await loadDriverStatus(config, fixture.driverToken);
    if (finalDriverStatus.hasActiveJob === true) {
      throw new Error('Driver still has an active job after settlement approval');
    }
    registry.update(runId, {
      approvalCandidateVerified: true,
      settlementStatus: approved.commissionStatus,
      receiptStatus: approved.receiptStatus,
      bookingFinalStatus: approved.status,
      driverActiveJobAfterApproval: false,
    });
    return registry.get(runId);
  } finally {
    if (!config.keepFixture) await cleanupFixtureVerified(config, fixture, registry);
  }
}

function writeManifest(config, registry) {
  fs.mkdirSync(config.artifactDir, { recursive: true });
  const manifestPath = path.join(config.artifactDir, MANIFEST_NAME);
  const allowed = registry.records.map((record) => redact({
    runId: record.runId,
    bookingNumber: record.bookingNumber,
    v1ReceiptStatus: record.v1ReceiptStatus,
    v2ReceiptStatus: record.v2ReceiptStatus,
    settlementStatus: record.settlementStatus,
    receiptStatus: record.receiptStatus,
    rejectionReasonVerified: record.rejectionReasonVerified,
    oldReceiptInactive: record.oldReceiptInactive,
    canApproveAfterResubmission: record.canApproveAfterResubmission,
    approvalCandidateVerified: record.approvalCandidateVerified,
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
  if (args.keepFixture) env.TRIDE_E2E_KEEP_FIXTURE = '1';
  const config = buildConfig(env, { requireSecrets: !args.dryRun });
  const dryRunSummary = redact({
    dryRun: true,
    target: config.target,
    frontendHost: config.frontendHost,
    backendHost: config.backendHost,
    driverId: config.driverId,
    marker: E2E_MARKER,
    expectedCommissionAmount: EXPECTED_COMMISSION_AMOUNT,
    expectedCurrency: EXPECTED_CURRENCY,
    syntheticReceipts: ['E2E TEST RECEIPT V1', 'E2E TEST RECEIPT V2'],
  });
  if (args.dryRun) {
    console.log(JSON.stringify(dryRunSummary, null, 2));
    return;
  }

  const registry = new FixtureRegistry();
  try {
    const auth = await authenticateAndPreflight(config);
    const record = await runRejectionResubmission(config, auth, registry);
    console.log(
      `PASS settlement rejection/resubmission ${record.bookingNumber}; ` +
      `booking=${record.bookingFinalStatus}; settlement=${record.settlementStatus}; ` +
      `cleanup=${record.cleanupStatus}`,
    );
  } finally {
    if (registry.records.length) {
      console.log(`Redacted rejection/resubmission E2E manifest: ${writeManifest(config, registry)}`);
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
  REJECTION_REASON,
  createSyntheticReceiptPng,
  parseArgs,
  writeManifest,
};
