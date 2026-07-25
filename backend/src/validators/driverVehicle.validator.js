const Joi = require('joi');
const { unicodeText } = require('./common.validator');

const approvalStatusValues = ['PENDING', 'APPROVED', 'REJECTED'];

const createDriverVehicleSchema = Joi.object({
  vehicleTypeId: Joi.number().integer().positive().required(),
  plateNumber: Joi.string().trim().min(2).max(20).required(),
  modelName: Joi.string().trim().max(100).allow('', null),
  color: Joi.string().trim().max(30).allow('', null),
}).unknown(true);

const adminDriverVehicleListQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).optional(),
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  status: Joi.string().valid(...approvalStatusValues).optional(),
  search: unicodeText({ max: 100, allowEmpty: true }).default(null),
});

const adminDriverVehicleIdParamsSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const adminDriverVehicleFileParamsSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
  fileId: Joi.number().integer().positive().required(),
});

const adminDriverVehicleApproveSchema = Joi.object({
  adminNote: unicodeText({ max: 2000, allowEmpty: true }).default(null),
});

const adminDriverVehicleRejectSchema = Joi.object({
  rejectionReason: unicodeText({ max: 500 }),
  adminNote: unicodeText({ max: 2000, allowEmpty: true }).default(null),
});

module.exports = {
  createDriverVehicleSchema,
  adminDriverVehicleListQuerySchema,
  adminDriverVehicleIdParamsSchema,
  adminDriverVehicleFileParamsSchema,
  adminDriverVehicleApproveSchema,
  adminDriverVehicleRejectSchema,
};
