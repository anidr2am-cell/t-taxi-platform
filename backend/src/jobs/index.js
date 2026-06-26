/**
 * jobs/index.js — Scheduled tasks (cron) skeleton
 *
 * 구현 단계: node-cron 또는 별도 worker 프로세스
 */
const logger = require('../utils/logger');

function registerJobs() {
  logger.info('Background jobs: none registered (skeleton)');
  // Example: sync flight delays, cleanup old socket sessions
}

module.exports = {
  registerJobs,
};
