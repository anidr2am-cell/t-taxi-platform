const express = require('express');
const adminPricingRoutes = require('./admin.pricing.routes');
const adminDispatchRoutes = require('./admin.dispatch.routes');
const adminSettlementRoutes = require('./admin.settlement.routes');
const adminReviewRoutes = require('./admin.review.routes');
const adminNotificationRoutes = require('./admin.notification.routes');

const router = express.Router();

router.use(adminPricingRoutes);
router.use(adminDispatchRoutes);
router.use(adminSettlementRoutes);
router.use(adminReviewRoutes);
router.use(adminNotificationRoutes);

// TODO: dashboard, golf, airports, users, chats, translations, settings

module.exports = router;
