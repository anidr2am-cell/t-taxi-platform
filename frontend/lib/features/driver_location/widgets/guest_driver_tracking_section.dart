import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/driver_location.dart';
import '../services/driver_location_api_service.dart';
import '../services/driver_location_socket_service.dart';
import 'driver_location_map.dart';

class GuestDriverTrackingSection extends StatefulWidget {
  const GuestDriverTrackingSection({
    super.key,
    required this.bookingId,
    required this.guestAccessToken,
    required this.bookingStatus,
    this.api,
    this.socket,
  });

  final int bookingId;
  final String guestAccessToken;
  final String bookingStatus;
  final DriverLocationApiService? api;
  final DriverLocationSocketService? socket;

  @override
  State<GuestDriverTrackingSection> createState() =>
      _GuestDriverTrackingSectionState();
}

class _GuestDriverTrackingSectionState
    extends State<GuestDriverTrackingSection> {
  static const _locationStatuses = {'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP'};
  static const _visibleStatuses = {
    'DRIVER_ASSIGNED',
    'ON_ROUTE',
    'DRIVER_ARRIVED',
    'PICKED_UP',
  };
  static const _freshLocation = Duration(seconds: 60);

  late final DriverLocationApiService _api =
      widget.api ?? DriverLocationApiService();
  late final DriverLocationSocketService _socket =
      widget.socket ?? DriverLocationSocketService();

  Timer? _staleTimer;
  bool _loading = false;
  bool _connected = false;
  String? _error;
  GuestDriverLocationResult? _result;
  int _generation = 0;

  bool get _visible => _visibleStatuses.contains(widget.bookingStatus);

  bool get _canLoadLocation =>
      _locationStatuses.contains(widget.bookingStatus) &&
      widget.guestAccessToken.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _syncLifecycle();
  }

  @override
  void didUpdateWidget(covariant GuestDriverTrackingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId ||
        oldWidget.guestAccessToken != widget.guestAccessToken ||
        oldWidget.bookingStatus != widget.bookingStatus) {
      _generation += 1;
      _socket.disconnect();
      _staleTimer?.cancel();
      _syncLifecycle();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _staleTimer?.cancel();
    _socket.disconnect();
    super.dispose();
  }

  void _syncLifecycle() {
    if (!_visible) {
      _loading = false;
      _result = null;
      _error = null;
      return;
    }
    if (!_canLoadLocation) {
      _loading = false;
      _result = const GuestDriverLocationResult(
        available: false,
        reason: 'WAITING_FOR_DRIVER',
      );
      return;
    }
    final generation = _generation;
    _load(generation: generation);
    _connectSocket(generation: generation);
    _startStaleTimer(generation);
  }

  Future<void> _connectSocket({required int generation}) async {
    _socket.onGuestChanged = (payload) {
      if (!mounted || generation != _generation) return;
      if (payload['bookingId'] != widget.bookingId) return;
      final next = GuestDriverLocationResult.fromJson(payload);
      final currentRecordedAt = _result?.driver?.recordedAt;
      final nextRecordedAt = next.driver?.recordedAt;
      if (_isOlderOrSame(nextRecordedAt, currentRecordedAt)) return;
      setState(() {
        _result = next;
        _error = null;
      });
    };
    _socket.onError = (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = context.l10n.t('customer_driver_location_load_failed');
      });
    };
    _socket.onStateChanged = () {
      if (!mounted || generation != _generation) return;
      setState(() => _connected = _socket.connected);
    };
    await _socket.connect(guestAccessToken: widget.guestAccessToken);
    if (!mounted || generation != _generation || !_canLoadLocation) return;
    _socket.subscribeGuest(widget.bookingId);
  }

  Future<void> _load({int? generation}) async {
    final expectedGeneration = generation ?? _generation;
    if (!_canLoadLocation) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.getGuestDriverLocation(
        bookingId: widget.bookingId,
        guestAccessToken: widget.guestAccessToken,
      );
      if (!mounted || expectedGeneration != _generation) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } catch (err) {
      if (!mounted || expectedGeneration != _generation) return;
      setState(() {
        _loading = false;
        _error = userFacingError(
          err,
          fallback: context.l10n.t('customer_driver_location_load_failed'),
        );
      });
    }
  }

  void _startStaleTimer(int generation) {
    _staleTimer?.cancel();
    _staleTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || generation != _generation) return;
      setState(() {});
    });
  }

  bool _isOlderOrSame(String? next, String? current) {
    if (next == null || current == null) return false;
    final nextTime = DateTime.tryParse(next)?.toUtc();
    final currentTime = DateTime.tryParse(current)?.toUtc();
    if (nextTime == null || currentTime == null) return false;
    return !nextTime.isAfter(currentTime);
  }

  bool _isStale(DriverLocation? driver) {
    final value = driver?.recordedAt ?? driver?.lastSeenAt;
    if (value == null) return true;
    final time = DateTime.tryParse(value)?.toUtc();
    if (time == null) return true;
    return DateTime.now().toUtc().difference(time) > _freshLocation;
  }

  String _statusMessage(AppLocalizations l10n) {
    switch (widget.bookingStatus) {
      case 'DRIVER_ASSIGNED':
        return l10n.t('customer_driver_location_waiting');
      case 'ON_ROUTE':
        return l10n.t('customer_driver_on_route');
      case 'DRIVER_ARRIVED':
        return l10n.t('customer_driver_arrived');
      case 'PICKED_UP':
        return l10n.t('customer_trip_in_progress');
      default:
        return l10n.t('customer_driver_location_ended');
    }
  }

  String _updatedLabel(AppLocalizations l10n, DriverLocation driver) {
    final raw = driver.recordedAt ?? driver.lastSeenAt;
    final updatedAt = raw == null ? null : DateTime.tryParse(raw)?.toLocal();
    if (updatedAt == null) return l10n.t('customer_driver_location_stale');
    final minutes = DateTime.now().difference(updatedAt).inMinutes;
    if (minutes <= 0) return l10n.t('customer_driver_location_updated_now');
    return l10n
        .t('customer_driver_location_updated_minutes')
        .replaceAll('{minutes}', '$minutes');
  }

  Future<void> _openExternalMap(DriverLocation driver) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${driver.latitude},${driver.longitude}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();

    final l10n = context.l10n;
    final driver = _result?.driver;
    final hasLocation = _result?.available == true && driver != null;
    final stale = hasLocation && _isStale(driver);

    return AppUi.surfaceCard(
      backgroundColor: hasLocation
          ? (stale ? AppTokens.warningLight : AppTokens.successLight)
          : AppTokens.infoLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                hasLocation ? Icons.local_taxi : Icons.location_searching,
                color: hasLocation
                    ? (stale ? AppTokens.warning : AppTokens.success)
                    : AppTokens.info,
              ),
              const SizedBox(width: AppTokens.spaceSm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('customer_driver_location_title'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _statusMessage(l10n),
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _connected ? Icons.cloud_done : Icons.cloud_off,
                color: _connected ? AppTokens.success : AppTokens.textMuted,
                size: 18,
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: AppTokens.spaceMd),
            const LinearProgressIndicator(),
          ] else if (_error != null) ...[
            const SizedBox(height: AppTokens.spaceMd),
            AppUi.errorState(
              message: l10n.t('customer_driver_location_load_failed'),
              onRetry: _canLoadLocation ? () => _load() : null,
              retryLabel: l10n.t('customer_driver_location_retry'),
            ),
          ] else if (!hasLocation) ...[
            if (widget.bookingStatus != 'DRIVER_ASSIGNED') ...[
              const SizedBox(height: AppTokens.spaceMd),
              Text(
                l10n.t('customer_driver_location_temporarily_unavailable'),
                style: const TextStyle(color: AppTokens.textSecondary),
              ),
            ],
          ] else ...[
            const SizedBox(height: AppTokens.spaceMd),
            DriverLocationMap(locations: [driver], height: 220),
            const SizedBox(height: AppTokens.spaceMd),
            AppUi.summaryRow(
              label: l10n.t('guest_lookup_driver'),
              value: driver.displayName,
              emphasize: true,
            ),
            if (driver.vehicle?.trim().isNotEmpty == true)
              AppUi.summaryRow(
                label: l10n.t('vehicle'),
                value: driver.vehicle!,
              ),
            AppUi.summaryRow(
              label: l10n.t('status'),
              value: stale
                  ? l10n.t('customer_driver_location_stale')
                  : l10n.t('customer_driver_location_live'),
            ),
            AppUi.summaryRow(
              label: l10n.t('customer_driver_location_updated_label'),
              value: _updatedLabel(l10n, driver),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () => _openExternalMap(driver),
                icon: const Icon(Icons.map_outlined),
                label: Text(l10n.t('customer_driver_location_open_map')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
