const express = require('express');
const adminController = require('../controllers/admin.controller');
const driverLocationController = require('../controllers/driverLocation.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  adminBookingListQuerySchema,
  bookingNumberParamsSchema,
  assignDriverSchema,
  reassignDriverSchema,
} = require('../validators/admin.validator');
const { adminDriverLocationQuerySchema } = require('../validators/driverLocation.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/bookings',
  adminOnly,
  validate({ query: adminBookingListQuerySchema }),
  adminController.listBookings,
);

router.get(
  '/bookings/:bookingNumber',
  adminOnly,
  validate({ params: bookingNumberParamsSchema }),
  adminController.getBookingDetail,
);

router.post(
  '/bookings/:bookingNumber/assign-driver',
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: assignDriverSchema }),
  adminController.assignDriver,
);

router.post(
  '/bookings/:bookingNumber/reassign-driver',
  adminOnly,
  validate({ params: bookingNumberParamsSchema, body: reassignDriverSchema }),
  adminController.reassignDriver,
);

router.get(
  '/drivers',
  adminOnly,
  adminController.listDrivers,
);

router.get(
  '/drivers/locations',
  adminOnly,
  validate({ query: adminDriverLocationQuerySchema }),
  driverLocationController.listAdminDriverLocations,
);

module.exports = router;
