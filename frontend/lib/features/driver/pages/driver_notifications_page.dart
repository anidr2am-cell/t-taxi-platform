import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../utils/user_facing_error.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../pages/driver_booking_detail_page.dart';
import '../pages/driver_chat_page.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../../driver_settlement/services/driver_settlement_api_service.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../services/driver_api_service.dart';

class DriverNotificationsPage extends StatefulWidget {
  const DriverNotificationsPage({
    super.key,
    this.api,
    this.deviceRegistrationService,
    this.chatPageBuilder,
    this.detailPageBuilder,
    this.showAppBar = true,
  });

  final DriverApiService? api;
  final NotificationDeviceRegistrationService? deviceRegistrationService;
  final Widget Function(String bookingNumber)? chatPageBuilder;
  final Widget Function(String bookingNumber)? detailPageBuilder;
  final bool showAppBar;

  @override
  State<DriverNotificationsPage> createState() =>
      _DriverNotificationsPageState();
}

class _DriverNotificationsPageState extends State<DriverNotificationsPage> {
  late final DriverApiService _api = widget.api ?? const DriverApiService();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ??
      NotificationDeviceRegistrationService();
  bool _loading = true;
  bool _markingAll = false;
  bool _enablingNotifications = false;
  String? _error;
  String? _pushStatus;
  List<dynamic> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.listNotifications();
      setState(() {
        _items = DriverUx.sortNotifications(
          data['items'] as List<dynamic>? ?? [],
        );
        _loading = false;
      });
    } catch (err) {
      if (driverIsAuthError(err) && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) driverHandleApiError(context, err);
        });
      }
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_load_failed'),
        );
        _loading = false;
      });
    }
  }

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _api.markAllNotificationsRead();
      await _load();
    } catch (err) {
      setState(
        () => _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_action_failed'),
        ),
      );
    } finally {
      setState(() => _markingAll = false);
    }
  }

  Future<void> _markRead(int id) async {
    try {
      await _api.markNotificationRead(id);
      await _load();
    } catch (err) {
      setState(
        () => _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_action_failed'),
        ),
      );
    }
  }

  Future<void> _enableNotifications() async {
    if (_enablingNotifications) return;
    setState(() {
      _enablingNotifications = true;
      _pushStatus = null;
    });
    final result = await _deviceRegistration.enableAuthenticated(
      accessTokenLoader: _api.getSavedToken,
    );
    setState(() {
      _pushStatus = _messageForPushResult(result);
      _enablingNotifications = false;
    });
  }

  String _messageForPushResult(NotificationDeviceRegistrationResult result) {
    switch (result.status) {
      case NotificationDeviceRegistrationStatus.registered:
        return context.l10n.t('driver_notification_enabled');
      case NotificationDeviceRegistrationStatus.permissionDenied:
        return context.l10n.t('driver_notification_denied');
      case NotificationDeviceRegistrationStatus.unsupported:
        return context.l10n.t('driver_notification_unsupported');
      case NotificationDeviceRegistrationStatus.configMissing:
        return context.l10n.t('driver_notification_unconfigured');
      case NotificationDeviceRegistrationStatus.failed:
        return result.message ?? context.l10n.t('driver_notification_failed');
    }
  }

  void _openTarget(Map<String, dynamic> item) {
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    final bookingNumber = payload['bookingNumber'] as String?;
    final type = item['notificationType'] as String? ?? '';
    final category = item['category'] as String? ?? '';
    final action = item['action'] as String? ?? '';
    final deepLink = item['deepLink'] as String? ?? '';

    if (bookingNumber != null && bookingNumber.isNotEmpty) {
      if (_isChatNotification(
        type: type,
        category: category,
        action: action,
        deepLink: deepLink,
        payload: payload,
      )) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _buildChatPage(bookingNumber)),
        );
        return;
      }
      if (type.contains('COMMISSION') ||
          type.contains('RECEIPT') ||
          type.contains('SETTLEMENT')) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DriverSettlementDetailPage(
              bookingNumber: bookingNumber,
              api: const DriverSettlementApiService(),
            ),
          ),
        );
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => _buildDetailPage(bookingNumber)),
        );
      }
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.t('driver_notification_no_target'))),
    );
  }

  bool _isChatNotification({
    required String type,
    required String category,
    required String action,
    required String deepLink,
    required Map<String, dynamic> payload,
  }) {
    final candidates = [
      type,
      category,
      action,
      deepLink,
      payload['type'] as String? ?? '',
      payload['category'] as String? ?? '',
      payload['action'] as String? ?? '',
      payload['deepLink'] as String? ?? '',
    ].map((value) => value.toUpperCase()).join(' ');
    return candidates.contains('CHAT') || candidates.contains('MESSAGE');
  }

  String _typeBadgeLabel(Map<String, dynamic> item, AppLocalizations l10n) {
    final payload = Map<String, dynamic>.from(item['payload'] as Map? ?? {});
    final type = item['notificationType'] as String? ?? '';
    final category = item['category'] as String? ?? '';
    final action = item['action'] as String? ?? '';
    final deepLink = item['deepLink'] as String? ?? '';
    final candidates = [
      type,
      category,
      action,
      deepLink,
      payload['type'] as String? ?? '',
      payload['category'] as String? ?? '',
      payload['action'] as String? ?? '',
      payload['deepLink'] as String? ?? '',
    ].map((value) => value.toUpperCase()).join(' ');

    if (candidates.contains('CHAT') || candidates.contains('MESSAGE')) {
      return l10n.t('notification_type_chat');
    }
    if (candidates.contains('COMMISSION') ||
        candidates.contains('RECEIPT') ||
        candidates.contains('SETTLEMENT')) {
      return l10n.t('notification_type_settlement');
    }
    if (candidates.contains('PICKUP')) {
      return l10n.t('notification_type_pickup');
    }
    final bookingNumber = payload['bookingNumber'] as String?;
    if (bookingNumber != null && bookingNumber.isNotEmpty) {
      return l10n.t('notification_type_booking');
    }
    return l10n.t('notification_type_system');
  }

  Widget _buildChatPage(String bookingNumber) {
    return widget.chatPageBuilder?.call(bookingNumber) ??
        DriverChatPage(
          bookingNumber: bookingNumber,
          bookingDetailPageBuilder: _buildDetailPage,
        );
  }

  Widget _buildDetailPage(String bookingNumber) {
    return widget.detailPageBuilder?.call(bookingNumber) ??
        DriverBookingDetailPage(
          bookingNumber: bookingNumber,
          api: _api,
          showStatusControl: true,
        );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(l10n.t('driver_nav_notifications')),
              actions: [
                IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
                IconButton(
                  onPressed: _enablingNotifications ? null : _enableNotifications,
                  icon: const Icon(Icons.notifications_active_outlined),
                  tooltip: l10n.t('driver_notification_enable'),
                ),
                IconButton(
                  onPressed: _markingAll ? null : _markAll,
                  icon: const Icon(Icons.done_all),
                  tooltip: l10n.t('driver_mark_all_read'),
                ),
              ],
            )
          : null,
      body: _loading
          ? AppUi.loadingState()
          : _error != null
          ? AppUi.errorState(
              message: _error!,
              onRetry: _load,
              retryLabel: l10n.t('driver_retry'),
            )
          : Column(
              children: [
                if (_pushStatus != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppTokens.spaceMd,
                      AppTokens.spaceSm,
                      AppTokens.spaceMd,
                      0,
                    ),
                    child: AppUi.surfaceCard(
                      backgroundColor: AppTokens.infoLight,
                      padding: const EdgeInsets.all(AppTokens.spaceSm),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.info_outline,
                            color: AppTokens.info,
                            size: 18,
                          ),
                          const SizedBox(width: AppTokens.spaceSm),
                          Expanded(child: Text(_pushStatus!)),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: _items.isEmpty
                      ? AppUi.emptyState(
                          title: l10n.t('driver_notifications_empty'),
                          icon: Icons.notifications_none_outlined,
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.separated(
                            padding: AppUi.pagePadding(context),
                            itemCount: _items.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: AppTokens.spaceSm),
                            itemBuilder: (context, index) {
                              final item = Map<String, dynamic>.from(
                                _items[index] as Map,
                              );
                              final read = item['read'] == true;
                              final payload = Map<String, dynamic>.from(
                                item['payload'] as Map? ?? {},
                              );
                              final bookingNumber =
                                  payload['bookingNumber'] as String?;
                              final createdAt =
                                  item['createdAt'] as String? ?? '';
                              return _NotificationCard(
                                title:
                                    item['title'] as String? ??
                                    l10n.t('driver_notification_default'),
                                body: item['body'] as String? ?? '',
                                typeLabel: _typeBadgeLabel(item, l10n),
                                bookingNumber: bookingNumber,
                                createdAt: createdAt,
                                read: read,
                                markReadLabel: l10n.t(
                                  'driver_notification_mark_read',
                                ),
                                newBadgeLabel: l10n.t(
                                  'driver_notification_new',
                                ),
                                onMarkRead: read
                                    ? null
                                    : () => _markRead(
                                        item['notificationId'] as int,
                                      ),
                                onTap: () {
                                  if (!read) {
                                    _markRead(item['notificationId'] as int);
                                  }
                                  _openTarget(item);
                                },
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.title,
    required this.body,
    required this.typeLabel,
    required this.read,
    required this.onTap,
    required this.markReadLabel,
    required this.newBadgeLabel,
    this.bookingNumber,
    this.createdAt = '',
    this.onMarkRead,
  });

  final String title;
  final String body;
  final String typeLabel;
  final bool read;
  final VoidCallback onTap;
  final String markReadLabel;
  final String newBadgeLabel;
  final String? bookingNumber;
  final String createdAt;
  final VoidCallback? onMarkRead;

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      onTap: onTap,
      backgroundColor: read ? AppTokens.surface : AppTokens.primaryLight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: read
                  ? AppTokens.surfaceMuted
                  : AppTokens.primary.withValues(alpha: 0.12),
              borderRadius: AppTokens.borderRadiusSm,
            ),
            child: Icon(
              Icons.notifications_outlined,
              color: read ? AppTokens.textMuted : AppTokens.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: AppTokens.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: TextStyle(
                          fontWeight: read ? FontWeight.w600 : FontWeight.w800,
                          color: read
                              ? AppTokens.textPrimary
                              : AppTokens.primaryDark,
                        ),
                      ),
                    ),
                    if (!read)
                      AppUi.statusBadge(
                        newBadgeLabel,
                        tone: AppStatusTone.info,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: AppTokens.spaceXs,
                  runSpacing: AppTokens.spaceXs,
                  children: [
                    AppUi.statusBadge(typeLabel, tone: AppStatusTone.neutral),
                    if (bookingNumber != null && bookingNumber!.isNotEmpty)
                      Text(
                        bookingNumber!,
                        style: const TextStyle(
                          color: AppTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    if (createdAt.isNotEmpty)
                      Text(
                        createdAt,
                        style: const TextStyle(
                          color: AppTokens.textMuted,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      fontSize: 13,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (onMarkRead != null)
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: onMarkRead,
              tooltip: markReadLabel,
            ),
        ],
      ),
    );
  }
}
