const { isEffectiveAt } = require('../utils/pricing.util');

// Public business information only. Do not return repository rows directly.
class LandingDataService {
  constructor({ routeRepository, vehicleRepository, pricingService, platformSettingsService, now = Date.now }) {
    Object.assign(this, { routeRepository, vehicleRepository, pricingService, platformSettingsService, now });
    this.cached = null;
    this.pending = null;
  }

  async get() {
    if (this.cached && this.now() < this.cached.expiresAt) return this.cached.data;
    if (this.pending) return this.pending;
    this.pending = this.load().then(data => {
      this.cached = { data, expiresAt: this.now() + 300_000 };
      return data;
    }).finally(() => { this.pending = null; });
    return this.pending;
  }

  async load() {
    const [routes, vehicles, contacts] = await Promise.all([
      this.routeRepository.findAll(), this.vehicleRepository.findActiveTypesOrdered(),
      this.platformSettingsService.getContactChannelsPublic(),
    ]);
    const vehicleCodes = vehicles.map(v => v.code).filter(code => ['SEDAN', 'SUV', 'VAN'].includes(code));
    const rows = [];
    for (const route of routes.filter(r => r.isActive && isEffectiveAt(r, new Date(this.now())))) {
      const prices = {};
      for (const vehicleTypeCode of vehicleCodes) {
        const quote = await this.pricingService.calculate({
          serviceTypeCode: route.serviceTypeCode, vehicleTypeCode, vehicleCount: 1,
          originLocationCode: route.originLocationCode,
          destinationLocationCode: route.destinationLocationCode, options: {},
        });
        if (typeof quote.totalAmount !== 'number' || !Number.isFinite(quote.totalAmount) || quote.totalAmount <= 0) {
          throw new Error('Landing fare unavailable');
        }
        prices[vehicleTypeCode] = quote.totalAmount;
      }
      rows.push({ serviceTypeCode: route.serviceTypeCode, origin: route.originLocationCode,
        originLabel: route.originDisplayName, destination: route.destinationLocationCode,
        label: route.destinationDisplayName, prices });
    }
    const channels = contacts.channels.map(c => ({ code: c.code, displayName: c.displayName,
      addUrl: c.addUrl || null, phoneNumber: c.phoneNumber || null,
      accountId: c.accountId || null, qrImageUrl: c.qrImageUrl || null }));
    return { currency: 'THB', updatedAt: new Date(this.now()).toISOString(), rows, channels };
  }
}
module.exports = LandingDataService;
