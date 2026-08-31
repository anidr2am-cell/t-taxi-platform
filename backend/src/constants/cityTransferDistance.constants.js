/**
 * CITY_TRANSFER distance-based pricing bounds and road-distance estimation.
 */
module.exports = {
  /** Multiplier applied to haversine (straight-line) km to estimate road distance. */
  ROAD_DISTANCE_CORRECTION_FACTOR: 1.3,
  /** Distances below this km (exclusive upper bound of auto-quote) require manual inquiry. */
  MIN_AUTO_QUOTE_DISTANCE_KM: 12,
  /** Distances above this km require manual inquiry. */
  MAX_AUTO_QUOTE_DISTANCE_KM: 200,
};
