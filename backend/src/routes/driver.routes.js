const express = require('express');
const driverController = require('../controllers/driver.controller');
const driverLocationController = require('../controllers/driverLocation.controller');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const validate = require('../middlewares/validate.middleware');
const createRateLimit = require('../middlewares/rateLimit.middleware');
const ROLES = require('../constants/roles');
const { locationUpdateSchema } = require('../validators/driverLocation.validator');

const router = express.Router();
const driverLocationRateLimit = createRateLimit({ windowMs: 60_000, max: 60 });

router.use(authMiddleware, roleMiddleware([ROLES.DRIVER]));

router.get('/status', driverController.getStatus);
router.post('/online', driverController.goOnline);
router.post('/offline', driverController.goOffline);
router.get('/calls/open', driverController.listOpenCalls);
router.post('/calls/:bookingNumber/claim', driverController.claimOpenCall);
router.get('/bookings/today', driverController.listTodayBookings);
router.post(
  '/location',
  driverLocationRateLimit,
  validate({ body: locationUpdateSchema }),
  driverLocationController.updateDriverLocation,
);
router.get('/rating-summary', require('../controllers/review.controller').getDriverRatingSummary);
router.get('/notifications', require('../controllers/notification.controller').listDriverNotifications);
router.get('/notifications/unread-count', require('../controllers/notification.controller').driverUnreadCount);
router.post('/notifications/:notificationId/read', require('../controllers/notification.controller').markDriverRead);
router.post('/notifications/read-all', require('../controllers/notification.controller').markDriverReadAll);
router.post('/bookings/:bookingNumber/start-route', driverController.startOnRoute);
router.post('/bookings/:bookingNumber/arrive', driverController.markArrived);
router.post('/bookings/:bookingNumber/mark-picked-up', driverController.markPickedUp);
router.post('/bookings/:bookingNumber/end-trip', driverController.endTrip);
router.post('/bookings/:bookingNumber/complete', driverController.completeTrip);
router.post('/bookings/:bookingNumber/release', driverController.releaseAssignment);
// Legacy QR scan routes — compatibility only; button trip flow must not call these.
router.post('/bookings/:bookingNumber/scan-boarding', driverController.scanBoarding);
router.post('/bookings/:bookingNumber/scan-dropoff', driverController.scanDropoff);
router.get('/bookings/:bookingNumber', driverController.getBookingDetail);

router.use('/settlements', require('./driver.settlement.routes'));

// TODO: online, offline, assignments, booking actions

module.exports = router;
