const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const { parseStoredTags } = require('../constants/reviewTags');
const { generateSecureToken, hashToken } = require('../utils/tokenHash.util');
const { isBookingReviewEligible } = require('../utils/reviewEligibility.util');
const GuestVehiclePhotoService = require('./guestVehiclePhoto.service');
const {
  evaluateCustomerCancellation,
} = require('../policies/customerBookingCancellation.policy');

const LOOKUP_GUEST_TOKEN_TTL_HOURS = 24;
const CUSTOMER_TRACKING_STATUSES = new Set([
  BOOKING_STATUS.DRIVER_ASSIGNED,
  BOOKING_STATUS.ON_ROUTE,
  BOOKING_STATUS.DRIVER_ARRIVED,
  BOOKING_STATUS.PICKED_UP,
]);

class GuestBookingLookupService {
  constructor(pool, bookingRepository, guestVehiclePhotoService = null, reviewRepository = null) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.guestVehiclePhotoService = guestVehiclePhotoService
      ?? new GuestVehiclePhotoService(bookingRepository);
    this.reviewRepository = reviewRepository;
  }

  normalizePhone(value) {
    return String(value ?? '').replace(/\D/g, '');
  }

  addHours(date, hours) {
    const result = new Date(date);
    result.setHours(result.getHours() + hours);
    return result;
  }

  formatDateTime(date) {
    return date.toISOString().slice(0, 19).replace('T', ' ');
  }

  notFound() {
    return new AppError('Booking not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
    });
  }

  formatThailandIso(value) {
    if (!value) return null;
    return `${String(value).replace(' ', 'T')}+07:00`;
  }

  formatUtcIso(value) {
    if (!value) return null;
    return `${String(value).replace(' ', 'T')}Z`;
  }

  boolean(value) {
    return value === true || value === 1 || value === '1';
  }

  isReviewEligible(row) {
    return isBookingReviewEligible(row);
  }

  mapGuestReviewState(row, review) {
    if (!this.isReviewEligible(row)) {
      return null;
    }
    if (!review) {
      return {
        eligible: true,
        submitted: false,
        rating: null,
        tags: [],
        comment: null,
        createdAt: null,
      };
    }
    return {
      eligible: true,
      submitted: true,
      rating: review.rating,
      tags: parseStoredTags(review.tags_json),
      comment: review.comment ?? null,
      createdAt: review.created_at ?? null,
    };
  }

  mapBooking(row, guestAccessToken, guestAccessExpiresAt, review = null) {
    const adults = Number(row.adults ?? 0);
    const children = Number(row.children ?? 0);
    const infants = Number(row.infants ?? 0);
    const vehiclePhotoUrl = this.guestVehiclePhotoService.mapVehiclePhotoUrl(row);
    const hasVehicleDetails = row.assigned_vehicle_plate
      || row.assigned_vehicle_type_code
      || row.assigned_vehicle_type_name;
    const assignedDriver = row.driver_name
      ? {
        name: row.driver_name,
        phone: row.driver_phone ?? null,
        vehicle: hasVehicleDetails || vehiclePhotoUrl
          ? {
            typeCode: row.assigned_vehicle_type_code ?? null,
            typeName: row.assigned_vehicle_type_name ?? null,
            plateNumber: row.assigned_vehicle_plate ?? null,
            modelName: row.assigned_vehicle_model ?? null,
            color: row.assigned_vehicle_color ?? null,
            vehiclePhotoUrl,
          }
          : null,
      }
      : null;
    const terminalStatus = [
      BOOKING_STATUS.COMPLETED,
      BOOKING_STATUS.CANCELLED,
      BOOKING_STATUS.NO_SHOW,
    ].includes(row.status);
    const boardingQrRecoverable = [
      BOOKING_STATUS.PENDING,
      BOOKING_STATUS.OPEN,
      BOOKING_STATUS.CONFIRMED,
      BOOKING_STATUS.DRIVER_ASSIGNED,
      BOOKING_STATUS.ON_ROUTE,
      BOOKING_STATUS.DRIVER_ARRIVED,
    ].includes(row.status) && !row.boarding_qr_used_at;

    const reviewEligible = this.isReviewEligible(row);
    const reviewSubmitted = Boolean(review);
    const canReview = reviewEligible && !reviewSubmitted;
    const cancellation = evaluateCustomerCancellation({
      status: row.status,
      scheduledPickupAt: row.scheduled_pickup_at_text ?? row.scheduled_pickup_at,
    });
    const reassignmentInProgress = Boolean(row.has_driver_release_history)
      && !assignedDriver
      && [
        BOOKING_STATUS.PENDING,
        BOOKING_STATUS.OPEN,
        BOOKING_STATUS.CONFIRMED,
      ].includes(row.status);

    return {
      bookingId: row.id,
      bookingNumber: row.booking_number,
      status: row.status,
      reassignmentInProgress,
      canReview,
      canCancel: cancellation.canCancel,
      cancellationDeadline: cancellation.cancellationDeadline,
      cancellationBlockedReason: cancellation.cancellationBlockedReason,
      scheduledPickupAt: this.formatThailandIso(row.scheduled_pickup_at_text),
      serviceType: {
        code: row.service_type_code,
        name: row.service_type_name,
      },
      route: {
        origin: {
          code: row.origin_location_code ?? null,
          address: row.origin_address,
        },
        destination: {
          code: row.destination_location_code ?? null,
          address: row.destination_address,
        },
      },
      options: {
        nameSignRequested: this.boolean(row.name_sign_requested),
      },
      vehicle: {
        typeCode: row.vehicle_type_code,
        typeName: row.vehicle_type_name,
        count: Number(row.vehicle_count ?? 1),
      },
      passengers: {
        adults,
        children,
        infants,
        total: adults + children + infants,
      },
      luggage: {
        carriers20Inch: Number(row.carriers_20_inch ?? 0),
        carriers24InchPlus: Number(row.carriers_24_inch_plus ?? 0),
        golfBags: Number(row.golf_bags ?? 0),
        specialItems: row.special_items ?? null,
      },
      flight: {
        flightNumber: row.flight_number ?? null,
      },
      pricing: {
        totalAmount: Number(row.total_amount ?? 0),
        currency: row.currency,
        paymentMethod: row.payment_method,
        paymentStatus: row.payment_status,
      },
      assignedDriver,
      capabilities: {
        chatAvailable: Boolean(assignedDriver) && !terminalStatus,
        notificationsAvailable: true,
        dropoffQrIssueAvailable: row.status === BOOKING_STATUS.PICKED_UP,
        reviewAvailable: canReview,
        trackingAvailable: CUSTOMER_TRACKING_STATUSES.has(row.status),
        boardingQrRecoverable,
        boardingQrPreviouslyIssued: Boolean(row.boarding_qr_token_hash) && !terminalStatus,
        cancelAvailable: cancellation.canCancel,
      },
      review: this.mapGuestReviewState(row, review),
      guestAccess: {
        token: guestAccessToken,
        expiresAt: this.formatUtcIso(guestAccessExpiresAt),
      },
    };
  }

  async lookup(input) {
    const bookingNumber = String(input.bookingNumber).trim().toUpperCase();
    const phone = this.normalizePhone(input.phone);
    if (!phone) {
      throw this.notFound();
    }

    const conn = await this.pool.getConnection();
    const guestAccessToken = generateSecureToken();
    const expiresAt = this.formatDateTime(
      this.addHours(new Date(), LOOKUP_GUEST_TOKEN_TTL_HOURS),
    );

    try {
      await conn.beginTransaction();

      const booking = await this.bookingRepository.findGuestLookupBookingByNumber(
        conn,
        bookingNumber,
      );
      const storedPhone = this.normalizePhone(booking?.customer_phone);
      if (!booking || storedPhone !== phone) {
        throw this.notFound();
      }

      await this.bookingRepository.insertGuestToken(
        conn,
        booking.id,
        hashToken(guestAccessToken),
        expiresAt,
      );

      await conn.commit();

      const review = this.reviewRepository
        ? await this.reviewRepository.findByBookingId(booking.id)
        : null;

      return this.mapBooking(booking, guestAccessToken, expiresAt, review);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = GuestBookingLookupService;
