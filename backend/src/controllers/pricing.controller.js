const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const HTTP_STATUS = require('../constants/httpStatus');
const container = require('../helpers/container');

const getPricingService = () => container.get('pricingService');
const getPricingAdminService = () => container.get('pricingAdminService');
const getRouteAdminService = () => container.get('routeAdminService');
const getVehiclePriceAdminService = () => container.get('vehiclePriceAdminService');
const getChargePolicyAdminService = () => container.get('chargePolicyAdminService');
const getCityTransferDistanceBandAdminService = () => (
  container.get('cityTransferDistanceBandAdminService')
);

const calculatePricing = asyncHandler(async (req, res) => {
  const data = await getPricingService().calculate(req.body);
  return success(res, data, 'OK');
});

const simulatePricing = asyncHandler(async (req, res) => {
  const data = await getPricingService().simulate(req.body);
  return success(res, data, 'OK');
});

const getPricingSummary = asyncHandler(async (req, res) => {
  const data = await getPricingAdminService().getSummary();
  return success(res, data, 'OK');
});

const listRoutes = asyncHandler(async (req, res) => {
  const data = await getRouteAdminService().list({
    includeInactive: Boolean(req.query.includeInactive),
  });
  return success(res, data, 'OK');
});

const getRoute = asyncHandler(async (req, res) => {
  const data = await getRouteAdminService().getById(Number(req.params.id));
  return success(res, data, 'OK');
});

const createRoute = asyncHandler(async (req, res) => {
  const data = await getRouteAdminService().create(req.body, req.user.id);
  return success(res, data, 'Route created', HTTP_STATUS.CREATED);
});

const updateRoute = asyncHandler(async (req, res) => {
  const data = await getRouteAdminService().update(
    Number(req.params.id),
    req.body,
    req.user.id,
  );
  return success(res, data, 'Route updated');
});

const deleteRoute = asyncHandler(async (req, res) => {
  await getRouteAdminService().delete(Number(req.params.id), req.user.id);
  return success(res, null, 'Route deleted');
});

const copyRoute = asyncHandler(async (req, res) => {
  const data = await getRouteAdminService().copy(
    Number(req.params.id),
    req.body,
    req.user.id,
  );
  return success(res, data, 'Route copied', HTTP_STATUS.CREATED);
});

const listVehiclePrices = asyncHandler(async (req, res) => {
  const data = await getVehiclePriceAdminService().list({
    routeId: req.query.routeId ? Number(req.query.routeId) : undefined,
    includeInactive: Boolean(req.query.includeInactive),
  });
  return success(res, data, 'OK');
});

const getVehiclePrice = asyncHandler(async (req, res) => {
  const data = await getVehiclePriceAdminService().getById(Number(req.params.id));
  return success(res, data, 'OK');
});

const createVehiclePrice = asyncHandler(async (req, res) => {
  const data = await getVehiclePriceAdminService().create(req.body, req.user.id);
  return success(res, data, 'Vehicle price created', HTTP_STATUS.CREATED);
});

const updateVehiclePrice = asyncHandler(async (req, res) => {
  const data = await getVehiclePriceAdminService().update(
    Number(req.params.id),
    req.body,
    req.user.id,
  );
  return success(res, data, 'Vehicle price updated');
});

const deleteVehiclePrice = asyncHandler(async (req, res) => {
  await getVehiclePriceAdminService().delete(Number(req.params.id), req.user.id);
  return success(res, null, 'Vehicle price deleted');
});

const listChargePolicies = asyncHandler(async (req, res) => {
  const data = await getChargePolicyAdminService().list({
    includeInactive: Boolean(req.query.includeInactive),
  });
  return success(res, data, 'OK');
});

const getChargePolicy = asyncHandler(async (req, res) => {
  const data = await getChargePolicyAdminService().getById(Number(req.params.id));
  return success(res, data, 'OK');
});

const createChargePolicy = asyncHandler(async (req, res) => {
  const data = await getChargePolicyAdminService().create(req.body, req.user.id);
  return success(res, data, 'Charge policy created', HTTP_STATUS.CREATED);
});

const updateChargePolicy = asyncHandler(async (req, res) => {
  const data = await getChargePolicyAdminService().update(
    Number(req.params.id),
    req.body,
    req.user.id,
  );
  return success(res, data, 'Charge policy updated');
});

const deleteChargePolicy = asyncHandler(async (req, res) => {
  await getChargePolicyAdminService().delete(Number(req.params.id), req.user.id);
  return success(res, null, 'Charge policy deleted');
});

const listCityTransferDistanceBands = asyncHandler(async (req, res) => {
  const data = await getCityTransferDistanceBandAdminService().list({
    includeInactive: Boolean(req.query.includeInactive),
  });
  return success(res, data, 'OK');
});

const updateCityTransferDistanceBand = asyncHandler(async (req, res) => {
  const data = await getCityTransferDistanceBandAdminService().update(
    Number(req.params.id),
    {
      sedanPrice: req.body.sedanPrice,
      suvPrice: req.body.suvPrice,
      vanPrice: req.body.vanPrice,
      isActive: req.body.isActive,
    },
  );
  return success(res, data, 'City transfer distance band updated');
});

module.exports = {
  calculatePricing,
  simulatePricing,
  getPricingSummary,
  listRoutes,
  getRoute,
  createRoute,
  updateRoute,
  deleteRoute,
  copyRoute,
  listVehiclePrices,
  getVehiclePrice,
  createVehiclePrice,
  updateVehiclePrice,
  deleteVehiclePrice,
  listChargePolicies,
  getChargePolicy,
  createChargePolicy,
  updateChargePolicy,
  deleteChargePolicy,
  listCityTransferDistanceBands,
  updateCityTransferDistanceBand,
};
