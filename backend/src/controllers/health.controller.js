/**
 * controllers/health.controller.js
 *
 * Controller: HTTP 입출력만. 비즈니스 로직은 Service에 위임.
 */
const asyncHandler = require('../utils/asyncHandler');
const { success } = require('../utils/apiResponse');
const config = require('../config');
const database = require('../config/database');
const HTTP_STATUS = require('../constants/httpStatus');
const { uploadDir } = require('../config/multer');
const container = require('../helpers/container');
const fs = require('fs/promises');
const path = require('path');

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

async function canWriteUploadDirectory() {
  const probe = path.join(uploadDir, `.readiness-${process.pid}-${Date.now()}.tmp`);
  try {
    await fs.mkdir(uploadDir, { recursive: true });
    await fs.writeFile(probe, 'ok', { encoding: 'utf8' });
    await fs.unlink(probe);
    return true;
  } catch {
    try {
      await fs.unlink(probe);
    } catch {
      // ignore cleanup failures for a best-effort readiness probe
    }
    return false;
  }
}

const getReadiness = asyncHandler(async (req, res) => {
  let dbOk = false;
  try {
    dbOk = await database.ping();
  } catch {
    dbOk = false;
  }

  const uploadWritable = await canWriteUploadDirectory();
  const flightSyncScheduler = container.get('flightSyncSchedulerService');
  const flightSyncStatus = flightSyncScheduler.getStatus();
  const ready = dbOk && uploadWritable;

  return success(
    res,
    {
      status: ready ? 'ready' : 'degraded',
      timestamp: new Date().toISOString(),
      checks: {
        database: dbOk ? 'connected' : 'disconnected',
        uploadDirectory: uploadWritable ? 'writable' : 'not_writable',
      },
      integrations: {
        aviationstackConfigured: flightSyncStatus.providerConfigured,
        flightSyncEnabled: flightSyncStatus.enabled,
        flightSyncRunning: flightSyncStatus.running,
        smtpConfigured: Boolean(config.smtp.host),
        firebaseConfigured: Boolean(
          config.firebaseSettings.projectId || config.firebaseSettings.serviceAccountPath,
        ),
      },
    },
    'OK',
    ready ? HTTP_STATUS.OK : HTTP_STATUS.SERVICE_UNAVAILABLE,
  );
});

module.exports = {
  getHealth,
  getReadiness,
};
