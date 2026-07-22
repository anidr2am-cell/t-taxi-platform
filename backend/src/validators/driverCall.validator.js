const Joi = require('joi');
const {
  DRIVER_RELEASE_REASON,
} = require('../policies/driverAssignmentRelease.policy');

const releaseAssignmentSchema = Joi.object({
  reasonCode: Joi.string()
    .trim()
    .uppercase()
    .valid(...Object.values(DRIVER_RELEASE_REASON))
    .required(),
  reasonDetail: Joi.string().trim().max(500).allow('', null).optional(),
});

module.exports = {
  releaseAssignmentSchema,
};
