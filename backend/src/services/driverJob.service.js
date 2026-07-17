const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

const THAILAND_TIME_ZONE = 'Asia/Bangkok';

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

  allowedActions(status) {
    if (status === 'DRIVER_ASSIGNED') {
      return ['VIEW_DETAILS', 'START_ON_ROUTE'];
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

  mapBase(row) {
    return {
      bookingNumber: row.booking_number,
      status: row.status,
      serviceType: {
        code: row.service_type_code,
        name: row.service_type_name,
      },
      pickupDate: row.pickup_date,
      pickupTime: row.pickup_time,
      origin: row.origin_address,
      destination: row.destination_address,
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
      allowedActions: this.allowedActions(row.status),
    };
  }

  mapDetail(row) {
    return {
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
        latestEstimatedArrival: row.flight_estimated_arrival_at_text,
        delayMinutes: row.delay_minutes,
      },
      specialInstructions: row.special_requests,
      paymentMethod: row.payment_method,
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
  }

  async listToday(driverUserId, now = new Date()) {
    const range = this.getTodayRange(now);
    const rows = await this.bookingRepository.findActiveDriverBookingsForDate(
      driverUserId,
      range,
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
