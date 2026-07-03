const express = require('express');
const driverApplicationController = require('../controllers/driverApplication.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  adminDriverApplicationListQuerySchema,
  adminDriverApplicationIdParamsSchema,
  adminDriverApplicationApproveSchema,
  adminDriverApplicationRejectSchema,
} = require('../validators/driverApplication.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/driver-applications',
  adminOnly,
  validate({ query: adminDriverApplicationListQuerySchema }),
  driverApplicationController.listAdmin,
);

router.get(
  '/driver-applications/:id',
  adminOnly,
  validate({ params: adminDriverApplicationIdParamsSchema }),
  driverApplicationController.getAdminDetail,
);

router.get(
  '/driver-applications/:id/files/:fileId',
  adminOnly,
  driverApplicationController.getAdminFile,
);

router.post(
  '/driver-applications/:id/approve',
  adminOnly,
  validate({
    params: adminDriverApplicationIdParamsSchema,
    body: adminDriverApplicationApproveSchema,
  }),
  driverApplicationController.approve,
);

router.post(
  '/driver-applications/:id/reject',
  adminOnly,
  validate({
    params: adminDriverApplicationIdParamsSchema,
    body: adminDriverApplicationRejectSchema,
  }),
  driverApplicationController.reject,
);

module.exports = router;
