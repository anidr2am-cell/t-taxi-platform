/**
 * app.js — Express application factory
 *
 * HTTP 미들웨어, Swagger, API 라우트, 에러 핸들러를 조립합니다.
 * server.js가 이 모듈을 import하여 HTTP 서버에 연결합니다.
 *
 * 원칙: 비즈니스 로직은 여기에 넣지 않습니다.
 */
const express = require('express');
const helmet = require('helmet');
const cors = require('cors');
const config = require('./config');
const logger = require('./utils/logger');
const { setupSwagger } = require('./config/swagger');
const routes = require('./routes');
const notFoundMiddleware = require('./middlewares/notFound.middleware');
const errorMiddleware = require('./middlewares/error.middleware');
const requestLoggerMiddleware = require('./middlewares/requestLogger.middleware');

const app = express();

app.set('trust proxy', 1);

app.use(helmet({ contentSecurityPolicy: config.server.nodeEnv === 'production' }));
app.use(cors(config.cors.options));
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));
app.use(requestLoggerMiddleware);

if (config.swagger.enabled) {
  setupSwagger(app);
}

app.use(`/api/${config.server.apiVersion}`, routes);

app.use(notFoundMiddleware);
app.use(errorMiddleware);

app.on('mount', () => {
  logger.debug('Express app mounted');
});

module.exports = app;
