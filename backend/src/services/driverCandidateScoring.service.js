const { haversineKm } = require('../utils/geo.util');
const SCORING = require('../constants/driverAssignmentScoring');

const EXCLUSION = {
  INACTIVE_DRIVER: 'INACTIVE_DRIVER',
  USER_INACTIVE: 'USER_INACTIVE',
  SUSPENDED: 'SUSPENDED',
  OFFLINE: 'OFFLINE',
  VEHICLE_MISMATCH: 'VEHICLE_MISMATCH',
  MISSING_VEHICLE: 'MISSING_VEHICLE',
  MAX_ACTIVE_JOBS: 'MAX_ACTIVE_JOBS',
  STALE_LOCATION: 'STALE_LOCATION',
  SETTLEMENT_BLOCKED: 'SETTLEMENT_BLOCKED',
  SCHEDULE_CONFLICT: 'SCHEDULE_CONFLICT',
};

const REASON = {
  VEHICLE_MATCH: 'VEHICLE_MATCH',
  ONLINE: 'ONLINE',
  NO_ACTIVE_JOB: 'NO_ACTIVE_JOB',
  NEAR_PICKUP: 'NEAR_PICKUP',
  LOCATION_FRESH: 'LOCATION_FRESH',
  LOW_ASSIGNMENT_LOAD: 'LOW_ASSIGNMENT_LOAD',
  HIGH_RATING: 'HIGH_RATING',
};

class DriverCandidateScoringService {
  isLocationFresh(driver, now = Date.now()) {
    const updatedAt = driver.location_updated_at || driver.location_recorded_at;
    if (!updatedAt) return false;
    const updatedMs = new Date(updatedAt).getTime();
    if (Number.isNaN(updatedMs)) return false;
    return now - updatedMs <= SCORING.FRESH_LOCATION_MS;
  }

  resolveVehicleTypeId(driver) {
    return driver.primary_vehicle_type_id ?? driver.vehicle_type_id ?? null;
  }

  evaluateEligibility(driver, booking, { settlementBlocked = false } = {}) {
    const reasons = [];

    if (!driver.is_active) reasons.push(EXCLUSION.INACTIVE_DRIVER);
    if (driver.user_is_active === 0) reasons.push(EXCLUSION.USER_INACTIVE);
    if (driver.status === 'SUSPENDED') reasons.push(EXCLUSION.SUSPENDED);
    if (settlementBlocked) reasons.push(EXCLUSION.SETTLEMENT_BLOCKED);

    const vehicleTypeId = this.resolveVehicleTypeId(driver);
    if (!vehicleTypeId || !driver.primary_vehicle_id) {
      reasons.push(EXCLUSION.MISSING_VEHICLE);
    } else if (Number(vehicleTypeId) !== Number(booking.vehicle_type_id)) {
      reasons.push(EXCLUSION.VEHICLE_MISMATCH);
    }

    const activeJobCount = Number(driver.active_assignment_count ?? 0);
    if (activeJobCount >= SCORING.MAX_ACTIVE_JOBS) {
      reasons.push(EXCLUSION.MAX_ACTIVE_JOBS);
    }

    if (SCORING.ONLINE_REQUIRED && (driver.status === 'OFFLINE' || !driver.is_online)) {
      reasons.push(EXCLUSION.OFFLINE);
    }

    if (SCORING.LOCATION_FRESH_REQUIRED && !this.isLocationFresh(driver)) {
      reasons.push(EXCLUSION.STALE_LOCATION);
    }

    if (Number(driver.schedule_conflict_count ?? 0) > 0) {
      reasons.push(EXCLUSION.SCHEDULE_CONFLICT);
    }

    return {
      eligible: reasons.length === 0,
      exclusionReasons: reasons,
    };
  }

  scoreDriver(driver, booking, distanceKm) {
    const reasons = [REASON.VEHICLE_MATCH];
    let score = 0;

    if (driver.is_online && driver.status !== 'OFFLINE') {
      score += SCORING.SCORE_WEIGHTS.ONLINE;
      reasons.push(REASON.ONLINE);
    }

    const activeJobCount = Number(driver.active_assignment_count ?? 0);
    if (activeJobCount === 0) {
      score += SCORING.SCORE_WEIGHTS.NO_ACTIVE_JOB;
      reasons.push(REASON.NO_ACTIVE_JOB);
    }

    if (distanceKm != null) {
      const proximity = Math.max(
        0,
        SCORING.SCORE_WEIGHTS.NEAR_PICKUP_MAX
          * (1 - Math.min(distanceKm, SCORING.NEAR_PICKUP_DISTANCE_KM) / SCORING.NEAR_PICKUP_DISTANCE_KM),
      );
      if (proximity > 0) {
        score += Math.round(proximity);
        reasons.push(REASON.NEAR_PICKUP);
      }
    }

    if (this.isLocationFresh(driver)) {
      score += SCORING.SCORE_WEIGHTS.LOCATION_FRESH;
      reasons.push(REASON.LOCATION_FRESH);
    }

    const assignmentsToday = Number(driver.assignments_today_count ?? 0);
    if (assignmentsToday < SCORING.ASSIGNMENTS_TODAY_LOW_THRESHOLD) {
      score += SCORING.SCORE_WEIGHTS.LOW_ASSIGNMENT_LOAD;
      reasons.push(REASON.LOW_ASSIGNMENT_LOAD);
    }

    const rating = driver.average_rating != null ? Number(driver.average_rating) : null;
    if (rating != null && rating >= SCORING.RATING_THRESHOLD) {
      score += SCORING.SCORE_WEIGHTS.HIGH_RATING;
      reasons.push(REASON.HIGH_RATING);
    }

    return { score, reasons };
  }

  /**
   * Sort eligible candidates: higher score, fewer active jobs, closer distance,
   * oldest last assignment, then lower driverId.
   * Null distance sorts after any known distance (MAX_SAFE_INTEGER).
   * Null lastAssignedAt sorts as epoch 0 (never assigned = oldest for fair rotation).
   */
  compareCandidates(a, b) {
    if (b.score !== a.score) return b.score - a.score;

    const activeDiff = Number(a.activeJobCount) - Number(b.activeJobCount);
    if (activeDiff !== 0) return activeDiff;

    const distA = a.distanceKm ?? Number.MAX_SAFE_INTEGER;
    const distB = b.distanceKm ?? Number.MAX_SAFE_INTEGER;
    if (distA !== distB) return distA - distB;

    const lastA = a.lastAssignedAt ? new Date(a.lastAssignedAt).getTime() : 0;
    const lastB = b.lastAssignedAt ? new Date(b.lastAssignedAt).getTime() : 0;
    if (lastA !== lastB) return lastA - lastB;

    return Number(a.driverId) - Number(b.driverId);
  }

  buildCandidate(driver, booking, { settlementBlocked = false } = {}) {
    const eligibility = this.evaluateEligibility(driver, booking, { settlementBlocked });

    let distanceKm = null;
    if (
      booking.origin_lat != null
      && booking.origin_lng != null
      && driver.current_lat != null
      && driver.current_lng != null
    ) {
      distanceKm = haversineKm(
        booking.origin_lat,
        booking.origin_lng,
        driver.current_lat,
        driver.current_lng,
      );
    }

    const scoring = eligibility.eligible
      ? this.scoreDriver(driver, booking, distanceKm)
      : { score: 0, reasons: [] };

    return {
      driverId: driver.id,
      displayName: driver.name,
      vehicleTypeCode: driver.primary_vehicle_type_code ?? null,
      online: driver.is_online === 1 && driver.status !== 'OFFLINE',
      activeJobCount: Number(driver.active_assignment_count ?? 0),
      distanceKm,
      locationFresh: this.isLocationFresh(driver),
      averageRating: driver.average_rating != null ? Number(driver.average_rating) : null,
      assignmentsTodayCount: Number(driver.assignments_today_count ?? 0),
      lastAssignedAt: driver.last_assigned_at ?? null,
      score: scoring.score,
      reasons: scoring.reasons,
      eligible: eligibility.eligible,
      exclusionReasons: eligibility.exclusionReasons,
    };
  }

  rankCandidates(candidates) {
    const eligible = candidates.filter((row) => row.eligible).sort((a, b) => this.compareCandidates(a, b));
    const excluded = candidates.filter((row) => !row.eligible);
    return { eligible, excluded };
  }
}

module.exports = DriverCandidateScoringService;
module.exports.EXCLUSION = EXCLUSION;
module.exports.REASON = REASON;
