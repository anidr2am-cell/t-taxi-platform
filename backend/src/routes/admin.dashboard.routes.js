const express = require('express');
const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const { getStatistics } = require('../services/adminStatistics.service');
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

router.get('/statistics', adminOnly, asyncHandler(async (req, res) => {
  res.set('Cache-Control', 'private, no-store');
  return success(res, await getStatistics(req.query.from, req.query.to));
}));

module.exports = router;
