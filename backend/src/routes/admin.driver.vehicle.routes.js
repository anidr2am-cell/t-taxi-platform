const express = require('express');
const driverVehicleController = require('../controllers/driverVehicle.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  adminDriverVehicleListQuerySchema,
  adminDriverVehicleIdParamsSchema,
  adminDriverVehicleFileParamsSchema,
  adminDriverVehicleApproveSchema,
  adminDriverVehicleRejectSchema,
} = require('../validators/driverVehicle.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/driver-vehicles',
  adminOnly,
  validate({ query: adminDriverVehicleListQuerySchema }),
  driverVehicleController.listAdmin,
);

router.get(
  '/driver-vehicles/:id',
  adminOnly,
  validate({ params: adminDriverVehicleIdParamsSchema }),
  driverVehicleController.getAdminDetail,
);

router.get(
  '/driver-vehicles/:id/files/:fileId',
  adminOnly,
  validate({ params: adminDriverVehicleFileParamsSchema }),
  driverVehicleController.getAdminFile,
);

router.post(
  '/driver-vehicles/:id/approve',
  adminOnly,
  validate({
    params: adminDriverVehicleIdParamsSchema,
    body: adminDriverVehicleApproveSchema,
  }),
  driverVehicleController.approve,
);

router.post(
  '/driver-vehicles/:id/reject',
  adminOnly,
  validate({
    params: adminDriverVehicleIdParamsSchema,
    body: adminDriverVehicleRejectSchema,
  }),
  driverVehicleController.reject,
);

module.exports = router;
