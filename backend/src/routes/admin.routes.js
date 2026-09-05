const express = require('express');
const adminDashboardRoutes = require('./admin.dashboard.routes');
const adminPricingRoutes = require('./admin.pricing.routes');
const adminDispatchRoutes = require('./admin.dispatch.routes');
const adminSettlementRoutes = require('./admin.settlement.routes');
const adminReviewRoutes = require('./admin.review.routes');
const adminNotificationRoutes = require('./admin.notification.routes');
const adminFlightRoutes = require('./admin.flight.routes');
const adminDriverApplicationRoutes = require('./admin.driver.application.routes');
const adminDriverVehicleRoutes = require('./admin.driver.vehicle.routes');
const adminSettingsRoutes = require('./admin.settings.routes');
const adminCouponRoutes = require('./admin.coupon.routes');

const router = express.Router();

router.use(adminDashboardRoutes);
router.use(adminPricingRoutes);
router.use(adminDispatchRoutes);
router.use(adminSettlementRoutes);
router.use(adminReviewRoutes);
router.use(adminNotificationRoutes);
router.use(adminFlightRoutes);
router.use(adminDriverApplicationRoutes);
router.use(adminDriverVehicleRoutes);
router.use(adminSettingsRoutes);
router.use(adminCouponRoutes);

// TODO: golf, airports, users, translations, settings

module.exports = router;
