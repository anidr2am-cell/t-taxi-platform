const express = require('express');
const driverController = require('../controllers/driver.controller');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');

const router = express.Router();

router.use(authMiddleware, roleMiddleware([ROLES.DRIVER]));

router.get('/bookings/today', driverController.listTodayBookings);
router.get('/rating-summary', require('../controllers/review.controller').getDriverRatingSummary);
router.get('/notifications', require('../controllers/notification.controller').listDriverNotifications);
router.get('/notifications/unread-count', require('../controllers/notification.controller').driverUnreadCount);
router.post('/notifications/:notificationId/read', require('../controllers/notification.controller').markDriverRead);
router.post('/notifications/read-all', require('../controllers/notification.controller').markDriverReadAll);
router.post('/bookings/:bookingNumber/arrive', driverController.markArrived);
router.post('/bookings/:bookingNumber/scan-boarding', driverController.scanBoarding);
router.post('/bookings/:bookingNumber/scan-dropoff', driverController.scanDropoff);
router.get('/bookings/:bookingNumber', driverController.getBookingDetail);

router.use('/settlements', require('./driver.settlement.routes'));

// TODO: online, offline, location, assignments, booking actions

module.exports = router;
