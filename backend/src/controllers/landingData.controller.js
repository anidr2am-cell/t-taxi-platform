const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const container = require('../helpers/container');
const LandingDataService = require('../services/landingData.service');
let service;
exports.get = asyncHandler(async (_req, res) => {
  service ||= new LandingDataService(Object.fromEntries(
    ['routeRepository', 'vehicleRepository', 'pricingService', 'platformSettingsService']
      .map(key => [key, container.get(key)]),
  ));
  const data = await service.get();
  res.set('Cache-Control', 'public, max-age=300');
  return success(res, data, 'OK');
});
