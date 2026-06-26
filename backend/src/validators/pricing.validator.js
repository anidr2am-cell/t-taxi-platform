const Joi = require('joi');
const SERVICE_TYPES = require('../constants/serviceTypes');
const VEHICLE_TYPES = require('../constants/vehicleTypes');
const CHARGE_POLICY_TYPES = require('../constants/chargePolicyTypes');
const CALCULATION_TYPES = require('../constants/calculationTypes');
const LOCATION_TYPES = require('../constants/locationTypes');

const passengersDto = Joi.object({
  adults: Joi.number().integer().min(1).optional(),
  children: Joi.number().integer().min(0).optional(),
  infants: Joi.number().integer().min(0).optional(),
});

const luggageDto = Joi.object({
  carriers20Inch: Joi.number().integer().min(0).optional(),
  carriers24InchPlus: Joi.number().integer().min(0).optional(),
  golfBags: Joi.number().integer().min(0).optional(),
});

const bookingOptionsDto = Joi.object({
  nameSign: Joi.boolean().optional(),
  waiting: Joi.boolean().optional(),
  parking: Joi.boolean().optional(),
  toll: Joi.boolean().optional(),
});

const pricingCalculateSchema = Joi.object({
  serviceTypeCode: Joi.string().valid(...Object.values(SERVICE_TYPES)).required(),
  vehicleTypeCode: Joi.string().valid(...Object.values(VEHICLE_TYPES)).required(),
  vehicleCount: Joi.number().integer().min(1).default(1),
  scheduledPickupAt: Joi.date().iso().optional(),
  originAirportIata: Joi.string().trim().uppercase().length(3).optional(),
  destinationRegion: Joi.string().trim().optional(),
  originLocationCode: Joi.string().trim().uppercase().optional(),
  destinationLocationCode: Joi.string().trim().uppercase().optional(),
  options: bookingOptionsDto.optional(),
  passengers: passengersDto.optional(),
  luggage: luggageDto.optional(),
}).or('originAirportIata', 'originLocationCode')
  .or('destinationRegion', 'destinationLocationCode');

const routeCreateSchema = Joi.object({
  serviceTypeCode: Joi.string().valid(...Object.values(SERVICE_TYPES)).optional(),
  serviceTypeId: Joi.number().integer().positive().optional(),
  originLocationCode: Joi.string().trim().uppercase().optional(),
  originLocationId: Joi.number().integer().positive().optional(),
  destinationLocationCode: Joi.string().trim().uppercase().optional(),
  destinationLocationId: Joi.number().integer().positive().optional(),
  isActive: Joi.boolean().optional(),
  displayOrder: Joi.number().integer().optional(),
  effectiveFrom: Joi.date().iso().allow(null).optional(),
  effectiveTo: Joi.date().iso().allow(null).optional(),
}).or('serviceTypeCode', 'serviceTypeId')
  .or('originLocationCode', 'originLocationId')
  .or('destinationLocationCode', 'destinationLocationId');

const routeUpdateSchema = Joi.object({
  serviceTypeCode: Joi.string().valid(...Object.values(SERVICE_TYPES)).optional(),
  serviceTypeId: Joi.number().integer().positive().optional(),
  originLocationCode: Joi.string().trim().uppercase().optional(),
  originLocationId: Joi.number().integer().positive().optional(),
  destinationLocationCode: Joi.string().trim().uppercase().optional(),
  destinationLocationId: Joi.number().integer().positive().optional(),
  isActive: Joi.boolean().optional(),
  displayOrder: Joi.number().integer().optional(),
  effectiveFrom: Joi.date().iso().allow(null).optional(),
  effectiveTo: Joi.date().iso().allow(null).optional(),
}).min(1);

const routeCopySchema = Joi.object({
  newOriginLocationId: Joi.number().integer().positive().optional(),
  newDestinationLocationId: Joi.number().integer().positive().optional(),
  originLocationCode: Joi.string().trim().uppercase().optional(),
  originLocationId: Joi.number().integer().positive().optional(),
  destinationLocationCode: Joi.string().trim().uppercase().optional(),
  destinationLocationId: Joi.number().integer().positive().optional(),
  serviceTypeId: Joi.number().integer().positive().optional(),
  isActive: Joi.boolean().optional(),
  displayOrder: Joi.number().integer().optional(),
  effectiveFrom: Joi.date().iso().allow(null).optional(),
  effectiveTo: Joi.date().iso().allow(null).optional(),
}).or('newOriginLocationId', 'originLocationId', 'originLocationCode');

const routeListQuerySchema = Joi.object({
  includeInactive: Joi.boolean().optional(),
});

const vehiclePriceCreateSchema = Joi.object({
  routeId: Joi.number().integer().positive().required(),
  vehicleTypeCode: Joi.string().valid(...Object.values(VEHICLE_TYPES)).optional(),
  vehicleTypeId: Joi.number().integer().positive().optional(),
  price: Joi.number().positive().required(),
  currency: Joi.string().trim().uppercase().length(3).optional(),
  isActive: Joi.boolean().optional(),
  effectiveFrom: Joi.date().iso().allow(null).optional(),
  effectiveTo: Joi.date().iso().allow(null).optional(),
}).or('vehicleTypeCode', 'vehicleTypeId');

const vehiclePriceUpdateSchema = Joi.object({
  price: Joi.number().positive().optional(),
  currency: Joi.string().trim().uppercase().length(3).optional(),
  isActive: Joi.boolean().optional(),
  effectiveFrom: Joi.date().iso().allow(null).optional(),
  effectiveTo: Joi.date().iso().allow(null).optional(),
}).min(1);

const vehiclePriceListQuerySchema = Joi.object({
  routeId: Joi.number().integer().positive().optional(),
  includeInactive: Joi.boolean().optional(),
});

const chargePolicyCreateSchema = Joi.object({
  chargeType: Joi.string().valid(...Object.values(CHARGE_POLICY_TYPES)).required(),
  calculationType: Joi.string().valid(...Object.values(CALCULATION_TYPES)).required(),
  amount: Joi.number().min(0).required(),
  isActive: Joi.boolean().optional(),
  effectiveFrom: Joi.date().iso().allow(null).optional(),
  effectiveTo: Joi.date().iso().allow(null).optional(),
});

const chargePolicyUpdateSchema = Joi.object({
  chargeType: Joi.string().valid(...Object.values(CHARGE_POLICY_TYPES)).optional(),
  calculationType: Joi.string().valid(...Object.values(CALCULATION_TYPES)).optional(),
  amount: Joi.number().min(0).optional(),
  isActive: Joi.boolean().optional(),
  effectiveFrom: Joi.date().iso().allow(null).optional(),
  effectiveTo: Joi.date().iso().allow(null).optional(),
}).min(1);

const chargePolicyListQuerySchema = Joi.object({
  includeInactive: Joi.boolean().optional(),
});

const pricingSimulateSchema = Joi.object({
  serviceType: Joi.alternatives().try(
    Joi.string().valid(...Object.values(SERVICE_TYPES)),
    Joi.number().integer().positive(),
  ).required(),
  originLocationId: Joi.number().integer().positive().required(),
  destinationLocationId: Joi.number().integer().positive().required(),
  vehicleTypeId: Joi.number().integer().positive().required(),
  options: Joi.object({
    nameSign: Joi.boolean().optional(),
    waiting: Joi.boolean().optional(),
    parking: Joi.boolean().optional(),
    toll: Joi.boolean().optional(),
  }).optional(),
  scheduledPickupAt: Joi.date().iso().optional(),
});

const idParamSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

module.exports = {
  pricingCalculateSchema,
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
  LOCATION_TYPES,
};
