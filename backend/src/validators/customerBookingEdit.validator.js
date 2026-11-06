const Joi=require('joi');
const {isValidFlightNumber,normalizeFlightNumber}=require('../utils/flightNumber.util');
const update=Joi.object({revision:Joi.string().hex().length(64).required(),customer:Joi.object({
 phone:Joi.string().trim().pattern(/^\+[1-9]\d{6,14}$/),email:Joi.string().trim().email().max(255).allow(null,''),
 messengerType:Joi.string().valid('KAKAO','LINE','WHATSAPP','WECHAT','TELEGRAM','SMS'),messengerId:Joi.string().trim().max(100).allow(null,'')}).min(1),
 flightNumber:Joi.string().trim().max(20).allow(null,'').custom((v,h)=>!v||isValidFlightNumber(v)?(v?normalizeFlightNumber(v):null):h.error('any.invalid')),
 specialRequests:Joi.string().trim().max(2000).allow(null,''),changeRequest:Joi.string().trim().min(1).max(2000)}).or('customer','flightNumber','specialRequests','changeRequest');
module.exports={update};
