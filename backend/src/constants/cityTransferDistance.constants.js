/**
 * CITY_TRANSFER distance-based pricing bounds and road-distance estimation.
 */
module.exports = {
  /** Multiplier applied to haversine (straight-line) km to estimate road distance. */
  ROAD_DISTANCE_CORRECTION_FACTOR: 1.3,
  /** Difference from a configured route distance that remains included in the base fare. */
  ROUTE_DISTANCE_INCLUDED_KM: 10,
  /** Started distance block charged after the included difference. */
  ROUTE_DISTANCE_STEP_KM: 10,
  /** THB charged per started distance block, per vehicle. */
  ROUTE_DISTANCE_STEP_PRICE: 100,
  /** Distances below this km (exclusive upper bound of auto-quote) require manual inquiry. */
  MIN_AUTO_QUOTE_DISTANCE_KM: 12,
  /** Distances above this km require manual inquiry. */
  MAX_AUTO_QUOTE_DISTANCE_KM: 200,
};
