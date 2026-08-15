#!/usr/bin/env node
/**
 * Staging LIVE E2E: settlement approval replay (Phase 3 Step 3).
 * Scenarios A (receipt approve replay) and B (manual approve replay) with semantic conflicts.
 */
const { createBookingSchema } = require('../src/validators/booking.validator');
const {
  assertSafeEnvironment,
  toPricingPayload,
  createBookingIdempotencyKey,
  REGRESSION_MARKER,
  TEST_NAME_PREFIX,
} = require('./staging-booking-regression');
const {
  loadE2eLocalEnv,
  fetchJson,
  login,
  uploadReceipt,
  pdfBytes,
  responseData,
  driveToSettlementPending,
} = require('./staging-receipt-idempotency-e2e');
const {
  assertTestDriverEligibleForNewJob,
  cleanupRegressionBookings,
  formatCleanupFailure,
} = require('./e2eRegressionCleanup');

const RECEIPT_CUSTOMER_NAME = '[E2E] Settlement Approval Replay Receipt';
const MANUAL_CUSTOMER_NAME = '[E2E] Settlement Approval Replay Manual';
const APPROVAL_MODES = {
  RECEIPT_VERIFIED: 'RECEIPT_VERIFIED',
  MANUAL_WITHOUT_RECEIPT: 'MANUAL_WITHOUT_RECEIPT',
};
const RECEIPT_THEN_MANUAL_CONFLICT_CODES = new Set([
  'SETTLEMENT_ALREADY_APPROVED',
  'SETTLEMENT_MANUAL_APPROVAL_NOT_ALLOWED',
]);

function futurePickup(offsetDays = 14) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offsetDays);
  date.setUTCHours(6, 30, 0, 0);
  return date.toISOString();
}

function bookingPayload(customerName, emailLocalPart) {
  return {
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: futurePickup(),
    origin: {
      name: 'Suvarnabhumi Airport',
      address: 'Suvarnabhumi Airport, Bangkok, Thailand',
      placeId: 'staging-bkk',
    },
    destination: {
      name: 'Pattaya',
      address: 'Pattaya, Chon Buri, Thailand',
      placeId: 'staging-pattaya',
    },
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
    transfer: { airportIata: 'BKK', flightNumber: 'TG403' },
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 0, golfBags: 0 },
    options: { nameSign: true, nameSignText: 'E2E Settlement Approval Replay' },
    customer: {
      name: customerName,
      phone: '+66000000005',
      email: `${emailLocalPart}@example.com`,
      countryCode: 'TH',
    },
    additionalRequests: REGRESSION_MARKER,
  };
}

function receiptBookingPayload() {
  return bookingPayload(RECEIPT_CUSTOMER_NAME, 'settlement-approval-replay-receipt');
}

function manualBookingPayload() {
  return bookingPayload(MANUAL_CUSTOMER_NAME, 'settlement-approval-replay-manual');
}

function createEmptyReport() {
  return {
    RECEIPT_BOOKING: null,
    RECEIPT_APPROVE_FIRST_STATUS: null,
    RECEIPT_APPROVE_RETRY_STATUS: null,
    RECEIPT_APPROVAL_MODE: null,
    RECEIPT_COMMISSION_STATUS: null,
    RECEIPT_BOOKING_STATUS: null,
    RECEIPT_THEN_MANUAL_STATUS: null,
    RECEIPT_THEN_MANUAL_ERROR: null,
    MANUAL_BOOKING: null,
    MANUAL_APPROVE_FIRST_STATUS: null,
    MANUAL_APPROVE_RETRY_STATUS: null,
    MANUAL_APPROVAL_MODE: null,
    MANUAL_COMMISSION_STATUS: null,
    MANUAL_BOOKING_STATUS: null,
    MANUAL_THEN_UPLOAD_STATUS: null,
    MANUAL_THEN_UPLOAD_ERROR: null,
  };
}

function assertSafeE2ePayload(payload) {
  if (!String(payload?.customer?.name ?? '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error('E2E payload customer name must start with [E2E]');
  }
  if (payload?.additionalRequests !== REGRESSION_MARKER) {
    throw new Error('E2E payload must use AUTOMATED_REGRESSION_TEST marker');
  }
}

function extractSettlementState(detail) {
  return {
    bookingStatus: detail?.status ?? null,
    commissionStatus: detail?.commissionStatus ?? null,
    approvalMode: detail?.approvalMode ?? detail?.approval?.mode ?? null,
  };
}

function countApprovedReviewEntries(reviewHistory, approvalMode) {
  return (reviewHistory ?? []).filter(
    (entry) => entry.action === 'APPROVED' && entry.approvalMode === approvalMode,
  ).length;
}

function assertReceiptApproveReplay(firstStatus, retryStatus, firstDetail, retryDetail) {
  if (firstStatus !== 200 || retryStatus !== 200) {
    throw new Error(`Expected receipt approve replay 200/200, got ${firstStatus}/${retryStatus}`);
  }
  const first = extractSettlementState(firstDetail);
  const retry = extractSettlementState(retryDetail);
  if (first.bookingStatus !== 'COMPLETED' || first.commissionStatus !== 'APPROVED') {
    throw new Error(`Receipt first approve state invalid: ${JSON.stringify(first)}`);
  }
  if (first.approvalMode !== APPROVAL_MODES.RECEIPT_VERIFIED) {
    throw new Error(`Receipt approvalMode expected RECEIPT_VERIFIED, got ${first.approvalMode}`);
  }
  if (JSON.stringify(first) !== JSON.stringify(retry)) {
    throw new Error('Receipt approve retry changed durable settlement state');
  }
  const approvedEntries = countApprovedReviewEntries(
    retryDetail?.reviewHistory,
    APPROVAL_MODES.RECEIPT_VERIFIED,
  );
  if (approvedEntries !== 1) {
    throw new Error(`Expected 1 RECEIPT_VERIFIED reviewHistory entry, got ${approvedEntries}`);
  }
}

function assertManualApproveReplay(firstStatus, retryStatus, firstDetail, retryDetail) {
  if (firstStatus !== 200 || retryStatus !== 200) {
    throw new Error(`Expected manual approve replay 200/200, got ${firstStatus}/${retryStatus}`);
  }
  const first = extractSettlementState(firstDetail);
  const retry = extractSettlementState(retryDetail);
  if (first.bookingStatus !== 'COMPLETED' || first.commissionStatus !== 'APPROVED') {
    throw new Error(`Manual first approve state invalid: ${JSON.stringify(first)}`);
  }
  if (first.approvalMode !== APPROVAL_MODES.MANUAL_WITHOUT_RECEIPT) {
    throw new Error(`Manual approvalMode expected MANUAL_WITHOUT_RECEIPT, got ${first.approvalMode}`);
  }
  if (JSON.stringify(first) !== JSON.stringify(retry)) {
    throw new Error('Manual approve retry changed durable settlement state');
  }
  const approvedEntries = countApprovedReviewEntries(
    retryDetail?.reviewHistory,
    APPROVAL_MODES.MANUAL_WITHOUT_RECEIPT,
  );
  if (approvedEntries !== 1) {
    throw new Error(`Expected 1 MANUAL_WITHOUT_RECEIPT reviewHistory entry, got ${approvedEntries}`);
  }
}

function assertReceiptThenManualConflict(status, errorCode) {
  if (status === 200) {
    throw new Error('Receipt-then-manual must not return replay 200 as MANUAL_WITHOUT_RECEIPT');
  }
  if (status !== 409) {
    throw new Error(`Receipt-then-manual expected 409 conflict, got ${status}`);
  }
  if (!RECEIPT_THEN_MANUAL_CONFLICT_CODES.has(errorCode)) {
    throw new Error(`Receipt-then-manual unexpected error code: ${errorCode}`);
  }
}

function assertManualThenUploadConflict(status, errorCode) {
  if (status !== 409 || errorCode !== 'RECEIPT_ALREADY_APPROVED') {
    throw new Error(`Manual-then-upload expected 409 RECEIPT_ALREADY_APPROVED, got ${status} ${errorCode}`);
  }
}

function parseReportField(logText, fieldName) {
  const match = String(logText).match(new RegExp(`"${fieldName}":\\s*"([^"]+)"`));
  return match ? match[1] : null;
}

function parseReportFromLog(logText) {
  const report = createEmptyReport();
  for (const key of Object.keys(report)) {
    const stringMatch = String(logText).match(new RegExp(`"${key}":\\s*"([^"]+)"`));
    const numberMatch = String(logText).match(new RegExp(`"${key}":\\s*(\\d+)`));
    const nullMatch = String(logText).match(new RegExp(`"${key}":\\s*null`));
    if (stringMatch) report[key] = stringMatch[1];
    else if (numberMatch) report[key] = Number(numberMatch[1]);
    else if (nullMatch) report[key] = null;
  }
  return report;
}

function parseDbCheckRow(rowText) {
  const [
    status,
    commissionStatus,
    commissionPaidAtSet,
    commissionApprovedCount,
    manualApprovedCount,
    settlementApprovedOutboxCount,
    activeAssignmentCount,
    activeReceiptFiles,
  ] = String(rowText).trim().split('\t');
  return {
    status,
    commissionStatus,
    commissionPaidAtSet: Number(commissionPaidAtSet),
    commissionApprovedCount: Number(commissionApprovedCount),
    manualApprovedCount: Number(manualApprovedCount),
    settlementApprovedOutboxCount: Number(settlementApprovedOutboxCount),
    activeAssignmentCount: Number(activeAssignmentCount),
    activeReceiptFiles: Number(activeReceiptFiles),
  };
}

function assertReceiptDbSideEffects(row) {
  if (row.commissionApprovedCount !== 1) {
    throw new Error(`DB receipt commission_approved_count expected 1, got ${row.commissionApprovedCount}`);
  }
  if (row.manualApprovedCount !== 0) {
    throw new Error(`DB receipt manual_approved_count expected 0, got ${row.manualApprovedCount}`);
  }
  if (row.settlementApprovedOutboxCount !== 1) {
    throw new Error(`DB receipt settlement.approved outbox expected 1, got ${row.settlementApprovedOutboxCount}`);
  }
  if (row.status !== 'COMPLETED' || row.commissionStatus !== 'PAID' || row.commissionPaidAtSet !== 1) {
    throw new Error(`DB receipt booking settlement state invalid: ${JSON.stringify(row)}`);
  }
  if (row.activeAssignmentCount !== 0) {
    throw new Error(`DB receipt active assignments expected 0, got ${row.activeAssignmentCount}`);
  }
}

function assertManualDbSideEffects(row) {
  if (row.manualApprovedCount !== 1) {
    throw new Error(`DB manual manual_approved_count expected 1, got ${row.manualApprovedCount}`);
  }
  if (row.commissionApprovedCount !== 0) {
    throw new Error(`DB manual commission_approved_count expected 0, got ${row.commissionApprovedCount}`);
  }
  if (row.settlementApprovedOutboxCount !== 1) {
    throw new Error(`DB manual settlement.approved outbox expected 1, got ${row.settlementApprovedOutboxCount}`);
  }
  if (row.activeReceiptFiles !== 0) {
    throw new Error(`DB manual active_receipt_files expected 0, got ${row.activeReceiptFiles}`);
  }
  if (row.status !== 'COMPLETED' || row.commissionStatus !== 'PAID' || row.commissionPaidAtSet !== 1) {
    throw new Error(`DB manual booking settlement state invalid: ${JSON.stringify(row)}`);
  }
  if (row.activeAssignmentCount !== 0) {
    throw new Error(`DB manual active assignments expected 0, got ${row.activeAssignmentCount}`);
  }
}

async function getSettlementDetail(baseUrl, adminToken, bookingNumber) {
  const detail = await fetchJson(
    baseUrl,
    `/api/v1/admin/settlements/${encodeURIComponent(bookingNumber)}`,
    { headers: { authorization: `Bearer ${adminToken}` } },
  );
  if (!detail.ok) {
    throw new Error(`Settlement detail failed: ${detail.body?.error_code || detail.status}`);
  }
  return responseData(detail.body);
}

async function postApprove(baseUrl, adminToken, bookingNumber) {
  return fetchJson(
    baseUrl,
    `/api/v1/admin/settlements/${encodeURIComponent(bookingNumber)}/approve`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${adminToken}` },
    },
  );
}

async function postManualApprove(baseUrl, adminToken, bookingNumber, note = REGRESSION_MARKER) {
  return fetchJson(
    baseUrl,
    `/api/v1/admin/settlements/${encodeURIComponent(bookingNumber)}/manual-approve`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${adminToken}` },
      body: JSON.stringify({ note }),
    },
  );
}

function assertManualPreconditions(detail) {
  if (detail?.canManualApprove !== true) {
    throw new Error('Manual scenario requires canManualApprove=true');
  }
  if (detail?.receiptFileId != null) {
    throw new Error('Manual scenario requires receiptFileId absent');
  }
  if (!(Number(detail?.commissionAmount) > 0)) {
    throw new Error('Manual scenario requires commission amount > 0');
  }
}

async function createRegressionBooking(baseUrl, payload) {
  assertSafeE2ePayload(payload);
  const { error } = createBookingSchema.validate(payload, { abortEarly: false });
  if (error) throw new Error(`Invalid payload: ${error.message}`);

  await fetchJson(baseUrl, '/api/v1/bookings/pricing/calculate', {
    method: 'POST',
    body: JSON.stringify(toPricingPayload(payload)),
  });
  const created = await fetchJson(baseUrl, '/api/v1/bookings', {
    method: 'POST',
    headers: { 'Idempotency-Key': createBookingIdempotencyKey() },
    body: JSON.stringify(payload),
  });
  if (!created.ok) {
    throw new Error(`Create booking failed: ${created.body?.error_code}`);
  }
  const createdData = responseData(created.body);
  if (!createdData?.bookingNumber) throw new Error('Create booking missing bookingNumber');
  return {
    bookingNumber: createdData.bookingNumber,
    guestAccessToken: createdData.guestAccessToken,
    payload,
  };
}

async function runReceiptScenario(baseUrl, { adminToken, driverToken, report }) {
  const { bookingNumber, guestAccessToken, payload } = await createRegressionBooking(
    baseUrl,
    receiptBookingPayload(),
  );
  report.RECEIPT_BOOKING = bookingNumber;

  await driveToSettlementPending(baseUrl, {
    adminToken,
    driverToken,
    bookingNumber,
    guestAccessToken,
  });

  const receiptKey = createBookingIdempotencyKey();
  const upload = await uploadReceipt(
    baseUrl,
    driverToken,
    bookingNumber,
    pdfBytes('approval-replay-receipt'),
    receiptKey,
  );
  if (!upload.ok) {
    throw new Error(`Receipt upload failed: ${upload.body?.error_code}`);
  }

  const firstApprove = await postApprove(baseUrl, adminToken, bookingNumber);
  report.RECEIPT_APPROVE_FIRST_STATUS = firstApprove.status;
  const firstDetail = responseData(firstApprove.body);

  const retryApprove = await postApprove(baseUrl, adminToken, bookingNumber);
  report.RECEIPT_APPROVE_RETRY_STATUS = retryApprove.status;
  const retryDetail = responseData(retryApprove.body);

  assertReceiptApproveReplay(
    report.RECEIPT_APPROVE_FIRST_STATUS,
    report.RECEIPT_APPROVE_RETRY_STATUS,
    firstDetail,
    retryDetail,
  );

  const settled = extractSettlementState(retryDetail);
  report.RECEIPT_APPROVAL_MODE = settled.approvalMode;
  report.RECEIPT_COMMISSION_STATUS = settled.commissionStatus;
  report.RECEIPT_BOOKING_STATUS = settled.bookingStatus;

  const receiptThenManual = await postManualApprove(baseUrl, adminToken, bookingNumber);
  report.RECEIPT_THEN_MANUAL_STATUS = receiptThenManual.status;
  report.RECEIPT_THEN_MANUAL_ERROR = receiptThenManual.body?.error_code ?? null;
  assertReceiptThenManualConflict(report.RECEIPT_THEN_MANUAL_STATUS, report.RECEIPT_THEN_MANUAL_ERROR);

  return { bookingNumber, payload };
}

async function runManualScenario(baseUrl, { adminToken, driverToken, report }) {
  const { bookingNumber, guestAccessToken, payload } = await createRegressionBooking(
    baseUrl,
    manualBookingPayload(),
  );
  report.MANUAL_BOOKING = bookingNumber;

  await driveToSettlementPending(baseUrl, {
    adminToken,
    driverToken,
    bookingNumber,
    guestAccessToken,
  });

  const preDetail = await getSettlementDetail(baseUrl, adminToken, bookingNumber);
  assertManualPreconditions(preDetail);

  const firstManual = await postManualApprove(baseUrl, adminToken, bookingNumber);
  report.MANUAL_APPROVE_FIRST_STATUS = firstManual.status;
  const firstDetail = responseData(firstManual.body);

  const retryManual = await postManualApprove(baseUrl, adminToken, bookingNumber);
  report.MANUAL_APPROVE_RETRY_STATUS = retryManual.status;
  const retryDetail = responseData(retryManual.body);

  assertManualApproveReplay(
    report.MANUAL_APPROVE_FIRST_STATUS,
    report.MANUAL_APPROVE_RETRY_STATUS,
    firstDetail,
    retryDetail,
  );

  const settled = extractSettlementState(retryDetail);
  report.MANUAL_APPROVAL_MODE = settled.approvalMode;
  report.MANUAL_COMMISSION_STATUS = settled.commissionStatus;
  report.MANUAL_BOOKING_STATUS = settled.bookingStatus;

  const manualThenUpload = await uploadReceipt(
    baseUrl,
    driverToken,
    bookingNumber,
    pdfBytes('approval-replay-manual-conflict'),
    createBookingIdempotencyKey(),
  );
  report.MANUAL_THEN_UPLOAD_STATUS = manualThenUpload.status;
  report.MANUAL_THEN_UPLOAD_ERROR = manualThenUpload.body?.error_code ?? null;
  assertManualThenUploadConflict(report.MANUAL_THEN_UPLOAD_STATUS, report.MANUAL_THEN_UPLOAD_ERROR);

  return { bookingNumber, payload };
}

async function main() {
  loadE2eLocalEnv();
  const { baseUrl } = assertSafeEnvironment({ dryRun: false });
  const report = createEmptyReport();

  let adminToken;
  let driverToken;
  let driverDisplayName;
  let driverWasOnline = false;
  const records = [];
  let scenariosCompleted = false;

  try {
    const adminLogin = await login(baseUrl, process.env.TRIDE_ADMIN_EMAIL, process.env.TRIDE_ADMIN_PASSWORD);
    const driverLogin = await login(
      baseUrl,
      process.env.TRIDE_TEST_DRIVER_EMAIL,
      process.env.TRIDE_TEST_DRIVER_PASSWORD,
    );
    adminToken = adminLogin.token;
    driverToken = driverLogin.token;
    driverDisplayName = driverLogin.user?.name ?? `${TEST_NAME_PREFIX} Regression Driver`;

    await fetchJson(baseUrl, '/api/v1/driver/online', {
      method: 'POST',
      headers: { authorization: `Bearer ${driverToken}` },
    });
    driverWasOnline = true;

    await assertTestDriverEligibleForNewJob(baseUrl, adminToken, driverDisplayName);

    records.push(await runReceiptScenario(baseUrl, { adminToken, driverToken, report }));
    records.push(await runManualScenario(baseUrl, { adminToken, driverToken, report }));
    scenariosCompleted = true;

    console.log(JSON.stringify(report, null, 2));

    await cleanupRegressionBookings(baseUrl, { adminToken, driverToken, records });
    await assertTestDriverEligibleForNewJob(baseUrl, adminToken, driverDisplayName);

    console.log('PASS settlement approval replay E2E');
  } catch (err) {
    console.error(`FAIL settlement approval replay E2E: ${err.message}`);
    console.log(JSON.stringify(report, null, 2));
    process.exitCode = 1;

    if (adminToken) {
      const cleanupTargets = [...records];
      const seen = new Set(cleanupTargets.map((record) => record.bookingNumber));
      if (report.RECEIPT_BOOKING && !seen.has(report.RECEIPT_BOOKING)) {
        cleanupTargets.push({ bookingNumber: report.RECEIPT_BOOKING, payload: receiptBookingPayload() });
      }
      if (report.MANUAL_BOOKING && !seen.has(report.MANUAL_BOOKING)) {
        cleanupTargets.push({ bookingNumber: report.MANUAL_BOOKING, payload: manualBookingPayload() });
      }
      for (const record of cleanupTargets) {
        try {
          await cleanupRegressionBookings(baseUrl, { adminToken, driverToken, records: [record] });
        } catch (cleanupErr) {
          console.error(formatCleanupFailure(record.bookingNumber, cleanupErr.message));
        }
      }
    }
  } finally {
    if (driverWasOnline && driverToken) {
      try {
        await fetchJson(baseUrl, '/api/v1/driver/offline', {
          method: 'POST',
          headers: { authorization: `Bearer ${driverToken}` },
        });
      } catch (offlineErr) {
        console.error(`Driver offline cleanup failed: ${offlineErr.message}`);
        process.exitCode = 1;
      }
    }
  }
}

if (require.main === module) {
  main().catch((err) => {
    console.error(err.message);
    process.exit(1);
  });
}

module.exports = {
  APPROVAL_MODES,
  RECEIPT_THEN_MANUAL_CONFLICT_CODES,
  REGRESSION_MARKER,
  TEST_NAME_PREFIX,
  assertManualApproveReplay,
  assertManualDbSideEffects,
  assertManualPreconditions,
  assertManualThenUploadConflict,
  assertReceiptApproveReplay,
  assertReceiptDbSideEffects,
  assertReceiptThenManualConflict,
  assertSafeE2ePayload,
  createEmptyReport,
  extractSettlementState,
  manualBookingPayload,
  parseDbCheckRow,
  parseReportField,
  parseReportFromLog,
  receiptBookingPayload,
};
