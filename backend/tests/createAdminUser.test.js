process.env.NODE_ENV = 'test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const bcrypt = require('bcryptjs');

const AuthService = require('../src/services/auth.service');
const ROLES = require('../src/constants/roles');
const {
  createOrUpdateAdminUser,
  formatResult,
  parseArgs,
  resolveInputs,
} = require('../scripts/createAdminUser');

function createMemoryPool(seed = {}) {
  const state = {
    users: seed.users ? seed.users.map((user) => ({ ...user })) : [],
    profiles: seed.profiles ? seed.profiles.map((profile) => ({ ...profile })) : [],
    committed: 0,
    rolledBack: 0,
    released: 0,
  };

  const conn = {
    async beginTransaction() {},
    async commit() {
      state.committed += 1;
    },
    async rollback() {
      state.rolledBack += 1;
    },
    release() {
      state.released += 1;
    },
    async query(sql, params) {
      if (sql.includes('FROM users') && sql.includes('WHERE email = ?')) {
        const email = params[0];
        return [state.users.filter((user) => user.email === email && user.deleted_at == null).slice(0, 1)];
      }

      if (sql.includes('FROM user_profiles') && sql.includes('WHERE user_id = ?')) {
        const userId = params[0];
        return [state.profiles.filter((profile) => profile.user_id === userId && profile.deleted_at == null).slice(0, 1)];
      }

      if (sql.includes('INSERT INTO users')) {
        const [email, passwordHash, role] = params;
        const id = state.users.length + 1;
        state.users.push({
          id,
          email,
          password_hash: passwordHash,
          role,
          locale: 'en',
          is_active: 1,
          deleted_at: null,
        });
        return [{ insertId: id }];
      }

      if (sql.includes('UPDATE users')) {
        const [passwordHash, role, id] = params;
        const user = state.users.find((row) => row.id === id);
        user.password_hash = passwordHash;
        user.role = role;
        user.locale = user.locale || 'en';
        user.is_active = 1;
        return [{ affectedRows: 1 }];
      }

      if (sql.includes('INSERT INTO user_profiles')) {
        const [userId, displayName] = params;
        state.profiles.push({
          id: state.profiles.length + 1,
          user_id: userId,
          display_name: displayName,
          deleted_at: null,
        });
        return [{ insertId: state.profiles.length }];
      }

      if (sql.includes('UPDATE user_profiles')) {
        const [displayName, id] = params;
        const profile = state.profiles.find((row) => row.id === id);
        profile.display_name = displayName;
        return [{ affectedRows: 1 }];
      }

      throw new Error(`Unhandled SQL in test: ${sql}`);
    },
  };

  return {
    state,
    async getConnection() {
      return conn;
    },
  };
}

describe('createAdminUser script', () => {
  test('parses CLI options and validates admin role', () => {
    const args = parseArgs([
      '--email',
      'Admin@TRide.local',
      '--password',
      'Admin123456!',
      '--name',
      'T-Ride Admin',
      '--role',
      'super_admin',
      '--force',
    ]);
    const input = resolveInputs(args);

    assert.equal(input.email, 'admin@tride.local');
    assert.equal(input.role, ROLES.SUPER_ADMIN);
    assert.equal(input.force, true);
  });

  test('defaults role to ADMIN and name to T-Ride Admin', () => {
    const input = resolveInputs({
      email: 'admin@tride.local',
      password: 'Admin123456!',
    });

    assert.equal(input.role, ROLES.ADMIN);
    assert.equal(input.name, 'T-Ride Admin');
  });

  test('rejects invalid role', () => {
    assert.throws(
      () => resolveInputs({
        email: 'admin@tride.local',
        password: 'Admin123456!',
        name: 'Admin',
        role: 'CUSTOMER',
      }),
      /ADMIN or SUPER_ADMIN/,
    );
  });

  test('rejects weak password', () => {
    assert.throws(
      () => resolveInputs({
        email: 'admin@tride.local',
        password: 'short1',
        name: 'Admin',
        role: 'ADMIN',
      }),
      /at least 8 characters/,
    );
  });

  test('creates new SUPER_ADMIN with hashed password and profile', async () => {
    const pool = createMemoryPool();

    const result = await createOrUpdateAdminUser(pool, {
      email: 'admin@tride.local',
      password: 'Admin123456!',
      name: 'T-Ride Admin',
      role: ROLES.SUPER_ADMIN,
      force: false,
    });

    assert.equal(result.email, 'admin@tride.local');
    assert.equal(result.role, ROLES.SUPER_ADMIN);
    assert.equal(result.isActive, true);
    assert.equal(pool.state.users.length, 1);
    assert.equal(pool.state.users[0].is_active, 1);
    assert.notEqual(pool.state.users[0].password_hash, 'Admin123456!');
    assert.doesNotMatch(pool.state.users[0].password_hash, /^Admin123456!$/);
    assert.equal(await bcrypt.compare('Admin123456!', pool.state.users[0].password_hash), true);
    assert.equal(pool.state.profiles[0].display_name, 'T-Ride Admin');
    assert.equal(pool.state.committed, 1);
  });

  test('creates new ADMIN with hashed password and active account', async () => {
    const pool = createMemoryPool();

    const result = await createOrUpdateAdminUser(pool, {
      email: 'admin@tride.local',
      password: 'Admin123456!',
      name: 'T-Ride Admin',
      role: ROLES.ADMIN,
      force: false,
    });

    assert.equal(result.role, ROLES.ADMIN);
    assert.equal(pool.state.users[0].role, ROLES.ADMIN);
    assert.equal(pool.state.users[0].is_active, 1);
    assert.equal(await bcrypt.compare('Admin123456!', pool.state.users[0].password_hash), true);
  });

  test('blocks duplicate email without force', async () => {
    const passwordHash = await bcrypt.hash('OldAdmin123!', 12);
    const pool = createMemoryPool({
      users: [{
        id: 1,
        email: 'admin@tride.local',
        password_hash: passwordHash,
        role: ROLES.ADMIN,
        is_active: 1,
      }],
    });

    await assert.rejects(
      () => createOrUpdateAdminUser(pool, {
        email: 'admin@tride.local',
        password: 'Admin123456!',
        name: 'T-Ride Admin',
        role: ROLES.SUPER_ADMIN,
        force: false,
      }),
      /--force/,
    );
    assert.equal(await bcrypt.compare('OldAdmin123!', pool.state.users[0].password_hash), true);
    assert.equal(pool.state.rolledBack, 1);
  });

  test('force resets password role profile and keeps login compatibility', async () => {
    const oldHash = await bcrypt.hash('OldAdmin123!', 12);
    const pool = createMemoryPool({
      users: [{
        id: 1,
        email: 'admin@tride.local',
        password_hash: oldHash,
        role: ROLES.ADMIN,
        locale: 'en',
        is_active: 0,
        deleted_at: null,
      }],
      profiles: [{ id: 1, user_id: 1, display_name: 'Old Admin', deleted_at: null }],
    });

    const result = await createOrUpdateAdminUser(pool, {
      email: 'admin@tride.local',
      password: 'NewAdmin123!',
      name: 'T-Ride Admin',
      role: ROLES.SUPER_ADMIN,
      force: true,
    });

    assert.equal(result.role, ROLES.SUPER_ADMIN);
    assert.equal(result.isActive, true);
    assert.equal(pool.state.users[0].is_active, 1);
    assert.equal(pool.state.profiles[0].display_name, 'T-Ride Admin');
    assert.equal(await bcrypt.compare('NewAdmin123!', pool.state.users[0].password_hash), true);
    assert.equal(await bcrypt.compare('OldAdmin123!', pool.state.users[0].password_hash), false);

    const auth = new AuthService(
      {
        async findByEmail(email) {
          const user = pool.state.users.find((row) => row.email === email);
          return {
            ...user,
            name: pool.state.profiles.find((profile) => profile.user_id === user.id)?.display_name,
          };
        },
        async updateLastLoginAt() {},
      },
      {
        signAccessToken() { return 'access-token'; },
        signRefreshToken() { return { token: 'refresh-token' }; },
        getAccessExpiresInSeconds() { return 900; },
      },
    );

    const login = await auth.login({
      email: 'admin@tride.local',
      password: 'NewAdmin123!',
    });

    assert.equal(login.user.role, ROLES.SUPER_ADMIN);
    assert.equal(login.accessToken, 'access-token');
  });

  test('formatted output never includes plaintext password or password hash', async () => {
    const hash = await bcrypt.hash('Admin123456!', 12);
    const lines = formatResult({
      email: 'admin@tride.local',
      role: ROLES.ADMIN,
      isActive: true,
      password: 'Admin123456!',
      passwordHash: hash,
    });
    const output = lines.join('\n');

    assert.match(output, /admin@tride\.local/);
    assert.match(output, /ADMIN/);
    assert.doesNotMatch(output, /Admin123456!/);
    assert.doesNotMatch(output, new RegExp(hash.replace(/\$/g, '\\$')));
    assert.doesNotMatch(output, /password/i);
    assert.doesNotMatch(output, /hash/i);
  });
});
