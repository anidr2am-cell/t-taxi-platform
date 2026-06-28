const express = require('express');
const placesController = require('../controllers/places.controller');

const router = express.Router();

router.get('/autocomplete', placesController.autocomplete);
router.get('/details', placesController.details);

module.exports = router;
