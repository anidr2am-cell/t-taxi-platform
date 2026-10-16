const express=require('express');
const {authMiddleware}=require('../middlewares/auth.middleware');
const roleMiddleware=require('../middlewares/role.middleware');
const ROLES=require('../constants/roles');
const validate=require('../middlewares/validate.middleware');
const Joi=require('joi');
const asyncHandler=require('../utils/asyncHandler');
const {success}=require('../utils/apiResponse');
const AppError=require('../utils/AppError');
const Repository=require('../repositories/golfPricing.repository');
const router=express.Router();
router.use('/golf',authMiddleware,roleMiddleware([ROLES.ADMIN,ROLES.SUPER_ADMIN]));
router.get('/golf/prices',asyncHandler(async(_req,res)=>success(res,await new Repository().listPrices())));
router.get('/golf/courses',asyncHandler(async(_req,res)=>success(res,await new Repository().listCourses())));
router.patch('/golf/prices/:id',validate({params:Joi.object({id:Joi.number().integer().positive().required()}),body:Joi.object({price:Joi.number().integer().positive().max(1000000).required()})}),asyncHandler(async(req,res)=>{
 if(!await new Repository().updatePrice(Number(req.params.id),req.body.price,req.user.id)) throw new AppError('Golf fare not found',{statusCode:404,errorCode:'NOT_FOUND'});
 return success(res,{updated:true});
}));
module.exports=router;
