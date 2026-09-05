process.env.NODE_ENV = 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');

const app = require('../src/app');
const container = require('../src/helpers/container');
const HomeBannerService = require('../src/services/homeBanner.service');

const CUSTOMER_ID = 42;
const ADMIN_ID = 7;

function registerCustomerAuth(userId = CUSTOMER_ID) {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: userId, role: 'CUSTOMER', email: 'customer@test.local' };
    },
  }));
}

function registerAdminAuth(userId = ADMIN_ID) {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: userId, role: 'ADMIN', email: 'admin@test.local' };
    },
  }));
}

describe('Public home banner API', () => {
  test('GET /api/v1/public/home-banners returns active banners without auth', async () => {
    container.register('homeBannerService', () => ({
      async listPublicBanners() {
        return [{
          id: 1,
          displayOrder: 0,
          imageUrl: '/api/v1/public/home-banners/1/image',
        }];
      },
    }));

    const response = await request(app).get('/api/v1/public/home-banners');
    assert.equal(response.statusCode, 200);
    assert.equal(response.body.data.length, 1);
    assert.match(response.body.data[0].imageUrl, /\/public\/home-banners\/1\/image$/);
  });
});

describe('Admin home banner API', () => {
  test('GET /api/v1/admin/home-banners requires admin auth', async () => {
    registerCustomerAuth();
    const response = await request(app)
      .get('/api/v1/admin/home-banners')
      .set('Authorization', 'Bearer test-token');
    assert.equal(response.statusCode, 403);
  });

  test('POST /api/v1/admin/home-banners requires admin auth', async () => {
    registerCustomerAuth();
    const response = await request(app)
      .post('/api/v1/admin/home-banners')
      .set('Authorization', 'Bearer test-token');
    assert.equal(response.statusCode, 403);
  });

  test('DELETE /api/v1/admin/home-banners/:id requires admin auth', async () => {
    registerCustomerAuth();
    const response = await request(app)
      .delete('/api/v1/admin/home-banners/1')
      .set('Authorization', 'Bearer test-token');
    assert.equal(response.statusCode, 403);
  });

  test('GET /api/v1/admin/home-banners lists banners for admin', async () => {
    registerAdminAuth();
    container.register('homeBannerService', () => ({
      async listAdminBanners() {
        return [{
          id: 2,
          displayOrder: 1,
          isActive: true,
          imageUrl: '/api/v1/admin/home-banners/2/image',
        }];
      },
    }));

    const response = await request(app)
      .get('/api/v1/admin/home-banners')
      .set('Authorization', 'Bearer admin-token');
    assert.equal(response.statusCode, 200);
    assert.equal(response.body.data[0].id, 2);
  });
});

describe('HomeBannerService.mapPublicRow', () => {
  test('maps public image URL', () => {
    const service = new HomeBannerService({});
    const mapped = service.mapPublicRow({
      id: 3,
      display_order: 5,
      is_active: 1,
      image_path: 'home-banners/promo.png',
    });
    assert.equal(mapped.imageUrl, '/api/v1/public/home-banners/3/image');
    assert.equal(mapped.displayOrder, 5);
  });
});
