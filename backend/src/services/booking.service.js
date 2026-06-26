const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const PAYMENT_METHODS = require('../constants/paymentMethods');
const COMMISSION_STATUS = require('../constants/commissionStatus');
const { generateSecureToken, hashToken } = require('../utils/tokenHash.util');

const TRUST_MESSAGE = 'Your booking has been received. Please show your boarding QR to the driver when you get in. After pickup, a new drop-off QR will be generated automatically.';

const GUEST_TOKEN_TTL_DAYS = 90;
const BOARDING_QR_TTL_HOURS = 48;

class BookingService {
  constructor(
    pool,
    bookingRepository,
    chatRepository,
    bookingNumberService,
    pricingService,
    vehicleRecommendationService,
    vehicleRepository,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.chatRepository = chatRepository;
    this.bookingNumberService = bookingNumberService;
    this.pricingService = pricingService;
    this.vehicleRecommendationService = vehicleRecommendationService;
    this.vehicleRepository = vehicleRepository;
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

  async createBooking(input, authUser) {
    const conn = await this.pool.getConnection();

    const guestAccessToken = authUser ? null : generateSecureToken();
    const boardingQrToken = generateSecureToken();

    try {
      await conn.beginTransaction();

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

      const scheduledPickupAt = input.scheduledPickupAt ?? null;
      const now = new Date();
      const boardingExpires = scheduledPickupAt
        ? this.addHours(new Date(scheduledPickupAt), BOARDING_QR_TTL_HOURS)
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

      const bookingId = await this.bookingRepository.insertBooking(conn, {
        bookingNumber,
        status: 'PENDING',
        serviceTypeId: serviceType.id,
        originAddress: this.resolvePlaceAddress(origin),
        originPlaceId: origin.placeId ?? null,
        originLat: origin.lat ?? null,
        originLng: origin.lng ?? null,
        destinationAddress: this.resolvePlaceAddress(destination),
        destinationPlaceId: destination.placeId ?? null,
        destinationLat: destination.lat ?? null,
        destinationLng: destination.lng ?? null,
        scheduledPickupAt,
        vehicleTypeId: vehicleType.id,
        recommendedVehicleTypeId,
        vehicleCount: input.vehicleCount ?? 1,
        routeId: pricing.routeId,
        currency: pricing.currency,
        paymentStatus: 'UNPAID',
        paymentMethod: PAYMENT_METHODS.PAY_DRIVER,
        commissionStatus: COMMISSION_STATUS.NOT_DUE_YET,
        customerUserId,
        customerName: input.customer.name,
        customerEmail: input.customer.email,
        customerPhone: input.customer.phone,
        customerCountryCode: input.customer.countryCode
          ? input.customer.countryCode.toUpperCase()
          : null,
        specialRequests: input.additionalRequests ?? input.specialRequests ?? null,
        metadata: Object.keys(metadata).length ? metadata : null,
        boardingQrTokenHash: hashToken(boardingQrToken),
        boardingQrExpiresAt: this.formatDateTime(boardingExpires),
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
      await this.bookingRepository.insertTransferDetails(conn, bookingId, {
        airportId: airportInfo.airportId,
        airportCodeCustom: airportInfo.airportCodeCustom,
        flightNumber: input.transfer?.flightNumber ?? null,
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
        toStatus: 'PENDING',
        changedByUserId: customerUserId,
        changedByRole: customerUserId ? 'CUSTOMER' : 'SYSTEM',
        reason: 'BOOKING_CREATED',
      });

      await this.bookingRepository.insertActivityLog(conn, bookingId, {
        activityType: 'BOOKING_CREATED',
        actorUserId: customerUserId,
        actorRole: customerUserId ? 'CUSTOMER' : 'SYSTEM',
        description: 'Booking created',
        payload: { bookingNumber, paymentMethod: PAYMENT_METHODS.PAY_DRIVER },
      });

      const roomCode = `CHAT-${bookingNumber}`;
      const chatRoomId = await this.chatRepository.insertRoom(conn, bookingId, roomCode);
      await this.chatRepository.insertParticipant(conn, chatRoomId, {
        userId: customerUserId,
        participantRole: 'CUSTOMER',
        displayName: input.customer.name,
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

      await conn.commit();

      const booking = await this.bookingRepository.findById(bookingId);

      return {
        bookingNumber: booking.booking_number,
        status: booking.status,
        paymentMethod: booking.payment_method,
        paymentStatus: booking.payment_status,
        totalAmount: Number(booking.total_amount),
        currency: booking.currency,
        guestAccessToken,
        chatRoomCode: roomCode,
        boardingQrToken,
        trustMessage: TRUST_MESSAGE,
      };
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = BookingService;
