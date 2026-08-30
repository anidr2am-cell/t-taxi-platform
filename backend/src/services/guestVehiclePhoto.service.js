const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const ROLES = require('../constants/roles');
const { hashToken } = require('../utils/tokenHash.util');

class GuestVehiclePhotoService {
  constructor(bookingRepository, bookingService = null, pool = null) {
    this.bookingRepository = bookingRepository;
    this.bookingService = bookingService;
    this.pool = pool;
  }

  buildPublicPhotoPath(bookingId) {
    return `/api/v1/public/bookings/${bookingId}/assigned-driver-vehicle-photo`;
  }

  mapVehiclePhotoUrl(row) {
    if (!row?.driver_name || !row?.driver_vehicle_photo_file_id) {
      return null;
    }
    return this.buildPublicPhotoPath(row.id);
  }

  mapPhotoFileRow(file) {
    return {
      filePath: file.file_path,
      mimeType: file.mime_type,
      originalFilename: file.original_filename,
    };
  }

  async getAssignedDriverVehiclePhotoFile(bookingId, guestAccessToken, authUser = null) {
    if (
      authUser?.role === ROLES.CUSTOMER
      && this.bookingService
      && this.pool
    ) {
      const conn = await this.pool.getConnection();
      try {
        const booking = await this.bookingRepository.findById(bookingId, conn);
        if (
          booking
          && booking.customer_user_id
          && booking.customer_user_id === authUser.id
        ) {
          return this.getAssignedDriverVehiclePhotoFileForCustomer(bookingId, authUser);
        }
      } finally {
        conn.release();
      }
    }

    return this.getAssignedDriverVehiclePhotoFileForGuest(
      bookingId,
      guestAccessToken,
    );
  }

  async getAssignedDriverVehiclePhotoFileForCustomer(bookingId, authUser) {
    const conn = await this.pool.getConnection();
    try {
      const booking = await this.bookingRepository.findById(bookingId, conn);
      if (!booking) {
        throw new AppError('Booking not found', {
          statusCode: HTTP_STATUS.NOT_FOUND,
          errorCode: ERROR_CODES.BOOKING_NOT_FOUND,
        });
      }

      await this.bookingService.assertCustomerOrGuestAccess(
        conn,
        booking,
        authUser,
        null,
      );
    } finally {
      conn.release();
    }

    const file = await this.bookingRepository.findAssignedDriverVehiclePhotoFileByBookingId(
      bookingId,
    );
    if (!file) {
      throw new AppError('Vehicle photo not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }

    return this.mapPhotoFileRow(file);
  }

  async getAssignedDriverVehiclePhotoFileForGuest(bookingId, guestAccessToken) {
    const token = String(guestAccessToken ?? '').trim();
    if (!token) {
      throw new AppError('Booking is not accessible', {
        statusCode: HTTP_STATUS.FORBIDDEN,
        errorCode: ERROR_CODES.BOOKING_NOT_ACCESSIBLE,
      });
    }

    const file = await this.bookingRepository.findGuestAssignedDriverVehiclePhotoFile(
      bookingId,
      hashToken(token),
    );
    if (!file) {
      throw new AppError('Vehicle photo not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }

    return this.mapPhotoFileRow(file);
  }
}

module.exports = GuestVehiclePhotoService;
