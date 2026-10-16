const Joi=require('joi');
module.exports=Joi.object({
  courseId:Joi.number().integer().positive().required(),
  tripType:Joi.string().valid('ROUND_TRIP','OUTBOUND','RETURN').required(),
  holes:Joi.when('tripType',{is:'ROUND_TRIP',then:Joi.number().valid(18,27,36).required(),otherwise:Joi.number().valid(18,27,36).allow(null).optional()}),
});
