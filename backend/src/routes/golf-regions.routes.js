const express = require('express');
const router = express.Router();

router.get('/',(_req,res)=>res.json({success:true,data:['PATTAYA']}));

module.exports = router;
