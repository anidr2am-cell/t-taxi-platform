import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_status.dart';
import '../pages/driver_profile_page.dart';
import '../pages/driver_support_page.dart';
import '../services/driver_api_service.dart';

class DriverAccountPage extends StatefulWidget {
  const DriverAccountPage({
    super.key,
    this.api,
    this.settlementApi,
    this.deviceRegistrationService,
    this.onStatusChanged,
  });

  final DriverApiService? api;
  final DriverSettlementApiService? settlementApi;
  final NotificationDeviceRegistrationService? deviceRegistrationService;
  final VoidCallback? onStatusChanged;

  @override
  State<DriverAccountPage> createState() => _DriverAccountPageState();
}

class _DriverAccountPageState extends State<DriverAccountPage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  late final DriverSettlementApiService _settlementApi =
      widget.settlementApi ?? const DriverSettlementApiService();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ??
      NotificationDeviceRegistrationService();
  Future<Map<String, dynamic>>? _ratingFuture;
  Future<DriverStatus>? _statusFuture;
  Future<String?>? _nameFuture;
  Future<int>? _pendingSettlementFuture;
  bool _enablingNotifications = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    setState(() {
      _ratingFuture = _api.getRatingSummary();
      _statusFuture = _api.getStatus();
      _nameFuture = _api.getDriverDisplayName();
      _pendingSettlementFuture = _settlementApi.listSettlements().then(
        DriverUx.countPendingSettlements,
      );
    });
  }

  Future<void> _logout() async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('driver_logout_confirm_title')),
        content: Text(l10n.t('driver_logout_confirm_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.t('driver_confirm_no')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.t('driver_logout')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _deviceRegistration.deactivateAuthenticated(
        accessTokenLoader: _api.getSavedToken,
      );
    } catch (_) {}
    await _api.logout();
    if (!mounted) return;
    driverRedirectToLogin(context);
  }

  Future<void> _enableNotifications() async {
    if (_enablingNotifications) return;
    setState(() => _enablingNotifications = true);
    final result = await _deviceRegistration.enableAuthenticated(
      accessTokenLoader: _api.getSavedToken,
    );
    if (!mounted) return;
    setState(() => _enablingNotifications = false);
    final message = switch (result.status) {
      NotificationDeviceRegistrationStatus.registered =>
        context.l10n.t('driver_notification_enabled'),
      NotificationDeviceRegistrationStatus.permissionDenied =>
        context.l10n.t('driver_notification_denied'),
      NotificationDeviceRegistrationStatus.unsupported =>
        context.l10n.t('driver_notification_unsupported'),
      NotificationDeviceRegistrationStatus.configMissing =>
        context.l10n.t('driver_notification_unconfigured'),
      NotificationDeviceRegistrationStatus.failed =>
        result.message ?? context.l10n.t('driver_notification_failed'),
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _openLanguagePicker() {
    final locale = context.read<LocaleState>();
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              child: Text(
                context.l10n.t('driver_account_language'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ...AppLocalizations.supportedLanguages.map((code) {
              final selected = locale.languageCode == code;
              return ListTile(
                leading: selected
                    ? const Icon(Icons.check, color: AppTokens.success)
                    : const Icon(Icons.language),
                title: Text(AppLocalizations.languageNames[code] ?? code),
                onTap: () {
                  context.read<LocaleState>().setLanguage(code);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_nav_account'))),
      body: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          _AccountHeader(
            nameFuture: _nameFuture,
            statusFuture: _statusFuture,
            ratingFuture: _ratingFuture,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _AccountMenuTile(
            icon: Icons.receipt_long_outlined,
            title: l10n.t('driver_account_settlement'),
            badgeFuture: _pendingSettlementFuture,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DriverSettlementListPage(api: _settlementApi),
              ),
            ),
          ),
          _AccountMenuTile(
            icon: Icons.support_agent_outlined,
            title: l10n.t('driver_account_support'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DriverSupportPage()),
            ),
          ),
          _AccountMenuTile(
            icon: Icons.person_outline,
            title: l10n.t('driver_account_profile'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DriverProfilePage(
                  api: _api,
                  deviceRegistrationService: _deviceRegistration,
                  onStatusChanged: widget.onStatusChanged,
                ),
              ),
            ),
          ),
          _AccountMenuTile(
            icon: Icons.language_outlined,
            title: l10n.t('driver_account_language'),
            onTap: _openLanguagePicker,
          ),
          _AccountMenuTile(
            icon: Icons.notifications_outlined,
            title: l10n.t('driver_account_notification_settings'),
            onTap: _enablingNotifications ? null : _enableNotifications,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          SizedBox(
            height: 52,
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

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.nameFuture,
    required this.statusFuture,
    required this.ratingFuture,
  });

  final Future<String?>? nameFuture;
  final Future<DriverStatus>? statusFuture;
  final Future<Map<String, dynamic>>? ratingFuture;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AppUi.surfaceCard(
      child: Column(
        children: [
          FutureBuilder<String?>(
            future: nameFuture,
            builder: (context, nameSnapshot) {
              final name = nameSnapshot.data?.trim();
              return Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppTokens.primaryLight,
                    child: Text(
                      _initials(name),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTokens.primary,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppTokens.spaceMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name == null || name.isEmpty
                              ? l10n.t('driver_nav_account')
                              : name,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        FutureBuilder<DriverStatus>(
                          future: statusFuture,
                          builder: (context, statusSnapshot) {
                            final online = statusSnapshot.data?.online == true;
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: AppUi.statusBadge(
                                online
                                    ? l10n.t('driver_online')
                                    : l10n.t('driver_offline'),
                                tone: online
                                    ? AppStatusTone.success
                                    : AppStatusTone.neutral,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppTokens.spaceMd),
          FutureBuilder<Map<String, dynamic>>(
            future: ratingFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return Text(l10n.t('driver_rating_loading'));
              }
              if (snapshot.hasError) {
                return Text(
                  l10n.t('driver_rating_error'),
                  style: const TextStyle(color: AppTokens.error),
                );
              }
              final rating = snapshot.data ?? {};
              final avg = rating['averageRating'];
              final count = rating['reviewCount'] ?? 0;
              return Row(
                children: [
                  const Icon(Icons.star, color: AppTokens.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      avg == null
                          ? l10n.t('driver_no_ratings')
                          : '$avg · $count ${l10n.t('driver_rating_count')}',
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
        .toUpperCase();
  }
}

class _AccountMenuTile extends StatelessWidget {
  const _AccountMenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.badgeFuture,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final Future<int>? badgeFuture;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, color: AppTokens.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (badgeFuture != null)
            FutureBuilder<int>(
              future: badgeFuture,
              builder: (context, snapshot) {
                final count = snapshot.data ?? 0;
                if (count <= 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(right: AppTokens.spaceSm),
                  child: Badge(label: Text('$count')),
                );
              },
            ),
          const Icon(Icons.chevron_right, color: AppTokens.textMuted),
        ],
      ),
      onTap: onTap,
    );
  }
}
