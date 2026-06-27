const express = require('express');
const adminPricingRoutes = require('./admin.pricing.routes');
const adminDispatchRoutes = require('./admin.dispatch.routes');
const adminSettlementRoutes = require('./admin.settlement.routes');
const adminReviewRoutes = require('./admin.review.routes');

const router = express.Router();

router.use(adminPricingRoutes);
router.use(adminDispatchRoutes);
router.use(adminSettlementRoutes);
router.use(adminReviewRoutes);

// TODO: dashboard, golf, airports, users, chats, translations, settings

module.exports = router;
