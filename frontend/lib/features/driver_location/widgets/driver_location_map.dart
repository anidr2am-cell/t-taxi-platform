import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/driver_location.dart';

class DriverLocationMap extends StatelessWidget {
  const DriverLocationMap({
    super.key,
    required this.locations,
    this.height = 260,
    this.onTapLocation,
  });

  final List<DriverLocation> locations;
  final double height;
  final ValueChanged<DriverLocation>? onTapLocation;

  @override
  Widget build(BuildContext context) {
    if (locations.isEmpty) {
      return SizedBox(
        height: height,
        child: const Center(child: Text('No driver location available')),
      );
    }

    final center = LatLng(locations.first.latitude, locations.first.longitude);
    return SizedBox(
      height: height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: center,
            initialZoom: locations.length == 1 ? 14 : 10,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'dev.ttaxi.frontend',
            ),
            MarkerLayer(
              markers: locations
                  .map(
                    (location) => Marker(
                      point: LatLng(location.latitude, location.longitude),
                      width: 44,
                      height: 44,
                      child: IconButton(
                        tooltip: location.displayName,
                        onPressed: () => onTapLocation?.call(location),
                        icon: Icon(
                          Icons.local_taxi,
                          color: location.stale
                              ? Theme.of(context).colorScheme.error
                              : Theme.of(context).colorScheme.primary,
                          size: 30,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}
