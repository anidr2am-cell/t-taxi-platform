const express = require('express');
const adminFlightController = require('../controllers/adminFlight.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  adminFlightListQuerySchema,
  bookingIdParamsSchema,
} = require('../validators/adminFlight.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/flights',
  adminOnly,
  validate({ query: adminFlightListQuerySchema }),
  adminFlightController.listFlights,
);

router.get(
  '/flights/:bookingId',
  adminOnly,
  validate({ params: bookingIdParamsSchema }),
  adminFlightController.getFlightDetail,
);

router.post(
  '/flights/:bookingId/sync',
  adminOnly,
  validate({ params: bookingIdParamsSchema }),
  adminFlightController.syncFlight,
);

module.exports = router;
