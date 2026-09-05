const Joi = require('joi');

const bannerIdParamSchema = Joi.object({
  id: Joi.number().integer().positive().required(),
});

const createHomeBannerSchema = Joi.object({
  displayOrder: Joi.number().integer().min(0).optional(),
});

const updateHomeBannerSchema = Joi.object({
  isActive: Joi.boolean().optional(),
  displayOrder: Joi.number().integer().min(0).optional(),
}).or('isActive', 'displayOrder');

module.exports = {
  bannerIdParamSchema,
  createHomeBannerSchema,
  updateHomeBannerSchema,
};
