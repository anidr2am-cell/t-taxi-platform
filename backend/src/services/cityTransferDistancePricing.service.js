const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const VEHICLE_TYPES = require('../constants/vehicleTypes');
const { estimateRoadDistanceKm } = require('../utils/geo.util');
const {
  MIN_AUTO_QUOTE_DISTANCE_KM,
  MAX_AUTO_QUOTE_DISTANCE_KM,
} = require('../constants/cityTransferDistance.constants');

const SUPPORTED_VEHICLE_TYPES = new Set([
  VEHICLE_TYPES.SEDAN,
  VEHICLE_TYPES.SUV,
  VEHICLE_TYPES.VAN,
]);

const VEHICLE_PRICE_FIELD = {
  [VEHICLE_TYPES.SEDAN]: 'sedanPrice',
  [VEHICLE_TYPES.SUV]: 'suvPrice',
  [VEHICLE_TYPES.VAN]: 'vanPrice',
};

class CityTransferDistancePricingService {
  constructor(cityTransferDistanceBandRepository) {
    this.cityTransferDistanceBandRepository = cityTransferDistanceBandRepository;
  }

  throwInquiryRequired(message) {
    throw new AppError(message, {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.INQUIRY_REQUIRED,
    });
  }

  resolveVehiclePrice(band, vehicleTypeCode) {
    const normalizedCode = String(vehicleTypeCode ?? '').trim().toUpperCase();
    if (!SUPPORTED_VEHICLE_TYPES.has(normalizedCode)) {
      return null;
    }
    const field = VEHICLE_PRICE_FIELD[normalizedCode];
    const price = band[field];
    if (price == null || !Number.isFinite(Number(price)) || Number(price) <= 0) {
      return null;
    }
    return {
      vehicleTypeCode: normalizedCode,
      price: Number(price),
      currency: band.currency,
    };
  }

  async calculateByDistance(originLat, originLng, destLat, destLng, vehicleTypeCode) {
    const estimatedDistanceKm = estimateRoadDistanceKm(
      originLat,
      originLng,
      destLat,
      destLng,
    );

    if (estimatedDistanceKm == null) {
      this.throwInquiryRequired('Pricing inquiry required for invalid coordinates');
    }

    if (estimatedDistanceKm < MIN_AUTO_QUOTE_DISTANCE_KM) {
      this.throwInquiryRequired('Pricing inquiry required for short distance');
    }

    if (estimatedDistanceKm > MAX_AUTO_QUOTE_DISTANCE_KM) {
      this.throwInquiryRequired('Pricing inquiry required for long distance');
    }

    const band = await this.cityTransferDistanceBandRepository.findActiveBandByDistance(
      estimatedDistanceKm,
    );
    if (!band) {
      this.throwInquiryRequired('Pricing inquiry required for unmatched distance band');
    }

    const vehiclePrice = this.resolveVehiclePrice(band, vehicleTypeCode);
    if (!vehiclePrice) {
      this.throwInquiryRequired('Pricing inquiry required for unsupported vehicle type');
    }

    return {
      band,
      estimatedDistanceKm,
      vehicleTypeCode: vehiclePrice.vehicleTypeCode,
      price: vehiclePrice.price,
      currency: vehiclePrice.currency,
    };
  }
}

module.exports = CityTransferDistancePricingService;
