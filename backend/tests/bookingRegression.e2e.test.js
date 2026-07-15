process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const test = require('node:test');
const assert = require('node:assert/strict');
const jwt = require('jsonwebtoken');
const request = require('supertest');

const AppError = require('../src/utils/AppError');
const HTTP_STATUS = require('../src/constants/httpStatus');
const ERROR_CODES = require('../src/constants/errorCodes');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const container = require('../src/helpers/container');
const app = require('../src/app');

const REGRESSION_MARKER = 'AUTOMATED_REGRESSION_TEST';
const ADMIN_TOKEN = sign('ADMIN', 501);
const DRIVER_TOKEN = sign('DRIVER', 601);
const TEST_DRIVER_ID = 42;
const TEST_DRIVER_USER_ID = 601;

function sign(role, id) {
  return jwt.sign(
    { sub: id, email: `${role.toLowerCase()}${id}@example.com`, role, type: 'access' },
    process.env.JWT_ACCESS_SECRET,
    { expiresIn: '1h' },
  );
}

function futurePickup(offsetDays = 30) {
  const date = new Date();
  date.setUTCDate(date.getUTCDate() + offsetDays);
  date.setUTCHours(3, 30, 0, 0);
  return date.toISOString();
}

function scenarioPayload({
  serviceTypeCode = 'AIRPORT_PICKUP',
  customerName = '[E2E] John Regression',
  flightNumber = '7C2203',
} = {}) {
  const base = {
    serviceTypeCode,
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: futurePickup(),
    origin: {
      name: 'Suvarnabhumi Airport',
      address: 'Suvarnabhumi Airport, Bangkok, Thailand',
      placeId: 'test-bkk',
      lat: 13.69,
      lng: 100.75,
    },
    destination: {
      name: 'Pattaya',
      address: 'Pattaya, Chon Buri, Thailand',
      placeId: 'test-pattaya',
      lat: 12.9236,
      lng: 100.8825,
    },
    originAirportIata: 'BKK',
    destinationLocationCode: 'PATTAYA',
    passengers: { adults: 2, children: 0, infants: 0 },
    luggage: { carriers20Inch: 1, carriers24InchPlus: 1, golfBags: 0 },
    options: { nameSign: true },
    transfer: { airportIata: 'BKK', flightNumber },
    customer: {
      name: customerName,
      phone: '+66000000001',
      email: 'regression@example.com',
      countryCode: 'TH',
    },
    additionalRequests: REGRESSION_MARKER,
  };

  if (serviceTypeCode === 'AIRPORT_DROPOFF') {
    return {
      ...base,
      origin: {
        name: 'Pattaya',
        address: 'Pattaya, Chon Buri, Thailand',
        placeId: 'test-pattaya',
        lat: 12.9236,
        lng: 100.8825,
      },
      destination: {
        name: 'Suvarnabhumi Airport',
        address: 'Suvarnabhumi Airport, Bangkok, Thailand',
        placeId: 'test-bkk',
        lat: 13.69,
        lng: 100.75,
      },
      originAirportIata: undefined,
      originLocationCode: 'PATTAYA',
      destinationLocationCode: 'BKK',
      transfer: { airportIata: 'BKK', flightNumber: null },
      options: { nameSign: false },
    };
  }

  if (serviceTypeCode === 'CITY_TRANSFER') {
    return {
      ...base,
      origin: {
        name: 'Bangkok',
        address: 'Bangkok, Thailand',
        placeId: 'test-bangkok',
        lat: 13.7563,
        lng: 100.5018,
      },
      destination: {
        name: 'Pattaya',
        address: 'Pattaya, Chon Buri, Thailand',
        placeId: 'test-pattaya',
        lat: 12.9236,
        lng: 100.8825,
      },
      originAirportIata: undefined,
      originLocationCode: 'BANGKOK',
      destinationLocationCode: 'PATTAYA',
      transfer: undefined,
      options: { nameSign: false },
    };
  }

  return base;
}

function pricingResult(payload) {
  return {
    currency: 'THB',
    totalAmount: payload.serviceTypeCode === 'CITY_TRANSFER' ? 1300 : 1500,
    chargeItems: [
      {
        chargeType: 'VEHICLE_BASE',
        description: `${payload.vehicleTypeCode} ${payload.serviceTypeCode}`,
        quantity: 1,
        unitPrice: payload.serviceTypeCode === 'CITY_TRANSFER' ? 1300 : 1500,
        amount: payload.serviceTypeCode === 'CITY_TRANSFER' ? 1300 : 1500,
      },
    ],
    routeId: payload.serviceTypeCode === 'AIRPORT_DROPOFF' ? 22 : 11,
    appliedPricingRuleId: payload.serviceTypeCode === 'AIRPORT_DROPOFF' ? 22 : 11,
    vehiclePriceId: 99,
  };
}

function installRegressionStubs(state) {
  container.register('vehicleRecommendationService', () => ({
    async recommend(input) {
      assert.ok(input.adults >= 1);
      return {
        recommendedVehicle: input.adults >= 5 ? 'VAN' : 'SUV',
        selectableVehicles: ['SEDAN', 'SUV', 'VAN'],
        multipleVehicles: false,
        message: 'OK',
      };
    },
  }));

  container.register('pricingService', () => ({
    async calculate(input) {
      if (input.destinationLocationCode === 'UNKNOWN') {
        throw new AppError('Route not found for the given service and locations', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }
      if (input.vehicleTypeCode === 'LUXURY') {
        throw new AppError('Vehicle price not configured for this route', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.NOT_FOUND,
        });
      }
      return pricingResult(input);
    },
  }));

  container.register('bookingService', () => ({
    async createBooking(input) {
      const number = `TX20990101000${state.bookings.length + 1}`;
      const quote = pricingResult(input);
      const booking = {
        bookingId: 100 + state.bookings.length,
        bookingNumber: number,
        status: BOOKING_STATUS.OPEN,
        paymentMethod: 'PAY_DRIVER',
        paymentStatus: 'UNPAID',
        totalAmount: quote.totalAmount,
        currency: quote.currency,
        guestAccessToken: `guest-token-${state.bookings.length + 1}`,
        customerPhone: input.customer.phone,
        serviceTypeCode: input.serviceTypeCode,
        customerName: input.customer.name,
        flightNumber: input.transfer?.flightNumber ?? null,
        additionalRequests: input.additionalRequests,
      };
      state.bookings.push(booking);
      return booking;
    },
  }));

  container.register('guestBookingLookupService', () => ({
    async lookup(input) {
      const booking = state.bookings.find((item) => item.bookingNumber === input.bookingNumber);
      if (!booking || booking.customerPhone !== input.phone) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }
      return {
        bookingNumber: booking.bookingNumber,
        status: booking.status,
        serviceType: { code: booking.serviceTypeCode },
        pricing: { totalAmount: booking.totalAmount, currency: booking.currency },
        guestAccess: { token: booking.guestAccessToken },
      };
    },
  }));

  container.register('adminDispatchService', () => ({
    async listBookings() {
      return {
        page: 1,
        pageSize: 20,
        total: state.bookings.length,
        items: state.bookings.map((booking) => ({
          bookingNumber: booking.bookingNumber,
          serviceType: { code: booking.serviceTypeCode },
          serviceTypeCode: booking.serviceTypeCode,
          customerDisplayName: booking.customerName,
          totalAmount: booking.totalAmount,
          currency: booking.currency,
          status: booking.status,
        })),
      };
    },
    async getDriverCandidates() {
      return {
        items: [{
          driverId: TEST_DRIVER_ID,
          displayName: '[E2E] Test Driver',
          eligible: true,
          reasons: [],
        }],
      };
    },
    async assignDriver(bookingNumber, body) {
      assert.equal(body.driverId, TEST_DRIVER_ID);
      const booking = state.bookings.find((item) => item.bookingNumber === bookingNumber);
      booking.status = BOOKING_STATUS.DRIVER_ASSIGNED;
      booking.driverUserId = TEST_DRIVER_USER_ID;
      return {
        bookingNumber,
        bookingStatus: BOOKING_STATUS.DRIVER_ASSIGNED,
        assignmentId: 700,
        driverId: TEST_DRIVER_ID,
      };
    },
    async archiveBookings(body) {
      state.archived.push(...body.bookingNumbers);
      return { archived: body.bookingNumbers.length };
    },
  }));

  container.register('driverJobService', () => ({
    async listToday(driverUserId) {
      return {
        items: state.bookings
          .filter((item) => item.driverUserId === driverUserId)
          .map((item) => ({
            bookingNumber: item.bookingNumber,
            status: item.status,
            customer: { displayName: item.customerName },
          })),
      };
    },
    async getDetail(driverUserId, bookingNumber) {
      const booking = state.bookings.find((item) => (
        item.bookingNumber === bookingNumber && item.driverUserId === driverUserId
      ));
      if (!booking) throw new AppError('Booking not found', { statusCode: 404, errorCode: ERROR_CODES.BOOKING_NOT_FOUND });
      return { bookingNumber, status: booking.status };
    },
  }));

  container.register('driverTripFlowService', () => ({
    async startOnRoute(driverUserId, bookingNumber) {
      return transitionDriverBooking(state, driverUserId, bookingNumber, BOOKING_STATUS.DRIVER_ASSIGNED, BOOKING_STATUS.ON_ROUTE);
    },
    async markArrived(driverUserId, bookingNumber) {
      return transitionDriverBooking(state, driverUserId, bookingNumber, BOOKING_STATUS.ON_ROUTE, BOOKING_STATUS.DRIVER_ARRIVED);
    },
    async markPickedUp(driverUserId, bookingNumber) {
      return transitionDriverBooking(state, driverUserId, bookingNumber, BOOKING_STATUS.DRIVER_ARRIVED, BOOKING_STATUS.PICKED_UP);
    },
    async endTrip(driverUserId, bookingNumber) {
      return transitionDriverBooking(state, driverUserId, bookingNumber, BOOKING_STATUS.PICKED_UP, BOOKING_STATUS.SETTLEMENT_PENDING);
    },
  }));
}

function transitionDriverBooking(state, driverUserId, bookingNumber, from, to) {
  const booking = state.bookings.find((item) => (
    item.bookingNumber === bookingNumber && item.driverUserId === driverUserId
  ));
  if (!booking) {
    throw new AppError('Booking not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
    });
  }
  if (booking.status !== from) {
    throw new AppError('Invalid booking status transition', {
      statusCode: HTTP_STATUS.CONFLICT,
      errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
    });
  }
  booking.status = to;
  return { bookingNumber, status: to, idempotent: false };
}

test('booking regression API covers pickup, dropoff, city transfer, lookup, admin, assignment, and driver flow', async () => {
  const state = { bookings: [], archived: [] };
  installRegressionStubs(state);

  const scenarios = [
    scenarioPayload({ customerName: '[E2E] 박용세', flightNumber: '7c-2203' }),
    scenarioPayload({ customerName: '[E2E] สมชาย ทดสอบ', flightNumber: 'TG401' }),
    scenarioPayload({ customerName: '[E2E] John Regression', flightNumber: null }),
    scenarioPayload({ serviceTypeCode: 'AIRPORT_DROPOFF', customerName: '[E2E] Airport Dropoff' }),
    scenarioPayload({ serviceTypeCode: 'CITY_TRANSFER', customerName: '[E2E] City Transfer' }),
  ];

  for (const payload of scenarios) {
    const recommendation = await request(app)
      .post('/api/v1/bookings/vehicle/recommend')
      .send({
        adults: payload.passengers.adults,
        children: payload.passengers.children,
        infants: payload.passengers.infants,
        luggage20: payload.luggage.carriers20Inch,
        luggage24: payload.luggage.carriers24InchPlus,
        golfBags: payload.luggage.golfBags,
      });
    assert.equal(recommendation.status, 200);
    assert.equal(recommendation.body.data.recommendedVehicle, 'SUV');

    const pricing = await request(app)
      .post('/api/v1/bookings/pricing/calculate')
      .send({
        serviceTypeCode: payload.serviceTypeCode,
        vehicleTypeCode: payload.vehicleTypeCode,
        vehicleCount: payload.vehicleCount,
        scheduledPickupAt: payload.scheduledPickupAt,
        originAirportIata: payload.originAirportIata,
        originLocationCode: payload.originLocationCode,
        destinationLocationCode: payload.destinationLocationCode,
        options: payload.options,
        passengers: payload.passengers,
        luggage: payload.luggage,
      });
    assert.equal(pricing.status, 200);
    assert.equal(pricing.body.data.currency, 'THB');

    const created = await request(app)
      .post('/api/v1/bookings')
      .send(payload);
    assert.equal(created.status, 201);
    assert.equal(created.body.data.status, BOOKING_STATUS.OPEN);
    assert.match(created.body.data.bookingNumber, /^TX\d{12}$/);

    const stored = state.bookings.find((item) => item.bookingNumber === created.body.data.bookingNumber);
    assert.equal(stored.additionalRequests, REGRESSION_MARKER);
    if (payload.serviceTypeCode === 'AIRPORT_PICKUP' && payload.transfer?.flightNumber) {
      assert.equal(stored.flightNumber, payload.transfer.flightNumber.replace('-', '').toUpperCase());
    } else if (payload.serviceTypeCode !== 'AIRPORT_PICKUP') {
      assert.equal(stored.flightNumber, null);
    }

    const lookup = await request(app)
      .post('/api/v1/public/bookings/lookup')
      .send({ bookingNumber: created.body.data.bookingNumber, phone: payload.customer.phone });
    assert.equal(lookup.status, 200);
    assert.equal(lookup.body.data.bookingNumber, created.body.data.bookingNumber);
  }

  const adminList = await request(app)
    .get('/api/v1/admin/bookings')
    .set('Authorization', `Bearer ${ADMIN_TOKEN}`);
  assert.equal(adminList.status, 200);
  assert.equal(adminList.body.data.total, scenarios.length);
  assert.ok(adminList.body.data.items.some((item) => item.customerDisplayName === '[E2E] 박용세'));
  assert.ok(adminList.body.data.items.some((item) => item.customerDisplayName === '[E2E] สมชาย ทดสอบ'));

  const bookingNumber = state.bookings[0].bookingNumber;
  const candidates = await request(app)
    .get(`/api/v1/admin/bookings/${bookingNumber}/driver-candidates`)
    .set('Authorization', `Bearer ${ADMIN_TOKEN}`);
  assert.equal(candidates.status, 200);
  assert.equal(candidates.body.data.items[0].driverId, TEST_DRIVER_ID);

  const assigned = await request(app)
    .post(`/api/v1/admin/bookings/${bookingNumber}/assign-driver`)
    .set('Authorization', `Bearer ${ADMIN_TOKEN}`)
    .send({ driverId: TEST_DRIVER_ID, assignmentReason: REGRESSION_MARKER });
  assert.equal(assigned.status, 200);
  assert.equal(assigned.body.data.bookingStatus, BOOKING_STATUS.DRIVER_ASSIGNED);

  const driverJobs = await request(app)
    .get('/api/v1/driver/bookings/today')
    .set('Authorization', `Bearer ${DRIVER_TOKEN}`);
  assert.equal(driverJobs.status, 200);
  assert.equal(driverJobs.body.data.items[0].bookingNumber, bookingNumber);

  const onRoute = await request(app)
    .post(`/api/v1/driver/bookings/${bookingNumber}/start-route`)
    .set('Authorization', `Bearer ${DRIVER_TOKEN}`);
  assert.equal(onRoute.status, 200);
  assert.equal(onRoute.body.data.status, BOOKING_STATUS.ON_ROUTE);

  const invalidRepeat = await request(app)
    .post(`/api/v1/driver/bookings/${bookingNumber}/start-route`)
    .set('Authorization', `Bearer ${DRIVER_TOKEN}`);
  assert.equal(invalidRepeat.status, 409);
  assert.equal(invalidRepeat.body.error_code, ERROR_CODES.INVALID_STATUS_TRANSITION);

  for (const [path, expected] of [
    ['arrive', BOOKING_STATUS.DRIVER_ARRIVED],
    ['mark-picked-up', BOOKING_STATUS.PICKED_UP],
    ['end-trip', BOOKING_STATUS.SETTLEMENT_PENDING],
  ]) {
    const response = await request(app)
      .post(`/api/v1/driver/bookings/${bookingNumber}/${path}`)
      .set('Authorization', `Bearer ${DRIVER_TOKEN}`);
    assert.equal(response.status, 200);
    assert.equal(response.body.data.status, expected);
  }

  const archived = await request(app)
    .post('/api/v1/admin/bookings/archive')
    .set('Authorization', `Bearer ${ADMIN_TOKEN}`)
    .send({ bookingNumbers: state.bookings.map((item) => item.bookingNumber), reason: REGRESSION_MARKER });
  assert.equal(archived.status, 200);
  assert.equal(state.archived.length, scenarios.length);
});

test('booking regression validation errors include field, type, and source details', async () => {
  installRegressionStubs({ bookings: [], archived: [] });

  const cases = [
    {
      name: 'blank customer name',
      body: { ...scenarioPayload(), customer: { ...scenarioPayload().customer, name: '   ' } },
      field: 'customer.name',
    },
    {
      name: 'bad flight number',
      body: { ...scenarioPayload(), transfer: { airportIata: 'BKK', flightNumber: 'TG/401' } },
      field: 'transfer.flightNumber',
      type: 'any.invalid',
    },
    {
      name: 'zero passengers',
      body: { ...scenarioPayload(), passengers: { adults: 0, children: 0, infants: 0 } },
      field: 'passengers.adults',
    },
    {
      name: 'past pickup time',
      body: { ...scenarioPayload(), scheduledPickupAt: '2020-01-01T09:30:00+07:00' },
      field: 'scheduledPickupAt',
    },
    {
      name: 'bad email',
      body: { ...scenarioPayload(), customer: { ...scenarioPayload().customer, email: 'bad-email' } },
      field: 'customer.email',
      type: 'string.email',
    },
    {
      name: 'missing destination',
      body: (() => {
        const payload = scenarioPayload();
        delete payload.destination;
        return payload;
      })(),
      field: 'destination',
    },
    {
      name: 'unsupported vehicle type',
      body: { ...scenarioPayload(), vehicleTypeCode: 'BUS' },
      field: 'vehicleTypeCode',
      type: 'any.only',
    },
  ];

  for (const item of cases) {
    const response = await request(app).post('/api/v1/bookings').send(item.body);
    assert.equal(response.status, 400, item.name);
    assert.equal(response.body.error_code, ERROR_CODES.VALIDATION_ERROR, item.name);
    assert.ok(Array.isArray(response.body.errors), item.name);
    const detail = response.body.errors.find((error) => error.field === item.field);
    assert.ok(detail, item.name);
    assert.equal(detail.source, 'body', item.name);
    if (item.type) assert.equal(detail.type, item.type, item.name);
    assert.ok(!JSON.stringify(response.body).includes('regression@example.com'), item.name);
  }

  const routeMissing = await request(app)
    .post('/api/v1/bookings/pricing/calculate')
    .send({
      serviceTypeCode: 'CITY_TRANSFER',
      vehicleTypeCode: 'SUV',
      originLocationCode: 'BANGKOK',
      destinationLocationCode: 'UNKNOWN',
      scheduledPickupAt: futurePickup(),
    });
  assert.equal(routeMissing.status, 404);
  assert.equal(routeMissing.body.error_code, ERROR_CODES.NOT_FOUND);
  assert.ok(!JSON.stringify(routeMissing.body).includes('regression@example.com'));
});
