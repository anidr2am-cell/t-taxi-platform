const Joi = require('joi');
const { unicodeText, vehiclePlateText } = require('./common.validator');

const statusValues = ['PENDING', 'APPROVED', 'REJECTED'];
const ownershipValues = ['OWNED', 'RENTED', 'COMPANY', 'OTHER'];
const localeValues = ['ko', 'en', 'th', 'ja', 'zh'];
const currentVehicleYear = new Date().getFullYear();

const applicationNumberSchema = Joi.string().trim().pattern(/^DA[0-9A-F]{14}$/).required();
const tokenSchema = Joi.string().trim().min(32).max(128).required();
const optionalEmailSchema = Joi.string()
  .trim()
  .lowercase()
  .email()
  .max(255)
  .empty('')
  .allow(null)
  .optional();

const driverApplicationCreateSchema = Joi.object({
  fullName: unicodeText({ max: 100 }),
  email: optionalEmailSchema,
  password: Joi.string().min(6).max(128).required(),
  passwordConfirm: Joi.string().valid(Joi.ref('password')).required().messages({
    'any.only': '"passwordConfirm" must match "password"',
  }),
  phone: Joi.string().trim().min(5).max(30).required(),
  phoneCountryCode: Joi.string().trim().max(5).allow('', null),
  countryCode: Joi.string().trim().uppercase().length(2).allow('', null),
  locale: Joi.string().valid(...localeValues).default('ko'),
  drivingLicenseNumber: unicodeText({ min: 3, max: 50 }),
  drivingLicenseCountry: Joi.string().trim().uppercase().length(2).allow('', null),
  drivingLicenseExpiryDate: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).allow('', null),
  yearsOfDrivingExperience: Joi.number().integer().min(0).max(80).required(),
  vehicleOwnershipType: Joi.string().valid(...ownershipValues).required(),
  vehicleTypeCode: Joi.string().trim().uppercase().min(2).max(30).required(),
  vehicleMake: unicodeText({ max: 50, allowEmpty: true }).default(null),
  vehicleModel: unicodeText({ max: 100, allowEmpty: true }).default(null),
  vehicleYear: Joi.number()
    .integer()
    .min(1980)
    .max(currentVehicleYear)
    .allow(null)
    .messages({
      'number.base': 'กรุณากรอกปีรถเป็นตัวเลข 4 หลัก เช่น 2020',
      'number.integer': 'กรุณากรอกปีรถเป็นตัวเลข 4 หลัก เช่น 2020',
      'number.min': 'กรุณากรอกปีรถตั้งแต่ปี 1980 เป็นต้นไป',
      'number.max': `กรุณากรอกปีรถไม่เกินปี ${currentVehicleYear}`,
    }),
  vehicleColor: unicodeText({ max: 30, allowEmpty: true }).default(null),
  vehiclePlateNumber: vehiclePlateText({ min: 1, max: 30 }),
  serviceAreas: Joi.array()
    .items(unicodeText({ max: 100 }).optional())
    .min(1)
    .max(30)
    .required()
    .messages({
      'array.min': 'กรุณาเลือกพื้นที่ให้บริการอย่างน้อย 1 แห่ง',
      'any.required': 'กรุณาเลือกพื้นที่ให้บริการอย่างน้อย 1 แห่ง',
    }),
  languages: Joi.array().items(Joi.string().trim().min(2).max(10)).max(20).default([]),
  notes: unicodeText({ max: 2000, allowEmpty: true }).default(null),
  bankName: unicodeText({ max: 100, allowEmpty: true }).default(null),
  bankAccountNumber: Joi.string().trim().max(80).allow('', null),
  bankAccountHolder: unicodeText({ max: 100, allowEmpty: true }).default(null),
  lineId: Joi.string().trim().max(100).allow('', null),
  primaryServiceArea: unicodeText({ max: 100, allowEmpty: true }).default(null),
  personalDataConsent: Joi.boolean().valid(true).required().messages({
    'any.only': 'กรุณายอมรับเงื่อนไขก่อนส่งใบสมัคร',
    'any.required': 'กรุณายอมรับเงื่อนไขก่อนส่งใบสมัคร',
  }),
  driverTermsConsent: Joi.boolean().valid(true).required().messages({
    'any.only': 'กรุณายอมรับเงื่อนไขก่อนส่งใบสมัคร',
    'any.required': 'กรุณายอมรับเงื่อนไขก่อนส่งใบสมัคร',
  }),
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
  view: Joi.string().valid('needs_action', 'approved', 'closed', 'all').optional(),
  status: Joi.string().valid(...statusValues).optional(),
  countryCode: Joi.string().trim().uppercase().length(2).optional(),
  vehicleTypeCode: Joi.string().trim().uppercase().max(30).optional(),
  dateFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  dateTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  search: unicodeText({ max: 100, allowEmpty: true }).default(null),
});

const adminDriverApplicationIdParamsSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const adminDriverApplicationApproveSchema = Joi.object({
  adminNote: unicodeText({ max: 2000, allowEmpty: true }).default(null),
});

const adminDriverApplicationRejectSchema = Joi.object({
  rejectionReason: unicodeText({ max: 2000 }),
  adminNote: unicodeText({ max: 2000, allowEmpty: true }).default(null),
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
