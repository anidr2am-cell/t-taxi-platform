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
const BookingAssignmentReopenService = require('../src/services/bookingAssignmentReopen.service');
const ERROR_CODES = require('../src/constants/errorCodes');

test('reopen broadcast blocked when contact is not verified and flag enabled', async () => {
  const conn = {};
  const booking = {
    id: 1,
    booking_number: 'TX202608130010',
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    contact_status: CONTACT_STATUS.PENDING,
    vehicle_type_id: 2,
    scheduled_pickup_at: '2026-08-13 09:00:00',
    is_urgent_request: 0,
  };

  const service = new BookingAssignmentReopenService(
    {
      async deactivateAssignment() {
        return true;
      },
      async reopenAfterDriverRelease() {},
      async insertStatusLog() {},
      async insertActivityLog() {},
      async findOpenDriverCallByBookingId() {
        return {
          booking_number: booking.booking_number,
          status: BOOKING_STATUS.OPEN,
        };
      },
    },
    {
      async listEligibleForOpenBooking() {
        return [];
      },
    },
  );

  await assert.rejects(
    () => service.reopenAssignedBookingInTransaction(conn, {
      booking,
      bookingNumber: booking.booking_number,
      activeAssignment: { id: 5 },
      actorUserId: 1,
      actorRole: 'ADMIN',
      assignmentReleaseMarker: 'ADMIN_RELEASED',
      assignmentSocketReasonCode: 'ADMIN_RELEASED',
      statusLogMemo: 'test',
      activityType: 'DRIVER_UNASSIGNED',
      activityDescription: 'test',
      activityPayload: {},
      mapOpenCall: () => ({}),
    }),
    (err) => err.errorCode === ERROR_CODES.BOOKING_CONTACT_NOT_VERIFIED,
  );
});

test('reopen broadcast allowed when contact verified and flag enabled', async () => {
  const conn = {};
  const booking = {
    id: 1,
    booking_number: 'TX202608130011',
    status: BOOKING_STATUS.DRIVER_ASSIGNED,
    contact_status: CONTACT_STATUS.VERIFIED,
    vehicle_type_id: 2,
    scheduled_pickup_at: '2026-08-13 09:00:00',
    is_urgent_request: 0,
  };

  const service = new BookingAssignmentReopenService(
    {
      async deactivateAssignment() {
        return true;
      },
      async reopenAfterDriverRelease() {},
      async insertStatusLog() {},
      async insertActivityLog() {},
      async findOpenDriverCallByBookingId() {
        return {
          booking_number: booking.booking_number,
          status: BOOKING_STATUS.OPEN,
        };
      },
    },
    {
      async listEligibleForOpenBooking() {
        return [{ id: 2, user_id: 9 }];
      },
    },
  );

  const result = await service.reopenAssignedBookingInTransaction(conn, {
    booking,
    bookingNumber: booking.booking_number,
    activeAssignment: { id: 5 },
    actorUserId: 1,
    actorRole: 'ADMIN',
    assignmentReleaseMarker: 'ADMIN_RELEASED',
    assignmentSocketReasonCode: 'ADMIN_RELEASED',
    statusLogMemo: 'test',
    activityType: 'DRIVER_UNASSIGNED',
    activityDescription: 'test',
    activityPayload: {},
    mapOpenCall: () => ({ bookingNumber: booking.booking_number }),
  });

  assert.equal(result.bookingNumber, booking.booking_number);
  assert.equal(result.openCallTargets.length, 1);
});
