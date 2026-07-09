const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');
const { hashToken } = require('../utils/tokenHash.util');

class GuestVehiclePhotoService {
  constructor(bookingRepository) {
    this.bookingRepository = bookingRepository;
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

  async getAssignedDriverVehiclePhotoFile(bookingId, guestAccessToken) {
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

    return {
      filePath: file.file_path,
      mimeType: file.mime_type,
      originalFilename: file.original_filename,
    };
  }
}

module.exports = GuestVehiclePhotoService;
