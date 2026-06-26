/**
 * config/env.js — Environment validation with Joi
 *
 * 앱 시작 시 .env 값을 검증합니다. 필수 값이 없으면 즉시 종료하여
 * 런타임 중 예기치 않은 오류를 방지합니다.
 */
const Joi = require('joi');

const envSchema = Joi.object({
  NODE_ENV: Joi.string().valid('development', 'production', 'test').default('development'),
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
  FIREBASE_PROJECT_ID: Joi.string().allow('').optional(),
  FIREBASE_CLIENT_EMAIL: Joi.string().allow('').optional(),
  FIREBASE_PRIVATE_KEY: Joi.string().allow('').optional(),
  FIREBASE_SERVICE_ACCOUNT_PATH: Joi.string().optional(),
  UPLOAD_DIR: Joi.string().default('./uploads'),
  UPLOAD_MAX_FILE_SIZE_MB: Joi.number().min(1).max(50).default(10),
  LOG_LEVEL: Joi.string().valid('error', 'warn', 'info', 'debug').default('info'),
  LOG_DIR: Joi.string().default('./logs'),
  SWAGGER_ENABLED: Joi.boolean().truthy('true').falsy('false').default(true),
  SWAGGER_ROUTE: Joi.string().default('/api-docs'),
  SOCKET_PATH: Joi.string().default('/socket.io'),
}).unknown(true);

const { value: env, error } = envSchema.validate(process.env, { abortEarly: false });

if (error) {
  // eslint-disable-next-line no-console
  console.error('❌ Invalid environment variables:\n', error.details.map((d) => d.message).join('\n'));
  process.exit(1);
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
};
