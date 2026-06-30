const express = require('express');
const notificationController = require('../controllers/notification.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  registerNotificationDeviceSchema,
  notificationDeviceParamsSchema,
} = require('../validators/notification.validator');

const router = express.Router();

router.use(authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN, ROLES.DRIVER]));

router.get('/devices', notificationController.listAuthenticatedDevices);

router.post(
  '/devices',
  validate({ body: registerNotificationDeviceSchema }),
  notificationController.registerAuthenticatedDevice,
);

router.delete(
  '/devices/:deviceId',
  validate({ params: notificationDeviceParamsSchema }),
  notificationController.deleteAuthenticatedDevice,
);

module.exports = router;
