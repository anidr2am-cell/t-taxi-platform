const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = process.env.SOCIAL_TOKEN_ENCRYPTION_KEY
  || Buffer.alloc(32, 1).toString('base64');

const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { EVENTS } = require('../src/events');
const { driverUserRoom, setRealtimeIo } = require('../src/socket/realtime');

const ADMIN = { id: 1, role: 'ADMIN' };

function createHarness({ customerUserId = null, customerChargeAmount = null } = {}) {
  const calls = {
    booking: null,
    chargeItems: [],
    luggage: null,
    luggageUpdates: 0,
    passengerUpdates: 0,
    transferUpdates: 0,
    transferInserts: 0,
    lastUpdateFields: null,
    payoutUpserts: 0,
    transferUpsertPayload: null,
    metadataSnapshot: {
      originLocation: { name: 'Suvarnabhumi', nameTh: 'ท่าอากาศยานสุวรรณภูมิ' },
      destinationLocation: { name: 'Pattaya', nameTh: 'พัทยา' },
    },
    notifications: [],
    notes: [],
    socket: [],
    outbox: [],
    dispatchedOutboxIds: [],
    commits: 0,
    rollbacks: 0,
  };
  const conn = {
    async beginTransaction() {},
    async commit() { calls.commits += 1; },
    async rollback() { calls.rollbacks += 1; },
    release() {},
  };
  const bookingRepository = {
    async insertBooking(_conn, row) {
      calls.booking = row;
      return 10;
    },
    async insertPassengers() {},
    async insertLuggage(_conn, _bookingId, luggage) {
      calls.luggage = luggage;
    },
    async updateLuggage(_conn, _bookingId, luggage) {
      calls.luggageUpdates += 1;
      calls.luggage = luggage;
    },
    async insertTransferDetails() {
      calls.transferInserts += 1;
    },
    async upsertTransferDetails(_conn, _bookingId, payload) {
      calls.transferUpdates += 1;
      calls.transferUpsertPayload = payload;
    },
    async findAdminManualBookingFieldsForUpdate() {
      return {
        origin_address: 'Origin',
        origin_place_id: 'p1',
        origin_lat: 13.7,
        origin_lng: 100.5,
        destination_address: 'Dest',
        destination_place_id: 'p2',
        destination_lat: 12.9,
        destination_lng: 100.8,
        scheduled_pickup_at: '2026-12-01 09:30:00',
        vehicle_type_id: 1,
        service_type_id: 2,
        prefer_female_driver: 1,
        special_requests: 'original memo',
        name_sign_text: null,
        customer_user_id: 55,
        customer_name: 'Member Kim',
        customer_email: 'kim@example.com',
        customer_phone: '0811111111',
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        vehicle_type_code: 'SEDAN',
        service_type_code: 'CITY_TRANSFER',
      };
    },
    async findPassengersByBookingId() {
      return { adults: 2, children: 1, infants: 0 };
    },
    async findLuggageByBookingId() {
      return {
        carriers_20_inch: 1,
        carriers_24_inch_plus: 2,
        golf_bags: 0,
        special_items: 'wheelchair',
      };
    },
    async findTransferByBookingId() {
      return {
        flight_number: 'TG123',
        airport_iata: 'BKK',
        golf_course_id: 42,
        golf_region: 'East',
        driver_included: 1,
        flight_estimated_arrival_at: '2026-12-01 11:00:00',
      };
    },
    async insertChargeItem(_conn, _bookingId, item) {
      calls.chargeItems.push(item);
    },
    async insertStatusLog() {},
    async insertActivityLog() {},
    async findById() {
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: BOOKING_STATUS.OPEN,
        payment_status: calls.booking?.paymentMethod === 'ADMIN_COLLECTED' ? 'PAID' : 'UNPAID',
        total_amount: calls.chargeItems[0]?.amount ?? 0,
        currency: 'THB',
      };
    },
    async findByBookingNumberForUpdate(_conn, bookingNumber) {
      return {
        id: 10,
        booking_number: bookingNumber,
        status: BOOKING_STATUS.OPEN,
        booking_source: 'ADMIN_MANUAL',
      };
    },
    async findBookingMetadataForUpdate() {
      return calls.metadataSnapshot;
    },
    async findManualPayoutAmountByBookingId() {
      return 800;
    },
    async findAirportByIata(_conn, iata) {
      if (iata === 'BKK') {
        return { id: 1, iata_code: 'BKK' };
      }
      return null;
    },
    async updateAdminManualBookingFields(_conn, _id, fields) {
      calls.lastUpdateFields = fields;
    },
    async updatePassengers() {
      calls.passengerUpdates += 1;
    },
    async upsertManualPayoutChargeItem(_conn, _bookingId, item) {
      calls.payoutUpserts += 1;
      calls.chargeItems = [item];
    },
    async syncAdminManualNameSignChargeItem(_conn, _bookingId, enabled) {
      if (enabled) {
        calls.chargeItems.push({
          chargeType: 'NAME_SIGN',
          amount: 0,
        });
      }
    },
  };
  const couponRepository = {
    async findCustomerById(id) {
      if (id !== 55) return null;
      return {
        id: 55,
        role: 'CUSTOMER',
        name: 'Member Kim',
        phone: '0811111111',
        email: 'kim@example.com',
      };
    },
  };
  const noteService = {
    async create(bookingNumber, payload, adminUser) {
      calls.notes.push({ bookingNumber, payload, adminUser });
    },
  };
  const containerPath = require.resolve('../src/helpers/container');
  const originalContainer = require(containerPath);
  require.cache[containerPath].exports = {
    ...originalContainer,
    get(name) {
      if (name === 'adminBookingNoteService') return noteService;
      return originalContainer.get(name);
    },
  };

  const service = new BookingService(
    { async getConnection() { return conn; } },
    bookingRepository,
    { async generateNext() { return 'TX202607130001'; } },
    {
      async resolveServiceType() {
        return { id: 2, code: 'CITY_TRANSFER', name: 'City transfer' };
      },
    },
    { async recommend() { return { recommendedVehicle: 'SEDAN' }; } },
    { async findTypeByCode() { return { id: 1, code: 'SEDAN', name: 'Sedan' }; } },
    {
      async insertNotificationEvent(_conn, event) {
        calls.outbox.push(event);
        return 30;
      },
    },
    {
      async dispatchOutboxIds(ids) {
        calls.dispatchedOutboxIds.push(ids);
      },
    },
    null,
    {
      async listEligibleForOpenBooking() {
        return [{ id: 7, user_id: 42 }];
      },
    },
    () => ({
      async sendDirectNotification(notification) {
        calls.notifications.push(notification);
      },
    }),
    null,
    null,
    null,
    null,
    { couponRepository },
  );

  setRealtimeIo({
    to(room) {
      return {
        emit(event, payload) {
          calls.socket.push({ room, event, payload });
        },
      };
    },
  });

  const input = {
    origin: { address: 'Suvarnabhumi Airport' },
    destination: { address: 'Pattaya Beach' },
    scheduledPickupAt: '2026-12-01T02:30:00.000Z',
    vehicleTypeCode: 'SEDAN',
    payoutAmount: 800,
    paymentCollection: customerUserId ? 'DRIVER_COLLECTS' : 'ADMIN_COLLECTED',
    customer: customerUserId
      ? { customerUserId, name: 'Ignored', phone: '000' }
      : { name: 'Guest Lee', phone: '0822222222' },
    customerChargeAmount,
  };

  return {
    service,
    calls,
    input,
    restoreContainer() {
      require.cache[containerPath].exports = originalContainer;
    },
  };
}

test('createAdminManualBooking links member, marks commission exempt, and broadcasts open call', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    const result = await service.createAdminManualBooking(input, ADMIN);

    assert.equal(calls.booking.bookingSource, 'ADMIN_MANUAL');
    assert.equal(calls.booking.commissionExempt, true);
    assert.equal(calls.booking.customerUserId, 55);
    assert.equal(calls.booking.customerName, 'Member Kim');
    assert.equal(calls.booking.contactStatus, 'VERIFIED');
    assert.equal(calls.booking.paymentMethod, 'PAY_DRIVER');
    assert.equal(calls.chargeItems[0].amount, 800);
    assert.equal(result.bookingNumber, 'TX202607130001');
    assert.equal(calls.commits, 1);
    assert.equal(calls.notifications.length, 1);
    assert.equal(
      calls.notifications[0].notificationType,
      NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
    );
    assert.equal(calls.socket[0].payload.isAdminManualCall, true);
    assert.equal(calls.socket[0].payload.requiresBankAccountConfirmation, false);
    assert.equal(calls.notes.length, 0);
    assert.equal(calls.outbox.length, 1);
    assert.equal(calls.outbox[0].eventType, EVENTS.BOOKING_CREATED);
    assert.equal(calls.outbox[0].payload.customerUserId, 55);
    assert.deepEqual(calls.dispatchedOutboxIds, [[30]]);
  } finally {
    setRealtimeIo(null);
    restoreContainer();
  }
});

test('createAdminManualBooking marks name sign for drivers when picket enabled', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.createAdminManualBooking(
      {
        ...input,
        nameSign: true,
        nameSignText: 'KIM MINSU',
      },
      ADMIN,
    );

    assert.equal(calls.booking.nameSignText, 'KIM MINSU');
    assert.equal(
      calls.chargeItems.some((item) => item.chargeType === 'NAME_SIGN'),
      true,
    );
    assert.equal(calls.socket[0].payload.nameSignRequested, true);
    assert.equal(calls.socket[0].payload.nameSignText, 'KIM MINSU');
  } finally {
    setRealtimeIo(null);
    restoreContainer();
  }
});

test('updateAdminManualBooking updates payout for admin manual open call', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    const result = await service.updateAdminManualBooking(
      'TX202607130001',
      { ...input, payoutAmount: 950 },
      ADMIN,
    );

    assert.equal(result.bookingNumber, 'TX202607130001');
    assert.equal(calls.chargeItems[0].amount, 950);
    assert.equal(calls.commits, 1);
  } finally {
    restoreContainer();
  }
});

test('createAdminManualBooking persists luggage from request body', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.createAdminManualBooking(
      {
        ...input,
        luggage: {
          carriers20Inch: 1,
          carriers24InchPlus: 2,
          golfBags: 0,
          specialLuggageCount: 1,
        },
      },
      ADMIN,
    );

    assert.deepEqual(calls.luggage, {
      carriers20Inch: 1,
      carriers24InchPlus: 2,
      golfBags: 0,
      specialItems: '1',
    });
  } finally {
    setRealtimeIo(null);
    restoreContainer();
  }
});

test('updateAdminManualBooking memo-only keeps luggage passengers payout and payment', async () => {
  const { service, calls, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.updateAdminManualBooking(
      'TX202607130001',
      { memo: 'memo only' },
      ADMIN,
    );

    assert.equal(calls.luggageUpdates, 0);
    assert.equal(calls.passengerUpdates, 0);
    assert.equal(calls.payoutUpserts, 0);
    assert.equal(calls.transferUpdates, 0);
    assert.equal(calls.lastUpdateFields.preferFemaleDriver, true);
    assert.equal(calls.lastUpdateFields.specialRequests, 'memo only');
    assert.equal(calls.lastUpdateFields.paymentMethod, 'PAY_DRIVER');
    assert.equal(calls.lastUpdateFields.paymentStatus, 'UNPAID');
    assert.deepEqual(
      calls.lastUpdateFields.metadata.originLocation.name,
      'Suvarnabhumi',
    );
    assert.deepEqual(
      calls.lastUpdateFields.metadata.originLocation.nameTh,
      'ท่าอากาศยานสุวรรณภูมิ',
    );
  } finally {
    restoreContainer();
  }
});

test('adminManualBookingUpdateSchema accepts memo-only body without payoutAmount', async () => {
  const { adminManualBookingUpdateSchema } = require('../src/validators/admin.validator');
  const { error, value } = adminManualBookingUpdateSchema.validate({ memo: 'notes only' });
  assert.equal(error, undefined);
  assert.equal(value.memo, 'notes only');
  assert.equal(value.payoutAmount, undefined);
});

test('updateAdminManualBooking can explicitly clear preferFemaleDriver', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.updateAdminManualBooking(
      'TX202607130001',
      { payoutAmount: 900, preferFemaleDriver: false },
      ADMIN,
    );
    assert.equal(calls.lastUpdateFields.preferFemaleDriver, false);
  } finally {
    restoreContainer();
  }
});

test('updateAdminManualBooking preserves specialItems text when luggage omitted', async () => {
  const { service, calls, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.updateAdminManualBooking(
      'TX202607130001',
      { memo: 'touch memo only' },
      ADMIN,
    );
    assert.equal(calls.luggageUpdates, 0);
  } finally {
    restoreContainer();
  }
});

test('updateAdminManualBooking customer phone-only keeps member name email and link', async () => {
  const { service, calls, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.updateAdminManualBooking(
      'TX202607130001',
      { customer: { phone: '0899999999' } },
      ADMIN,
    );
    assert.equal(calls.lastUpdateFields.customerUserId, 55);
    assert.equal(calls.lastUpdateFields.customerName, 'Member Kim');
    assert.equal(calls.lastUpdateFields.customerEmail, 'kim@example.com');
    assert.equal(calls.lastUpdateFields.customerPhone, '0899999999');
  } finally {
    restoreContainer();
  }
});

test('updateAdminManualBooking flight-only update preserves golf transfer fields', async () => {
  const { service, calls, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.updateAdminManualBooking(
      'TX202607130001',
      { transfer: { flightNumber: 'TG456' } },
      ADMIN,
    );
    assert.equal(calls.transferUpsertPayload.flightNumber, 'TG456');
    assert.equal(calls.transferUpsertPayload.golfCourseId, 42);
    assert.equal(calls.transferUpsertPayload.golfRegion, 'East');
    assert.equal(calls.transferUpsertPayload.driverIncluded, true);
  } finally {
    restoreContainer();
  }
});

test('updateAdminManualBooking explicit flight clear wipes flight number on upsert', async () => {
  const { service, calls, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.updateAdminManualBooking(
      'TX202607130001',
      { transfer: { flightNumber: '' } },
      ADMIN,
    );
    assert.equal(calls.transferUpsertPayload.flightNumber, null);
    assert.equal(calls.transferUpsertPayload.updateFlightArrivalTimes, true);
    assert.equal(calls.transferUpsertPayload.flightEstimatedArrivalAt, null);
  } finally {
    restoreContainer();
  }
});

test('updateAdminManualBooking updates luggage counts', async () => {
  const { service, calls, input, restoreContainer } = createHarness({ customerUserId: 55 });
  try {
    await service.updateAdminManualBooking(
      'TX202607130001',
      {
        ...input,
        luggage: {
          carriers20Inch: 3,
          carriers24InchPlus: 0,
          golfBags: 1,
          specialLuggageCount: 0,
        },
      },
      ADMIN,
    );

    assert.deepEqual(calls.luggage, {
      carriers20Inch: 3,
      carriers24InchPlus: 0,
      golfBags: 1,
      specialItems: null,
    });
  } finally {
    restoreContainer();
  }
});

test('createAdminManualBooking creates guest booking and auto note when customer charge provided', async () => {
  const { service, calls, input, restoreContainer } = createHarness({
    customerChargeAmount: 1000,
  });
  try {
    await service.createAdminManualBooking(input, ADMIN);

    assert.equal(calls.booking.customerUserId, null);
    assert.equal(calls.booking.customerName, 'Guest Lee');
    assert.equal(calls.booking.paymentMethod, 'ADMIN_COLLECTED');
    assert.equal(calls.socket[0].payload.requiresBankAccountConfirmation, true);
    assert.equal(calls.notes.length, 1);
    assert.match(calls.notes[0].payload.text, /고객 결제 1000 THB/);
    assert.match(calls.notes[0].payload.text, /기사 지급 800 THB/);
    assert.equal(calls.outbox.length, 1);
    assert.equal(calls.outbox[0].eventType, EVENTS.BOOKING_CREATED);
    assert.equal(calls.outbox[0].payload.customerUserId, null);
    assert.deepEqual(calls.dispatchedOutboxIds, [[30]]);
  } finally {
    setRealtimeIo(null);
    restoreContainer();
  }
});
