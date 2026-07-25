/**
 * Vehicle match tiers for open-call eligibility.
 *
 * Hierarchy (match_tier in vehicle_types):
 *   SEDAN=1, SUV=2, VAN=3
 *   VIP_SUV / VIP_VAN / LUXURY = NULL → exact vehicle_type_id only
 *
 * Driver capability = max(match_tier) among APPROVED + is_active vehicles
 * that participate in the hierarchy (non-null match_tier).
 * A VAN-capable driver may take SEDAN/SUV/VAN bookings; never the reverse.
 */

const HIERARCHY_MATCH_TIERS_BY_CODE = Object.freeze({
  SEDAN: 1,
  SUV: 2,
  VAN: 3,
});

const EXACT_MATCH_ONLY_CODES = Object.freeze(['VIP_SUV', 'VIP_VAN', 'LUXURY']);

function matchTierForCode(code) {
  if (code == null) return null;
  const key = String(code).toUpperCase();
  return Object.prototype.hasOwnProperty.call(HIERARCHY_MATCH_TIERS_BY_CODE, key)
    ? HIERARCHY_MATCH_TIERS_BY_CODE[key]
    : null;
}

/**
 * @param {Array<{ code: string, isActive?: boolean, approvalStatus?: string }>} driverVehicles
 * @returns {string[]}
 */
function activeApprovedVehicleCodes(driverVehicles = []) {
  return driverVehicles
    .filter((vehicle) => {
      const active = vehicle.isActive !== false && Number(vehicle.is_active ?? 1) !== 0;
      const status = String(
        vehicle.approvalStatus
          ?? vehicle.approval_status
          ?? 'APPROVED',
      ).toUpperCase();
      return active && status === 'APPROVED' && vehicle.code;
    })
    .map((vehicle) => String(vehicle.code).toUpperCase());
}

/**
 * Whether a driver with the given approved active vehicle codes can see/claim a booking.
 * Mirrors SQL compatibility used by findOpenDriverCallsForDriver / findMatchingVehicle.
 */
function isBookingCompatibleWithDriverVehicles(driverVehicleCodes, bookingVehicleCode) {
  const codes = (driverVehicleCodes || []).map((code) => String(code).toUpperCase());
  const bookingCode = String(bookingVehicleCode || '').toUpperCase();
  if (!bookingCode || codes.length === 0) return false;
  if (codes.includes(bookingCode)) return true;

  const bookingTier = matchTierForCode(bookingCode);
  if (bookingTier == null) return false;

  return codes.some((code) => {
    const driverTier = matchTierForCode(code);
    return driverTier != null && driverTier >= bookingTier;
  });
}

function isExactVehicleMatch(driverVehicleCodes, bookingVehicleCode) {
  const bookingCode = String(bookingVehicleCode || '').toUpperCase();
  return (driverVehicleCodes || [])
    .map((code) => String(code).toUpperCase())
    .includes(bookingCode);
}

/**
 * SQL predicate: driver_vehicles row (alias) covers booking vehicle type (id expression).
 * Expects joins to vt_driver / vt_booking to be provided by the caller, OR use
 * driverVehicleCoversBookingExistsSql which includes joins.
 */
function driverVehicleCoversBookingExistsSql({
  driverIdExpr = 'd.id',
  bookingVehicleTypeIdExpr = 'b.vehicle_type_id',
  vehicleAlias = 'dv_match',
} = {}) {
  return `
    EXISTS (
      SELECT 1
      FROM driver_vehicles ${vehicleAlias}
      INNER JOIN vehicle_types vt_driver
        ON vt_driver.id = ${vehicleAlias}.vehicle_type_id
       AND vt_driver.deleted_at IS NULL
      INNER JOIN vehicle_types vt_booking
        ON vt_booking.id = ${bookingVehicleTypeIdExpr}
       AND vt_booking.deleted_at IS NULL
      WHERE ${vehicleAlias}.driver_id = ${driverIdExpr}
        AND ${vehicleAlias}.is_active = 1
        AND COALESCE(${vehicleAlias}.approval_status, 'APPROVED') = 'APPROVED'
        AND ${vehicleAlias}.deleted_at IS NULL
        AND (
          ${vehicleAlias}.vehicle_type_id = vt_booking.id
          OR (
            vt_booking.match_tier IS NOT NULL
            AND vt_driver.match_tier IS NOT NULL
            AND vt_driver.match_tier >= vt_booking.match_tier
          )
        )
    )
  `;
}

function exactVehicleMatchExistsSql({
  driverIdExpr = 'd.id',
  bookingVehicleTypeIdExpr = 'b.vehicle_type_id',
  vehicleAlias = 'dv_exact',
} = {}) {
  return `
    EXISTS (
      SELECT 1
      FROM driver_vehicles ${vehicleAlias}
      WHERE ${vehicleAlias}.driver_id = ${driverIdExpr}
        AND ${vehicleAlias}.vehicle_type_id = ${bookingVehicleTypeIdExpr}
        AND ${vehicleAlias}.is_active = 1
        AND COALESCE(${vehicleAlias}.approval_status, 'APPROVED') = 'APPROVED'
        AND ${vehicleAlias}.deleted_at IS NULL
    )
  `;
}

/**
 * Subquery selecting one compatible driver_vehicles.id for notify/claim assignment.
 * Prefer exact type, then lowest sufficient match_tier (closest upgrade).
 */
function compatibleDriverVehicleIdSubquerySql({
  driverIdExpr = 'd.id',
  bookingVehicleTypeIdParam = '?',
} = {}) {
  return `
    (
      SELECT dv2.id
      FROM driver_vehicles dv2
      INNER JOIN vehicle_types vt_driver
        ON vt_driver.id = dv2.vehicle_type_id
       AND vt_driver.deleted_at IS NULL
      INNER JOIN vehicle_types vt_booking
        ON vt_booking.id = ${bookingVehicleTypeIdParam}
       AND vt_booking.deleted_at IS NULL
      WHERE dv2.driver_id = ${driverIdExpr}
        AND dv2.is_active = 1
        AND COALESCE(dv2.approval_status, 'APPROVED') = 'APPROVED'
        AND dv2.deleted_at IS NULL
        AND (
          dv2.vehicle_type_id = vt_booking.id
          OR (
            vt_booking.match_tier IS NOT NULL
            AND vt_driver.match_tier IS NOT NULL
            AND vt_driver.match_tier >= vt_booking.match_tier
          )
        )
      ORDER BY
        CASE WHEN dv2.vehicle_type_id = vt_booking.id THEN 0 ELSE 1 END,
        vt_driver.match_tier ASC,
        dv2.is_primary DESC,
        dv2.id ASC
      LIMIT 1
    )
  `;
}

module.exports = {
  HIERARCHY_MATCH_TIERS_BY_CODE,
  EXACT_MATCH_ONLY_CODES,
  matchTierForCode,
  activeApprovedVehicleCodes,
  isBookingCompatibleWithDriverVehicles,
  isExactVehicleMatch,
  driverVehicleCoversBookingExistsSql,
  exactVehicleMatchExistsSql,
  compatibleDriverVehicleIdSubquerySql,
};
