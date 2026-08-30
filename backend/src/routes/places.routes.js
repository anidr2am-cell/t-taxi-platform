const express = require('express');
const placesController = require('../controllers/places.controller');
const validate = require('../middlewares/validate.middleware');
const {
  placesAutocompleteRateLimit,
  placesDetailsRateLimit,
} = require('../middlewares/placesRateLimit.middleware');
const {
  placesAutocompleteQuerySchema,
  placesDetailsQuerySchema,
} = require('../validators/places.validator');

const router = express.Router();

router.get(
  '/autocomplete',
  placesAutocompleteRateLimit,
  validate({ query: placesAutocompleteQuerySchema }),
  placesController.autocomplete,
);
router.get(
  '/details',
  placesDetailsRateLimit,
  validate({ query: placesDetailsQuerySchema }),
  placesController.details,
);

module.exports = router;
