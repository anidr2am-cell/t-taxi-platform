const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const UrgentNegotiationService = require('../src/services/urgentNegotiation.service');
const ERROR_CODES = require('../src/constants/errorCodes');
const HTTP_STATUS = require('../src/constants/httpStatus');
const {
  DRIVER_ALL_ROOM,
  driverUserRoom,
  guestBookingRoom,
  setRealtimeIo,
} = require('../src/socket/realtime');

const BOOKING_NUMBER = 'TX202607230001';

function createConn() {
  return {
    began: false,
    committed: false,
    rolledBack: false,
    released: false,
    async beginTransaction() { this.began = true; },
    async commit() { this.committed = true; },
    async rollback() { this.rolledBack = true; },
    release() { this.released = true; },
  };
}

function createPool(conn = createConn()) {
  return {
    conn,
    async getConnection() { return conn; },
  };
}

function createNegotiationState(overrides = {}) {
  return {
    id: 100,
    booking_id: 10,
    status: 'BROADCASTING',
    attempt_count: 0,
    locked_driver_id: null,
    lock_expires_at: '2026-07-23 01:30:00.000',
    ...overrides,
  };
}

function createBookingState(overrides = {}) {
  return {
    id: 10,
    booking_number: BOOKING_NUMBER,
    is_urgent_request: 1,
    urgent_negotiation_id: 100,
    status: 'OPEN',
    ...overrides,
  };
}

function createHarness(overrides = {}) {
  const conn = createConn();
  const pool = createPool(conn);
  const calls = {
    attempts: [],
    lockCalls: [],
  };

  let booking = createBookingState(overrides.booking);
  let negotiation = overrides.negotiation === null
    ? null
    : createNegotiationState(overrides.negotiation);

  const urgentNegotiationRepository = {
    async findBookingForUrgentLock(_conn, bookingNumber) {
      if (overrides.missingBooking) return null;
      if (booking.booking_number !== bookingNumber) return null;
      return { ...booking };
    },
    async findBroadcastingNegotiationForUpdate(_conn, bookingId) {
      if (!negotiation || negotiation.booking_id !== bookingId) return null;
      if (negotiation.status !== 'BROADCASTING') return null;
      return { ...negotiation };
    },
    async lockNegotiationIfBroadcasting(_conn, { negotiationId, driverId }) {
      calls.lockCalls.push({ negotiationId, driverId });
      if (!negotiation || negotiation.id !== negotiationId) return 0;
      if (negotiation.status !== 'BROADCASTING' || negotiation.locked_driver_id != null) {
        return 0;
      }
      negotiation = {
        ...negotiation,
        status: 'LOCKED',
        locked_driver_id: driverId,
        lock_expires_at: '2026-07-23 01:30:00.000',
      };
      return 1;
    },
    async findNegotiationById(_conn, negotiationId) {
      if (!negotiation || negotiation.id !== negotiationId) return null;
      return { ...negotiation };
    },
    async insertAttempt(_conn, row) {
      calls.attempts.push(row);
      return calls.attempts.length;
    },
    getNegotiation() { return negotiation; },
  };

  const driverRepository = {
    async findByUserIdForUpdate(_conn, userId) {
      const drivers = {
        42: { id: 7, user_id: 42, name: 'Driver A', is_active: 1, user_is_active: 1 },
        43: { id: 8, user_id: 43, name: 'Driver B', is_active: 1, user_is_active: 1 },
      };
      return drivers[userId] || null;
    },
    async findById(driverId) {
      const drivers = {
        7: { id: 7, user_id: 42, name: 'Driver A' },
        8: { id: 8, user_id: 43, name: 'Driver B' },
      };
      return drivers[driverId] || null;
    },
  };

  const driverJobService = {
    validateBookingNumber(value) {
      if (!/^TX\d{12}$/.test(String(value || ''))) {
        const AppError = require('../src/utils/AppError');
        throw new AppError('Invalid booking number', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      return String(value);
    },
  };

  const service = new UrgentNegotiationService(
    pool,
    urgentNegotiationRepository,
    driverRepository,
    driverJobService,
    null,
    null,
    null,
  );

  return {
    service,
    conn,
    calls,
    urgentNegotiationRepository,
    getNegotiation: () => urgentNegotiationRepository.getNegotiation(),
  };
}

function captureSocket() {
  const emitted = [];
  setRealtimeIo({
    to(room) {
      return {
        emit(event, payload) {
          emitted.push({ room, event, payload });
        },
      };
    },
  });
  return emitted;
}

test('lockNegotiation succeeds for BROADCASTING negotiation and creates attempt row', async () => {
  const emitted = captureSocket();
  const { service, conn, calls } = createHarness();

  const result = await service.lockNegotiation(42, BOOKING_NUMBER);

  assert.equal(conn.committed, true);
  assert.equal(conn.rolledBack, false);
  assert.equal(result.negotiationId, 100);
  assert.equal(result.attemptNumber, 1);
  assert.equal(result.driverId, 7);
  assert.equal(result.status, 'LOCKED');
  assert.deepEqual(calls.attempts, [{
    negotiationId: 100,
    attemptNumber: 1,
    driverId: 7,
  }]);
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42) && row.event === 'driver:urgent-call:eta-required'),
    true,
  );
  assert.equal(
    emitted.some((row) => row.room === DRIVER_ALL_ROOM && row.event === 'driver:urgent-call:locked'),
    true,
  );
  setRealtimeIo(null);
});

test('concurrent lock attempts allow only one success and one URGENT_ALREADY_LOCKED', async () => {
  let negotiation = createNegotiationState();
  const booking = createBookingState();
  const calls = { lockCalls: [], attempts: [] };

  const urgentNegotiationRepository = {
    async findBookingForUrgentLock() { return { ...booking }; },
    async findBroadcastingNegotiationForUpdate() {
      if (negotiation.status !== 'BROADCASTING') return null;
      return { ...negotiation };
    },
    async lockNegotiationIfBroadcasting(_conn, { negotiationId, driverId }) {
      calls.lockCalls.push({ negotiationId, driverId });
      if (negotiation.status !== 'BROADCASTING' || negotiation.locked_driver_id != null) {
        return 0;
      }
      negotiation = {
        ...negotiation,
        status: 'LOCKED',
        locked_driver_id: driverId,
      };
      return 1;
    },
    async findNegotiationById(_conn, negotiationId) {
      return negotiation.id === negotiationId ? { ...negotiation } : null;
    },
    async insertAttempt(_conn, row) {
      calls.attempts.push(row);
      return calls.attempts.length;
    },
  };

  const driverRepository = {
    async findByUserIdForUpdate(_conn, userId) {
      return userId === 42
        ? { id: 7, user_id: 42, is_active: 1, user_is_active: 1 }
        : { id: 8, user_id: 43, is_active: 1, user_is_active: 1 };
    },
  };

  const driverJobService = {
    validateBookingNumber(value) { return String(value); },
  };

  const service = new UrgentNegotiationService(
    createPool(),
    urgentNegotiationRepository,
    driverRepository,
    driverJobService,
  );

  setRealtimeIo({
    to() {
      return { emit() {} };
    },
  });

  const results = await Promise.allSettled([
    service.lockNegotiation(42, BOOKING_NUMBER),
    service.lockNegotiation(43, BOOKING_NUMBER),
  ]);

  const fulfilled = results.filter((row) => row.status === 'fulfilled');
  const rejected = results.filter((row) => row.status === 'rejected');

  assert.equal(fulfilled.length, 1);
  assert.equal(rejected.length, 1);
  assert.equal(rejected[0].reason.errorCode, ERROR_CODES.URGENT_ALREADY_LOCKED);
  assert.equal(calls.lockCalls.length, 2);
  assert.equal(calls.attempts.length, 1);
  setRealtimeIo(null);
});

test('lockNegotiation rejects when negotiation is already LOCKED', async () => {
  const { service } = createHarness({
    negotiation: {
      id: 100,
      booking_id: 10,
      status: 'LOCKED',
      attempt_count: 1,
      locked_driver_id: 7,
    },
  });

  await assert.rejects(
    () => service.lockNegotiation(43, BOOKING_NUMBER),
    (error) => error.errorCode === ERROR_CODES.URGENT_NEGOTIATION_NOT_BROADCASTING
      && error.statusCode === HTTP_STATUS.CONFLICT,
  );
});

test('lockNegotiation returns 404 for missing booking', async () => {
  const { service } = createHarness({ missingBooking: true });

  await assert.rejects(
    () => service.lockNegotiation(42, BOOKING_NUMBER),
    (error) => error.errorCode === ERROR_CODES.NOT_FOUND
      && error.statusCode === HTTP_STATUS.NOT_FOUND,
  );
});

test('lockNegotiation returns 400 when booking is not urgent', async () => {
  const { service } = createHarness({
    booking: { is_urgent_request: 0 },
  });

  await assert.rejects(
    () => service.lockNegotiation(42, BOOKING_NUMBER),
    (error) => error.errorCode === ERROR_CODES.URGENT_NOT_URGENT_BOOKING
      && error.statusCode === HTTP_STATUS.BAD_REQUEST,
  );
});

const SUBMIT_NOW_MS = Date.parse('2099-07-23 01:30:00+07:00');

function createSubmitEtaHarness(overrides = {}) {
  const conn = createConn();
  const pool = createPool(conn);
  const calls = {
    awaitingCustomer: [],
    attemptUpdates: [],
  };

  let booking = createBookingState({
    scheduled_pickup_at: '2099-07-23 02:00:00',
    customer_user_id: 99,
    ...overrides.booking,
  });

  let negotiation = overrides.negotiation === null
    ? null
    : createNegotiationState({
      status: 'LOCKED',
      locked_driver_id: 7,
      lock_expires_at: '2099-07-23 01:35:00.000',
      min_required_eta_minutes: null,
      ...overrides.negotiation,
    });

  let attempts = overrides.attempts ?? [{
    id: 1,
    negotiation_id: 100,
    attempt_number: 1,
    driver_id: 7,
    proposed_eta_minutes: null,
    eta_submitted_at: null,
    outcome: 'IN_PROGRESS',
  }];

  const urgentNegotiationRepository = {
    async findBookingForUrgentLock(_conn, bookingNumber) {
      if (overrides.missingBooking) return null;
      if (booking.booking_number !== bookingNumber) return null;
      return { ...booking };
    },
    async findNegotiationByBookingIdForUpdate(_conn, bookingId) {
      if (!negotiation || negotiation.booking_id !== bookingId) return null;
      return { ...negotiation };
    },
    async markNegotiationAwaitingCustomer(_conn, negotiationId) {
      calls.awaitingCustomer.push(negotiationId);
      if (!negotiation || negotiation.id !== negotiationId || negotiation.status !== 'LOCKED') {
        return null;
      }
      negotiation = {
        ...negotiation,
        status: 'AWAITING_CUSTOMER',
        customer_decision_expires_at: '2099-07-23 01:32:00.000',
      };
      return { ...negotiation };
    },
    async updateLatestAttemptEta(_conn, { negotiationId, etaMinutes }) {
      calls.attemptUpdates.push({ negotiationId, etaMinutes });
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      if (!latest) return 0;
      latest.proposed_eta_minutes = etaMinutes;
      latest.eta_submitted_at = '2099-07-23 01:30:00.000';
      return 1;
    },
    async findLatestAttempt(_conn, negotiationId) {
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      return latest ? { ...latest } : null;
    },
    getNegotiation() { return negotiation; },
    getAttempts() { return attempts.map((row) => ({ ...row })); },
  };

  const driverRepository = {
    async findByUserIdForUpdate(_conn, userId) {
      const drivers = {
        42: { id: 7, user_id: 42, is_active: 1, user_is_active: 1 },
        43: { id: 8, user_id: 43, is_active: 1, user_is_active: 1 },
      };
      return drivers[userId] || null;
    },
  };

  const driverJobService = {
    validateBookingNumber(value) {
      if (!/^TX\d{12}$/.test(String(value || ''))) {
        const AppError = require('../src/utils/AppError');
        throw new AppError('Invalid booking number', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      return String(value);
    },
  };

  const service = new UrgentNegotiationService(
    pool,
    urgentNegotiationRepository,
    driverRepository,
    driverJobService,
    null,
    null,
    null,
  );

  return {
    service,
    conn,
    calls,
    getNegotiation: urgentNegotiationRepository.getNegotiation,
    getAttempts: urgentNegotiationRepository.getAttempts,
  };
}

test('submitEta moves LOCKED negotiation to AWAITING_CUSTOMER and updates attempt row', async () => {
  const emitted = captureSocket();
  const { service, conn, calls, getNegotiation, getAttempts } = createSubmitEtaHarness();

  const result = await service.submitEta(42, BOOKING_NUMBER, 25, { nowMs: SUBMIT_NOW_MS });

  assert.equal(conn.committed, true);
  assert.equal(result.status, 'AWAITING_CUSTOMER');
  assert.equal(result.etaMinutes, 25);
  assert.equal(result.customerDecisionExpiresAt, '2099-07-23 01:32:00.000');
  assert.equal(getNegotiation().status, 'AWAITING_CUSTOMER');
  assert.deepEqual(calls.attemptUpdates, [{ negotiationId: 100, etaMinutes: 25 }]);
  assert.equal(getAttempts()[0].proposed_eta_minutes, 25);
  assert.equal(
    emitted.some((row) => row.room === guestBookingRoom(10)
      && row.event === 'booking:urgent-negotiation:eta-proposed'
      && row.payload.etaMinutes === 25),
    true,
  );
  setRealtimeIo(null);
});

test('submitEta rejects when negotiation is not LOCKED', async () => {
  const { service } = createSubmitEtaHarness({
    negotiation: { status: 'BROADCASTING', locked_driver_id: null },
  });

  await assert.rejects(
    () => service.submitEta(42, BOOKING_NUMBER, 25, { nowMs: SUBMIT_NOW_MS }),
    (error) => error.errorCode === ERROR_CODES.URGENT_NOT_LOCKED
      && error.statusCode === HTTP_STATUS.CONFLICT,
  );
});

test('submitEta rejects when caller is not the locked driver', async () => {
  const { service } = createSubmitEtaHarness();

  await assert.rejects(
    () => service.submitEta(43, BOOKING_NUMBER, 25, { nowMs: SUBMIT_NOW_MS }),
    (error) => error.errorCode === ERROR_CODES.URGENT_NOT_LOCKED_DRIVER
      && error.statusCode === HTTP_STATUS.FORBIDDEN,
  );
});

test('submitEta rejects after lock_expires_at has passed', async () => {
  const { service } = createSubmitEtaHarness({
    negotiation: { lock_expires_at: '2099-07-23 01:29:00.000' },
  });

  await assert.rejects(
    () => service.submitEta(42, BOOKING_NUMBER, 25, { nowMs: SUBMIT_NOW_MS }),
    (error) => error.errorCode === ERROR_CODES.URGENT_ETA_WINDOW_EXPIRED
      && error.statusCode === HTTP_STATUS.CONFLICT,
  );
});

test('submitEta rejects ETA greater than remaining pickup window', async () => {
  const { service } = createSubmitEtaHarness({
    booking: { scheduled_pickup_at: '2099-07-23 01:35:00' },
  });

  await assert.rejects(
    () => service.submitEta(42, BOOKING_NUMBER, 10, { nowMs: SUBMIT_NOW_MS }),
    (error) => error.errorCode === ERROR_CODES.URGENT_ETA_EXCEEDS_PICKUP_WINDOW
      && error.statusCode === HTTP_STATUS.BAD_REQUEST,
  );
});

test('submitEta rejects ETA that is not faster than previous rejection minimum', async () => {
  const { service } = createSubmitEtaHarness({
    negotiation: { min_required_eta_minutes: 25 },
  });

  await assert.rejects(
    () => service.submitEta(42, BOOKING_NUMBER, 25, { nowMs: SUBMIT_NOW_MS }),
    (error) => error.errorCode === ERROR_CODES.URGENT_ETA_NOT_FAST_ENOUGH
      && error.statusCode === HTTP_STATUS.UNPROCESSABLE
      && /25/.test(error.message),
  );
});

const DECISION_NOW_MS = Date.parse('2099-07-23 01:31:00+07:00');

function createCustomerDecisionHarness(overrides = {}) {
  const conn = createConn();
  const pool = createPool(conn);
  const calls = {
    attemptOutcomes: [],
    assignments: [],
    statusUpdates: [],
    chat: [],
  };

  let booking = createBookingState({
    scheduled_pickup_at: '2099-07-23 02:00:00',
    customer_user_id: 99,
    vehicle_type_id: 3,
    status: 'OPEN',
    ...overrides.booking,
  });

  let negotiation = overrides.negotiation === null
    ? null
    : createNegotiationState({
      status: 'AWAITING_CUSTOMER',
      locked_driver_id: 7,
      attempt_count: 0,
      customer_decision_expires_at: '2099-07-23 01:32:00.000',
      min_required_eta_minutes: null,
      ...overrides.negotiation,
    });

  let attempts = overrides.attempts ?? [{
    id: 1,
    negotiation_id: 100,
    attempt_number: 1,
    driver_id: 7,
    proposed_eta_minutes: 30,
    eta_submitted_at: '2099-07-23 01:30:00.000',
    outcome: 'IN_PROGRESS',
  }];

  const urgentNegotiationRepository = {
    async findBookingForUrgentLock(_conn, bookingNumber) {
      if (overrides.missingBooking) return null;
      if (booking.booking_number !== bookingNumber) return null;
      return { ...booking };
    },
    async findNegotiationByBookingIdForUpdate(_conn, bookingId) {
      if (!negotiation || negotiation.booking_id !== bookingId) return null;
      return { ...negotiation };
    },
    async findLatestAttempt(_conn, negotiationId) {
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      return latest ? { ...latest } : null;
    },
    async updateLatestAttemptOutcome(_conn, { negotiationId, outcome }) {
      calls.attemptOutcomes.push({ negotiationId, outcome });
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      if (!latest) return 0;
      latest.outcome = outcome;
      latest.outcome_at = '2099-07-23 01:31:00.000';
      return 1;
    },
    async confirmNegotiation(_conn, negotiationId) {
      if (!negotiation || negotiation.id !== negotiationId || negotiation.status !== 'AWAITING_CUSTOMER') {
        return null;
      }
      negotiation = {
        ...negotiation,
        status: 'CONFIRMED',
        closed_at: '2099-07-23 01:31:00.000',
        closed_reason: 'CUSTOMER_ACCEPTED',
      };
      return { ...negotiation };
    },
    async rejectAndRebroadcast(_conn, { negotiationId, minRequiredEtaMinutes }) {
      if (!negotiation || negotiation.id !== negotiationId || negotiation.status !== 'AWAITING_CUSTOMER') {
        return null;
      }
      negotiation = {
        ...negotiation,
        status: 'BROADCASTING',
        attempt_count: Number(negotiation.attempt_count || 0) + 1,
        min_required_eta_minutes: minRequiredEtaMinutes,
        locked_driver_id: null,
        locked_at: null,
        lock_expires_at: null,
        customer_decision_expires_at: null,
      };
      return { ...negotiation };
    },
    async rebroadcastAfterAttemptFailure(_conn, { negotiationId, fromStatus, minRequiredEtaMinutes }) {
      if (!negotiation || negotiation.id !== negotiationId || negotiation.status !== fromStatus) {
        return null;
      }
      negotiation = {
        ...negotiation,
        status: 'BROADCASTING',
        attempt_count: Number(negotiation.attempt_count || 0) + 1,
        min_required_eta_minutes: minRequiredEtaMinutes != null
          ? minRequiredEtaMinutes
          : negotiation.min_required_eta_minutes,
        locked_driver_id: null,
        locked_at: null,
        lock_expires_at: null,
        customer_decision_expires_at: null,
      };
      return { ...negotiation };
    },
    async cancelNegotiationExhausted(_conn, { negotiationId, minRequiredEtaMinutes }) {
      if (!negotiation || negotiation.id !== negotiationId || negotiation.status !== 'AWAITING_CUSTOMER') {
        return null;
      }
      negotiation = {
        ...negotiation,
        status: 'CANCELLED',
        attempt_count: Number(negotiation.attempt_count || 0) + 1,
        min_required_eta_minutes: minRequiredEtaMinutes,
        closed_at: '2099-07-23 01:31:00.000',
        closed_reason: 'URGENT_NEGOTIATION_EXHAUSTED',
      };
      return { ...negotiation };
    },
    async cancelAfterAttemptFailure(_conn, { negotiationId, fromStatus, minRequiredEtaMinutes }) {
      if (!negotiation || negotiation.id !== negotiationId || negotiation.status !== fromStatus) {
        return null;
      }
      negotiation = {
        ...negotiation,
        status: 'CANCELLED',
        attempt_count: Number(negotiation.attempt_count || 0) + 1,
        min_required_eta_minutes: minRequiredEtaMinutes != null
          ? minRequiredEtaMinutes
          : negotiation.min_required_eta_minutes,
        closed_at: '2099-07-23 01:31:00.000',
        closed_reason: 'URGENT_NEGOTIATION_EXHAUSTED',
      };
      return { ...negotiation };
    },
    getNegotiation() { return negotiation; },
    getAttempts() { return attempts.map((row) => ({ ...row })); },
  };

  const driverRepository = {
    async findByIdForUpdate(_conn, driverId) {
      const drivers = {
        7: {
          id: 7,
          user_id: 42,
          name: 'Driver A',
          is_active: 1,
        },
      };
      return drivers[driverId] || null;
    },
    async findById(driverId) {
      const drivers = {
        7: { id: 7, user_id: 42, name: 'Driver A' },
      };
      return drivers[driverId] || null;
    },
    async findActiveAssignmentPickupsForConflict() {
      return overrides.conflictRows ?? [];
    },
    async findMatchingVehicle(_conn, driverId, vehicleTypeId) {
      if (driverId === 7 && vehicleTypeId === booking.vehicle_type_id) {
        return { id: 501 };
      }
      return null;
    },
  };

  const bookingRepository = {
    async findActiveAssignmentForUpdate() {
      return overrides.activeAssignment ?? null;
    },
    async insertDriverAssignment(_conn, row) {
      calls.assignments.push(row);
      return 9001;
    },
    async updateStatus(_conn, bookingId, status, actorUserId, statusFields = {}) {
      calls.statusUpdates.push({ bookingId, status, actorUserId, statusFields });
      booking = { ...booking, status };
      return 1;
    },
    async insertStatusLog() {},
    async insertActivityLog() {},
  };

  const bookingService = {
    async assertCustomerOrGuestAccess() {
      if (overrides.accessDenied) {
        const AppError = require('../src/utils/AppError');
        throw new AppError('Booking is not accessible', {
          statusCode: HTTP_STATUS.FORBIDDEN,
          errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
        });
      }
    },
  };

  const chatService = {
    async ensureRoom(_conn, currentBooking) {
      calls.chat.push({ type: 'ensureRoom', bookingId: currentBooking.id });
      return { id: 55, booking_id: currentBooking.id };
    },
    async ensureDriverParticipant(_conn, room, currentBooking, driverUserId) {
      calls.chat.push({
        type: 'ensureDriverParticipant',
        roomId: room.id,
        bookingId: currentBooking.id,
        driverUserId,
      });
      return { participantId: 77 };
    },
  };

  const driverJobService = {
    validateBookingNumber(value) {
      if (!/^TX\d{12}$/.test(String(value || ''))) {
        const AppError = require('../src/utils/AppError');
        throw new AppError('Invalid booking number', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      return String(value);
    },
  };

  const service = new UrgentNegotiationService(
    pool,
    urgentNegotiationRepository,
    driverRepository,
    driverJobService,
    bookingRepository,
    bookingService,
    chatService,
  );

  return {
    service,
    conn,
    calls,
    getNegotiation: urgentNegotiationRepository.getNegotiation,
    getBooking: () => ({ ...booking }),
    getAttempts: urgentNegotiationRepository.getAttempts,
  };
}

test('submitCustomerDecision ACCEPT confirms negotiation and creates assignment', async () => {
  const emitted = captureSocket();
  const { service, conn, calls, getNegotiation, getBooking } = createCustomerDecisionHarness();

  const result = await service.submitCustomerDecision(
    BOOKING_NUMBER,
    'ACCEPT',
    { authUser: { id: 99, role: 'CUSTOMER' }, nowMs: DECISION_NOW_MS },
  );

  assert.equal(conn.committed, true);
  assert.equal(result.status, 'CONFIRMED');
  assert.equal(result.decision, 'ACCEPT');
  assert.equal(result.assignmentId, 9001);
  assert.equal(getNegotiation().status, 'CONFIRMED');
  assert.equal(getBooking().status, 'DRIVER_ASSIGNED');
  assert.deepEqual(calls.assignments[0], {
    bookingId: 10,
    driverId: 7,
    driverVehicleId: 501,
    assignedByUserId: 99,
    assignmentReason: 'URGENT_CUSTOMER_CONFIRMED',
  });
  assert.equal(calls.attemptOutcomes[0].outcome, 'CUSTOMER_ACCEPTED');
  assert.equal(calls.chat.length, 2);
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42)
      && row.event === 'driver:urgent-call:confirmed'),
    true,
  );
  assert.equal(
    emitted.some((row) => row.room === guestBookingRoom(10)
      && row.event === 'booking:urgent-negotiation:confirmed'),
    true,
  );
  setRealtimeIo(null);
});

test('submitCustomerDecision REJECT on first round returns to BROADCASTING and updates min ETA', async () => {
  const emitted = captureSocket();
  const { service, conn, getNegotiation } = createCustomerDecisionHarness();

  const result = await service.submitCustomerDecision(
    BOOKING_NUMBER,
    'REJECT',
    { authUser: { id: 99, role: 'CUSTOMER' }, nowMs: DECISION_NOW_MS },
  );

  assert.equal(conn.committed, true);
  assert.equal(result.status, 'BROADCASTING');
  assert.equal(result.decision, 'REJECT');
  assert.equal(result.attemptCount, 1);
  assert.equal(result.minRequiredEtaMinutes, 30);
  assert.equal(getNegotiation().status, 'BROADCASTING');
  assert.equal(getNegotiation().min_required_eta_minutes, 30);
  assert.equal(getNegotiation().locked_driver_id, null);
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42)
      && row.event === 'driver:urgent-call:round-ended'),
    true,
  );
  assert.equal(
    emitted.some((row) => row.room === DRIVER_ALL_ROOM
      && row.event === 'driver:urgent-call:unlocked'
      && row.payload.minRequiredEtaMinutes === 30),
    true,
  );
  assert.equal(
    emitted.some((row) => row.room === DRIVER_ALL_ROOM
      && row.event === 'driver:urgent-call:new'
      && row.payload.minRequiredEtaMinutes === 30),
    true,
  );
  setRealtimeIo(null);
});

test('submitCustomerDecision REJECT on third round cancels booking and negotiation', async () => {
  const emitted = captureSocket();
  const { service, conn, getNegotiation, getBooking } = createCustomerDecisionHarness({
    negotiation: {
      attempt_count: 2,
    },
    attempts: [{
      id: 3,
      negotiation_id: 100,
      attempt_number: 3,
      driver_id: 7,
      proposed_eta_minutes: 20,
      eta_submitted_at: '2099-07-23 01:30:00.000',
      outcome: 'IN_PROGRESS',
    }],
  });

  const result = await service.submitCustomerDecision(
    BOOKING_NUMBER,
    'REJECT',
    { authUser: { id: 99, role: 'CUSTOMER' }, nowMs: DECISION_NOW_MS },
  );

  assert.equal(conn.committed, true);
  assert.equal(result.status, 'CANCELLED');
  assert.equal(result.attemptCount, 3);
  assert.equal(result.bookingStatus, 'CANCELLED');
  assert.equal(getNegotiation().status, 'CANCELLED');
  assert.equal(getNegotiation().closed_reason, 'URGENT_NEGOTIATION_EXHAUSTED');
  assert.equal(getBooking().status, 'CANCELLED');
  assert.equal(
    emitted.some((row) => row.room === DRIVER_ALL_ROOM
      && row.event === 'driver:urgent-call:cancelled'),
    true,
  );
  assert.equal(
    emitted.some((row) => row.room === guestBookingRoom(10)
      && row.event === 'booking:urgent-negotiation:cancelled'),
    true,
  );
  setRealtimeIo(null);
});

test('submitCustomerDecision rejects when negotiation is not AWAITING_CUSTOMER', async () => {
  const { service } = createCustomerDecisionHarness({
    negotiation: { status: 'LOCKED' },
  });

  await assert.rejects(
    () => service.submitCustomerDecision(
      BOOKING_NUMBER,
      'ACCEPT',
      { authUser: { id: 99, role: 'CUSTOMER' }, nowMs: DECISION_NOW_MS },
    ),
    (error) => error.errorCode === ERROR_CODES.URGENT_NEGOTIATION_NOT_AWAITING
      && error.statusCode === HTTP_STATUS.CONFLICT,
  );
});

test('submitCustomerDecision rejects after customer decision window expires', async () => {
  const { service } = createCustomerDecisionHarness({
    negotiation: {
      customer_decision_expires_at: '2099-07-23 01:30:00.000',
    },
  });

  await assert.rejects(
    () => service.submitCustomerDecision(
      BOOKING_NUMBER,
      'ACCEPT',
      { authUser: { id: 99, role: 'CUSTOMER' }, nowMs: DECISION_NOW_MS },
    ),
    (error) => error.errorCode === ERROR_CODES.URGENT_DECISION_WINDOW_EXPIRED
      && error.statusCode === HTTP_STATUS.CONFLICT,
  );
});

function createRejectThenSubmitEtaHarness() {
  const conn = createConn();
  const pool = createPool(conn);

  let booking = createBookingState({
    scheduled_pickup_at: '2099-07-23 02:00:00',
    customer_user_id: 99,
    vehicle_type_id: 3,
    status: 'OPEN',
  });

  let negotiation = createNegotiationState({
    status: 'AWAITING_CUSTOMER',
    locked_driver_id: 7,
    attempt_count: 0,
    lock_expires_at: '2099-07-23 01:35:00.000',
    customer_decision_expires_at: '2099-07-23 01:32:00.000',
    min_required_eta_minutes: null,
  });

  let attempts = [{
    id: 1,
    negotiation_id: 100,
    attempt_number: 1,
    driver_id: 7,
    proposed_eta_minutes: 25,
    eta_submitted_at: '2099-07-23 01:30:00.000',
    outcome: 'IN_PROGRESS',
  }];

  const urgentNegotiationRepository = {
    async findBookingForUrgentLock(_conn, bookingNumber) {
      if (booking.booking_number !== bookingNumber) return null;
      return { ...booking };
    },
    async findNegotiationByBookingIdForUpdate(_conn, bookingId) {
      if (negotiation.booking_id !== bookingId) return null;
      return { ...negotiation };
    },
    async findLatestAttempt(_conn, negotiationId) {
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      return latest ? { ...latest } : null;
    },
    async updateLatestAttemptOutcome(_conn, { negotiationId, outcome }) {
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      if (!latest) return 0;
      latest.outcome = outcome;
      return 1;
    },
    async rejectAndRebroadcast(_conn, { negotiationId, minRequiredEtaMinutes }) {
      negotiation = {
        ...negotiation,
        status: 'BROADCASTING',
        attempt_count: 1,
        min_required_eta_minutes: minRequiredEtaMinutes,
        locked_driver_id: null,
        locked_at: null,
        lock_expires_at: null,
        customer_decision_expires_at: null,
      };
      return { ...negotiation };
    },
    async rebroadcastAfterAttemptFailure(_conn, { negotiationId, fromStatus, minRequiredEtaMinutes }) {
      if (negotiation.id !== negotiationId || negotiation.status !== fromStatus) return null;
      negotiation = {
        ...negotiation,
        status: 'BROADCASTING',
        attempt_count: 1,
        min_required_eta_minutes: minRequiredEtaMinutes,
        locked_driver_id: null,
        locked_at: null,
        lock_expires_at: null,
        customer_decision_expires_at: null,
      };
      return { ...negotiation };
    },
    async findBroadcastingNegotiationForUpdate(_conn, bookingId) {
      if (negotiation.booking_id !== bookingId || negotiation.status !== 'BROADCASTING') {
        return null;
      }
      return { ...negotiation };
    },
    async lockNegotiationIfBroadcasting(_conn, { negotiationId, driverId }) {
      if (negotiation.id !== negotiationId || negotiation.status !== 'BROADCASTING') return 0;
      negotiation = {
        ...negotiation,
        status: 'LOCKED',
        locked_driver_id: driverId,
        lock_expires_at: '2099-07-23 01:35:00.000',
      };
      return 1;
    },
    async findNegotiationById(_conn, negotiationId) {
      return negotiation.id === negotiationId ? { ...negotiation } : null;
    },
    async insertAttempt(_conn, row) {
      attempts.push({
        id: attempts.length + 1,
        negotiation_id: row.negotiationId,
        attempt_number: row.attemptNumber,
        driver_id: row.driverId,
        proposed_eta_minutes: null,
        outcome: 'IN_PROGRESS',
      });
      return attempts.length;
    },
    async markNegotiationAwaitingCustomer(_conn, negotiationId) {
      if (negotiation.id !== negotiationId || negotiation.status !== 'LOCKED') return null;
      negotiation = {
        ...negotiation,
        status: 'AWAITING_CUSTOMER',
        customer_decision_expires_at: '2099-07-23 01:32:00.000',
      };
      return { ...negotiation };
    },
    async updateLatestAttemptEta(_conn, { negotiationId, etaMinutes }) {
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      if (!latest) return 0;
      latest.proposed_eta_minutes = etaMinutes;
      return 1;
    },
  };

  const driverRepository = {
    async findByUserIdForUpdate(_conn, userId) {
      return userId === 42
        ? { id: 7, user_id: 42, is_active: 1, user_is_active: 1 }
        : null;
    },
    async findById(driverId) {
      return driverId === 7 ? { id: 7, user_id: 42 } : null;
    },
    async findActiveAssignmentPickupsForConflict() { return []; },
    async findMatchingVehicle() { return { id: 501 }; },
  };

  const bookingRepository = {
    async findActiveAssignmentForUpdate() { return null; },
    async insertDriverAssignment() { return 9001; },
    async updateStatus(_conn, _bookingId, status) {
      booking = { ...booking, status };
    },
    async insertStatusLog() {},
    async insertActivityLog() {},
  };

  const bookingService = {
    async assertCustomerOrGuestAccess() {},
  };

  const driverJobService = {
    validateBookingNumber(value) { return String(value); },
  };

  const service = new UrgentNegotiationService(
    pool,
    urgentNegotiationRepository,
    driverRepository,
    driverJobService,
    bookingRepository,
    bookingService,
    null,
  );

  setRealtimeIo({
    to() {
      return { emit() {} };
    },
  });

  return {
    service,
    getNegotiation: () => ({ ...negotiation }),
  };
}

test('after customer REJECT, submitEta rejects ETA that is not faster than updated minimum', async () => {
  const { service, getNegotiation } = createRejectThenSubmitEtaHarness();

  await service.submitCustomerDecision(
    BOOKING_NUMBER,
    'REJECT',
    { authUser: { id: 99, role: 'CUSTOMER' }, nowMs: DECISION_NOW_MS },
  );
  assert.equal(getNegotiation().min_required_eta_minutes, 25);

  await service.lockNegotiation(42, BOOKING_NUMBER);

  await assert.rejects(
    () => service.submitEta(42, BOOKING_NUMBER, 25, { nowMs: SUBMIT_NOW_MS }),
    (error) => error.errorCode === ERROR_CODES.URGENT_ETA_NOT_FAST_ENOUGH
      && error.statusCode === HTTP_STATUS.UNPROCESSABLE,
  );

  setRealtimeIo(null);
});

function createTimeoutHarness(overrides = {}) {
  const conn = createConn();
  const pool = createPool(conn);

  let booking = createBookingState({
    scheduled_pickup_at: '2099-07-23 02:00:00',
    customer_user_id: 99,
    vehicle_type_id: 3,
    status: 'OPEN',
    ...overrides.booking,
  });

  let negotiation = createNegotiationState({
    status: overrides.initialStatus ?? 'LOCKED',
    locked_driver_id: 7,
    attempt_count: overrides.attemptCount ?? 0,
    lock_expires_at: '2099-07-23 01:29:00',
    customer_decision_expires_at: '2099-07-23 01:32:00',
    min_required_eta_minutes: overrides.minRequiredEtaMinutes ?? null,
    ...overrides.negotiation,
  });

  let attempts = overrides.attempts ?? [{
    id: 1,
    negotiation_id: 100,
    attempt_number: overrides.attemptNumber ?? 1,
    driver_id: 7,
    proposed_eta_minutes: overrides.proposedEtaMinutes ?? null,
    eta_submitted_at: null,
    outcome: 'IN_PROGRESS',
  }];

  const expiredLockedRows = overrides.expiredLockedRows ?? (
    negotiation.status === 'LOCKED' ? [{
      id: negotiation.id,
      booking_id: booking.id,
      booking_number: booking.booking_number,
      booking_status: booking.status,
      attempt_count: negotiation.attempt_count,
      locked_driver_id: negotiation.locked_driver_id,
      lock_expires_at: negotiation.lock_expires_at,
      min_required_eta_minutes: negotiation.min_required_eta_minutes,
    }] : []
  );

  const expiredAwaitingRows = overrides.expiredAwaitingRows ?? (
    negotiation.status === 'AWAITING_CUSTOMER' ? [{
      id: negotiation.id,
      booking_id: booking.id,
      booking_number: booking.booking_number,
      booking_status: booking.status,
      attempt_count: negotiation.attempt_count,
      locked_driver_id: negotiation.locked_driver_id,
      customer_decision_expires_at: negotiation.customer_decision_expires_at,
      min_required_eta_minutes: negotiation.min_required_eta_minutes,
    }] : []
  );

  const urgentNegotiationRepository = {
    async listExpiredLockedNegotiations() {
      return expiredLockedRows.map((row) => ({ ...row }));
    },
    async listExpiredAwaitingCustomerNegotiations() {
      return expiredAwaitingRows.map((row) => ({ ...row }));
    },
    async findNegotiationByIdForUpdate(_conn, negotiationId) {
      if (negotiation.id !== negotiationId) return null;
      return { ...negotiation };
    },
    async findBookingForUrgentLockById(_conn, bookingId) {
      if (booking.id !== bookingId) return null;
      return { ...booking };
    },
    async findLatestAttempt(_conn, negotiationId) {
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      return latest ? { ...latest } : null;
    },
    async updateLatestAttemptOutcome(_conn, { negotiationId, outcome }) {
      const latest = attempts
        .filter((row) => row.negotiation_id === negotiationId)
        .sort((a, b) => b.attempt_number - a.attempt_number)[0];
      if (!latest) return 0;
      latest.outcome = outcome;
      latest.outcome_at = '2099-07-23 01:31:00.000';
      return 1;
    },
    async rebroadcastAfterAttemptFailure(_conn, { negotiationId, fromStatus, minRequiredEtaMinutes }) {
      if (negotiation.id !== negotiationId || negotiation.status !== fromStatus) return null;
      negotiation = {
        ...negotiation,
        status: 'BROADCASTING',
        attempt_count: Number(negotiation.attempt_count || 0) + 1,
        min_required_eta_minutes: minRequiredEtaMinutes != null
          ? minRequiredEtaMinutes
          : negotiation.min_required_eta_minutes,
        locked_driver_id: null,
        locked_at: null,
        lock_expires_at: null,
        customer_decision_expires_at: null,
      };
      return { ...negotiation };
    },
    async cancelAfterAttemptFailure(_conn, { negotiationId, fromStatus, minRequiredEtaMinutes }) {
      if (negotiation.id !== negotiationId || negotiation.status !== fromStatus) return null;
      negotiation = {
        ...negotiation,
        status: 'CANCELLED',
        attempt_count: Number(negotiation.attempt_count || 0) + 1,
        min_required_eta_minutes: minRequiredEtaMinutes != null
          ? minRequiredEtaMinutes
          : negotiation.min_required_eta_minutes,
        closed_reason: 'URGENT_NEGOTIATION_EXHAUSTED',
      };
      return { ...negotiation };
    },
    getNegotiation() { return negotiation; },
    getAttempts() { return attempts.map((row) => ({ ...row })); },
  };

  const driverRepository = {
    async findById(driverId) {
      return driverId === 7 ? { id: 7, user_id: 42, name: 'Driver A' } : null;
    },
  };

  const bookingRepository = {
    async updateStatus(_conn, _bookingId, status) {
      booking = { ...booking, status };
    },
    async insertStatusLog() {},
    async insertActivityLog() {},
  };

  const driverJobService = {
    validateBookingNumber(value) { return String(value); },
  };

  const service = new UrgentNegotiationService(
    pool,
    urgentNegotiationRepository,
    driverRepository,
    driverJobService,
    bookingRepository,
    { async assertCustomerOrGuestAccess() {} },
    null,
  );

  return {
    service,
    conn,
    getNegotiation: urgentNegotiationRepository.getNegotiation,
    getBooking: () => ({ ...booking }),
    getAttempts: urgentNegotiationRepository.getAttempts,
  };
}

test('processDriverEtaTimeout rebroadcasts and increments attempt_count', async () => {
  const emitted = captureSocket();
  const { service, conn, getNegotiation, getAttempts } = createTimeoutHarness();

  const result = await service.processDriverEtaTimeout(100, { nowMs: DECISION_NOW_MS });

  assert.equal(conn.committed, true);
  assert.equal(result.status, 'BROADCASTING');
  assert.equal(result.attemptCount, 1);
  assert.equal(getNegotiation().status, 'BROADCASTING');
  assert.equal(getNegotiation().attempt_count, 1);
  assert.equal(getAttempts()[0].outcome, 'DRIVER_ETA_TIMEOUT');
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42)
      && row.event === 'driver:urgent-call:round-ended'),
    true,
  );
  assert.equal(
    emitted.some((row) => row.room === DRIVER_ALL_ROOM
      && row.event === 'driver:urgent-call:new'),
    true,
  );
  setRealtimeIo(null);
});

test('processDriverEtaTimeout cancels negotiation after third expired lock', async () => {
  const emitted = captureSocket();
  const { service, conn, getNegotiation, getBooking } = createTimeoutHarness({
    attemptCount: 2,
    attemptNumber: 3,
    attempts: [{
      id: 3,
      negotiation_id: 100,
      attempt_number: 3,
      driver_id: 7,
      proposed_eta_minutes: null,
      outcome: 'IN_PROGRESS',
    }],
  });

  const result = await service.processDriverEtaTimeout(100, { nowMs: DECISION_NOW_MS });

  assert.equal(conn.committed, true);
  assert.equal(result.status, 'CANCELLED');
  assert.equal(result.attemptCount, 3);
  assert.equal(getNegotiation().status, 'CANCELLED');
  assert.equal(getBooking().status, 'CANCELLED');
  assert.equal(
    emitted.some((row) => row.room === guestBookingRoom(10)
      && row.event === 'booking:urgent-negotiation:cancelled'),
    true,
  );
  setRealtimeIo(null);
});

test('processCustomerDecisionTimeout auto-rejects and updates min_required_eta_minutes', async () => {
  const emitted = captureSocket();
  const { service, conn, getNegotiation } = createTimeoutHarness({
    initialStatus: 'AWAITING_CUSTOMER',
    negotiation: {
      status: 'AWAITING_CUSTOMER',
      customer_decision_expires_at: '2099-07-23 01:29:00',
    },
    proposedEtaMinutes: 28,
    expiredLockedRows: [],
    expiredAwaitingRows: [{
      id: 100,
      booking_id: 10,
      booking_number: BOOKING_NUMBER,
      booking_status: 'OPEN',
      attempt_count: 0,
      locked_driver_id: 7,
      customer_decision_expires_at: '2099-07-23 01:29:00',
      min_required_eta_minutes: null,
    }],
  });

  const result = await service.processCustomerDecisionTimeout(100, { nowMs: DECISION_NOW_MS });

  assert.equal(conn.committed, true);
  assert.equal(result.status, 'BROADCASTING');
  assert.equal(result.decision, 'AUTO_REJECT');
  assert.equal(result.minRequiredEtaMinutes, 28);
  assert.equal(getNegotiation().min_required_eta_minutes, 28);
  assert.equal(
    emitted.some((row) => row.room === DRIVER_ALL_ROOM
      && row.event === 'driver:urgent-call:new'
      && row.payload.minRequiredEtaMinutes === 28),
    true,
  );
  setRealtimeIo(null);
});

test('processExpiredNegotiations processes locked and awaiting expired rows', async () => {
  setRealtimeIo({ to() { return { emit() {} }; } });

  const lockedProcessed = [];
  const customerProcessed = [];

  const urgentNegotiationRepository = {
    async listExpiredLockedNegotiations() {
      return [{ id: 100, booking_number: BOOKING_NUMBER }];
    },
    async listExpiredAwaitingCustomerNegotiations() {
      return [{ id: 101, booking_number: BOOKING_NUMBER }];
    },
  };

  const service = new UrgentNegotiationService(
    createPool(),
    urgentNegotiationRepository,
    {},
    { validateBookingNumber(value) { return String(value); } },
    {},
    { async assertCustomerOrGuestAccess() {} },
    null,
  );

  service.processDriverEtaTimeout = async (negotiationId) => {
    lockedProcessed.push(negotiationId);
    return { socketActions: [] };
  };
  service.processCustomerDecisionTimeout = async (negotiationId) => {
    customerProcessed.push(negotiationId);
    return { socketActions: [] };
  };

  const summary = await service.processExpiredNegotiations({
    nowMs: DECISION_NOW_MS,
    batchSize: 20,
  });

  assert.equal(summary.lockedSelected, 1);
  assert.equal(summary.lockedProcessed, 1);
  assert.equal(summary.customerSelected, 1);
  assert.equal(summary.customerProcessed, 1);
  assert.deepEqual(lockedProcessed, [100]);
  assert.deepEqual(customerProcessed, [101]);
  setRealtimeIo(null);
});
