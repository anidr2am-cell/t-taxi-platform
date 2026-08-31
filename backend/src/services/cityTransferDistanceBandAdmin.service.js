const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

class CityTransferDistanceBandAdminService {
  constructor(cityTransferDistanceBandRepository) {
    this.cityTransferDistanceBandRepository = cityTransferDistanceBandRepository;
  }

  async list(options = {}) {
    return this.cityTransferDistanceBandRepository.findAll(options);
  }

  async getById(id) {
    const band = await this.cityTransferDistanceBandRepository.findById(id);
    if (!band) {
      throw new AppError('City transfer distance band not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }
    return band;
  }

  async update(id, input) {
    await this.getById(id);
    return this.cityTransferDistanceBandRepository.update(id, input);
  }
}

module.exports = CityTransferDistanceBandAdminService;
