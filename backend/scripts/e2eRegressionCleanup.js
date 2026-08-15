/**
 * Shared staging E2E regression cleanup helpers.
 * Uses production APIs only — no direct DB updates.
 */
const SCORING = require('../src/constants/driverAssignmentScoring');
const {
  REGRESSION_MARKER,
  TEST_NAME_PREFIX,
} = require('./staging-booking-regression');

const CLEANUP_NOTE = 'E2E regression cleanup';

function responseData(body) {
  return body?.data ?? body;
}

function assertSafeRegressionBookingDetail(detail, record) {
  const data = responseData(detail);
  if (data?.bookingNumber !== record.bookingNumber) {
    throw new Error(`Cleanup detail mismatch for ${record.bookingNumber}`);
  }
  if (!String(data?.customer?.name ?? '').startsWith(TEST_NAME_PREFIX)) {
    throw new Error(`Cleanup refused non-E2E booking ${record.bookingNumber}`);
  }
  if (data?.specialRequests !== REGRESSION_MARKER) {
    throw new Error(`Cleanup refused booking without regression marker ${record.bookingNumber}`);
  }
  return data;
}

function formatCleanupFailure(bookingNumber, reason) {
  return `CLEANUP_FAILED booking=${bookingNumber} reason=${reason}`;
}

async function fetchAdminBookingDetail(baseUrl, adminToken, bookingNumber) {
  const detail = await fetchJson(baseUrl, `/api/v1/admin/bookings/${bookingNumber}`, {
    headers: { authorization: `Bearer ${adminToken}` },
  });
  if (!detail.ok) {
    throw new Error(`Admin booking detail failed: ${detail.body?.error_code || detail.status}`);
  }
  return responseData(detail.body);
}

async function fetchJson(baseUrl, urlPath, options = {}) {
  const response = await fetch(`${baseUrl}${urlPath}`, {
    ...options,
    headers: {
      'content-type': 'application/json',
      ...(options.headers || {}),
    },
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  return { ok: response.ok, status: response.status, body };
}

async function findTestDriver(baseUrl, adminToken, driverDisplayName) {
  const { ok, body } = await fetchJson(baseUrl, '/api/v1/admin/drivers', {
    headers: { authorization: `Bearer ${adminToken}` },
  });
  if (!ok) {
    throw new Error(`Admin drivers list failed: ${body?.error_code || 'unknown'}`);
  }
  const items = responseData(body)?.items ?? responseData(body) ?? [];
  const expectedName = String(driverDisplayName ?? `${TEST_NAME_PREFIX} Regression Driver`);
  const driver = items.find((row) => String(row.displayName ?? '') === expectedName);
  if (!driver) {
    throw new Error(`Test driver not found in admin drivers list: ${expectedName}`);
  }
  return driver;
}

async function assertTestDriverEligibleForNewJob(baseUrl, adminToken, driverDisplayName) {
  const driver = await findTestDriver(baseUrl, adminToken, driverDisplayName);
  const activeCount = Number(driver.activeAssignmentCount ?? 0);
  if (activeCount >= SCORING.MAX_ACTIVE_JOBS) {
    throw new Error(
      `Test driver has ${activeCount} active job(s); requires ${SCORING.MAX_ACTIVE_JOBS - 1} or fewer before creating a new E2E booking`,
    );
  }
  if (!driver.assignmentEligible) {
    throw new Error(`Test driver is not assignment eligible (${driver.eligibilityState ?? 'unknown'})`);
  }
  return driver;
}

async function postDriverTripActions(baseUrl, driverToken, bookingNumber, actions) {
  for (const action of actions) {
    const step = await fetchJson(baseUrl, `/api/v1/driver/bookings/${bookingNumber}/${action}`, {
      method: 'POST',
      headers: { authorization: `Bearer ${driverToken}` },
    });
    if (!step.ok) {
      throw new Error(`${action} failed during E2E teardown: ${step.body?.error_code || step.status}`);
    }
  }
}

async function fetchAdminSettlementDetail(baseUrl, adminToken, bookingNumber) {
  const detail = await fetchJson(
    baseUrl,
    `/api/v1/admin/settlements/${encodeURIComponent(bookingNumber)}`,
    {
      headers: { authorization: `Bearer ${adminToken}` },
    },
  );
  if (detail.status === 404) {
    return null;
  }
  if (!detail.ok) {
    throw new Error(`Admin settlement detail failed: ${detail.body?.error_code || detail.status}`);
  }
  return responseData(detail.body);
}

function settlementHasReceipt(settlementDetail) {
  return Boolean(settlementDetail?.receiptFileId);
}

async function completeSettlementPendingBooking(baseUrl, adminToken, bookingNumber) {
  const settlement = await fetchAdminSettlementDetail(baseUrl, adminToken, bookingNumber);
  const hasReceipt = settlementHasReceipt(settlement);

  if (hasReceipt) {
    const approve = await fetchJson(
      baseUrl,
      `/api/v1/admin/settlements/${encodeURIComponent(bookingNumber)}/approve`,
      {
        method: 'POST',
        headers: { authorization: `Bearer ${adminToken}` },
      },
    );
    if (!approve.ok) {
      throw new Error(`Settlement approve failed: ${approve.body?.error_code || approve.status}`);
    }
    return { path: 'approve', settlement };
  }

  const manual = await fetchJson(
    baseUrl,
    `/api/v1/admin/settlements/${encodeURIComponent(bookingNumber)}/manual-approve`,
    {
      method: 'POST',
      headers: { authorization: `Bearer ${adminToken}` },
      body: JSON.stringify({ note: CLEANUP_NOTE }),
    },
  );
  if (!manual.ok) {
    throw new Error(`Settlement manual-approve failed: ${manual.body?.error_code || manual.status}`);
  }
  return { path: 'manual-approve', settlement };
}

async function teardownRegressionBooking(baseUrl, {
  adminToken,
  driverToken = null,
  bookingNumber,
  payload = null,
}) {
  const record = { bookingNumber, payload: payload ?? { customer: { name: `${TEST_NAME_PREFIX} teardown` } } };
  const detail = await fetchAdminBookingDetail(baseUrl, adminToken, bookingNumber);
  assertSafeRegressionBookingDetail(detail, record);

  switch (detail.status) {
    case 'OPEN':
    case 'CONFIRMED':
    case 'CONTACT_PENDING':
    case 'CONTACT_CONFIRM_REQUESTED':
    case 'CONTACT_VERIFIED':
    case 'COMPLETED':
    case 'CANCELLED':
    case 'NO_SHOW':
      return { action: 'none', status: detail.status };

    case 'DRIVER_ASSIGNED': {
      const unassign = await fetchJson(
        baseUrl,
        `/api/v1/admin/bookings/${bookingNumber}/unassign-driver`,
        {
          method: 'POST',
          headers: { authorization: `Bearer ${adminToken}` },
          body: JSON.stringify({ reason: REGRESSION_MARKER }),
        },
      );
      if (!unassign.ok) {
        throw new Error(`Admin unassign failed: ${unassign.body?.error_code || unassign.status}`);
      }
      return { action: 'unassign', status: detail.status };
    }

    case 'ON_ROUTE':
      if (!driverToken) throw new Error('Driver token required to teardown ON_ROUTE booking');
      await postDriverTripActions(baseUrl, driverToken, bookingNumber, [
        'arrive',
        'mark-picked-up',
        'end-trip',
      ]);
      return teardownRegressionBooking(baseUrl, {
        adminToken,
        driverToken,
        bookingNumber,
        payload,
      });

    case 'DRIVER_ARRIVED':
      if (!driverToken) throw new Error('Driver token required to teardown DRIVER_ARRIVED booking');
      await postDriverTripActions(baseUrl, driverToken, bookingNumber, [
        'mark-picked-up',
        'end-trip',
      ]);
      return teardownRegressionBooking(baseUrl, {
        adminToken,
        driverToken,
        bookingNumber,
        payload,
      });

    case 'PICKED_UP':
      if (!driverToken) throw new Error('Driver token required to teardown PICKED_UP booking');
      await postDriverTripActions(baseUrl, driverToken, bookingNumber, ['end-trip']);
      return teardownRegressionBooking(baseUrl, {
        adminToken,
        driverToken,
        bookingNumber,
        payload,
      });

    case 'SETTLEMENT_PENDING':
      return {
        ...(await completeSettlementPendingBooking(baseUrl, adminToken, bookingNumber)),
        action: 'settlement_complete',
        status: detail.status,
      };

    default:
      throw new Error(`Unsupported booking status for E2E teardown: ${detail.status}`);
  }
}

async function archiveRegressionBookings(baseUrl, adminToken, records) {
  if (!records.length) return { archived: 0 };
  for (const record of records) {
    const detail = await fetchAdminBookingDetail(baseUrl, adminToken, record.bookingNumber);
    assertSafeRegressionBookingDetail(detail, record);
  }
  const body = await fetchJson(baseUrl, '/api/v1/admin/bookings/archive', {
    method: 'POST',
    headers: { authorization: `Bearer ${adminToken}` },
    body: JSON.stringify({
      bookingNumbers: records.map((record) => record.bookingNumber),
      reason: REGRESSION_MARKER,
    }),
  });
  if (!body.ok) {
    throw new Error(`Archive failed: ${body.body?.error_code || body.status}`);
  }
  return responseData(body.body);
}

async function cleanupRegressionBooking(baseUrl, {
  adminToken,
  driverToken = null,
  record,
}) {
  await teardownRegressionBooking(baseUrl, {
    adminToken,
    driverToken,
    bookingNumber: record.bookingNumber,
    payload: record.payload,
  });
  return archiveRegressionBookings(baseUrl, adminToken, [record]);
}

async function cleanupRegressionBookings(baseUrl, {
  adminToken,
  driverToken = null,
  records,
}) {
  for (const record of records) {
    await teardownRegressionBooking(baseUrl, {
      adminToken,
      driverToken,
      bookingNumber: record.bookingNumber,
      payload: record.payload,
    });
  }
  return archiveRegressionBookings(baseUrl, adminToken, records);
}

module.exports = {
  CLEANUP_NOTE,
  assertSafeRegressionBookingDetail,
  assertTestDriverEligibleForNewJob,
  archiveRegressionBookings,
  cleanupRegressionBooking,
  cleanupRegressionBookings,
  formatCleanupFailure,
  fetchAdminSettlementDetail,
  settlementHasReceipt,
  teardownRegressionBooking,
};
