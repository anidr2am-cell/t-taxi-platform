const test = require('node:test');
const assert = require('node:assert/strict');

process.env.NODE_ENV = 'test';
process.env.DB_USER = 'test';
process.env.DB_NAME = 'tride_test';
process.env.JWT_ACCESS_SECRET = 'test-access-secret';
process.env.JWT_REFRESH_SECRET = 'test-refresh-secret';
process.env.CONTACT_CONNECTION_REQUIRED = 'true';

delete require.cache[require.resolve('../src/config/env')];
delete require.cache[require.resolve('../src/policies/bookingDispatchEligibility.policy')];

const CONTACT_STATUS = require('../src/constants/contactStatus');
const BOOKING_STATUS = require('../src/constants/reservationStatus');
const BookingService = require('../src/services/booking.service');

test('dispatchAfterContactVerified marks metadata and skips duplicate dispatch', async () => {
  const metadataUpdates = [];
  const bookingRow = {
    id: 5,
    contact_status: CONTACT_STATUS.VERIFIED,
    status: BOOKING_STATUS.OPEN,
    metadata: JSON.stringify({}),
  };

  const pool = {
    async getConnection() {
      return {
        release() {},
      };
    },
  };

  const bookingRepository = {
    async findById(id) {
      return { ...bookingRow, id };
    },
    async findOpenDriverCallByBookingId(_conn, id) {
      return {
        id,
        booking_number: 'TX202608130020',
        contact_status: CONTACT_STATUS.VERIFIED,
        status: BOOKING_STATUS.OPEN,
        metadata: bookingRow.metadata,
        vehicle_type_id: 1,
        scheduled_pickup_at: '2026-08-13 09:00:00',
        total_amount: 1000,
        currency: 'THB',
        payment_method: 'PAY_DRIVER',
        is_urgent_request: 0,
        service_type_code: 'AIRPORT_PICKUP',
        service_type_name: 'Airport Pickup',
        vehicle_type_code: 'SEDAN',
        vehicle_type_name: 'Sedan',
        origin_address: 'BKK',
        destination_address: 'Hotel',
      };
    },
    async updateBookingFields(_conn, bookingId, fields) {
      metadataUpdates.push({ bookingId, metadata: fields.metadata });
      bookingRow.metadata = JSON.stringify(fields.metadata);
    },
  };

  const service = new BookingService(
    pool,
    bookingRepository,
    {},
    {},
    {},
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
  );

  service.getEligibleDriversForOpenBooking = async () => [{ id: 1, user_id: 2 }];
  service.mapEligibleDriversToTargets = (drivers) => drivers.map((d) => ({
    driverId: d.id,
    userId: d.user_id,
  }));
  service.buildOpenCallPayload = () => ({ bookingNumber: 'TX202608130020' });
  service.parseBookingMetadata = BookingService.prototype.parseBookingMetadata;
  service.isContactDispatchCompleted = BookingService.prototype.isContactDispatchCompleted;
  service.markContactDispatchCompleted = BookingService.prototype.markContactDispatchCompleted;
  let notificationCount = 0;
  service.dispatchOpenCallNotifications = async () => {
    notificationCount += 1;
  };
  service.dispatchUrgentCallNotifications = async () => {};

  const first = await service.dispatchAfterContactVerified(bookingRow);
  const second = await service.dispatchAfterContactVerified(bookingRow);

  assert.equal(first, true);
  assert.equal(second, false);
  assert.equal(metadataUpdates.length, 1);
  assert.equal(metadataUpdates[0].metadata.contactDispatchCompleted, true);
  assert.equal(notificationCount, 1);
});

test('needsContactDispatchRetry is true for verified open booking without dispatch marker', () => {
  delete require.cache[require.resolve('../src/services/booking.service')];
  const BookingServiceFresh = require('../src/services/booking.service');
  const service = new BookingServiceFresh({}, {}, {}, {}, {}, {}, null, null, null, null, null, null, null, null, null, null);

  assert.equal(
    service.needsContactDispatchRetry({
      contact_status: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: JSON.stringify({}),
    }),
    true,
  );
  assert.equal(
    service.needsContactDispatchRetry({
      contact_status: CONTACT_STATUS.VERIFIED,
      status: BOOKING_STATUS.OPEN,
      metadata: JSON.stringify({ contactDispatchCompleted: true }),
    }),
    false,
  );
});
