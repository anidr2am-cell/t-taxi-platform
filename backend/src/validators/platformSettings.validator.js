const Joi = require('joi');
const { unicodeText } = require('./common.validator');

const adminSettingsUpdateSchema = Joi.object({
  lineQrDescription: unicodeText({ max: 500, allowEmpty: true }).default(''),
  bankName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  accountName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  accountNumber: Joi.string().trim().max(50).allow('', null).default(''),
  promptPayNumber: Joi.string().trim().max(50).allow('', null).default(''),
}).unknown(false);

const adminSettingsImageKindParamsSchema = Joi.object({
  kind: Joi.string().valid('lineQr', 'promptPayQr', 'contactLineQr', 'contactKakaoQr', 'contactWechatQr').required(),
});

module.exports = {
  adminSettingsUpdateSchema,
  adminSettingsImageKindParamsSchema,
};
