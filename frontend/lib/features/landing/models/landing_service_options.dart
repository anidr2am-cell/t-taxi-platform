import 'package:flutter/material.dart';

import '../../booking/models/service_type_option.dart';

class LandingServiceOption {
  final BookingServiceType type;
  final IconData icon;

  const LandingServiceOption({required this.type, required this.icon});
}

const landingServiceOptions = [
  LandingServiceOption(
    type: BookingServiceType.airportPickup,
    icon: Icons.flight_land,
  ),
  LandingServiceOption(
    type: BookingServiceType.airportDropoff,
    icon: Icons.flight_takeoff,
  ),
  LandingServiceOption(
    type: BookingServiceType.cityTransfer,
    icon: Icons.route_outlined,
  ),
  LandingServiceOption(
    type: BookingServiceType.golfTransfer,
    icon: Icons.sports_golf,
  ),
];
