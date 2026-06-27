const express = require('express');
const adminPricingRoutes = require('./admin.pricing.routes');
const adminDispatchRoutes = require('./admin.dispatch.routes');

const router = express.Router();

router.use(adminPricingRoutes);
router.use(adminDispatchRoutes);

// TODO: dashboard, golf, airports, users, chats, translations, settings

module.exports = router;
