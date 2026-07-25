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
const chatController = require("../controllers/chat.controller");
const {
  chatMessageListQuerySchema,
  sendChatMessageSchema,
  markChatReadSchema,
} = require("../validators/chat.validator");
const {
  submitUrgentDecisionSchema,
} = require("../validators/urgentNegotiation.validator");

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

router.get(
  "/:bookingNumber/chat",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }),
  chatController.getBookingChat,
);

router.get(
  "/:bookingNumber/chat/messages",
  optionalAuthMiddleware,
  validate({
    params: bookingNumberParamsSchema,
    query: chatMessageListQuerySchema,
  }),
  chatController.listBookingChatMessages,
);

router.post(
  "/:bookingNumber/chat/messages",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema, body: sendChatMessageSchema }),
  chatController.sendBookingChatMessage,
);

router.post(
  "/:bookingNumber/pickup-alert",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema }),
  chatController.sendBookingPickupAlert,
);

router.post(
  "/:bookingNumber/chat/read",
  optionalAuthMiddleware,
  validate({ params: bookingNumberParamsSchema, body: markChatReadSchema }),
  chatController.markBookingChatRead,
);

module.exports = router;
