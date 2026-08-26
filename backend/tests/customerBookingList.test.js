process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const CustomerBookingService = require('../src/services/customerBooking.service');
const GuestBookingLookupService = require('../src/services/guestBookingLookup.service');

const USER_ID = 42;
const OTHER_USER_ID = 99;

function bookingRow(overrides = {}) {
  return {
    id: 10,
    booking_number: 'TX202607010001',
    status: 'DRIVER_ASSIGNED',
    scheduled_pickup_at_text: '2026-07-01 09:30:00',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    metadata: JSON.stringify({
      originLocation: { name: 'Suvarnabhumi Airport' },
      destinationLocation: { name: 'Pattaya Beach Hotel' },
    }),
    customer_phone: '+66 81 234 5678',
    customer_country_code: 'TH',
    payment_method: 'PAY_DRIVER',
    payment_status: 'UNPAID',
    total_amount: '1500.00',
    currency: 'THB',
    vehicle_count: 1,
    boarding_qr_token_hash: 'boarding-hash',
    boarding_qr_used_at: null,
    dropoff_qr_token_hash: null,
    dropoff_qr_used_at: null,
    route_id: 30,
    service_type_code: 'AIRPORT_PICKUP',
    service_type_name: 'Airport Pickup',
    vehicle_type_code: 'SUV',
    vehicle_type_name: 'SUV',
    adults: 2,
    children: 0,
    infants: 0,
    carriers_20_inch: 1,
    carriers_24_inch_plus: 0,
    golf_bags: 0,
    special_items: null,
    flight_number: 'TG409',
    origin_location_code: 'BKK',
    destination_location_code: 'PATTAYA',
    name_sign_requested: 0,
    prefer_female_driver: 0,
    has_driver_release_history: 0,
    driver_id: 4,
    driver_name: 'Driver A',
    driver_phone: '+66 80 000 0000',
    assigned_vehicle_plate: '1กข1234',
    assigned_vehicle_model: 'Camry',
    assigned_vehicle_color: 'Black',
    assigned_vehicle_type_code: 'SUV',
    assigned_vehicle_type_name: 'SUV',
    driver_vehicle_photo_file_id: null,
    ...overrides,
  };
}

function createHarness(rowsByUser = new Map([[USER_ID, [bookingRow()]]])) {
  const calls = {
    findByCustomerUserId: [],
    countByCustomerUserId: [],
    reviewLookups: [],
  };

  const bookingRepository = {
    async findByCustomerUserId(userId, pagination) {
      calls.findByCustomerUserId.push({ userId, pagination });
      const rows = rowsByUser.get(userId) ?? [];
      const { limit, offset } = pagination;
      return rows.slice(offset, offset + limit);
    },
    async countByCustomerUserId(userId) {
      calls.countByCustomerUserId.push(userId);
      return (rowsByUser.get(userId) ?? []).length;
    },
  };

  const guestBookingLookupService = new GuestBookingLookupService(
    { getConnection: async () => ({ release() {} }) },
    bookingRepository,
    {
      mapVehiclePhotoUrl() {
        return null;
      },
    },
  );

  const reviewRepository = {
    async findByBookingId(bookingId) {
      calls.reviewLookups.push(bookingId);
      return null;
    },
  };

  const service = new CustomerBookingService(
    bookingRepository,
    guestBookingLookupService,
    reviewRepository,
  );

  return { service, calls };
}

function registerCustomerAuth(userId = USER_ID) {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: userId, role: 'CUSTOMER', email: 'customer@test.local' };
    },
  }));
}

describe('CustomerBookingService.listMyBookings', () => {
  test('returns only the authenticated user bookings', async () => {
    const otherBooking = bookingRow({
      id: 11,
      booking_number: 'TX202607010002',
    });
    const harness = createHarness(new Map([
      [USER_ID, [bookingRow()]],
      [OTHER_USER_ID, [otherBooking]],
    ]));

    const result = await harness.service.listMyBookings(USER_ID, { page: 1, limit: 20 });

    assert.equal(result.total, 1);
    assert.equal(result.bookings.length, 1);
    assert.equal(result.bookings[0].bookingNumber, 'TX202607010001');
    assert.equal(harness.calls.findByCustomerUserId[0].userId, USER_ID);
    assert.equal(harness.calls.countByCustomerUserId[0], USER_ID);
  });

  test('returns empty list for a new user with no bookings', async () => {
    const harness = createHarness(new Map());

    const result = await harness.service.listMyBookings(USER_ID, { page: 1, limit: 20 });

    assert.deepEqual(result, {
      bookings: [],
      total: 0,
      page: 1,
      limit: 20,
    });
  });

  test('paginates results', async () => {
    const rows = [
      bookingRow({ id: 1, booking_number: 'TX202607010001' }),
      bookingRow({ id: 2, booking_number: 'TX202607010002' }),
      bookingRow({ id: 3, booking_number: 'TX202607010003' }),
    ];
    const harness = createHarness(new Map([[USER_ID, rows]]));

    const page1 = await harness.service.listMyBookings(USER_ID, { page: 1, limit: 2 });
    const page2 = await harness.service.listMyBookings(USER_ID, { page: 2, limit: 2 });

    assert.equal(page1.total, 3);
    assert.equal(page1.bookings.length, 2);
    assert.equal(page1.bookings[0].bookingNumber, 'TX202607010001');
    assert.equal(page1.bookings[1].bookingNumber, 'TX202607010002');
    assert.equal(page2.bookings.length, 1);
    assert.equal(page2.bookings[0].bookingNumber, 'TX202607010003');
    assert.deepEqual(harness.calls.findByCustomerUserId[0].pagination, {
      page: 1,
      limit: 2,
      offset: 0,
    });
    assert.deepEqual(harness.calls.findByCustomerUserId[1].pagination, {
      page: 2,
      limit: 2,
      offset: 2,
    });
  });

  test('includes assigned driver and vehicle when present', async () => {
    const harness = createHarness();

    const result = await harness.service.listMyBookings(USER_ID, { page: 1, limit: 20 });
    const booking = result.bookings[0];

    assert.equal(booking.assignedDriver?.name, 'Driver A');
    assert.equal(booking.assignedDriver?.phone, '+66 80 000 0000');
    assert.equal(booking.assignedDriver?.vehicle?.plateNumber, '1กข1234');
    assert.equal(booking.assignedDriver?.vehicle?.modelName, 'Camry');
    assert.equal(booking.route.origin.code, 'BKK');
    assert.equal(booking.scheduledPickupAt, '2026-07-01T09:30:00+07:00');
  });
});

describe('GET /api/v1/customer/bookings', () => {
  test('returns 401 without JWT', async () => {
    const res = await request(app).get('/api/v1/customer/bookings');

    assert.equal(res.status, 401);
  });

  test('returns paginated bookings for authenticated customer', async () => {
    registerCustomerAuth(USER_ID);
    container.register('customerBookingService', () => ({
      async listMyBookings(userId, query) {
        assert.equal(userId, USER_ID);
        assert.equal(query.page, 2);
        assert.equal(query.limit, 1);
        return {
          bookings: [{
            bookingNumber: 'TX202607010002',
            status: 'OPEN',
            route: {
              origin: { code: 'BKK', address: 'BKK Airport', name: null },
              destination: { code: 'PATTAYA', address: 'Pattaya Hotel', name: null },
            },
            scheduledPickupAt: '2026-07-02T10:00:00+07:00',
            assignedDriver: null,
          }],
          total: 2,
          page: 2,
          limit: 1,
        };
      },
    }));

    const res = await request(app)
      .get('/api/v1/customer/bookings?page=2&limit=1')
      .set('Authorization', 'Bearer customer-token')
      .expect(200);

    assert.equal(res.body.success, true);
    assert.equal(res.body.data.total, 2);
    assert.equal(res.body.data.page, 2);
    assert.equal(res.body.data.limit, 1);
    assert.equal(res.body.data.bookings.length, 1);
    assert.equal(res.body.data.bookings[0].bookingNumber, 'TX202607010002');
  });
});
