const VEHICLE_TYPES = require('../constants/vehicleTypes');

class VehicleRecommendationService {
  constructor(vehicleRepository) {
    this.vehicleRepository = vehicleRepository;
  }

  normalizeInput(input) {
    const adults = input.adults;
    const children = input.children ?? 0;
    const infants = input.infants ?? 0;
    const luggage20 = input.luggage20 ?? 0;
    const luggage24 = input.luggage24 ?? 0;
    const golfBags = input.golfBags ?? 0;
    const specialLuggageCount = input.specialLuggageCount ?? 0;

    const passengerCount = adults + children + infants;
    const luggageCount = luggage20 + luggage24 + golfBags + specialLuggageCount;

    return {
      adults,
      children,
      infants,
      luggage20,
      luggage24,
      golfBags,
      specialLuggageCount,
      passengerCount,
      luggageCount,
    };
  }

  applyRecommendationRules(counts) {
    const { passengerCount, luggageCount, luggage24 } = counts;

    if (passengerCount > 8) {
      return { multipleVehicles: true, recommendedVehicle: null };
    }

    if (passengerCount >= 4 && passengerCount <= 8 && luggageCount <= 8) {
      return { multipleVehicles: false, recommendedVehicle: VEHICLE_TYPES.VAN };
    }

    if (passengerCount <= 2 && luggage24 > 0) {
      return { multipleVehicles: false, recommendedVehicle: VEHICLE_TYPES.SUV };
    }

    if (passengerCount <= 2 && luggageCount <= 4 && luggage24 === 0) {
      return { multipleVehicles: false, recommendedVehicle: VEHICLE_TYPES.SEDAN };
    }

    if (passengerCount <= 3 && luggageCount <= 4) {
      return { multipleVehicles: false, recommendedVehicle: VEHICLE_TYPES.SUV };
    }

    return null;
  }

  fitsCapacityRule(rule, counts) {
    return (
      counts.passengerCount <= rule.max_passengers
      && counts.luggage20 <= rule.max_carriers_20_inch
      && counts.luggage24 <= rule.max_carriers_24_inch_plus
      && counts.golfBags <= rule.max_golf_bags
      && counts.specialLuggageCount <= rule.max_special_luggage
    );
  }

  findDbRecommendedVehicle(capacityRules, counts) {
    const fitting = capacityRules.filter((rule) => this.fitsCapacityRule(rule, counts));
    if (fitting.length === 0) {
      return { multipleVehicles: true, recommendedVehicle: null };
    }

    const smallest = fitting.reduce((best, rule) => (
      rule.sort_order < best.sort_order ? rule : best
    ));

    return { multipleVehicles: false, recommendedVehicle: smallest.code };
  }

  buildSelectableVehicles(vehicleTypes, recommendedCode) {
    const recommended = vehicleTypes.find((type) => type.code === recommendedCode);
    if (!recommended) {
      return [];
    }

    return vehicleTypes
      .filter((type) => type.sort_order >= recommended.sort_order)
      .map((type) => type.code);
  }

  buildMessage({ multipleVehicles, recommendedVehicle }) {
    if (multipleVehicles) {
      return 'Multiple vehicles are required for your party size and luggage.';
    }

    const labels = {
      [VEHICLE_TYPES.SEDAN]: 'Sedan is recommended for your party.',
      [VEHICLE_TYPES.SUV]: 'SUV is recommended for your party.',
      [VEHICLE_TYPES.VIP_SUV]: 'VIP SUV is recommended for your party.',
      [VEHICLE_TYPES.VAN]: 'Van is recommended for your party.',
      [VEHICLE_TYPES.VIP_VAN]: 'VIP Van is recommended for your party.',
      [VEHICLE_TYPES.LUXURY]: 'Luxury vehicle is recommended for your party.',
    };

    return labels[recommendedVehicle] || 'Vehicle recommendation available.';
  }

  async recommend(input) {
    const counts = this.normalizeInput(input);
    const vehicleTypes = await this.vehicleRepository.findActiveTypesOrdered();

    let result = this.applyRecommendationRules(counts);

    if (!result) {
      const capacityRules = await this.vehicleRepository.findActiveCapacityRules();
      result = this.findDbRecommendedVehicle(capacityRules, counts);
    }

    const { multipleVehicles, recommendedVehicle } = result;
    const selectableVehicles = multipleVehicles
      ? []
      : this.buildSelectableVehicles(vehicleTypes, recommendedVehicle);

    const message = this.buildMessage({ multipleVehicles, recommendedVehicle });

    return {
      recommendedVehicle,
      selectableVehicles,
      multipleVehicles,
      message,
    };
  }
}

module.exports = VehicleRecommendationService;
