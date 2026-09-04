const Joi = require('joi');

const mileageTransactionListQuerySchema = Joi.object({
  page: Joi.number().integer().min(1).default(1),
  limit: Joi.number().integer().min(1).max(100).default(20),
});

module.exports = {
  mileageTransactionListQuerySchema,
};
