const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { periodsOverlap } = require('../utils/pricing.util');

class RouteAdminService {
  constructor(
    routeRepository,
    vehiclePriceRepository,
    serviceTypeRepository,
    locationRepository,
  ) {
    this.routeRepository = routeRepository;
    this.vehiclePriceRepository = vehiclePriceRepository;
    this.serviceTypeRepository = serviceTypeRepository;
    this.locationRepository = locationRepository;
  }

  async list(options) {
    return this.routeRepository.findAll(options);
  }

  async getById(id) {
    const route = await this.routeRepository.findById(id);
    if (!route) {
      throw new AppError('Route not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }
    return route;
  }

  async assertServiceTypeExists(serviceTypeId) {
    const serviceType = await this.serviceTypeRepository.findById(serviceTypeId);
    if (!serviceType) {
      throw new AppError('Service type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return serviceType;
  }

  async assertLocationExists(locationId) {
    const location = await this.locationRepository.findById(locationId);
    if (!location) {
      throw new AppError('Location not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return location;
  }

  assertOriginNotDestination(originLocationId, destinationLocationId) {
    if (originLocationId === destinationLocationId) {
      throw new AppError('Origin and destination must be different', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
  }

  async resolveServiceTypeId(serviceTypeCode, serviceTypeId) {
    if (serviceTypeId) {
      await this.assertServiceTypeExists(serviceTypeId);
      return serviceTypeId;
    }
    const serviceType = await this.serviceTypeRepository.findByCode(serviceTypeCode);
    if (!serviceType) {
      throw new AppError('Service type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return serviceType.id;
  }

  async resolveLocationId(locationCode, locationId) {
    if (locationId) {
      await this.assertLocationExists(locationId);
      return locationId;
    }
    if (!locationCode) {
      throw new AppError('Location code or id is required', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    const location = await this.locationRepository.findByCode(
      String(locationCode).trim().toUpperCase(),
    );
    if (!location) {
      throw new AppError('Location not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return location.id;
  }

  async create(input, userId) {
    const serviceTypeId = await this.resolveServiceTypeId(
      input.serviceTypeCode,
      input.serviceTypeId,
    );
    const originLocationId = await this.resolveLocationId(
      input.originLocationCode,
      input.originLocationId,
    );
    const destinationLocationId = await this.resolveLocationId(
      input.destinationLocationCode,
      input.destinationLocationId,
    );
    this.assertOriginNotDestination(originLocationId, destinationLocationId);

    try {
      return await this.routeRepository.create({
        serviceTypeId,
        originLocationId,
        destinationLocationId,
        isActive: input.isActive,
        displayOrder: input.displayOrder,
        effectiveFrom: input.effectiveFrom,
        effectiveTo: input.effectiveTo,
        createdBy: userId,
        updatedBy: userId,
      });
    } catch (err) {
      if (err.code === 'ER_DUP_ENTRY') {
        throw new AppError('Route already exists for this service, origin, and destination', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      throw err;
    }
  }

  async update(id, input, userId) {
    const current = await this.getById(id);

    const serviceTypeId = input.serviceTypeCode || input.serviceTypeId
      ? await this.resolveServiceTypeId(input.serviceTypeCode, input.serviceTypeId)
      : current.serviceTypeId;

    const originLocationId = input.originLocationCode || input.originLocationId
      ? await this.resolveLocationId(input.originLocationCode, input.originLocationId)
      : current.originLocationId;

    const destinationLocationId = input.destinationLocationCode || input.destinationLocationId
      ? await this.resolveLocationId(input.destinationLocationCode, input.destinationLocationId)
      : current.destinationLocationId;

    this.assertOriginNotDestination(originLocationId, destinationLocationId);

    const data = {
      serviceTypeId,
      originLocationId,
      destinationLocationId,
      updatedBy: userId,
    };

    if (input.isActive !== undefined) {
      data.isActive = input.isActive;
    }
    if (input.displayOrder !== undefined) {
      data.displayOrder = input.displayOrder;
    }
    if (input.effectiveFrom !== undefined) {
      data.effectiveFrom = input.effectiveFrom;
    }
    if (input.effectiveTo !== undefined) {
      data.effectiveTo = input.effectiveTo;
    }

    return this.routeRepository.update(id, data);
  }

  async delete(id, userId) {
    await this.getById(id);
    await this.routeRepository.softDelete(id, userId);
    return true;
  }

  async copy(sourceRouteId, input, userId) {
    const source = await this.getById(sourceRouteId);
    const sourcePrices = await this.vehiclePriceRepository.findByRouteId(
      source.id,
      { includeInactive: false },
    );

    const newOriginLocationId = input.newOriginLocationId
      ?? input.originLocationId
      ?? await this.resolveLocationId(input.originLocationCode, null);

    let newDestinationLocationId = input.newDestinationLocationId
      ?? input.destinationLocationId;

    if (!newDestinationLocationId) {
      if (input.destinationLocationCode) {
        newDestinationLocationId = await this.resolveLocationId(input.destinationLocationCode, null);
      } else {
        newDestinationLocationId = source.destinationLocationId;
      }
    } else {
      await this.assertLocationExists(newDestinationLocationId);
    }

    this.assertOriginNotDestination(newOriginLocationId, newDestinationLocationId);

    let newRoute;
    try {
      newRoute = await this.routeRepository.create({
        serviceTypeId: input.serviceTypeId ?? source.serviceTypeId,
        originLocationId: newOriginLocationId,
        destinationLocationId: newDestinationLocationId,
        isActive: input.isActive ?? source.isActive,
        displayOrder: input.displayOrder ?? source.displayOrder,
        effectiveFrom: input.effectiveFrom ?? source.effectiveFrom,
        effectiveTo: input.effectiveTo ?? source.effectiveTo,
        createdBy: userId,
        updatedBy: userId,
      });
    } catch (err) {
      if (err.code === 'ER_DUP_ENTRY') {
        throw new AppError('Route already exists for this service, origin, and destination', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      throw err;
    }

    if (sourcePrices.length) {
      await this.vehiclePriceRepository.bulkCreate(
        sourcePrices.map((price) => ({
          routeId: newRoute.id,
          vehicleTypeId: price.vehicleTypeId,
          price: price.price,
          currency: price.currency,
          isActive: true,
          effectiveFrom: price.effectiveFrom,
          effectiveTo: price.effectiveTo,
          createdBy: userId,
          updatedBy: userId,
        })),
      );
    }

    return {
      route: newRoute,
      copiedVehiclePriceCount: sourcePrices.length,
    };
  }
}

module.exports = RouteAdminService;
