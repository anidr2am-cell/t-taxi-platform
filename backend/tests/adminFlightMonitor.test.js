process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const ERROR_CODES = require('../src/constants/errorCodes');
const FLIGHT_STATUS = require('../src/constants/flightStatus');
const FLIGHT_SYNC_STATUS = require('../src/constants/flightSyncStatus');
const AdminFlightMonitorService = require('../src/services/adminFlightMonitor.service');
const FlightService = require('../src/services/flight.service');
const AppError = require('../src/utils/AppError');
const {
  parseServiceDateTimeToMs,
  getElapsedMsSinceServiceDateTime,
} = require('../src/utils/serviceDateTime.util');
const container = require('../src/helpers/container');
const app = require('../src/app');

function bangkokMysqlAtOffsetSeconds(nowMs, offsetSeconds) {
  const targetMs = nowMs - offsetSeconds * 1000;
  const parts = new Intl.DateTimeFormat('en-US', {
    timeZone: 'Asia/Bangkok',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    second: '2-digit',
    hourCycle: 'h23',
    hour12: false,
  }).formatToParts(new Date(targetMs));
  const part = (type) => parts.find((item) => item.type === type)?.value;
  const hour = part('hour') === '24' ? '00' : part('hour');
  return `${part('year')}-${part('month')}-${part('day')} ${hour}:${part('minute')}:${part('second')}`;
}

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function flightRow(overrides = {}) {
  return {
    booking_id: 42,
    booking_number: 'TX202607010001',
    booking_status: 'PENDING',
    scheduled_pickup_at: '2026-07-01 09:30:00',
    scheduled_pickup_at_text: '2026-07-01 09:30:00',
    service_type_code: 'AIRPORT_PICKUP',
    flight_number: 'TG409',
    airline_code: 'TG',
    flight_date: '2026-07-01',
    departure_airport_iata: 'SIN',
    arrival_airport_iata: 'BKK',
    flight_scheduled_arrival_at: '2026-07-01 12:00:00',
    flight_scheduled_arrival_at_text: '2026-07-01 12:00:00',
    flight_estimated_arrival_at: '2026-07-01 12:15:00',
    flight_estimated_arrival_at_text: '2026-07-01 12:15:00',
    flight_actual_arrival_at: null,
    flight_actual_arrival_at_text: null,
    delay_minutes: 15,
    delay_status: 'Delayed 15 min',
    flight_status: FLIGHT_STATUS.DELAYED,
    last_synced_at: null,
    last_synced_at_text: null,
    sync_status: FLIGHT_SYNC_STATUS.NEVER,
    sync_error: null,
    ...overrides,
  };
}

function createService(overrides = {}) {
  const flightService = overrides.flightService ?? {
    normalizeFlightNumber: (value) => String(value).trim().replace(/\s+/g, '').toUpperCase(),
    isProviderConfigured: () => true,
    async search() {
      return {
        airlineCode: 'TG',
        departure: { airportCode: 'SIN' },
        arrival: {
          airportCode: 'BKK',
          scheduledAt: '2026-07-01T12:00:00+00:00',
          estimatedAt: '2026-07-01T12:20:00+00:00',
          actualAt: null,
        },
        status: FLIGHT_STATUS.DELAYED,
        delayMinutes: 20,
      };
    },
  };

  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };

  const pool = overrides.pool ?? { async getConnection() { return conn; } };
  const flightMonitorRepository = overrides.flightMonitorRepository ?? {
    async listFlights() {
      return { total: 1, rows: [flightRow()] };
    },
    async findFlightBookingById(id) {
      return flightRow({ booking_id: id });
    },
    async updateFlightSync() {},
  };
  const bookingRepository = overrides.bookingRepository ?? {
    async insertActivityLog() {},
  };
  const outboxRepository = overrides.outboxRepository ?? {
    async insertNotificationEvent() {
      return 9001;
    },
  };
  const outboxProcessor = overrides.outboxProcessor ?? {
    async dispatchOutboxIds() {},
  };

  return new AdminFlightMonitorService(
    pool,
    flightMonitorRepository,
    flightService,
    bookingRepository,
    outboxRepository,
    outboxProcessor,
    {
      syncEnabled: overrides.syncEnabled ?? true,
      minSyncIntervalMs: overrides.minSyncIntervalMs ?? 120000,
      nowFn: overrides.nowFn,
    },
  );
}

test('ADMIN can list flights', async () => {
  container.register('adminFlightMonitorService', () => ({
    async listFlights() {
      return {
        page: 1,
        pageSize: 20,
        total: 1,
        items: [{ bookingNumber: 'TX202607010001', flightNumber: 'TG409' }],
      };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/flights')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.total, 1);
  assert.equal(res.body.data.items[0].flightNumber, 'TG409');
});

test('SUPER_ADMIN can list flights', async () => {
  container.register('adminFlightMonitorService', () => ({
    async listFlights() {
      return { page: 1, pageSize: 20, total: 0, items: [] };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/flights')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN')}`);

  assert.equal(res.status, 200);
});

test('DRIVER, CUSTOMER, and unauthenticated requests are rejected', async () => {
  const resDriver = await request(app)
    .get('/api/v1/admin/flights')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`);
  assert.equal(resDriver.status, 403);

  const resCustomer = await request(app)
    .get('/api/v1/admin/flights')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 8)}`);
  assert.equal(resCustomer.status, 403);
  assert.equal(resCustomer.body.error_code, ERROR_CODES.FORBIDDEN);

  const resGuest = await request(app).get('/api/v1/admin/flights');
  assert.equal(resGuest.status, 401);
});

test('service normalizes flight number filter', async () => {
  let capturedFilters = null;
  const service = createService({
    flightMonitorRepository: {
      async listFlights(filters) {
        capturedFilters = filters;
        return { total: 0, rows: [] };
      },
    },
  });

  await service.listFlights({ flightNumber: ' tg 409 ', page: 1 });
  assert.equal(capturedFilters.flightNumber, 'TG409');
});

test('service maps row without sensitive fields', () => {
  const service = createService();
  const mapped = service.mapRow(flightRow({ customer_user_id: 77 }));
  assert.equal(mapped.bookingNumber, 'TX202607010001');
  assert.equal(mapped.flightNumber, 'TG409');
  assert.equal(mapped.delayMinutes, 15);
  assert.ok(!('customer_user_id' in mapped));
  assert.ok(!('customerUserId' in mapped));
});

test('getFlightDetail rejects non-airport pickup bookings', async () => {
  const service = createService({
    flightMonitorRepository: {
      async findFlightBookingById() {
        return flightRow({ service_type_code: 'CITY_TRANSFER', flight_number: 'TG409' });
      },
    },
  });

  await assert.rejects(
    () => service.getFlightDetail(42),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND,
  );
});

test('getFlightDetail rejects bookings without flight number', async () => {
  const service = createService({
    flightMonitorRepository: {
      async findFlightBookingById() {
        return flightRow({ flight_number: null });
      },
    },
  });

  await assert.rejects(
    () => service.getFlightDetail(42),
    (err) => err.errorCode === ERROR_CODES.NOT_FOUND,
  );
});

test('sync skips when provider is not configured', async () => {
  let persisted = null;
  const service = createService({
    flightService: {
      normalizeFlightNumber: (value) => String(value).trim().replace(/\s+/g, '').toUpperCase(),
      isProviderConfigured: () => false,
      async search() {
        throw new Error('should not be called');
      },
    },
    flightMonitorRepository: {
      async findFlightBookingById(id) {
        return flightRow({
          booking_id: id,
          sync_status: persisted?.data.syncStatus ?? FLIGHT_SYNC_STATUS.NEVER,
          sync_error: persisted?.data.syncError ?? null,
        });
      },
      async updateFlightSync(_conn, bookingId, data) {
        persisted = { bookingId, data };
      },
    },
  });

  const result = await service.syncFlight(42, { id: 1, role: 'ADMIN' });
  assert.equal(result.syncStatus, FLIGHT_SYNC_STATUS.NOT_CONFIGURED);
  assert.equal(result.syncError, 'CONFIG_MISSING');
  assert.equal(result.providerConfigured, false);
  assert.equal(persisted.data.syncStatus, FLIGHT_SYNC_STATUS.NOT_CONFIGURED);
});

test('sync maps provider response and calculates delay metadata', async () => {
  let persisted = null;
  const service = createService({
    flightMonitorRepository: {
      async findFlightBookingById(id) {
        return flightRow({
          booking_id: id,
          delay_minutes: persisted?.data.delayMinutes ?? 0,
          flight_status: persisted?.data.flightStatus ?? FLIGHT_STATUS.SCHEDULED,
          sync_status: persisted?.data.syncStatus ?? FLIGHT_SYNC_STATUS.NEVER,
        });
      },
      async updateFlightSync(_conn, bookingId, data) {
        persisted = { bookingId, data };
      },
    },
  });

  const result = await service.syncFlight(42, { id: 1, role: 'ADMIN' });
  assert.equal(result.syncStatus, FLIGHT_SYNC_STATUS.SUCCESS);
  assert.equal(persisted.data.delayMinutes, 20);
  assert.equal(persisted.data.flightStatus, FLIGHT_STATUS.DELAYED);
  assert.equal(persisted.data.departureAirportIata, 'SIN');
  assert.equal(persisted.data.arrivalAirportIata, 'BKK');
});

test('sync rejects completed bookings without changing booking status', async () => {
  const service = createService({
    flightMonitorRepository: {
      async findFlightBookingById() {
        return flightRow({ booking_status: 'COMPLETED' });
      },
    },
  });

  await assert.rejects(
    () => service.syncFlight(42, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('parseServiceDateTimeToMs treats MySQL DATETIME as Asia/Bangkok wall clock', () => {
  const ms = parseServiceDateTimeToMs('2026-07-01 09:30:00');
  assert.equal(new Date(ms).toISOString(), '2026-07-01T02:30:00.000Z');
});

test('parseServiceDateTimeToMs accepts ISO strings', () => {
  const iso = '2026-07-01T02:30:00.000Z';
  assert.equal(parseServiceDateTimeToMs(iso), Date.parse(iso));
});

test('parseServiceDateTimeToMs returns null for missing or invalid values', () => {
  assert.equal(parseServiceDateTimeToMs(null), null);
  assert.equal(parseServiceDateTimeToMs(''), null);
  assert.equal(parseServiceDateTimeToMs('not-a-date'), null);
});

test('getElapsedMsSinceServiceDateTime uses explicit now anchor', () => {
  const nowMs = Date.parse('2026-07-01T10:00:00.000Z');
  const elapsed = getElapsedMsSinceServiceDateTime('2026-07-01 16:58:01', nowMs);
  assert.equal(elapsed, 119000);
});

test('assertSyncCooldown allows null last sync', () => {
  const service = createService({ minSyncIntervalMs: 120000 });
  assert.doesNotThrow(() => service.assertSyncCooldown(flightRow({
    last_synced_at: null,
    last_synced_at_text: null,
  })));
});

test('assertSyncCooldown ignores invalid datetime safely', () => {
  const service = createService({ minSyncIntervalMs: 120000 });
  assert.doesNotThrow(() => service.assertSyncCooldown(flightRow({
    last_synced_at_text: 'invalid-datetime',
  })));
});

test('sync cooldown blocks when last sync was 119 seconds ago (MySQL DATETIME)', async () => {
  const fixedNow = Date.parse('2026-07-01T10:00:00.000Z');
  const service = createService({
    minSyncIntervalMs: 120000,
    nowFn: () => fixedNow,
    flightMonitorRepository: {
      async findFlightBookingById() {
        return flightRow({
          last_synced_at_text: bangkokMysqlAtOffsetSeconds(fixedNow, 119),
        });
      },
      async updateFlightSync() {},
    },
  });

  await assert.rejects(
    () => service.syncFlight(42, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.RATE_LIMIT,
  );
});

test('sync cooldown allows when last sync was 120 seconds ago (MySQL DATETIME)', () => {
  const fixedNow = Date.parse('2026-07-01T10:00:00.000Z');
  const service = createService({
    minSyncIntervalMs: 120000,
    nowFn: () => fixedNow,
  });

  assert.doesNotThrow(() => service.assertSyncCooldown(flightRow({
    last_synced_at_text: bangkokMysqlAtOffsetSeconds(fixedNow, 120),
  })));
});

test('sync cooldown allows when last sync was 120 seconds ago (ISO string)', () => {
  const fixedNow = Date.parse('2026-07-01T10:00:00.000Z');
  const service = createService({
    minSyncIntervalMs: 120000,
    nowFn: () => fixedNow,
  });

  assert.doesNotThrow(() => service.assertSyncCooldown(flightRow({
    last_synced_at: new Date(fixedNow - 120000).toISOString(),
    last_synced_at_text: null,
  })));
});

test('sync cooldown blocks when last sync was 119 seconds ago (ISO string)', async () => {
  const fixedNow = Date.parse('2026-07-01T10:00:00.000Z');
  const service = createService({
    minSyncIntervalMs: 120000,
    nowFn: () => fixedNow,
    flightMonitorRepository: {
      async findFlightBookingById() {
        return flightRow({
          last_synced_at: new Date(fixedNow - 119000).toISOString(),
          last_synced_at_text: null,
        });
      },
      async updateFlightSync() {},
    },
  });

  await assert.rejects(
    () => service.syncFlight(42, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.RATE_LIMIT,
  );
});

test('sync persists provider failure without corrupting booking status field', async () => {
  let persisted = null;
  const service = createService({
    flightService: {
      normalizeFlightNumber: (value) => String(value).trim().replace(/\s+/g, '').toUpperCase(),
      isProviderConfigured: () => true,
      async search() {
        throw new AppError('Flight not found', {
          statusCode: 404,
          errorCode: ERROR_CODES.FLIGHT_NOT_FOUND,
        });
      },
    },
    flightMonitorRepository: {
      async findFlightBookingById(id) {
        return flightRow({ booking_id: id, booking_status: 'PENDING' });
      },
      async updateFlightSync(_conn, bookingId, data) {
        persisted = { bookingId, data };
      },
    },
  });

  await assert.rejects(
    () => service.syncFlight(42, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.FLIGHT_NOT_FOUND,
  );
  assert.equal(persisted.data.syncStatus, FLIGHT_SYNC_STATUS.FAILED);
  assert.equal(persisted.data.syncError, ERROR_CODES.FLIGHT_NOT_FOUND);
});

test('sync maps rate limit failures', async () => {
  let persisted = null;
  const service = createService({
    flightService: {
      normalizeFlightNumber: (value) => String(value).trim().replace(/\s+/g, '').toUpperCase(),
      isProviderConfigured: () => true,
      async search() {
        throw new AppError('Rate limited', {
          statusCode: 429,
          errorCode: ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED,
        });
      },
    },
    flightMonitorRepository: {
      async findFlightBookingById(id) {
        return flightRow({ booking_id: id });
      },
      async updateFlightSync(_conn, bookingId, data) {
        persisted = { bookingId, data };
      },
    },
  });

  await assert.rejects(
    () => service.syncFlight(42, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED,
  );
  assert.equal(persisted.data.syncStatus, FLIGHT_SYNC_STATUS.RATE_LIMITED);
});

test('notification events are created only on meaningful changes', () => {
  const service = createService();
  const previous = flightRow({
    flight_status: FLIGHT_STATUS.SCHEDULED,
    delay_minutes: 0,
  });

  const unchanged = service.buildNotificationEvents(
    previous,
    {
      flightStatus: FLIGHT_STATUS.SCHEDULED,
      delayMinutes: 0,
      flightActualArrivalAt: null,
    },
    42,
    'TX202607010001',
  );
  assert.equal(unchanged.length, 0);

  const delayed = service.buildNotificationEvents(
    previous,
    {
      flightStatus: FLIGHT_STATUS.DELAYED,
      delayMinutes: 15,
      flightActualArrivalAt: null,
    },
    42,
    'TX202607010001',
  );
  assert.equal(delayed.length, 1);
  assert.equal(delayed[0].eventType, 'flight.delayed');
  assert.equal(delayed[0].payload.eventId, 'flight:delayed:42:15:DELAYED');

  const duplicateDelay = service.buildNotificationEvents(
    { ...previous, delay_minutes: 15, flight_status: FLIGHT_STATUS.DELAYED },
    {
      flightStatus: FLIGHT_STATUS.DELAYED,
      delayMinutes: 15,
      flightActualArrivalAt: null,
    },
    42,
    'TX202607010001',
  );
  assert.equal(duplicateDelay.length, 0);
});

test('flight service normalizes invalid flight numbers for booking validation path', () => {
  const service = new FlightService({ apiKey: 'x', baseUrl: 'https://example.test' });
  assert.throws(
    () => service.normalizeFlightNumber('bad flight'),
    (err) => err.errorCode === ERROR_CODES.INVALID_FLIGHT_NUMBER,
  );
});

test('manual sync endpoint requires admin role', async () => {
  container.register('adminFlightMonitorService', () => ({
    async syncFlight(bookingId) {
      return { bookingId, syncStatus: FLIGHT_SYNC_STATUS.SUCCESS };
    },
  }));

  const ok = await request(app)
    .post('/api/v1/admin/flights/42/sync')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);
  assert.equal(ok.status, 200);

  const blocked = await request(app)
    .post('/api/v1/admin/flights/42/sync')
    .set('Authorization', `Bearer ${sign('DRIVER', 3)}`);
  assert.equal(blocked.status, 403);
});
