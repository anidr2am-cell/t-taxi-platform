const { test, describe, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const app = require('../src/app');
const container = require('../src/helpers/container');
const PlacesService = require('../src/services/places.service');
const ERROR_CODES = require('../src/constants/errorCodes');

const config = { apiKey: 'test-google-key' };

function createHttpClient(data, calls) {
  return {
    async post(url, body, options) {
      calls.push({ method: 'POST', url, body, options });
      return { data };
    },
    async get(url, options) {
      calls.push({ method: 'GET', url, options });
      return { data };
    },
  };
}

describe('Places routes', () => {
  beforeEach(() => {
    container.register('placesService', () => new PlacesService({ apiKey: '' }, createHttpClient({}, [])));
  });

  test('GET /api/v1/places/autocomplete is mounted and returns predictions', async () => {
    const calls = [];
    container.register('placesService', () => new PlacesService(config, createHttpClient({
      suggestions: [
        {
          placePrediction: {
            placeId: 'place-1',
            text: { text: 'Pattaya Beach, Chon Buri, Thailand' },
            structuredFormat: {
              mainText: { text: 'Pattaya Beach' },
              secondaryText: { text: 'Chon Buri, Thailand' },
            },
          },
        },
      ],
    }, calls)));

    const res = await request(app)
      .get('/api/v1/places/autocomplete')
      .query({ input: '  pattaya  ', language: 'ko' })
      .expect(200);

    assert.equal(res.body.success, true);
    assert.equal(res.body.data.predictions.length, 1);
    assert.deepEqual(res.body.data.predictions[0], {
      placeId: 'place-1',
      description: 'Pattaya Beach, Chon Buri, Thailand',
      mainText: 'Pattaya Beach',
      secondaryText: 'Chon Buri, Thailand',
    });
    assert.equal(calls[0].method, 'POST');
    assert.equal(calls[0].url, 'https://places.googleapis.com/v1/places:autocomplete');
    assert.equal(calls[0].body.input, 'pattaya');
    assert.equal(calls[0].body.languageCode, 'ko');
    assert.equal(calls[0].options.headers['X-Goog-Api-Key'], 'test-google-key');
    assert.match(calls[0].options.headers['X-Goog-FieldMask'], /suggestions\.placePrediction\.placeId/);
  });

  test('input shorter than 2 characters returns validation error', async () => {
    const res = await request(app)
      .get('/api/v1/places/autocomplete')
      .query({ input: 'p', language: 'ko' })
      .expect(400);

    assert.equal(res.body.success, false);
    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });

  test('missing Google configuration returns controlled service error instead of route 404', async () => {
    const res = await request(app)
      .get('/api/v1/places/autocomplete')
      .query({ input: 'pattaya', language: 'ko' })
      .expect(503);

    assert.equal(res.body.success, false);
    assert.equal(res.body.error_code, ERROR_CODES.EXTERNAL_API_ERROR);
    assert.match(res.body.message, /not configured/i);
  });

  test('GET /api/v1/places/details returns normalized place details', async () => {
    const calls = [];
    container.register('placesService', () => new PlacesService(config, createHttpClient({
      id: 'place-1',
      displayName: { text: 'Pattaya Beach' },
      formattedAddress: 'Pattaya Beach, Chon Buri, Thailand',
      location: { latitude: 12.9236, longitude: 100.8825 },
    }, calls)));

    const res = await request(app)
      .get('/api/v1/places/details')
      .query({ placeId: 'place-1', language: 'ko' })
      .expect(200);

    assert.deepEqual(res.body.data, {
      placeId: 'place-1',
      name: 'Pattaya Beach',
      formattedAddress: 'Pattaya Beach, Chon Buri, Thailand',
      lat: 12.9236,
      lng: 100.8825,
    });
    assert.equal(calls[0].method, 'GET');
    assert.equal(calls[0].url, 'https://places.googleapis.com/v1/places/place-1');
    assert.equal(calls[0].options.params.languageCode, 'ko');
    assert.equal(calls[0].options.headers['X-Goog-Api-Key'], 'test-google-key');
  });
});
