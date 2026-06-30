import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../utils/user_facing_error.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_status.dart';
import '../services/driver_api_service.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({
    super.key,
    this.api,
    this.deviceRegistrationService,
    this.onStatusChanged,
  });

  final DriverApiService? api;
  final NotificationDeviceRegistrationService? deviceRegistrationService;
  final VoidCallback? onStatusChanged;

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ?? NotificationDeviceRegistrationService();
  Future<Map<String, dynamic>>? _ratingFuture;
  Future<DriverStatus>? _statusFuture;
  bool _statusUpdating = false;
  String? _statusError;

  @override
  void initState() {
    super.initState();
    _ratingFuture = _api.getRatingSummary();
    _statusFuture = _api.getStatus();
  }

  void _refreshStatus() {
    setState(() {
      _statusFuture = _api.getStatus();
      _statusError = null;
    });
  }

  Future<void> _setOnlineState(bool online, DriverStatus? current) async {
    if (_statusUpdating) return;
    if (!online && current?.hasActiveJob == true) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Go offline?'),
          content: const Text(
            'You have an active job. Going offline is blocked until the job is finished.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Try anyway')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() {
      _statusUpdating = true;
      _statusError = null;
    });
    try {
      final next = online ? await _api.goOnline() : await _api.goOffline();
      if (!mounted) return;
      setState(() {
        _statusFuture = Future.value(next);
        _statusUpdating = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onStatusChanged?.call();
      });
    } catch (err) {
      if (!mounted) return;
      if (driverIsAuthError(err)) {
        driverHandleApiError(context, err);
        return;
      }
      setState(() {
        _statusUpdating = false;
        _statusError = userFacingError(err, fallback: context.l10n.t('ui_action_failed'));
        _statusFuture = _api.getStatus();
      });
    }
  }

  Future<void> _logout() async {
    try {
      await _deviceRegistration.deactivateAuthenticated(
        accessTokenLoader: _api.getSavedToken,
      );
    } catch (_) {
      // Push cleanup is best effort; never block logout.
    }
    await _api.logout();
    if (!mounted) return;
    driverRedirectToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_nav_profile'))),
      body: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _ratingFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return AppUi.surfaceCard(
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppTokens.spaceMd),
                      Text(l10n.t('driver_rating_error').replaceAll('Could not load ', 'Loading ')),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                return AppUi.surfaceCard(
                  backgroundColor: AppTokens.errorLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.t('driver_rating_error'),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(snapshot.error.toString()),
                    ],
                  ),
                );
              }
              final rating = snapshot.data ?? {};
              final avg = rating['averageRating'];
              final count = rating['reviewCount'] ?? 0;
              return AppUi.surfaceCard(
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTokens.warningLight,
                        borderRadius: AppTokens.borderRadiusSm,
                      ),
                      child: const Icon(Icons.star, color: AppTokens.warning, size: 28),
                    ),
                    const SizedBox(width: AppTokens.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            avg == null
                                ? l10n.t('driver_no_ratings')
                                : '$avg ${l10n.t('driver_rating_average')}',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text('$count ${l10n.t('driver_rating_count')}'),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppTokens.spaceMd),
          FutureBuilder<DriverStatus>(
            future: _statusFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return AppUi.surfaceCard(
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: AppTokens.spaceMd),
                      const Expanded(child: Text('Loading driver status')),
                    ],
                  ),
                );
              }
              if (snapshot.hasError) {
                return AppUi.surfaceCard(
                  backgroundColor: AppTokens.errorLight,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline, color: AppTokens.error),
                          const SizedBox(width: AppTokens.spaceSm),
                          const Expanded(
                            child: Text(
                              'Driver status unavailable',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            onPressed: _refreshStatus,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      Text(snapshot.error.toString()),
                    ],
                  ),
                );
              }
              final status = snapshot.data;
              final online = status?.online == true;
              return AppUi.surfaceCard(
                backgroundColor: online ? AppTokens.successLight : AppTokens.surfaceMuted,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          online ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                          color: online ? AppTokens.success : AppTokens.textMuted,
                          size: 28,
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                online ? 'Online' : 'Offline',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                status?.status ?? 'OFFLINE',
                                style: const TextStyle(color: AppTokens.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (status?.hasActiveJob == true) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      AppUi.surfaceCard(
                        backgroundColor: AppTokens.warningLight,
                        padding: const EdgeInsets.all(AppTokens.spaceSm),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: AppTokens.warning, size: 18),
                            SizedBox(width: AppTokens.spaceSm),
                            Expanded(
                              child: Text(
                                l10n.t('driver_active_job_stay_online'),
                                style: TextStyle(
                                  color: AppTokens.warning,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (status?.lastSeenAt != null) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        'Last seen ${status!.lastSeenAt}',
                        style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13),
                      ),
                    ],
                    if (_statusError != null) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      Text(
                        _statusError!,
                        style: const TextStyle(color: AppTokens.error),
                      ),
                    ],
                    if (_statusUpdating) ...[
                      const SizedBox(height: AppTokens.spaceSm),
                      const LinearProgressIndicator(),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: FilledButton(
                              onPressed: _statusUpdating || online
                                  ? null
                                  : () => _setOnlineState(true, status),
                              child: const Text('Go online'),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppTokens.spaceSm),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton(
                              onPressed: _statusUpdating || !online
                                  ? null
                                  : () => _setOnlineState(false, status),
                              child: const Text('Go offline'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: Text(l10n.t('driver_logout')),
            ),
          ),
        ],
      ),
    );
  }
}
