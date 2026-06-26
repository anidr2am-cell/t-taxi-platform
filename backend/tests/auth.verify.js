/**
 * Auth verification script — run: node tests/auth.verify.js
 */
require('dotenv').config();
process.env.DB_PORT = '3307';

const http = require('http');
const jwt = require('jsonwebtoken');
const bcrypt = require('bcryptjs');
const database = require('../src/config/database');
const config = require('../src/config');
const app = require('../src/app');

const BASE = `http://127.0.0.1:${process.env.TEST_PORT || 3010}/api/v1`;
const email = `authverify_${Date.now()}@example.com`;
const password = 'secret123';

const results = [];

function record(name, pass, detail = '') {
  results.push({ name, pass, detail });
  const mark = pass ? 'PASS' : 'FAIL';
  console.log(`${mark} ${name}${detail ? ` — ${detail}` : ''}`);
}

async function request(method, path, { body, token } = {}) {
  const url = new URL(path.replace(/^\//, ''), BASE.endsWith('/') ? BASE : `${BASE}/`);
  const payload = body ? JSON.stringify(body) : null;
  const headers = { 'Content-Type': 'application/json', Accept: 'application/json' };
  if (token) headers.Authorization = `Bearer ${token}`;

  return new Promise((resolve, reject) => {
    const req = http.request(url, { method, headers }, (res) => {
      let data = '';
      res.on('data', (c) => { data += c; });
      res.on('end', () => {
        try {
          resolve({ status: res.statusCode, body: data ? JSON.parse(data) : null });
        } catch {
          resolve({ status: res.statusCode, body: data });
        }
      });
    });
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function decode(token, secret) {
  return jwt.verify(token, secret);
}

async function run() {
  const server = http.createServer(app);
  await new Promise((r) => server.listen(process.env.TEST_PORT || 3010, r));

  let accessToken;
  let refreshToken;
  let userId;
  let role;

  try {
    const reg = await request('POST', '/auth/register', {
      body: {
        email,
        password,
        name: 'Auth Verify',
        phone: '+821012345678',
        countryCode: 'KR',
        locale: 'ko',
      },
    });
    record('POST /auth/register', reg.status === 201 && reg.body?.success, `status=${reg.status}`);
    accessToken = reg.body?.data?.accessToken;
    refreshToken = reg.body?.data?.refreshToken;
    userId = reg.body?.data?.user?.id;
    role = reg.body?.data?.user?.role;
    record('JWT generation (register)', Boolean(accessToken && refreshToken));
    record('expiresIn on register', reg.body?.data?.expiresIn === 3600, String(reg.body?.data?.expiresIn));

    const accessPayload = decode(accessToken, config.jwt.accessSecret);
    record('Access token payload', accessPayload.type === 'access' && accessPayload.role === 'CUSTOMER');
    const refreshPayload = decode(refreshToken, config.jwt.refreshSecret);
    record('Refresh token jti', Boolean(refreshPayload.jti && refreshPayload.type === 'refresh'));

    const [rows] = await database.pool.query(
      'SELECT password_hash FROM users WHERE email = ? AND deleted_at IS NULL',
      [email],
    );
    const hash = rows[0]?.password_hash;
    record(
      'Password hashing (bcrypt)',
      hash && hash.startsWith('$2') && await bcrypt.compare(password, hash),
    );

    const badLogin = await request('POST', '/auth/login', {
      body: { email, password: 'wrongpassword' },
    });
    record(
      'Invalid credentials',
      badLogin.status === 401 && badLogin.body?.error_code === 'AUTH_INVALID',
      `status=${badLogin.status}`,
    );

    const login = await request('POST', '/auth/login', {
      body: { email, password },
    });
    record('POST /auth/login', login.status === 200 && login.body?.success, `status=${login.status}`);
    const loginRefresh = login.body?.data?.refreshToken;
    record(
      'Refresh token issued on login',
      Boolean(loginRefresh),
    );
    record(
      'Refresh token rotation on login',
      loginRefresh !== refreshToken,
      'new refresh token on each login',
    );

    const refreshRes = await request('POST', '/auth/refresh', {
      body: { refreshToken: loginRefresh },
    });
    record('POST /auth/refresh', refreshRes.status === 200 && refreshRes.body?.data?.accessToken);
    const newAccess = refreshRes.body?.data?.accessToken;
    record(
      'Refresh returns new access token',
      newAccess && newAccess !== accessToken,
    );
    record(
      'Refresh token rotation on refresh',
      !refreshRes.body?.data?.refreshToken,
      'OpenAPI: no new refreshToken on refresh endpoint',
    );
    accessToken = newAccess;

    const me = await request('GET', '/auth/me', { token: accessToken });
    record(
      'GET /auth/me + role extraction',
      me.status === 200 && me.body?.data?.role === 'CUSTOMER' && me.body?.data?.email === email,
      `role=${me.body?.data?.role}`,
    );

    const noAuth = await request('GET', '/auth/me');
    record(
      'Authorization middleware (missing token)',
      noAuth.status === 401,
      `status=${noAuth.status}`,
    );

    const badAccess = await request('GET', '/auth/me', { token: 'invalid.token.here' });
    record(
      'Authorization middleware (invalid token)',
      badAccess.status === 401,
      `status=${badAccess.status}`,
    );

    const expiredAccess = jwt.sign(
      { sub: userId, email, role: 'CUSTOMER', type: 'access' },
      config.jwt.accessSecret,
      { expiresIn: -10 },
    );
    const expiredRes = await request('GET', '/auth/me', { token: expiredAccess });
    record('Expired access token', expiredRes.status === 401, `status=${expiredRes.status}`);

    const logout = await request('POST', '/auth/logout', {
      token: accessToken,
      body: { refreshToken: loginRefresh },
    });
    record('POST /auth/logout', logout.status === 200 && logout.body?.success, `status=${logout.status}`);

    const revokedRefresh = await request('POST', '/auth/refresh', {
      body: { refreshToken: loginRefresh },
    });
    record(
      'Revoked refresh token',
      revokedRefresh.status === 401 && revokedRefresh.body?.error_code === 'AUTH_INVALID',
      `status=${revokedRefresh.status}`,
    );
  } catch (err) {
    record('Test suite execution', false, err.message);
    console.error(err);
  } finally {
    await database.pool.query('DELETE FROM user_profiles WHERE user_id IN (SELECT id FROM users WHERE email = ?)', [email]);
    await database.pool.query('DELETE FROM users WHERE email = ?', [email]);
    server.close();
    await database.pool.end();
  }

  const failed = results.filter((r) => !r.pass);
  console.log('\n--- Summary ---');
  console.log(`Total: ${results.length}, Passed: ${results.length - failed.length}, Failed: ${failed.length}`);
  if (failed.length) {
    console.log('Failed:', failed.map((f) => f.name).join(', '));
    process.exit(1);
  }
}

run();
