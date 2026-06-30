const express = require('express');
const flightController = require('../controllers/flight.controller');
const bookingController = require('../controllers/booking.controller');
const notificationController = require('../controllers/notification.controller');
const validate = require('../middlewares/validate.middleware');
const createRateLimit = require('../middlewares/rateLimit.middleware');
const { guestBookingLookupSchema } = require('../validators/booking.validator');
const {
  registerNotificationDeviceSchema,
  guestNotificationDeviceParamsSchema,
} = require('../validators/notification.validator');

const router = express.Router();
const bookingLookupRateLimit = createRateLimit({ windowMs: 60_000, max: 10 });
const guestDeviceRateLimit = createRateLimit({ windowMs: 60_000, max: 10 });

router.get('/flights/search', flightController.searchFlights);
router.post(
  '/bookings/lookup',
  bookingLookupRateLimit,
  validate({ body: guestBookingLookupSchema }),
  bookingController.lookupGuestBooking,
);

router.post(
  '/bookings/:bookingId/notification-devices',
  guestDeviceRateLimit,
  validate({
    params: guestNotificationDeviceParamsSchema,
    body: registerNotificationDeviceSchema,
  }),
  notificationController.registerGuestDevice,
);

router.delete(
  '/bookings/:bookingId/notification-devices/:deviceId',
  guestDeviceRateLimit,
  validate({ params: guestNotificationDeviceParamsSchema }),
  notificationController.deleteGuestDevice,
);

module.exports = router;
