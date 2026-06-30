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
} = require('../validators/pricing.validator');

const router = express.Router();
const adminOnly = [authMiddleware, roleMiddleware([ROLES.ADMIN, ROLES.SUPER_ADMIN])];

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

module.exports = router;
