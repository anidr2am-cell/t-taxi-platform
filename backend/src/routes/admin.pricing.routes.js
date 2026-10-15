const express = require('express');
const pricingController = require('../controllers/pricing.controller');
const validate = require('../middlewares/validate.middleware');
const { authMiddleware } = require('../middlewares/auth.middleware');
const roleMiddleware = require('../middlewares/role.middleware');
const ROLES = require('../constants/roles');
const {
  routeCreateSchema,
  routeUpdateSchema,
  routeCopySchema,
  routeListQuerySchema,
  vehiclePriceCreateSchema,
  vehiclePriceUpdateSchema,
  vehiclePriceListQuerySchema,
  chargePolicyCreateSchema,
  chargePolicyUpdateSchema,
  chargePolicyListQuerySchema,
  pricingSimulateSchema,
  idParamSchema,
  cityTransferDistanceBandUpdateSchema,
} = require('../validators/pricing.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];
const RegionRepository = require('../repositories/pricingRegion.repository');
const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const Joi = require('joi');
const geometry = Joi.alternatives().try(
  Joi.object({ type: Joi.string().valid('Circle').required(), lat: Joi.number().min(-90).max(90).required(),
    lng: Joi.number().min(-180).max(180).required(), radiusKm: Joi.number().positive().max(200).required() }),
  Joi.object({ type: Joi.string().valid('Polygon').required(), coordinates: Joi.array().length(1).items(
    Joi.array().min(4).max(5000).items(Joi.array().ordered(Joi.number().min(-180).max(180).required(), Joi.number().min(-90).max(90).required()).length(2))
      .custom((ring, h) => JSON.stringify(ring[0]) === JSON.stringify(ring[ring.length - 1]) ? ring : h.error('any.invalid')),
  ).required() }),
).required();
// Retain the preview API path; it now returns approved, editable regional fares.
router.get('/pricing/region-candidates', adminOnly, asyncHandler(async (_req, res) => success(res, await new RegionRepository().listFares())));
router.patch('/pricing/region-fares/:id', adminOnly, validate({ params: idParamSchema,
  body: Joi.object({ price: Joi.number().positive().max(1000000).required() }) }),
asyncHandler(async (req, res) => {
  const changed = await new RegionRepository().updateFare(Number(req.params.id), req.body.price);
  if (!changed) return res.status(404).json({ success:false,message:'Regional fare not found' });
  return success(res,{updated:true});
}));
router.get('/pricing/regions', adminOnly, asyncHandler(async (_req, res) => success(res, await new RegionRepository().list())));
router.patch('/pricing/regions/:id', adminOnly, validate({ params: idParamSchema,
  body: Joi.object({ geometry, priority: Joi.number().integer().min(0).max(1000).required(), isActive: Joi.boolean().required() }) }),
asyncHandler(async (req, res) => {
  const changed = await new RegionRepository().update(Number(req.params.id), req.body);
  if (!changed) return res.status(404).json({ success: false, message: 'Region not found' });
  return success(res, { updated: true });
}));

router.get(
  '/routes',
  adminOnly,
  validate({ query: routeListQuerySchema }),
  pricingController.listRoutes,
);
router.post(
  '/routes',
  adminOnly,
  validate({ body: routeCreateSchema }),
  pricingController.createRoute,
);
router.get(
  '/routes/:id',
  adminOnly,
  validate({ params: idParamSchema }),
  pricingController.getRoute,
);
router.patch(
  '/routes/:id',
  adminOnly,
  validate({ params: idParamSchema, body: routeUpdateSchema }),
  pricingController.updateRoute,
);
router.delete(
  '/routes/:id',
  adminOnly,
  validate({ params: idParamSchema }),
  pricingController.deleteRoute,
);
router.post(
  '/routes/:id/copy',
  adminOnly,
  validate({ params: idParamSchema, body: routeCopySchema }),
  pricingController.copyRoute,
);

router.post(
  '/pricing/simulate',
  adminOnly,
  validate({ body: pricingSimulateSchema }),
  pricingController.simulatePricing,
);
router.get(
  '/pricing/summary',
  adminOnly,
  pricingController.getPricingSummary,
);

router.get(
  '/vehicle-prices',
  adminOnly,
  validate({ query: vehiclePriceListQuerySchema }),
  pricingController.listVehiclePrices,
);
router.post(
  '/vehicle-prices',
  adminOnly,
  validate({ body: vehiclePriceCreateSchema }),
  pricingController.createVehiclePrice,
);
router.get(
  '/vehicle-prices/:id',
  adminOnly,
  validate({ params: idParamSchema }),
  pricingController.getVehiclePrice,
);
router.patch(
  '/vehicle-prices/:id',
  adminOnly,
  validate({ params: idParamSchema, body: vehiclePriceUpdateSchema }),
  pricingController.updateVehiclePrice,
);
router.delete(
  '/vehicle-prices/:id',
  adminOnly,
  validate({ params: idParamSchema }),
  pricingController.deleteVehiclePrice,
);

router.get(
  '/charge-policies',
  adminOnly,
  validate({ query: chargePolicyListQuerySchema }),
  pricingController.listChargePolicies,
);
router.post(
  '/charge-policies',
  adminOnly,
  validate({ body: chargePolicyCreateSchema }),
  pricingController.createChargePolicy,
);
router.get(
  '/charge-policies/:id',
  adminOnly,
  validate({ params: idParamSchema }),
  pricingController.getChargePolicy,
);
router.patch(
  '/charge-policies/:id',
  adminOnly,
  validate({ params: idParamSchema, body: chargePolicyUpdateSchema }),
  pricingController.updateChargePolicy,
);
router.delete(
  '/charge-policies/:id',
  adminOnly,
  validate({ params: idParamSchema }),
  pricingController.deleteChargePolicy,
);

router.get(
  '/city-transfer-distance-bands',
  adminOnly,
  validate({ query: chargePolicyListQuerySchema }),
  pricingController.listCityTransferDistanceBands,
);
router.put(
  '/city-transfer-distance-bands/:id',
  adminOnly,
  validate({ params: idParamSchema, body: cityTransferDistanceBandUpdateSchema }),
  pricingController.updateCityTransferDistanceBand,
);

module.exports = router;
