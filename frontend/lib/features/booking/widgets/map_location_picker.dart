import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../config/map_provider_config.dart';
import '../models/location_option.dart';
import '../services/current_location_service.dart';
import '../services/device_locale_resolver.dart';
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
    this.deviceLocaleResolver,
    this.currentLocationProvider,
  });

  final String languageCode;
  final LocationOption? initialLocation;
  final ReverseLocationLookup? reverseLookup;
  final DeviceLocaleResolver? deviceLocaleResolver;
  final CurrentLocationProvider? currentLocationProvider;

  static Future<LocationOption?> show(
    BuildContext context, {
    required String languageCode,
    LocationOption? initialLocation,
    ReverseLocationLookup? reverseLookup,
    DeviceLocaleResolver? deviceLocaleResolver,
    CurrentLocationProvider? currentLocationProvider,
  }) {
    return showDialog<LocationOption>(
      context: context,
      builder: (_) => Dialog.fullscreen(
        child: MapLocationPicker(
          languageCode: languageCode,
          initialLocation: initialLocation,
          reverseLookup: reverseLookup,
          deviceLocaleResolver: deviceLocaleResolver,
          currentLocationProvider: currentLocationProvider,
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
  final MapController _mapController = MapController();
  late LatLng _selected;
  late final String _reverseGeocodingLanguage;
  bool _resolving = false;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    final current = widget.initialLocation;
    _reverseGeocodingLanguage =
        (widget.deviceLocaleResolver ?? DeviceLocaleResolver()).resolve(
          appLanguage: widget.languageCode,
        );
    _selected = current?.latitude != null && current?.longitude != null
        ? LatLng(current!.latitude!, current.longitude!)
        : _thailandCenter;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    if (_locating || _resolving) return;
    setState(() => _locating = true);
    try {
      final location =
          await (widget.currentLocationProvider ??
                  GeolocatorCurrentLocationProvider())
              .locate();
      if (!mounted) return;
      final point = LatLng(location.latitude, location.longitude);
      setState(() {
        _selected = point;
        _locating = false;
      });
      _mapController.move(point, 16);
      if (location.accuracyMeters > 100) {
        _showMessage('low_location_accuracy');
      }
    } on CurrentLocationException catch (error) {
      if (!mounted) return;
      setState(() => _locating = false);
      _showMessage(_messageKey(error.failure));
    } catch (_) {
      if (!mounted) return;
      setState(() => _locating = false);
      _showMessage('location_unavailable');
    }
  }

  void _showMessage(String key) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.t(key))));
  }

  String _messageKey(CurrentLocationFailure failure) {
    return switch (failure) {
      CurrentLocationFailure.permissionRequired =>
        'location_permission_required',
      CurrentLocationFailure.permissionDenied => 'location_permission_denied',
      CurrentLocationFailure.permissionPermanentlyDenied =>
        'location_permission_permanently_denied',
      CurrentLocationFailure.serviceDisabled => 'location_service_disabled',
      CurrentLocationFailure.unavailable => 'location_unavailable',
      CurrentLocationFailure.timeout => 'location_timeout',
      CurrentLocationFailure.requiresHttps => 'location_requires_https',
    };
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
        _reverseGeocodingLanguage,
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
              mapController: _mapController,
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
                Positioned(
                  top: 12,
                  right: 12,
                  child: SafeArea(
                    child: FilledButton.tonalIcon(
                      key: const ValueKey('map_current_location'),
                      onPressed: _locating || _resolving
                          ? null
                          : _useCurrentLocation,
                      icon: _locating
                          ? const SizedBox(
                              key: ValueKey('map_current_location_loading'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.my_location),
                      label: Text(
                        l10n.t(
                          _locating
                              ? 'locating_current_position'
                              : 'current_location',
                        ),
                      ),
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
                    onPressed: _resolving || _locating ? null : _confirm,
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
