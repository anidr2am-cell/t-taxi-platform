const express = require('express');
const bookingController = require('../controllers/booking.controller');
const pricingController = require('../controllers/pricing.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware, optionalAuthMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  vehicleRecommendSchema,
  createBookingSchema,
  updateBookingStatusSchema,
} = require('../validators/booking.validator');
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

router.patch(
  '/:bookingNumber/status',
  authMiddleware,
  roleMiddleware([ROLES.CUSTOMER, ROLES.DRIVER, ROLES.ADMIN, ROLES.SUPER_ADMIN]),
  validate({ body: updateBookingStatusSchema }),
  bookingController.updateBookingStatus,
);

router.post(
  '/:bookingNumber/dropoff-qr/issue',
  optionalAuthMiddleware,
  bookingController.issueDropoffQr,
);

module.exports = router;
