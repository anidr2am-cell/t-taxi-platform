const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const BookingService = require('../src/services/booking.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const { EVENTS } = require('../src/events');
const { setRealtimeIo } = require('../src/socket/realtime');

const SERVER_PRICE = {
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
  totalAmount: 1,
};

function createHarness({ pricingService } = {}) {
  const calls = {
    booking: null,
    passengers: null,
    luggage: null,
    transfer: null,
    chargeItems: [],
    statusLog: null,
    activityLog: null,
    guestToken: null,
    outbox: [],
    pricingInputs: [],
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };

  const resolvedPricingService = pricingService ?? {
    async calculate(input) {
      calls.pricingInputs.push(input);
      return SERVER_PRICE;
    },
    async resolveServiceType() {
      return { id: 1, code: 'AIRPORT_PICKUP', name: 'Airport Pickup' };
    },
  };

  const bookingRepository = {
    async insertBooking(_conn, row) {
      calls.booking = row;
      return 10;
    },
    async insertPassengers(_conn, bookingId, passengers) {
      calls.passengers = { bookingId, ...passengers };
    },
    async insertLuggage(_conn, bookingId, luggage) {
      calls.luggage = { bookingId, ...luggage };
    },
    async insertTransferDetails(_conn, bookingId, transfer) {
      calls.transfer = { bookingId, ...transfer };
    },
    async insertChargeItem(_conn, bookingId, item) {
      calls.chargeItems.push({ bookingId, ...item });
    },
    async insertStatusLog(_conn, bookingId, log) {
      calls.statusLog = { bookingId, ...log };
    },
    async insertActivityLog(_conn, bookingId, log) {
      calls.activityLog = { bookingId, ...log };
    },
    async insertGuestToken(_conn, bookingId, tokenHash, expiresAt) {
      calls.guestToken = { bookingId, tokenHash, expiresAt };
    },
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
        total_amount: SERVER_PRICE.totalAmount,
        currency: 'THB',
      };
    },
  };

  const service = new BookingService(
    { async getConnection() { return conn; } },
    bookingRepository,
    { async generateNext() { return 'TX202607130001'; } },
    resolvedPricingService,
    { async recommend() { return { recommendedVehicle: 'SUV' }; } },
    { async findTypeByCode() { return { id: 2, code: 'SUV', name: 'SUV' }; } },
    {
      async insertNotificationEvent(_conn, event) {
        calls.outbox.push(event);
        return 30;
      },
    },
    { async dispatchOutboxIds() {} },
    null,
    { async listEligibleForOpenBooking() { return []; } },
    null,
    null,
    null,
    null,
  );

  setRealtimeIo({ to() { return { emit() {} }; } });

  return { service, calls };
}

test('createBooking recalculates pricing server-side via buildPricingInput', async () => {
  const { service, calls } = createHarness();
  await service.createBooking(CREATE_INPUT, null);

  assert.equal(calls.pricingInputs.length, 1);
  assert.deepEqual(calls.pricingInputs[0], {
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    options: { nameSign: true, nameSignText: 'KIM FAMILY' },
    scheduledPickupAt: CREATE_INPUT.scheduledPickupAt,
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
  });
  assert.equal(Object.hasOwn(calls.pricingInputs[0], 'totalAmount'), false);
});

test('createBooking stores server charge items and initial total_amount zero', async () => {
  const { service, calls } = createHarness();
  const result = (await service.createBooking(CREATE_INPUT, null)).data;

  assert.equal(calls.booking.totalAmount, 0);
  assert.equal(calls.booking.routeId, SERVER_PRICE.routeId);
  assert.deepEqual(
    calls.chargeItems.map((item) => ({
      chargeType: item.chargeType,
      amount: item.amount,
      referenceType: item.referenceType,
      referenceId: item.referenceId,
    })),
    [{
      chargeType: 'VEHICLE_BASE',
      amount: 1300,
      referenceType: 'VEHICLE_PRICE',
      referenceId: 99,
    }],
  );
  assert.equal(result.totalAmount, SERVER_PRICE.totalAmount);
});

test('createBooking persists child tables and guest access token for guest booking', async () => {
  const { service, calls } = createHarness();
  await service.createBooking(CREATE_INPUT, null);

  assert.deepEqual(calls.passengers, {
    bookingId: 10,
    adults: 2,
    children: 1,
    infants: 0,
  });
  assert.deepEqual(calls.luggage, {
    bookingId: 10,
    carriers20Inch: 1,
    carriers24InchPlus: 2,
    golfBags: 1,
    specialItems: '1',
  });
  assert.equal(calls.transfer.flightNumber, 'TG409');
  assert.equal(calls.statusLog.toStatus, BOOKING_STATUS.OPEN);
  assert.equal(calls.activityLog.activityType, 'BOOKING_CREATED');
  assert.ok(calls.guestToken);
  assert.equal(calls.guestToken.bookingId, 10);
  assert.equal(calls.outbox[0].eventType, EVENTS.BOOKING_CREATED);
});

test('createBooking stores customer contact and route fields on booking row', async () => {
  const { service, calls } = createHarness();
  await service.createBooking(CREATE_INPUT, null);

  assert.equal(calls.booking.originPlaceId, 'google-bkk');
  assert.equal(calls.booking.destinationPlaceId, 'google-pattaya');
  assert.equal(calls.booking.customerName, 'Kim Test');
  assert.equal(calls.booking.customerPhone, '+66123456789');
  assert.equal(calls.booking.nameSignText, 'KIM FAMILY');
  assert.equal(calls.booking.specialRequests, 'Need child seat');

  const metadata = typeof calls.booking.metadata === 'string'
    ? JSON.parse(calls.booking.metadata)
    : calls.booking.metadata;
  assert.equal(metadata.messengerType, 'LINE');
  assert.equal(metadata.messengerId, 'line-user-id');
  assert.equal(metadata.originLocation.name, 'Suvarnabhumi Airport');
  assert.equal(metadata.destinationLocation.name, 'Pattaya Hotel');
});

test('createBooking omits metadata messenger keys when customer messenger fields are omitted', async () => {
  const { service, calls } = createHarness();
  await service.createBooking({
    ...CREATE_INPUT,
    customer: {
      name: CREATE_INPUT.customer.name,
      phone: CREATE_INPUT.customer.phone,
    },
  }, null);

  const metadata = typeof calls.booking.metadata === 'string'
    ? JSON.parse(calls.booking.metadata)
    : calls.booking.metadata;
  assert.equal(metadata.messengerType, undefined);
  assert.equal(metadata.messengerId, undefined);
});
