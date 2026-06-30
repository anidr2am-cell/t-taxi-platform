process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');
const { appEvents, EVENTS } = require('../src/events');

const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const AdminDispatchService = require('../src/services/adminDispatch.service');
const DriverCandidateScoringService = require('../src/services/driverCandidateScoring.service');
const container = require('../src/helpers/container');
const app = require('../src/app');

const settlementStub = { async driverHasBlockingSettlement() { return false; } };
const scoringService = new DriverCandidateScoringService();

function sign(role = 'ADMIN', id = 1) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function queueRow(overrides = {}) {
  return {
    booking_number: 'TX202607010001',
    status: 'PENDING',
    scheduled_pickup_at: '2026-07-01 09:30:00',
    origin_address: 'BKK',
    destination_address: 'Pattaya',
    customer_name: 'Kim',
    customer_phone: '+66123456789',
    payment_method: 'PAY_DRIVER',
    total_amount: 1200,
    currency: 'THB',
    created_at: '2026-06-30 10:00:00',
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
    delay_status: null,
    assignment_id: null,
    assignment_driver_id: null,
    assignment_status: null,
    driver_name: null,
    driver_phone: null,
    ...overrides,
  };
}

test('ADMIN can list bookings', async () => {
  container.register('adminDispatchService', () => ({
    async listBookings() {
      return { page: 1, pageSize: 20, total: 1, items: [{ bookingNumber: 'TX202607010001' }] };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/bookings')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.total, 1);
});

test('SUPER_ADMIN can list bookings', async () => {
  container.register('adminDispatchService', () => ({
    async listBookings() {
      return { page: 1, pageSize: 20, total: 0, items: [] };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/bookings')
    .set('Authorization', `Bearer ${sign('SUPER_ADMIN')}`);

  assert.equal(res.status, 200);
});

test('DRIVER and CUSTOMER are rejected', async () => {
  const resDriver = await request(app)
    .get('/api/v1/admin/bookings')
    .set('Authorization', `Bearer ${sign('DRIVER', 9)}`);
  assert.equal(resDriver.status, 403);

  const resCustomer = await request(app)
    .get('/api/v1/admin/bookings')
    .set('Authorization', `Bearer ${sign('CUSTOMER', 8)}`);
  assert.equal(resCustomer.status, 403);
  assert.equal(resCustomer.body.error_code, ERROR_CODES.FORBIDDEN);
});

test('service maps queue item without secrets', () => {
  const service = new AdminDispatchService({}, {}, {}, {}, settlementStub, null, null, scoringService);
  const item = service.mapQueueItem(queueRow());
  assert.equal(item.bookingNumber, 'TX202607010001');
  assert.equal(item.scheduledPickupAt, '2026-07-01 09:30:00');
  assert.equal(item.activeAssignment, null);
  assert.equal(item.passengerCount, 2);
  assert.ok(!('boardingQrTokenHash' in item));
});

test('assign rejects already assigned booking', async () => {
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.PENDING, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() {
      return { id: 10, driver_id: 5 };
    },
  };
  const service = new AdminDispatchService(pool, bookingRepo, {}, {}, settlementStub, null, null, scoringService);

  await assert.rejects(
    () => service.assignDriver('TX202607010001', { driverId: 6 }, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.ALREADY_ASSIGNED,
  );
});

test('reassign rejects same driver', async () => {
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.DRIVER_ASSIGNED, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() {
      return { id: 10, driver_id: 5 };
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, {}, {}, settlementStub, null, null, scoringService);

  await assert.rejects(
    () => service.reassignDriver(
      'TX202607010001',
      { driverId: 5, reason: 'test' },
      { id: 1, role: 'ADMIN' },
    ),
    (err) => err.statusCode === 409,
  );
});

test('reassign rejects PICKED_UP booking', async () => {
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.PICKED_UP, booking_number: 'TX202607010001' };
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, {}, {}, settlementStub, null, null, scoringService);

  await assert.rejects(
    () => service.reassignDriver(
      'TX202607010001',
      { driverId: 6, reason: 'swap' },
      { id: 1, role: 'ADMIN' },
    ),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('assign uses BookingStatusService transitions', async () => {
  const transitions = [];
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.PENDING, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() {
      return null;
    },
    async insertDriverAssignment() {
      return 99;
    },
    async insertActivityLog() {},
  };
  const driverRepo = {
    async findByIdForUpdate() {
      return { id: 6, name: 'Driver A', phone: '+6600', is_active: 1, status: 'AVAILABLE' };
    },
    async findPrimaryVehicle() {
      return { id: 3 };
    },
  };
  const statusService = {
    async transitionInTransaction(_conn, _bookingNumber, input) {
      transitions.push(input.status);
      return { result: {}, domainEvent: null, eventPayload: null };
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, driverRepo, statusService, settlementStub, null, null, scoringService);

  await service.assignDriver('TX202607010001', { driverId: 6 }, { id: 1, role: 'ADMIN' });
  assert.deepEqual(transitions, [BOOKING_STATUS.CONFIRMED, BOOKING_STATUS.DRIVER_ASSIGNED]);
});

test('reassign dispatches outbox only after commit', async () => {
  let dispatched = 0;
  const outboxRepository = {
    async insertNotificationEvent() {
      return 77;
    },
  };
  const outboxProcessor = {
    async dispatchOutboxIds(ids) {
      assert.deepEqual(ids, [77]);
      dispatched += 1;
    },
  };

  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.DRIVER_ASSIGNED, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() {
      return { id: 10, driver_id: 5 };
    },
    async deactivateAssignment() {
      return true;
    },
    async insertDriverAssignment() {
      return 11;
    },
    async insertActivityLog() {},
  };
  const driverRepo = {
    async findByIdForUpdate() {
      return { id: 6, name: 'Driver B', phone: '+6601', is_active: 1, status: 'AVAILABLE' };
    },
    async findPrimaryVehicle() {
      return null;
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(
    pool,
    bookingRepo,
    driverRepo,
    {},
    settlementStub,
    outboxRepository,
    outboxProcessor,
    scoringService,
  );

  await service.reassignDriver(
    'TX202607010001',
    { driverId: 6, reason: 'Closer driver' },
    { id: 1, role: 'ADMIN' },
  );
  assert.equal(dispatched, 1);
});

test('booking detail never includes qr hashes', async () => {
  const bookingRepo = {
    async findAdminBookingDetail() {
      return {
        id: 1,
        booking_number: 'TX202607010001',
        status: 'PENDING',
        scheduled_pickup_at: '2026-07-01 09:30:00',
        origin_address: 'BKK',
        destination_address: 'Pattaya',
        customer_name: 'Kim',
        customer_email: 'kim@example.com',
        customer_phone: '+66123456789',
        customer_country_code: 'TH',
        special_requests: null,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        commission_status: 'NOT_DUE_YET',
        total_amount: 1200,
        currency: 'THB',
        vehicle_count: 1,
        created_at: '2026-06-30 10:00:00',
        updated_at: '2026-06-30 10:00:00',
        metadata: null,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport Pickup',
        vehicle_type_code: 'SUV',
        vehicle_type_name: 'SUV',
        adults: +2,
        children: 0,
        infants: 0,
        carriers_20_inch: 1,
        carriers_24_inch_plus: 0,
        golf_bags: 0,
        special_items: null,
        flight_number: 'TG409',
        flight_scheduled_arrival_at: null,
        flight_estimated_arrival_at: null,
        delay_status: null,
        delay_minutes: null,
        airport_code_custom: 'BKK',
        airport_iata: 'BKK',
        boarding_qr_token_hash: 'secret',
      };
    },
    async findChargeItemsByBookingId() { return []; },
    async findStatusLogsByBookingId() { return []; },
    async findAssignmentsByBookingId() { return []; },
  };
  const service = new AdminDispatchService({}, bookingRepo, {}, {}, settlementStub, null, null, scoringService);
  const detail = await service.getBookingDetail('TX202607010001');
  assert.equal(detail.bookingNumber, 'TX202607010001');
  assert.equal(detail.scheduledPickupAt, '2026-07-01 09:30:00');
  assert.ok(!('boardingQrTokenHash' in detail));
  assert.ok(!('guestAccessToken' in detail));
});

test('booking detail returns latest active assignment and ignores old inactive assignment', async () => {
  const bookingRepo = {
    async findAdminBookingDetail() {
      return {
        id: 1,
        booking_number: 'TX202607010001',
        status: 'DRIVER_ASSIGNED',
        scheduled_pickup_at: '2026-07-01 09:30:00',
        origin_address: 'BKK',
        destination_address: 'Pattaya',
        customer_name: 'Kim',
        customer_email: 'kim@example.com',
        customer_phone: '+66123456789',
        customer_country_code: 'TH',
        special_requests: null,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        commission_status: 'NOT_DUE_YET',
        total_amount: 1200,
        currency: 'THB',
        vehicle_count: 1,
        created_at: '2026-06-30 10:00:00',
        updated_at: '2026-06-30 10:00:00',
        metadata: null,
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
        flight_number: null,
        flight_scheduled_arrival_at: null,
        flight_estimated_arrival_at: null,
        delay_status: null,
        delay_minutes: null,
        airport_code_custom: null,
        airport_iata: null,
      };
    },
    async findChargeItemsByBookingId() { return []; },
    async findStatusLogsByBookingId() { return []; },
    async findAssignmentsByBookingId() {
      return [
        {
          id: 12,
          driver_id: 7,
          driver_name: 'New Driver',
          driver_phone: '+6601',
          driver_status: 'AVAILABLE',
          status: 'ASSIGNED',
          is_active: 1,
          assigned_at: '2026-06-30 12:00:00',
          unassigned_at: null,
          assignment_reason: 'AUTO_ASSIGN',
          vehicle_type_code: 'SUV',
          vehicle_type_name: 'SUV',
          vehicle_plate: 'LOCAL-SUV-D2',
          vehicle_model: 'Local Test SUV',
        },
        {
          id: 11,
          driver_id: 6,
          driver_name: 'Old Driver',
          driver_phone: '+6600',
          driver_status: 'OFFLINE',
          status: 'CANCELLED',
          is_active: 0,
          assigned_at: '2026-06-30 11:00:00',
          unassigned_at: '2026-06-30 12:00:00',
          assignment_reason: 'Reassigned',
        },
      ];
    },
  };
  const service = new AdminDispatchService({}, bookingRepo, {}, {}, settlementStub, null, null, scoringService);
  const detail = await service.getBookingDetail('TX202607010001');

  assert.equal(detail.activeAssignment.driverId, 7);
  assert.equal(detail.activeAssignment.driverDisplayName, 'New Driver');
  assert.equal(detail.activeAssignment.driverStatus, 'AVAILABLE');
  assert.equal(detail.activeAssignment.vehicle.plateNumber, 'LOCAL-SUV-D2');
  assert.equal(detail.assignmentHistory[1].isActive, false);
  assert.ok(!('driverEmail' in detail.activeAssignment));
  assert.ok(!('driverPhone' in detail.activeAssignment));
  assert.ok(!('driverPhone' in detail.assignmentHistory[0]));
});

test('queue active assignment maps driver and vehicle without private auth data', () => {
  const service = new AdminDispatchService({}, {}, {}, {}, settlementStub, null, null, scoringService);
  const item = service.mapQueueItem(queueRow({
    assignment_id: 20,
    assignment_driver_id: 7,
    assignment_status: 'ASSIGNED',
    driver_name: 'Driver A',
    driver_status: 'AVAILABLE',
    assigned_vehicle_type_code: 'SUV',
    assigned_vehicle_type_name: 'SUV',
    assigned_vehicle_plate: 'LOCAL-SUV-D2',
    assigned_vehicle_model: 'Local Test SUV',
  }));

  assert.equal(item.activeAssignment.driverDisplayName, 'Driver A');
  assert.equal(item.activeAssignment.driverStatus, 'AVAILABLE');
  assert.equal(item.activeAssignment.vehicle.plateNumber, 'LOCAL-SUV-D2');
  assert.ok(!('email' in item.activeAssignment));
  assert.ok(!('driverPhone' in item.activeAssignment));
});

test('listBookings passes search and assignment filters to repository', async () => {
  let capturedFilters = null;
  const bookingRepo = {
    async countAdminBookings(filters) {
      capturedFilters = filters;
      return 0;
    },
    async findAdminBookings() { return []; },
  };
  const service = new AdminDispatchService({}, bookingRepo, {}, {}, settlementStub, null, null, scoringService);
  await service.listBookings({
    search: 'TG409',
    status: 'PENDING',
    assignmentState: 'UNASSIGNED',
    serviceDateFrom: '2026-07-01',
    serviceDateTo: '2026-07-02',
    page: 2,
    limit: 10,
  });
  assert.equal(capturedFilters.search, 'TG409');
  assert.equal(capturedFilters.status, 'PENDING');
  assert.equal(capturedFilters.assignmentState, 'UNASSIGNED');
  assert.equal(capturedFilters.serviceDateFrom, '2026-07-01 00:00:00');
  assert.ok(capturedFilters.serviceDateTo);
});

test('ADMIN can get booking detail', async () => {
  container.register('adminDispatchService', () => ({
    async getBookingDetail(bookingNumber) {
      return { bookingNumber, status: 'PENDING', allowedActions: ['ASSIGN_DRIVER'] };
    },
  }));

  const res = await request(app)
    .get('/api/v1/admin/bookings/TX202607010001')
    .set('Authorization', `Bearer ${sign('ADMIN')}`);

  assert.equal(res.status, 200);
  assert.equal(res.body.data.bookingNumber, 'TX202607010001');
});

test('assign rejects ineligible driver', async () => {
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.PENDING, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() { return null; },
  };
  const driverRepo = {
    async findByIdForUpdate() {
      return { id: 6, name: 'Suspended', phone: '+6600', is_active: 0, status: 'SUSPENDED' };
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, driverRepo, {}, settlementStub, null, null, scoringService);

  await assert.rejects(
    () => service.assignDriver('TX202607010001', { driverId: 6 }, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('assign rejects terminal booking status', async () => {
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.COMPLETED, booking_number: 'TX202607010001' };
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, {}, {}, settlementStub, null, null, scoringService);

  await assert.rejects(
    () => service.assignDriver('TX202607010001', { driverId: 6 }, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.INVALID_STATUS_TRANSITION,
  );
});

test('assign creates exactly one active assignment', async () => {
  let insertCount = 0;
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.CONFIRMED, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() { return null; },
    async insertDriverAssignment() {
      insertCount += 1;
      return 42;
    },
    async insertActivityLog() {},
  };
  const driverRepo = {
    async findByIdForUpdate() {
      return { id: 6, name: 'Driver A', phone: '+6600', is_active: 1, status: 'AVAILABLE' };
    },
    async findPrimaryVehicle() { return { id: 3 }; },
  };
  const statusService = {
    async transitionInTransaction() {
      return { result: {}, domainEvent: null, eventPayload: null };
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, driverRepo, statusService, settlementStub, null, null, scoringService);

  await service.assignDriver('TX202607010001', { driverId: 6 }, { id: 1, role: 'ADMIN' });
  assert.equal(insertCount, 1);
});

test('reassign deactivates previous assignment and creates one new active assignment', async () => {
  let deactivated = false;
  let insertCount = 0;
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.DRIVER_ASSIGNED, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() {
      return { id: 10, driver_id: 5 };
    },
    async deactivateAssignment() {
      deactivated = true;
      return true;
    },
    async insertDriverAssignment() {
      insertCount += 1;
      return 11;
    },
    async insertActivityLog() {},
  };
  const driverRepo = {
    async findByIdForUpdate() {
      return { id: 6, name: 'Driver B', phone: '+6601', is_active: 1, status: 'AVAILABLE' };
    },
    async findPrimaryVehicle() { return null; },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, driverRepo, {}, settlementStub, null, null, scoringService);

  await service.reassignDriver(
    'TX202607010001',
    { driverId: 6, reason: 'Closer' },
    { id: 1, role: 'ADMIN' },
  );
  assert.equal(deactivated, true);
  assert.equal(insertCount, 1);
});

test('assign maps ER_DUP_ENTRY to ASSIGNMENT_CONFLICT', async () => {
  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.PENDING, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() { return null; },
    async insertDriverAssignment() {
      const err = new Error('dup');
      err.code = 'ER_DUP_ENTRY';
      throw err;
    },
  };
  const driverRepo = {
    async findByIdForUpdate() {
      return { id: 6, name: 'Driver A', phone: '+6600', is_active: 1, status: 'AVAILABLE' };
    },
    async findPrimaryVehicle() { return null; },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(pool, bookingRepo, driverRepo, {}, settlementStub, null, null, scoringService);

  await assert.rejects(
    () => service.assignDriver('TX202607010001', { driverId: 6 }, { id: 1, role: 'ADMIN' }),
    (err) => err.errorCode === ERROR_CODES.ASSIGNMENT_CONFLICT,
  );
});

test('reassign does not dispatch outbox when transaction fails', async () => {
  let dispatched = 0;
  const outboxRepository = {
    async insertNotificationEvent() {
      return 77;
    },
  };
  const outboxProcessor = {
    async dispatchOutboxIds() {
      dispatched += 1;
    },
  };

  const bookingRepo = {
    async findByBookingNumberForUpdate() {
      return { id: 1, status: BOOKING_STATUS.DRIVER_ASSIGNED, booking_number: 'TX202607010001' };
    },
    async findActiveAssignmentForUpdate() {
      return { id: 10, driver_id: 5 };
    },
    async deactivateAssignment() {
      const err = new Error('fail');
      throw err;
    },
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const pool = { async getConnection() { return conn; } };
  const service = new AdminDispatchService(
    pool,
    bookingRepo,
    {},
    {},
    settlementStub,
    outboxRepository,
    outboxProcessor,
    scoringService,
  );

  await assert.rejects(
    () => service.reassignDriver(
      'TX202607010001',
      { driverId: 6, reason: 'swap' },
      { id: 1, role: 'ADMIN' },
    ),
  );
  assert.equal(dispatched, 0);
});
