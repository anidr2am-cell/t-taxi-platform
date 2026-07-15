const Joi = require('joi');
const { paginationQuery, bookingNumberParam } = require('./common.validator');
const BOOKING_STATUS = require('../constants/reservationStatus');
const { ADMIN_BOOKING_VIEWS } = require('../constants/adminOperations.constants');
const adminBookingListQuerySchema = paginationQuery.keys({
  page_size: Joi.number().integer().min(1).max(100).optional(),
  limit: Joi.number().integer().min(1).max(100).optional(),
  view: Joi.string()
    .valid(...Object.values(ADMIN_BOOKING_VIEWS))
    .optional(),
  search: Joi.string().max(100).allow('', null),
  status: Joi.string().valid(...Object.values(BOOKING_STATUS)).optional(),
  serviceDateFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  serviceDateTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  dateFrom: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  dateTo: Joi.string().pattern(/^\d{4}-\d{2}-\d{2}$/).optional(),
  driverId: Joi.number().integer().positive().optional(),
  assignmentState: Joi.string().valid('ASSIGNED', 'UNASSIGNED').optional(),
  serviceType: Joi.string().max(64).optional(),
  service_type: Joi.string().max(64).optional(),
  origin: Joi.string().max(200).optional(),
  destination: Joi.string().max(200).optional(),
  settlementStatus: Joi.string()
    .valid('RECEIPT_REJECTED', 'RECEIPT_SUBMITTED', 'RECEIPT_MISSING', 'ADMIN_CONFIRMED')
    .optional(),
  settlement_status: Joi.string()
    .valid('RECEIPT_REJECTED', 'RECEIPT_SUBMITTED', 'RECEIPT_MISSING', 'ADMIN_CONFIRMED')
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
});

const bookingNumberParamsSchema = Joi.object({
  bookingNumber: bookingNumberParam.required(),
});

const assignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().required(),
  driverVehicleId: Joi.number().integer().positive().optional(),
  assignmentReason: Joi.string().max(255).allow('', null),
  reason: Joi.string().max(255).allow('', null),
});

const reassignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().required(),
  driverVehicleId: Joi.number().integer().positive().optional(),
  reason: Joi.string().max(255).required(),
  assignmentReason: Joi.string().max(255).allow('', null),
});

const autoAssignDriverSchema = Joi.object({
  driverId: Joi.number().integer().positive().optional(),
  useTopCandidate: Joi.boolean().optional(),
  expectedAssignmentVersion: Joi.number().integer().min(0).optional(),
  assignmentReason: Joi.string().max(255).allow('', null),
}).or('driverId', 'useTopCandidate');

const qrReissueSchema = Joi.object({
  type: Joi.string().valid('BOARDING', 'DROPOFF').insensitive().required(),
});

const adminBookingNotesQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).optional(),
  limit: Joi.number().integer().min(1).max(50).optional(),
});

const createAdminBookingNoteSchema = Joi.object({
  text: Joi.string().trim().min(1).max(1000).required(),
  adminUserId: Joi.forbidden(),
  admin_user_id: Joi.forbidden(),
});

const archiveBookingsSchema = Joi.object({
  bookingNumbers: Joi.array().items(bookingNumberParam).min(1).max(100).required(),
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

module.exports = {
  adminBookingListQuerySchema,
  bookingNumberParamsSchema,
  assignDriverSchema,
  reassignDriverSchema,
  autoAssignDriverSchema,
  qrReissueSchema,
  adminBookingNotesQuerySchema,
  createAdminBookingNoteSchema,
  archiveBookingsSchema,
  archiveDriversSchema,
  driverIdParamsSchema,
};
