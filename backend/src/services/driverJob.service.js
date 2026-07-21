const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const SERVICE_TYPES = require('../constants/serviceTypes');
const { parseServiceDateTimeToMs } = require('../utils/serviceDateTime.util');

const THAILAND_TIME_ZONE = 'Asia/Bangkok';
const STANDBY_WINDOW_MS = 60 * 60 * 1000;

class DriverJobService {
  constructor(bookingRepository) {
    this.bookingRepository = bookingRepository;
  }

  getThailandDateParts(now = new Date()) {
    const parts = new Intl.DateTimeFormat('en-US', {
      timeZone: THAILAND_TIME_ZONE,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
    }).formatToParts(now);

    const value = (type) => parts.find((part) => part.type === type)?.value;
    return {
      year: value('year'),
      month: value('month'),
      day: value('day'),
    };
  }

  addDays(dateText, days) {
    const [year, month, day] = dateText.split('-').map(Number);
    const date = new Date(Date.UTC(year, month - 1, day + days));
    return date.toISOString().slice(0, 10);
  }

  getTodayRange(now = new Date()) {
    const { year, month, day } = this.getThailandDateParts(now);
    const today = `${year}-${month}-${day}`;
    const tomorrow = this.addDays(today, 1);
    return {
      date: today,
      start: `${today} 00:00:00`,
      end: `${tomorrow} 00:00:00`,
    };
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

  canConfirmStandby(row, now = new Date()) {
    if (row.status !== 'DRIVER_ASSIGNED') return false;
    if (row.assignment_status !== 'ASSIGNED') return false;
    const allowedAt = this.standbyAllowedAt(row);
    const allowedAtMs = parseServiceDateTimeToMs(allowedAt);
    const nowMs = now instanceof Date ? now.getTime() : Number(now);
    return allowedAtMs != null && Number.isFinite(nowMs) && nowMs >= allowedAtMs;
  }

  allowedActions(row, now = new Date()) {
    const status = row.status;
    const assignmentStatus = row.assignment_status ?? null;
    if (status === 'DRIVER_ASSIGNED') {
      if (assignmentStatus === 'ASSIGNED') {
        if (!this.canConfirmStandby(row, now)) {
          return ['VIEW_DETAILS'];
        }
        return ['VIEW_DETAILS', 'ACCEPT_BOOKING'];
      }
      if (assignmentStatus === 'ACCEPTED') {
        return ['VIEW_DETAILS', 'START_ON_ROUTE'];
      }
      return ['VIEW_DETAILS'];
    }
    if (status === 'ON_ROUTE') {
      return ['VIEW_DETAILS', 'MARK_ARRIVED'];
    }
    if (status === 'DRIVER_ARRIVED') {
      return ['VIEW_DETAILS', 'MARK_PICKED_UP'];
    }
    if (status === 'PICKED_UP') {
      return ['VIEW_DETAILS', 'END_TRIP'];
    }
    return [];
  }

  passengerCount(row) {
    return Number(row.adults || 0) + Number(row.children || 0) + Number(row.infants || 0);
  }

  paymentMethodLabel(paymentMethod) {
    switch (paymentMethod) {
      case 'PAY_DRIVER':
      case 'PAY_DRIVER_AT_DESTINATION':
        return 'PAY_DRIVER_AT_DESTINATION';
      case 'BANK_TRANSFER':
        return 'BANK_TRANSFER';
      case 'CARD':
      case 'CREDIT_CARD':
        return 'CARD';
      default:
        return null;
    }
  }

  moneyAmount(value) {
    if (value == null) return null;
    const amount = Number(value);
    return Number.isFinite(amount) ? amount : null;
  }

  driverExpectedIncome(totalAmount, commissionAmount) {
    const customerPaymentAmount = this.moneyAmount(totalAmount);
    const companyCommissionAmount = this.moneyAmount(commissionAmount);
    if (customerPaymentAmount == null || companyCommissionAmount == null) {
      return null;
    }
    if (customerPaymentAmount < 0 || companyCommissionAmount < 0) {
      return null;
    }
    if (companyCommissionAmount > customerPaymentAmount) {
      return null;
    }
    return customerPaymentAmount - companyCommissionAmount;
  }

  paymentSummary(row) {
    const customerPaymentAmount = this.moneyAmount(row.total_amount);
    const companyCommissionAmount = this.moneyAmount(row.commission_amount);
    const driverExpectedIncomeAmount = this.driverExpectedIncome(
      row.total_amount,
      row.commission_amount,
    );
    const currency = row.currency ?? null;
    return {
      customerPaymentAmount,
      customerPaymentCurrency: customerPaymentAmount == null ? null : currency,
      customerPaymentMethod: this.paymentMethodLabel(row.payment_method),
      companyCommissionAmount,
      companyCommissionCurrency: companyCommissionAmount == null ? null : currency,
      driverExpectedIncomeAmount,
      driverExpectedIncomeCurrency: driverExpectedIncomeAmount == null ? null : currency,
    };
  }

  location(value) {
    if (value == null) return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }

  metadata(row) {
    if (!row.metadata) return {};
    if (typeof row.metadata === 'object') return row.metadata;
    try {
      const parsed = JSON.parse(row.metadata);
      return parsed && typeof parsed === 'object' ? parsed : {};
    } catch (_) {
      return {};
    }
  }

  standbyReference(row) {
    if (row.service_type_code === SERVICE_TYPES.AIRPORT_PICKUP) {
      const arrival =
        row.flight_scheduled_arrival_at
        ?? row.flight_scheduled_arrival_at_text
        ?? row.flight_estimated_arrival_at
        ?? row.flight_estimated_arrival_at_text;
      if (arrival) {
        return {
          referenceTimeType: 'AIRPORT_ARRIVAL',
          referenceTime: arrival,
        };
      }
    }
    return {
      referenceTimeType: 'VEHICLE_DEPARTURE',
      referenceTime: row.scheduled_pickup_at ?? null,
    };
  }

  standbyAllowedAt(row) {
    const reference = this.standbyReference(row);
    const referenceMs = parseServiceDateTimeToMs(reference.referenceTime);
    if (referenceMs == null) return null;
    return new Date(referenceMs - STANDBY_WINDOW_MS).toISOString();
  }

  mapBase(row) {
    const standbyReference = this.standbyReference(row);
    const standbyAllowedAt = this.standbyAllowedAt(row);
    const standbyConfirmed = row.assignment_status === 'ACCEPTED';
    const metadata = this.metadata(row);
    const originLocation = metadata.originLocation ?? {};
    const destinationLocation = metadata.destinationLocation ?? {};
    return {
      bookingNumber: row.booking_number,
      status: row.status,
      assignmentStatus: row.assignment_status ?? null,
      acceptedAt: row.accepted_at ?? null,
      scheduledPickupAt: row.scheduled_pickup_at ?? null,
      standbyReferenceTimeType: standbyReference.referenceTimeType,
      standbyReferenceTime: standbyReference.referenceTime,
      standbyAllowedAt,
      standbyConfirmed,
      standbyConfirmedAt: standbyConfirmed ? row.accepted_at ?? null : null,
      canConfirmStandby: this.canConfirmStandby(row),
      serviceType: {
        code: row.service_type_code,
        name: row.service_type_name,
      },
      pickupDate: row.pickup_date,
      pickupTime: row.pickup_time,
      origin: row.origin_address,
      destination: row.destination_address,
      pickupLocation: this.locationDetails({
        name: originLocation.name,
        address: row.origin_address,
        placeId: row.origin_place_id,
        latitude: row.origin_lat,
        longitude: row.origin_lng,
      }),
      destinationLocation: this.locationDetails({
        name: destinationLocation.name,
        address: row.destination_address,
        placeId: row.destination_place_id,
        latitude: row.destination_lat,
        longitude: row.destination_lng,
      }),
      originLatitude: this.location(row.origin_lat),
      originLongitude: this.location(row.origin_lng),
      destinationLatitude: this.location(row.destination_lat),
      destinationLongitude: this.location(row.destination_lng),
      passengerCount: this.passengerCount(row),
      vehicleType: {
        code: row.vehicle_type_code,
        name: row.vehicle_type_name,
      },
      ...this.paymentSummary(row),
      currency: row.currency,
      paymentMethodLabel: this.paymentMethodLabel(row.payment_method),
      customerDisplayName: row.customer_name,
      flightNumber: row.flight_number,
      flightStatus: row.delay_status,
      latestEstimatedArrival: row.flight_estimated_arrival_at_text,
      allowedActions: this.allowedActions(row),
    };
  }

  locationDetails({ name, address, placeId, latitude, longitude }) {
    const normalizedName = typeof name === 'string' && name.trim() ? name.trim() : null;
    const normalizedAddress =
      typeof address === 'string' && address.trim() ? address.trim() : null;
    const displayName =
      normalizedName && normalizedName !== normalizedAddress ? normalizedName : null;
    return {
      name: displayName,
      address: normalizedAddress,
      latitude: this.location(latitude),
      longitude: this.location(longitude),
      placeId: typeof placeId === 'string' && placeId.trim() ? placeId.trim() : null,
    };
  }

  mapDetail(row) {
    const detail = {
      ...this.mapBase(row),
      customerPhone: row.customer_phone,
      passengers: {
        adults: Number(row.adults || 0),
        children: Number(row.children || 0),
        infants: Number(row.infants || 0),
      },
      luggage: {
        carriers20Inch: Number(row.carriers_20_inch || 0),
        carriers24InchPlus: Number(row.carriers_24_inch_plus || 0),
        golfBags: Number(row.golf_bags || 0),
        specialItems: row.special_items,
      },
      flight: {
        flightNumber: row.flight_number,
        flightStatus: row.delay_status,
        scheduledArrival: row.flight_scheduled_arrival_at_text,
        latestEstimatedArrival: row.flight_estimated_arrival_at_text,
        delayMinutes: row.delay_minutes,
      },
      specialInstructions: row.special_requests,
      paymentMethod: row.payment_method,
      nameSignRequested: Boolean(row.name_sign_requested),
      qr: {
        boarding: {
          available: Boolean(row.boarding_qr_token_hash),
          consumed: Boolean(row.boarding_qr_used_at),
        },
        dropoff: {
          available: Boolean(row.dropoff_qr_token_hash && !row.dropoff_qr_used_at),
          consumed: Boolean(row.dropoff_qr_used_at),
        },
      },
    };
    delete detail.companyCommissionAmount;
    delete detail.companyCommissionCurrency;
    delete detail.driverExpectedIncomeAmount;
    delete detail.driverExpectedIncomeCurrency;
    return detail;
  }

  async listToday(driverUserId, now = new Date()) {
    return this.listScheduled(driverUserId, now);
  }

  async listScheduled(driverUserId, now = new Date()) {
    const range = this.getTodayRange(now);
    const rows = await this.bookingRepository.findActiveDriverBookingsScheduled(
      driverUserId,
    );
    return {
      date: range.date,
      items: rows.map((row) => this.mapBase(row)),
    };
  }

  async getDetail(driverUserId, bookingNumber) {
    const normalizedBookingNumber = this.validateBookingNumber(bookingNumber);
    let row = await this.bookingRepository.findActiveDriverBookingByNumber(
      driverUserId,
      normalizedBookingNumber,
    );

    if (!row) {
      row = await this.bookingRepository.findDriverTerminalBookingByNumber(
        driverUserId,
        normalizedBookingNumber,
      );
    }

    if (!row) {
      throw new AppError('Booking not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.BOOKING_NOT_FOUND || ERROR_CODES.NOT_FOUND,
      });
    }

    return this.mapDetail(row);
  }
}

module.exports = DriverJobService;
