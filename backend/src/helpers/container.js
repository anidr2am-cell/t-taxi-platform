/**
 * helpers/container.js — Simple Dependency Injection container
 */
const UserRepository = require('../repositories/user.repository');
const VehicleRepository = require('../repositories/vehicle.repository');
const VehicleService = require('../services/vehicle.service');
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
const PricingAdminService = require('../services/pricingAdmin.service');
const BookingRepository = require('../repositories/booking.repository');
const AdminDashboardRepository = require('../repositories/adminDashboard.repository');
const ChatRepository = require('../repositories/chat.repository');
const BookingNumberService = require('../services/bookingNumber.service');
const BookingService = require('../services/booking.service');
const GuestBookingLookupService = require('../services/guestBookingLookup.service');
const BookingStatusService = require('../services/bookingStatus.service');
const AdminDashboardService = require('../services/adminDashboard.service');
const FlightService = require('../services/flight.service');
const PlacesService = require('../services/places.service');
const DriverJobService = require('../services/driverJob.service');
const DriverStatusService = require('../services/driverStatus.service');
const DriverRepository = require('../repositories/driver.repository');
const DriverLocationRepository = require('../repositories/driverLocation.repository');
const DriverLocationService = require('../services/driverLocation.service');
const FileRepository = require('../repositories/file.repository');
const SettingsRepository = require('../repositories/settings.repository');
const CommissionSettlementService = require('../services/commissionSettlement.service');
const ReviewRepository = require('../repositories/review.repository');
const ReviewService = require('../services/review.service');
const AdminDispatchService = require('../services/adminDispatch.service');
const DriverCandidateScoringService = require('../services/driverCandidateScoring.service');
const AdminQrReissueService = require('../services/adminQrReissue.service');
const DriverQrService = require('../services/driverQr.service');
const DriverTripFlowService = require('../services/driverTripFlow.service');
const NotificationRepository = require('../repositories/notification.repository');
const NotificationService = require('../services/notification.service');
const OutboxRepository = require('../repositories/outbox.repository');
const OutboxProcessor = require('../services/outboxProcessor.service');
const FlightMonitorRepository = require('../repositories/flightMonitor.repository');
const DriverApplicationRepository = require('../repositories/driverApplication.repository');
const SupportInquiryRepository = require('../repositories/supportInquiry.repository');
const AdminFlightMonitorService = require('../services/adminFlightMonitor.service');
const FlightSyncWorker = require('../workers/flightSync.worker');
const FlightSyncSchedulerService = require('../services/flightSyncScheduler.service');
const ChatService = require('../services/chat.service');
const DriverApplicationService = require('../services/driverApplication.service');
const SupportInquiryService = require('../services/supportInquiry.service');
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
container.register('vehicleService', (c) => new VehicleService(
  c.get('vehicleRepository'),
));
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
container.register('pricingAdminService', (c) => new PricingAdminService(
  c.get('routeRepository'),
  c.get('vehiclePriceRepository'),
  c.get('chargePolicyRepository'),
));
container.register('bookingRepository', () => new BookingRepository());
container.register('adminDashboardRepository', () => new AdminDashboardRepository());
container.register('chatRepository', () => new ChatRepository());
container.register('bookingNumberService', () => new BookingNumberService());
container.register('bookingStatusService', (c) => new BookingStatusService(
  database.pool,
  c.get('bookingRepository'),
  c.get('outboxRepository'),
  c.get('outboxProcessor'),
));
container.register('bookingService', (c) => new BookingService(
  database.pool,
  c.get('bookingRepository'),
  c.get('chatRepository'),
  c.get('bookingNumberService'),
  c.get('pricingService'),
  c.get('vehicleRecommendationService'),
  c.get('vehicleRepository'),
  c.get('outboxRepository'),
  c.get('outboxProcessor'),
  c.get('flightService'),
));
container.register('guestBookingLookupService', (c) => new GuestBookingLookupService(
  database.pool,
  c.get('bookingRepository'),
));
container.register('adminDashboardService', (c) => new AdminDashboardService(
  c.get('adminDashboardRepository'),
));
container.register('flightService', () => new FlightService({
  apiKey: config.external.aviationStackApiKey,
  baseUrl: config.external.aviationStackBaseUrl,
  timeoutMs: config.external.aviationStackTimeoutMs,
}));
container.register('placesService', () => new PlacesService({
  apiKey: config.external.googleMapsApiKey,
}));
container.register('driverJobService', (c) => new DriverJobService(
  c.get('bookingRepository'),
));
container.register('driverStatusService', (c) => new DriverStatusService(
  database.pool,
  c.get('driverRepository'),
  c.get('commissionSettlementService'),
));
container.register('driverRepository', () => new DriverRepository());
container.register('driverLocationRepository', () => new DriverLocationRepository());
container.register('driverLocationService', (c) => new DriverLocationService(
  database.pool,
  c.get('driverLocationRepository'),
));
container.register('settingsRepository', () => new SettingsRepository());
container.register('fileRepository', () => new FileRepository());
container.register('commissionSettlementService', (c) => new CommissionSettlementService(
  database.pool,
  c.get('bookingRepository'),
  c.get('driverRepository'),
  c.get('fileRepository'),
  c.get('settingsRepository'),
  c.get('outboxRepository'),
  c.get('outboxProcessor'),
));
container.register('reviewRepository', () => new ReviewRepository());
container.register('reviewService', (c) => new ReviewService(
  database.pool,
  c.get('bookingRepository'),
  c.get('reviewRepository'),
  c.get('driverRepository'),
  c.get('bookingService'),
  c.get('outboxRepository'),
  c.get('outboxProcessor'),
));
container.register('driverCandidateScoringService', () => new DriverCandidateScoringService());
container.register('adminQrReissueService', (c) => new AdminQrReissueService(
  database.pool,
  c.get('bookingRepository'),
));
container.register('adminDispatchService', (c) => new AdminDispatchService(
  database.pool,
  c.get('bookingRepository'),
  c.get('driverRepository'),
  c.get('bookingStatusService'),
  c.get('commissionSettlementService'),
  c.get('outboxRepository'),
  c.get('outboxProcessor'),
  c.get('driverCandidateScoringService'),
  c.get('adminQrReissueService'),
));
container.register('driverTripFlowService', (c) => new DriverTripFlowService(
  database.pool,
  c.get('bookingRepository'),
  c.get('bookingStatusService'),
  c.get('driverJobService'),
));
container.register('driverQrService', (c) => new DriverQrService(
  database.pool,
  c.get('bookingRepository'),
  c.get('bookingStatusService'),
  c.get('driverJobService'),
));
container.register('notificationRepository', () => new NotificationRepository());
container.register('notificationService', (c) => new NotificationService(
  database.pool,
  c.get('notificationRepository'),
  c.get('userRepository'),
  c.get('bookingRepository'),
  c.get('driverRepository'),
  c.get('bookingService'),
));
container.register('outboxRepository', () => new OutboxRepository(database.pool));
container.register('outboxProcessor', (c) => new OutboxProcessor(
  c.get('outboxRepository'),
  () => c.get('notificationService'),
));
container.register('chatService', (c) => new ChatService(
  database.pool,
  c.get('chatRepository'),
  c.get('bookingRepository'),
  c.get('driverRepository'),
  c.get('userRepository'),
  c.get('outboxRepository'),
  c.get('outboxProcessor'),
));
container.register('flightMonitorRepository', () => new FlightMonitorRepository());
container.register('driverApplicationRepository', () => new DriverApplicationRepository());
container.register('supportInquiryRepository', () => new SupportInquiryRepository());
container.register('adminFlightMonitorService', (c) => new AdminFlightMonitorService(
  database.pool,
  c.get('flightMonitorRepository'),
  c.get('flightService'),
  c.get('bookingRepository'),
  c.get('outboxRepository'),
  c.get('outboxProcessor'),
  {
    syncEnabled: true,
    minSyncIntervalMs: config.external.flightSyncMinIntervalMs,
    delayNotificationDeltaMinutes: config.external.flightDelayNotificationDeltaMinutes,
  },
));
container.register('flightSyncWorker', (c) => new FlightSyncWorker({
  flightMonitorRepository: c.get('flightMonitorRepository'),
  adminFlightMonitorService: c.get('adminFlightMonitorService'),
  config: {
    enabled: config.external.flightSyncEnabled,
    batchSize: config.external.flightSyncBatchSize,
    lookbackHours: config.external.flightSyncLookbackHours,
    lookaheadHours: config.external.flightSyncLookaheadHours,
    maxRetries: config.external.flightSyncMaxRetries,
    retryBaseMs: config.external.flightSyncRetryBaseMs,
  },
}));
container.register('flightSyncSchedulerService', (c) => new FlightSyncSchedulerService(
  c.get('flightSyncWorker'),
  {
    enabled: config.external.flightSyncEnabled,
    intervalMs: config.external.flightSyncIntervalMs,
    batchSize: config.external.flightSyncBatchSize,
  },
  () => c.get('flightService').isProviderConfigured(),
));
container.register('driverApplicationService', (c) => new DriverApplicationService(
  database.pool,
  c.get('driverApplicationRepository'),
  c.get('fileRepository'),
  c.get('userRepository'),
));
container.register('supportInquiryService', (c) => new SupportInquiryService(
  database.pool,
  c.get('supportInquiryRepository'),
));

module.exports = container;
