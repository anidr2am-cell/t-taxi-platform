/**
 * controllers/health.controller.js
 *
 * Controller: HTTP 입출력만. 비즈니스 로직은 Service에 위임.
 */
const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const config = require('../config');
const database = require('../config/database');

const getHealth = asyncHandler(async (req, res) => {
  let dbOk = false;
  try {
    dbOk = await database.ping();
  } catch {
    dbOk = false;
  }

  return success(res, {
    status: dbOk ? 'ok' : 'degraded',
    version: config.server.apiVersion,
    app: config.server.appName,
    timestamp: new Date().toISOString(),
    database: dbOk ? 'connected' : 'disconnected',
  });
});

module.exports = {
  getHealth,
};
