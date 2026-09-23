const Joi = require("joi");
const {
  apiDate,
  paginationQuery,
  bookingNumberParam,
  unicodeText,
} = require("./common.validator");
const BOOKING_STATUS = require("../constants/reservationStatus");
const {
  ADMIN_BOOKING_VIEWS,
} = require("../constants/adminOperations.constants");
const adminBookingListQuerySchema = paginationQuery
  .keys({
    page_size: Joi.number().integer().min(1).max(100).optional(),
    limit: Joi.number().integer().min(1).max(100).optional(),
    view: Joi.string()
      .valid(...Object.values(ADMIN_BOOKING_VIEWS))
      .optional(),
    search: unicodeText({ max: 100, allowEmpty: true }).default(null),
    status: Joi.string()
      .valid(...Object.values(BOOKING_STATUS))
      .optional(),
    serviceDateFrom: apiDate().optional(),
    serviceDateTo: apiDate().optional(),
    dateFrom: apiDate().optional(),
    dateTo: apiDate().optional(),
    driverId: Joi.number().integer().positive().optional(),
    assignmentState: Joi.string().valid("ASSIGNED", "UNASSIGNED").optional(),
    serviceType: Joi.string().max(64).optional(),
    service_type: Joi.string().max(64).optional(),
    origin: unicodeText({ max: 200, allowEmpty: true }).optional(),
    destination: unicodeText({ max: 200, allowEmpty: true }).optional(),
    settlementStatus: Joi.string()
      .valid(
        "RECEIPT_REJECTED",
        "RECEIPT_SUBMITTED",
        "RECEIPT_MISSING",
        "ADMIN_CONFIRMED",
      )
      .optional(),
    settlement_status: Joi.string()
      .valid(
        "RECEIPT_REJECTED",
        "RECEIPT_SUBMITTED",
        "RECEIPT_MISSING",
        "ADMIN_CONFIRMED",
      )
      .optional(),
    lowRating: Joi.boolean().optional(),
    low_rating: Joi.boolean().optional(),
    unassigned: Joi.boolean().optional(),
    hasInquiry: Joi.boolean().optional(),
    has_inquiry: Joi.boolean().optional(),
    sort: Joi.string().optional(),
    archived: Joi.boolean().optional(),
    archivedOnly: Joi.boolean().optional(),
    archived_only: Joi.boolean().optional(),
  })
  .custom((value, helpers) => {
    const from = value.serviceDateFrom || value.dateFrom;
    const to = value.serviceDateTo || value.dateTo;
    if (from && to && from > to) {
      return helpers.error("date.range", {
        field: value.serviceDateFrom ? "serviceDateTo" : "dateTo",
      });
    }
    return value;
  })
  .messages({
    "date.range": "{{#field}} must be on or after the start date",
  });

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: bookingNumberParam.required(),
});

const assignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().required(),
  driverVehicleId: Joi.number().integer().positive().optional(),
  assignmentReason: unicodeText({ max: 255, allowEmpty: true }).default(null),
  reason: unicodeText({ max: 255, allowEmpty: true }).default(null),
});

const reassignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().required(),
  driverVehicleId: Joi.number().integer().positive().optional(),
  reason: unicodeText({ max: 255 }),
  assignmentReason: unicodeText({ max: 255, allowEmpty: true }).default(null),
});

const unassignDriverSchema = Joi.object({
  reason: unicodeText({ max: 255 }),
});

const autoAssignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().optional(),
  useTopCandidate: Joi.boolean().optional(),
  expectedAssignmentVersion: Joi.number().integer().min(0).optional(),
  assignmentReason: unicodeText({ max: 255, allowEmpty: true }).default(null),
}).or("driverId", "useTopCandidate");

const qrReissueSchema = Joi.object({
  type: Joi.string().valid("BOARDING", "DROPOFF").insensitive().required(),
});

const adminBookingNotesQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).optional(),
  limit: Joi.number().integer().min(1).max(50).optional(),
});

const createAdminBookingNoteSchema = Joi.object({
  text: unicodeText({ max: 1000 }),
  adminUserId: Joi.forbidden(),
  admin_user_id: Joi.forbidden(),
});

const processBookingNoShowSchema = Joi.object({
  penaltyAmount: Joi.number().positive().required(),
  reason: unicodeText({ max: 1000 }).required(),
  memo: unicodeText({ max: 500, allowEmpty: true }).default(null),
});

const archiveBookingsSchema = Joi.object({
  bookingNumbers: Joi.array()
    .items(bookingNumberParam)
    .min(1)
    .max(100)
    .required(),
});

const archiveDriversSchema = Joi.object({
  driverIds: Joi.array()
    .items(Joi.number().integer().positive())
    .min(1)
    .max(100)
    .required(),
});

const driverIdParamsSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const adminManualLocationSchema = Joi.object({
  address: unicodeText({ max: 500 }).required(),
  placeId: Joi.string().max(255).allow(null, '').optional(),
  lat: Joi.number().optional(),
  lng: Joi.number().optional(),
  name: unicodeText({ max: 200, allowEmpty: true }).optional(),
});

const adminManualBookingCreateSchema = Joi.object({
  origin: adminManualLocationSchema.required(),
  destination: adminManualLocationSchema.required(),
  scheduledPickupAt: Joi.string().isoDate().required(),
  vehicleTypeCode: Joi.string()
    .valid('SEDAN', 'SUV', 'VIP_SUV', 'VAN', 'VIP_VAN')
    .required(),
  serviceTypeCode: Joi.string()
    .valid('AIRPORT_PICKUP', 'AIRPORT_DROPOFF', 'CITY_TRANSFER', 'GOLF_TRANSFER')
    .optional(),
  passengers: Joi.object({
    adults: Joi.number().integer().min(1).default(1),
    children: Joi.number().integer().min(0).default(0),
    infants: Joi.number().integer().min(0).default(0),
  }).default({ adults: 1, children: 0, infants: 0 }),
  payoutAmount: Joi.number().positive().required(),
  customerChargeAmount: Joi.number().positive().optional(),
  paymentCollection: Joi.string()
    .valid('DRIVER_COLLECTS', 'ADMIN_COLLECTED')
    .required(),
  customer: Joi.object({
    customerUserId: Joi.number().integer().positive().optional(),
    name: unicodeText({ max: 120, allowEmpty: true }).optional(),
    phone: Joi.string().max(32).allow('', null).optional(),
    email: Joi.string().email({ tlds: { allow: false } }).allow('', null).optional(),
  }).required(),
  memo: unicodeText({ max: 1000, allowEmpty: true }).optional(),
  nameSignText: unicodeText({ max: 120, allowEmpty: true }).optional(),
  preferFemaleDriver: Joi.boolean().optional(),
});

const adminManualBookingUpdateSchema = adminManualBookingCreateSchema;

const adminManualBookingCancelSchema = Joi.object({
  reason: unicodeText({ max: 100, allowEmpty: true }).optional(),
  memo: unicodeText({ max: 500, allowEmpty: true }).optional(),
});

module.exports = {
  adminBookingListQuerySchema,
  bookingNumberParamsSchema,
  assignDriverSchema,
  reassignDriverSchema,
  unassignDriverSchema,
  autoAssignDriverSchema,
  qrReissueSchema,
  adminBookingNotesQuerySchema,
  createAdminBookingNoteSchema,
  processBookingNoShowSchema,
  archiveBookingsSchema,
  archiveDriversSchema,
  driverIdParamsSchema,
  adminManualBookingCreateSchema,
  adminManualBookingUpdateSchema,
  adminManualBookingCancelSchema,
};
