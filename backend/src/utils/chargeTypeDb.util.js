const CHARGE_TYPES = require('../constants/chargeTypes');

/**
 * Maps canonical charge types to values accepted by older DB enums.
 */
const DB_CHARGE_TYPE_ALIASES = {
  [CHARGE_TYPES.AIRPORT_SURCHARGE]: 'AIRPORT_PARKING',
  [CHARGE_TYPES.WAITING_CHARGE]: 'OTHER',
};

function toDatabaseChargeType(chargeType) {
  return DB_CHARGE_TYPE_ALIASES[chargeType] || chargeType;
}

module.exports = {
  toDatabaseChargeType,
};
