const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const AppError = require('../src/utils/AppError');
const HTTP_STATUS = require('../src/constants/httpStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const {
  computeBookingCreateRequestHash,
  buildBookingCreateFingerprintPayload,
} = require('../src/utils/bookingIdempotency.util');
const BookingIdempotencyService = require('../src/services/bookingIdempotency.service');
const BookingService = require('../src/services/booking.service');
const { EVENTS } = require('../src/events');
const { setRealtimeIo } = require('../src/socket/realtime');

const CREATE_INPUT = {
  bookingMode: 'STANDARD',
  serviceTypeCode: 'AIRPORT_PICKUP',
  vehicleTypeCode: 'SUV',
  vehicleCount: 1,
  scheduledPickupAt: '2026-12-01T02:30:00.000Z',
  originAirportIata: 'BKK',
  destinationLocationCode: 'PATTAYA',
  origin: {
    name: 'Suvarnabhumi Airport',
    address: '999 Moo 1, Samut Prakan, Thailand',
    placeId: 'google-bkk',
    lat: 13.69,
    lng: 100.75,
  },
  destination: {
    name: 'Pattaya Hotel',
    address: 'Pattaya, Chon Buri, Thailand',
    placeId: 'google-pattaya',
    lat: 12.92,
    lng: 100.88,
  },
  passengers: { adults: 2, children: 1, infants: 0 },
  luggage: {
    carriers20Inch: 1,
    carriers24InchPlus: 2,
    golfBags: 1,
    specialLuggageCount: 1,
  },
  options: { nameSign: true, nameSignText: 'KIM FAMILY' },
  transfer: { airportIata: 'BKK', flightNumber: 'TG409' },
  customer: {
    name: 'Kim Test',
    phone: '+66123456789',
    messengerType: 'LINE',
    messengerId: 'line-user-id',
  },
  additionalRequests: 'Need child seat',
};

const ALT_INPUT = {
  ...CREATE_INPUT,
  additionalRequests: 'Different request',
};

const PRICE = {
  routeId: 7,
  currency: 'THB',
  totalAmount: 1300,
  chargeItems: [
    {
      chargeType: 'VEHICLE_BASE',
      description: 'SUV AIRPORT_PICKUP',
      quantity: 1,
      unitPrice: 1300,
      amount: 1300,
      referenceType: 'VEHICLE_PRICE',
      referenceId: 99,
    },
  ],
};

function createInMemoryIdempotencyRepository({ waitOnPending = false } = {}) {
  const rows = new Map();
  const pendingWaiters = new Map();

  const notifyPendingWaiters = (idempotencyKey) => {
    const waiters = pendingWaiters.get(idempotencyKey) ?? [];
    pendingWaiters.delete(idempotencyKey);
    for (const resolve of waiters) {
      resolve();
    }
  };

  return {
    async findByKeyForUpdate(_conn, idempotencyKey) {
      if (waitOnPending) {
        const deadline = Date.now() + 5000;
        while (Date.now() < deadline) {
          const row = rows.get(idempotencyKey);
          if (!row || row.status === 'COMPLETED') {
            break;
          }
          if (row.status === 'PENDING') {
            await new Promise((resolve) => {
              const waiters = pendingWaiters.get(idempotencyKey) ?? [];
              waiters.push(resolve);
              pendingWaiters.set(idempotencyKey, waiters);
            });
            continue;
          }
        }
      }

      const row = rows.get(idempotencyKey);
      if (!row) return null;
      if (row.expiresAt <= new Date()) {
        rows.delete(idempotencyKey);
        return null;
      }
      return { ...row };
    },
    async insertPending(_conn, { idempotencyKey, requestHash, expiresAt }) {
      if (rows.has(idempotencyKey)) {
        const err = new Error('Duplicate idempotency key');
        err.code = 'ER_DUP_ENTRY';
        throw err;
      }
      rows.set(idempotencyKey, {
        idempotency_key: idempotencyKey,
        request_hash: requestHash,
        status: 'PENDING',
        expires_at: expiresAt,
        booking_id: null,
        response_status: 201,
        response_payload: null,
      });
    },
    async markCompleted(_conn, { idempotencyKey, bookingId, responseStatus, responsePayload }) {
      const row = rows.get(idempotencyKey);
      if (!row) return;
      row.booking_id = bookingId;
      row.response_status = responseStatus;
      row.response_payload = responsePayload;
      row.status = 'COMPLETED';
      notifyPendingWaiters(idempotencyKey);
    },
    async deletePending(_conn, idempotencyKey) {
      const row = rows.get(idempotencyKey);
      if (row?.status === 'PENDING') {
        rows.delete(idempotencyKey);
        notifyPendingWaiters(idempotencyKey);
      }
    },
    rows,
  };
}

function createBookingHarness({
  failAfterPending = false,
  idempotencyRepository = createInMemoryIdempotencyRepository(),
} = {}) {
  const calls = {
    insertBooking: 0,
    commits: 0,
    rollbacks: 0,
    outbox: 0,
    dispatchOutbox: 0,
    notifications: 0,
  };
  const conn = {
    async beginTransaction() {},
    async commit() {
      calls.commits += 1;
    },
    async rollback() {
      calls.rollbacks += 1;
    },
    release() {},
  };
  const idempotencyService = new BookingIdempotencyService(idempotencyRepository);
  const bookingRepository = {
    async insertBooking() {
      calls.insertBooking += 1;
      if (failAfterPending) {
        throw new Error('charge item insert failed');
      }
      return 10;
    },
    async insertPassengers() {},
    async insertLuggage() {},
    async insertTransferDetails() {},
    async insertChargeItem() {},
    async insertStatusLog() {},
    async insertActivityLog() {},
    async insertGuestToken() {},
    async findAirportByIata() {
      return { id: 1, iata_code: 'BKK' };
    },
    async findById(_bookingId, _conn) {
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: BOOKING_STATUS.OPEN,
        scheduled_pickup_at: CREATE_INPUT.scheduledPickupAt,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: PRICE.totalAmount,
        currency: 'THB',
        is_urgent_request: 0,
      };
    },
  };

  const service = new BookingService(
    { async getConnection() { return conn; } },
    bookingRepository,
    { async generateNext() { return 'TX202607130001'; } },
    {
      async calculate() { return PRICE; },
      async resolveServiceType() {
        return { id: 1, code: 'AIRPORT_PICKUP', name: 'Airport pickup' };
      },
    },
    { async recommend() { return { recommendedVehicle: 'SUV' }; } },
    { async findTypeByCode() { return { id: 3, code: 'SUV', name: 'SUV' }; } },
    {
      async insertNotificationEvent() {
        calls.outbox += 1;
        return 30;
      },
    },
    {
      async dispatchOutboxIds() {
        calls.dispatchOutbox += 1;
      },
    },
    null,
    {
      async listEligibleForOpenBooking() {
        return [{ id: 7, user_id: 42 }];
      },
    },
    () => ({
      async sendDirectNotification() {
        calls.notifications += 1;
      },
    }),
    null,
    null,
    null,
    idempotencyService,
  );

  setRealtimeIo({
    to() {
      return { emit() {} };
    },
  });

  return { service, calls, idempotencyRepository };
}

test('computeBookingCreateRequestHash is stable across key ordering differences', () => {
  const hashA = computeBookingCreateRequestHash({
    ...CREATE_INPUT,
    passengers: { adults: 2, children: 1, infants: 0 },
  });
  const hashB = computeBookingCreateRequestHash({
    ...CREATE_INPUT,
    passengers: { infants: 0, adults: 2, children: 1 },
  });
  assert.equal(hashA, hashB);
  assert.match(hashA, /^[a-f0-9]{64}$/);
});

test('computeBookingCreateRequestHash changes when meaningful payload changes', () => {
  const hashA = computeBookingCreateRequestHash(CREATE_INPUT);
  const hashB = computeBookingCreateRequestHash(ALT_INPUT);
  assert.notEqual(hashA, hashB);
});

test('buildBookingCreateFingerprintPayload excludes server-only values', () => {
  const fingerprint = buildBookingCreateFingerprintPayload({
    ...CREATE_INPUT,
    totalAmount: 9999,
    guestAccessToken: 'secret',
  });
  assert.equal(fingerprint.totalAmount, undefined);
  assert.equal(fingerprint.guestAccessToken, undefined);
});

test('A same key same payload creates once and replays stored response', async () => {
  const { service, calls } = createBookingHarness();
  const key = '550e8400-e29b-41d4-a716-446655440000';

  const first = await service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });
  const second = await service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });

  assert.equal(calls.insertBooking, 1);
  assert.equal(first.replayed, false);
  assert.equal(second.replayed, true);
  assert.equal(first.data.bookingId, second.data.bookingId);
  assert.equal(first.data.bookingNumber, second.data.bookingNumber);
  assert.equal(first.data.guestAccessToken, second.data.guestAccessToken);
  assert.equal(first.data.boardingQrToken, second.data.boardingQrToken);
});

test('B same key different payload returns conflict without creating another booking', async () => {
  const { service, calls } = createBookingHarness();
  const key = '550e8400-e29b-41d4-a716-446655440001';

  await service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });

  await assert.rejects(
    () => service.createBooking(ALT_INPUT, null, { idempotencyKey: key }),
    (err) => {
      assert.ok(err instanceof AppError);
      assert.equal(err.statusCode, HTTP_STATUS.CONFLICT);
      assert.equal(err.errorCode, ERROR_CODES.IDEMPOTENCY_KEY_REUSED);
      return true;
    },
  );
  assert.equal(calls.insertBooking, 1);
});

test('C different keys with same payload create independent bookings', async () => {
  const { service, calls } = createBookingHarness();

  await service.createBooking(CREATE_INPUT, null, {
    idempotencyKey: '550e8400-e29b-41d4-a716-446655440002',
  });
  await service.createBooking(CREATE_INPUT, null, {
    idempotencyKey: '550e8400-e29b-41d4-a716-446655440003',
  });

  assert.equal(calls.insertBooking, 2);
});

test('D requests without idempotency key keep existing create behavior', async () => {
  const { service, calls } = createBookingHarness();

  await service.createBooking(CREATE_INPUT, null);
  await service.createBooking(CREATE_INPUT, null);

  assert.equal(calls.insertBooking, 2);
});

test('E concurrent same-key requests create only one booking', async () => {
  const idempotencyRepository = createInMemoryIdempotencyRepository({ waitOnPending: true });
  let releaseCreate;
  const createGate = new Promise((resolve) => {
    releaseCreate = resolve;
  });

  const calls = { insertBooking: 0 };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const idempotencyService = new BookingIdempotencyService(idempotencyRepository);
  const bookingRepository = {
    async insertBooking() {
      calls.insertBooking += 1;
      await createGate;
      return 10;
    },
    async insertPassengers() {},
    async insertLuggage() {},
    async insertTransferDetails() {},
    async insertChargeItem() {},
    async insertStatusLog() {},
    async insertActivityLog() {},
    async insertGuestToken() {},
    async findAirportByIata() {
      return { id: 1, iata_code: 'BKK' };
    },
    async findById() {
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: BOOKING_STATUS.OPEN,
        scheduled_pickup_at: CREATE_INPUT.scheduledPickupAt,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: PRICE.totalAmount,
        currency: 'THB',
        is_urgent_request: 0,
      };
    },
  };

  const service = new BookingService(
    { async getConnection() { return conn; } },
    bookingRepository,
    { async generateNext() { return 'TX202607130001'; } },
    {
      async calculate() { return PRICE; },
      async resolveServiceType() {
        return { id: 1, code: 'AIRPORT_PICKUP', name: 'Airport pickup' };
      },
    },
    { async recommend() { return { recommendedVehicle: 'SUV' }; } },
    { async findTypeByCode() { return { id: 3, code: 'SUV', name: 'SUV' }; } },
    { async insertNotificationEvent() { return 30; } },
    { async dispatchOutboxIds() {} },
    null,
    { async listEligibleForOpenBooking() { return []; } },
    () => ({ async sendDirectNotification() {} }),
    null,
    null,
    null,
    idempotencyService,
  );

  setRealtimeIo({ to() { return { emit() {} }; } });

  const key = '550e8400-e29b-41d4-a716-446655440004';
  const firstPromise = service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });
  await new Promise((resolve) => setImmediate(resolve));
  const secondPromise = service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });

  releaseCreate();
  const [first, second] = await Promise.all([firstPromise, secondPromise]);

  assert.equal(calls.insertBooking, 1);
  assert.equal(first.replayed, false);
  assert.equal(second.replayed, true);
  assert.equal(first.data.bookingId, second.data.bookingId);
});

test('F failed create releases pending key so retry can succeed', async () => {
  const { service, calls, idempotencyRepository } = createBookingHarness({
    failAfterPending: true,
  });
  const key = '550e8400-e29b-41d4-a716-446655440005';

  await assert.rejects(
    () => service.createBooking(CREATE_INPUT, null, { idempotencyKey: key }),
    /charge item insert failed/,
  );
  assert.equal(calls.insertBooking, 1);
  assert.equal(idempotencyRepository.rows.has(key), false);

  const retryHarness = createBookingHarness({ idempotencyRepository });
  const result = await retryHarness.service.createBooking(CREATE_INPUT, null, {
    idempotencyKey: key,
  });

  assert.equal(retryHarness.calls.insertBooking, 1);
  assert.equal(result.replayed, false);
  assert.equal(result.data.bookingNumber, 'TX202607130001');
});

test('same key same hash PENDING returns IDEMPOTENCY_REQUEST_IN_PROGRESS without creating booking', async () => {
  const idempotencyRepository = createInMemoryIdempotencyRepository();
  const key = '550e8400-e29b-41d4-a716-446655440010';
  const requestHash = computeBookingCreateRequestHash(CREATE_INPUT);
  idempotencyRepository.rows.set(key, {
    idempotency_key: key,
    request_hash: requestHash,
    status: 'PENDING',
    expires_at: new Date(Date.now() + 3600000),
    booking_id: null,
    response_status: 201,
    response_payload: null,
  });

  const { service, calls } = createBookingHarness({ idempotencyRepository });

  await assert.rejects(
    () => service.createBooking(CREATE_INPUT, null, { idempotencyKey: key }),
    (err) => {
      assert.ok(err instanceof AppError);
      assert.equal(err.statusCode, HTTP_STATUS.CONFLICT);
      assert.equal(err.errorCode, ERROR_CODES.IDEMPOTENCY_REQUEST_IN_PROGRESS);
      return true;
    },
  );
  assert.equal(calls.insertBooking, 0);
});

test('complete stores only replay secrets and replay rebuilds full create response', async () => {
  const { service, idempotencyRepository } = createBookingHarness();
  const key = '550e8400-e29b-41d4-a716-446655440011';

  const first = await service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });
  const row = idempotencyRepository.rows.get(key);
  assert.equal(row.status, 'COMPLETED');
  assert.deepEqual(Object.keys(row.response_payload).sort(), [
    'boardingQrToken',
    'guestAccessToken',
  ]);
  assert.ok(row.response_payload.guestAccessToken);
  assert.ok(row.response_payload.boardingQrToken);
  assert.equal(row.response_payload.bookingId, undefined);

  const second = await service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });
  assert.equal(second.replayed, true);
  assert.equal(second.data.bookingId, first.data.bookingId);
  assert.equal(second.data.bookingNumber, first.data.bookingNumber);
  assert.equal(second.data.guestAccessToken, first.data.guestAccessToken);
  assert.equal(second.data.boardingQrToken, first.data.boardingQrToken);
  assert.equal(second.data.trustMessage, first.data.trustMessage);
});

test('COMPLETED replay does not rerun booking create side effects', async () => {
  const { service, calls } = createBookingHarness();
  const key = '550e8400-e29b-41d4-a716-446655440012';

  await service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });
  const afterFirst = { ...calls };

  await service.createBooking(CREATE_INPUT, null, { idempotencyKey: key });

  assert.equal(calls.insertBooking, afterFirst.insertBooking);
  assert.equal(calls.outbox, afterFirst.outbox);
  assert.equal(calls.dispatchOutbox, afterFirst.dispatchOutbox);
  assert.equal(calls.notifications, afterFirst.notifications);
});
