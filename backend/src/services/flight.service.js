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

const SOURCE = 'AVIATIONSTACK';
const CACHE_TTL_MS = 5 * 60 * 1000;

const STATUS_MAP = {
  scheduled: 'SCHEDULED',
  active: 'ACTIVE',
  landed: 'LANDED',
  cancelled: 'CANCELLED',
  canceled: 'CANCELLED',
  diverted: 'DIVERTED',
  delayed: 'DELAYED',
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

  buildFlightNumberFromProvider(item) {
    const flightIata = item?.flight?.iata;
    if (flightIata) {
      return String(flightIata).replace(/\s+/g, '').toUpperCase();
    }

    const airlineCode = item?.airline?.iata || item?.airline?.icao;
    const flightNumber = item?.flight?.number;
    if (airlineCode && flightNumber) {
      return `${airlineCode}${flightNumber}`.replace(/\s+/g, '').toUpperCase();
    }

    return null;
  }

  getDatePart(value) {
    if (!value || typeof value !== 'string') return null;
    return value.slice(0, 10);
  }

  matchesRequestedDate(item, flightDate) {
    return [
      item?.flight_date,
      item?.departure?.scheduled,
      item?.arrival?.scheduled,
    ].some((value) => this.getDatePart(value) === flightDate);
  }

  selectBestResult(items, flightNumber, flightDate) {
    const candidates = items
      .map((item, index) => ({
        item,
        index,
        providerFlightNumber: this.buildFlightNumberFromProvider(item),
        dateMatches: this.matchesRequestedDate(item, flightDate),
        scheduledAt: item?.departure?.scheduled || item?.arrival?.scheduled || '',
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
    return STATUS_MAP[String(providerStatus).trim().toLowerCase()] ?? 'UNKNOWN';
  }

  calculateDelayMinutes(item) {
    const scheduled = Date.parse(item?.arrival?.scheduled);
    const estimated = Date.parse(item?.arrival?.estimated);

    if (!Number.isNaN(scheduled) && !Number.isNaN(estimated)) {
      return Math.max(0, Math.round((estimated - scheduled) / 60000));
    }

    const providerDelay = Number(item?.arrival?.delay ?? item?.departure?.delay);
    if (Number.isFinite(providerDelay)) {
      return Math.max(0, Math.round(providerDelay));
    }

    return 0;
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
        airportCode: item?.departure?.iata ?? null,
        airportName: item?.departure?.airport ?? null,
        scheduledAt: item?.departure?.scheduled ?? null,
        estimatedAt: item?.departure?.estimated ?? null,
        actualAt: item?.departure?.actual ?? null,
        terminal: item?.departure?.terminal ?? null,
        gate: item?.departure?.gate ?? null,
      },
      arrival: {
        airportCode: item?.arrival?.iata ?? null,
        airportName: item?.arrival?.airport ?? null,
        scheduledAt: item?.arrival?.scheduled ?? null,
        estimatedAt: item?.arrival?.estimated ?? null,
        actualAt: item?.arrival?.actual ?? null,
        terminal: item?.arrival?.terminal ?? null,
        gate: item?.arrival?.gate ?? null,
      },
      status: this.mapStatus(item?.flight_status),
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
