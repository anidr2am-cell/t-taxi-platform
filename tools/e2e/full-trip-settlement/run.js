#!/usr/bin/env node
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { createRequire } = require('node:module');
const {
  E2E_MARKER,
  FixtureRegistry,
  NetworkAudit,
  assertServerCleanupCandidate,
  buildConfig,
  loadEnvFile,
  mergeEnv,
  redact,
  serializeSafeError,
} = require('../customer-driver-location/core');
const {
  authenticateAndPreflight,
  runViewportScenario,
} = require('../customer-driver-location/run');
const {
  assertMoneyFields,
  createSyntheticReceiptPng,
} = require('../settlement-lifecycle/run');

const CUSTOMER_VIEWPORT = { width: 390, height: 844 };

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

async function loadDriverStatus(config, fixture) {
  return requestJson(config, '/api/v1/driver/status', {
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
    body: JSON.stringify({ reason: `${E2E_MARKER} ${fixture.runId}` }),
  });
}

async function uploadReceipt(config, fixture) {
  const bytes = createSyntheticReceiptPng(fixture.runId);
  const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'tride-full-trip-e2e-'));
  const tempPath = path.join(tempDir, `full-trip-settlement-receipt-${fixture.runId}.png`);
  fs.writeFileSync(tempPath, bytes);
  try {
    const form = new FormData();
    const blob = new Blob([bytes], { type: 'image/png' });
    form.append('file', blob, path.basename(tempPath));
    return await requestMultipart(
      config,
      `/api/v1/driver/settlements/${fixture.bookingNumber}/receipt`,
      form,
      { headers: bearer(fixture.driverToken) },
    );
  } finally {
    fs.rmSync(tempDir, { recursive: true, force: true });
  }
}

async function waitForBookingStatus(config, fixture, expectedStatus, timeoutMs = 20000) {
  const started = Date.now();
  let lastStatus = null;
  while (Date.now() - started < timeoutMs) {
    const booking = await getAdminBookingDetail(config, fixture);
    lastStatus = booking?.status;
    if (lastStatus === expectedStatus) return booking;
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  throw new Error(`Timed out waiting for ${expectedStatus}; last status=${lastStatus}`);
}

async function cleanupFixtureVerified(config, fixture, registry) {
  if (!fixture?.bookingNumber) return;
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

function assertDriverReleased(status) {
  if (status?.hasActiveJob === true) {
    throw new Error('Driver still has an active job after settlement approval');
  }
}

function assertFinalCustomerState(booking) {
  if (booking?.status !== 'COMPLETED') {
    throw new Error(`Customer terminal state expected COMPLETED, got ${booking?.status}`);
  }
}

function assignedDriverIdFrom(serverBooking) {
  return Number(
    serverBooking?.assignedDriver?.id ??
    serverBooking?.activeAssignment?.driverId ??
    serverBooking?.assignedDriverId ??
    serverBooking?.driverId ??
    serverBooking?.driver?.id,
  );
}

function assertFullTripApprovalCandidate(fixture, serverBooking, adminSettlement, expectedDriverId) {
  assertServerCleanupCandidate(fixture, serverBooking);
  if (serverBooking?.status !== 'SETTLEMENT_PENDING') {
    throw new Error(
      `Approval refused booking status ${serverBooking?.status}, expected SETTLEMENT_PENDING for ${fixture.runId}`,
    );
  }
  if (adminSettlement?.canApprove !== true) {
    throw new Error(`Approval refused canApprove=false for ${fixture.runId}`);
  }
  if (adminSettlement?.commissionStatus !== 'RECEIPT_SUBMITTED') {
    throw new Error(
      `Approval refused commissionStatus ${adminSettlement?.commissionStatus}, expected RECEIPT_SUBMITTED`,
    );
  }
  if (adminSettlement?.receiptStatus !== 'RECEIPT_SUBMITTED') {
    throw new Error(
      `Approval refused receiptStatus ${adminSettlement?.receiptStatus}, expected RECEIPT_SUBMITTED`,
    );
  }
  if (!adminSettlement?.receiptMetadata) {
    throw new Error(`Approval refused missing receipt metadata for ${fixture.runId}`);
  }
  const assignedDriverId = assignedDriverIdFrom(serverBooking);
  if (!Number.isFinite(assignedDriverId)) {
    throw new Error(`Approval refused missing assigned driver ID for ${fixture.runId}`);
  }
  if (Number(expectedDriverId) !== assignedDriverId) {
    throw new Error(`Approval refused assigned driver mismatch for ${fixture.runId}`);
  }
  return true;
}

async function openBrowser(args) {
  let playwright;
  try {
    playwright = require('@playwright/test');
  } catch (err) {
    const backendRequire = createRequire(path.join(__dirname, '..', '..', '..', 'backend', 'package.json'));
    playwright = backendRequire('@playwright/test');
  }
  const { chromium, firefox, webkit } = playwright;
  const browserType = { chromium, firefox, webkit }[args.project] || chromium;
  return browserType.launch({ headless: !args.headed });
}

function writeManifest(config, registry, name = 'full-trip-settlement-e2e-manifest.json') {
  fs.mkdirSync(config.artifactDir, { recursive: true });
  const manifestPath = path.join(config.artifactDir, name);
  fs.writeFileSync(manifestPath, `${JSON.stringify(registry.manifest().map(redact), null, 2)}\n`);
  return manifestPath;
}

async function runFullTripSettlement(config, args = {}, injected = {}) {
  const registry = injected.registry || new FixtureRegistry();
  const auth = injected.auth || await authenticateAndPreflight(config);
  const browser = injected.browser || await openBrowser(args);
  let fixture = null;
  try {
    const scenarioConfig = { ...config, keepFixture: true };
    await runViewportScenario({
      browser,
      config: scenarioConfig,
      viewport: CUSTOMER_VIEWPORT,
      auth,
      registry,
    });
    fixture = registry.records[0];
    if (!fixture?.bookingNumber) throw new Error('Full trip scenario did not create a fixture');

    const due = await loadDriverSettlement(config, fixture);
    registry.update(fixture.runId, { settlementStatus: due?.commissionStatus || due?.status || 'DUE' });
    assertMoneyFields(due);

    await uploadReceipt(config, fixture);
    registry.update(fixture.runId, { receiptStatus: 'submitted' });

    const approvalBooking = await getAdminBookingDetail(config, fixture);
    const approvalSettlement = await loadAdminSettlement(config, fixture);
    assertFullTripApprovalCandidate(fixture, approvalBooking, approvalSettlement, config.driverId);
    registry.update(fixture.runId, { approvalCandidateVerified: true });

    await approveSettlement(config, fixture);
    const completed = await waitForBookingStatus(config, fixture, 'COMPLETED');
    assertFinalCustomerState(completed);
    registry.update(fixture.runId, {
      approvalStatus: 'approved',
      bookingFinalStatus: completed.status,
      settlementStatus: 'APPROVED',
    });

    const finalDriverStatus = await loadDriverStatus(config, fixture);
    assertDriverReleased(finalDriverStatus);
    registry.update(fixture.runId, { driverActiveJobReleased: true });
    return { fixture, registry };
  } finally {
    if (!injected.browser && browser) {
      await browser.close().catch(() => {});
    }
    if (fixture && !config.keepFixture) {
      await cleanupFixtureVerified(config, fixture, registry);
    }
  }
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
    hardAllowedHosts: config.allowedHosts,
    driverId: config.driverId,
    customerViewport: `${CUSTOMER_VIEWPORT.width}x${CUSTOMER_VIEWPORT.height}`,
    browserProject: args.project,
    marker: E2E_MARKER,
  });
  if (args.dryRun) {
    console.log(JSON.stringify(dryRunSummary, null, 2));
    return;
  }

  const registry = new FixtureRegistry();
  let primaryError = null;
  try {
    await runFullTripSettlement(config, args, { registry });
  } catch (err) {
    primaryError = err;
  } finally {
    if (config.keepFixture || registry.records.length) {
      const manifestPath = writeManifest(config, registry);
      console.log(`Redacted full-trip E2E manifest: ${manifestPath}`);
    }
  }
  if (primaryError) throw primaryError;
  const record = registry.records[0];
  console.log(
    `PASS full trip settlement ${record.bookingNumber}; ` +
    `booking=${record.bookingFinalStatus}; settlement=${record.settlementStatus}; ` +
    `cleanup=${record.cleanupStatus}; driverReleased=${record.driverActiveJobReleased === true}`,
  );
}

if (require.main === module) {
  main().catch((err) => {
    console.error(JSON.stringify(serializeSafeError(err), null, 2));
    process.exit(1);
  });
}

module.exports = {
  CUSTOMER_VIEWPORT,
  NetworkAudit,
  assertDriverReleased,
  assertFullTripApprovalCandidate,
  assertFinalCustomerState,
  parseArgs,
  runFullTripSettlement,
  writeManifest,
};
