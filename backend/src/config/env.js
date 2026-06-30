/**
 * config/env.js — Environment validation with Joi
 *
 * 앱 시작 시 .env 값을 검증합니다. 필수 값이 없으면 즉시 종료하여
 * 런타임 중 예기치 않은 오류를 방지합니다.
 */
const Joi = require('joi');

const envSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'staging', 'production', 'test').default('development'),
  PORT: Joi.number().port().default(3000),
  API_VERSION: Joi.string().default('v1'),
  APP_NAME: Joi.string().default('TTaxi'),
  CORS_ORIGIN: Joi.string().default('http://localhost:8080'),
  PUBLIC_API_URL: Joi.string().uri().optional(),
  DB_HOST: Joi.string().default('localhost'),
  DB_PORT: Joi.number().port().default(3306),
  DB_USER: Joi.string().required(),
  DB_PASSWORD: Joi.string().allow('').default(''),
  DB_NAME: Joi.string().required(),
  DB_CONNECTION_LIMIT: Joi.number().integer().min(1).default(10),
  JWT_ACCESS_SECRET: Joi.string().min(16).required(),
  JWT_REFRESH_SECRET: Joi.string().min(16).required(),
  JWT_ACCESS_EXPIRES_IN: Joi.string().default('1h'),
  JWT_REFRESH_EXPIRES_IN: Joi.string().default('7d'),
  GOOGLE_MAPS_API_KEY: Joi.string().allow('').optional(),
  AVIATIONSTACK_API_KEY: Joi.string().allow('').optional(),
  AVIATIONSTACK_BASE_URL: Joi.string().uri().default('http://api.aviationstack.com/v1'),
  AVIATIONSTACK_TIMEOUT_MS: Joi.number().integer().min(1000).max(30000).default(5000),
  FLIGHT_SYNC_ENABLED: Joi.boolean().truthy('true', '1').falsy('false', '0').default(false),
  FLIGHT_SYNC_MIN_INTERVAL_MS: Joi.number().integer().min(30000).max(3600000).default(120000),
  FLIGHT_SYNC_INTERVAL_MS: Joi.number().integer().min(30000).max(3600000).default(300000),
  FLIGHT_SYNC_BATCH_SIZE: Joi.number().integer().min(1).max(100).default(20),
  FLIGHT_SYNC_LOOKBACK_HOURS: Joi.number().integer().min(0).max(72).default(6),
  FLIGHT_SYNC_LOOKAHEAD_HOURS: Joi.number().integer().min(1).max(168).default(48),
  FLIGHT_SYNC_MAX_RETRIES: Joi.number().integer().min(1).max(10).default(3),
  FLIGHT_SYNC_RETRY_BASE_MS: Joi.number().integer().min(1000).max(300000).default(30000),
  FLIGHT_DELAY_NOTIFICATION_DELTA_MINUTES: Joi.number().integer().min(1).max(180).default(15),
  FIREBASE_PROJECT_ID: Joi.string().allow('').optional(),
  FIREBASE_CLIENT_EMAIL: Joi.string().allow('').optional(),
  FIREBASE_PRIVATE_KEY: Joi.string().allow('').optional(),
  FIREBASE_SERVICE_ACCOUNT_PATH: Joi.string().optional(),
  UPLOAD_DIR: Joi.string().default('./uploads'),
  UPLOAD_MAX_FILE_SIZE_MB: Joi.number().min(1).max(50).default(10),
  LOG_LEVEL: Joi.string().valid('error', 'warn', 'info', 'debug').default('info'),
  LOG_DIR: Joi.string().default('./logs'),
  SWAGGER_ENABLED: Joi.boolean().truthy('true').falsy('false').optional(),
  SWAGGER_ROUTE: Joi.string().default('/api-docs'),
  SOCKET_PATH: Joi.string().default('/socket.io'),
  SMTP_HOST: Joi.string().allow('').optional(),
  SMTP_PORT: Joi.number().port().default(587),
  SMTP_SECURE: Joi.boolean().truthy('true').falsy('false').default(false),
  SMTP_USER: Joi.string().allow('').optional(),
  SMTP_PASSWORD: Joi.string().allow('').optional(),
  SMTP_FROM: Joi.string().allow('').optional(),
  SMTP_FROM_NAME: Joi.string().allow('').optional(),
  SMTP_FROM_EMAIL: Joi.string().email().allow('').optional(),
  TZ: Joi.string().default('Asia/Bangkok'),
  ALLOW_DEV_QR_REISSUE: Joi.boolean().truthy('true', '1').falsy('false', '0').optional(),
}).unknown(true);

const { value: env, error } = envSchema.validate(process.env, { abortEarly: false });

function resolveAllowDevQrReissue(nodeEnv, explicitValue) {
  if (explicitValue === true) return true;
  if (explicitValue === false) return false;
  return nodeEnv === 'development';
}

const WEAK_SECRET_PATTERNS = [
  /^secret$/i,
  /^changeme$/i,
  /^change-me/i,
  /^replace-with/i,
  /^test-/i,
];

function isWeakSecret(value) {
  if (!value || value.length < 16) return true;
  return WEAK_SECRET_PATTERNS.some((pattern) => pattern.test(value.trim()));
}

if (error) {
  // eslint-disable-next-line no-console
  console.error('❌ Invalid environment variables:\n', error.details.map((d) => d.message).join('\n'));
  process.exit(1);
}

const isProductionLike = env.NODE_ENV === 'production' || env.NODE_ENV === 'staging';

if (env.SWAGGER_ENABLED === undefined) {
  env.SWAGGER_ENABLED = !isProductionLike;
}

if (isProductionLike) {
  const productionErrors = [];
  if (isWeakSecret(env.JWT_ACCESS_SECRET)) {
    productionErrors.push('JWT_ACCESS_SECRET must be a strong secret in production/staging');
  }
  if (isWeakSecret(env.JWT_REFRESH_SECRET)) {
    productionErrors.push('JWT_REFRESH_SECRET must be a strong secret in production/staging');
  }
  if (!env.DB_PASSWORD) {
    productionErrors.push('DB_PASSWORD is required in production/staging');
  }
  if (env.CORS_ORIGIN === '*' || !env.CORS_ORIGIN) {
    productionErrors.push('CORS_ORIGIN must be an explicit allowlist in production/staging');
  }
  if (resolveAllowDevQrReissue(env.NODE_ENV, env.ALLOW_DEV_QR_REISSUE)) {
    productionErrors.push('ALLOW_DEV_QR_REISSUE must be false in production/staging');
  }
  if (productionErrors.length) {
    // eslint-disable-next-line no-console
    console.error('❌ Production environment validation failed:\n', productionErrors.join('\n'));
    process.exit(1);
  }
}

module.exports = {
  server: {
    nodeEnv: env.NODE_ENV,
    port: env.PORT,
    apiVersion: env.API_VERSION,
    appName: env.APP_NAME,
    publicApiUrl: env.PUBLIC_API_URL,
  },
  jwt: {
    accessSecret: env.JWT_ACCESS_SECRET,
    refreshSecret: env.JWT_REFRESH_SECRET,
    accessExpiresIn: env.JWT_ACCESS_EXPIRES_IN,
    refreshExpiresIn: env.JWT_REFRESH_EXPIRES_IN,
  },
  external: {
    googleMapsApiKey: env.GOOGLE_MAPS_API_KEY,
    aviationStackApiKey: env.AVIATIONSTACK_API_KEY,
    aviationStackBaseUrl: env.AVIATIONSTACK_BASE_URL,
    aviationStackTimeoutMs: env.AVIATIONSTACK_TIMEOUT_MS,
    flightSyncEnabled: env.FLIGHT_SYNC_ENABLED,
    flightSyncMinIntervalMs: env.FLIGHT_SYNC_MIN_INTERVAL_MS,
    flightSyncIntervalMs: env.FLIGHT_SYNC_INTERVAL_MS,
    flightSyncBatchSize: env.FLIGHT_SYNC_BATCH_SIZE,
    flightSyncLookbackHours: env.FLIGHT_SYNC_LOOKBACK_HOURS,
    flightSyncLookaheadHours: env.FLIGHT_SYNC_LOOKAHEAD_HOURS,
    flightSyncMaxRetries: env.FLIGHT_SYNC_MAX_RETRIES,
    flightSyncRetryBaseMs: env.FLIGHT_SYNC_RETRY_BASE_MS,
    flightDelayNotificationDeltaMinutes: env.FLIGHT_DELAY_NOTIFICATION_DELTA_MINUTES,
  },
  firebase: {
    projectId: env.FIREBASE_PROJECT_ID,
    clientEmail: env.FIREBASE_CLIENT_EMAIL,
    privateKey: env.FIREBASE_PRIVATE_KEY,
    serviceAccountPath: env.FIREBASE_SERVICE_ACCOUNT_PATH,
  },
  database: {
    host: env.DB_HOST,
    port: env.DB_PORT,
    user: env.DB_USER,
    password: env.DB_PASSWORD,
    name: env.DB_NAME,
    connectionLimit: env.DB_CONNECTION_LIMIT,
  },
  upload: {
    dir: env.UPLOAD_DIR,
    maxFileSizeMb: env.UPLOAD_MAX_FILE_SIZE_MB,
    maxFileSizeBytes: env.UPLOAD_MAX_FILE_SIZE_MB * 1024 * 1024,
  },
  logging: {
    level: env.LOG_LEVEL,
    dir: env.LOG_DIR,
  },
  swagger: {
    enabled: env.SWAGGER_ENABLED,
    route: env.SWAGGER_ROUTE,
  },
  socket: {
    path: env.SOCKET_PATH,
  },
  cors: {
    origin: env.CORS_ORIGIN,
  },
  smtp: {
    host: env.SMTP_HOST,
    port: env.SMTP_PORT,
    secure: env.SMTP_SECURE,
    user: env.SMTP_USER,
    password: env.SMTP_PASSWORD,
    from: env.SMTP_FROM || env.SMTP_FROM_EMAIL,
    fromName: env.SMTP_FROM_NAME,
    fromEmail: env.SMTP_FROM_EMAIL || env.SMTP_FROM,
  },
  timezone: env.TZ,
  features: {
    allowDevQrReissue: resolveAllowDevQrReissue(env.NODE_ENV, env.ALLOW_DEV_QR_REISSUE),
  },
};
