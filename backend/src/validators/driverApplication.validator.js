const Joi = require('joi');

const statusValues = ['PENDING', 'APPROVED', 'REJECTED'];
const ownershipValues = ['OWNED', 'RENTED', 'COMPANY', 'OTHER'];
const localeValues = ['ko', 'en', 'th', 'ja', 'zh'];

const applicationNumberSchema = Joi.string().trim().pattern(/^DA[0-9A-F]{14}$/).required();
const tokenSchema = Joi.string().trim().min(32).max(128).required();
const optionalEmailSchema = Joi.string().trim().lowercase().email().max(255).empty('').optional();

const driverApplicationCreateSchema = Joi.object({
  fullName: Joi.string().trim().min(1).max(100).required(),
  email: optionalEmailSchema,
  password: Joi.string().min(6).max(128).required(),
  passwordConfirm: Joi.string().valid(Joi.ref('password')).required().messages({
    'any.only': '"passwordConfirm" must match "password"',
  }),
  phone: Joi.string().trim().min(5).max(30).required(),
  phoneCountryCode: Joi.string().trim().max(5).allow('', null),
  countryCode: Joi.string().trim().uppercase().length(2).allow('', null),
  locale: Joi.string().valid(...localeValues).default('ko'),
  drivingLicenseNumber: Joi.string().trim().min(3).max(50).required(),
  drivingLicenseCountry: Joi.string().trim().uppercase().length(2).allow('', null),
  drivingLicenseExpiryDate: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).allow('', null),
  yearsOfDrivingExperience: Joi.number().integer().min(0).max(80).required(),
  vehicleOwnershipType: Joi.string().valid(...ownershipValues).required(),
  vehicleTypeCode: Joi.string().trim().uppercase().min(2).max(30).required(),
  vehicleMake: Joi.string().trim().max(50).allow('', null),
  vehicleModel: Joi.string().trim().max(100).allow('', null),
  vehicleYear: Joi.number().integer().min(1980).max(2100).allow(null),
  vehicleColor: Joi.string().trim().max(30).allow('', null),
  vehiclePlateNumber: Joi.string().trim().uppercase().min(2).max(20).required(),
  serviceAreas: Joi.array().items(Joi.string().trim().min(1).max(100)).min(1).max(30).required(),
  languages: Joi.array().items(Joi.string().trim().min(2).max(10)).max(20).default([]),
  notes: Joi.string().trim().max(2000).allow('', null),
  bankName: Joi.string().trim().max(100).allow('', null),
  bankAccountNumber: Joi.string().trim().max(80).allow('', null),
  bankAccountHolder: Joi.string().trim().max(100).allow('', null),
  lineId: Joi.string().trim().max(100).allow('', null),
  primaryServiceArea: Joi.string().trim().max(100).allow('', null),
  personalDataConsent: Joi.boolean().valid(true).required(),
  driverTermsConsent: Joi.boolean().valid(true).required(),
});

const driverApplicationStatusQuerySchema = Joi.object({
  applicationNumber: applicationNumberSchema,
  token: tokenSchema,
});

const driverApplicationResubmitParamsSchema = Joi.object({
  applicationNumber: applicationNumberSchema,
});

const driverApplicationResubmitSchema = driverApplicationCreateSchema.keys({
  token: tokenSchema,
});

const adminDriverApplicationListQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).optional(),
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  status: Joi.string().valid(...statusValues).optional(),
  countryCode: Joi.string().trim().uppercase().length(2).optional(),
  vehicleTypeCode: Joi.string().trim().uppercase().max(30).optional(),
  dateFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  dateTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  search: Joi.string().trim().max(100).allow('', null),
});

const adminDriverApplicationIdParamsSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const adminDriverApplicationApproveSchema = Joi.object({
  adminNote: Joi.string().trim().max(2000).allow('', null),
});

const adminDriverApplicationRejectSchema = Joi.object({
  rejectionReason: Joi.string().trim().min(1).max(2000).required(),
  adminNote: Joi.string().trim().max(2000).allow('', null),
});

module.exports = {
  driverApplicationCreateSchema,
  driverApplicationStatusQuerySchema,
  driverApplicationResubmitParamsSchema,
  driverApplicationResubmitSchema,
  adminDriverApplicationListQuerySchema,
  adminDriverApplicationIdParamsSchema,
  adminDriverApplicationApproveSchema,
  adminDriverApplicationRejectSchema,
};
