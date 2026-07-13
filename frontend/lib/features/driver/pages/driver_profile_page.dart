import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../driver_auth.dart';
import '../services/driver_api_service.dart';
import '../widgets/driver_status_control.dart';

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
      widget.deviceRegistrationService ??
      NotificationDeviceRegistrationService();
  Future<Map<String, dynamic>>? _ratingFuture;

  @override
  void initState() {
    super.initState();
    _ratingFuture = _api.getRatingSummary();
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
                      Text(l10n.t('driver_rating_loading')),
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
                      child: const Icon(
                        Icons.star,
                        color: AppTokens.warning,
                        size: 28,
                      ),
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
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
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
          DriverStatusControl(
            api: _api,
            onStatusChanged: widget.onStatusChanged,
            padding: EdgeInsets.zero,
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
