const express = require('express');
const router = express.Router();

const asyncHandler=require('../utils/asyncHandler');
const {success}=require('../utils/apiResponse');
const Repository=require('../repositories/golfPricing.repository');
router.get('/',asyncHandler(async(req,res)=>success(res,await new Repository().listCourses(req.query.region||null))));

module.exports = router;
