import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/driver_location_api_service.dart';

class DriverLiveLocationControl extends StatefulWidget {
  const DriverLiveLocationControl({
    super.key,
    required this.hasActiveJob,
    this.api,
    this.interval = const Duration(seconds: 15),
  });

  final bool hasActiveJob;
  final DriverLocationApiService? api;
  final Duration interval;

  @override
  State<DriverLiveLocationControl> createState() => _DriverLiveLocationControlState();
}

class _DriverLiveLocationControlState extends State<DriverLiveLocationControl> {
  Timer? _timer;
  bool _enabled = false;
  bool _sending = false;
  String? _error;
  DateTime? _lastSentAt;

  @override
  void didUpdateWidget(covariant DriverLiveLocationControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.hasActiveJob && _enabled) {
      _stop();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _toggle(bool value) async {
    if (!value) {
      _stop();
      return;
    }
    await _start();
  }

  Future<void> _start() async {
    if (!widget.hasActiveJob) return;
    setState(() {
      _enabled = true;
      _error = null;
    });
    await _sendOnce();
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) => _sendOnce());
  }

  void _stop() {
    _timer?.cancel();
    setState(() {
      _enabled = false;
      _sending = false;
    });
  }

  Future<Position> _getPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const DriverLocationApiException('Location services are disabled');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const DriverLocationApiException('Location permission denied');
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _sendOnce() async {
    if (_sending || !_enabled || !widget.hasActiveJob) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final position = await _getPosition();
      await (widget.api ?? DriverLocationApiService()).updateDriverLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        heading: position.heading.isNaN ? null : position.heading,
        speedKph: position.speed.isNaN ? null : position.speed * 3.6,
        recordedAt: position.timestamp,
      );
      if (!mounted) return;
      setState(() {
        _lastSentAt = DateTime.now();
        _sending = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasActiveJob) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.my_location),
              title: const Text('Share live location'),
              subtitle: Text(_lastSentAt == null
                  ? 'Only while an active job is in progress'
                  : 'Last sent ${_lastSentAt!.toLocal()}'),
              value: _enabled,
              onChanged: _toggle,
            ),
            if (_sending) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ],
        ),
      ),
    );
  }
}
