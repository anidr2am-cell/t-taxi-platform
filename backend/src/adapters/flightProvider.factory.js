const AeroDataBoxFlightAdapter = require('../adapters/aeroDataBoxFlight.adapter');

function createFlightProviderAdapter(config, httpClient) {
  return new AeroDataBoxFlightAdapter(config, httpClient);
}

module.exports = {
  createFlightProviderAdapter,
};
