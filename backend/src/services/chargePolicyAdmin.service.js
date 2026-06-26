const AppError = require('../utils/AppError');
const HTTP_STATUS = require('../constants/httpStatus');
const ERROR_CODES = require('../constants/errorCodes');

class ChargePolicyAdminService {
  constructor(chargePolicyRepository) {
    this.chargePolicyRepository = chargePolicyRepository;
  }

  async list(options) {
    return this.chargePolicyRepository.findAll(options);
  }

  async getById(id) {
    const policy = await this.chargePolicyRepository.findById(id);
    if (!policy) {
      throw new AppError('Charge policy not found', {
        statusCode: HTTP_STATUS.NOT_FOUND,
        errorCode: ERROR_CODES.NOT_FOUND,
      });
    }
    return policy;
  }

  async create(input, userId) {
    return this.chargePolicyRepository.create({
      chargeType: input.chargeType,
      calculationType: input.calculationType,
      amount: input.amount,
      isActive: input.isActive,
      effectiveFrom: input.effectiveFrom,
      effectiveTo: input.effectiveTo,
      createdBy: userId,
      updatedBy: userId,
    });
  }

  async update(id, input, userId) {
    await this.getById(id);
    return this.chargePolicyRepository.update(id, {
      chargeType: input.chargeType,
      calculationType: input.calculationType,
      amount: input.amount,
      isActive: input.isActive,
      effectiveFrom: input.effectiveFrom,
      effectiveTo: input.effectiveTo,
      updatedBy: userId,
    });
  }

  async delete(id, userId) {
    await this.getById(id);
    await this.chargePolicyRepository.softDelete(id, userId);
    return true;
  }
}

module.exports = ChargePolicyAdminService;
