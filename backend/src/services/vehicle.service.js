class VehicleService {
  constructor(vehicleRepository) {
    this.vehicleRepository = vehicleRepository;
  }

  async listTypes() {
    const rows = await this.vehicleRepository.findPublicTypesOrdered();
    return rows.map((row) => ({
      id: row.id,
      code: row.code,
      name: row.name,
      passengerCapacity: row.max_passengers,
      luggageCapacity: row.max_luggage,
      isActive: Boolean(row.is_active),
    }));
  }
}

module.exports = VehicleService;
