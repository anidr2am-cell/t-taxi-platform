const VEHICLE_TYPES = require('../constants/vehicleTypes');

const DRIVER_REGISTRATION_EXCLUDED_CODES = Object.freeze([VEHICLE_TYPES.VIP_VAN]);

function isDriverRegistrationVehicleType(code) {
  const normalized = String(code ?? '').trim().toUpperCase();
  return normalized.length > 0 && !DRIVER_REGISTRATION_EXCLUDED_CODES.includes(normalized);
}

module.exports = {
  DRIVER_REGISTRATION_EXCLUDED_CODES,
  isDriverRegistrationVehicleType,
};
