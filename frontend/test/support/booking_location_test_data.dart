import 'package:frontend/features/booking/models/location_option.dart';

LocationOption testBookingLocation({
  required String name,
  String? address,
}) {
  final resolvedAddress = address ?? name;
  return LocationOption(
    id: 'test:$name',
    displayName: name,
    kind: LocationKind.place,
    name: name,
    address: resolvedAddress,
  );
}
