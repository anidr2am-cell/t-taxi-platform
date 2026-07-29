const axios = require('axios');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

class AeroDataBoxFlightAdapter {
  constructor(config, httpClient = axios) {
    this.config = config;
    this.httpClient = httpClient;
  }

  isConfigured() {
    return Boolean(this.config?.apiKey && this.config?.host);
  }

  normalizeEndpoint(endpoint) {
    return String(endpoint ?? '').replace(/\/+$/, '');
  }

  mapProviderError(err) {
    if (err instanceof AppError) return err;

    if (err.code === 'ECONNABORTED' || err.code === 'ETIMEDOUT') {
      return new AppError('Flight provider timed out', {
        statusCode: HTTP_STATUS.GATEWAY_TIMEOUT,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_TIMEOUT,
      });
    }

    const status = err.response?.status;

    if (status === 401 || status === 403) {
      return new AppError('Flight provider is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
      });
    }

    if (status === 429) {
      return new AppError('Flight provider rate limit reached', {
        statusCode: HTTP_STATUS.TOO_MANY_REQUESTS,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_RATE_LIMITED,
      });
    }

    return new AppError('Flight provider error', {
      statusCode: HTTP_STATUS.BAD_GATEWAY,
      errorCode: ERROR_CODES.FLIGHT_PROVIDER_ERROR,
    });
  }

  async fetchFlights(flightNumber, flightDate) {
    if (!this.isConfigured()) {
      throw new AppError('Flight provider is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
      });
    }

    const baseUrl = this.normalizeEndpoint(this.config.baseUrl);
    const encodedFlightNumber = encodeURIComponent(flightNumber);
    const response = await this.httpClient.get(
      `${baseUrl}/flights/number/${encodedFlightNumber}/${flightDate}`,
      {
        timeout: this.config.timeoutMs,
        headers: {
          'X-RapidAPI-Key': this.config.apiKey,
          'X-RapidAPI-Host': this.config.host,
        },
      },
    );

    if (!response || !Array.isArray(response.data)) {
      throw new AppError('Malformed flight provider response', {
        statusCode: HTTP_STATUS.BAD_GATEWAY,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_ERROR,
      });
    }

    return response.data;
  }
}

module.exports = AeroDataBoxFlightAdapter;
