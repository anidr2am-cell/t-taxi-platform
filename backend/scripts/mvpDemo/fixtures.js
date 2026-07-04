/**
 * MVP demo fixtures — local/staging only. Do not use in production.
 */
const BOOKING_STATUS = require('../../src/constants/reservationStatus');

const DEMO_ADMIN = {
  email: 'admin@ttaxi.dev',
  password: 'Admin123456!',
  name: 'MVP Admin',
  role: 'SUPER_ADMIN',
};

const DEMO_DRIVER = {
  email: 'driver@ttaxi.dev',
  password: 'Driver123456!',
  name: 'MVP Demo Driver',
  phone: '+66810000001',
};

const DEMO_CUSTOMER_BASE_PHONE = '+668200000';

const STATUS_SCENARIOS = [
  { status: BOOKING_STATUS.PENDING, steps: [] },
  { status: BOOKING_STATUS.DRIVER_ASSIGNED, steps: ['assign'] },
  { status: BOOKING_STATUS.ON_ROUTE, steps: ['assign', 'onRoute'] },
  { status: BOOKING_STATUS.DRIVER_ARRIVED, steps: ['assign', 'onRoute', 'arrived'] },
  { status: BOOKING_STATUS.COMPLETED, steps: ['assign', 'onRoute', 'arrived', 'complete'] },
  { status: BOOKING_STATUS.CANCELLED, steps: ['cancel'] },
];

function scheduledPickupAt(hoursFromNow = 4) {
  const date = new Date(Date.now() + hoursFromNow * 60 * 60 * 1000);
  date.setMinutes(0, 0, 0);
  return date.toISOString();
}

function buildBookingPayload({ customerName, customerPhone, label }) {
  return {
    serviceTypeCode: 'AIRPORT_PICKUP',
    vehicleTypeCode: 'SUV',
    vehicleCount: 1,
    scheduledPickupAt: scheduledPickupAt(),
    originAirportIata: 'BKK',
    originLocationCode: 'BKK',
    destinationLocationCode: 'PATTAYA',
    origin: {
      address: 'Suvarnabhumi Airport (BKK)',
      placeId: 'demo-bkk-origin',
      lat: 13.6900,
      lng: 100.7501,
      name: 'BKK Airport',
    },
    destination: {
      address: 'Pattaya Beach Hotel',
      placeId: 'demo-pattaya-destination',
      lat: 12.9236,
      lng: 100.8825,
      name: 'Pattaya',
    },
    passengers: {
      adults: 2,
      children: 0,
      infants: 0,
    },
    luggage: {
      carriers20Inch: 1,
      carriers24InchPlus: 0,
      golfBags: 0,
      specialItems: null,
      specialLuggageCount: 0,
    },
    options: {
      nameSign: false,
    },
    customer: {
      name: customerName,
      email: null,
      phone: customerPhone,
      countryCode: 'TH',
    },
    additionalRequests: label ? `MVP demo seed — ${label}` : 'MVP demo seed',
  };
}

function customerPhoneForIndex(index) {
  const suffix = String(index + 1).padStart(2, '0');
  return `${DEMO_CUSTOMER_BASE_PHONE}${suffix}`;
}

function parseScenarioFilter(raw) {
  if (!raw) return STATUS_SCENARIOS;
  const wanted = new Set(
    String(raw)
      .split(',')
      .map((item) => item.trim().toUpperCase())
      .filter(Boolean),
  );
  return STATUS_SCENARIOS.filter((scenario) => wanted.has(scenario.status));
}

module.exports = {
  DEMO_ADMIN,
  DEMO_DRIVER,
  DEMO_CUSTOMER_BASE_PHONE,
  STATUS_SCENARIOS,
  scheduledPickupAt,
  buildBookingPayload,
  customerPhoneForIndex,
  parseScenarioFilter,
};
