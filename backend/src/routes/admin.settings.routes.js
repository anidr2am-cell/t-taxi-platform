const express = require('express');
const controller = require('../controllers/platformSettings.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const { upload } = require('../config/multer');
const {
  adminSettingsUpdateSchema,
  adminSettingsImageKindParamsSchema,
} = require('../validators/platformSettings.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get('/settings', adminOnly, controller.getAdmin);
router.put(
  '/settings',
  adminOnly,
  validate({ body: adminSettingsUpdateSchema }),
  controller.updateAdmin,
);
router.post(
  '/settings/images/:kind',
  adminOnly,
  validate({ params: adminSettingsImageKindParamsSchema }),
  upload.single('file'),
  controller.handleUploadError,
  controller.uploadImage,
);

module.exports = router;
