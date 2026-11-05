const express = require("express");
const bookingController = require("../controllers/booking.controller");
const pricingController = require("../controllers/pricing.controller");
const validate = require("../middlewares/validate.middleware");
const reviewController = require("../controllers/review.controller");
const notificationController = require("../controllers/notification.controller");
const {
  authMiddleware,
  optionalAuthMiddleware,
} = require("../middlewares/auth.middleware");
const {
  bookingNumberParamsSchema,
  submitReviewSchema,
} = require("../validators/review.validator");
const roleMiddleware = require("../middlewares/role.middleware");
const ROLES = require("../constants/roles");
const {
  vehicleRecommendSchema,
  createBookingSchema,
  updateBookingStatusSchema,
  cancelBookingSchema,
} = require("../validators/booking.validator");
const { pricingCalculateSchema } = require("../validators/pricing.validator");
const {
  notificationListQuerySchema,
} = require("../validators/notification.validator");
const {
  submitUrgentDecisionSchema,
} = require("../validators/urgentNegotiation.validator");
const bookingContactConnectionController = require("../controllers/bookingContactConnection.controller");
const {
  startContactConnectionSchema,
} = require("../validators/bookingContactConnection.validator");

const router = express.Router();

router.post(
  "/vehicle/recommend",
  validate({ body: vehicleRecommendSchema }),
  bookingController.recommendVehicle,
);

router.post(
  "/pricing/calculate",
  validate({ body: pricingCalculateSchema }),
  pricingController.calculatePricing,
);

router.get(
  "/contact-channels/public",
  bookingContactConnectionController.getContactChannelSettings,
);

router.get(
  "/:bookingNumber/contact-connection",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }),
  bookingContactConnectionController.getContactConnection,
);

router.post(
  "/:bookingNumber/contact-connections",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema, body: startContactConnectionSchema }),
  bookingContactConnectionController.startContactConnection,
);

router.post(
  "/:bookingNumber/contact-connections/confirm-sent",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }),
  bookingContactConnectionController.confirmContactSent,
);

router.post(
  "/",
  optionalAuthMiddleware,
  validate({ body: createBookingSchema }),
  bookingController.createBooking,
);

router.patch(
  "/:bookingNumber/status",
  authMiddleware,
  roleMiddleware([
    ROLES.CUSTOMER,
    ROLES.DRIVER,
    ROLES.ADMIN,
    ROLES.SUPER_ADMIN,
  ]),
  validate({ body: updateBookingStatusSchema }),
  bookingController.updateBookingStatus,
);

router.post(
  "/:bookingNumber/cancel",
  optionalAuthMiddleware,
  validate({ body: cancelBookingSchema }),
  bookingController.cancelBooking,
);

router.post(
  "/:bookingNumber/urgent-decision",
  optionalAuthMiddleware,
  validate({ body: submitUrgentDecisionSchema }),
  bookingController.submitUrgentDecision,
);

router.get(
  "/:bookingNumber/urgent-negotiation",
  optionalAuthMiddleware,
  bookingController.getUrgentNegotiation,
);

// Legacy QR issue routes — compatibility only; customer UI must not call these.
router.post(
  "/:bookingNumber/boarding-qr/issue",
  optionalAuthMiddleware,
  bookingController.issueBoardingQr,
);

router.post(
  "/:bookingNumber/dropoff-qr/issue",
  optionalAuthMiddleware,
  bookingController.issueDropoffQr,
);

router.get(
  "/:bookingNumber/review",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }),
  reviewController.getBookingReview,
);

router.post(
  "/:bookingNumber/review",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema, body: submitReviewSchema }),
  reviewController.submitBookingReview,
);

router.get(
  "/:bookingNumber/notifications",
  optionalAuthMiddleware,
  validate({
    params: bookingNumberParamsSchema,
    query: notificationListQuerySchema,
  }),
  notificationController.listBookingNotifications,
);

// Opening a link or mail preview must never notify a driver: only explicit POST does.
const gateArrival = require('../controllers/customerGateArrival.controller');
const gateArrivalLimit = require('../middlewares/rateLimit.middleware')({ max:30 });
router.get('/:bookingNumber/gate-arrival', gateArrivalLimit, optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }), gateArrival.status);
router.post('/:bookingNumber/gate-arrival', gateArrivalLimit, optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }), gateArrival.send);

module.exports = router;
