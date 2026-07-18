const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const DriverJobService = require('../src/services/driverJob.service');
const BookingRepository = require('../src/repositories/booking.repository');
const ERROR_CODES = require('../src/constants/errorCodes');
const container = require('../src/helpers/container');
const app = require('../src/app');

function sign(role = 'DRIVER', id = 44) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function row(overrides = {}) {
  return {
    booking_number: 'TX202607010001',
    status: 'DRIVER_ASSIGNED',
    assignment_status: 'ASSIGNED',
    pickup_date: '2026-07-01',
    pickup_time: '09:30',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    customer_name: 'Kim',
    customer_phone: '+66123456789',
    special_requests: 'Meet at gate',
    payment_method: 'PAY_DRIVER',
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
    flight_estimated_arrival_at_text: '2026-07-01 08:55:00',
    delay_status: 'Delayed 10 min',
    delay_minutes: 10,
    ...overrides,
  };
}

test('DRIVER can access today endpoint', async () => {
  container.register('driverJobService', () => ({
    async listToday(driverUserId) {
      assert.equal(driverUserId, 44);
      return {
        date: '2026-07-01',
        items: [
          {
            bookingNumber: 'TX209901010001',
            status: 'DRIVER_ASSIGNED',
            assignmentStatus: 'ASSIGNED',
          },
        ],
      };
    },
  }));

  const res = await request(app)
    .get('/api/v1/driver/bookings/today')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.items[0].bookingNumber, 'TX209901010001');
  assert.equal(res.body.data.items[0].status, 'DRIVER_ASSIGNED');
  assert.equal(res.body.data.items[0].assignmentStatus, 'ASSIGNED');
});

test('DRIVER detail endpoint returns accepted assignment status', async () => {
  container.register('driverJobService', () => ({
    async getDetail(driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, 'TX209901010001');
      return {
        bookingNumber,
        status: 'DRIVER_ASSIGNED',
        assignmentStatus: 'ACCEPTED',
      };
    },
  }));

  const res = await request(app)
    .get('/api/v1/driver/bookings/TX209901010001')
    .set('Authorization', `Bearer ${sign('DRIVER', 44)}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.bookingNumber, 'TX209901010001');
  assert.equal(res.body.data.status, 'DRIVER_ASSIGNED');
  assert.equal(res.body.data.assignmentStatus, 'ACCEPTED');
});

test('non-DRIVER is rejected', async () => {
  const res = await request(app)
    .get('/api/v1/driver/bookings/today')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 55)}`);

  assert.equal(res.status, 403);
  assert.equal(res.body.error_code, ERROR_CODES.FORBIDDEN);
});

test('repository filters only active assigned bookings for this driver and excludes cancelled', async () => {
  const calls = [];
  const repo = new BookingRepository({
    async query(sql, params) {
      calls.push({ sql, params });
      return [[]];
    },
  });

  await repo.findActiveDriverBookingsForDate(44, {
    start: '2026-07-01 00:00:00',
    end: '2026-07-02 00:00:00',
  });

  const { sql, params } = calls[0];
  assert.match(sql, /d\.user_id = \?/);
  assert.match(sql, /bda\.status AS assignment_status/);
  assert.match(sql, /bda\.is_active = 1/);
  assert.match(sql, /bda\.status IN \('ASSIGNED', 'ACCEPTED'\)/);
  assert.match(sql, /b\.status <> 'CANCELLED'/);
  assert.match(sql, /b\.scheduled_pickup_at >= \?/);
  assert.match(sql, /b\.scheduled_pickup_at < \?/);
  assert.match(sql, /ORDER BY b\.scheduled_pickup_at ASC/);
  assert.deepEqual(params, [44, '2026-07-01 00:00:00', '2026-07-02 00:00:00']);
});

test('repository detail uses active assignment so reassigned bookings are hidden from previous driver', async () => {
  const calls = [];
  const repo = new BookingRepository({
    async query(sql, params) {
      calls.push({ sql, params });
      return [[]];
    },
  });

  await repo.findActiveDriverBookingByNumber(44, 'TX202607010001');

  const { sql, params } = calls[0];
  assert.match(sql, /d\.user_id = \?/);
  assert.match(sql, /bda\.status AS assignment_status/);
  assert.match(sql, /bda\.is_active = 1/);
  assert.match(sql, /bda\.deleted_at IS NULL/);
  assert.match(sql, /bda\.status IN \('ASSIGNED', 'ACCEPTED'\)/);
  assert.deepEqual(params, [44, 'TX202607010001']);
});

test('Thailand date boundary behavior uses Asia Bangkok local day', () => {
  const service = new DriverJobService({});
  const range = service.getTodayRange(new Date('2026-06-30T18:30:00.000Z'));

  assert.equal(range.date, '2026-07-01');
  assert.equal(range.start, '2026-07-01 00:00:00');
  assert.equal(range.end, '2026-07-02 00:00:00');
});

test('today range includes 00:00 and 23:59 Thailand service-local pickups', () => {
  const service = new DriverJobService({});
  const range = service.getTodayRange(new Date('2026-07-01T12:00:00.000Z'));

  assert.equal('2026-07-01 00:00:00' >= range.start, true);
  assert.equal('2026-07-01 23:59:00' < range.end, true);
  assert.equal('2026-07-02 00:00:00' < range.end, false);
});

test('today list sorting is requested from repository and mapped concisely', async () => {
  const service = new DriverJobService({
    async findActiveDriverBookingsForDate(_driverUserId, _range) {
      return [row({ booking_number: 'TX202607010001' })];
    },
  });

  const result = await service.listToday(44, new Date('2026-07-01T01:00:00.000Z'));

  assert.equal(result.items[0].bookingNumber, 'TX202607010001');
  assert.equal(result.items[0].assignmentStatus, 'ASSIGNED');
  assert.equal(result.items[0].pickupDate, '2026-07-01');
  assert.equal(result.items[0].pickupTime, '09:30');
  assert.equal(result.items[0].passengerCount, 3);
  assert.equal(result.items[0].customerDisplayName, 'Kim');
  assert.deepEqual(result.items[0].allowedActions, ['VIEW_DETAILS', 'START_ON_ROUTE']);
});

test('driver can access assigned booking detail', async () => {
  const service = new DriverJobService({
    async findActiveDriverBookingByNumber(driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, 'TX202607010001');
      return row();
    },
  });

  const detail = await service.getDetail(44, 'TX202607010001');

  assert.equal(detail.bookingNumber, 'TX202607010001');
  assert.equal(detail.assignmentStatus, 'ASSIGNED');
  assert.equal(detail.customerPhone, '+66123456789');
  assert.equal(detail.passengers.adults, 2);
  assert.equal(detail.luggage.carriers24InchPlus, 2);
  assert.equal(detail.paymentMethod, 'PAY_DRIVER');
});

test('driver cannot access another driver booking', async () => {
  const service = new DriverJobService({
    async findActiveDriverBookingByNumber() {
      return null;
    },
    async findDriverTerminalBookingByNumber() {
      return null;
    },
  });

  await assert.rejects(
    () => service.getDetail(44, 'TX202607010001'),
    (err) => err.errorCode === ERROR_CODES.BOOKING_NOT_FOUND,
  );
});

test('driver can read completed booking detail after assignment closes', async () => {
  const service = new DriverJobService({
    async findActiveDriverBookingByNumber() {
      return null;
    },
    async findDriverTerminalBookingByNumber(driverUserId, bookingNumber) {
      assert.equal(driverUserId, 44);
      assert.equal(bookingNumber, 'TX202607010001');
      return row({ status: 'COMPLETED', assignment_status: 'COMPLETED' });
    },
  });

  const detail = await service.getDetail(44, 'TX202607010001');

  assert.equal(detail.status, 'COMPLETED');
  assert.equal(detail.assignmentStatus, 'COMPLETED');
  assert.deepEqual(detail.allowedActions, []);
});

test('repository terminal detail uses completed assignment for this driver only', async () => {
  const calls = [];
  const repo = new BookingRepository({
    async query(sql, params) {
      calls.push({ sql, params });
      return [[]];
    },
  });

  await repo.findDriverTerminalBookingByNumber(44, 'TX202607010001');

  const { sql, params } = calls[0];
  assert.match(sql, /d\.user_id = \?/);
  assert.match(sql, /bda\.status AS assignment_status/);
  assert.match(sql, /bda\.status = 'COMPLETED'/);
  assert.match(sql, /b\.status IN \('COMPLETED', 'CANCELLED', 'NO_SHOW'\)/);
  assert.deepEqual(params, [44, 'TX202607010001']);
});

test('invalid booking number is rejected', async () => {
  const service = new DriverJobService({});

  await assert.rejects(
    () => service.getDetail(44, 'BAD'),
    (err) => err.errorCode === ERROR_CODES.VALIDATION_ERROR,
  );
});

test('internal admin fields are not exposed in detail', async () => {
  const service = new DriverJobService({
    async findActiveDriverBookingByNumber() {
      return row({
        total_amount: 1600,
        currency: 'THB',
        payment_method: 'PAY_DRIVER_AT_DESTINATION',
        commission_amount: 200,
        commission_status: 'DUE',
        admin_note: 'VIP internal',
      });
    },
  });

  const detail = await service.getDetail(44, 'TX202607010001');

  assert.equal(Object.hasOwn(detail, 'totalAmount'), false);
  assert.equal(Object.hasOwn(detail, 'commissionStatus'), false);
  assert.equal(Object.hasOwn(detail, 'adminNotes'), false);
  assert.equal(detail.customerPaymentAmount, 1600);
  assert.equal(detail.customerPaymentCurrency, 'THB');
  assert.equal(detail.customerPaymentMethod, 'PAY_DRIVER_AT_DESTINATION');
  assert.equal(detail.companyCommissionAmount, 200);
  assert.equal(detail.companyCommissionCurrency, 'THB');
  assert.equal(detail.driverExpectedIncomeAmount, 1400);
  assert.equal(detail.driverExpectedIncomeCurrency, 'THB');
});

test('driver job payment summary keeps unsafe expected income nullable', () => {
  const service = new DriverJobService({});

  assert.equal(service.driverExpectedIncome(1300, 200), 1100);
  assert.equal(service.driverExpectedIncome(1300, 0), 1300);
  assert.equal(service.driverExpectedIncome(null, 200), null);
  assert.equal(service.driverExpectedIncome(1300, null), null);
  assert.equal(service.driverExpectedIncome(1300, 1500), null);
  assert.equal(service.driverExpectedIncome(-1, 0), null);
  assert.equal(service.driverExpectedIncome(1300, -1), null);

  const summary = service.paymentSummary({
    total_amount: 1300,
    commission_amount: 1500,
    currency: 'THB',
    payment_method: 'PAY_DRIVER',
  });
  assert.equal(summary.customerPaymentAmount, 1300);
  assert.equal(summary.companyCommissionAmount, 1500);
  assert.equal(summary.driverExpectedIncomeAmount, null);
  assert.equal(summary.driverExpectedIncomeCurrency, null);
});

test('driver job mapping preserves assignment status without guessing', () => {
  const service = new DriverJobService({});

  const statuses = ['ASSIGNED', 'ACCEPTED', 'REJECTED', 'COMPLETED', 'CANCELLED'];
  for (const status of statuses) {
    const result = service.mapBase(row({ assignment_status: status }));
    assert.equal(result.assignmentStatus, status);
  }
  assert.equal(service.mapBase(row({ assignment_status: null })).assignmentStatus, null);
  const unknown = service.mapBase(row({ assignment_status: 'FUTURE_STATUS' }));
  assert.equal(unknown.assignmentStatus, 'FUTURE_STATUS');
});
