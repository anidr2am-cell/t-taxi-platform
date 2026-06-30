const AppError = require('../utils/AppError');
const ERROR_CODES = require('../constants/errorCodes');
const FLIGHT_STATUS = require('../constants/flightStatus');
const FLIGHT_SYNC_CONFIG = require('../constants/flightSyncConfig');
const { parseServiceDateTimeToMs } = require('../utils/serviceDateTime.util');
const logger = require('../utils/logger');

const FINAL_STATUSES = new Set([FLIGHT_STATUS.LANDED, FLIGHT_STATUS.CANCELLED]);
const TRANSIENT_ERRORS = new Set([
  ERROR_CODES.FLIGHT_PROVIDER_TIMEOUT,
  ERROR_CODES.FLIGHT_PROVIDER_ERROR,
  ERROR_CODES.EXTERNAL_API_ERROR,
]);

function sleep(ms) {
  return new Promise((resolve) => {
    const timer = setTimeout(resolve, ms);
    if (timer.unref) timer.unref();
  });
}

class FlightSyncWorker {
  constructor({
    flightMonitorRepository,
    adminFlightMonitorService,
    config,
    nowFn = () => Date.now(),
  }) {
    this.flightMonitorRepository = flightMonitorRepository;
    this.adminFlightMonitorService = adminFlightMonitorService;
    this.config = config;
    this.nowFn = nowFn;
    this.processingBookingIds = new Set();
  }

  getWindow() {
    const now = this.nowFn();
    return {
      start: this.formatSqlDateTime(new Date(now - this.config.lookbackHours * 60 * 60 * 1000)),
      end: this.formatSqlDateTime(new Date(now + this.config.lookaheadHours * 60 * 60 * 1000)),
    };
  }

  formatSqlDateTime(date) {
    return date.toISOString().slice(0, 19).replace('T', ' ');
  }

  getArrivalMs(row) {
    return parseServiceDateTimeToMs(
      row.flight_estimated_arrival_at_text
        ?? row.flight_estimated_arrival_at
        ?? row.flight_scheduled_arrival_at_text
        ?? row.flight_scheduled_arrival_at
        ?? row.scheduled_pickup_at_text
        ?? row.scheduled_pickup_at,
    );
  }

  getRequiredIntervalMs(row) {
    const arrivalMs = this.getArrivalMs(row);
    if (arrivalMs == null) return null;
    const absoluteDistance = Math.abs(arrivalMs - this.nowFn());
    if (absoluteDistance <= FLIGHT_SYNC_CONFIG.NEAR_ARRIVAL_WINDOW_MS) {
      return FLIGHT_SYNC_CONFIG.NEAR_SYNC_INTERVAL_MS;
    }
    if (absoluteDistance <= FLIGHT_SYNC_CONFIG.MID_ARRIVAL_WINDOW_MS) {
      return FLIGHT_SYNC_CONFIG.MID_SYNC_INTERVAL_MS;
    }
    if (absoluteDistance <= FLIGHT_SYNC_CONFIG.FAR_ARRIVAL_WINDOW_MS) {
      return FLIGHT_SYNC_CONFIG.FAR_SYNC_INTERVAL_MS;
    }
    return null;
  }

  isEligibleByPolicy(row) {
    if (FINAL_STATUSES.has(row.flight_status) && row.sync_status === 'SUCCESS') {
      return false;
    }

    const intervalMs = this.getRequiredIntervalMs(row);
    if (intervalMs == null) return false;

    const lastSyncedRaw = row.last_synced_at_text ?? row.last_synced_at;
    const lastSyncedMs = parseServiceDateTimeToMs(lastSyncedRaw);
    if (lastSyncedMs == null) return true;
    return this.nowFn() - lastSyncedMs >= intervalMs;
  }

  prioritize(rows) {
    return [...rows].sort((a, b) => {
      const now = this.nowFn();
      const aDistance = Math.abs((this.getArrivalMs(a) ?? Number.MAX_SAFE_INTEGER) - now);
      const bDistance = Math.abs((this.getArrivalMs(b) ?? Number.MAX_SAFE_INTEGER) - now);
      if (aDistance !== bDistance) return aDistance - bDistance;

      const aActive = a.flight_status === FLIGHT_STATUS.DELAYED || a.flight_status === FLIGHT_STATUS.ACTIVE;
      const bActive = b.flight_status === FLIGHT_STATUS.DELAYED || b.flight_status === FLIGHT_STATUS.ACTIVE;
      if (aActive !== bActive) return aActive ? -1 : 1;

      const aNever = !a.last_synced_at_text && !a.last_synced_at;
      const bNever = !b.last_synced_at_text && !b.last_synced_at;
      if (aNever !== bNever) return aNever ? -1 : 1;

      const aLast = parseServiceDateTimeToMs(a.last_synced_at_text ?? a.last_synced_at) ?? 0;
      const bLast = parseServiceDateTimeToMs(b.last_synced_at_text ?? b.last_synced_at) ?? 0;
      if (aLast !== bLast) return aLast - bLast;

      return Number(a.booking_id) - Number(b.booking_id);
    });
  }

  async loadCandidates() {
    const window = this.getWindow();
    const rows = await this.flightMonitorRepository.listAutoSyncCandidates({
      windowStart: window.start,
      windowEnd: window.end,
      limit: Math.max(this.config.batchSize * 3, this.config.batchSize),
    });
    const seen = new Set();
    return this.prioritize(rows)
      .filter((row) => {
        if (seen.has(row.booking_id)) return false;
        seen.add(row.booking_id);
        return !this.processingBookingIds.has(row.booking_id) && this.isEligibleByPolicy(row);
      })
      .slice(0, this.config.batchSize);
  }

  shouldRetry(err) {
    return TRANSIENT_ERRORS.has(err.errorCode);
  }

  async syncWithRetry(bookingId) {
    let attempt = 0;
    // eslint-disable-next-line no-constant-condition
    while (true) {
      try {
        return await this.adminFlightMonitorService.syncFlight(bookingId, null);
      } catch (err) {
        attempt += 1;
        if (err.errorCode === ERROR_CODES.RATE_LIMIT) {
          return { skipped: true, reason: ERROR_CODES.RATE_LIMIT };
        }
        if (!this.shouldRetry(err) || attempt >= this.config.maxRetries) {
          throw err;
        }
        await sleep(this.config.retryBaseMs * (2 ** (attempt - 1)));
      }
    }
  }

  emptySummary(extra = {}) {
    return {
      selected: 0,
      succeeded: 0,
      skipped: 0,
      failed: 0,
      rateLimited: false,
      configMissing: false,
      durationMs: 0,
      ...extra,
    };
  }

  async runCycle() {
    const startedAt = this.nowFn();
    const summary = this.emptySummary();

    if (!this.config.enabled) {
      summary.skipped = 1;
      summary.durationMs = this.nowFn() - startedAt;
      return summary;
    }

    if (!this.adminFlightMonitorService.flightService.isProviderConfigured()) {
      summary.configMissing = true;
      summary.durationMs = this.nowFn() - startedAt;
      logger.warn('Flight sync worker skipped: provider not configured');
      return summary;
    }

    const candidates = await this.loadCandidates();
    summary.selected = candidates.length;

    for (const candidate of candidates) {
      if (summary.rateLimited) {
        summary.skipped += 1;
        continue;
      }
      this.processingBookingIds.add(candidate.booking_id);
      try {
        const result = await this.syncWithRetry(candidate.booking_id);
        if (result?.skipped) {
          summary.skipped += 1;
        } else {
          summary.succeeded += 1;
        }
      } catch (err) {
        if (err.errorCode === ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED) {
          summary.failed += 1;
          summary.rateLimited = true;
        } else if (err instanceof AppError) {
          summary.failed += 1;
        } else {
          summary.failed += 1;
        }
        logger.warn('Flight sync item failed', {
          bookingId: candidate.booking_id,
          errorCode: err.errorCode ?? ERROR_CODES.INTERNAL_SERVER_ERROR,
        });
      } finally {
        this.processingBookingIds.delete(candidate.booking_id);
      }
    }

    summary.durationMs = this.nowFn() - startedAt;
    logger.info('Flight sync worker cycle completed', summary);
    return summary;
  }
}

module.exports = FlightSyncWorker;
