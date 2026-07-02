process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const test = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const app = require('../src/app');
const container = require('../src/helpers/container');
const GuestBookingLookupService = require('../src/services/guestBookingLookup.service');
const { hashToken } = require('../src/utils/tokenHash.util');

function bookingRow(overrides = {}) {
  return {
    id: 10,
    booking_number: 'TX202607010001',
    status: 'PICKED_UP',
    scheduled_pickup_at_text: '2026-07-01 09:30:00',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    customer_phone: '+66 81 234 5678',
    customer_country_code: 'TH',
    payment_method: 'PAY_DRIVER',
    payment_status: 'UNPAID',
    total_amount: '1500.00',
    currency: 'THB',
    vehicle_count: 1,
    boarding_qr_token_hash: 'boarding-hash',
    boarding_qr_used_at: '2026-07-01 09:45:00',
    dropoff_qr_token_hash: null,
    dropoff_qr_used_at: null,
    route_id: 30,
    service_type_code: 'AIRPORT_PICKUP',
    service_type_name: 'Airport Pickup',
    vehicle_type_code: 'SUV',
    vehicle_type_name: 'SUV',
    adults: 2,
    children: 1,
    infants: 0,
    carriers_20_inch: 1,
    carriers_24_inch_plus: 2,
    golf_bags: 0,
    special_items: null,
    flight_number: 'TG409',
    origin_location_code: 'BKK',
    destination_location_code: 'PATTAYA',
    name_sign_requested: 0,
    driver_name: 'Driver A',
    driver_phone: '+66 80 000 0000',
    assigned_vehicle_plate: '1กข1234',
    assigned_vehicle_model: 'Camry',
    assigned_vehicle_color: 'Black',
    assigned_vehicle_type_code: 'SUV',
    assigned_vehicle_type_name: 'SUV',
    ...overrides,
  };
}

function buildService(row = bookingRow()) {
  const calls = {
    committed: 0,
    rolledBack: 0,
    released: 0,
    insertedTokens: [],
    lookups: [],
  };
  const conn = {
    beginTransaction: async () => {},
    commit: async () => { calls.committed += 1; },
    rollback: async () => { calls.rolledBack += 1; },
    release: () => { calls.released += 1; },
  };
  const pool = {
    getConnection: async () => conn,
  };
  const repository = {
    async findGuestLookupBookingByNumber(_conn, bookingNumber) {
      calls.lookups.push(bookingNumber);
      return row;
    },
    async insertGuestToken(_conn, bookingId, tokenHash, expiresAt) {
      calls.insertedTokens.push({ bookingId, tokenHash, expiresAt });
    },
  };
  return {
    service: new GuestBookingLookupService(pool, repository),
    calls,
  };
}

test('guest lookup returns safe summary and fresh guest access token', async () => {
  const { service, calls } = buildService();

  const result = await service.lookup({
    bookingNumber: 'tx202607010001',
    phone: ' +66 (81) 234-5678 ',
  });

  assert.equal(calls.lookups[0], 'TX202607010001');
  assert.equal(calls.committed, 1);
  assert.equal(calls.rolledBack, 0);
  assert.equal(calls.insertedTokens.length, 1);
  assert.equal(calls.insertedTokens[0].bookingId, 10);
  assert.equal(calls.insertedTokens[0].tokenHash, hashToken(result.guestAccess.token));
  assert.equal(result.bookingNumber, 'TX202607010001');
  assert.equal(result.scheduledPickupAt, '2026-07-01T09:30:00+07:00');
  assert.equal(result.pricing.paymentMethod, 'PAY_DRIVER');
  assert.equal(result.serviceType.code, 'AIRPORT_PICKUP');
  assert.equal(result.route.origin.code, 'BKK');
  assert.equal(result.route.destination.code, 'PATTAYA');
  assert.equal(result.options.nameSignRequested, false);
  assert.equal(result.capabilities.dropoffQrIssueAvailable, true);
  assert.equal(result.capabilities.boardingQrRecoverable, false);
  assert.equal(result.assignedDriver.name, 'Driver A');
  assert.equal(result.assignedDriver.vehicle.plateNumber, '1กข1234');
  assert.equal(result.assignedDriver.vehicle.color, 'Black');
  assert.ok(!JSON.stringify(result).includes('customer_phone'));
  assert.ok(!JSON.stringify(result).includes('customer_email'));
  assert.ok(!JSON.stringify(result).includes('boarding-hash'));
  assert.ok(!JSON.stringify(result).includes('"route_id"'));
  assert.ok(!JSON.stringify(result).includes('"driver_id"'));
});

test('guest lookup includes BKK name sign option for airport pickup guide', async () => {
  const { service } = buildService(bookingRow({ name_sign_requested: 1 }));

  const result = await service.lookup({
    bookingNumber: 'TX202607010001',
    phone: '+66 81 234 5678',
  });

  assert.equal(result.serviceType.code, 'AIRPORT_PICKUP');
  assert.equal(result.route.origin.code, 'BKK');
  assert.equal(result.options.nameSignRequested, true);
});

test('guest lookup exposes other airport code without forcing BKK guide', async () => {
  const { service } = buildService(bookingRow({ origin_location_code: 'DMK' }));

  const result = await service.lookup({
    bookingNumber: 'TX202607010001',
    phone: '+66 81 234 5678',
  });

  assert.equal(result.serviceType.code, 'AIRPORT_PICKUP');
  assert.equal(result.route.origin.code, 'DMK');
  assert.equal(result.options.nameSignRequested, false);
});

test('guest lookup exposes dropoff service code so airport pickup guide remains hidden', async () => {
  const { service } = buildService(bookingRow({
    service_type_code: 'AIRPORT_DROPOFF',
    service_type_name: 'Airport Dropoff',
    origin_location_code: 'PATTAYA',
    destination_location_code: 'BKK',
    name_sign_requested: 0,
  }));

  const result = await service.lookup({
    bookingNumber: 'TX202607010001',
    phone: '+66 81 234 5678',
  });

  assert.equal(result.serviceType.code, 'AIRPORT_DROPOFF');
  assert.equal(result.route.origin.code, 'PATTAYA');
  assert.equal(result.route.destination.code, 'BKK');
  assert.equal(result.options.nameSignRequested, false);
});

test('guest lookup rejects wrong phone with generic booking not found and no token insert', async () => {
  const { service, calls } = buildService();

  await assert.rejects(
    () => service.lookup({
      bookingNumber: 'TX202607010001',
      phone: '+66 81 234 5670',
    }),
    (err) => err.errorCode === 'BOOKING_NOT_FOUND' && err.statusCode === 404,
  );

  assert.equal(calls.insertedTokens.length, 0);
  assert.equal(calls.committed, 0);
  assert.equal(calls.rolledBack, 1);
});

test('guest lookup does not allow partial phone matching', async () => {
  const { service } = buildService();

  await assert.rejects(
    () => service.lookup({
      bookingNumber: 'TX202607010001',
      phone: '2345678',
    }),
    (err) => err.errorCode === 'BOOKING_NOT_FOUND',
  );
});

test('cancelled booking can be found but active customer actions are disabled', async () => {
  const { service } = buildService(bookingRow({ status: 'CANCELLED' }));

  const result = await service.lookup({
    bookingNumber: 'TX202607010001',
    phone: '+66 81 234 5678',
  });

  assert.equal(result.status, 'CANCELLED');
  assert.equal(result.capabilities.chatAvailable, false);
  assert.equal(result.capabilities.dropoffQrIssueAvailable, false);
  assert.equal(result.capabilities.boardingQrPreviouslyIssued, false);
});

test('guest lookup route validates and returns public envelope', async () => {
  container.register('guestBookingLookupService', () => ({
    async lookup(input) {
      assert.deepEqual(input, {
        bookingNumber: 'TX202607010001',
        phone: '+66 81 234 5678',
      });
      return {
        bookingNumber: 'TX202607010001',
        status: 'PICKED_UP',
        guestAccess: { token: 'guest-token', expiresAt: '2026-07-02T00:00:00Z' },
      };
    },
  }));

  const res = await request(app)
    .post('/api/v1/public/bookings/lookup')
    .send({ bookingNumber: 'tx202607010001', phone: '+66 81 234 5678' });

  assert.equal(res.statusCode, 200);
  assert.equal(res.body.success, true);
  assert.equal(res.body.data.bookingNumber, 'TX202607010001');
  assert.equal(res.body.data.guestAccess.token, 'guest-token');
});
