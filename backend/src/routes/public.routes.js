const express = require('express');
const flightController = require('../controllers/flight.controller');

const router = express.Router();

router.get('/flights/search', flightController.searchFlights);

module.exports = router;
