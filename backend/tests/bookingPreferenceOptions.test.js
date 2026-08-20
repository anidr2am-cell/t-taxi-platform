const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'tride_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret';

const { createBookingSchema } = require('../src/validators/booking.validator');
const BookingService = require('../src/services/booking.service');
const GuestBookingLookupService = require('../src/services/guestBookingLookup.service');
const AdminDispatchService = require('../src/services/adminDispatch.service');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
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

function validPayload(overrides = {}) {
  return {
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
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: {},
    options: {},
    transfer: { airportIata: 'BKK' },
    customer: {
      name: 'Kim Test',
      phone: '+66123456789',
    },
    ...overrides,
  };
}

function createBookingHarness() {
  const calls = { booking: null };
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
      return { id: 1, iata_code: 'BKK' };
    },
    async findById() {
      return {
        id: 10,
        booking_number: 'TX202607130001',
        status: BOOKING_STATUS.OPEN,
        scheduled_pickup_at: '2026-12-01T02:30:00.000Z',
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
    {
      async calculate() { return SERVER_PRICE; },
      async resolveServiceType() {
        return { id: 1, code: 'AIRPORT_PICKUP', name: 'Airport Pickup' };
      },
    },
    { async recommend() { return { recommendedVehicle: 'SUV' }; } },
    { async findTypeByCode() { return { id: 2, code: 'SUV', name: 'SUV' }; } },
    null,
    null,
    null,
    null,
    null,
    null,
    null,
    null,
  );

  setRealtimeIo({ to() { return { emit() {} }; } });

  return { service, calls };
}

test('createBookingSchema defaults preferFemaleDriver to false', () => {
  const { error, value } = createBookingSchema.validate(validPayload());
  assert.equal(error, undefined);
  assert.equal(value.options.preferFemaleDriver, false);
});

test('createBookingSchema accepts preferFemaleDriver when true', () => {
  const { error, value } = createBookingSchema.validate(validPayload({
    options: {
      preferFemaleDriver: true,
    },
  }));
  assert.equal(error, undefined);
  assert.equal(value.options.preferFemaleDriver, true);
});

test('createBooking persists preferFemaleDriver when provided', async () => {
  const { service, calls } = createBookingHarness();
  await service.createBooking(validPayload({
    options: {
      preferFemaleDriver: true,
    },
  }));

  assert.equal(calls.booking.preferFemaleDriver, true);
});

test('createBooking persists preferFemaleDriver as false when omitted', async () => {
  const { service, calls } = createBookingHarness();
  await service.createBooking(validPayload());

  assert.equal(calls.booking.preferFemaleDriver, false);
});

test('guest lookup exposes preferFemaleDriver from stored booking row', async () => {
  const conn = {
    beginTransaction: async () => {},
    commit: async () => {},
    rollback: async () => {},
    release: () => {},
  };
  const repository = {
    async findGuestLookupBookingByNumber() {
      return {
        id: 10,
        booking_number: 'TX202607010001',
        status: 'OPEN',
        scheduled_pickup_at_text: '2026-07-01 09:30:00',
        origin_address: 'BKK Airport',
        destination_address: 'Pattaya Hotel',
        customer_phone: '+66123456789',
        payment_method: 'PAY_DRIVER',
        payment_status: 'UNPAID',
        total_amount: '1500.00',
        currency: 'THB',
        vehicle_count: 1,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport Pickup',
        vehicle_type_code: 'SUV',
        vehicle_type_name: 'SUV',
        adults: 2,
        children: 0,
        infants: 0,
        carriers_20_inch: 0,
        carriers_24_inch_plus: 0,
        golf_bags: 0,
        special_items: null,
        flight_number: null,
        origin_location_code: 'BKK',
        destination_location_code: 'PATTAYA',
        name_sign_requested: 0,
        prefer_female_driver: 1,
      };
    },
    async insertGuestToken() {},
  };
  const service = new GuestBookingLookupService(
    { async getConnection() { return conn; } },
    repository,
  );

  const result = await service.lookup({
    bookingNumber: 'TX202607010001',
    phone: '+66123456789',
  });

  assert.equal(result.options.preferFemaleDriver, true);
});

test('admin booking detail exposes preferFemaleDriver from stored booking row', async () => {
  const bookingRepo = {
    async findAdminBookingDetail() {
      return {
        id: 1,
        booking_number: 'TX202607010001',
        status: 'OPEN',
        scheduled_pickup_at: '2026-07-01 09:30:00',
        origin_address: 'BKK',
        destination_address: 'Pattaya',
        customer_name: 'Kim',
        customer_email: null,
        customer_phone: '+66123456789',
        customer_country_code: 'TH',
        special_requests: null,
        prefer_female_driver: 1,
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
        carriers_20_inch: 0,
        carriers_24_inch_plus: 0,
        golf_bags: 0,
        special_items: null,
        flight_number: null,
        flight_scheduled_arrival_at: null,
        flight_estimated_arrival_at: null,
        delay_status: null,
        delay_minutes: null,
        airport_code_custom: 'BKK',
        airport_iata: 'BKK',
      };
    },
    async findChargeItemsByBookingId() { return []; },
    async findStatusLogsByBookingId() { return []; },
    async findAssignmentsByBookingId() { return []; },
  };
  const service = new AdminDispatchService(
    {},
    bookingRepo,
    {},
    {},
    { async driverHasBlockingSettlement() { return false; } },
    null,
    null,
    {},
  );

  const detail = await service.getBookingDetail('TX202607010001');

  assert.equal(detail.options.preferFemaleDriver, true);
});
