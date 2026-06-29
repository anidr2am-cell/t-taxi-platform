const express = require('express');
const adminDashboardRoutes = require('./admin.dashboard.routes');
const adminPricingRoutes = require('./admin.pricing.routes');
const adminDispatchRoutes = require('./admin.dispatch.routes');
const adminSettlementRoutes = require('./admin.settlement.routes');
const adminReviewRoutes = require('./admin.review.routes');
const adminNotificationRoutes = require('./admin.notification.routes');
const adminChatRoutes = require('./admin.chat.routes');

const router = express.Router();

router.use(adminDashboardRoutes);
router.use(adminPricingRoutes);
router.use(adminDispatchRoutes);
router.use(adminSettlementRoutes);
router.use(adminReviewRoutes);
router.use(adminNotificationRoutes);
router.use(adminChatRoutes);

// TODO: golf, airports, users, translations, settings

module.exports = router;
