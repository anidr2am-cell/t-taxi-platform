const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const logger = require('../utils/logger');

const DRIVER_STATUS = {
  AVAILABLE: 'AVAILABLE',
  OFFLINE: 'OFFLINE',
  SUSPENDED: 'SUSPENDED',
};

class DriverStatusService {
  constructor(pool, driverRepository, commissionSettlementService = null) {
    this.pool = pool;
    this.driverRepository = driverRepository;
    this.commissionSettlementService = commissionSettlementService;
  }

  mapStatus(driver, hasActiveJob = null) {
    return {
      driverId: Number(driver.id),
      active: Boolean(driver.is_active) && Boolean(driver.user_is_active ?? 1),
      online: Boolean(driver.is_online) && driver.status !== DRIVER_STATUS.OFFLINE,
      status: driver.status,
      hasActiveJob: hasActiveJob ?? Number(driver.active_job_count ?? 0) > 0,
      lastSeenAt: driver.last_seen_at ?? null,
    };
  }

  assertCanGoOnline(driver) {
    if (!driver || !driver.is_active || driver.user_is_active === 0) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    if (driver.status === DRIVER_STATUS.SUSPENDED) {
      throw new AppError('Driver is suspended', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }
  }

  async assertSettlementEligible(driverId) {
    if (!this.commissionSettlementService) return;
    const blocked = await this.commissionSettlementService.driverHasBlockingSettlement(driverId);
    if (blocked) {
      throw new AppError('This driver cannot receive a new job until the previous settlement is confirmed.', {
        statusCode: HTTP_STATUS.CONFLICT,
        errorCode: ERROR_CODES.DRIVER_NOT_ELIGIBLE,
      });
    }
  }

  async getStatus(driverUserId) {
    const driver = await this.driverRepository.findByUserId(driverUserId);
    if (!driver || !driver.is_active || driver.user_is_active === 0) {
      throw new AppError('Driver not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
      });
    }
    return this.mapStatus(driver);
  }

  async goOnline(driverUserId) {
    const conn = await this.pool.getConnection();
    let driver;
    let hasActiveJob = false;
    try {
      await conn.beginTransaction();
      driver = await this.driverRepository.findByUserIdForUpdate(conn, driverUserId);
      this.assertCanGoOnline(driver);
      await this.assertSettlementEligible(driver.id);
      hasActiveJob = await this.driverRepository.hasActiveJob(conn, driver.id);
      await this.driverRepository.updateOnlineState(conn, driver.id, {
        isOnline: true,
        status: DRIVER_STATUS.AVAILABLE,
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    logger.info('Driver went online', { driverId: driver.id });
    return this.getStatus(driverUserId).then((status) => ({ ...status, hasActiveJob }));
  }

  async goOffline(driverUserId, { allowActiveJob = false } = {}) {
    const conn = await this.pool.getConnection();
    let driver;
    let hasActiveJob = false;
    try {
      await conn.beginTransaction();
      driver = await this.driverRepository.findByUserIdForUpdate(conn, driverUserId);
      if (!driver || !driver.is_active || driver.user_is_active === 0) {
        throw new AppError('Driver not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.DRIVER_NOT_FOUND,
        });
      }
      hasActiveJob = await this.driverRepository.hasActiveJob(conn, driver.id);
      if (hasActiveJob && !allowActiveJob) {
        throw new AppError('Cannot go offline while an active trip is assigned', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.DRIVER_NOT_AVAILABLE,
        });
      }
      await this.driverRepository.updateOnlineState(conn, driver.id, {
        isOnline: false,
        status: DRIVER_STATUS.OFFLINE,
      });
      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    logger.info('Driver went offline', { driverId: driver.id, hasActiveJob });
    return this.getStatus(driverUserId).then((status) => ({ ...status, hasActiveJob }));
  }

  async goOfflineBestEffort(driverUserId) {
    try {
      await this.goOffline(driverUserId);
    } catch (err) {
      logger.warn('Best-effort driver offline update failed', {
        driverUserId,
        errorCode: err.errorCode,
      });
    }
  }
}

module.exports = DriverStatusService;
