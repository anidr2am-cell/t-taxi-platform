/**
 * server.js — Application entry point
 *
 * 역할:
 * 1. 환경 변수 로드 (dotenv)
 * 2. Express app 생성 (app.js)
 * 3. HTTP 서버 + Socket.IO 부트
 * 4. Graceful shutdown (SIGTERM / SIGINT)
 *
 * 실행: npm run dev | npm start
 */
require('dotenv').config();

const http = require('http');
const { Server } = require('socket.io');
const app = require('./app');
const config = require('./config');
const logger = require('./utils/logger');
const { initSocket } = require('./socket');
const { registerSettlementHandlers } = require('./events/handlers/settlement.handler');

registerSettlementHandlers();

const PORT = config.server.port;

const httpServer = http.createServer(app);

const io = new Server(httpServer, {
  path: config.socket.path,
  cors: {
    origin: config.cors.origin,
    methods: ['GET', 'POST'],
    credentials: true,
  },
});

initSocket(io);

httpServer.listen(PORT, () => {
  logger.info(`TTaxi API listening on http://localhost:${PORT}`);
  logger.info(`Environment: ${config.server.nodeEnv}`);
if (config.swagger.enabled) {
    logger.info(`Swagger UI: http://localhost:${PORT}${config.swagger.route}`);
  }
  logger.info(`API base: http://localhost:${PORT}/api/${config.server.apiVersion}`);
});

function shutdown(signal) {
  logger.info(`${signal} received — shutting down gracefully`);
  httpServer.close(() => {
    logger.info('HTTP server closed');
    process.exit(0);
  });
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

process.on('unhandledRejection', (reason) => {
  logger.error('Unhandled Rejection', { reason });
});

process.on('uncaughtException', (err) => {
  logger.error('Uncaught Exception', { err });
  shutdown('uncaughtException');
});

module.exports = { httpServer, io };
