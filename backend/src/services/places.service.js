const axios = require('axios');
const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const logger = require('../utils/logger');

const BASE_URL = 'https://places.googleapis.com/v1';
const TIMEOUT_MS = 5000;

class PlacesService {
  constructor(config, httpClient = axios) {
    this.config = config;
    this.httpClient = httpClient;
  }

  normalizeInput(input) {
    const value = String(input ?? '').trim();
    if (value.length < 2) {
      throw new AppError('Place search input must be at least 2 characters', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return value;
  }

  normalizeLanguage(language) {
    const value = String(language ?? '').trim().toLowerCase();
    return /^[a-z]{2}$/.test(value) ? value : 'en';
  }

  normalizePlaceId(placeId) {
    const value = String(placeId ?? '').trim();
    if (!value) {
      throw new AppError('placeId is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return value;
  }

  ensureConfigured() {
    if (!this.config?.apiKey) {
      throw new AppError('Google Places provider is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }
  }

  mapProviderErrorStatus(status) {
    if (status === 404) {
      return new AppError('Place not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.GOOGLE_PLACE_NOT_FOUND,
      });
    }
    if (status === 401 || status === 403) {
      return new AppError('Google Places provider is not configured', {
        statusCode: HTTP_STATUS.SERVICE_UNAVAILABLE,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }

    return new AppError('Google Places provider error', {
      statusCode: HTTP_STATUS.BAD_GATEWAY,
      errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
    });
  }

  mapRequestError(err) {
    if (err instanceof AppError) return err;
    if (err.code === 'ECONNABORTED' || err.code === 'ETIMEDOUT') {
      return new AppError('Google Places provider timed out', {
        statusCode: HTTP_STATUS.GATEWAY_TIMEOUT,
        errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
      });
    }
    if (err.response?.status) {
      return this.mapProviderErrorStatus(err.response.status);
    }
    return new AppError('Google Places provider error', {
      statusCode: HTTP_STATUS.BAD_GATEWAY,
      errorCode: ERROR_CODES.EXTERNAL_API_ERROR,
    });
  }

  logProviderFailure(errorCode) {
    logger.warn('Google Places lookup failed', {
      errorCode,
      provider: 'GOOGLE_PLACES',
    });
  }

  normalizePrediction(item) {
    const placePrediction = item?.placePrediction ?? item;
    const structured = placePrediction?.structuredFormat ?? {};
    const fallbackText = placePrediction?.text?.text ?? '';
    return {
      placeId: placePrediction?.placeId ?? '',
      description: fallbackText,
      mainText: structured.mainText?.text ?? fallbackText,
      secondaryText: structured.secondaryText?.text ?? '',
    };
  }

  normalizeDetails(result) {
    const location = result?.location ?? {};
    return {
      placeId: result?.id ?? '',
      name: result?.displayName?.text ?? '',
      formattedAddress: result?.formattedAddress ?? '',
      lat: typeof location.latitude === 'number' ? location.latitude : null,
      lng: typeof location.longitude === 'number' ? location.longitude : null,
    };
  }

  async autocomplete(input) {
    const normalizedInput = this.normalizeInput(input.input);
    const language = this.normalizeLanguage(input.language);
    this.ensureConfigured();

    try {
      const response = await this.httpClient.post(`${BASE_URL}/places:autocomplete`, {
        input: normalizedInput,
        languageCode: language,
      }, {
        timeout: TIMEOUT_MS,
        headers: {
          'X-Goog-Api-Key': this.config.apiKey,
          'X-Goog-FieldMask': [
            'suggestions.placePrediction.placeId',
            'suggestions.placePrediction.text',
            'suggestions.placePrediction.structuredFormat',
          ].join(','),
        },
      });

      return {
        predictions: (response.data?.suggestions ?? []).map((item) => this.normalizePrediction(item)),
      };
    } catch (err) {
      const mapped = this.mapRequestError(err);
      this.logProviderFailure(mapped.errorCode);
      throw mapped;
    }
  }

  async details(input) {
    const placeId = this.normalizePlaceId(input.placeId);
    const language = this.normalizeLanguage(input.language);
    this.ensureConfigured();

    try {
      const response = await this.httpClient.get(`${BASE_URL}/places/${encodeURIComponent(placeId)}`, {
        timeout: TIMEOUT_MS,
        params: {
          languageCode: language,
        },
        headers: {
          'X-Goog-Api-Key': this.config.apiKey,
          'X-Goog-FieldMask': 'id,displayName,formattedAddress,location',
        },
      });

      return this.normalizeDetails(response.data ?? {});
    } catch (err) {
      const mapped = this.mapRequestError(err);
      this.logProviderFailure(mapped.errorCode);
      throw mapped;
    }
  }
}

module.exports = PlacesService;
