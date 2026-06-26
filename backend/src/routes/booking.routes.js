const express = require('express');
const bookingController = require('../controllers/booking.controller');
const pricingController = require('../controllers/pricing.controller');
const validate = require('../middlewares/validate.middleware');
const { optionalAuthMiddleware } = require('../middlewares/auth.middleware');
const { vehicleRecommendSchema, createBookingSchema } = require('../validators/booking.validator');
const { pricingCalculateSchema } = require('../validators/pricing.validator');

const router = express.Router();

router.post(
  '/vehicle/recommend',
  validate({ body: vehicleRecommendSchema }),
  bookingController.recommendVehicle,
);

router.post(
  '/pricing/calculate',
  validate({ body: pricingCalculateSchema }),
  pricingController.calculatePricing,
);

router.post(
  '/',
  optionalAuthMiddleware,
  validate({ body: createBookingSchema }),
  bookingController.createBooking,
);

module.exports = router;
