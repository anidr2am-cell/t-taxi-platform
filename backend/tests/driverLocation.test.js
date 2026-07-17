process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');
const DriverLocationService = require('../src/services/driverLocation.service');
const {
  registerDriverLocationHandlers,
  bookingDriverLocationRoom,
  ADMIN_DRIVER_LOCATION_ROOM,
} = require('../src/socket/handlers/driverLocation.handler');
const { TRACKABLE_BOOKING_STATUSES } = require('../src/constants/driverLocation');

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function registerDriverLocationService(service) {
  container.register('driverLocationService', () => service);
}

function buildSocket(overrides = {}) {
  const joinedRooms = new Set();
  return {
    id: overrides.id ?? 'socket-1',
    data: {
      authUser: overrides.authUser ?? null,
      guestAccessToken: overrides.guestAccessToken ?? null,
    },
    joinedRooms,
    emitted: [],
    handlers: {},
    async join(room) {
      joinedRooms.add(room);
    },
    async leave(room) {
      joinedRooms.delete(room);
    },
    emit(event, payload) {
      this.emitted.push({ event, payload });
    },
    on(event, handler) {
      this.handlers[event] = handler;
    },
  };
}

function buildIo() {
  const emitted = [];
  return {
    emitted,
    to(room) {
      return {
        emit(event, payload) {
          emitted.push({ room, event, payload });
        },
      };
    },
  };
}

test('DRIVER can update own location through REST endpoint', async () => {
  registerDriverLocationService({
    async updateDriverLocation(driverUserId, input) {
      assert.equal(driverUserId, 44);
      assert.equal(input.latitude, 12.9236);
      return { accepted: true, recordedAt: '2026-07-01T03:30:00.000Z', bookingIds: [9] };
    },
  });

  const res = await request(app)
    .post('/api/v1/driver/location')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({
      latitude: 12.9236,
      longitude: 100.8825,
      accuracyMeters: 15.5,
      heading: 120,
      speedKph: 35,
      recordedAt: new Date().toISOString(),
    });

  assert.equal(res.status, 200);
  assert.equal(res.body.data.accepted, true);
  assert.equal(res.body.data.bookingIds, undefined);
});

test('ADMIN and unauthenticated users cannot use driver location update endpoint', async () => {
  const admin = await request(app)
    .post('/api/v1/driver/location')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`)
    .send({ latitude: 12, longitude: 100 });
  assert.equal(admin.status, 403);

  const anon = await request(app)
    .post('/api/v1/driver/location')
    .send({ latitude: 12, longitude: 100 });
  assert.equal(anon.status, 401);
});

test('invalid latitude/longitude rejected before service call', async () => {
  let called = false;
  registerDriverLocationService({
    async updateDriverLocation() {
      called = true;
    },
  });

  const res = await request(app)
    .post('/api/v1/driver/location')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`)
    .send({ latitude: 120, longitude: 100 });

  assert.equal(res.status, 400);
  assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  assert.equal(called, false);
});

test('admin driver location snapshot requires ADMIN role and returns no private fields', async () => {
  registerDriverLocationService({
    async listAdminLocations(filters) {
      assert.equal(filters.onlineOnly, true);
      return {
        items: [{
          driverId: 7,
          displayName: 'Somchai',
          vehicle: 'SUV / Camry / 1กข1234',
          latitude: 12.9,
          longitude: 100.8,
          stale: false,
          activeBooking: { bookingNumber: 'TX202607010001', status: 'DRIVER_ASSIGNED' },
        }],
      };
    },
  });

  const ok = await request(app)
    .get('/api/v1/admin/drivers/locations?onlineOnly=true')
    .set('Authorization', `Bearer ${sign('ADMIN', 1)}`);
  assert.equal(ok.status, 200);
  assert.equal(ok.body.data.items[0].displayName, 'Somchai');
  assert.equal(ok.body.data.items[0].phone, undefined);

  const forbidden = await request(app)
    .get('/api/v1/admin/drivers/locations')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);
  assert.equal(forbidden.status, 403);
});

test('guest can access only assigned driver for own booking', async () => {
  registerDriverLocationService({
    async getGuestDriverLocation(bookingId, guestAccessToken) {
      assert.equal(bookingId, 99);
      assert.equal(guestAccessToken, 'guest-token');
      return {
        available: true,
        driver: {
          driverId: 7,
          displayName: 'Somchai',
          latitude: 12.9,
          longitude: 100.8,
          stale: false,
        },
      };
    },
  });

  const res = await request(app)
    .get('/api/v1/public/bookings/99/driver-location')
    .set('X-Guest-Access-Token', 'guest-token');
  assert.equal(res.status, 200);
  assert.equal(res.body.data.available, true);
  assert.equal(res.body.data.driver.displayName, 'Somchai');
});

test('terminal or unassigned booking returns safe unavailable response', async () => {
  const service = new DriverLocationService({}, {
    async findGuestAssignedDriverLocation() {
      return {
        booking_status: 'COMPLETED',
        driver_id: 7,
        driver_name: 'Somchai',
        current_lat: 12.9,
        current_lng: 100.8,
      };
    },
  });

  const result = await service.getGuestDriverLocation(3, 'guest-token');
  assert.equal(result.available, false);
  assert.equal(result.driver, null);
});

test('stale flag is true when location is older than sixty seconds', () => {
  const service = new DriverLocationService({}, {});
  const now = new Date('2026-07-01T10:01:01.000Z');
  assert.equal(service.isStale('2026-07-01T10:00:00.000Z', now), true);
  assert.equal(service.isStale('2026-07-01T10:00:10.000Z', now), false);
});

test('service-level validation also protects socket location updates', () => {
  const service = new DriverLocationService({}, {});
  assert.throws(
    () => service.validateLocationInput({ latitude: 99, longitude: 100 }),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('driver location is trackable only during active trip statuses', () => {
  assert.equal(TRACKABLE_BOOKING_STATUSES.has('DRIVER_ASSIGNED'), false);
  assert.equal(TRACKABLE_BOOKING_STATUSES.has('ON_ROUTE'), true);
  assert.equal(TRACKABLE_BOOKING_STATUSES.has('DRIVER_ARRIVED'), true);
  assert.equal(TRACKABLE_BOOKING_STATUSES.has('PICKED_UP'), true);
  assert.equal(TRACKABLE_BOOKING_STATUSES.has('SETTLEMENT_PENDING'), false);
});

test('service ignores duplicate or older location timestamps without updating', async () => {
  let updated = false;
  const recordedAt = new Date();
  const service = new DriverLocationService(
    {
      async getConnection() {
        return {
          async beginTransaction() {},
          async commit() {},
          async rollback() {},
          release() {},
        };
      },
    },
    {
      async findDriverByUserIdForUpdate() {
        return {
          id: 7,
          is_active: true,
          is_online: true,
          status: 'AVAILABLE',
          location_recorded_at: recordedAt.toISOString(),
        };
      },
      async hasActiveJob() {
        return true;
      },
      async updateCurrentLocation() {
        updated = true;
      },
      async listActiveBookingRoomsForDriver() {
        return [99];
      },
    },
  );

  const result = await service.updateDriverLocation(44, {
    latitude: 12.9,
    longitude: 100.8,
    recordedAt: recordedAt.toISOString(),
  });

  assert.equal(result.accepted, false);
  assert.equal(result.reason, 'STALE_LOCATION');
  assert.deepEqual(result.bookingIds, []);
  assert.equal(updated, false);
});

test('service accepts fresh location when driver has trackable active job', async () => {
  let updated = false;
  const service = new DriverLocationService(
    {
      async getConnection() {
        return {
          async beginTransaction() {},
          async commit() {},
          async rollback() {},
          release() {},
        };
      },
    },
    {
      async findDriverByUserIdForUpdate() {
        return {
          id: 7,
          is_active: true,
          is_online: true,
          status: 'AVAILABLE',
          location_recorded_at: '2026-07-01 10:29:00',
        };
      },
      async hasActiveJob() {
        return true;
      },
      async updateCurrentLocation(_conn, driverId, location) {
        assert.equal(driverId, 7);
        assert.equal(location.latitude, 12.9);
        updated = true;
      },
      async listActiveBookingRoomsForDriver() {
        return [99];
      },
    },
  );

  const result = await service.updateDriverLocation(44, {
    latitude: 12.9,
    longitude: 100.8,
    recordedAt: new Date().toISOString(),
  });

  assert.equal(result.accepted, true);
  assert.deepEqual(result.bookingIds, [99]);
  assert.equal(updated, true);
});

test('socket driver location update ignores client supplied driverId and broadcasts authorized result', async () => {
  const io = buildIo();
  const socket = buildSocket({ authUser: { id: 44, role: ROLES.DRIVER } });
  registerDriverLocationService({
    async updateDriverLocation(driverUserId, payload) {
      assert.equal(driverUserId, 44);
      assert.equal(payload.driverId, 999);
      return { driverId: 7, bookingIds: [99] };
    },
    async listAdminLocations() {
      return {
        items: [{
          driverId: 7,
          displayName: 'Somchai',
          latitude: 12.9,
          longitude: 100.8,
          stale: false,
        }],
      };
    },
  });

  registerDriverLocationHandlers(io, socket);
  let ack;
  await socket.handlers['driver:location:update'](
    { driverId: 999, latitude: 12.9, longitude: 100.8 },
    (value) => { ack = value; },
  );

  assert.equal(ack.ok, true);
  assert.deepEqual(
    io.emitted.map((item) => [item.room, item.event]),
    [
      [ADMIN_DRIVER_LOCATION_ROOM, 'driver:location:changed'],
      [bookingDriverLocationRoom(99), 'booking:driver-location:changed'],
    ],
  );
});

test('socket location update does not broadcast stale no-op result', async () => {
  const io = buildIo();
  const socket = buildSocket({ authUser: { id: 44, role: ROLES.DRIVER } });
  registerDriverLocationService({
    async updateDriverLocation() {
      return { driverId: 7, accepted: false, bookingIds: [] };
    },
    async listAdminLocations() {
      throw new Error('stale no-op should not load snapshot');
    },
  });

  registerDriverLocationHandlers(io, socket);
  let ack;
  await socket.handlers['driver:location:update'](
    { latitude: 12.9, longitude: 100.8 },
    (value) => { ack = value; },
  );

  assert.equal(ack.ok, true);
  assert.equal(ack.accepted, false);
  assert.deepEqual(io.emitted, []);
});

test('socket guest cannot subscribe to another booking', async () => {
  const io = buildIo();
  const socket = buildSocket({ guestAccessToken: 'guest-token' });
  registerDriverLocationService({
    async getGuestDriverLocation() {
      const err = new Error('Booking is not accessible');
      err.errorCode = ERROR_CODES.BOOKING_NOT_ACCESSIBLE;
      throw err;
    },
  });
  registerDriverLocationHandlers(io, socket);

  let ack;
  await socket.handlers['booking:driver-location:subscribe'](
    { bookingId: 100 },
    (value) => { ack = value; },
  );

  assert.equal(ack.ok, false);
  assert.equal(socket.joinedRooms.size, 0);
  assert.equal(ack.error.code, ERROR_CODES.BOOKING_NOT_ACCESSIBLE);
});

test('socket admin room subscription requires admin role', async () => {
  const io = buildIo();
  const adminSocket = buildSocket({ authUser: { id: 1, role: ROLES.SUPER_ADMIN } });
  registerDriverLocationHandlers(io, adminSocket);
  await adminSocket.handlers['driver-location:admin:subscribe']();
  assert.equal(adminSocket.joinedRooms.has(ADMIN_DRIVER_LOCATION_ROOM), true);

  const driverSocket = buildSocket({ authUser: { id: 44, role: ROLES.DRIVER } });
  registerDriverLocationHandlers(io, driverSocket);
  let ack;
  await driverSocket.handlers['driver-location:admin:subscribe']({}, (value) => { ack = value; });
  assert.equal(ack.ok, false);
  assert.equal(driverSocket.joinedRooms.has(ADMIN_DRIVER_LOCATION_ROOM), false);
});
