const express = require('express');
const driverController = require('../controllers/driver.controller');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');

const router = express.Router();

router.use(authMiddleware, roleMiddleware([ROLES.DRIVER]));

router.get('/bookings/today', driverController.listTodayBookings);
router.post('/bookings/:bookingNumber/arrive', driverController.markArrived);
router.post('/bookings/:bookingNumber/scan-boarding', driverController.scanBoarding);
router.post('/bookings/:bookingNumber/scan-dropoff', driverController.scanDropoff);
router.get('/bookings/:bookingNumber', driverController.getBookingDetail);

// TODO: online, offline, location, assignments, booking actions

module.exports = router;
