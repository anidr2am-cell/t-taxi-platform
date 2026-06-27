const express = require('express');
const bookingController = require('../controllers/booking.controller');
const pricingController = require('../controllers/pricing.controller');
const validate = require('../middlewares/validate.middleware');
const reviewController = require('../controllers/review.controller');
const { authMiddleware, optionalAuthMiddleware } = require('../middlewares/auth.middleware');
const {
  bookingNumberParamsSchema,
  submitReviewSchema,
} = require('../validators/review.validator');
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

router.get(
  '/:bookingNumber/review',
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }),
  reviewController.getBookingReview,
);

router.post(
  '/:bookingNumber/review',
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema, body: submitReviewSchema }),
  reviewController.submitBookingReview,
);

module.exports = router;
