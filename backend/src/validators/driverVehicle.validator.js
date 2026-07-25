const Joi = require('joi');

const createDriverVehicleSchema = Joi.object({
  vehicleTypeId: Joi.number().integer().positive().required(),
  plateNumber: Joi.string().trim().min(2).max(20).required(),
  modelName: Joi.string().trim().max(100).allow('', null),
  color: Joi.string().trim().max(30).allow('', null),
}).unknown(true);

module.exports = {
  createDriverVehicleSchema,
};
