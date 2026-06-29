const express = require('express');
const adminDashboardController = require('../controllers/adminDashboard.controller');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

router.get(
  '/dashboard/metrics',
  adminOnly,
  adminDashboardController.getMetrics,
);

module.exports = router;
