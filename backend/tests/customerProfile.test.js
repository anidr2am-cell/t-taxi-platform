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
const CustomerProfileService = require('../src/services/customerProfile.service');
const UserRepository = require('../src/repositories/user.repository');
const AuthService = require('../src/services/auth.service');
const TokenService = require('../src/services/token.service');
const RevokedRefreshTokenStore = require('../src/services/revokedRefreshToken.store');
const ERROR_CODES = require('../src/constants/errorCodes');
const ROLES = require('../src/constants/roles');

const CUSTOMER_ID = 42;

function registerCustomerAuth(userId = CUSTOMER_ID) {
  container.register('authService', () => ({
    verifyAccessToken() {
      return { id: userId, role: ROLES.CUSTOMER, email: 'customer@test.local' };
    },
  }));
}

function createDuplicatePhoneError(phone) {
  const err = new Error('Duplicate entry');
  err.code = 'ER_DUP_ENTRY';
  err.sqlMessage = `Duplicate entry '${phone}' for key 'uk_users_phone'`;
  return err;
}

function createDbHarness(initial = {}) {
  const state = {
    users: new Map([
      [CUSTOMER_ID, {
        id: CUSTOMER_ID,
        email: 'social@test.local',
        role: ROLES.CUSTOMER,
        phone: null,
        phone_country_code: null,
        locale: 'ko',
        is_active: 1,
        deleted_at: null,
        ...initial.user,
      }],
    ]),
    profiles: new Map([
      [CUSTOMER_ID, {
        user_id: CUSTOMER_ID,
        display_name: 'Customer',
        deleted_at: null,
        ...initial.profile,
      }],
    ]),
  };

  for (const extraUser of initial.extraUsers || []) {
    state.users.set(extraUser.id, extraUser);
    if (extraUser.profile) {
      state.profiles.set(extraUser.id, extraUser.profile);
    }
  }

  const queries = [];

  const conn = {
    committed: false,
    rolledBack: false,
    released: false,
    async beginTransaction() {},
    async commit() { this.committed = true; },
    async rollback() { this.rolledBack = true; },
    release() { this.released = true; },
    async query(sql, params = []) {
      queries.push({ sql: sql.replace(/\s+/g, ' ').trim(), params });
      const normalized = sql.replace(/\s+/g, ' ').trim();

      if (normalized.includes('FROM users u') && normalized.includes('FOR UPDATE')) {
        const userId = params[0];
        const user = state.users.get(userId);
        if (!user || user.deleted_at) return [[]];
        const profile = state.profiles.get(userId);
        return [[{
          ...user,
          name: profile?.display_name ?? null,
        }]];
      }

      if (normalized.startsWith('UPDATE users SET phone = ?')) {
        const [phone, phoneCountryCode, userId] = params;
        for (const [otherUserId, otherUser] of state.users.entries()) {
          if (otherUserId !== userId && otherUser.phone === phone && !otherUser.deleted_at) {
            throw createDuplicatePhoneError(phone);
          }
        }
        const user = state.users.get(userId);
        if (user) {
          user.phone = phone;
          user.phone_country_code = phoneCountryCode;
        }
        return [{ affectedRows: 1 }];
      }

      if (normalized.includes('FROM user_profiles') && normalized.includes('LIMIT 1')) {
        const userId = params[0];
        const profile = state.profiles.get(userId);
        if (!profile || profile.deleted_at) return [[]];
        return [[{ id: 1 }]];
      }

      if (normalized.startsWith('UPDATE user_profiles SET display_name = ?')) {
        const [displayName, userId] = params;
        const profile = state.profiles.get(userId) || { user_id: userId, deleted_at: null };
        profile.display_name = displayName;
        state.profiles.set(userId, profile);
        return [{ affectedRows: 1 }];
      }

      if (normalized.startsWith('INSERT INTO user_profiles')) {
        const [userId, displayName] = params;
        state.profiles.set(userId, { user_id: userId, display_name: displayName, deleted_at: null });
        return [{ insertId: 1 }];
      }

      return [[]];
    },
  };

  const pool = {
    async getConnection() { return conn; },
    async query(sql, params = []) {
      const normalized = sql.replace(/\s+/g, ' ').trim();
      if (normalized.includes('FROM users u') && normalized.includes('WHERE u.id = ?')) {
        const userId = params[0];
        const user = state.users.get(userId);
        if (!user || user.deleted_at) return [[]];
        const profile = state.profiles.get(userId);
        return [[{
          ...user,
          name: profile?.display_name ?? null,
        }]];
      }
      return [[]];
    },
  };

  const userRepository = new UserRepository(pool);
  const service = new CustomerProfileService(pool, userRepository);

  return { service, conn, state, queries };
}

describe('PATCH /api/v1/customer/profile', () => {
  test('returns 401 without JWT', async () => {
    const res = await request(app)
      .patch('/api/v1/customer/profile')
      .send({ name: 'Alice', phone: '+821012345678' });

    assert.equal(res.status, 401);
  });

  test('returns 400 when name is missing', async () => {
    registerCustomerAuth();

    const res = await request(app)
      .patch('/api/v1/customer/profile')
      .set('Authorization', 'Bearer customer-token')
      .send({ phone: '+821012345678' });

    assert.equal(res.status, 400);
    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });

  test('returns 400 when phone is missing', async () => {
    registerCustomerAuth();

    const res = await request(app)
      .patch('/api/v1/customer/profile')
      .set('Authorization', 'Bearer customer-token')
      .send({ name: 'Alice' });

    assert.equal(res.status, 400);
    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });

  test('returns 400 when phone is too short', async () => {
    registerCustomerAuth();

    const res = await request(app)
      .patch('/api/v1/customer/profile')
      .set('Authorization', 'Bearer customer-token')
      .send({ name: 'Alice', phone: '1234' });

    assert.equal(res.status, 400);
    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
  });

  test('returns updated profile for authenticated customer', async () => {
    registerCustomerAuth();
    container.register('customerProfileService', () => ({
      async updateProfile(userId, input) {
        assert.equal(userId, CUSTOMER_ID);
        assert.deepEqual(input, {
          name: 'Alice Kim',
          phone: '+821012345678',
          phoneCountryCode: '+82',
        });
        return {
          id: CUSTOMER_ID,
          email: 'social@test.local',
          role: ROLES.CUSTOMER,
          name: 'Alice Kim',
          phone: '+821012345678',
          locale: 'ko',
          isActive: true,
        };
      },
    }));

    const res = await request(app)
      .patch('/api/v1/customer/profile')
      .set('Authorization', 'Bearer customer-token')
      .send({
        name: 'Alice Kim',
        phone: '+821012345678',
        phoneCountryCode: '+82',
      })
      .expect(200);

    assert.equal(res.body.success, true);
    assert.equal(res.body.message, 'Profile updated');
    assert.equal(res.body.data.name, 'Alice Kim');
    assert.equal(res.body.data.phone, '+821012345678');
  });
  test('returns 409 when phone is already used by another account', async () => {
    registerCustomerAuth();
    container.register('customerProfileService', () => {
      const { service } = createDbHarness({
        extraUsers: [{
          id: 99,
          email: 'existing@test.local',
          role: ROLES.CUSTOMER,
          phone: '+821012345678',
          phone_country_code: '+82',
          locale: 'ko',
          is_active: 1,
          deleted_at: null,
          profile: {
            user_id: 99,
            display_name: 'Existing User',
            deleted_at: null,
          },
        }],
      });
      return service;
    });

    const res = await request(app)
      .patch('/api/v1/customer/profile')
      .set('Authorization', 'Bearer customer-token')
      .send({
        name: 'Alice Kim',
        phone: '+821012345678',
        phoneCountryCode: '+82',
      });

    assert.equal(res.status, 409);
    assert.equal(res.body.error_code, ERROR_CODES.DUPLICATE_BOOKING);
    assert.equal(res.body.errors[0].field, 'phone');
  });
});

describe('CustomerProfileService.updateProfile', () => {
  test('updates users.phone, phone_country_code, and user_profiles.display_name in one transaction', async () => {
    const { service, conn, state } = createDbHarness();

    const result = await service.updateProfile(CUSTOMER_ID, {
      name: 'Alice Kim',
      phone: '+821012345678',
      phoneCountryCode: '+82',
    });

    assert.equal(conn.committed, true);
    assert.equal(conn.released, true);
    assert.equal(state.users.get(CUSTOMER_ID).phone, '+821012345678');
    assert.equal(state.users.get(CUSTOMER_ID).phone_country_code, '+82');
    assert.equal(state.profiles.get(CUSTOMER_ID).display_name, 'Alice Kim');
    assert.deepEqual(result, {
      id: CUSTOMER_ID,
      email: 'social@test.local',
      role: ROLES.CUSTOMER,
      name: 'Alice Kim',
      phone: '+821012345678',
      locale: 'ko',
      isActive: true,
    });
  });

  test('inserts user_profiles row when profile is missing', async () => {
    const { service, state } = createDbHarness({ profile: null });
    state.profiles.delete(CUSTOMER_ID);

    await service.updateProfile(CUSTOMER_ID, {
      name: 'New Name',
      phone: '+66812345678',
      phoneCountryCode: '+66',
    });

    assert.equal(state.users.get(CUSTOMER_ID).phone, '+66812345678');
    assert.equal(state.profiles.get(CUSTOMER_ID).display_name, 'New Name');
  });

  test('rejects duplicate phone with 409 and field phone', async () => {
    const { service } = createDbHarness({
      extraUsers: [{
        id: 99,
        email: 'existing@test.local',
        role: ROLES.CUSTOMER,
        phone: '+821012345678',
        phone_country_code: '+82',
        locale: 'ko',
        is_active: 1,
        deleted_at: null,
      }],
    });

    await assert.rejects(
      () => service.updateProfile(CUSTOMER_ID, {
        name: 'Alice Kim',
        phone: '+821012345678',
        phoneCountryCode: '+82',
      }),
      (err) => err.statusCode === 409
        && err.errorCode === ERROR_CODES.DUPLICATE_BOOKING
        && err.errors?.[0]?.field === 'phone',
    );
  });
});

describe('AuthService.register duplicate phone', () => {
  test('returns 400 with field phone instead of 500 when phone is already taken', async () => {
    const tokenService = new TokenService(new RevokedRefreshTokenStore());
    const userRepository = {
      async findByEmail() {
        return null;
      },
      async createCustomerWithProfile() {
        throw createDuplicatePhoneError('+821012345678');
      },
    };
    const authService = new AuthService(userRepository, tokenService);

    await assert.rejects(
      () => authService.register({
        email: 'new@test.local',
        password: 'secret123',
        name: 'New User',
        phone: '+821012345678',
      }),
      (err) => err.statusCode === 400
        && err.errorCode === ERROR_CODES.VALIDATION_ERROR
        && err.errors?.[0]?.field === 'phone'
        && err.message === '이미 사용 중인 전화번호입니다',
    );
  });

  test('POST /auth/register returns 400 for duplicate phone', async () => {
    container.register('userRepository', () => ({
      async findByEmail() {
        return null;
      },
      async createCustomerWithProfile() {
        throw createDuplicatePhoneError('+821099887766');
      },
    }));
    container.register('authService', (c) => new AuthService(
      c.get('userRepository'),
      c.get('tokenService'),
      c.get('socialAccountRepository'),
    ));

    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({
        email: 'duplicate-phone@example.com',
        password: 'secret1234',
        name: 'Duplicate Phone User',
        phone: '+821099887766',
      });

    assert.equal(res.status, 400);
    assert.equal(res.body.error_code, ERROR_CODES.VALIDATION_ERROR);
    assert.equal(res.body.errors[0].field, 'phone');
    assert.notEqual(res.status, 500);
  });
});

describe('AuthService login response profile fields', () => {
  test('mapUser and buildAuthResponse include phone field', async () => {
    const user = {
      id: 90,
      email: 'social@example.com',
      role: ROLES.CUSTOMER,
      name: 'Social User',
      phone: '+821012345678',
      locale: 'ko',
      is_active: 1,
    };
    const tokenService = new TokenService(new RevokedRefreshTokenStore());
    const authService = new AuthService({}, tokenService);

    const mapped = authService.mapUser(user);
    assert.ok(Object.prototype.hasOwnProperty.call(mapped, 'phone'));
    assert.equal(mapped.phone, '+821012345678');

    const response = await authService.buildAuthResponse({ ...user, phone: null });
    assert.ok(Object.prototype.hasOwnProperty.call(response.user, 'phone'));
    assert.equal(response.user.phone, null);
    assert.ok(response.accessToken);
  });
});
