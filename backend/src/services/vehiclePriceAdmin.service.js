const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { periodsOverlap } = require('../utils/pricing.util');

class VehiclePriceAdminService {
  constructor(vehiclePriceRepository, routeRepository, vehicleRepository) {
    this.vehiclePriceRepository = vehiclePriceRepository;
    this.routeRepository = routeRepository;
    this.vehicleRepository = vehicleRepository;
  }

  async list(options) {
    return this.vehiclePriceRepository.findAll(options);
  }

  async getById(id) {
    const price = await this.vehiclePriceRepository.findById(id);
    if (!price) {
      throw new AppError('Vehicle price not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }
    return price;
  }

  async assertNoOverlappingActivePrice(routeId, vehicleTypeId, period, excludeId) {
    const activePrices = await this.vehiclePriceRepository.findActiveByRouteAndVehicleType(
      routeId,
      vehicleTypeId,
      { excludeId },
    );

    const candidate = {
      effectiveFrom: period.effectiveFrom ?? null,
      effectiveTo: period.effectiveTo ?? null,
    };

    const overlap = activePrices.find((existing) => periodsOverlap(candidate, existing));
    if (overlap) {
      throw new AppError('An active price already exists for this route, vehicle type, and effective period', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
  }

  async resolveVehicleTypeId(vehicleTypeCode, vehicleTypeId) {
    if (vehicleTypeId) {
      const vehicleType = await this.vehicleRepository.findTypeById(vehicleTypeId);
      if (!vehicleType) {
        throw new AppError('Vehicle type not found', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      return vehicleType.id;
    }

    const vehicleType = await this.vehicleRepository.findTypeByCode(vehicleTypeCode);
    if (!vehicleType) {
      throw new AppError('Vehicle type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return vehicleType.id;
  }

  async create(input, userId) {
    const route = await this.routeRepository.findById(input.routeId);
    if (!route) {
      throw new AppError('Route not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const vehicleTypeId = await this.resolveVehicleTypeId(
      input.vehicleTypeCode,
      input.vehicleTypeId,
    );

    const isActive = input.isActive ?? true;
    if (isActive) {
      await this.assertNoOverlappingActivePrice(input.routeId, vehicleTypeId, {
        effectiveFrom: input.effectiveFrom,
        effectiveTo: input.effectiveTo,
      });
    }

    return this.vehiclePriceRepository.create({
      routeId: input.routeId,
      vehicleTypeId,
      price: input.price,
      currency: input.currency,
      isActive,
      effectiveFrom: input.effectiveFrom,
      effectiveTo: input.effectiveTo,
      createdBy: userId,
      updatedBy: userId,
    });
  }

  async update(id, input, userId) {
    const current = await this.getById(id);

    const isActive = input.isActive !== undefined ? input.isActive : current.isActive;
    const effectiveFrom = input.effectiveFrom !== undefined
      ? input.effectiveFrom
      : current.effectiveFrom;
    const effectiveTo = input.effectiveTo !== undefined
      ? input.effectiveTo
      : current.effectiveTo;

    if (isActive) {
      await this.assertNoOverlappingActivePrice(
        current.routeId,
        current.vehicleTypeId,
        { effectiveFrom, effectiveTo },
        id,
      );
    }

    return this.vehiclePriceRepository.update(id, {
      price: input.price,
      currency: input.currency,
      isActive: input.isActive,
      effectiveFrom: input.effectiveFrom,
      effectiveTo: input.effectiveTo,
      updatedBy: userId,
    });
  }

  async delete(id, userId) {
    await this.getById(id);
    await this.vehiclePriceRepository.softDelete(id, userId);
    return true;
  }
}

module.exports = VehiclePriceAdminService;
