const express = require('express');
const flightController = require('../controllers/flight.controller');
const bookingController = require('../controllers/booking.controller');
const validate = require('../middlewares/validate.middleware');
const createRateLimit = require('../middlewares/rateLimit.middleware');
const { guestBookingLookupSchema } = require('../validators/booking.validator');

const router = express.Router();
const bookingLookupRateLimit = createRateLimit({ windowMs: 60_000, max: 10 });

router.get('/flights/search', flightController.searchFlights);
router.post(
  '/bookings/lookup',
  bookingLookupRateLimit,
  validate({ body: guestBookingLookupSchema }),
  bookingController.lookupGuestBooking,
);

module.exports = router;
