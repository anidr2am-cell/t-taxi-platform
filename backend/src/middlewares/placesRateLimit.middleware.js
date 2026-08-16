const createRateLimit = require('./rateLimit.middleware');

const ONE_MINUTE_MS = 60 * 1000;

const placesAutocompleteRateLimit = createRateLimit({
  windowMs: ONE_MINUTE_MS,
  max: 60,
  keyFn: (req) => `places:autocomplete:ip:${req.ip}`,
});

const placesDetailsRateLimit = createRateLimit({
  windowMs: ONE_MINUTE_MS,
  max: 30,
  keyFn: (req) => `places:details:ip:${req.ip}`,
});

module.exports = {
  placesAutocompleteRateLimit,
  placesDetailsRateLimit,
};
