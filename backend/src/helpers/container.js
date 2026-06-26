/**
 * helpers/container.js — Simple Dependency Injection container
 */
const UserRepository = require('../repositories/user.repository');
const VehicleRepository = require('../repositories/vehicle.repository');
const LocationRepository = require('../repositories/location.repository');
const ServiceTypeRepository = require('../repositories/serviceType.repository');
const RouteRepository = require('../repositories/route.repository');
const VehiclePriceRepository = require('../repositories/vehiclePrice.repository');
const ChargePolicyRepository = require('../repositories/chargePolicy.repository');
const RevokedRefreshTokenStore = require('../services/revokedRefreshToken.store');
const TokenService = require('../services/token.service');
const AuthService = require('../services/auth.service');
const VehicleRecommendationService = require('../services/vehicleRecommendation.service');
const PricingService = require('../services/pricing.service');
const RouteAdminService = require('../services/routeAdmin.service');
const VehiclePriceAdminService = require('../services/vehiclePriceAdmin.service');
const ChargePolicyAdminService = require('../services/chargePolicyAdmin.service');
const BookingRepository = require('../repositories/booking.repository');
const ChatRepository = require('../repositories/chat.repository');
const BookingNumberService = require('../services/bookingNumber.service');
const BookingService = require('../services/booking.service');
const BookingStatusService = require('../services/bookingStatus.service');
const FlightService = require('../services/flight.service');
const DriverJobService = require('../services/driverJob.service');
const DriverQrService = require('../services/driverQr.service');
const config = require('../config/env');
const database = require('../config/database');

class Container {
  constructor() {
    this.registry = new Map();
  }

  register(name, factory) {
    this.registry.set(name, { factory, instance: null });
  }

  get(name) {
    const entry = this.registry.get(name);
    if (!entry) {
      throw new Error(`DI: '${name}' is not registered`);
    }
    if (!entry.instance) {
      entry.instance = entry.factory(this);
    }
    return entry.instance;
  }

  clear() {
    this.registry.clear();
  }
}

const container = new Container();

container.register('userRepository', () => new UserRepository());
container.register('revokedRefreshTokenStore', () => new RevokedRefreshTokenStore());
container.register('tokenService', (c) => new TokenService(c.get('revokedRefreshTokenStore')));
container.register('authService', (c) => new AuthService(
  c.get('userRepository'),
  c.get('tokenService'),
));
container.register('vehicleRepository', () => new VehicleRepository());
container.register('vehicleRecommendationService', (c) => new VehicleRecommendationService(
  c.get('vehicleRepository'),
));
container.register('locationRepository', () => new LocationRepository());
container.register('serviceTypeRepository', () => new ServiceTypeRepository());
container.register('routeRepository', () => new RouteRepository());
container.register('vehiclePriceRepository', () => new VehiclePriceRepository());
container.register('chargePolicyRepository', () => new ChargePolicyRepository());
container.register('pricingService', (c) => new PricingService(
  c.get('serviceTypeRepository'),
  c.get('locationRepository'),
  c.get('routeRepository'),
  c.get('vehiclePriceRepository'),
  c.get('chargePolicyRepository'),
  c.get('vehicleRepository'),
));
container.register('routeAdminService', (c) => new RouteAdminService(
  c.get('routeRepository'),
  c.get('vehiclePriceRepository'),
  c.get('serviceTypeRepository'),
  c.get('locationRepository'),
));
container.register('vehiclePriceAdminService', (c) => new VehiclePriceAdminService(
  c.get('vehiclePriceRepository'),
  c.get('routeRepository'),
  c.get('vehicleRepository'),
));
container.register('chargePolicyAdminService', (c) => new ChargePolicyAdminService(
  c.get('chargePolicyRepository'),
));
container.register('bookingRepository', () => new BookingRepository());
container.register('chatRepository', () => new ChatRepository());
container.register('bookingNumberService', () => new BookingNumberService());
container.register('bookingStatusService', (c) => new BookingStatusService(
  database.pool,
  c.get('bookingRepository'),
));
container.register('bookingService', (c) => new BookingService(
  database.pool,
  c.get('bookingRepository'),
  c.get('chatRepository'),
  c.get('bookingNumberService'),
  c.get('pricingService'),
  c.get('vehicleRecommendationService'),
  c.get('vehicleRepository'),
));
container.register('flightService', () => new FlightService({
  apiKey: config.external.aviationStackApiKey,
  baseUrl: config.external.aviationStackBaseUrl,
  timeoutMs: config.external.aviationStackTimeoutMs,
}));
container.register('driverJobService', (c) => new DriverJobService(
  c.get('bookingRepository'),
));
container.register('driverQrService', (c) => new DriverQrService(
  database.pool,
  c.get('bookingRepository'),
  c.get('bookingStatusService'),
  c.get('driverJobService'),
));

module.exports = container;
