/**
 * routes/index.js — Mount all API route modules
 *
 * 새 feature 추가 시:
 * 1. routes/booking.routes.js 생성
 * 2. controllers/booking.controller.js 생성
 * 3. 여기에 router.use('/bookings', bookingRoutes) 등록
 */
const express = require('express');
const healthRoutes = require('./health.routes');
const authRoutes = require('./auth.routes');
const customerRoutes = require('./customer.routes');
const bookingRoutes = require('./booking.routes');
const driverRoutes = require('./driver.routes');
const vehicleRoutes = require('./vehicle.routes');
const airportRoutes = require('./airport.routes');
const golfRoutes = require('./golf.routes');
const golfRegionsRoutes = require('./golf-regions.routes');
const chatRoutes = require('./chat.routes');
const notificationRoutes = require('./notification.routes');
const adminRoutes = require('./admin.routes');
const settingsRoutes = require('./settings.routes');
const translationRoutes = require('./translation.routes');
const placesRoutes = require('./places.routes');
const flightsRoutes = require('./flights.routes');
const publicRoutes = require('./public.routes');

const router = express.Router();

router.use('/health', healthRoutes);
router.use('/auth', authRoutes);
router.use('/customer', customerRoutes);
router.use('/bookings', bookingRoutes);
router.use('/driver', driverRoutes);
router.use('/vehicles', vehicleRoutes);
router.use('/airports', airportRoutes);
router.use('/golf-courses', golfRoutes);
router.use('/golf-regions', golfRegionsRoutes);
router.use('/chat', chatRoutes);
router.use('/notifications', notificationRoutes);
router.use('/admin', adminRoutes);
router.use('/settings', settingsRoutes);
router.use('/translations', translationRoutes);
router.use('/places', placesRoutes);
router.use('/flights', flightsRoutes);
router.use('/public', publicRoutes);

module.exports = router;
