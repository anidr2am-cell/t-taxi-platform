const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const BookingService = require('../src/services/booking.service');
const { getThailandAirportNameTh } = require('../src/constants/thailandAirports.constants');
const { setRealtimeIo } = require('../src/socket/realtime');

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
  ],
};

const BASE_INPUT = {
  serviceTypeCode: 'AIRPORT_PICKUP',
  vehicleTypeCode: 'VAN',
  scheduledPickupAt: '2026-07-14T03:00:00.000Z',
  origin: {
    name: 'BKK — Suvarnabhumi Airport',
    address: '999 Moo 1, Nong Prue, Bang Phli District, Samut Prakan 10540, Thailand',
    lat: 13.689999,
    lng: 100.747924,
  },
  destination: {
    name: 'Hilton Pattaya',
    address: '333/101 Moo 9, Pattaya, Chon Buri 20260, Thailand',
    lat: 12.934,
    lng: 100.883,
  },
  passengers: { adults: 2, children: 0, infants: 0 },
  luggage: { carriers20Inch: 1, carriers24InchPlus: 0, golfBags: 0 },
  options: { nameSign: false },
  customer: { name: 'Test Customer', phone: '0800000000' },
};

function createHarness({ placesService = null } = {}) {
  const calls = {
    booking: null,
    placesDetails: [],
  };
  const conn = {
    async beginTransaction() {},
    async commit() {},
    async rollback() {},
    release() {},
  };
  const bookingRepository = {
    async insertBooking(_conn, row) {
      calls.booking = row;
      return 10;
    },
    async insertPassengers() {},
    async insertLuggage() {},
    async insertTransferDetails() {},
    async insertChargeItem() {},
    async insertStatusLog() {},
    async insertActivityLog() {},
    async insertGuestToken() {},
    async findAirportByIata() {
      return { id: 1 };
    },
    async findById() {
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: 'OPEN',
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: 1200,
        currency: 'THB',
      };
    },
  };

  const resolvedPlacesService = placesService ?? {
    async details(input) {
      calls.placesDetails.push(input);
      return {
        placeId: input.placeId,
        name: 'โรงแรมฮilton พัทยา',
        formattedAddress: '333/101 หมู่ 9 พัทยา',
        lat: 12.934,
        lng: 100.883,
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
      async insertNotificationEvent() {
        return 30;
      },
    },
    {
      async dispatchOutboxIds() {},
    },
    null,
    {
      async listEligibleForOpenBooking() {
        return [];
      },
    },
    null,
    null,
    null,
    resolvedPlacesService,
  );

  setRealtimeIo({
    to() {
      return { emit() {} };
    },
  });

  return { service, calls };
}

function parseMetadata(row) {
  return typeof row.metadata === 'string' ? JSON.parse(row.metadata) : row.metadata;
}

test('createBooking sets origin nameTh from originAirportIata mapping', async () => {
  const { service, calls } = createHarness({ placesService: null });
  await service.createBooking({
    ...BASE_INPUT,
    originAirportIata: 'BKK',
  }, null);

  const metadata = parseMetadata(calls.booking);
  assert.equal(metadata.originLocation.name, 'BKK — Suvarnabhumi Airport');
  assert.equal(metadata.originLocation.nameTh, getThailandAirportNameTh('BKK'));
  assert.equal(Object.hasOwn(metadata.originLocation, 'nameTh'), true);
  assert.equal(metadata.destinationLocation?.nameTh, undefined);
});

test('createBooking sets destination nameTh from destinationLocationCode airport mapping', async () => {
  const { service, calls } = createHarness({ placesService: null });
  await service.createBooking({
    ...BASE_INPUT,
    serviceTypeCode: 'AIRPORT_DROPOFF',
    originAirportIata: undefined,
    originLocationCode: 'PATTAYA',
    destinationLocationCode: 'BKK',
    destination: {
      name: 'BKK — Suvarnabhumi Airport',
      address: '999 Moo 1, Nong Prue, Bang Phli District, Samut Prakan 10540, Thailand',
      lat: 13.689999,
      lng: 100.747924,
    },
  }, null);

  const metadata = parseMetadata(calls.booking);
  assert.equal(metadata.destinationLocation.nameTh, getThailandAirportNameTh('BKK'));
});

test('createBooking sets nameTh from Places Details when placeId exists and no IATA mapping', async () => {
  const { service, calls } = createHarness();
  await service.createBooking({
    ...BASE_INPUT,
    originAirportIata: undefined,
    destination: {
      ...BASE_INPUT.destination,
      placeId: 'google-hilton-pattaya',
    },
  }, null);

  assert.equal(calls.placesDetails.length, 1);
  assert.deepEqual(calls.placesDetails[0], {
    placeId: 'google-hilton-pattaya',
    language: 'th',
  });

  const metadata = parseMetadata(calls.booking);
  assert.equal(metadata.destinationLocation.nameTh, 'โรงแรมฮilton พัทยา');
  assert.equal(metadata.destinationLocation.name, 'Hilton Pattaya');
});

test('createBooking succeeds without nameTh when Places Details fails', async () => {
  const { service, calls } = createHarness({
    placesService: {
      async details() {
        throw new Error('Google Places provider timed out');
      },
    },
  });

  const result = await service.createBooking({
    ...BASE_INPUT,
    originAirportIata: undefined,
    destination: {
      ...BASE_INPUT.destination,
      placeId: 'google-hilton-pattaya',
    },
  }, null);

  assert.equal(result.bookingNumber, 'TX202607130001');
  const metadata = parseMetadata(calls.booking);
  assert.equal(metadata.destinationLocation.name, 'Hilton Pattaya');
  assert.equal(metadata.destinationLocation.nameTh, undefined);
});

test('createBooking omits nameTh when neither IATA mapping nor placeId is available', async () => {
  const { service, calls } = createHarness({ placesService: null });
  await service.createBooking({
    ...BASE_INPUT,
    originAirportIata: undefined,
    origin: {
      name: 'Pinned spot',
      address: '13.756300, 100.501800',
      lat: 13.7563,
      lng: 100.5018,
    },
    destination: {
      name: 'Pinned hotel',
      address: '12.934000, 100.883000',
      lat: 12.934,
      lng: 100.883,
    },
  }, null);

  const metadata = parseMetadata(calls.booking);
  assert.equal(metadata.originLocation.name, 'Pinned spot');
  assert.equal(metadata.originLocation.nameTh, undefined);
  assert.equal(metadata.destinationLocation.name, 'Pinned hotel');
  assert.equal(metadata.destinationLocation.nameTh, undefined);
});
