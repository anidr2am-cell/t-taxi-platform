const { isEffectiveAt } = require('../utils/pricing.util');

const EXPIRING_SOON_DAYS = 30;

function classifyPriceStatus(price, now) {
  if (!price.isActive) {
    return 'inactive';
  }

  const from = price.effectiveFrom ? new Date(price.effectiveFrom) : null;
  const to = price.effectiveTo ? new Date(price.effectiveTo) : null;

  if (to && now > to) {
    return 'expired';
  }
  if (from && now < from) {
    return 'future';
  }
  if (isEffectiveAt(price, now)) {
    return 'current';
  }
  return 'inactive';
}

function isExpiringSoon(price, now) {
  if (!price.isActive || !price.effectiveTo) {
    return false;
  }

  const to = new Date(price.effectiveTo);
  if (to <= now) {
    return false;
  }

  const threshold = new Date(now);
  threshold.setDate(threshold.getDate() + EXPIRING_SOON_DAYS);
  return to <= threshold;
}

class PricingAdminService {
  constructor(routeRepository, vehiclePriceRepository, chargePolicyRepository) {
    this.routeRepository = routeRepository;
    this.vehiclePriceRepository = vehiclePriceRepository;
    this.chargePolicyRepository = chargePolicyRepository;
  }

  async getSummary() {
    const now = new Date();
    const [routes, prices, policies] = await Promise.all([
      this.routeRepository.findAll({ includeInactive: true }),
      this.vehiclePriceRepository.findAll({ includeInactive: true }),
      this.chargePolicyRepository.findAll({ includeInactive: true }),
    ]);

    const activeRoutes = routes.filter((route) => route.isActive);
    const activePrices = prices.filter((price) => price.isActive);
    const activePolicies = policies.filter((policy) => policy.isActive);
    const currentPrices = prices.filter((price) => classifyPriceStatus(price, now) === 'current');
    const expiringSoonPrices = prices.filter((price) => isExpiringSoon(price, now));

    return {
      activeRouteCount: activeRoutes.length,
      activeVehiclePriceCount: activePrices.length,
      activeChargePolicyCount: activePolicies.length,
      currentPriceCount: currentPrices.length,
      expiringSoonPriceCount: expiringSoonPrices.length,
      updatedAt: now.toISOString(),
    };
  }
}

module.exports = PricingAdminService;
module.exports.classifyPriceStatus = classifyPriceStatus;
module.exports.isExpiringSoon = isExpiringSoon;
