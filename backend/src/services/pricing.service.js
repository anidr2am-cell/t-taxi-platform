const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const CHARGE_POLICY_TYPES = require('../constants/chargePolicyTypes');
const CHARGE_TYPES = require('../constants/chargeTypes');
const CALCULATION_TYPES = require('../constants/calculationTypes');
const SERVICE_TYPES = require('../constants/serviceTypes');
const {
  isEffectiveAt,
  mapPolicyTypeToChargeType,
  roundMoney,
} = require('../utils/pricing.util');

class PricingService {
  constructor(
    serviceTypeRepository,
    locationRepository,
    routeRepository,
    vehiclePriceRepository,
    chargePolicyRepository,
    vehicleRepository,
  ) {
    this.serviceTypeRepository = serviceTypeRepository;
    this.locationRepository = locationRepository;
    this.routeRepository = routeRepository;
    this.vehiclePriceRepository = vehiclePriceRepository;
    this.chargePolicyRepository = chargePolicyRepository;
    this.vehicleRepository = vehicleRepository;
  }

  normalizeRegionCode(value) {
    return String(value).trim().toUpperCase().replace(/\s+/g, '_');
  }

  async resolveLocations(input) {
    let origin = null;
    let destination = null;

    if (input.originLocationId) {
      origin = await this.locationRepository.findById(input.originLocationId);
    } else if (input.originLocationCode) {
      origin = await this.locationRepository.findByCode(
        this.normalizeRegionCode(input.originLocationCode),
      );
    } else if (input.originAirportIata) {
      origin = await this.locationRepository.findByAirportIata(
        input.originAirportIata.trim().toUpperCase(),
      );
    }

    if (input.destinationLocationId) {
      destination = await this.locationRepository.findById(input.destinationLocationId);
    } else if (input.destinationLocationCode) {
      destination = await this.locationRepository.findByCode(
        this.normalizeRegionCode(input.destinationLocationCode),
      );
    } else if (input.destinationRegion) {
      destination = await this.locationRepository.findByCode(
        this.normalizeRegionCode(input.destinationRegion),
      );
    }

    return { origin, destination };
  }

  async resolveServiceType(serviceType) {
    if (typeof serviceType === 'number') {
      const row = await this.serviceTypeRepository.findById(serviceType);
      if (!row) {
        throw new AppError('Service type not found', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }
      return row;
    }

    const code = String(serviceType).trim().toUpperCase();
    if (!Object.values(SERVICE_TYPES).includes(code)) {
      throw new AppError('Service type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const row = await this.serviceTypeRepository.findByCode(code);
    if (!row) {
      throw new AppError('Service type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return row;
  }

  selectRoute(routes, at) {
    const effective = routes.filter((route) => isEffectiveAt(route, at));
    return effective[0] || routes[0] || null;
  }

  selectVehiclePrice(prices, vehicleTypeId, at) {
    const active = prices.filter(
      (price) => price.vehicleTypeId === vehicleTypeId
        && price.isActive
        && isEffectiveAt(price, at),
    );
    return active[0] || null;
  }

  isNightTime(scheduledAt) {
    if (!scheduledAt) {
      return false;
    }
    const date = new Date(scheduledAt);
    if (Number.isNaN(date.getTime())) {
      return false;
    }
    const hour = date.getHours();
    return hour >= 22 || hour < 6;
  }

  isWeekend(scheduledAt) {
    if (!scheduledAt) {
      return false;
    }
    const date = new Date(scheduledAt);
    if (Number.isNaN(date.getTime())) {
      return false;
    }
    const day = date.getDay();
    return day === 0 || day === 6;
  }

  isAirportService(serviceTypeCode) {
    return serviceTypeCode === 'AIRPORT_PICKUP' || serviceTypeCode === 'AIRPORT_DROPOFF';
  }

  shouldApplyPolicy(policy, context) {
    const { options, serviceTypeCode, scheduledPickupAt } = context;

    switch (policy.chargeType) {
      case CHARGE_POLICY_TYPES.NAME_SIGN:
        return Boolean(options?.nameSign);
      case CHARGE_POLICY_TYPES.NIGHT:
        return this.isNightTime(scheduledPickupAt);
      case CHARGE_POLICY_TYPES.HOLIDAY:
        return this.isWeekend(scheduledPickupAt);
      case CHARGE_POLICY_TYPES.AIRPORT:
        return this.isAirportService(serviceTypeCode);
      case CHARGE_POLICY_TYPES.WAITING:
        return Boolean(options?.waiting);
      case CHARGE_POLICY_TYPES.PARKING:
        return Boolean(options?.parking);
      case CHARGE_POLICY_TYPES.TOLL:
        return Boolean(options?.toll);
      default:
        return false;
    }
  }

  calculatePolicyAmount(policy, baseAmount, subtotal) {
    switch (policy.calculationType) {
      case CALCULATION_TYPES.FIXED:
        return roundMoney(Number(policy.amount));
      case CALCULATION_TYPES.PERCENT_OF_BASE:
        return roundMoney(baseAmount * (Number(policy.amount) / 100));
      case CALCULATION_TYPES.PERCENT_OF_SUBTOTAL:
        return roundMoney(subtotal * (Number(policy.amount) / 100));
      default:
        return 0;
    }
  }

  buildPolicyDescription(policy) {
    const labels = {
      [CHARGE_POLICY_TYPES.NAME_SIGN]: 'Name sign service',
      [CHARGE_POLICY_TYPES.WAITING]: 'Waiting charge',
      [CHARGE_POLICY_TYPES.PARKING]: 'Parking charge',
      [CHARGE_POLICY_TYPES.TOLL]: 'Toll charge',
      [CHARGE_POLICY_TYPES.HOLIDAY]: 'Holiday surcharge',
      [CHARGE_POLICY_TYPES.NIGHT]: 'Night surcharge',
      [CHARGE_POLICY_TYPES.AIRPORT]: 'Airport surcharge',
    };
    return labels[policy.chargeType] || policy.chargeType;
  }

  async computeQuote({
    serviceType,
    vehicleType,
    originLocationId,
    destinationLocationId,
    vehicleCount = 1,
    options = {},
    scheduledPickupAt,
  }) {
    if (originLocationId === destinationLocationId) {
      throw new AppError('Origin and destination must be different', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const routes = await this.routeRepository.findActiveByServiceAndLocations(
      serviceType.id,
      originLocationId,
      destinationLocationId,
    );

    if (!routes.length) {
      throw new AppError('Route not found for the given service and locations', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }

    const at = scheduledPickupAt ? new Date(scheduledPickupAt) : new Date();
    const route = this.selectRoute(routes, at);

    const vehiclePrices = await this.vehiclePriceRepository.findByRouteId(route.id);
    const vehiclePrice = this.selectVehiclePrice(vehiclePrices, vehicleType.id, at);

    if (!vehiclePrice) {
      throw new AppError('Vehicle price not configured for this route', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }

    const baseUnitPrice = roundMoney(vehiclePrice.price);
    const baseAmount = roundMoney(baseUnitPrice * vehicleCount);

    const chargeItems = [{
      chargeType: CHARGE_TYPES.VEHICLE_BASE,
      description: `${vehicleType.code} ${serviceType.code}`,
      quantity: vehicleCount,
      unitPrice: baseUnitPrice,
      amount: baseAmount,
      referenceType: 'VEHICLE_PRICE',
      referenceId: vehiclePrice.id,
    }];

    let subtotal = baseAmount;
    const policies = await this.chargePolicyRepository.findActivePolicies();
    const context = {
      options,
      serviceTypeCode: serviceType.code,
      scheduledPickupAt,
    };

    for (const policy of policies) {
      if (!isEffectiveAt(policy, at) || !this.shouldApplyPolicy(policy, context)) {
        continue;
      }

      const policyAmount = this.calculatePolicyAmount(policy, baseAmount, subtotal);
      if (policyAmount === 0) {
        continue;
      }

      chargeItems.push({
        chargeType: mapPolicyTypeToChargeType(policy.chargeType),
        description: this.buildPolicyDescription(policy),
        quantity: 1,
        unitPrice: policyAmount,
        amount: policyAmount,
        referenceType: 'CHARGE_POLICY',
        referenceId: policy.id,
      });
      subtotal = roundMoney(subtotal + policyAmount);
    }

    const discount = 0;
    const totalAmount = roundMoney(subtotal - discount);

    return {
      route,
      vehiclePrice,
      vehicleType,
      serviceType,
      chargeItems,
      subtotal,
      discount,
      totalAmount,
      currency: vehiclePrice.currency,
    };
  }

  async simulate(input) {
    const serviceType = await this.resolveServiceType(input.serviceType);

    const origin = await this.locationRepository.findById(input.originLocationId);
    const destination = await this.locationRepository.findById(input.destinationLocationId);
    if (!origin || !destination) {
      throw new AppError('Origin or destination location not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const vehicleType = await this.vehicleRepository.findTypeById(input.vehicleTypeId);
    if (!vehicleType) {
      throw new AppError('Vehicle type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const quote = await this.computeQuote({
      serviceType,
      vehicleType,
      originLocationId: input.originLocationId,
      destinationLocationId: input.destinationLocationId,
      vehicleCount: 1,
      options: input.options ?? {},
      scheduledPickupAt: input.scheduledPickupAt,
    });

    const responseChargeItems = quote.chargeItems.map((item) => ({
      chargeType: item.chargeType,
      description: item.description,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      amount: item.amount,
    }));

    return {
      matchedRoute: quote.route,
      vehicleBasePrice: {
        id: quote.vehiclePrice.id,
        routeId: quote.vehiclePrice.routeId,
        vehicleTypeId: quote.vehiclePrice.vehicleTypeId,
        vehicleTypeCode: quote.vehicleType.code,
        price: quote.vehiclePrice.price,
        currency: quote.vehiclePrice.currency,
        effectiveFrom: quote.vehiclePrice.effectiveFrom,
        effectiveTo: quote.vehiclePrice.effectiveTo,
      },
      chargeItems: responseChargeItems,
      subtotal: quote.subtotal,
      discount: quote.discount,
      totalAmount: quote.totalAmount,
      currency: quote.currency,
    };
  }

  async calculate(input) {
    const serviceType = await this.serviceTypeRepository.findByCode(input.serviceTypeCode);
    if (!serviceType) {
      throw new AppError('Service type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const vehicleType = await this.vehicleRepository.findTypeByCode(input.vehicleTypeCode);
    if (!vehicleType) {
      throw new AppError('Vehicle type not found', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }

    const { origin, destination } = await this.resolveLocations(input);
    if (!origin || !destination) {
      throw new AppError('Origin or destination location not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }

    const quote = await this.computeQuote({
      serviceType,
      vehicleType,
      originLocationId: origin.id,
      destinationLocationId: destination.id,
      vehicleCount: input.vehicleCount ?? 1,
      options: input.options ?? {},
      scheduledPickupAt: input.scheduledPickupAt,
    });

    const responseItems = quote.chargeItems.map((item) => ({
      chargeType: item.chargeType,
      description: item.description,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      amount: item.amount,
      referenceType: item.referenceType ?? null,
      referenceId: item.referenceId ?? null,
    }));

    return {
      currency: quote.currency,
      chargeItems: responseItems,
      totalAmount: quote.totalAmount,
      appliedPricingRuleId: quote.route.id,
      routeId: quote.route.id,
      vehiclePriceId: quote.vehiclePrice.id,
    };
  }
}

module.exports = PricingService;
