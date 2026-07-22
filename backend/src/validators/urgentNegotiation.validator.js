const Joi = require('joi');

const submitUrgentCallEtaSchema = Joi.object({
  etaMinutes: Joi.number().integer().strict().required(),
});

const submitUrgentDecisionSchema = Joi.object({
  decision: Joi.string().valid('ACCEPT', 'REJECT').required(),
  guestAccessToken: Joi.string().trim().min(1).max(512).optional(),
});

module.exports = {
  submitUrgentCallEtaSchema,
  submitUrgentDecisionSchema,
};