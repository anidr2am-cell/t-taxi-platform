const Joi = require('joi');
const { unicodeText } = require('./common.validator');

const booleanSetting = Joi.alternatives().try(
  Joi.boolean(),
  Joi.string().valid('true', 'false', '1', '0', ''),
);

const adminSettingsUpdateSchema = Joi.object({
  lineQrDescription: unicodeText({ max: 500, allowEmpty: true }).default(''),
  bankName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  accountName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  accountNumber: Joi.string().trim().max(50).allow('', null).default(''),
  promptPayNumber: Joi.string().trim().max(50).allow('', null).default(''),
}).unknown(false);

const adminContactChannelsUpdateSchema = Joi.object({
  guestLookupInquiryBannerEnabled: booleanSetting.default(false),
  guestLookupInquiryBannerMessage: unicodeText({ max: 500, allowEmpty: true }).default(''),
  contactLineEnabled: booleanSetting.default(false),
  contactLineDisplayName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  contactLineAddUrl: Joi.string().trim().max(500).allow('', null).default(''),
  contactLineAccountId: Joi.string().trim().max(100).allow('', null).default(''),
  contactKakaoEnabled: booleanSetting.default(false),
  contactKakaoDisplayName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  contactKakaoAddUrl: Joi.string().trim().max(500).allow('', null).default(''),
  contactKakaoAccountId: Joi.string().trim().max(100).allow('', null).default(''),
  contactWhatsappEnabled: booleanSetting.default(false),
  contactWhatsappDisplayName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  contactWhatsappPhoneNumber: Joi.string().trim().max(30).allow('', null).default(''),
  contactWechatEnabled: booleanSetting.default(false),
  contactWechatDisplayName: unicodeText({ max: 100, allowEmpty: true }).default(''),
  contactWechatAccountId: Joi.string().trim().max(100).allow('', null).default(''),
}).unknown(false);

const adminSettingsImageKindParamsSchema = Joi.object({
  kind: Joi.string().valid('lineQr', 'promptPayQr', 'contactLineQr', 'contactKakaoQr', 'contactWechatQr').required(),
});

module.exports = {
  adminSettingsUpdateSchema,
  adminContactChannelsUpdateSchema,
  adminSettingsImageKindParamsSchema,
};
