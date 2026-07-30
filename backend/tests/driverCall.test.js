const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const DriverCallService = require('../src/services/driverCall.service');
const BookingAssignmentReopenService = require('../src/services/bookingAssignmentReopen.service');
const DriverJobService = require('../src/services/driverJob.service');
const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { registerDriverCallHandlers } = require('../src/socket/handlers/driverCalls.handler');
const { DRIVER_ALL_ROOM, driverUserRoom, setRealtimeIo } = require('../src/socket/realtime');
const HTTP_STATUS = require('../src/constants/httpStatus');

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

function openCallRow(overrides = {}) {
  return {
    booking_number: 'TX202607130001',
    status: BOOKING_STATUS.OPEN,
    pickup_date: '2026-07-13',
    pickup_time: '10:30',
    origin_address: 'BKK Airport',
    destination_address: 'Pattaya Hotel',
    total_amount: 2500,
    currency: 'THB',
    payment_method: 'PAY_DRIVER',
    commission_amount: 300,
    service_type_code: 'AIRPORT_PICKUP',
    service_type_name: 'Airport pickup',
    vehicle_type_code: 'VAN',
    vehicle_type_name: 'Van',
    adults: 2,
    children: 1,
    infants: 0,
    carriers_20_inch: 1,
    carriers_24_inch_plus: 2,
    golf_bags: 1,
    special_items: 'folding stroller',
    name_sign_requested: 1,
    name_sign_text: 'KIM FAMILY',
    is_exact_vehicle_match: 1,
    ...overrides,
  };
}

function createHarness(overrides = {}) {
  const conn = createConn();
  const pool = createPool(conn);
  const calls = {
    assignments: [],
    statusUpdates: [],
    statusLogs: [],
    activityLogs: [],
    deactivatedAssignments: [],
    reopened: [],
    notifications: [],
    conflictLookups: [],
    getDetailCalls: [],
    urgentActiveLookups: [],
    urgentNegotiationsInserted: [],
    urgentNegotiationLinks: [],
  };
  const booking = {
    id: 10,
    booking_number: 'TX202607130001',
    status: BOOKING_STATUS.OPEN,
    vehicle_type_id: 3,
    scheduled_pickup_at: '2099-07-13 10:00:00',
    ...overrides.booking,
  };
  const driver = {
    id: 7,
    user_id: 42,
    name: 'Somchai',
    is_active: 1,
    user_is_active: 1,
    is_online: 1,
    status: 'AVAILABLE',
    ...overrides.driver,
  };
  const bookingRepository = {
    async findOpenDriverCallsForDriver() {
      return overrides.openRows ?? [openCallRow()];
    },
    async findOpenDriverCallByBookingId() {
      return overrides.reopenedOpenRow ?? openCallRow();
    },
    async findByBookingNumberForUpdate() {
      return booking;
    },
    async findActiveAssignmentForUpdate() {
      return overrides.activeAssignment ?? null;
    },
    async hasReleasedAssignment() {
      return overrides.hasReleasedAssignment ?? false;
    },
    async insertDriverAssignment(_conn, row) {
      calls.assignments.push(row);
      return 99;
    },
    async updateStatus(_conn, bookingId, status, actorUserId) {
      calls.statusUpdates.push({ bookingId, status, actorUserId });
    },
    async reopenAfterDriverRelease(_conn, bookingId, actorUserId) {
      calls.reopened.push({ bookingId, actorUserId });
      booking.status = BOOKING_STATUS.OPEN;
    },
    async deactivateAssignment(_conn, assignmentId, reason) {
      calls.deactivatedAssignments.push({ assignmentId, reason });
      return overrides.deactivateAssignmentResult ?? true;
    },
    async insertStatusLog(_conn, bookingId, log) {
      calls.statusLogs.push({ bookingId, log });
    },
    async insertActivityLog(_conn, bookingId, activity) {
      calls.activityLogs.push({ bookingId, activity });
    },
    async updateUrgentNegotiationId(_conn, bookingId, negotiationId) {
      calls.urgentNegotiationLinks.push({ bookingId, negotiationId });
      booking.urgent_negotiation_id = negotiationId;
    },
    async findActiveDriverBookingByNumberForUpdate() {
      return overrides.detailRow ?? {
        booking_number: booking.booking_number,
        status: BOOKING_STATUS.DRIVER_ASSIGNED,
        assignment_status: 'ASSIGNED',
        scheduled_pickup_at: booking.scheduled_pickup_at,
        pickup_date: '2026-07-13',
        pickup_time: '10:00',
        origin_address: 'BKK Airport',
        destination_address: 'Pattaya Hotel',
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport pickup',
        vehicle_type_code: 'VAN',
        vehicle_type_name: 'Van',
        adults: 2,
        children: 0,
        infants: 0,
        payment_method: 'PAY_DRIVER',
        total_amount: 2500,
        currency: 'THB',
      };
    },
  };
  const driverRepository = {
    async findByUserId() {
      return driver;
    },
    async findByUserIdForUpdate() {
      return driver;
    },
    async hasActiveJob() {
      return overrides.hasActiveJob ?? false;
    },
    async findActiveAssignmentPickupsForConflict() {
      calls.conflictLookups.push({ driverId: driver.id });
      return overrides.conflictRows ?? [];
    },
    async findMatchingVehicle() {
      if (overrides.matchingVehicle === false) return null;
      if (overrides.matchingVehicle && typeof overrides.matchingVehicle === 'object') {
        return overrides.matchingVehicle;
      }
      return { id: 55, vehicle_type_id: 3, vehicle_type_code: 'VAN', plate_number: 'VAN-1' };
    },
    async listApprovedActiveVehicles() {
      return overrides.approvedVehicles ?? [
        {
          id: 55,
          vehicle_type_id: 3,
          vehicle_type_code: 'VAN',
          vehicle_type_name: 'Van',
          plate_number: 'VAN-1',
        },
      ];
    },
    async findApprovedVehicleByIdForDriver(_conn, _driverId, vehicleId) {
      if (overrides.ownedVehicleById === null) return null;
      if (overrides.ownedVehicleById) return overrides.ownedVehicleById;
      const vehicles = overrides.approvedVehicles ?? [
        {
          id: 55,
          vehicle_type_id: 3,
          vehicle_type_code: 'VAN',
          vehicle_type_name: 'Van',
          plate_number: 'VAN-1',
        },
      ];
      return vehicles.find((item) => Number(item.id) === Number(vehicleId)) || null;
    },
    async findCompatibleVehicleById(_conn, _driverId, vehicleId) {
      if (overrides.compatibleVehicleById === false) return null;
      if (overrides.compatibleVehicleById) return overrides.compatibleVehicleById;
      const vehicles = overrides.approvedVehicles ?? [
        {
          id: 55,
          vehicle_type_id: 3,
          vehicle_type_code: 'VAN',
          vehicle_type_name: 'Van',
          plate_number: 'VAN-1',
        },
      ];
      return vehicles.find((item) => Number(item.id) === Number(vehicleId)) || null;
    },
    async listEligibleForOpenBooking() {
      return overrides.eligibleDrivers ?? [
        { id: 8, user_id: 43 },
        { id: 9, user_id: 44 },
      ];
    },
  };
  const notificationService = {
    async sendDirectNotification(params) {
      calls.notifications.push(params);
    },
  };
  const notificationServiceResolver = () => notificationService;
  const sharedDriverJobService = new DriverJobService(null);
  const driverJobService = {
    validateBookingNumber(value) {
      return sharedDriverJobService.validateBookingNumber(value);
    },
    metadata(row) {
      return sharedDriverJobService.metadata(row);
    },
    locationDetails(params) {
      return sharedDriverJobService.locationDetails(params);
    },
    serviceDateTimeIso(value) {
      return sharedDriverJobService.serviceDateTimeIso(value);
    },
    async getDetail(userId, bookingNumber) {
      calls.getDetailCalls.push({ userId, bookingNumber });
      return {
        bookingNumber: booking.booking_number,
        status: BOOKING_STATUS.DRIVER_ASSIGNED,
        customerPhone: '+66812345678',
      };
    },
    mapDetail(row) {
      return {
        bookingNumber: row.booking_number ?? booking.booking_number,
        status: row.status ?? BOOKING_STATUS.DRIVER_ASSIGNED,
        pickupDate: row.pickup_date ?? '2026-07-13',
        pickupTime: row.pickup_time ?? '10:00',
        customerPhone: '+66812345678',
      };
    },
    paymentSummary(row) {
      return sharedDriverJobService.paymentSummary(row);
    },
  };
  const commissionSettlementService = {
    async driverHasBlockingSettlement(driverId) {
      if (overrides.blockedDriverIds) {
        return overrides.blockedDriverIds.includes(Number(driverId));
      }
      return overrides.commissionBlocked ?? false;
    },
  };
  const urgentNegotiationRepository = {
    async findActiveNegotiationForBookingForUpdate(_conn, bookingId) {
      calls.urgentActiveLookups.push(bookingId);
      return overrides.activeUrgentNegotiation ?? null;
    },
    async insertNegotiation(_conn, { bookingId }) {
      calls.urgentNegotiationsInserted.push({ bookingId });
      return overrides.newNegotiationId ?? 500;
    },
  };
  const bookingAssignmentReopenService = new BookingAssignmentReopenService(
    bookingRepository,
    driverRepository,
    notificationServiceResolver,
    commissionSettlementService,
    urgentNegotiationRepository,
  );
  return {
    conn,
    calls,
    service: new DriverCallService(
      pool,
      bookingRepository,
      driverRepository,
      driverJobService,
      notificationService,
      commissionSettlementService,
      urgentNegotiationRepository,
      bookingAssignmentReopenService,
    ),
  };
}

test('open call list hides customer personal details before assignment', async () => {
  const { service } = createHarness();
  const result = await service.listOpenCalls(42);

  assert.equal(result.items.length, 1);
  assert.equal(result.items[0].bookingNumber, 'TX202607130001');
  assert.equal(result.items[0].amount, 2500);
  assert.equal(result.items[0].customerPaymentAmount, 2500);
  assert.equal(result.items[0].customerPaymentCurrency, 'THB');
  assert.equal(result.items[0].customerPaymentMethod, 'PAY_DRIVER_AT_DESTINATION');
  assert.equal(result.items[0].companyCommissionAmount, 300);
  assert.equal(result.items[0].companyCommissionCurrency, 'THB');
  assert.equal(result.items[0].driverExpectedIncomeAmount, 2200);
  assert.equal(result.items[0].driverExpectedIncomeCurrency, 'THB');
  assert.equal(result.items[0].nameSignAmount, 0);
  assert.equal(result.items[0].nameSignRequested, true);
  assert.equal(result.items[0].nameSignText, 'KIM FAMILY');
  assert.equal(result.items[0].luggage.golfBags, 1);
  assert.equal(result.items[0].isExactVehicleMatch, true);
  assert.equal(result.items[0].vehicleMatchType, 'EXACT');
  assert.equal(result.items[0].compatibleVehicles.length, 1);
  assert.equal(result.items[0].compatibleVehicles[0].driverVehicleId, 55);
  assert.equal(Object.hasOwn(result.items[0], 'customerPhone'), false);
  assert.equal(Object.hasOwn(result.items[0], 'customerEmail'), false);
  assert.equal(Object.hasOwn(result.items[0], 'specialInstructions'), false);
});

test('open call list subtracts stored NAME_SIGN amount from expected income', async () => {
  const { service } = createHarness({
    openRows: [
      openCallRow({
        total_amount: 1300,
        commission_amount: 200,
        name_sign_amount: 100,
      }),
    ],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(result.items[0].nameSignAmount, 100);
  assert.equal(result.items[0].driverExpectedIncomeAmount, 1000);
});

test('open call list subtracts non-default NAME_SIGN amount from expected income', async () => {
  const { service } = createHarness({
    openRows: [
      openCallRow({
        total_amount: 1350,
        commission_amount: 200,
        name_sign_amount: 150,
      }),
    ],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(result.items[0].nameSignAmount, 150);
  assert.equal(result.items[0].driverExpectedIncomeAmount, 1000);
});

test('open call list includes pickupLocation and destinationLocation from metadata', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({
      origin_address: '999 Nong Prue, Bang Phli District, Samut Prakan 10540',
      destination_address: '333/101 Moo 9, Pattaya Beach Road, Chonburi',
      metadata: JSON.stringify({
        originLocation: { name: 'Suvarnabhumi Airport' },
        destinationLocation: { name: 'Hilton Pattaya' },
      }),
    })],
  });
  const result = await service.listOpenCalls(42);

  assert.deepEqual(result.items[0].pickupLocation, {
    name: 'Suvarnabhumi Airport',
    address: '999 Nong Prue, Bang Phli District, Samut Prakan 10540',
    latitude: null,
    longitude: null,
    placeId: null,
  });
  assert.deepEqual(result.items[0].destinationLocation, {
    name: 'Hilton Pattaya',
    address: '333/101 Moo 9, Pattaya Beach Road, Chonburi',
    latitude: null,
    longitude: null,
    placeId: null,
  });
  assert.equal(
    result.items[0].origin,
    '999 Nong Prue, Bang Phli District, Samut Prakan 10540',
  );
  assert.equal(
    result.items[0].destination,
    '333/101 Moo 9, Pattaya Beach Road, Chonburi',
  );
});

test('open call list includes nameTh in pickup and destination locations', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({
      metadata: JSON.stringify({
        originLocation: {
          name: 'BKK — Suvarnabhumi Airport',
          nameTh: 'ท่าอากาศยานสุวรรณภูมิ',
        },
        destinationLocation: {
          name: 'Hilton Pattaya',
          nameTh: 'โรงแรมฮilton พัทยา',
        },
      }),
    })],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(result.items[0].pickupLocation.nameTh, 'ท่าอากาศยานสุวรรณภูมิ');
  assert.equal(result.items[0].destinationLocation.nameTh, 'โรงแรมฮilton พัทยา');
});

test('open call list omits nameTh when metadata has no Thai place names', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({
      metadata: JSON.stringify({
        originLocation: { name: 'Suvarnabhumi Airport' },
        destinationLocation: { name: 'Hilton Pattaya' },
      }),
    })],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(Object.hasOwn(result.items[0].pickupLocation, 'nameTh'), false);
  assert.equal(Object.hasOwn(result.items[0].destinationLocation, 'nameTh'), false);
});

test('open call list omits duplicate location names when metadata matches address', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({
      origin_address: 'BKK Airport',
      destination_address: 'Pattaya Hotel',
      metadata: JSON.stringify({
        originLocation: { name: 'BKK Airport' },
        destinationLocation: { name: 'Pattaya Hotel' },
      }),
    })],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(result.items[0].pickupLocation.name, null);
  assert.equal(result.items[0].pickupLocation.address, 'BKK Airport');
  assert.equal(result.items[0].destinationLocation.name, null);
  assert.equal(result.items[0].destinationLocation.address, 'Pattaya Hotel');
});

test('open call list returns address-only locations when metadata has no names', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({ metadata: null })],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(result.items[0].pickupLocation.name, null);
  assert.equal(result.items[0].pickupLocation.address, 'BKK Airport');
  assert.equal(result.items[0].destinationLocation.name, null);
  assert.equal(result.items[0].destinationLocation.address, 'Pattaya Hotel');
});

test('mapOpenCall includes createdAt as ISO string from Bangkok wall clock', () => {
  const { service } = createHarness();
  const mapped = service.mapOpenCall(openCallRow({
    created_at: '2026-07-12 15:30:00',
  }));

  assert.equal(mapped.createdAt, '2026-07-12T08:30:00.000Z');
});

test('mapOpenCall returns null createdAt when missing', () => {
  const { service } = createHarness();
  assert.equal(service.mapOpenCall(openCallRow()).createdAt, null);
});

test('buildOpenCallPayload includes structured locations from metadata', () => {
  const service = new BookingService(
    null,
    {},
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  );
  const payload = service.buildOpenCallPayload({
    bookingNumber: 'TX202607130001',
    scheduledPickupAt: '2026-07-13T03:30:00.000Z',
    originAddress: '999 Nong Prue, Bang Phli',
    destinationAddress: 'Pattaya Beach Road',
    metadata: {
      originLocation: { name: 'Suvarnabhumi Airport' },
      destinationLocation: { name: 'Hilton Pattaya' },
    },
    serviceType: { code: 'AIRPORT_PICKUP', name: 'Airport pickup' },
    vehicleType: { code: 'VAN', name: 'Van' },
    pricing: { totalAmount: 2500, currency: 'THB' },
    luggage: {
      carriers20Inch: 0,
      carriers24InchPlus: 0,
      golfBags: 0,
      specialItems: null,
    },
  });

  assert.deepEqual(payload.pickupLocation, {
    name: 'Suvarnabhumi Airport',
    address: '999 Nong Prue, Bang Phli',
    latitude: null,
    longitude: null,
    placeId: null,
  });
  assert.deepEqual(payload.destinationLocation, {
    name: 'Hilton Pattaya',
    address: 'Pattaya Beach Road',
    latitude: null,
    longitude: null,
    placeId: null,
  });
  assert.equal(payload.origin, '999 Nong Prue, Bang Phli');
  assert.equal(payload.destination, 'Pattaya Beach Road');
});

test('buildOpenCallPayload includes nameTh from metadata', () => {
  const service = new BookingService(
    null,
    {},
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  );
  const payload = service.buildOpenCallPayload({
    bookingNumber: 'TX202607130001',
    scheduledPickupAt: '2026-07-13T03:30:00.000Z',
    originAddress: '999 Nong Prue, Bang Phli',
    destinationAddress: 'Pattaya Beach Road',
    metadata: {
      originLocation: {
        name: 'Suvarnabhumi Airport',
        nameTh: 'ท่าอากาศยานสุวรรณภูมิ',
      },
      destinationLocation: {
        name: 'Hilton Pattaya',
        nameTh: 'โรงแรมฮilton พัทยา',
      },
    },
    serviceType: { code: 'AIRPORT_PICKUP', name: 'Airport pickup' },
    vehicleType: { code: 'VAN', name: 'Van' },
    pricing: { totalAmount: 2500, currency: 'THB' },
    luggage: {
      carriers20Inch: 0,
      carriers24InchPlus: 0,
      golfBags: 0,
      specialItems: null,
    },
  });

  assert.equal(payload.pickupLocation.nameTh, 'ท่าอากาศยานสุวรรณภูมิ');
  assert.equal(payload.destinationLocation.nameTh, 'โรงแรมฮilton พัทยา');
});

test('open call list marks hierarchy downgrade calls as COMPATIBLE_UPGRADE', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({
      vehicle_type_code: 'SEDAN',
      vehicle_type_name: 'Sedan',
      is_exact_vehicle_match: 0,
    })],
  });
  const result = await service.listOpenCalls(42);
  assert.equal(result.items[0].vehicleType.code, 'SEDAN');
  assert.equal(result.items[0].isExactVehicleMatch, false);
  assert.equal(result.items[0].vehicleMatchType, 'COMPATIBLE_UPGRADE');
});

test('open call list keeps unsafe expected income nullable', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({ total_amount: 1300, commission_amount: 1500 })],
  });
  const result = await service.listOpenCalls(42);

  assert.equal(result.items[0].customerPaymentAmount, 1300);
  assert.equal(result.items[0].companyCommissionAmount, 1500);
  assert.equal(result.items[0].driverExpectedIncomeAmount, null);
  assert.equal(result.items[0].driverExpectedIncomeCurrency, null);
});

test('open call list hides calls when settlement confirmation is required', async () => {
  const { service } = createHarness({ commissionBlocked: true });

  const result = await service.listOpenCalls(42);

  assert.deepEqual(result, {
    items: [],
    blockedReason: 'UNPAID_SETTLEMENT',
    message: 'ยังไม่สามารถรับงานใหม่ได้ กรุณาชำระค่าคอมมิชชั่นและรอการตรวจสอบจากแอดมิน',
  });
});

test('claimOpenCall atomically creates assignment and moves booking to DRIVER_ASSIGNED', async () => {
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
  const { service, conn, calls } = createHarness();

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(conn.committed, true);
  assert.equal(conn.rolledBack, false);
  assert.equal(calls.assignments.length, 1);
  assert.deepEqual(calls.statusUpdates[0], {
    bookingId: 10,
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    actorUserId: 42,
  });
  assert.equal(calls.statusLogs[0].log.fromStatus, BOOKING_STATUS.OPEN);
  assert.equal(calls.statusLogs[0].log.toStatus, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(emitted.some((row) => row.event === 'driver:call:claimed'), true);
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42) && row.event === 'driver:call:confirmed'),
    true,
  );
  assert.equal(result.bookingNumber, 'TX202607130001');
  assert.equal(result.booking.bookingNumber, 'TX202607130001');
  setRealtimeIo(null);
});

test('claimOpenCall allows pickup times more than 60 minutes apart', async () => {
  const { service, conn, calls } = createHarness({
    conflictRows: [{
      id: 5,
      booking_number: 'TX202607120001',
      scheduled_pickup_at: '2026-07-13 11:01:00',
    }],
    booking: { scheduled_pickup_at: '2026-07-13 10:00:00' },
  });

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(conn.committed, true);
  assert.equal(calls.conflictLookups.length, 1);
});

test('claimOpenCall allows pickup times 90 minutes apart under simplified conflict rule', async () => {
  const { service, conn } = createHarness({
    conflictRows: [{
      id: 5,
      booking_number: 'TX202607120001',
      scheduled_pickup_at: '2026-07-13 11:30:00',
    }],
    booking: { scheduled_pickup_at: '2026-07-13 10:00:00' },
  });

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(conn.committed, true);
});

test('claimOpenCall rejects pickup conflict even when hasActiveJob is false', async () => {
  const { service, calls } = createHarness({
    hasActiveJob: false,
    conflictRows: [{
      id: 5,
      booking_number: 'TX202607120001',
      scheduled_pickup_at: '2026-07-13 11:00:00',
    }],
    booking: { scheduled_pickup_at: '2026-07-13 10:00:00' },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
  );
  assert.equal(calls.conflictLookups.length, 1);
});

test('claimOpenCall returns booking detail mapped inside transaction', async () => {
  const { service, calls } = createHarness({
    detailRow: {
      booking_number: 'TX202607130001',
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      assignment_status: 'ASSIGNED',
      pickup_date: '2026-07-13',
      pickup_time: '10:30',
    },
  });

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.booking.pickupTime, '10:30');
  assert.equal(result.booking.bookingNumber, 'TX202607130001');
  assert.deepEqual(calls.getDetailCalls, []);
});

test('claimOpenCall returns 409 when another driver already claimed booking', async () => {
  const { service, conn } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.ALREADY_ASSIGNED,
  );
  assert.equal(conn.rolledBack, true);
});

test('claimOpenCall rejects offline or busy drivers', async () => {
  const offline = createHarness({ driver: { is_online: 0, status: 'OFFLINE' } });
  await assert.rejects(
    () => offline.service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_AVAILABLE,
  );

  const busy = createHarness({
    conflictRows: [{
      id: 5,
      booking_number: 'TX202607120001',
      scheduled_pickup_at: '2099-07-13 11:00:00',
    }],
  });
  await assert.rejects(
    () => busy.service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_BOOKING_TIME_CONFLICT,
  );
});

test('claimOpenCall rejects settlement-blocked drivers', async () => {
  const { service, conn } = createHarness({ commissionBlocked: true });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
  assert.equal(conn.rolledBack, true);
});

test('claimOpenCall rejects vehicle type mismatch', async () => {
  const { service } = createHarness({ matchingVehicle: false });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('claimOpenCall assigns compatible hierarchy vehicle returned by findMatchingVehicle', async () => {
  const { service, conn, calls } = createHarness({
    booking: { vehicle_type_id: 1 },
    matchingVehicle: {
      id: 88,
      vehicle_type_id: 4,
      vehicle_type_code: 'VAN',
      plate_number: 'VAN-1',
    },
  });

  const result = await service.claimOpenCall(42, 'TX202607130001');
  assert.equal(result.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(conn.committed, true);
  assert.equal(calls.assignments[0].driverVehicleId, 88);
});

test('claimOpenCall uses explicit driverVehicleId when compatible (VAN on SEDAN call)', async () => {
  const { service, calls } = createHarness({
    booking: { vehicle_type_id: 1 },
    compatibleVehicleById: {
      id: 88,
      vehicle_type_id: 4,
      vehicle_type_code: 'VAN',
      plate_number: 'VAN-88',
    },
  });

  await service.claimOpenCall(42, 'TX202607130001', { driverVehicleId: 88 });
  assert.equal(calls.assignments[0].driverVehicleId, 88);
  assert.equal(calls.activityLogs[0].activity.payload.vehicleSelectedByDriver, true);
});

test('claimOpenCall rejects another driver vehicle id', async () => {
  const { service } = createHarness({
    compatibleVehicleById: false,
    ownedVehicleById: null,
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001', { driverVehicleId: 999 }),
    (err) => err.statusCode === 404
      && err.errorCode === ERROR_CODES.DRIVER_VEHICLE_NOT_FOUND,
  );
});

test('claimOpenCall rejects incompatible SEDAN vehicle on SUV booking', async () => {
  const { service } = createHarness({
    booking: { vehicle_type_id: 2 },
    compatibleVehicleById: false,
    ownedVehicleById: {
      id: 11,
      vehicle_type_id: 1,
      vehicle_type_code: 'SEDAN',
      plate_number: 'SED-1',
    },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001', { driverVehicleId: 11 }),
    (err) => err.statusCode === 409
      && err.errorCode === ERROR_CODES.DRIVER_NOT_ELIGIBLE,
  );
});

test('open call list includes multiple compatibleVehicles for multi-vehicle drivers', async () => {
  const { service } = createHarness({
    openRows: [openCallRow({
      vehicle_type_code: 'SEDAN',
      vehicle_type_name: 'Sedan',
      is_exact_vehicle_match: 0,
    })],
    approvedVehicles: [
      {
        id: 11,
        vehicle_type_code: 'SEDAN',
        vehicle_type_name: 'Sedan',
        plate_number: 'S-1',
      },
      {
        id: 22,
        vehicle_type_code: 'VAN',
        vehicle_type_name: 'Van',
        plate_number: 'V-1',
      },
    ],
  });
  const result = await service.listOpenCalls(42);
  assert.equal(result.items[0].compatibleVehicles.length, 2);
  assert.deepEqual(
    result.items[0].compatibleVehicles.map((item) => item.driverVehicleId),
    [11, 22],
  );
});

test('releaseAssignment reopens booking, clears active assignment, and notifies other drivers', async () => {
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
  const { service, conn, calls } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });

  const result = await service.releaseAssignment(42, 'TX202607130001', {
    reasonCode: 'SCHEDULE_CONFLICT',
  });

  assert.equal(result.status, BOOKING_STATUS.OPEN);
  assert.equal(result.released, true);
  assert.equal(result.reassignmentPriority, 'NORMAL');
  assert.equal(result.reasonCode, 'SCHEDULE_CONFLICT');
  assert.equal(conn.committed, true);
  assert.equal(conn.rolledBack, false);
  assert.deepEqual(calls.deactivatedAssignments[0], {
    assignmentId: 77,
    reason: 'DRIVER_RELEASED_ASSIGNMENT',
  });
  assert.deepEqual(calls.reopened[0], { bookingId: 10, actorUserId: 42 });
  assert.equal(calls.statusLogs[0].log.fromStatus, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(calls.statusLogs[0].log.toStatus, BOOKING_STATUS.OPEN);
  assert.equal(calls.statusLogs[0].log.reason, 'DRIVER_RELEASED_ASSIGNMENT');
  assert.equal(calls.notifications.length, 2);
  assert.equal(calls.notifications[0].notificationType, NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE);
  assert.equal(Object.hasOwn(calls.notifications[0].payload, 'customerPhone'), false);
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42) && row.event === 'driver:assignment:released'),
    true,
  );
  const releaseEvent = emitted.find(
    (row) => row.room === driverUserRoom(42) && row.event === 'driver:assignment:released',
  );
  assert.equal(releaseEvent.payload.reasonCode, 'DRIVER_RELEASED');
  assert.equal(
    emitted.filter((row) => row.event === 'driver:call:new').length,
    2,
  );
  setRealtimeIo(null);
});

test('releaseAssignment excludes settlement-blocked drivers from reopened call notifications', async () => {
  const { service, calls } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
    eligibleDrivers: [
      { id: 8, user_id: 43 },
      { id: 9, user_id: 44 },
    ],
    blockedDriverIds: [9],
  });

  const result = await service.releaseAssignment(42, 'TX202607130001', {
    reasonCode: 'DRIVER_ILLNESS',
  });

  assert.equal(result.released, true);
  assert.equal(calls.notifications.length, 1);
  assert.equal(calls.notifications[0].recipientDriverId, 8);
});

test('releaseAssignment rejects wrong driver and started trip', async () => {
  const wrongDriver = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 99, status: 'ASSIGNED', is_active: 1 },
  });
  await assert.rejects(
    () => wrongDriver.service.releaseAssignment(42, 'TX202607130001', {
      reasonCode: 'SCHEDULE_CONFLICT',
    }),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.BOOKING_NOT_ASSIGNED_TO_DRIVER,
  );
  assert.equal(wrongDriver.conn.rolledBack, true);

  const started = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ARRIVED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });
  await assert.rejects(
    () => started.service.releaseAssignment(42, 'TX202607130001', {
      reasonCode: 'ACCIDENT',
    }),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.BOOKING_RELEASE_NOT_ALLOWED,
  );
});

test('releaseAssignment keeps existing compatibility for ACCEPTED assignment', async () => {
  const { service, conn, calls } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ACCEPTED', is_active: 1 },
  });

  const result = await service.releaseAssignment(42, 'TX202607130001', {
    reasonCode: 'SCHEDULE_CONFLICT',
  });

  assert.equal(result.released, true);
  assert.equal(conn.committed, true);
  assert.equal(calls.deactivatedAssignments.length, 1);
});

test('releaseAssignment duplicate request returns conflict without reopening again', async () => {
  const { service, conn, calls } = createHarness({
    booking: { status: BOOKING_STATUS.OPEN },
    activeAssignment: null,
    hasReleasedAssignment: true,
  });

  await assert.rejects(
    () => service.releaseAssignment(42, 'TX202607130001', {
      reasonCode: 'SCHEDULE_CONFLICT',
    }),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.ASSIGNMENT_ALREADY_RELEASED,
  );
  assert.equal(conn.rolledBack, true);
  assert.equal(calls.reopened.length, 0);
  assert.equal(calls.notifications.length, 0);
});

test('releaseAssignment rolls back and emits no events when reopening fails', async () => {
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
  const { service, conn } = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });
  service.bookingRepository.reopenAfterDriverRelease = async () => {
    throw new Error('update failed');
  };

  await assert.rejects(
    () => service.releaseAssignment(42, 'TX202607130001', {
      reasonCode: 'SCHEDULE_CONFLICT',
    }),
    /update failed/,
  );
  assert.equal(conn.rolledBack, true);
  assert.equal(conn.committed, false);
  assert.equal(emitted.length, 0);
  setRealtimeIo(null);
});

test('releaseAssignment blocks normal reason within 2h but allows emergency CRITICAL', async () => {
  const pickup = '2026-07-25 15:00:00';
  const nowMs = Date.parse('2026-07-25T14:00:00+07:00');
  const blocked = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED, scheduled_pickup_at: pickup },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });
  await assert.rejects(
    () => blocked.service.releaseAssignment(
      42,
      'TX202607130001',
      { reasonCode: 'SCHEDULE_CONFLICT' },
      { nowMs },
    ),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.BOOKING_RELEASE_NOT_ALLOWED,
  );

  const allowed = createHarness({
    booking: { status: BOOKING_STATUS.DRIVER_ASSIGNED, scheduled_pickup_at: pickup },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });
  const result = await allowed.service.releaseAssignment(
    42,
    'TX202607130001',
    { reasonCode: 'VEHICLE_BREAKDOWN', reasonDetail: 'Engine light' },
    { nowMs },
  );
  assert.equal(result.released, true);
  assert.equal(result.reassignmentPriority, 'CRITICAL');
  assert.equal(allowed.calls.activityLogs[0].activity.payload.emergency, true);
});

test('claimOpenCall rejects a booking previously released by the same driver', async () => {
  const { service } = createHarness({ hasReleasedAssignment: true });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === 409 && err.errorCode === ERROR_CODES.ASSIGNMENT_ALREADY_RELEASED,
  );
});

test('claimOpenCall rejects urgent booking with active negotiation in BROADCASTING', async () => {
  const { service, calls } = createHarness({
    booking: { is_urgent_request: 1, status: BOOKING_STATUS.OPEN },
    activeUrgentNegotiation: { id: 100, status: 'BROADCASTING' },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.statusCode === HTTP_STATUS.CONFLICT
      && err.errorCode === ERROR_CODES.URGENT_NEGOTIATION_ACTIVE,
  );
  assert.equal(calls.assignments.length, 0);
  assert.deepEqual(calls.urgentActiveLookups, [10]);
});

test('claimOpenCall rejects urgent booking with active negotiation in LOCKED', async () => {
  const { service } = createHarness({
    booking: { is_urgent_request: 1, status: BOOKING_STATUS.OPEN },
    activeUrgentNegotiation: { id: 100, status: 'LOCKED' },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.errorCode === ERROR_CODES.URGENT_NEGOTIATION_ACTIVE,
  );
});

test('claimOpenCall rejects urgent booking with active negotiation in AWAITING_CUSTOMER', async () => {
  const { service } = createHarness({
    booking: { is_urgent_request: 1, status: BOOKING_STATUS.OPEN },
    activeUrgentNegotiation: { id: 100, status: 'AWAITING_CUSTOMER' },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.errorCode === ERROR_CODES.URGENT_NEGOTIATION_ACTIVE,
  );
});

test('claimOpenCall on confirmed urgent booking is blocked by OPEN status check before urgent gate', async () => {
  const { service, calls } = createHarness({
    booking: {
      is_urgent_request: 1,
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
    },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.errorCode === ERROR_CODES.ALREADY_ASSIGNED,
  );
  assert.equal(calls.urgentActiveLookups.length, 0);
});

test('claimOpenCall on cancelled urgent booking is blocked by OPEN status check', async () => {
  const { service, calls } = createHarness({
    booking: {
      is_urgent_request: 1,
      status: BOOKING_STATUS.CANCELLED,
    },
  });

  await assert.rejects(
    () => service.claimOpenCall(42, 'TX202607130001'),
    (err) => err.errorCode === ERROR_CODES.ALREADY_ASSIGNED,
  );
  assert.equal(calls.urgentActiveLookups.length, 0);
});

test('claimOpenCall still works for non-urgent open bookings', async () => {
  setRealtimeIo({ to() { return { emit() {} }; } });
  const { service, conn, calls } = createHarness({
    booking: { is_urgent_request: 0, status: BOOKING_STATUS.OPEN },
  });

  const result = await service.claimOpenCall(42, 'TX202607130001');

  assert.equal(result.status, BOOKING_STATUS.DRIVER_ASSIGNED);
  assert.equal(conn.committed, true);
  assert.equal(calls.assignments.length, 1);
  assert.equal(calls.urgentActiveLookups.length, 0);
  setRealtimeIo(null);
});

test('releaseAssignment on urgent booking restarts negotiation and emits driver:urgent-call:new', async () => {
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
  const { service, conn, calls } = createHarness({
    booking: {
      status: BOOKING_STATUS.DRIVER_ASSIGNED,
      is_urgent_request: 1,
      urgent_negotiation_id: 100,
    },
    activeAssignment: { id: 77, driver_id: 7, status: 'ASSIGNED', is_active: 1 },
    newNegotiationId: 501,
  });

  const result = await service.releaseAssignment(42, 'TX202607130001', {
    reasonCode: 'SCHEDULE_CONFLICT',
  });

  assert.equal(result.released, true);
  assert.equal(conn.committed, true);
  assert.deepEqual(calls.urgentNegotiationsInserted, [{ bookingId: 10 }]);
  assert.deepEqual(calls.urgentNegotiationLinks, [{ bookingId: 10, negotiationId: 501 }]);
  assert.equal(calls.notifications.length, 2);
  assert.equal(calls.notifications[0].notificationType, NOTIFICATION_TYPES.DRIVER_URGENT_CALL_NEW);
  assert.equal(
    emitted.some((row) => row.room === DRIVER_ALL_ROOM && row.event === 'driver:urgent-call:new'),
    true,
  );
  assert.equal(
    emitted.some((row) => row.event === 'driver:call:new'),
    false,
  );
  assert.equal(
    emitted.some((row) => row.room === driverUserRoom(42) && row.event === 'driver:assignment:released'),
    true,
  );
  setRealtimeIo(null);
});

test('booking creation helper returns eligible driver targets', async () => {
  const service = new BookingService(
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    {
      async listEligibleForOpenBooking() {
        return [
          { id: 7, user_id: 42 },
          { id: 8, user_id: 43 },
        ];
      },
    },
    null,
  );

  const targets = await service.notifyEligibleDriversForOpenBooking({}, {
    vehicleTypeId: 3,
  });

  assert.deepEqual(targets, [
    { driverId: 7, userId: 42 },
    { driverId: 8, userId: 43 },
  ]);
});

test('dispatchOpenCallNotifications sends DRIVER_CALL_AVAILABLE to each eligible driver', async () => {
  const sent = [];
  const service = new BookingService(
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    () => ({
      async sendDirectNotification(params) {
        sent.push(params);
      },
    }),
  );

  await service.dispatchOpenCallNotifications({
    drivers: [
      { id: 7, user_id: 42 },
      { id: 8, user_id: 43 },
    ],
    bookingId: 10,
    bookingNumber: 'TX202607130001',
    openCallPayload: {
      bookingNumber: 'TX202607130001',
      origin: 'BKK',
      destination: 'Pattaya',
    },
  });

  assert.equal(sent.length, 2);
  assert.equal(sent[0].notificationType, NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE);
  assert.equal(sent[0].recipientDriverId, 7);
  assert.equal(sent[0].payload.targetScreen, 'open_calls');
});

test('booking creation helper excludes settlement-blocked drivers from open call targets', async () => {
  const service = new BookingService(
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    {
      async listEligibleForOpenBooking() {
        return [
          { id: 7, user_id: 42 },
          { id: 8, user_id: 43 },
        ];
      },
    },
    null,
    {
      async driverHasBlockingSettlement(driverId) {
        return Number(driverId) === 8;
      },
    },
  );

  const targets = await service.notifyEligibleDriversForOpenBooking({}, {
    vehicleTypeId: 3,
  });

  assert.deepEqual(targets, [{ driverId: 7, userId: 42 }]);
});

test('dispatchOpenCallNotifications continues when one driver notification fails', async () => {
  const sent = [];
  const service = new BookingService(
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    () => ({
      async sendDirectNotification(params) {
        if (params.recipientUserId === 43) {
          throw new Error('fcm failed');
        }
        sent.push(params);
      },
    }),
  );

  await service.dispatchOpenCallNotifications({
    drivers: [
      { id: 7, user_id: 42 },
      { id: 8, user_id: 43 },
    ],
    bookingId: 10,
    bookingNumber: 'TX202607130001',
    openCallPayload: { bookingNumber: 'TX202607130001' },
  });

  assert.equal(sent.length, 1);
  assert.equal(sent[0].recipientUserId, 42);
});

test('driver call socket handler joins driver rooms and rejects non-drivers', async () => {
  const handlers = {};
  const joinedRooms = new Set();
  const emitted = [];
  const socket = {
    data: { authUser: { id: 42, role: 'DRIVER' } },
    on(event, handler) { handlers[event] = handler; },
    async join(room) { joinedRooms.add(room); },
    emit(event, payload) { emitted.push({ event, payload }); },
  };
  registerDriverCallHandlers({}, socket);
  await handlers['driver:calls:subscribe']({}, () => {});
  assert.equal(joinedRooms.has(DRIVER_ALL_ROOM), true);
  assert.equal(joinedRooms.has(driverUserRoom(42)), true);

  const customerHandlers = {};
  const customerSocket = {
    data: { authUser: { id: 9, role: 'CUSTOMER' } },
    on(event, handler) { customerHandlers[event] = handler; },
    async join() {},
    emit(event, payload) { emitted.push({ event, payload }); },
  };
  registerDriverCallHandlers({}, customerSocket);
  let ack;
  await customerHandlers['driver:calls:subscribe']({}, (value) => { ack = value; });
  assert.equal(ack.ok, false);
  assert.equal(ack.error.code, ERROR_CODES.FORBIDDEN);
});
