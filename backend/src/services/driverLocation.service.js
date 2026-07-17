const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { hashToken } = require('../utils/tokenHash.util');
const {
  FRESH_LOCATION_MS,
  TRACKABLE_BOOKING_STATUSES,
  TERMINAL_BOOKING_STATUSES,
} = require('../constants/driverLocation');

class DriverLocationService {
  constructor(pool, driverLocationRepository) {
    this.pool = pool;
    this.driverLocationRepository = driverLocationRepository;
  }

  toSqlDateTime(date) {
    return date.toISOString().slice(0, 19).replace('T', ' ');
  }

  parseRecordedAt(value) {
    if (!value) return new Date();
    const date = new Date(value);
    if (Number.isNaN(date.getTime())) {
      throw new AppError('Validation failed', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
        errors: [{ field: 'recordedAt', message: 'recordedAt must be a valid ISO timestamp', source: 'body' }],
      });
    }
    const now = Date.now();
    const ageMs = now - date.getTime();
    if (ageMs > 10 * 60_000 || ageMs < -2 * 60_000) {
      throw new AppError('Validation failed', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
        errors: [{ field: 'recordedAt', message: 'recordedAt is outside the accepted time window', source: 'body' }],
      });
    }
    return date;
  }

  validationError(field, message) {
    return new AppError('Validation failed', {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
      errors: [{ field, message, source: 'body' }],
    });
  }

  validateLocationInput(input) {
    const latitude = Number(input.latitude);
    const longitude = Number(input.longitude);
    if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90) {
      throw this.validationError('latitude', 'latitude must be between -90 and 90');
    }
    if (!Number.isFinite(longitude) || longitude < -180 || longitude > 180) {
      throw this.validationError('longitude', 'longitude must be between -180 and 180');
    }
    const accuracyMeters = input.accuracyMeters == null ? null : Number(input.accuracyMeters);
    if (accuracyMeters != null && (!Number.isFinite(accuracyMeters) || accuracyMeters < 0 || accuracyMeters > 5000)) {
      throw this.validationError('accuracyMeters', 'accuracyMeters must be between 0 and 5000');
    }
    const heading = input.heading == null ? null : Number(input.heading);
    if (heading != null && (!Number.isFinite(heading) || heading < 0 || heading > 359)) {
      throw this.validationError('heading', 'heading must be between 0 and 359');
    }
    const speedKph = input.speedKph == null ? null : Number(input.speedKph);
    if (speedKph != null && (!Number.isFinite(speedKph) || speedKph < 0 || speedKph > 240)) {
      throw this.validationError('speedKph', 'speedKph must be between 0 and 240');
    }
    return { latitude, longitude, accuracyMeters, heading, speedKph };
  }

  isStale(value, now = new Date()) {
    if (!value) return true;
    const time = new Date(value).getTime();
    if (Number.isNaN(time)) return true;
    return now.getTime() - time > FRESH_LOCATION_MS;
  }

  isDuplicateOrOlderLocation(existingRecordedAt, recordedAt) {
    if (!existingRecordedAt) return false;
    const existingTime = new Date(existingRecordedAt).getTime();
    if (Number.isNaN(existingTime)) return false;
    return recordedAt.getTime() <= existingTime;
  }

  vehicleSummary(row) {
    const parts = [row.vehicle_type_name, row.vehicle_model, row.vehicle_plate].filter(Boolean);
    return parts.length ? parts.join(' / ') : null;
  }

  mapLocationRow(row, { includeBooking = false } = {}) {
    if (!row || row.current_lat == null || row.current_lng == null) return null;
    const mapped = {
      driverId: Number(row.driver_id),
      displayName: row.driver_name,
      vehicle: this.vehicleSummary(row),
      latitude: Number(row.current_lat),
      longitude: Number(row.current_lng),
      accuracyMeters: row.current_accuracy_meters == null ? null : Number(row.current_accuracy_meters),
      heading: row.current_heading == null ? null : Number(row.current_heading),
      speedKph: row.current_speed_kph == null ? null : Number(row.current_speed_kph),
      recordedAt: row.location_recorded_at,
      lastSeenAt: row.last_seen_at ?? row.location_updated_at,
      online: row.is_online == null ? undefined : Boolean(row.is_online),
      stale: this.isStale(row.location_updated_at),
    };
    if (includeBooking) {
      mapped.activeBooking = row.booking_number
        ? { bookingNumber: row.booking_number, status: row.booking_status }
        : null;
    }
    return mapped;
  }

  async updateDriverLocation(driverUserId, input) {
    const normalized = this.validateLocationInput(input);
    const recordedAt = this.parseRecordedAt(input.recordedAt);
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const driver = await this.driverLocationRepository.findDriverByUserIdForUpdate(conn, driverUserId);
      if (!driver || !driver.is_active) {
        throw new AppError('Driver not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
        });
      }
      if (!driver.is_online || driver.status === 'OFFLINE' || driver.status === 'SUSPENDED') {
        throw new AppError('Driver is not online', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_AVAILABLE,
        });
      }
      const hasActiveJob = await this.driverLocationRepository.hasActiveJob(conn, driver.id);
      if (!hasActiveJob) {
        throw new AppError('Driver has no active job to share location', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.NO_ACTIVE_ASSIGNMENT,
        });
      }
      if (this.isDuplicateOrOlderLocation(driver.location_recorded_at, recordedAt)) {
        await conn.commit();
        return {
          driverId: driver.id,
          accepted: false,
          reason: 'STALE_LOCATION',
          recordedAt: recordedAt.toISOString(),
          bookingIds: [],
        };
      }
      await this.driverLocationRepository.updateCurrentLocation(conn, driver.id, {
        latitude: normalized.latitude,
        longitude: normalized.longitude,
        accuracyMeters: normalized.accuracyMeters,
        heading: normalized.heading == null ? null : Math.round(normalized.heading),
        speedKph: normalized.speedKph,
        recordedAtSql: this.toSqlDateTime(recordedAt),
      });
      await conn.commit();
      const bookingIds = await this.driverLocationRepository.listActiveBookingRoomsForDriver(driver.id);
      return {
        driverId: driver.id,
        accepted: true,
        recordedAt: recordedAt.toISOString(),
        bookingIds,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async listAdminLocations(filters = {}) {
    const rows = await this.driverLocationRepository.listAdminDriverLocations(filters);
    let items = rows.map((row) => this.mapLocationRow(row, { includeBooking: true })).filter(Boolean);
    if (filters.staleOnly) {
      items = items.filter((item) => item.stale);
    }
    return { items };
  }

  async getGuestDriverLocation(bookingId, guestAccessToken) {
    const token = String(guestAccessToken ?? '').trim();
    if (!token) {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    }
    const row = await this.driverLocationRepository.findGuestAssignedDriverLocation(
      bookingId,
      hashToken(token),
    );
    if (!row) {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    }
    if (TERMINAL_BOOKING_STATUSES.has(row.booking_status) || !TRACKABLE_BOOKING_STATUSES.has(row.booking_status)) {
      return { available: false, reason: 'BOOKING_NOT_TRACKABLE', driver: null };
    }
    const driver = this.mapLocationRow(row);
    if (!driver) {
      return { available: false, reason: 'LOCATION_UNAVAILABLE', driver: null };
    }
    return { available: true, driver };
  }

  async canGuestAccessBooking(bookingId, guestAccessToken) {
    const result = await this.getGuestDriverLocation(bookingId, guestAccessToken);
    return Boolean(result);
  }
}

module.exports = DriverLocationService;
