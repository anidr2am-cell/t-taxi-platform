'use strict';

const { randomUUID } = require('node:crypto');
const { urgentPickupIso } = require('./urgent-qa-pickup.cjs');

/** POST /bookings body for URGENT isolated QA (matches createBookingSchema). */
function buildUrgentBookingBody(minutesFromNow = 75, idSuffix) {
  const suffix = idSuffix ?? randomUUID();
  return {
    bookingMode: 'URGENT',
    serviceTypeCode: 'CITY_TRANSFER',
    vehicleTypeCode: 'SEDAN',
    scheduledPickupAt: urgentPickupIso(minutesFromNow),
    destinationRegion: 'Urgent QA',
    origin: {
      name: 'QA Origin',
      address: 'QA origin address',
      placeId: `urgent-o-${suffix}`,
      lat: 13.7563,
      lng: 100.5018,
    },
    destination: {
      name: 'QA Destination',
      address: 'QA destination address',
      placeId: `urgent-d-${suffix}`,
      lat: 13.9813,
      lng: 100.5018,
    },
    passengers: { adults: 1, children: 0, infants: 0 },
    customer: {
      name: 'Urgent QA Customer',
      phone: '0888777666',
    },
  };
}

module.exports = { buildUrgentBookingBody };
