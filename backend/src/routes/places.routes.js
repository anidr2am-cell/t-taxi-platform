const express = require('express');
const placesController = require('../controllers/places.controller');
const {
  placesAutocompleteRateLimit,
  placesDetailsRateLimit,
} = require('../middlewares/placesRateLimit.middleware');

const router = express.Router();

router.get('/autocomplete', placesAutocompleteRateLimit, placesController.autocomplete);
router.get('/details', placesDetailsRateLimit, placesController.details);

module.exports = router;
