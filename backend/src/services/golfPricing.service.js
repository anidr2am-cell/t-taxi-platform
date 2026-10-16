const AppError=require('../utils/AppError');
const {matchRegion}=require('../utils/pricingRegion.util');
const inquiry=()=>new AppError('Fare inquiry required',{statusCode:422,errorCode:'INQUIRY_REQUIRED'});
class GolfPricingService {
  constructor(repository,regions,pricing) { this.repository=repository;this.regions=regions;this.pricing=pricing; }
  async calculate(input) {
    const golf=input.golf;
    // Explicit choices are required. A missing/retired course remains an inquiry.
    if (!golf || !['ROUND_TRIP','OUTBOUND','RETURN'].includes(golf.tripType) ||
        (golf.tripType==='ROUND_TRIP' && ![18,27,36].includes(golf.holes))) throw inquiry();
    const course=await this.repository.findCourse(golf.courseId);
    if (!course || input.originAirportIata || input.destinationAirportIata) throw inquiry();
    const reverse=golf.tripType==='RETURN';
    const regions=await this.regions.list();
    const lat=reverse?input.destinationLat:input.originLat;
    const lng=reverse?input.destinationLng:input.originLng;
    const locationCode=reverse?input.destinationLocationCode:input.originLocationCode;
    const iata=regions.some(r=>r.airport_iata===locationCode)?locationCode:null;
    const region=matchRegion(regions,lat,lng,iata);
    if (!region || region.airport_iata || region.fare_location_code!=='PATTAYA') throw inquiry();
    // The chosen course must also be the actual route endpoint. This prevents
    // submitting a cheap course ID alongside an unrelated destination.
    const {haversineKm}=require('../utils/geo.util');
    const courseLat=reverse?input.originLat:input.destinationLat;
    const courseLng=reverse?input.originLng:input.destinationLng;
    if ([courseLat,courseLng].some(x=>x==null || !Number.isFinite(Number(x))) ||
        haversineKm(Number(courseLat),Number(courseLng),course.lat,course.lng)>0.5) throw inquiry();
    const vehicle=await this.pricing.vehicleRepository.findTypeByCode(input.vehicleTypeCode);
    if (!vehicle || !['SEDAN','SUV','VAN'].includes(vehicle.code)) throw inquiry();
    const holes=golf.tripType==='ROUND_TRIP'?golf.holes:18;
    const price=await this.repository.findPrice(course.fareGroup,vehicle.code,holes);
    if (!price) throw inquiry();
    const unitPrice=golf.tripType==='ROUND_TRIP'?price.price:price.price/2;
    const quantity=input.vehicleCount??1;
    const baseAmount=unitPrice*quantity;
    const result=await this.pricing.appendPolicyChargeItems({
      chargeItems:[{chargeType:'VEHICLE_BASE',description:`GOLF ${course.code} ${golf.tripType} ${holes}`,quantity,unitPrice,amount:baseAmount,referenceType:'GOLF_GROUP_PRICE',referenceId:price.id}],
      baseAmount,options:input.options??{},serviceTypeCode:'GOLF_TRANSFER',scheduledPickupAt:input.scheduledPickupAt,customerFacing:true,
    });
    return {...this.pricing.formatCalculateResponse({...result,currency:'THB'}),pricingMode:'GOLF_FIXED',
      golf:{courseId:course.id,courseName:course.name,tripType:golf.tripType,holes:golf.tripType==='ROUND_TRIP'?holes:null,roundTripIncludesWaiting:golf.tripType==='ROUND_TRIP'}};
  }
}
module.exports=GolfPricingService;
