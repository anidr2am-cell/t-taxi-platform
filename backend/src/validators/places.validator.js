const Joi = require('joi');

const PLACES_INPUT_MAX_LENGTH = 200;

const placesAutocompleteQuerySchema = Joi.object({
  input: Joi.string().trim().min(2).max(PLACES_INPUT_MAX_LENGTH).required(),
  language: Joi.string().trim().lowercase().pattern(/^[a-z]{2}$/).default('en'),
});

const placesDetailsQuerySchema = Joi.object({
  placeId: Joi.string().trim().min(1).max(PLACES_INPUT_MAX_LENGTH).required(),
  language: Joi.string().trim().lowercase().pattern(/^[a-z]{2}$/).default('en'),
});

module.exports = {
  PLACES_INPUT_MAX_LENGTH,
  placesAutocompleteQuerySchema,
  placesDetailsQuerySchema,
};
