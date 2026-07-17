import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../utils/user_facing_error.dart';
import '../services/driver_location_api_service.dart';

typedef DriverPositionProvider = Future<Position> Function();

enum DriverLocationSharingState {
  idle,
  starting,
  sharing,
  temporarilyUnavailable,
  permissionDenied,
  serviceDisabled,
  stopped,
}

enum _LocationFailureKind {
  permissionDenied,
  serviceDisabled,
  authError,
  noActiveAssignment,
  invalidTripStatus,
  temporaryNetworkError,
  unknown,
}

class DriverLiveLocationControl extends StatefulWidget {
  const DriverLiveLocationControl({
    super.key,
    required this.hasActiveJob,
    this.api,
    this.online,
    this.bookingNumber,
    this.bookingStatus,
    this.positionProvider,
    this.interval = const Duration(seconds: 15),
  });

  final bool hasActiveJob;
  final DriverLocationApiService? api;
  final bool? online;
  final String? bookingNumber;
  final String? bookingStatus;
  final DriverPositionProvider? positionProvider;
  final Duration interval;

  @override
  State<DriverLiveLocationControl> createState() =>
      _DriverLiveLocationControlState();
}

class _DriverLiveLocationControlState extends State<DriverLiveLocationControl> {
  static _DriverLiveLocationControlState? _activeController;

  Timer? _timer;
  Timer? _retryTimer;
  bool _enabled = false;
  bool _sending = false;
  String? _error;
  DateTime? _lastSentAt;
  String? _boundBookingNumber;
  DriverLocationSharingState _state = DriverLocationSharingState.idle;
  int _retryAttempt = 0;
  int _lifecycleGeneration = 0;

  static const _autoStartStatuses = {'ON_ROUTE', 'DRIVER_ARRIVED', 'PICKED_UP'};

  static const _stopStatuses = {
    'SETTLEMENT_PENDING',
    'COMPLETED',
    'CANCELLED',
    'NO_SHOW',
  };

  bool get _shouldAutoStart =>
      widget.hasActiveJob && _autoStartStatuses.contains(widget.bookingStatus);

  bool get _isAssignedOnly => widget.bookingStatus == 'DRIVER_ASSIGNED';

  bool get _shouldStop =>
      !widget.hasActiveJob ||
      widget.bookingStatus == null ||
      _stopStatuses.contains(widget.bookingStatus);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncLifecycle());
  }

  @override
  void didUpdateWidget(covariant DriverLiveLocationControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingNumber != widget.bookingNumber && _enabled) {
      _stop(invalidate: true);
    }
    if (oldWidget.hasActiveJob != widget.hasActiveJob ||
        oldWidget.bookingNumber != widget.bookingNumber ||
        oldWidget.bookingStatus != widget.bookingStatus ||
        oldWidget.online != widget.online) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncLifecycle());
    }
  }

  @override
  void dispose() {
    _lifecycleGeneration += 1;
    _timer?.cancel();
    _retryTimer?.cancel();
    if (_activeController == this) {
      _activeController = null;
    }
    super.dispose();
  }

  Future<void> _syncLifecycle() async {
    if (!mounted) return;
    if (_shouldStop) {
      if (_enabled || _state != DriverLocationSharingState.idle) {
        _stop(stoppedByLifecycle: true, invalidate: true);
      }
      return;
    }
    if (_shouldAutoStart) {
      await _start(auto: true);
    }
  }

  Future<void> _start({bool auto = false}) async {
    if (!widget.hasActiveJob || !_shouldAutoStart) return;
    if (_enabled && _boundBookingNumber == widget.bookingNumber) {
      return;
    }
    if (widget.online != true) {
      if (widget.online != false) return;
      if (_state == DriverLocationSharingState.temporarilyUnavailable &&
          _error == context.l10n.t('driver_live_location_online_required')) {
        return;
      }
      setState(() {
        _enabled = false;
        _state = DriverLocationSharingState.temporarilyUnavailable;
        _error = context.l10n.t('driver_live_location_online_required');
      });
      return;
    }
    _activeController?._stop(invalidate: true);
    _activeController = this;
    _lifecycleGeneration += 1;
    final generation = _lifecycleGeneration;
    _retryTimer?.cancel();
    _timer?.cancel();
    setState(() {
      _enabled = true;
      _sending = false;
      _state = DriverLocationSharingState.starting;
      _boundBookingNumber = widget.bookingNumber;
      _error = null;
    });
    final sent = await _sendOnce(generation: generation);
    if (!sent || !_isCurrentLifecycle(generation)) return;
    _startPeriodic(generation);
  }

  void _stop({bool stoppedByLifecycle = false, bool invalidate = false}) {
    if (invalidate) _lifecycleGeneration += 1;
    _timer?.cancel();
    _retryTimer?.cancel();
    _timer = null;
    _retryTimer = null;
    if (_activeController == this) {
      _activeController = null;
    }
    if (!mounted) return;
    setState(() {
      _enabled = false;
      _sending = false;
      _retryAttempt = 0;
      _state = stoppedByLifecycle
          ? DriverLocationSharingState.stopped
          : DriverLocationSharingState.idle;
      _boundBookingNumber = null;
    });
  }

  void _startPeriodic(int generation) {
    if (!_isCurrentLifecycle(generation)) return;
    _timer?.cancel();
    _timer = Timer.periodic(widget.interval, (_) {
      if (_isCurrentLifecycle(generation) && !_sending) {
        _sendOnce(generation: generation);
      }
    });
  }

  bool _isCurrentLifecycle(int generation) {
    return mounted &&
        generation == _lifecycleGeneration &&
        _enabled &&
        widget.hasActiveJob &&
        widget.online == true &&
        _boundBookingNumber == widget.bookingNumber &&
        _autoStartStatuses.contains(widget.bookingStatus);
  }

  Future<Position> _getPosition() async {
    if (widget.positionProvider != null) {
      return widget.positionProvider!();
    }
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const DriverLocationApiException(
        'Location services are disabled',
        errorCode: 'LOCATION_SERVICE_DISABLED',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const DriverLocationApiException(
        'Location permission denied',
        errorCode: 'LOCATION_PERMISSION_DENIED',
      );
    }
    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<bool> _sendOnce({required int generation}) async {
    if (_sending || !_isCurrentLifecycle(generation)) return false;
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
      if (!_isCurrentLifecycle(generation)) return false;
      _retryAttempt = 0;
      setState(() {
        _lastSentAt = DateTime.now();
        _sending = false;
        _state = DriverLocationSharingState.sharing;
      });
      return true;
    } catch (err) {
      if (!mounted || generation != _lifecycleGeneration) return false;
      final message = userFacingError(
        err,
        fallback: context.l10n.t('driver_location_error'),
      );
      final fatal = !_canAutoRetry(err);
      setState(() {
        _enabled = !fatal;
        _sending = false;
        _state = _stateForError(err);
        _error = message;
        if (fatal) {
          _boundBookingNumber = null;
        }
      });
      _timer?.cancel();
      _timer = null;
      if (fatal) {
        _retryTimer?.cancel();
        _retryTimer = null;
        _retryAttempt = 0;
        if (_activeController == this) _activeController = null;
      } else {
        _scheduleRetry(err, generation);
      }
      return false;
    }
  }

  DriverLocationSharingState _stateForError(Object err) {
    final kind = _classifyError(err);
    if (kind == _LocationFailureKind.permissionDenied) {
      return DriverLocationSharingState.permissionDenied;
    }
    if (kind == _LocationFailureKind.serviceDisabled) {
      return DriverLocationSharingState.serviceDisabled;
    }
    if (kind == _LocationFailureKind.authError ||
        kind == _LocationFailureKind.noActiveAssignment ||
        kind == _LocationFailureKind.invalidTripStatus) {
      return DriverLocationSharingState.stopped;
    }
    return DriverLocationSharingState.temporarilyUnavailable;
  }

  _LocationFailureKind _classifyError(Object err) {
    if (err is DriverLocationApiException) {
      final code = err.errorCode ?? '';
      if (code == 'LOCATION_PERMISSION_DENIED') {
        return _LocationFailureKind.permissionDenied;
      }
      if (code == 'LOCATION_SERVICE_DISABLED') {
        return _LocationFailureKind.serviceDisabled;
      }
      if (err.statusCode == 401 ||
          code == 'UNAUTHORIZED' ||
          code == 'AUTHENTICATION_REQUIRED') {
        return _LocationFailureKind.authError;
      }
      if (code == 'NO_ACTIVE_ASSIGNMENT') {
        return _LocationFailureKind.noActiveAssignment;
      }
      if (code == 'BOOKING_NOT_TRACKABLE' || code == 'INVALID_TRIP_STATUS') {
        return _LocationFailureKind.invalidTripStatus;
      }
      if (err.statusCode == null || err.statusCode! >= 500) {
        return _LocationFailureKind.temporaryNetworkError;
      }
    }
    final text = err.toString().toLowerCase();
    if (text.contains('permission')) {
      return _LocationFailureKind.permissionDenied;
    }
    if (text.contains('disabled') || text.contains('service')) {
      return _LocationFailureKind.serviceDisabled;
    }
    if (text.contains('log in') || text.contains('auth')) {
      return _LocationFailureKind.authError;
    }
    if (text.contains('no active job') || text.contains('active assignment')) {
      return _LocationFailureKind.noActiveAssignment;
    }
    return _LocationFailureKind.unknown;
  }

  bool _canAutoRetry(Object err) {
    return _classifyError(err) == _LocationFailureKind.temporaryNetworkError ||
        _classifyError(err) == _LocationFailureKind.unknown;
  }

  void _scheduleRetry(Object err, int generation) {
    _retryTimer?.cancel();
    if (!_isCurrentLifecycle(generation) || !_canAutoRetry(err)) return;
    final delays = [5, 15, 30];
    final seconds = delays[_retryAttempt.clamp(0, delays.length - 1)];
    _retryAttempt += 1;
    _retryTimer = Timer(Duration(seconds: seconds), () {
      if (!_isCurrentLifecycle(generation) || _sending) return;
      _sendOnce(generation: generation).then((sent) {
        if (sent && _isCurrentLifecycle(generation)) {
          _startPeriodic(generation);
        }
      });
    });
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

  String _titleKey() {
    return switch (_state) {
      DriverLocationSharingState.starting => 'driver_location_starting',
      DriverLocationSharingState.sharing => 'driver_location_sharing',
      DriverLocationSharingState.temporarilyUnavailable =>
        'driver_location_temporarily_unavailable',
      DriverLocationSharingState.permissionDenied =>
        'driver_location_permission_required',
      DriverLocationSharingState.serviceDisabled =>
        'driver_location_service_disabled',
      DriverLocationSharingState.stopped => 'driver_location_stopped',
      DriverLocationSharingState.idle => 'driver_location_status_title',
    };
  }

  IconData _icon() {
    return switch (_state) {
      DriverLocationSharingState.sharing => Icons.my_location,
      DriverLocationSharingState.starting => Icons.location_searching,
      DriverLocationSharingState.permissionDenied => Icons.location_disabled,
      DriverLocationSharingState.serviceDisabled => Icons.gps_off,
      DriverLocationSharingState.temporarilyUnavailable => Icons.sync_problem,
      _ => Icons.location_on_outlined,
    };
  }

  Color _toneColor() {
    return switch (_state) {
      DriverLocationSharingState.sharing => AppTokens.success,
      DriverLocationSharingState.starting => AppTokens.primary,
      DriverLocationSharingState.permissionDenied ||
      DriverLocationSharingState.serviceDisabled => AppTokens.error,
      DriverLocationSharingState.temporarilyUnavailable => AppTokens.warning,
      _ => AppTokens.textSecondary,
    };
  }

  Color _toneBackground() {
    return switch (_state) {
      DriverLocationSharingState.sharing => AppTokens.successLight,
      DriverLocationSharingState.starting => AppTokens.primaryLight,
      DriverLocationSharingState.permissionDenied ||
      DriverLocationSharingState.serviceDisabled => AppTokens.errorLight,
      DriverLocationSharingState.temporarilyUnavailable =>
        AppTokens.warningLight,
      _ => AppTokens.surface,
    };
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
        backgroundColor: _toneBackground(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(_icon(), color: _toneColor()),
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t(_titleKey()),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: _toneColor(),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _isAssignedOnly
                            ? l10n.t('driver_location_auto_start_guidance')
                            : _lastSentAt == null
                            ? l10n.t('driver_live_location_active_job_only')
                            : _formatLastSent(),
                        style: const TextStyle(
                          color: AppTokens.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
            if (!_enabled && !_isAssignedOnly && _shouldAutoStart) ...[
              const SizedBox(height: AppTokens.spaceSm),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _sending ? null : () => _start(),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.t('driver_location_retry')),
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
