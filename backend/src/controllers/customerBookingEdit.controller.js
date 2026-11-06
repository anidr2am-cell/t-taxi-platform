const container=require('../helpers/container');
const handle=(write)=>async(req,res,next)=>{try{const data=await container.get('customerBookingEditService').run(req.params.bookingNumber,req.user??null,req.headers['x-guest-access-token']??null,write?req.body:null);res.set('Cache-Control','no-store');res.json({success:true,data});}catch(e){next(e);}};
module.exports={get:handle(false),update:handle(true)};
