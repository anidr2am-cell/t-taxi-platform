const Joi = require('joi');

const vehicleTypeCodeValues = ['SEDAN', 'SUV', 'VIP_SUV', 'VAN', 'VIP_VAN', 'LUXURY'];

const updateDriverProfileSchema = Joi.object({
  name: Joi.string().trim().min(1).max(100),
  phone: Joi.string().trim().min(8).max(30),
  vehicleTypeCode: Joi.string().trim().uppercase().valid(
    'SEDAN',
    'SUV',
    'VIP_SUV',
    'VAN',
    'VIP_VAN',
    'LUXURY',
  ),
  vehicleModelName: Joi.string().trim().max(100).allow('', null),
  vehiclePlateNumber: Joi.string().trim().max(20),
  vehicleColor: Joi.string().trim().max(30).allow('', null),
  vehicleYear: Joi.number().integer().min(1990).max(new Date().getFullYear() + 1),
}).min(1);

module.exports = {
  updateDriverProfileSchema,
};
