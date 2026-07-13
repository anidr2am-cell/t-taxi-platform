const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const NOTIFICATION_TYPES = require('../src/constants/notificationTypes');
const { EVENTS } = require('../src/events');
const { driverUserRoom, setRealtimeIo } = require('../src/socket/realtime');

const PRICE = {
  routeId: 7,
  currency: 'THB',
  totalAmount: 1200,
  chargeItems: [
    {
      chargeType: 'VEHICLE_BASE',
      description: 'Base fare',
      quantity: 1,
      unitPrice: 1000,
      amount: 1000,
    },
    {
      chargeType: 'OPTION',
      description: 'Option',
      quantity: 1,
      unitPrice: 200,
      amount: 200,
    },
  ],
};

const BOOKING_INPUT = {
  serviceTypeCode: 'AIRPORT_PICKUP',
  vehicleTypeCode: 'VAN',
  scheduledPickupAt: '2026-07-14T03:00:00.000Z',
  origin: { name: 'BKK Airport', placeId: 'origin-place' },
  destination: { name: 'Pattaya Hotel', placeId: 'destination-place' },
  passengers: { adults: 2, children: 0, infants: 0 },
  luggage: { carriers20Inch: 1, carriers24InchPlus: 0, golfBags: 0 },
  customer: { name: 'Test Customer', phone: '0800000000' },
};

function createHarness({ failSecondChargeItem = false } = {}) {
  const calls = {
    booking: null,
    chargeItems: [],
    notifications: [],
    outbox: [],
    socket: [],
    sequence: [],
    commits: 0,
    rollbacks: 0,
  };
  const state = { status: null, totalAmount: null };
  const conn = {
    async beginTransaction() {},
    async commit() {
      calls.commits += 1;
      calls.sequence.push('commit');
    },
    async rollback() { calls.rollbacks += 1; },
    release() {},
  };
  const bookingRepository = {
    async insertBooking(_conn, row) {
      calls.booking = row;
      state.status = row.status;
      state.totalAmount = row.totalAmount;
      return 10;
    },
    async insertPassengers() {},
    async insertLuggage() {},
    async insertTransferDetails() {},
    async insertChargeItem(_conn, _bookingId, item) {
      if (failSecondChargeItem && calls.chargeItems.length === 1) {
        throw new Error('charge item insert failed');
      }
      calls.chargeItems.push(item);
      state.totalAmount = calls.chargeItems.reduce((sum, row) => sum + row.amount, 0);
    },
    async insertStatusLog() {},
    async insertActivityLog() {},
    async insertGuestToken() {},
    async findById() {
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: state.status,
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: state.totalAmount,
        currency: 'THB',
      };
    },
  };
  const service = new BookingService(
    { async getConnection() { return conn; } },
    bookingRepository,
    {
      async insertRoom() { return 20; },
      async insertParticipant() {},
    },
    { async generateNext() { return 'TX202607130001'; } },
    {
      async calculate() { return PRICE; },
      async resolveServiceType() {
        return { id: 1, code: 'AIRPORT_PICKUP', name: 'Airport pickup' };
      },
    },
    { async recommend() { return { recommendedVehicle: 'VAN' }; } },
    { async findTypeByCode() { return { id: 3, code: 'VAN', name: 'Van' }; } },
    {
      async insertNotificationEvent(_conn, event) {
        calls.outbox.push(event);
        return 30;
      },
    },
    {
      async dispatchOutboxIds(ids) {
        calls.sequence.push(`outbox:${ids.join(',')}`);
      },
    },
    null,
    {
      async listEligibleForOpenBooking() {
        return [{ id: 7, user_id: 42 }];
      },
    },
    {
      async insert(_conn, notification) {
        calls.notifications.push(notification);
      },
    },
  );

  setRealtimeIo({
    to(room) {
      return {
        emit(event, payload) {
          calls.sequence.push('socket');
          calls.socket.push({ room, event, payload });
        },
      };
    },
  });

  return { service, calls, state };
}

test('OPEN booking derives total from charge items and notifies eligible drivers after commit', async () => {
  const { service, calls, state } = createHarness();
  try {
    const result = await service.createBooking(BOOKING_INPUT, null);

    assert.equal(calls.booking.totalAmount, 0);
    assert.equal(calls.booking.status, BOOKING_STATUS.OPEN);
    assert.deepEqual(calls.chargeItems.map((item) => item.amount), [1000, 200]);
    assert.equal(state.totalAmount, PRICE.totalAmount);
    assert.equal(result.totalAmount, PRICE.totalAmount);
    assert.equal(result.status, BOOKING_STATUS.OPEN);
    assert.equal(calls.commits, 1);
    assert.equal(calls.rollbacks, 0);
    assert.equal(calls.notifications.length, 1);
    assert.equal(
      calls.notifications[0].notificationType,
      NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
    );
    assert.equal(calls.outbox[0].eventType, EVENTS.BOOKING_CREATED);
    assert.deepEqual(calls.sequence, ['commit', 'outbox:30', 'socket']);
    assert.equal(calls.socket[0].room, driverUserRoom(42));
    assert.equal(calls.socket[0].event, 'driver:call:new');
    assert.equal(Object.hasOwn(calls.socket[0].payload, 'customer'), false);
  } finally {
    setRealtimeIo(null);
  }
});

test('charge item failure rolls back without driver notification, outbox, or socket dispatch', async () => {
  const { service, calls } = createHarness({ failSecondChargeItem: true });
  try {
    await assert.rejects(
      () => service.createBooking(BOOKING_INPUT, null),
      /charge item insert failed/,
    );

    assert.equal(calls.booking.totalAmount, 0);
    assert.equal(calls.booking.status, BOOKING_STATUS.OPEN);
    assert.equal(calls.chargeItems.length, 1);
    assert.equal(calls.commits, 0);
    assert.equal(calls.rollbacks, 1);
    assert.equal(calls.notifications.length, 0);
    assert.equal(calls.outbox.length, 0);
    assert.equal(calls.socket.length, 0);
    assert.deepEqual(calls.sequence, []);
  } finally {
    setRealtimeIo(null);
  }
});
