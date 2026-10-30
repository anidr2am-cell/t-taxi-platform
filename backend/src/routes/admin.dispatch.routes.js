const express = require("express");
const adminController = require("../controllers/admin.controller");
const driverLocationController = require("../controllers/driverLocation.controller");
const validate = require("../middlewares/validate.middleware");
const { authMiddleware } = require("../middlewares/auth.middleware");
const roleMiddleware = require("../middlewares/role.middleware");
const ROLES = require("../constants/roles");
const {
  adminBookingListQuerySchema,
  bookingNumberParamsSchema,
  assignDriverSchema,
  reassignDriverSchema,
  unassignDriverSchema,
  autoAssignDriverSchema,
  qrReissueSchema,
  adminBookingNotesQuerySchema,
  createAdminBookingNoteSchema,
  processBookingNoShowSchema,
  archiveBookingsSchema,
  archiveDriversSchema,
  driverIdParamsSchema,
  adminManualBookingCreateSchema,
  adminManualBookingUpdateSchema,
  adminManualBookingCancelSchema,
  adminListDriversQuerySchema,
  driverSuspensionReasonSchema,
} = require("../validators/admin.validator");
const {
  adminDriverLocationQuerySchema,
} = require("../validators/driverLocation.validator");

const router = express.Router();
const adminOnly = [
  authMiddleware,
  roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN]),
];

const Joi = require('joi');
const { LOCALES, CHANNELS } = require('../utils/reviewRequest.util');
const { success } = require('../utils/apiResponse');
const asyncHandler = require('../utils/asyncHandler');
const container = require('../helpers/container');
const receiptEmailInput=Joi.object({email:Joi.string().trim().email({tlds:{allow:false}}).max(254).required(),locale:Joi.string().valid(...LOCALES).required()}).unknown(false);
router.get('/bookings/:bookingNumber/receipt-email',adminOnly,validate({params:bookingNumberParamsSchema}),
  asyncHandler(async(req,res)=>success(res,await container.get('adminReceiptEmailService').get(req.params.bookingNumber,req.user))));
router.post('/bookings/:bookingNumber/receipt-email/preview',adminOnly,validate({params:bookingNumberParamsSchema,body:receiptEmailInput}),
  asyncHandler(async(req,res)=>success(res,await container.get('adminReceiptEmailService').preview(req.params.bookingNumber,req.body,req.user))));
router.post('/bookings/:bookingNumber/receipt-email/send',adminOnly,validate({params:bookingNumberParamsSchema,body:receiptEmailInput.keys({previewHash:Joi.string().hex().length(64).required(),confirmed:Joi.boolean().valid(true).required()})}),
  asyncHandler(async(req,res)=>success(res,await container.get('adminReceiptEmailService').send(req.params.bookingNumber,req.body,req.user))));

router.get('/bookings/:bookingNumber/review-request', adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  asyncHandler(async (req, res) => success(res, await container.get('reviewRequestService').get(req.params.bookingNumber))));
router.post('/bookings/:bookingNumber/review-request', adminOnly,
  validate({ params: bookingNumberParamsSchema, body: Joi.object({
    action: Joi.string().valid('COPY', 'SENT', 'OPT_OUT').required(),
    locale: Joi.string().valid(...LOCALES).when('action', { is: 'OPT_OUT', then: Joi.optional(), otherwise: Joi.required() }),
    channel: Joi.string().valid(...CHANNELS).when('action', { is: 'SENT', then: Joi.required(), otherwise: Joi.forbidden() }),
    confirmResend: Joi.boolean().optional(),
    optedOut: Joi.boolean().when('action', { is: 'OPT_OUT', then: Joi.required(), otherwise: Joi.forbidden() }),
  }).unknown(false) }),
  asyncHandler(async (req, res) => success(res, await container.get('reviewRequestService').update(req.params.bookingNumber, req.body, req.user))));

router.get("/bookings/summary", adminOnly, adminController.getBookingsSummary);

router.post(
  "/bookings/manual",
  adminOnly,
  validate({ body: adminManualBookingCreateSchema }),
  adminController.createManualBooking,
);

router.patch(
  "/bookings/:bookingNumber/manual",
  adminOnly,
  validate({
    params: bookingNumberParamsSchema,
    body: adminManualBookingUpdateSchema,
  }),
  adminController.updateManualBooking,
);

router.post(
  "/bookings/:bookingNumber/manual/cancel",
  adminOnly,
  validate({
    params: bookingNumberParamsSchema,
    body: adminManualBookingCancelSchema,
  }),
  adminController.cancelManualBooking,
);

router.get(
  "/bookings",
  adminOnly,
  validate({ query: adminBookingListQuerySchema }),
  adminController.listBookings,
);

router.get(
  "/bookings/:bookingNumber",
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  adminController.getBookingDetail,
);

router.post(
  "/bookings/archive",
  adminOnly,
  validate({ body: archiveBookingsSchema }),
  adminController.archiveBookings,
);

router.post(
  "/bookings/restore",
  adminOnly,
  validate({ body: archiveBookingsSchema }),
  adminController.restoreBookings,
);

router.get(
  "/bookings/:bookingNumber/notes",
  adminOnly,
  validate({
    params: bookingNumberParamsSchema,
    query: adminBookingNotesQuerySchema,
  }),
  adminController.listBookingNotes,
);

router.post(
  "/bookings/:bookingNumber/notes",
  adminOnly,
  validate({
    params: bookingNumberParamsSchema,
    body: createAdminBookingNoteSchema,
  }),
  adminController.createBookingNote,
);

router.post(
  "/bookings/:bookingNumber/no-show",
  adminOnly,
  validate({
    params: bookingNumberParamsSchema,
    body: processBookingNoShowSchema,
  }),
  adminController.processBookingNoShow,
);

router.post(
  "/bookings/:bookingNumber/assign-driver",
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: assignDriverSchema }),
  adminController.assignDriver,
);

router.post(
  "/bookings/:bookingNumber/reassign-driver",
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: reassignDriverSchema }),
  adminController.reassignDriver,
);

router.post(
  "/bookings/:bookingNumber/unassign-driver",
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: unassignDriverSchema }),
  adminController.unassignDriver,
);

router.post(
  "/bookings/:bookingNumber/complete-trip",
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  adminController.completeActiveTrip,
);

router.get(
  "/bookings/:bookingNumber/driver-candidates",
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  adminController.getDriverCandidates,
);

router.post(
  "/bookings/:bookingNumber/auto-assign",
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: autoAssignDriverSchema }),
  adminController.autoAssignDriver,
);

router.post(
  "/bookings/:bookingNumber/qr/reissue",
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: qrReissueSchema }),
  adminController.reissueQr,
);

router.get(
  "/drivers",
  adminOnly,
  validate({ query: adminListDriversQuerySchema }),
  adminController.listDrivers,
);

router.post(
  "/drivers/archive",
  adminOnly,
  validate({ body: archiveDriversSchema }),
  adminController.archiveDrivers,
);

router.post(
  "/drivers/:id/restore",
  adminOnly,
  validate({ params: driverIdParamsSchema }),
  adminController.restoreDriver,
);

router.get(
  "/drivers/:id/deletion-preview",
  adminOnly,
  validate({ params: driverIdParamsSchema }),
  adminController.getDriverDeletionPreview,
);
router.get(
  "/drivers/:id/suspension-preview",
  adminOnly,
  validate({ params: driverIdParamsSchema }),
  adminController.getDriverSuspensionPreview,
);
router.get(
  "/drivers/:id/suspension-history",
  adminOnly,
  validate({ params: driverIdParamsSchema }),
  adminController.getDriverSuspensionHistory,
);
router.post(
  "/drivers/:id/suspend",
  adminOnly,
  validate({
    params: driverIdParamsSchema,
    body: driverSuspensionReasonSchema,
  }),
  adminController.suspendDriver,
);
router.post(
  "/drivers/:id/unsuspend",
  adminOnly,
  validate({
    params: driverIdParamsSchema,
    body: driverSuspensionReasonSchema,
  }),
  adminController.unsuspendDriver,
);

router.get(
  "/drivers/locations",
  adminOnly,
  validate({ query: adminDriverLocationQuerySchema }),
  driverLocationController.listAdminDriverLocations,
);

const bookingContactConnectionController = require("../controllers/bookingContactConnection.controller");

router.post(
  "/bookings/:bookingNumber/contact/verify",
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  bookingContactConnectionController.adminVerifyContact,
);

router.post(
  "/bookings/:bookingNumber/contact/dispatch-retry",
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  bookingContactConnectionController.adminRetryContactDispatch,
);

module.exports = router;
