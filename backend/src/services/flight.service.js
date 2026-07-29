const axios = require('axios');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const logger = require('../utils/logger');
const { createFlightProviderAdapter } = require('../adapters/flightProvider.factory');
const {
  isValidFlightNumber,
  normalizeFlightNumber,
} = require('../utils/flightNumber.util');

const SOURCE = 'AERODATABOX';
const CACHE_TTL_MS = 5 * 60 * 1000;

const STATUS_MAP = {
  Expected: 'SCHEDULED',
  CheckIn: 'SCHEDULED',
  Boarding: 'SCHEDULED',
  GateClosed: 'SCHEDULED',
  EnRoute: 'ACTIVE',
  Departed: 'ACTIVE',
  Approaching: 'ACTIVE',
  Arrived: 'LANDED',
  Canceled: 'CANCELLED',
  Cancelled: 'CANCELLED',
  Diverted: 'DIVERTED',
  Delayed: 'DELAYED',
};

class FlightService {
  constructor(config, httpClient = axios, cache = new Map(), provider = null) {
    this.config = config;
    this.httpClient = httpClient;
    this.cache = cache;
    this.provider = provider ?? createFlightProviderAdapter(config, httpClient);
  }

  isProviderConfigured() {
    return this.provider.isConfigured();
  }

  normalizeFlightNumber(flightNumber) {
    const normalized = normalizeFlightNumber(flightNumber);
    if (!normalized || !isValidFlightNumber(normalized)) {
      throw new AppError('Invalid flight number', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FLIGHT_NUMBER,
      });
    }
    return normalized;
  }

  normalizeFlightDate(flightDate) {
    const value = String(flightDate ?? '').trim();
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      throw new AppError('Invalid flight date', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FLIGHT_DATE,
      });
    }

    const parsed = new Date(`${value}T00:00:00.000Z`);
    if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
      throw new AppError('Invalid flight date', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.INVALID_FLIGHT_DATE,
      });
    }

    return value;
  }

  getCacheKey(flightNumber, flightDate) {
    return `${flightNumber}:${flightDate}`;
  }

  cloneValue(value) {
    return JSON.parse(JSON.stringify(value));
  }

  getCached(cacheKey) {
    const cached = this.cache.get(cacheKey);
    if (!cached || cached.expiresAt <= Date.now()) {
      this.cache.delete(cacheKey);
      return null;
    }
    return this.cloneValue(cached.value);
  }

  setCached(cacheKey, value) {
    this.cache.set(cacheKey, {
      value: this.cloneValue(value),
      expiresAt: Date.now() + CACHE_TTL_MS,
    });
  }

  ensureConfigured() {
    if (!this.provider.isConfigured()) {
      throw new AppError('Flight provider is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
      });
    }
  }

  normalizeAeroDataBoxUtc(value) {
    if (!value || typeof value !== 'string') return null;

    const trimmed = value.trim();
    let normalized = trimmed.includes('T') ? trimmed : trimmed.replace(' ', 'T');

    if (/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}Z$/i.test(normalized)) {
      normalized = normalized.replace(/Z$/i, ':00Z');
    }

    return normalized;
  }

  buildFlightNumberFromProvider(item) {
    if (!item?.number) return null;
    return String(item.number).replace(/\s+/g, '').toUpperCase();
  }

  getDatePart(value) {
    if (!value || typeof value !== 'string') return null;
    return value.slice(0, 10);
  }

  matchesRequestedDate(item, flightDate) {
    return [
      item?.departure?.scheduledTime?.utc,
      item?.arrival?.scheduledTime?.utc,
    ].some((value) => this.getDatePart(value) === flightDate);
  }

  selectBestResult(items, flightNumber, flightDate) {
    const candidates = items
      .map((item, index) => ({
        item,
        index,
        providerFlightNumber: this.buildFlightNumberFromProvider(item),
        dateMatches: this.matchesRequestedDate(item, flightDate),
        scheduledAt: item?.departure?.scheduledTime?.utc
          || item?.arrival?.scheduledTime?.utc
          || '',
      }))
      .filter((candidate) => candidate.providerFlightNumber === flightNumber)
      .filter((candidate) => candidate.dateMatches);

    candidates.sort((a, b) => {
      const timeCompare = a.scheduledAt.localeCompare(b.scheduledAt);
      if (timeCompare !== 0) return timeCompare;
      return a.index - b.index;
    });

    return candidates[0]?.item ?? null;
  }

  mapStatus(providerStatus) {
    if (!providerStatus) return 'UNKNOWN';
    const trimmed = String(providerStatus).trim();
    return STATUS_MAP[trimmed] ?? 'UNKNOWN';
  }

  calculateDelayMinutes(item) {
    const scheduledUtc = item?.arrival?.scheduledTime?.utc;
    const predictedUtc = item?.arrival?.predictedTime?.utc;

    if (!scheduledUtc || !predictedUtc) {
      return null;
    }

    const scheduled = Date.parse(this.normalizeAeroDataBoxUtc(scheduledUtc));
    const predicted = Date.parse(this.normalizeAeroDataBoxUtc(predictedUtc));

    if (Number.isNaN(scheduled) || Number.isNaN(predicted)) {
      return null;
    }

    return Math.max(0, Math.round((predicted - scheduled) / 60000));
  }

  logProviderFailure(errorCode, flightNumber, flightDate) {
    logger.warn('Flight provider lookup failed', {
      errorCode,
      flightNumber,
      flightDate,
      provider: SOURCE,
    });
  }

  async fetchProviderData(flightNumber, flightDate) {
    this.ensureConfigured();
    return this.provider.fetchFlights(flightNumber, flightDate);
  }

  normalizeProviderResult(item, flightNumber, flightDate) {
    const airlineCode = item?.airline?.iata ?? null;

    return {
      flightNumber,
      airlineCode,
      airlineName: item?.airline?.name ?? null,
      flightDate,
      departure: {
        airportCode: item?.departure?.airport?.iata ?? null,
        airportName: item?.departure?.airport?.name ?? null,
        scheduledAt: this.normalizeAeroDataBoxUtc(item?.departure?.scheduledTime?.utc),
        estimatedAt: this.normalizeAeroDataBoxUtc(item?.departure?.predictedTime?.utc),
        // AeroDataBox may add actualTime in future responses.
        actualAt: null,
        terminal: item?.departure?.terminal ?? null,
        gate: item?.departure?.gate ?? null,
      },
      arrival: {
        airportCode: item?.arrival?.airport?.iata ?? null,
        airportName: item?.arrival?.airport?.name ?? null,
        scheduledAt: this.normalizeAeroDataBoxUtc(item?.arrival?.scheduledTime?.utc),
        estimatedAt: this.normalizeAeroDataBoxUtc(item?.arrival?.predictedTime?.utc),
        // AeroDataBox may add actualTime in future responses.
        actualAt: null,
        terminal: item?.arrival?.terminal ?? null,
        gate: item?.arrival?.gate ?? null,
      },
      status: this.mapStatus(item?.status),
      delayMinutes: this.calculateDelayMinutes(item),
      source: SOURCE,
      retrievedAt: new Date().toISOString(),
    };
  }

  async search(input) {
    const flightNumber = this.normalizeFlightNumber(input.flightNumber);
    const flightDate = this.normalizeFlightDate(input.flightDate);
    const cacheKey = this.getCacheKey(flightNumber, flightDate);
    const cached = this.getCached(cacheKey);
    if (cached) return cached;

    let providerData;
    try {
      providerData = await this.fetchProviderData(flightNumber, flightDate);
    } catch (err) {
      const mapped = this.provider.mapProviderError(err);
      this.logProviderFailure(mapped.errorCode, flightNumber, flightDate);
      throw mapped;
    }

    const bestResult = this.selectBestResult(providerData, flightNumber, flightDate);
    if (!bestResult) {
      throw new AppError('Flight not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.FLIGHT_NOT_FOUND,
      });
    }

    const normalized = this.normalizeProviderResult(bestResult, flightNumber, flightDate);
    this.setCached(cacheKey, normalized);
    return normalized;
  }
}

module.exports = FlightService;
