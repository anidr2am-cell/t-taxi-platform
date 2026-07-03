const express = require('express');
const vehicleController = require('../controllers/vehicle.controller');

const router = express.Router();

router.get('/types', vehicleController.listTypes);

module.exports = router;
