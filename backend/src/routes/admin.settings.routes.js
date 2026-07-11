const express = require('express');
const controller = require('../controllers/platformSettings.controller');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const { upload } = require('../config/multer');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get('/settings', adminOnly, controller.getAdmin);
router.put('/settings', adminOnly, controller.updateAdmin);
router.post('/settings/images/:kind', adminOnly, upload.single('file'), controller.uploadImage);

module.exports = router;
