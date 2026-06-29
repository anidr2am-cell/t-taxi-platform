const AviationstackFlightAdapter = require('../adapters/aviationstackFlight.adapter');

function createFlightProviderAdapter(config, httpClient) {
  return new AviationstackFlightAdapter(config, httpClient);
}

module.exports = {
  createFlightProviderAdapter,
};
