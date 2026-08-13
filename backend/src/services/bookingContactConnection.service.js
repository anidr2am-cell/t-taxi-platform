const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const CONTACT_STATUS = require('../constants/contactStatus');
const CONTACT_CHANNEL = require('../constants/contactChannel');
const {
  isContactConnectionRequired,
} = require('../policies/bookingDispatchEligibility.policy');
const logger = require('../utils/logger');

class BookingContactConnectionService {
  constructor(
    pool,
    bookingRepository,
    contactConnectionRepository,
    bookingService,
    platformSettingsService = null,
  ) {
    this.pool = pool;
    this.bookingRepository = bookingRepository;
    this.contactConnectionRepository = contactConnectionRepository;
    this.bookingService = bookingService;
    this.platformSettingsService = platformSettingsService;
  }

  mapPublicConnection(booking, connection) {
    return {
      bookingNumber: booking.booking_number,
      contactStatus: booking.contact_status,
      contactChannel: booking.contact_channel,
      contactRequestedAt: booking.contact_requested_at,
      contactVerifiedAt: booking.contact_verified_at,
      isUrgentRequest: Number(booking.is_urgent_request) === 1,
      bookingStatus: booking.status,
      paymentMethod: booking.payment_method ?? 'PAY_DRIVER',
      paymentStatus: booking.payment_status ?? 'UNPAID',
      totalAmount: Number(booking.total_amount ?? 0),
      currency: booking.currency ?? 'THB',
      connection: connection
        ? {
            id: connection.id,
            channel: connection.channel,
            status: connection.status,
            customerConfirmedAt: connection.customer_confirmed_at,
            adminVerifiedAt: connection.admin_verified_at,
          }
        : null,
      contactConnectionRequired: isContactConnectionRequired(),
    };
  }

  async assertChannelEnabled(channel) {
    const settings = await this.getPublicSettings();
    const enabled = settings.channels.some((row) => row.code === channel);
    if (!enabled) {
      throw this.validationError('Contact channel is not available');
    }
  }

  async getPublicSettings() {
    if (!this.platformSettingsService?.getContactChannelsPublic) {
      return { channels: [] };
    }
    return this.platformSettingsService.getContactChannelsPublic();
  }

  async getConnectionStatus(bookingNumber, authUser, guestAccessToken) {
    const conn = await this.pool.getConnection();
    try {
      const booking = await this.bookingRepository.findContactBookingByNumber(
        bookingNumber,
        conn,
      );
      if (!booking) {
        throw this.notFound();
      }
      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        guestAccessToken,
      );
      const connection = await this.contactConnectionRepository.findActiveByBookingId(
        conn,
        booking.id,
      );
      return this.mapPublicConnection(booking, connection);
    } finally {
      conn.release();
    }
  }

  async startConnection(bookingNumber, channel, authUser, guestAccessToken) {
    if (!BookingContactConnectionRepository.isAllowedChannel(channel)) {
      throw this.validationError('Invalid contact channel');
    }
    if (channel === CONTACT_CHANNEL.EMAIL) {
      throw this.validationError('Email contact is not available yet');
    }
    await this.assertChannelEnabled(channel);

    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        bookingNumber,
        conn,
      );
      if (!booking) {
        throw this.notFound();
      }
      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        guestAccessToken,
      );

      if (booking.contact_status === CONTACT_STATUS.VERIFIED) {
        await conn.commit();
        const connection = await this.contactConnectionRepository.findActiveByBookingId(
          conn,
          booking.id,
        );
        return this.mapPublicConnection(booking, connection);
      }

      await this.contactConnectionRepository.cancelActiveConnections(conn, booking.id);
      const connectionId = await this.contactConnectionRepository.insertConnection(conn, {
        bookingId: booking.id,
        channel,
        status: CONTACT_STATUS.PENDING,
      });
      await this.contactConnectionRepository.updateBookingContactSnapshot(conn, booking.id, {
        contactStatus: CONTACT_STATUS.PENDING,
        contactChannel: channel,
        contactRequestedAt: null,
        contactVerifiedAt: null,
      });

      await conn.commit();
      const updatedBooking = await this.bookingRepository.findById(booking.id);
      const connection = await this.contactConnectionRepository.findById(null, connectionId);
      return this.mapPublicConnection(updatedBooking, connection);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async confirmSent(bookingNumber, authUser, guestAccessToken) {
    const conn = await this.pool.getConnection();
    try {
      await conn.beginTransaction();
      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        bookingNumber,
        conn,
      );
      if (!booking) {
        throw this.notFound();
      }
      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        guestAccessToken,
      );

      if (booking.contact_status === CONTACT_STATUS.VERIFIED) {
        await conn.commit();
        const connection = await this.contactConnectionRepository.findActiveByBookingId(
          conn,
          booking.id,
        );
        return this.mapPublicConnection(booking, connection);
      }

      const connection = await this.contactConnectionRepository.findActiveByBookingId(
        conn,
        booking.id,
      );
      if (!connection) {
        throw this.validationError('Select a messenger channel before confirming');
      }

      const now = this.bookingService.formatDateTime(new Date());
      if (booking.contact_status === CONTACT_STATUS.CONFIRM_REQUESTED) {
        await conn.commit();
        return this.mapPublicConnection(booking, {
          ...connection,
          status: CONTACT_STATUS.CONFIRM_REQUESTED,
        });
      }

      await this.contactConnectionRepository.updateConnectionStatus(conn, connection.id, {
        status: CONTACT_STATUS.CONFIRM_REQUESTED,
        customerConfirmedAt: now,
      });
      await this.contactConnectionRepository.updateBookingContactSnapshot(conn, booking.id, {
        contactStatus: CONTACT_STATUS.CONFIRM_REQUESTED,
        contactChannel: connection.channel,
        contactRequestedAt: now,
      });

      await conn.commit();
      const updatedBooking = await this.bookingRepository.findById(booking.id);
      const updatedConnection = await this.contactConnectionRepository.findById(
        null,
        connection.id,
      );
      return this.mapPublicConnection(updatedBooking, updatedConnection);
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }
  }

  async adminVerify(bookingNumber, adminUserId) {
    const conn = await this.pool.getConnection();
    let shouldDispatch = false;
    let bookingSnapshot = null;
    try {
      await conn.beginTransaction();
      const booking = await this.bookingRepository.findByBookingNumberForUpdate(
        bookingNumber,
        conn,
      );
      if (!booking) {
        throw this.notFound();
      }

      if (booking.contact_status === CONTACT_STATUS.VERIFIED) {
        const bookingWithMeta = await this.bookingRepository.findById(booking.id, conn);
        bookingSnapshot = bookingWithMeta ?? booking;
        shouldDispatch = this.bookingService.needsContactDispatchRetry(bookingSnapshot);
        await conn.commit();
      } else {
        if (booking.contact_status !== CONTACT_STATUS.CONFIRM_REQUESTED) {
          throw new AppError('Booking contact is not awaiting admin verification', {
            statusCode: HTTP_STATUS.CONFLICT,
            errorCode: ERROR_CODES.BOOKING_CONTACT_NOT_READY,
          });
        }

        const connection = await this.contactConnectionRepository.findActiveByBookingId(
          conn,
          booking.id,
        );
        if (!connection) {
          throw this.validationError('No active contact connection found');
        }

        const now = this.bookingService.formatDateTime(new Date());
        await this.contactConnectionRepository.updateConnectionStatus(conn, connection.id, {
          status: CONTACT_STATUS.VERIFIED,
          adminVerifiedAt: now,
          adminVerifiedBy: adminUserId,
        });
        await this.contactConnectionRepository.updateBookingContactSnapshot(conn, booking.id, {
          contactStatus: CONTACT_STATUS.VERIFIED,
          contactChannel: connection.channel,
          contactVerifiedAt: now,
        });

        shouldDispatch = isContactConnectionRequired();
        bookingSnapshot = await this.bookingRepository.findById(booking.id, conn);
        await conn.commit();
      }
    } catch (err) {
      await conn.rollback();
      throw err;
    } finally {
      conn.release();
    }

    let dispatchStarted = false;
    if (shouldDispatch && bookingSnapshot) {
      try {
        dispatchStarted = await this.bookingService.dispatchAfterContactVerified(bookingSnapshot);
      } catch (dispatchErr) {
        logger.error('Failed to dispatch after contact verification', {
          bookingNumber,
          error: dispatchErr?.message,
        });
      }
    }

    const refreshed = await this.bookingRepository.findContactBookingByNumber(bookingNumber);
    const connection = await this.contactConnectionRepository.findActiveByBookingId(
      null,
      refreshed.id,
    );
    return {
      ...this.mapPublicConnection(refreshed, connection),
      dispatchStarted,
    };
  }

  notFound() {
    return new AppError('Booking not found', {
      statusCode: HTTP_STATUS.NOT_FOUND,
      errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
    });
  }

  validationError(message) {
    return new AppError(message, {
      statusCode: HTTP_STATUS.BAD_REQUEST,
      errorCode: ERROR_CODES.VALIDATION_ERROR,
    });
  }
}

const BookingContactConnectionRepository = require('../repositories/bookingContactConnection.repository');

module.exports = BookingContactConnectionService;
