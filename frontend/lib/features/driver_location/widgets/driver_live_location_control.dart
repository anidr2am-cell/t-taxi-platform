import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../utils/user_facing_error.dart';
import '../services/driver_location_api_service.dart';

class DriverLiveLocationControl extends StatefulWidget {
  const DriverLiveLocationControl({
    super.key,
    required this.hasActiveJob,
    this.api,
    this.online,
    this.interval = const Duration(seconds: 15),
  });

  final bool hasActiveJob;
  final DriverLocationApiService? api;
  final bool? online;
  final Duration interval;

  @override
  State<DriverLiveLocationControl> createState() =>
      _DriverLiveLocationControlState();
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
    if (widget.online == false) {
      setState(() {
        _enabled = false;
        _error = context.l10n.t('driver_live_location_online_required');
      });
      return;
    }
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
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
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
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_action_failed'),
        );
      });
    }
  }

  String _formatLastSent() {
    if (_lastSentAt == null) {
      return context.l10n.t('driver_live_location_active_job_only');
    }
    final local = _lastSentAt!.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return context.l10n
        .t('driver_live_location_last_sent')
        .replaceAll('{time}', '$h:$m');
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasActiveJob) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: AppUi.surfaceCard(
        backgroundColor: _enabled ? AppTokens.successLight : AppTokens.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: Icon(
                Icons.my_location,
                color: _enabled ? AppTokens.success : AppTokens.textSecondary,
              ),
              title: Text(
                l10n.t('driver_live_location_share'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                _lastSentAt == null
                    ? l10n.t('driver_live_location_active_job_only')
                    : _formatLastSent(),
              ),
              value: _enabled,
              onChanged: _toggle,
            ),
            if (_sending) const LinearProgressIndicator(),
            if (_enabled) ...[
              const SizedBox(height: AppTokens.spaceSm),
              Text(
                l10n
                    .t('driver_live_location_interval_hint')
                    .replaceAll('{seconds}', '${widget.interval.inSeconds}'),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTokens.textMuted,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: AppTokens.spaceSm),
              AppUi.surfaceCard(
                backgroundColor: AppTokens.errorLight,
                padding: const EdgeInsets.all(AppTokens.spaceSm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: AppTokens.error,
                      size: 18,
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          color: AppTokens.error,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
