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
  static const _terminalStatuses = {
    'SETTLEMENT_PENDING',
    'COMPLETED',
    'CANCELLED',
    'NO_SHOW',
  };
  static const _freshLocation = Duration(seconds: 60);
  static const _statusPollingInterval = Duration(seconds: 15);

  late final DriverLocationApiService _api =
      widget.api ?? DriverLocationApiService();
  late final DriverLocationSocketService _socket =
      widget.socket ?? DriverLocationSocketService();

  Timer? _statusPollingTimer;
  Timer? _staleTimer;
  late String _currentBookingStatus;
  late String _currentGuestAccessToken;
  bool _loading = false;
  bool _connected = false;
  bool _locationLifecycleStarted = false;
  bool _refreshInFlight = false;
  String? _error;
  GuestDriverLocationResult? _result;
  int _generation = 0;

  bool get _visible => _visibleStatuses.contains(_currentBookingStatus);

  bool get _terminal => _terminalStatuses.contains(_currentBookingStatus);

  bool get _canLoadLocation =>
      _locationStatuses.contains(_currentBookingStatus) &&
      _currentGuestAccessToken.trim().isNotEmpty;

  bool get _canPollStatus =>
      _visible && _currentGuestAccessToken.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _currentBookingStatus = widget.bookingStatus;
    _currentGuestAccessToken = widget.guestAccessToken;
    _syncLifecycle();
  }

  @override
  void didUpdateWidget(covariant GuestDriverTrackingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId ||
        oldWidget.guestAccessToken != widget.guestAccessToken ||
        oldWidget.bookingStatus != widget.bookingStatus) {
      _generation += 1;
      _currentBookingStatus = widget.bookingStatus;
      _currentGuestAccessToken = widget.guestAccessToken;
      _resetLocationLifecycle();
      _statusPollingTimer?.cancel();
      _syncLifecycle();
    }
  }

  @override
  void dispose() {
    _generation += 1;
    _statusPollingTimer?.cancel();
    _resetLocationLifecycle();
    super.dispose();
  }

  void _syncLifecycle() {
    if (_terminal) {
      _enterTerminalState();
      return;
    }
    if (!_visible) {
      _loading = false;
      _result = null;
      _error = null;
      _statusPollingTimer?.cancel();
      _resetLocationLifecycle();
      return;
    }
    _startStatusPolling();
    if (!_canLoadLocation) {
      _loading = false;
      _result = const GuestDriverLocationResult(
        available: false,
        reason: 'WAITING_FOR_DRIVER',
      );
      _resetLocationLifecycle();
      return;
    }
    if (_locationLifecycleStarted) return;
    _locationLifecycleStarted = true;
    final generation = _generation;
    _connectSocket(generation: generation);
    _startStaleTimer(generation);
  }

  void _resetLocationLifecycle() {
    _locationLifecycleStarted = false;
    _staleTimer?.cancel();
    _staleTimer = null;
    _socket.disconnect();
    _connected = false;
  }

  void _enterTerminalState() {
    _generation += 1;
    _statusPollingTimer?.cancel();
    _statusPollingTimer = null;
    _resetLocationLifecycle();
    if (mounted) {
      setState(() {
        _loading = false;
        _error = null;
        _result = null;
      });
    } else {
      _loading = false;
      _error = null;
      _result = null;
    }
  }

  void _startStatusPolling() {
    if (!_canPollStatus || _statusPollingTimer != null) return;
    final generation = _generation;
    _refreshTrackingSnapshot(generation: generation);
    _statusPollingTimer = Timer.periodic(_statusPollingInterval, (_) {
      _refreshTrackingSnapshot(generation: generation);
    });
  }

  Future<void> _refreshTrackingSnapshot({required int generation}) async {
    if (!mounted || generation != _generation || !_canPollStatus) return;
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    if (_canLoadLocation && _result == null) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final result = await _api.getGuestDriverLocation(
        bookingId: widget.bookingId,
        guestAccessToken: _currentGuestAccessToken,
      );
      if (!mounted || generation != _generation) return;
      _applyTrackingSnapshot(result);
    } on DriverLocationApiException catch (err) {
      if (!mounted || generation != _generation) return;
      if (_isAuthorizationError(err)) {
        _generation += 1;
        _statusPollingTimer?.cancel();
        _statusPollingTimer = null;
        _resetLocationLifecycle();
        setState(() {
          _loading = false;
          _result = null;
          _error = userFacingError(
            err,
            fallback: context.l10n.t('customer_driver_location_load_failed'),
          );
        });
      } else if (_result == null && _canLoadLocation) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
    } catch (_) {
      if (!mounted || generation != _generation) return;
      if (_result == null && _canLoadLocation) {
        setState(() => _loading = false);
      }
      // Temporary network errors should not tear down the current marker.
      // The next polling tick can recover without rotating the guest token.
    } finally {
      _refreshInFlight = false;
    }
  }

  bool _isAuthorizationError(DriverLocationApiException err) {
    return err.statusCode == 401 ||
        err.statusCode == 403 ||
        err.errorCode == 'UNAUTHORIZED' ||
        err.errorCode == 'AUTH_REQUIRED' ||
        err.errorCode == 'AUTH_INVALID' ||
        err.errorCode == 'TOKEN_EXPIRED' ||
        err.errorCode == 'BOOKING_NOT_ACCESSIBLE';
  }

  void _applyTrackingSnapshot(GuestDriverLocationResult result) {
    final nextStatus = result.bookingStatus ?? _currentBookingStatus;
    final wasLocationActive = _canLoadLocation;
    final statusChanged = nextStatus != _currentBookingStatus;

    if (_terminalStatuses.contains(nextStatus)) {
      _currentBookingStatus = nextStatus;
      _enterTerminalState();
      return;
    }

    _currentBookingStatus = nextStatus;

    setState(() {
      _loading = false;
      _error = null;
      if (!_canLoadLocation) {
        _result = const GuestDriverLocationResult(
          available: false,
          reason: 'WAITING_FOR_DRIVER',
        );
      } else if (result.available == true && result.driver != null) {
        final currentRecordedAt = _result?.driver?.recordedAt;
        final nextRecordedAt = result.driver?.recordedAt;
        if (!_isOlderOrSame(nextRecordedAt, currentRecordedAt)) {
          _result = result;
        }
      } else if (_result == null || statusChanged) {
        _result = result;
      }
    });

    if (statusChanged || wasLocationActive != _canLoadLocation) {
      _syncLifecycle();
    }
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
    _socket.onError = (payload) {
      if (!mounted || generation != _generation) return;
      final code = payload['code']?.toString();
      if (code == 'BOOKING_NOT_TRACKABLE' || code == 'LOCATION_UNAVAILABLE') {
        setState(() {
          _loading = false;
          _error = null;
          _result = const GuestDriverLocationResult(
            available: false,
            reason: 'WAITING_FOR_DRIVER',
          );
        });
        return;
      }
      if (code == 'BOOKING_NOT_ACCESSIBLE' ||
          code == 'UNAUTHORIZED' ||
          code == 'AUTH_REQUIRED' ||
          code == 'AUTH_INVALID' ||
          code == 'TOKEN_EXPIRED') {
        _generation += 1;
        _statusPollingTimer?.cancel();
        _statusPollingTimer = null;
        _resetLocationLifecycle();
      }
      setState(() {
        _error = context.l10n.t('customer_driver_location_load_failed');
      });
    };
    _socket.onStateChanged = () {
      if (!mounted || generation != _generation) return;
      setState(() => _connected = _socket.connected);
    };
    await _socket.connect(guestAccessToken: _currentGuestAccessToken);
    if (!mounted || generation != _generation || !_canLoadLocation) return;
    _socket.subscribeGuest(widget.bookingId);
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
    switch (_currentBookingStatus) {
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
              onRetry: _canPollStatus
                  ? () => _refreshTrackingSnapshot(generation: _generation)
                  : null,
              retryLabel: l10n.t('customer_driver_location_retry'),
            ),
          ] else if (!hasLocation) ...[
            if (_currentBookingStatus != 'DRIVER_ASSIGNED') ...[
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
