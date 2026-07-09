import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../driver_settlement/pages/driver_settlement_list_page.dart';
import '../driver_auth.dart';
import '../driver_ux.dart';
import '../models/driver_booking.dart';
import '../models/driver_status.dart';
import '../services/driver_api_service.dart';
import 'driver_jobs_page.dart';
import 'driver_notifications_page.dart';
import 'driver_profile_page.dart';

/// Mobile-first driver shell: Jobs (default), Notifications, Settlement, Profile.
class DriverShellPage extends StatefulWidget {
  const DriverShellPage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverShellPage> createState() => _DriverShellPageState();
}

class _DriverShellPageState extends State<DriverShellPage> {
  int _index = 0;
  late final DriverApiService _api = widget.api ?? DriverApiService();
  Future<DriverStatus>? _statusFuture;
  Future<DriverBooking?>? _activeJobFuture;

  @override
  void initState() {
    super.initState();
    _ensureAuthenticated();
    _refreshSession();
  }

  Future<void> _ensureAuthenticated() async {
    final token = await _api.getSavedToken();
    if (!mounted) return;
    if (token == null || token.isEmpty) {
      driverRedirectToLogin(context);
    }
  }

  void _refreshSession() {
    setState(() {
      _statusFuture = _api.getStatus().then((status) {
        if (status.hasActiveJob) {
          _activeJobFuture = _loadActiveJob();
        } else {
          _activeJobFuture = Future.value(null);
        }
        return status;
      });
    });
  }

  Future<DriverBooking?> _loadActiveJob() async {
    try {
      final today = await _api.getTodayBookings();
      for (final booking in today.items) {
        if (DriverUx.groupForStatus(booking.status) == DriverJobGroup.active) {
          return booking;
        }
      }
    } catch (_) {
      // Session bar is informational; jobs tab handles errors.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = [
      DriverJobsPage(api: _api, onSessionChanged: _refreshSession),
      DriverNotificationsPage(api: _api),
      DriverSettlementListPage(api: null),
      DriverProfilePage(api: _api, onStatusChanged: _refreshSession),
    ];

    return Scaffold(
      body: Column(
        children: [
          _DriverSessionBar(
            statusFuture: _statusFuture,
            activeJobFuture: _activeJobFuture,
            onRefresh: _refreshSession,
          ),
          Expanded(child: pages[_index]),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) {
          setState(() => _index = i);
          _refreshSession();
        },
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.work_outline),
            selectedIcon: const Icon(Icons.work),
            label: l10n.t('driver_nav_jobs'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: l10n.t('driver_nav_notifications'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l10n.t('driver_nav_settlement'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.t('driver_nav_profile'),
          ),
        ],
      ),
    );
  }
}

class _DriverSessionBar extends StatelessWidget {
  const _DriverSessionBar({
    required this.statusFuture,
    required this.activeJobFuture,
    required this.onRefresh,
  });

  final Future<DriverStatus>? statusFuture;
  final Future<DriverBooking?>? activeJobFuture;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTokens.surface,
      elevation: 1,
      child: SafeArea(
        bottom: false,
        child: FutureBuilder<DriverStatus>(
          future: statusFuture,
          builder: (context, snapshot) {
            if (snapshot.hasError && driverIsAuthError(snapshot.error!)) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (context.mounted) {
                  driverHandleApiError(context, snapshot.error!);
                }
              });
            }

            final l10n = context.l10n;
            final status = snapshot.data;
            final online = status?.online == true;
            final loading = snapshot.connectionState == ConnectionState.waiting;

            return Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTokens.spaceMd,
                AppTokens.spaceSm,
                AppTokens.spaceMd,
                AppTokens.spaceSm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (loading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        AppUi.statusBadge(
                          online
                              ? l10n.t('driver_online')
                              : l10n.t('driver_offline'),
                          tone: online
                              ? AppStatusTone.success
                              : AppStatusTone.neutral,
                        ),
                      const SizedBox(width: AppTokens.spaceSm),
                      Expanded(
                        child: Text(
                          online
                              ? l10n.t('driver_session_ready')
                              : l10n.t('driver_session_offline'),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: AppTokens.textSecondary,
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                      ),
                      IconButton(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh, size: 20),
                        tooltip: context.l10n.t('driver_refresh'),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                  if (snapshot.hasError &&
                      !driverIsAuthError(snapshot.error!)) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    Text(
                      snapshot.error.toString(),
                      style: const TextStyle(
                        color: AppTokens.error,
                        fontSize: 13,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (status?.hasActiveJob == true) ...[
                    const SizedBox(height: AppTokens.spaceSm),
                    FutureBuilder<DriverBooking?>(
                      future: activeJobFuture,
                      builder: (context, jobSnapshot) {
                        final job = jobSnapshot.data;
                        if (job == null) {
                          return AppUi.surfaceCard(
                            backgroundColor: AppTokens.infoLight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppTokens.spaceMd,
                              vertical: AppTokens.spaceSm,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.local_taxi,
                                  color: AppTokens.info,
                                  size: 20,
                                ),
                                const SizedBox(width: AppTokens.spaceSm),
                                Expanded(
                                  child: Text(
                                    l10n.t('driver_active_job_in_progress'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: AppTokens.info,
                                        ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                        final nextKey = DriverUx.nextActionKey(job);
                        return AppUi.surfaceCard(
                          backgroundColor: AppTokens.infoLight,
                          padding: const EdgeInsets.all(AppTokens.spaceMd),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(
                                    Icons.local_taxi,
                                    color: AppTokens.info,
                                    size: 20,
                                  ),
                                  const SizedBox(width: AppTokens.spaceSm),
                                  Expanded(
                                    child: Text(
                                      job.bookingNumber,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppTokens.textPrimary,
                                      ),
                                    ),
                                  ),
                                  AppUi.statusBadge(
                                    context.l10n.t(
                                      DriverUx.statusLabelKey(job.status),
                                    ),
                                    tone: AppUi.toneForBookingStatus(
                                      job.status,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${job.pickupTime} · ${job.origin}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppTokens.textSecondary,
                                  fontSize: 13,
                                ),
                              ),
                              if (nextKey != null) ...[
                                const SizedBox(height: AppTokens.spaceSm),
                                AppUi.actionBanner(
                                  message: context.l10n.t(nextKey),
                                  icon: Icons.navigation,
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
