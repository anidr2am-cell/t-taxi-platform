const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const SERVICE_TYPES = require('../constants/serviceTypes');
const FLIGHT_STATUS = require('../constants/flightStatus');
const FLIGHT_SYNC_STATUS = require('../constants/flightSyncStatus');
const FLIGHT_SYNC_CONFIG = require('../constants/flightSyncConfig');
const { EVENTS } = require('../events');
const { isNotificationOutboxEvent } = require('../utils/outboxPayload.util');
const { parseServiceDateTimeToMs } = require('../utils/serviceDateTime.util');

const TERMINAL_BOOKING_STATUSES = new Set(['COMPLETED', 'CANCELLED', 'NO_SHOW']);
const CONFIG_MISSING = 'CONFIG_MISSING';

class AdminFlightMonitorService {
  constructor(
    pool,
    flightMonitorRepository,
    flightService,
    bookingRepository,
    outboxRepository,
    outboxProcessor,
    options = {},
  ) {
    this.pool = pool;
    this.flightMonitorRepository = flightMonitorRepository;
    this.flightService = flightService;
    this.bookingRepository = bookingRepository;
    this.outboxRepository = outboxRepository;
    this.outboxProcessor = outboxProcessor;
    this.syncEnabled = options.syncEnabled !== false;
    this.minSyncIntervalMs = options.minSyncIntervalMs ?? FLIGHT_SYNC_CONFIG.MIN_INTERVAL_MS;
    this.delayNotificationDeltaMinutes = options.delayNotificationDeltaMinutes
      ?? FLIGHT_SYNC_CONFIG.DELAY_NOTIFICATION_DELTA_MINUTES;
    this.nowFn = options.nowFn ?? (() => Date.now());
  }

  parsePagination(query) {
    const page = Math.max(Number(query.page) || 1, 1);
    const pageSize = Math.min(Math.max(Number(query.page_size ?? query.limit) || 20, 1), 100);
    return { page, pageSize };
  }

  parseListFilters(query) {
    return {
      date: query.date ? String(query.date).trim() : null,
      flightNumber: query.flightNumber
        ? this.flightService.normalizeFlightNumber(query.flightNumber)
        : null,
      status: query.status ? String(query.status).trim().toUpperCase() : null,
      delayedOnly: query.delayedOnly === true
        || query.delayedOnly === 'true'
        || query.delayedOnly === '1',
      bookingNumber: query.bookingNumber
        ? String(query.bookingNumber).trim().toUpperCase()
        : null,
    };
  }

  mapRow(row) {
    if (!row) return null;
    return {
      bookingId: row.booking_id,
      bookingNumber: row.booking_number,
      bookingStatus: row.booking_status,
      scheduledPickupAt: row.scheduled_pickup_at_text ?? row.scheduled_pickup_at,
      flightNumber: row.flight_number,
      airlineCode: row.airline_code,
      flightDate: row.flight_date,
      departureAirportIata: row.departure_airport_iata,
      arrivalAirportIata: row.arrival_airport_iata,
      scheduledArrivalAt: row.flight_scheduled_arrival_at_text ?? row.flight_scheduled_arrival_at,
      estimatedArrivalAt: row.flight_estimated_arrival_at_text ?? row.flight_estimated_arrival_at,
      actualArrivalAt: row.flight_actual_arrival_at_text ?? row.flight_actual_arrival_at,
      delayMinutes: row.delay_minutes == null ? null : Number(row.delay_minutes),
      delayStatus: row.delay_status,
      flightStatus: row.flight_status,
      lastSyncedAt: row.last_synced_at_text ?? row.last_synced_at,
      syncStatus: row.sync_status,
      syncError: row.sync_error,
    };
  }

  async listFlights(query) {
    const pagination = this.parsePagination(query);
    const filters = this.parseListFilters(query);
    const result = await this.flightMonitorRepository.listFlights(filters, pagination);
    return {
      page: pagination.page,
      pageSize: pagination.pageSize,
      total: result.total,
      items: result.rows.map((row) => this.mapRow(row)),
    };
  }

  async getFlightDetail(bookingId) {
    const row = await this.flightMonitorRepository.findFlightBookingById(bookingId);
    if (!row) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }
    if (row.service_type_code !== SERVICE_TYPES.AIRPORT_PICKUP || !row.flight_number) {
      throw new AppError('Booking is not eligible for flight monitoring', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }
    return this.mapRow(row);
  }

  deriveFlightDate(row) {
    if (row.flight_date) {
      const value = row.flight_date instanceof Date
        ? row.flight_date.toISOString().slice(0, 10)
        : String(row.flight_date).slice(0, 10);
      return value;
    }
    const source = row.scheduled_pickup_at_text ?? row.scheduled_pickup_at;
    if (!source) return null;
    return String(source).slice(0, 10);
  }

  parseProviderDateTime(value) {
    if (!value) return null;
    const parsed = Date.parse(value);
    if (Number.isNaN(parsed)) return null;
    return new Date(parsed).toISOString().slice(0, 19).replace('T', ' ');
  }

  buildDelayStatus(delayMinutes) {
    if (!delayMinutes || delayMinutes <= 0) return 'On time';
    return `Delayed ${delayMinutes} min`;
  }

  mapProviderToTransferUpdate(providerResult, flightDate) {
    return {
      airlineCode: providerResult.airlineCode,
      flightDate,
      departureAirportIata: providerResult.departure?.airportCode ?? null,
      arrivalAirportIata: providerResult.arrival?.airportCode ?? null,
      flightScheduledArrivalAt: this.parseProviderDateTime(providerResult.arrival?.scheduledAt),
      flightEstimatedArrivalAt: this.parseProviderDateTime(providerResult.arrival?.estimatedAt),
      flightActualArrivalAt: this.parseProviderDateTime(providerResult.arrival?.actualAt),
      delayMinutes: providerResult.delayMinutes ?? 0,
      delayStatus: this.buildDelayStatus(providerResult.delayMinutes ?? 0),
      flightStatus: providerResult.status ?? FLIGHT_STATUS.UNKNOWN,
    };
  }

  assertSyncAllowed(row) {
    if (row.service_type_code !== SERVICE_TYPES.AIRPORT_PICKUP || !row.flight_number) {
      throw new AppError('Booking is not eligible for flight sync', {
        statusCode: HTTP_STATUS.UNPROCESSABLE_ENTITY,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    if (TERMINAL_BOOKING_STATUSES.has(row.booking_status)) {
      throw new AppError('Flight sync is not allowed for completed or cancelled bookings', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
      });
    }
  }

  resolveLastSyncedAt(row) {
    return row.last_synced_at_text ?? row.last_synced_at;
  }

  assertSyncCooldown(row) {
    const lastSyncedRaw = this.resolveLastSyncedAt(row);
    if (lastSyncedRaw == null || lastSyncedRaw === '') return;

    const lastSyncedMs = parseServiceDateTimeToMs(lastSyncedRaw);
    if (lastSyncedMs == null) return;

    const elapsed = this.nowFn() - lastSyncedMs;
    if (elapsed < this.minSyncIntervalMs) {
      throw new AppError('Flight sync was requested too soon after the previous sync', {
        statusCode: HTTP_STATUS.TOO_MANY_REQUESTS,
        errorCode: ERROR_CODES.RATE_LIMIT,
      });
    }
  }

  buildNotificationEvents(previous, next, bookingId, bookingNumber) {
    const events = [];
    const basePayload = { bookingId, bookingNumber };

    if (
      next.flightStatus === FLIGHT_STATUS.CANCELLED
      && previous.flight_status !== FLIGHT_STATUS.CANCELLED
    ) {
      events.push({
        eventType: EVENTS.FLIGHT_CANCELLED,
        payload: {
          ...basePayload,
          eventId: `flight:cancelled:${bookingId}:${next.flightStatus}`,
          flightStatus: next.flightStatus,
        },
      });
    }

    if (
      next.flightStatus === FLIGHT_STATUS.LANDED
      && previous.flight_status !== FLIGHT_STATUS.LANDED
    ) {
      events.push({
        eventType: EVENTS.FLIGHT_LANDED,
        payload: {
          ...basePayload,
          eventId: `flight:landed:${bookingId}:${next.flightActualArrivalAt ?? next.flightStatus}`,
          flightStatus: next.flightStatus,
        },
      });
    }

    const prevDelay = Number(previous.delay_minutes ?? 0);
    const nextDelay = Number(next.delayMinutes ?? 0);
    const delayChanged = Math.abs(nextDelay - prevDelay) >= this.delayNotificationDeltaMinutes;
    const becameDelayed = nextDelay > 0
      && (prevDelay <= 0 || next.flightStatus === FLIGHT_STATUS.DELAYED);
    if (
      nextDelay > 0
      && (delayChanged || previous.flight_status !== next.flightStatus)
      && (becameDelayed || nextDelay > prevDelay)
    ) {
      events.push({
        eventType: EVENTS.FLIGHT_DELAYED,
        payload: {
          ...basePayload,
          eventId: `flight:delayed:${bookingId}:${nextDelay}:${next.flightStatus}`,
          delayMinutes: nextDelay,
          flightStatus: next.flightStatus,
        },
      });
    }

    return events;
  }

  mapSyncFailure(errorCode) {
    if (errorCode === ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED) {
      return FLIGHT_SYNC_STATUS.RATE_LIMITED;
    }
    return FLIGHT_SYNC_STATUS.FAILED;
  }

  async persistSyncResult(conn, bookingId, actorUserId, previousRow, update, syncMeta) {
    await this.flightMonitorRepository.updateFlightSync(conn, bookingId, {
      ...update,
      lastSyncedAt: syncMeta.lastSyncedAt,
      syncStatus: syncMeta.syncStatus,
      syncError: syncMeta.syncError,
    });

    await this.bookingRepository.insertActivityLog(conn, bookingId, {
      activityType: 'FLIGHT_SYNC_UPDATED',
      actorUserId,
      actorRole: actorUserId ? 'ADMIN' : 'SYSTEM',
      description: 'Flight data synchronized',
      payload: {
        syncStatus: syncMeta.syncStatus,
        flightStatus: update.flightStatus,
        delayMinutes: update.delayMinutes,
      },
    });

    const outboxIds = [];
    if (this.outboxRepository && syncMeta.syncStatus === FLIGHT_SYNC_STATUS.SUCCESS) {
      const events = this.buildNotificationEvents(previousRow, update, bookingId, previousRow.booking_number);
      for (const event of events) {
        if (!isNotificationOutboxEvent(event.eventType)) continue;
        const outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
          aggregateId: bookingId,
          eventType: event.eventType,
          payload: event.payload,
        });
        outboxIds.push(outboxId);
      }
    }
    return outboxIds;
  }

  async syncFlight(bookingId, actorUser) {
    const row = await this.flightMonitorRepository.findFlightBookingById(bookingId);
    if (!row) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
      });
    }

    this.assertSyncAllowed(row);
    this.assertSyncCooldown(row);

    const flightNumber = this.flightService.normalizeFlightNumber(row.flight_number);
    const flightDate = this.deriveFlightDate(row);
    if (!flightDate) {
      throw new AppError('Flight date is required for sync', {
        statusCode: HTTP_STATUS.UNPROCESSABLE_ENTITY,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const nowSql = new Date().toISOString().slice(0, 19).replace('T', ' ');
    const actorUserId = actorUser?.id ?? null;

    if (!this.syncEnabled || !this.flightService.isProviderConfigured()) {
      const conn = await this.pool.getConnection();
      try {
        await conn.beginTransaction();
        await this.persistSyncResult(conn, bookingId, actorUserId, row, {
          airlineCode: row.airline_code,
          flightDate: row.flight_date ?? flightDate,
          departureAirportIata: row.departure_airport_iata,
          arrivalAirportIata: row.arrival_airport_iata,
          flightScheduledArrivalAt: row.flight_scheduled_arrival_at,
          flightEstimatedArrivalAt: row.flight_estimated_arrival_at,
          flightActualArrivalAt: row.flight_actual_arrival_at,
          delayMinutes: row.delay_minutes ?? 0,
          delayStatus: row.delay_status,
          flightStatus: row.flight_status,
        }, {
          lastSyncedAt: nowSql,
          syncStatus: FLIGHT_SYNC_STATUS.NOT_CONFIGURED,
          syncError: CONFIG_MISSING,
        });
        await conn.commit();
      } catch (err) {
        await conn.rollback();
        throw err;
      } finally {
        conn.release();
      }

      return {
        ...this.mapRow(await this.flightMonitorRepository.findFlightBookingById(bookingId)),
        providerConfigured: false,
      };
    }

    let providerResult;
    try {
      providerResult = await this.flightService.search({ flightNumber, flightDate });
    } catch (err) {
      const syncStatus = this.mapSyncFailure(err.errorCode);
      const conn = await this.pool.getConnection();
      try {
        await conn.beginTransaction();
        await this.persistSyncResult(conn, bookingId, actorUserId, row, {
          airlineCode: row.airline_code,
          flightDate: row.flight_date ?? flightDate,
          departureAirportIata: row.departure_airport_iata,
          arrivalAirportIata: row.arrival_airport_iata,
          flightScheduledArrivalAt: row.flight_scheduled_arrival_at,
          flightEstimatedArrivalAt: row.flight_estimated_arrival_at,
          flightActualArrivalAt: row.flight_actual_arrival_at,
          delayMinutes: row.delay_minutes ?? 0,
          delayStatus: row.delay_status,
          flightStatus: row.flight_status,
        }, {
          lastSyncedAt: nowSql,
          syncStatus,
          syncError: err.errorCode ?? err.message,
        });
        await conn.commit();
      } catch (persistErr) {
        await conn.rollback();
        throw persistErr;
      } finally {
        conn.release();
      }
      throw err;
    }

    const update = this.mapProviderToTransferUpdate(providerResult, flightDate);
    const conn = await this.pool.getConnection();
    let outboxIds = [];
    try {
      await conn.beginTransaction();
      outboxIds = await this.persistSyncResult(conn, bookingId, actorUserId, row, update, {
        lastSyncedAt: nowSql,
        syncStatus: FLIGHT_SYNC_STATUS.SUCCESS,
        syncError: null,
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    if (this.outboxProcessor && outboxIds.length) {
      await this.outboxProcessor.dispatchOutboxIds(outboxIds);
    }

    return {
      ...this.mapRow(await this.flightMonitorRepository.findFlightBookingById(bookingId)),
      providerConfigured: true,
    };
  }
}

module.exports = AdminFlightMonitorService;
