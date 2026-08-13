const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const PAYMENT_METHODS = require('../constants/paymentMethods');
const COMMISSION_STATUS = require('../constants/commissionStatus');
const BOOKING_STATUS = require('../constants/reservationStatus');
const NOTIFICATION_TYPES = require('../constants/notificationTypes');
const ROLES = require('../constants/roles');
const { generateSecureToken, hashToken } = require('../utils/tokenHash.util');
const {
  extractAirlineCode,
  normalizeFlightNumber,
} = require('../utils/flightNumber.util');
const { randomUUID } = require('node:crypto');
const { EVENTS } = require('../events');
const { emitDriverCallAvailable, emitDriverUrgentCallNew } = require('../socket/realtime');
const {
  evaluateCustomerCancellation,
} = require('../policies/customerBookingCancellation.policy');
const {
  isContactConnectionRequired,
} = require('../policies/bookingDispatchEligibility.policy');
const CONTACT_STATUS = require('../constants/contactStatus');
const {
  getThailandAirportNameTh,
  normalizeAirportIata,
} = require('../constants/thailandAirports.constants');
const logger = require('../utils/logger');

const TRUST_MESSAGE = 'Keep your booking number. You can check driver assignment and trip status on the booking lookup page.';

const GUEST_TOKEN_TTL_DAYS = 90;
const BOARDING_QR_TTL_HOURS = 48;
const DROPOFF_QR_TTL_HOURS = 48;

const BOARDING_QR_ISSUE_STATUSES = new Set([
  BOOKING_STATUS.PENDING,
  BOOKING_STATUS.OPEN,
  BOOKING_STATUS.CONFIRMED,
  BOOKING_STATUS.DRIVER_ASSIGNED,
  BOOKING_STATUS.ON_ROUTE,
  BOOKING_STATUS.DRIVER_ARRIVED,
]);

class BookingService {
  constructor(
    pool,
    bookingRepository,
    bookingNumberService,
    pricingService,
    vehicleRecommendationService,
    vehicleRepository,
    outboxRepository,
    outboxProcessor,
    flightService = null,
    driverRepository = null,
    notificationServiceResolver = null,
    commissionSettlementService = null,
    urgentNegotiationRepository = null,
    placesService = null,
    bookingIdempotencyService = null,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.bookingNumberService = bookingNumberService;
    this.pricingService = pricingService;
    this.vehicleRecommendationService = vehicleRecommendationService;
    this.vehicleRepository = vehicleRepository;
    this.outboxRepository = outboxRepository;
    this.outboxProcessor = outboxProcessor;
    this.flightService = flightService;
    this.driverRepository = driverRepository;
    this.notificationServiceResolver = notificationServiceResolver;
    this.commissionSettlementService = commissionSettlementService;
    this.urgentNegotiationRepository = urgentNegotiationRepository;
    this.placesService = placesService;
    this.bookingIdempotencyService = bookingIdempotencyService;
  }

  buildOpenCallPayload({
    bookingNumber,
    scheduledPickupAt,
    originAddress,
    destinationAddress,
    metadata = null,
    serviceType,
    vehicleType,
    pricing,
    luggage,
  }) {
    const parsedMetadata = this.parseBookingMetadata(metadata);
    const originLocation = parsedMetadata.originLocation ?? {};
    const destinationLocation = parsedMetadata.destinationLocation ?? {};
    return {
      bookingNumber,
      status: BOOKING_STATUS.OPEN,
      scheduledPickupAt,
      origin: originAddress,
      destination: destinationAddress,
      pickupLocation: this.locationDetails({
        name: originLocation.name,
        nameTh: originLocation.nameTh,
        address: originAddress,
      }),
      destinationLocation: this.locationDetails({
        name: destinationLocation.name,
        nameTh: destinationLocation.nameTh,
        address: destinationAddress,
      }),
      serviceType: {
        code: serviceType.code,
        name: serviceType.name,
      },
      vehicleType: {
        code: vehicleType.code,
        name: vehicleType.name,
      },
      amount: Number(pricing.totalAmount ?? pricing.total ?? 0),
      currency: pricing.currency,
      luggage: {
        carriers20Inch: Number(luggage?.carriers20Inch ?? 0),
        carriers24InchPlus: Number(luggage?.carriers24InchPlus ?? 0),
        golfBags: Number(luggage?.golfBags ?? 0),
        specialItems: luggage?.specialItems ?? null,
      },
    };
  }

  async getEligibleDriversForOpenBooking(conn, vehicleTypeId, scheduledPickupAt = null) {
    if (!this.driverRepository) {
      return [];
    }

    const candidates = await this.driverRepository.listEligibleForOpenBooking(
      conn,
      vehicleTypeId,
      { scheduledPickupAt },
    );
    const drivers = [];
    for (const driver of candidates) {
      const blocked = this.commissionSettlementService
        ? await this.commissionSettlementService.driverHasBlockingSettlement(driver.id)
        : false;
      if (!blocked) drivers.push(driver);
    }
    return drivers;
  }

  mapEligibleDriversToTargets(drivers) {
    return drivers.map((driver) => ({
      driverId: driver.id,
      userId: driver.user_id,
    }));
  }

  getNotificationService() {
    return this.notificationServiceResolver ? this.notificationServiceResolver() : null;
  }

  buildDriverNotificationPayload(bookingNumber, payload, targetScreen) {
    return {
      ...payload,
      bookingNumber,
      targetScreen,
    };
  }

  async dispatchOpenCallNotifications({
    drivers,
    bookingId,
    bookingNumber,
    openCallPayload,
    idempotencyKeyPrefix = 'driver-call-open',
  }) {
    const notificationService = this.getNotificationService();
    if (!notificationService || !drivers.length) {
      return;
    }

    const payload = this.buildDriverNotificationPayload(
      bookingNumber,
      openCallPayload,
      'open_calls',
    );
    for (const driver of drivers) {
      try {
        await notificationService.sendDirectNotification({
          recipientUserId: driver.user_id,
          recipientDriverId: driver.id,
          bookingId,
          notificationType: NOTIFICATION_TYPES.DRIVER_CALL_AVAILABLE,
          payload,
          idempotencyKey: `${idempotencyKeyPrefix}:${bookingId}:${driver.id}`,
          eventName: 'driver.call.available',
        });
      } catch (err) {
        logger.warn('Open call notification failed', {
          bookingId,
          driverId: driver.id,
          error: err.message,
        });
      }
    }
  }

  async dispatchUrgentCallNotifications({
    drivers,
    bookingId,
    bookingNumber,
    urgentPayload,
    idempotencyKeyPrefix = 'driver-urgent-call-new',
  }) {
    const notificationService = this.getNotificationService();
    if (!notificationService || !drivers.length) {
      return;
    }

    const payload = this.buildDriverNotificationPayload(
      bookingNumber,
      urgentPayload,
      'urgent_calls',
    );
    for (const driver of drivers) {
      try {
        await notificationService.sendDirectNotification({
          recipientUserId: driver.user_id,
          recipientDriverId: driver.id,
          bookingId,
          notificationType: NOTIFICATION_TYPES.DRIVER_URGENT_CALL_NEW,
          payload,
          idempotencyKey: `${idempotencyKeyPrefix}:${bookingId}:${driver.id}`,
          eventName: 'driver.urgent-call.new',
        });
      } catch (err) {
        logger.warn('Urgent call notification failed', {
          bookingId,
          driverId: driver.id,
          error: err.message,
        });
      }
    }
  }

  async notifyEligibleDriversForOpenBooking(conn, {
    vehicleTypeId,
    scheduledPickupAt = null,
  }) {
    const drivers = await this.getEligibleDriversForOpenBooking(
      conn,
      vehicleTypeId,
      scheduledPickupAt,
    );
    return this.mapEligibleDriversToTargets(drivers);
  }

  buildPricingInput(input) {
    const body = {
      serviceTypeCode: input.serviceTypeCode,
      vehicleTypeCode: input.vehicleTypeCode,
      vehicleCount: input.vehicleCount ?? 1,
      options: input.options ?? {},
      scheduledPickupAt: input.scheduledPickupAt,
    };

    if (input.originAirportIata) body.originAirportIata = input.originAirportIata;
    if (input.destinationRegion) body.destinationRegion = input.destinationRegion;
    if (input.originLocationCode) body.originLocationCode = input.originLocationCode;
    if (input.destinationLocationCode) body.destinationLocationCode = input.destinationLocationCode;

    return body;
  }

  resolvePlaceAddress(place) {
    if (!place) return null;
    if (place.address) return place.address;
    if (place.name) return place.name;
    return null;
  }

  resolveAirportIataCode(airportIata, locationCode) {
    const fromAirportIata = normalizeAirportIata(airportIata);
    if (fromAirportIata && getThailandAirportNameTh(fromAirportIata)) {
      return fromAirportIata;
    }
    const fromLocationCode = normalizeAirportIata(locationCode);
    if (fromLocationCode && getThailandAirportNameTh(fromLocationCode)) {
      return fromLocationCode;
    }
    return null;
  }

  async resolveLocationNameTh({ airportIata, locationCode, placeId }) {
    const mappedIata = this.resolveAirportIataCode(airportIata, locationCode);
    if (mappedIata) {
      return getThailandAirportNameTh(mappedIata);
    }

    const normalizedPlaceId = typeof placeId === 'string' ? placeId.trim() : '';
    if (!normalizedPlaceId || !this.placesService) {
      return null;
    }

    try {
      const details = await this.placesService.details({
        placeId: normalizedPlaceId,
        language: 'th',
      });
      const nameTh = typeof details?.name === 'string' ? details.name.trim() : '';
      return nameTh || null;
    } catch (err) {
      logger.warn('Failed to resolve Thai place name from Google Places', {
        placeId: normalizedPlaceId,
        error: err instanceof Error ? err.message : String(err),
        errorCode: err?.errorCode ?? null,
      });
      return null;
    }
  }

  async buildLocationMetadata({
    name,
    airportIata,
    locationCode,
    placeId,
  }) {
    const normalizedName = typeof name === 'string' ? name.trim() : '';
    const nameTh = await this.resolveLocationNameTh({ airportIata, locationCode, placeId });

    const locationMetadata = {};
    if (normalizedName) {
      locationMetadata.name = normalizedName;
    }
    if (nameTh) {
      locationMetadata.nameTh = nameTh;
    }
    return Object.keys(locationMetadata).length ? locationMetadata : null;
  }

  parseBookingMetadata(metadata) {
    if (!metadata) return {};
    if (typeof metadata === 'object') return metadata;
    try {
      const parsed = JSON.parse(metadata);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (_) {
      return {};
    }
  }

  isContactDispatchCompleted(metadata) {
    return this.parseBookingMetadata(metadata).contactDispatchCompleted === true;
  }

  needsContactDispatchRetry(bookingRow) {
    if (!isContactConnectionRequired()) return false;
    if ((bookingRow?.contact_status ?? CONTACT_STATUS.VERIFIED) !== CONTACT_STATUS.VERIFIED) {
      return false;
    }
    if (bookingRow?.status !== BOOKING_STATUS.OPEN) {
      return false;
    }
    return !this.isContactDispatchCompleted(bookingRow.metadata);
  }

  async markContactDispatchCompleted(conn, bookingId, existingMetadata) {
    const metadata = this.parseBookingMetadata(existingMetadata);
    metadata.contactDispatchCompleted = true;
    await this.bookingRepository.updateBookingFields(conn, bookingId, { metadata });
  }

  location(value) {
    if (value == null) return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  locationDetails({ name, nameTh, address, placeId, latitude, longitude }) {
    const normalizedName = typeof name === 'string' && name.trim() ? name.trim() : null;
    const normalizedNameTh = typeof nameTh === 'string' && nameTh.trim() ? nameTh.trim() : null;
    const normalizedAddress =
      typeof address === 'string' && address.trim() ? address.trim() : null;
    const displayName =
      normalizedName && normalizedName !== normalizedAddress ? normalizedName : null;
    const location = {
      name: displayName,
      address: normalizedAddress,
      latitude: this.location(latitude),
      longitude: this.location(longitude),
      placeId: typeof placeId === 'string' && placeId.trim() ? placeId.trim() : null,
    };
    if (normalizedNameTh) {
      location.nameTh = normalizedNameTh;
    }
    return location;
  }

  addHours(date, hours) {
    const result = new Date(date);
    result.setHours(result.getHours() + hours);
    return result;
  }

  addDays(date, days) {
    const result = new Date(date);
    result.setDate(result.getDate() + days);
    return result;
  }

  formatDateTime(date) {
    return date.toISOString().slice(0, 19).replace('T', ' ');
  }

  formatThailandDateTime(value) {
    const date = new Date(value);
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: 'Asia/Bangkok',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
      hour12: false,
    }).formatToParts(date);
    const part = (type) => parts.find((item) => item.type === type)?.value;
    const hour = part('hour') === '24' ? '00' : part('hour');
    return `${part('year')}-${part('month')}-${part('day')} ${hour}:${part('minute')}:${part('second')}`;
  }

  extractAirlineCode(flightNumber) {
    return extractAirlineCode(flightNumber);
  }

  resolveTransferFlight(input) {
    const raw = input.transfer?.flightNumber;
    if (!raw || !String(raw).trim()) {
      return { flightNumber: null, airlineCode: null, flightDate: null };
    }
    if (!this.flightService) {
      const flightNumber = normalizeFlightNumber(raw);
      return {
        flightNumber,
        airlineCode: this.extractAirlineCode(flightNumber),
        flightDate: input.scheduledPickupAt ? String(input.scheduledPickupAt).slice(0, 10) : null,
      };
    }
    const flightNumber = this.flightService.normalizeFlightNumber(raw);
    return {
      flightNumber,
      airlineCode: this.extractAirlineCode(flightNumber),
      flightDate: input.scheduledPickupAt ? String(input.scheduledPickupAt).slice(0, 10) : null,
    };
  }

  async resolveTransferAirport(conn, input) {
    const iata = input.transfer?.airportIata
      || input.originAirportIata
      || input.destinationAirportIata;

    if (!iata) {
      return { airportId: null, airportCodeCustom: null };
    }

    const airport = await this.bookingRepository.findAirportByIata(conn, iata.toUpperCase());
    return {
      airportId: airport?.id ?? null,
      airportCodeCustom: airport ? null : iata.toUpperCase(),
    };
  }

  buildCreateBookingResult(booking, { guestAccessToken = null, boardingQrToken = null } = {}) {
    const cancellation = evaluateCustomerCancellation({
      status: booking.status,
      scheduledPickupAt: booking.scheduled_pickup_at,
    });
    return {
      bookingId: booking.id,
      bookingNumber: booking.booking_number,
      status: booking.status,
      paymentMethod: booking.payment_method,
      paymentStatus: booking.payment_status,
      totalAmount: Number(booking.total_amount),
      currency: booking.currency,
      guestAccessToken,
      boardingQrToken,
      trustMessage: TRUST_MESSAGE,
      isUrgentRequest: Boolean(booking.is_urgent_request),
      canCancel: cancellation.canCancel,
      cancellationDeadline: cancellation.cancellationDeadline,
      cancellationBlockedReason: cancellation.cancellationBlockedReason,
      contactStatus: booking.contact_status ?? CONTACT_STATUS.VERIFIED,
      contactConnectionRequired: isContactConnectionRequired(),
    };
  }

  shouldDeferDispatchUntilContactVerified() {
    return isContactConnectionRequired();
  }

  resolveInitialContactStatus() {
    return this.shouldDeferDispatchUntilContactVerified()
      ? CONTACT_STATUS.PENDING
      : CONTACT_STATUS.VERIFIED;
  }

  async dispatchAfterContactVerified(bookingRow) {
    if (!bookingRow?.id) return false;
    if ((bookingRow.contact_status ?? CONTACT_STATUS.VERIFIED) !== CONTACT_STATUS.VERIFIED) {
      return false;
    }

    const conn = await this.pool.getConnection();
    try {
      const booking = await this.bookingRepository.findById(bookingRow.id, conn);
      if (!booking || booking.status !== BOOKING_STATUS.OPEN) {
        return false;
      }

      const fullBooking = await this.bookingRepository.findOpenDriverCallByBookingId(
        conn,
        booking.id,
      );
      if (!fullBooking) {
        return false;
      }

      if (this.isContactDispatchCompleted(fullBooking.metadata)) {
        return false;
      }

      const eligibleDrivers = await this.getEligibleDriversForOpenBooking(
        conn,
        fullBooking.vehicle_type_id,
        fullBooking.scheduled_pickup_at,
      );

      const pricing = { totalAmount: fullBooking.total_amount, currency: fullBooking.currency };
      const metadata = this.parseBookingMetadata(fullBooking.metadata);
      const openCallPayload = this.buildOpenCallPayload({
        bookingNumber: fullBooking.booking_number,
        scheduledPickupAt: fullBooking.scheduled_pickup_at,
        originAddress: fullBooking.origin_address,
        destinationAddress: fullBooking.destination_address,
        metadata,
        serviceType: {
          code: fullBooking.service_type_code,
          name: fullBooking.service_type_name,
        },
        vehicleType: {
          code: fullBooking.vehicle_type_code,
          name: fullBooking.vehicle_type_name,
        },
        pricing,
        luggage: {
          carriers20Inch: fullBooking.carriers_20_inch ?? 0,
          carriers24InchPlus: fullBooking.carriers_24_inch_plus ?? 0,
          golfBags: fullBooking.golf_bags ?? 0,
          specialItems: fullBooking.special_items ?? null,
        },
      });

      if (fullBooking.is_urgent_request) {
        const urgentPayload = {
          bookingNumber: fullBooking.booking_number,
          negotiationId: fullBooking.urgent_negotiation_id,
          attemptCount: 0,
          minRequiredEtaMinutes: fullBooking.urgent_min_required_eta_minutes ?? null,
        };
        emitDriverUrgentCallNew(urgentPayload);
        await this.dispatchUrgentCallNotifications({
          drivers: eligibleDrivers,
          bookingId: booking.id,
          bookingNumber: fullBooking.booking_number,
          urgentPayload,
        });
      } else {
        const openCallTargets = this.mapEligibleDriversToTargets(eligibleDrivers);
        await this.dispatchOpenCallNotifications({
          drivers: eligibleDrivers,
          bookingId: booking.id,
          bookingNumber: fullBooking.booking_number,
          openCallPayload,
        });
        for (const target of openCallTargets) {
          emitDriverCallAvailable(target.userId, openCallPayload);
        }
      }

      await this.markContactDispatchCompleted(conn, booking.id, fullBooking.metadata);
      return true;
    } finally {
      conn.release();
    }
  }

  async createBooking(input, authUser, options = {}) {
    const { idempotencyKey = null } = options;
    const requestHash = idempotencyKey
      ? this.bookingIdempotencyService?.computeRequestHash(input)
      : null;

    const conn = await this.pool.getConnection();

    const guestAccessToken = authUser ? null : generateSecureToken();
    const boardingQrToken = generateSecureToken();

    try {
      await conn.beginTransaction();

      if (idempotencyKey && this.bookingIdempotencyService) {
        const idempotency = await this.bookingIdempotencyService.begin(
          conn,
          idempotencyKey,
          requestHash,
        );
        if (idempotency.action === 'replay') {
          const booking = await this.bookingRepository.findById(idempotency.bookingId, conn);
          if (!booking) {
            throw new AppError('Booking not found', {
              statusCode: HTTP_STATUS.NOT_FOUND,
              errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
            });
          }
          const response = this.buildCreateBookingResult(booking, {
            guestAccessToken: idempotency.replaySecrets?.guestAccessToken ?? null,
            boardingQrToken: idempotency.replaySecrets?.boardingQrToken ?? null,
          });
          await conn.commit();
          return {
            data: response,
            replayed: true,
            responseStatus: idempotency.responseStatus,
          };
        }
      }

      const pricingInput = this.buildPricingInput(input);
      const pricing = await this.pricingService.calculate(pricingInput);
      const serviceType = await this.pricingService.resolveServiceType(input.serviceTypeCode);

      const vehicleType = await this.vehicleRepository.findTypeByCode(input.vehicleTypeCode);
      if (!vehicleType) {
        throw new AppError('Vehicle type not found', {
          statusCode: HTTP_STATUS.BAD_REQUEST,
          errorCode: ERROR_CODES.VALIDATION_ERROR,
        });
      }

      const recommendation = await this.vehicleRecommendationService.recommend({
        adults: input.passengers.adults,
        children: input.passengers.children ?? 0,
        infants: input.passengers.infants ?? 0,
        luggage20: input.luggage?.carriers20Inch ?? 0,
        luggage24: input.luggage?.carriers24InchPlus ?? 0,
        golfBags: input.luggage?.golfBags ?? 0,
        specialLuggageCount: input.luggage?.specialLuggageCount ?? 0,
      });

      let recommendedVehicleTypeId = null;
      if (recommendation.recommendedVehicle) {
        const recommendedType = await this.vehicleRepository.findTypeByCode(
          recommendation.recommendedVehicle,
        );
        recommendedVehicleTypeId = recommendedType?.id ?? null;
      }

      const bookingNumber = await this.bookingNumberService.generateNext(conn);
      const customerUserId = authUser?.id ?? null;
      const createdBy = customerUserId;

      const scheduledPickupAtIso = input.scheduledPickupAt;
      const scheduledPickupAt = this.formatThailandDateTime(scheduledPickupAtIso);
      const now = new Date();
      const boardingExpires = scheduledPickupAt
        ? this.addHours(new Date(scheduledPickupAtIso), BOARDING_QR_TTL_HOURS)
        : this.addDays(now, 30);

      const metadata = {};
      if (input.customer?.messengerType) {
        metadata.messengerType = input.customer.messengerType;
      }
      if (input.customer?.messengerId) {
        metadata.messengerId = input.customer.messengerId;
      }

      const origin = input.origin ?? {};
      const destination = input.destination ?? {};
      const [originLocationMetadata, destinationLocationMetadata] = await Promise.all([
        this.buildLocationMetadata({
          name: origin.name,
          airportIata: input.originAirportIata,
          locationCode: input.originLocationCode,
          placeId: origin.placeId,
        }),
        this.buildLocationMetadata({
          name: destination.name,
          airportIata: input.destinationAirportIata,
          locationCode: input.destinationLocationCode,
          placeId: destination.placeId,
        }),
      ]);
      if (originLocationMetadata) {
        metadata.originLocation = originLocationMetadata;
      }
      if (destinationLocationMetadata) {
        metadata.destinationLocation = destinationLocationMetadata;
      }

      const originAddress = this.resolvePlaceAddress(origin);
      const destinationAddress = this.resolvePlaceAddress(destination);

      const bookingMode = String(input.bookingMode ?? 'STANDARD').trim().toUpperCase();
      const isUrgentRequest = bookingMode === 'URGENT';

      const bookingId = await this.bookingRepository.insertBooking(conn, {
        bookingNumber,
        status: BOOKING_STATUS.OPEN,
        contactStatus: this.resolveInitialContactStatus(),
        serviceTypeId: serviceType.id,
        originAddress,
        originPlaceId: origin.placeId ?? null,
        originLat: origin.lat ?? null,
        originLng: origin.lng ?? null,
        destinationAddress,
        destinationPlaceId: destination.placeId ?? null,
        destinationLat: destination.lat ?? null,
        destinationLng: destination.lng ?? null,
        scheduledPickupAt,
        vehicleTypeId: vehicleType.id,
        recommendedVehicleTypeId,
        vehicleCount: input.vehicleCount ?? 1,
        routeId: pricing.routeId,
        totalAmount: 0,
        currency: pricing.currency,
        paymentStatus: 'UNPAID',
        paymentMethod: PAYMENT_METHODS.PAY_DRIVER,
        commissionStatus: COMMISSION_STATUS.NOT_DUE_YET,
        customerUserId,
        customerName: input.customer.name,
        nameSignText: input.options?.nameSign ? input.options.nameSignText : null,
        customerEmail: input.customer?.email ?? null,
        customerPhone: input.customer.phone,
        customerCountryCode: input.customer.countryCode?.trim() || null,
        specialRequests: input.additionalRequests ?? input.specialRequests ?? null,
        metadata: Object.keys(metadata).length ? metadata : null,
        boardingQrTokenHash: hashToken(boardingQrToken),
        boardingQrExpiresAt: this.formatDateTime(boardingExpires),
        isUrgentRequest,
        createdBy,
        updatedBy: createdBy,
      });

      await this.bookingRepository.insertPassengers(conn, bookingId, {
        adults: input.passengers.adults,
        children: input.passengers.children ?? 0,
        infants: input.passengers.infants ?? 0,
      });

      const specialItems = input.luggage?.specialItems
        ?? (input.luggage?.specialLuggageCount
          ? String(input.luggage.specialLuggageCount)
          : null);

      await this.bookingRepository.insertLuggage(conn, bookingId, {
        carriers20Inch: input.luggage?.carriers20Inch ?? 0,
        carriers24InchPlus: input.luggage?.carriers24InchPlus ?? 0,
        golfBags: input.luggage?.golfBags ?? 0,
        specialItems,
      });

      const airportInfo = await this.resolveTransferAirport(conn, input);
      const flightInfo = this.resolveTransferFlight(input);
      await this.bookingRepository.insertTransferDetails(conn, bookingId, {
        airportId: airportInfo.airportId,
        airportCodeCustom: airportInfo.airportCodeCustom,
        flightNumber: flightInfo.flightNumber,
        airlineCode: flightInfo.airlineCode,
        flightDate: flightInfo.flightDate,
        golfCourseId: input.transfer?.golfCourseId ?? null,
        golfRegion: input.transfer?.golfRegion ?? null,
        driverIncluded: Boolean(input.transfer?.driverIncluded),
      });

      for (const item of pricing.chargeItems) {
        await this.bookingRepository.insertChargeItem(conn, bookingId, {
          chargeType: item.chargeType,
          description: item.description,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          amount: item.amount,
          referenceType: item.referenceType ?? null,
          referenceId: item.referenceId ?? null,
        }, createdBy);
      }

      await this.bookingRepository.insertStatusLog(conn, bookingId, {
        fromStatus: null,
        toStatus: BOOKING_STATUS.OPEN,
        changedByUserId: customerUserId,
        changedByRole: customerUserId ? 'CUSTOMER' : 'SYSTEM',
        reason: isUrgentRequest ? 'BOOKING_CREATED_URGENT_REQUEST' : 'BOOKING_CREATED_OPEN_CALL',
      });

      await this.bookingRepository.insertActivityLog(conn, bookingId, {
        activityType: isUrgentRequest ? 'URGENT_BOOKING_CREATED' : 'BOOKING_CREATED',
        actorUserId: customerUserId,
        actorRole: customerUserId ? 'CUSTOMER' : 'SYSTEM',
        description: isUrgentRequest ? 'Urgent booking created' : 'Booking created',
        payload: {
          bookingNumber,
          paymentMethod: PAYMENT_METHODS.PAY_DRIVER,
          bookingMode,
        },
      });

      if (guestAccessToken) {
        const guestExpires = this.addDays(now, GUEST_TOKEN_TTL_DAYS);
        await this.bookingRepository.insertGuestToken(
          conn,
          bookingId,
          hashToken(guestAccessToken),
          this.formatDateTime(guestExpires),
        );
      }

      let outboxId = null;
      let openCallTargets = [];
      let eligibleDrivers = [];
      let urgentNegotiationId = null;
      const openCallPayload = this.buildOpenCallPayload({
        bookingNumber,
        scheduledPickupAt,
        originAddress,
        destinationAddress,
        metadata: Object.keys(metadata).length ? metadata : null,
        serviceType,
        vehicleType,
        pricing,
        luggage: {
          carriers20Inch: input.luggage?.carriers20Inch ?? 0,
          carriers24InchPlus: input.luggage?.carriers24InchPlus ?? 0,
          golfBags: input.luggage?.golfBags ?? 0,
          specialItems,
        },
      });

      eligibleDrivers = await this.getEligibleDriversForOpenBooking(
        conn,
        vehicleType.id,
        scheduledPickupAt,
      );
      if (isUrgentRequest) {
        if (!this.urgentNegotiationRepository) {
          throw new AppError('Urgent negotiation service is unavailable', {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.URGENT_NEGOTIATION_NOT_FOUND,
          });
        }
        urgentNegotiationId = await this.urgentNegotiationRepository.insertNegotiation(conn, {
          bookingId,
        });
        await this.bookingRepository.updateUrgentNegotiationId(
          conn,
          bookingId,
          urgentNegotiationId,
        );
      } else {
        openCallTargets = this.mapEligibleDriversToTargets(eligibleDrivers);
      }

      if (this.outboxRepository) {
        outboxId = await this.outboxRepository.insertNotificationEvent(conn, {
          aggregateId: bookingId,
          eventType: EVENTS.BOOKING_CREATED,
          payload: {
            eventId: randomUUID(),
            eventName: EVENTS.BOOKING_CREATED,
            bookingId,
            bookingNumber,
            customerUserId,
          },
        });
      }

      const booking = await this.bookingRepository.findById(bookingId, conn);
      const response = this.buildCreateBookingResult(booking, {
        guestAccessToken,
        boardingQrToken,
      });

      if (idempotencyKey && this.bookingIdempotencyService) {
        await this.bookingIdempotencyService.complete(conn, {
          idempotencyKey,
          bookingId: booking.id,
          responseStatus: HTTP_STATUS.CREATED,
          responsePayload: this.bookingIdempotencyService.buildReplaySecrets({
            guestAccessToken,
            boardingQrToken,
          }),
        });
      }

      await conn.commit();

      if (this.outboxProcessor && outboxId) {
        await this.outboxProcessor.dispatchOutboxIds([outboxId]);
      }
      const deferDispatch = this.shouldDeferDispatchUntilContactVerified();
      if (!deferDispatch) {
        if (isUrgentRequest) {
          const urgentPayload = {
            bookingNumber,
            negotiationId: urgentNegotiationId,
            attemptCount: 0,
            minRequiredEtaMinutes: null,
          };
          emitDriverUrgentCallNew(urgentPayload);
          await this.dispatchUrgentCallNotifications({
            drivers: eligibleDrivers,
            bookingId,
            bookingNumber,
            urgentPayload,
          });
        } else {
          await this.dispatchOpenCallNotifications({
            drivers: eligibleDrivers,
            bookingId,
            bookingNumber,
            openCallPayload,
          });
          for (const target of openCallTargets) {
            emitDriverCallAvailable(target.userId, openCallPayload);
          }
        }
      }

      return {
        data: response,
        replayed: false,
        responseStatus: HTTP_STATUS.CREATED,
      };
    } catch (err) {
      if (idempotencyKey && this.bookingIdempotencyService) {
        try {
          await this.bookingIdempotencyService.releasePending(conn, idempotencyKey);
        } catch (releaseErr) {
          logger.warn('Failed to release pending idempotency key', {
            idempotencyKey,
            error: releaseErr?.message,
          });
        }
      }
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  validateBookingNumber(bookingNumber) {
    const value = String(bookingNumber ?? '').trim().toUpperCase();
    if (!/^TX\d{12}$/.test(value)) {
      throw new AppError('Invalid booking number', {
        statusCode: HTTP_STATUS.BAD_REQUEST,
        errorCode: ERROR_CODES.VALIDATION_ERROR,
      });
    }
    return value;
  }

  async assertCustomerOrGuestAccess(conn, booking, authUser, guestAccessToken) {
    if (
      authUser?.role === ROLES.CUSTOMER
      && booking.customer_user_id
      && booking.customer_user_id === authUser.id
    ) {
      return;
    }

    const token = String(guestAccessToken ?? '').trim();
    if (!token) {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    }

    const guestToken = await this.bookingRepository.findActiveGuestTokenForBooking(
      conn,
      booking.id,
      hashToken(token),
    );
    if (!guestToken) {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    }
  }

  async issueDropoffQr(bookingNumber, input = {}, authUser = null) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    const conn = await this.pool.getConnection();
    const rawDropoffToken = generateSecureToken();
    const expiresAt = this.formatDateTime(
      this.addHours(new Date(), DROPOFF_QR_TTL_HOURS),
    );
    let booking;

    try {
      await conn.beginTransaction();

      booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        normalizedBookingNumber,
      );

      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      await this.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        input.guestAccessToken,
      );

      if (booking.status !== BOOKING_STATUS.PICKED_UP) {
        throw new AppError(
          'Dropoff QR can only be issued after pickup and before completion',
          {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
            errors: [{
              requiredStatus: BOOKING_STATUS.PICKED_UP,
              currentStatus: booking.status,
            }],
          },
        );
      }

      await this.bookingRepository.setDropoffQr(
        conn,
        booking.id,
        hashToken(rawDropoffToken),
        expiresAt,
      );

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    return {
      bookingNumber: booking.booking_number,
      status: booking.status,
      dropoffQrToken: rawDropoffToken,
      dropoffQrExpiresAt: expiresAt,
    };
  }

  async issueBoardingQr(bookingNumber, input = {}, authUser = null) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    const conn = await this.pool.getConnection();
    const rawBoardingToken = generateSecureToken();
    const expiresAt = this.formatDateTime(
      this.addHours(new Date(), BOARDING_QR_TTL_HOURS),
    );
    let booking;

    try {
      await conn.beginTransaction();

      booking = await this.bookingRepository.findByBookingNumberForUpdate(
        conn,
        normalizedBookingNumber,
      );

      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      await this.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        input.guestAccessToken,
      );

      if (
        !BOARDING_QR_ISSUE_STATUSES.has(booking.status)
        || booking.boarding_qr_used_at
      ) {
        throw new AppError('Boarding QR can only be issued before pickup', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
          errors: [{ currentStatus: booking.status }],
        });
      }

      const hasActiveQr = Boolean(
        booking.boarding_qr_token_hash
        && booking.boarding_qr_expires_at
        && new Date(booking.boarding_qr_expires_at).getTime() > Date.now(),
      );
      if (hasActiveQr && !input.forceReissue) {
        throw new AppError('Boarding QR is already active for this booking', {
          statusCode: HTTP_STATUS.CONFLICT,
          errorCode: ERROR_CODES.INVALID_STATUS_TRANSITION,
        });
      }

      await this.bookingRepository.setBoardingQr(
        conn,
        booking.id,
        hashToken(rawBoardingToken),
        expiresAt,
      );

      await conn.commit();
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    return {
      bookingNumber: booking.booking_number,
      status: booking.status,
      boardingQrToken: rawBoardingToken,
      boardingQrExpiresAt: expiresAt,
    };
  }
}

module.exports = BookingService;
