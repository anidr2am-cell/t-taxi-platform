const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const BOOKING_STATUS = require('../constants/reservationStatus');
const { generateSecureToken, hashToken } = require('../utils/tokenHash.util');
const GuestVehiclePhotoService = require('./guestVehiclePhoto.service');

const LOOKUP_GUEST_TOKEN_TTL_HOURS = 24;

class GuestBookingLookupService {
  constructor(pool, bookingRepository, guestVehiclePhotoService = null) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.guestVehiclePhotoService = guestVehiclePhotoService
      ?? new GuestVehiclePhotoService(bookingRepository);
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

  mapBooking(row, guestAccessToken, guestAccessExpiresAt) {
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

    return {
      bookingId: row.id,
      bookingNumber: row.booking_number,
      status: row.status,
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
        reviewAvailable: row.status === BOOKING_STATUS.COMPLETED,
        boardingQrRecoverable: false,
        boardingQrPreviouslyIssued: Boolean(row.boarding_qr_token_hash) && !terminalStatus,
      },
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

      return this.mapBooking(booking, guestAccessToken, expiresAt);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }
}

module.exports = GuestBookingLookupService;
