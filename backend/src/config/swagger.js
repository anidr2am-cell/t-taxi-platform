/**
 * config/swagger.js — Swagger UI + OpenAPI 3.1 spec
 *
 * docs/openapi/openapi.yaml 을 읽어 Swagger UI에 연결합니다.
 * Flutter / Admin / Driver 팀과 동일한 API 문서를 서버에서 제공합니다.
 */
const path = require('path');
const fs = require('fs');
const yaml = require('yaml');
const swaggerUi = require('swagger-ui-express');
const env = require('./env');
const logger = require('../utils/logger');

const OPENAPI_PATH = path.resolve(__dirname, '../../../docs/openapi/openapi.yaml');

function loadOpenApiSpec() {
  if (!fs.existsSync(OPENAPI_PATH)) {
    logger.warn(`OpenAPI file not found: ${OPENAPI_PATH}`);
    return { openapi: '3.1.0', info: { title: 'TTaxi API', version: '1.0.0' }, paths: {} };
  }
  const raw = fs.readFileSync(OPENAPI_PATH, 'utf8');
  return yaml.parse(raw);
}

function setupSwagger(app) {
  if (!env.swagger.enabled) {
    logger.info('Swagger UI disabled');
    return;
  }

  const spec = loadOpenApiSpec();
  const route = env.swagger.route;

  app.use(route, swaggerUi.serve, swaggerUi.setup(spec, {
    customSiteTitle: 'TTaxi API Docs',
    swaggerOptions: {
      persistAuthorization: true,
    },
  }));

  app.get(`${route}/openapi.json`, (req, res) => {
    res.json(spec);
  });

  logger.info(`Swagger UI mounted at ${route}`);
}

module.exports = {
  loadOpenApiSpec,
  setupSwagger,
  OPENAPI_PATH,
};
