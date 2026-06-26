const express = require('express');
const adminPricingRoutes = require('./admin.pricing.routes');

const router = express.Router();

router.use(adminPricingRoutes);

// TODO: dashboard, bookings, drivers, golf, airports, users, chats, translations, settings

module.exports = router;
