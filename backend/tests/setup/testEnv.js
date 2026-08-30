/**
 * Shared test environment bootstrap.
 *
 * Loaded via `node --test --require ./tests/setup/testEnv.js` so every test
 * file gets consistent defaults before app modules validate env (env.js).
 *
 * Existing values in process.env are preserved (CI/staging overrides still work).
 */
process.env.NODE_ENV = process.env.NODE_ENV || 'test';
process.env.DB_USER = process.env.DB_USER || 'test';
process.env.DB_NAME = process.env.DB_NAME || 'ttaxi_test';
process.env.JWT_ACCESS_SECRET = process.env.JWT_ACCESS_SECRET || 'test-access-secret-value';
process.env.JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'test-refresh-secret-value';
process.env.SOCIAL_TOKEN_ENCRYPTION_KEY = process.env.SOCIAL_TOKEN_ENCRYPTION_KEY
  || Buffer.alloc(32, 3).toString('base64');
