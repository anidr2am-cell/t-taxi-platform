const axios = require('axios');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

class AviationstackFlightAdapter {
  constructor(config, httpClient = axios) {
    this.config = config;
    this.httpClient = httpClient;
  }

  isConfigured() {
    return Boolean(this.config?.apiKey && this.config?.baseUrl);
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
    const providerCode = String(err.response?.data?.error?.code ?? '').toLowerCase();

    if (status === 401 || status === 403 || providerCode.includes('access_key')) {
      return new AppError('Flight provider is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_NOT_CONFIGURED,
      });
    }

    if (status === 429 || providerCode.includes('rate')) {
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
    const response = await this.httpClient.get(`${baseUrl}/flights`, {
      timeout: this.config.timeoutMs,
      params: {
        access_key: this.config.apiKey,
        flight_iata: flightNumber,
        flight_date: flightDate,
      },
    });

    if (response.data?.error) {
      throw { response };
    }

    if (!response || !Array.isArray(response.data?.data)) {
      throw new AppError('Malformed flight provider response', {
        statusCode: HTTP_STATUS.BAD_GATEWAY,
        errorCode: ERROR_CODES.FLIGHT_PROVIDER_ERROR,
      });
    }

    return response.data.data;
  }
}

module.exports = AviationstackFlightAdapter;
