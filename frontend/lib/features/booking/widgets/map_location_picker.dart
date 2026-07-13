import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../config/map_provider_config.dart';
import '../models/location_option.dart';
import '../services/reverse_geocoding_service.dart';

typedef ReverseLocationLookup =
    Future<String?> Function(
      double latitude,
      double longitude,
      String language,
    );

class MapLocationPicker extends StatefulWidget {
  const MapLocationPicker({
    super.key,
    required this.languageCode,
    this.initialLocation,
    this.reverseLookup,
  });

  final String languageCode;
  final LocationOption? initialLocation;
  final ReverseLocationLookup? reverseLookup;

  static Future<LocationOption?> show(
    BuildContext context, {
    required String languageCode,
    LocationOption? initialLocation,
    ReverseLocationLookup? reverseLookup,
  }) {
    return showDialog<LocationOption>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: MapLocationPicker(
          languageCode: languageCode,
          initialLocation: initialLocation,
          reverseLookup: reverseLookup,
        ),
      ),
    );
  }

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  static const _thailandCenter = LatLng(13.7563, 100.5018);
  static final _reverseGeocoding = ReverseGeocodingService();
  late LatLng _selected;
  bool _resolving = false;

  @override
  void initState() {
    super.initState();
    final current = widget.initialLocation;
    _selected = current?.latitude != null && current?.longitude != null
        ? LatLng(current!.latitude!, current.longitude!)
        : _thailandCenter;
  }

  Future<void> _confirm() async {
    if (_resolving) return;
    setState(() => _resolving = true);
    String? address;
    try {
      final lookup =
          widget.reverseLookup ??
          (latitude, longitude, language) => _reverseGeocoding.lookup(
            latitude: latitude,
            longitude: longitude,
            language: language,
          );
      address = await lookup(
        _selected.latitude,
        _selected.longitude,
        widget.languageCode,
      );
    } catch (_) {
      address = null;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      LocationOption.fromCoordinates(
        latitude: _selected.latitude,
        longitude: _selected.longitude,
        address: address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('map_picker_title')),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).cancelButtonLabel,
          onPressed: _resolving ? null : () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(
                initialCenter: _selected,
                initialZoom: widget.initialLocation?.latitude != null ? 15 : 6,
                onTap: (_, point) => setState(() => _selected = point),
              ),
              children: [
                TileLayer(
                  urlTemplate: MapProviderConfig.tileUrlTemplate,
                  userAgentPackageName: 'dev.ttaxi.frontend',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selected,
                      width: 52,
                      height: 52,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 46,
                      ),
                    ),
                  ],
                ),
                SimpleAttributionWidget(
                  source: const Text(
                    'OpenStreetMap contributors',
                    key: ValueKey('openstreetmap_attribution'),
                  ),
                  onTap: () => unawaited(
                    launchUrl(
                      Uri.parse(MapProviderConfig.attributionUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(l10n.t('map_picker_hint'), textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(
                    '${_selected.latitude.toStringAsFixed(6)}, '
                    '${_selected.longitude.toStringAsFixed(6)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _resolving ? null : _confirm,
                    icon: _resolving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(l10n.t('map_picker_confirm')),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
