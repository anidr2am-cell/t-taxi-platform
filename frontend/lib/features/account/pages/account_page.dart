import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/models/auth_user.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import '../../booking/models/guest_booking_lookup_result.dart';
import '../../booking/pages/guest_booking_lookup_page.dart';
import '../../booking/services/customer_bookings_api_service.dart';
import '../../booking/utils/booking_status_display.dart';
import '../../booking/utils/customer_booking_format.dart';
import '../services/mileage_api_service.dart';
import '../utils/auth_provider_display.dart';
import 'mileage_history_page.dart';
import 'my_reviews_page.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({
    super.key,
    this.mileageApiService,
    this.customerBookingsApiService,
    this.authController,
  });

  final MileageApiService? mileageApiService;
  final CustomerBookingsApiService? customerBookingsApiService;
  final AuthController? authController;

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool _loadingMileage = true;
  int? _mileageBalance;
  String? _mileageError;

  bool _loadingCounts = true;
  CustomerBookingStatusCounts? _statusCounts;
  String? _countsError;

  bool _loadingRecent = true;
  List<GuestBookingLookupResult> _recentBookings = const [];
  String? _recentError;

  AuthController _resolveController(BuildContext context) {
    return widget.authController ?? AuthScope.of(context);
  }

  MileageApiService _resolveMileageApiService(AuthController controller) {
    return widget.mileageApiService ??
        MileageApiService(session: controller.customerSession);
  }

  CustomerBookingsApiService _resolveBookingsApiService(
    AuthController controller,
  ) {
    return widget.customerBookingsApiService ??
        CustomerBookingsApiService(session: controller.customerSession);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAccountData();
    });
  }

  Future<void> _loadAccountData() async {
    await Future.wait([
      _loadMileageIfLoggedIn(),
      _loadStatusCounts(),
      _loadRecentBookings(),
    ]);
  }

  Future<void> _loadMileageIfLoggedIn() async {
    final controller = _resolveController(context);
    if (!controller.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loadingMileage = false;
        _mileageBalance = null;
        _mileageError = null;
      });
      return;
    }

    setState(() {
      _loadingMileage = true;
      _mileageError = null;
    });

    try {
      final result =
          await _resolveMileageApiService(controller).getMileageBalance();
      if (!mounted) return;
      setState(() {
        _mileageBalance = result.balance;
        _loadingMileage = false;
      });
    } on MileageApiException catch (error) {
      if (!mounted) return;
      final authController = _resolveController(context);
      if (await authController.handleUnauthorizedApi(error)) {
        setState(() {
          _loadingMileage = false;
          _mileageError = context.l10n.t('account_mileage_load_failed');
        });
        return;
      }
      setState(() {
        _loadingMileage = false;
        _mileageError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingMileage = false;
        _mileageError = context.l10n.t('account_mileage_load_failed');
      });
    }
  }

  Future<void> _loadStatusCounts() async {
    final controller = _resolveController(context);
    if (!controller.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loadingCounts = false;
        _statusCounts = null;
        _countsError = null;
      });
      return;
    }

    setState(() {
      _loadingCounts = true;
      _countsError = null;
    });

    try {
      final counts = await _resolveBookingsApiService(controller).getStatusCounts();
      if (!mounted) return;
      setState(() {
        _statusCounts = counts;
        _loadingCounts = false;
      });
    } on CustomerBookingsApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCounts = false;
        _countsError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingCounts = false;
        _countsError = context.l10n.t('my_bookings_load_error');
      });
    }
  }

  Future<void> _loadRecentBookings() async {
    final controller = _resolveController(context);
    if (!controller.isLoggedIn) {
      if (!mounted) return;
      setState(() {
        _loadingRecent = false;
        _recentBookings = const [];
        _recentError = null;
      });
      return;
    }

    setState(() {
      _loadingRecent = true;
      _recentError = null;
    });

    try {
      final result = await _resolveBookingsApiService(controller).listMyBookings(
        page: 1,
        limit: 5,
      );
      if (!mounted) return;
      setState(() {
        _recentBookings = result.bookings;
        _loadingRecent = false;
      });
    } on CustomerBookingsApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingRecent = false;
        _recentError = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingRecent = false;
        _recentError = context.l10n.t('account_recent_bookings_load_failed');
      });
    }
  }

  Future<void> _handleLogout(AuthController controller) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('account_logout_menu')),
        content: Text(l10n.t('account_logout_confirm_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('account_logout_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('account_logout_menu')),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    await controller.signOut();
    if (!mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final message = l10n.t('landing_header_logout_success');
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  void _openMyBookings() {
    Navigator.of(context).pushNamed('/my-bookings');
  }

  void _openMileageHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MileageHistoryPage(
          mileageApiService: widget.mileageApiService,
        ),
      ),
    );
  }

  void _openMyReviews() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MyReviewsPage(
          apiService: widget.customerBookingsApiService,
        ),
      ),
    );
  }

  void _openSupport() {
    Navigator.of(context).pushNamed('/support');
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(context.l10n.t('account_feature_coming_soon'))),
      );
  }

  void _openRecentBooking(GuestBookingLookupResult booking) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GuestBookingLookupPage(
          initialResult: booking,
          enableCustomerTools: true,
          fromMyBookings: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _resolveController(context);
    final l10n = context.l10n;

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.isInitialized) {
          return Scaffold(
            appBar: AppBar(title: Text(l10n.t('account_page_title'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!controller.isLoggedIn) {
          return Scaffold(
            key: const Key('account_page_signed_out'),
            appBar: AppBar(title: Text(l10n.t('account_page_title'))),
            body: Center(
              child: Padding(
                padding: AppUi.pagePadding(context),
                child: Text(
                  l10n.t('account_sign_in_required'),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        final user = controller.user!;

        return Scaffold(
          key: const Key('account_page'),
          appBar: AppBar(title: Text(l10n.t('account_page_title'))),
          body: RefreshIndicator(
            onRefresh: _loadAccountData,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: AppUi.pagePadding(context),
              children: [
                _ProfileHeader(user: user, l10n: l10n),
                const SizedBox(height: AppTokens.spaceMd),
                _MileageCard(
                  l10n: l10n,
                  loading: _loadingMileage,
                  balance: _mileageBalance,
                  errorMessage: _mileageError,
                  onRetry: _loadMileageIfLoggedIn,
                  onTap: _openMileageHistory,
                ),
                const SizedBox(height: AppTokens.spaceLg),
                AppUi.sectionHeader(
                  context,
                  title: l10n.t('account_booking_counts_title'),
                ),
                _BookingStatusCountsRow(
                  l10n: l10n,
                  loading: _loadingCounts,
                  counts: _statusCounts,
                  errorMessage: _countsError,
                  onRetry: _loadStatusCounts,
                  onTap: _openMyBookings,
                ),
                const SizedBox(height: AppTokens.spaceLg),
                AppUi.sectionHeader(
                  context,
                  title: l10n.t('account_menu_section_title'),
                ),
                AppUi.surfaceCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        key: const Key('account_coupon_menu'),
                        leading: const Icon(Icons.local_offer_outlined),
                        title: Text(l10n.t('account_coupon_menu')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _showComingSoon,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('account_my_reviews_menu'),
                        leading: const Icon(Icons.rate_review_outlined),
                        title: Text(l10n.t('account_my_reviews_menu')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openMyReviews,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('account_customer_support_menu'),
                        leading: const Icon(Icons.support_agent_outlined),
                        title: Text(l10n.t('account_customer_support_menu')),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _openSupport,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        key: const Key('account_logout_menu'),
                        leading: const Icon(Icons.logout),
                        title: Text(l10n.t('account_logout_menu')),
                        onTap: controller.isLoading
                            ? null
                            : () => _handleLogout(controller),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                AppUi.sectionHeader(
                  context,
                  title: l10n.t('account_recent_bookings_title'),
                ),
                _RecentBookingsSection(
                  l10n: l10n,
                  loading: _loadingRecent,
                  bookings: _recentBookings,
                  errorMessage: _recentError,
                  onRetry: _loadRecentBookings,
                  onTapBooking: _openRecentBooking,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user, required this.l10n});

  final AuthUser user;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final providerLabel = AuthProviderDisplay.labelForProvider(
      l10n,
      user.authProvider,
    );

    return AppUi.surfaceCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTokens.primary.withValues(alpha: 0.12),
            child: const Icon(Icons.person, color: AppTokens.primary),
          ),
          const SizedBox(width: AppTokens.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (user.email != null && user.email!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    user.email!,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (providerLabel != null) ...[
                  const SizedBox(height: AppTokens.spaceSm),
                  Container(
                    key: const Key('account_auth_provider_badge'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTokens.surfaceMuted,
                      borderRadius: AppTokens.borderRadiusMd,
                      border: Border.all(color: AppTokens.border),
                    ),
                    child: Text(
                      providerLabel,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MileageCard extends StatelessWidget {
  const _MileageCard({
    required this.l10n,
    required this.loading,
    required this.balance,
    required this.errorMessage,
    required this.onRetry,
    required this.onTap,
  });

  final AppLocalizations l10n;
  final bool loading;
  final int? balance;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: const Key('account_mileage_card'),
      child: AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('account_mileage_label'),
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            if (loading)
              Row(
                key: const Key('account_mileage_loading'),
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: AppTokens.spaceSm),
                  Text(
                    l10n.t('account_mileage_loading'),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              )
            else if (errorMessage != null)
              Row(
                key: const Key('account_mileage_error'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      errorMessage!,
                      style: const TextStyle(color: AppTokens.error),
                    ),
                  ),
                  TextButton(
                    onPressed: onRetry,
                    child: Text(l10n.t('account_mileage_retry')),
                  ),
                ],
              )
            else
              InkWell(
                key: const Key('account_mileage_balance'),
                onTap: onTap,
                borderRadius: AppTokens.borderRadiusMd,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n
                              .t('account_mileage_balance')
                              .replaceAll(
                                '{balance}',
                                AuthProviderDisplay.formatPoints(balance ?? 0),
                              ),
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTokens.primary,
                              ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppTokens.textSecondary),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BookingStatusCountsRow extends StatelessWidget {
  const _BookingStatusCountsRow({
    required this.l10n,
    required this.loading,
    required this.counts,
    required this.errorMessage,
    required this.onRetry,
    required this.onTap,
  });

  final AppLocalizations l10n;
  final bool loading;
  final CustomerBookingStatusCounts? counts;
  final String? errorMessage;
  final VoidCallback onRetry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return AppUi.surfaceCard(
        child: Center(
          key: const Key('account_booking_counts_loading'),
          child: Padding(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    if (errorMessage != null) {
      return AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              errorMessage!,
              style: const TextStyle(color: AppTokens.error),
            ),
            TextButton(onPressed: onRetry, child: Text(l10n.t('account_mileage_retry'))),
          ],
        ),
      );
    }

    final items = [
      _CountItem(
        keyName: 'waiting',
        label: l10n.t('account_booking_count_waiting'),
        value: counts?.waiting ?? 0,
      ),
      _CountItem(
        keyName: 'assigned',
        label: l10n.t('account_booking_count_assigned'),
        value: counts?.assigned ?? 0,
      ),
      _CountItem(
        keyName: 'inProgress',
        label: l10n.t('account_booking_count_in_progress'),
        value: counts?.inProgress ?? 0,
      ),
      _CountItem(
        keyName: 'settlementPending',
        label: l10n.t('account_booking_count_settlement_pending'),
        value: counts?.settlementPending ?? 0,
      ),
      _CountItem(
        keyName: 'completed',
        label: l10n.t('account_booking_count_completed'),
        value: counts?.completed ?? 0,
      ),
      _CountItem(
        keyName: 'reviewPending',
        label: l10n.t('account_booking_count_review_pending'),
        value: counts?.reviewPending ?? 0,
      ),
    ];

    return AppUi.surfaceCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / 3;
          return Wrap(
            spacing: 0,
            runSpacing: AppTokens.spaceSm,
            children: items
                .map(
                  (item) => SizedBox(
                    width: itemWidth,
                    child: _BookingCountTile(
                      key: Key('account_booking_count_${item.keyName}'),
                      label: item.label,
                      value: item.value,
                      onTap: onTap,
                    ),
                  ),
                )
                .toList(),
          );
        },
      ),
    );
  }
}

class _CountItem {
  const _CountItem({
    required this.keyName,
    required this.label,
    required this.value,
  });

  final String keyName;
  final String label;
  final int value;
}

class _BookingCountTile extends StatelessWidget {
  const _BookingCountTile({
    super.key,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final int value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppTokens.borderRadiusMd,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: AppTokens.spaceSm,
          horizontal: 4,
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppTokens.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: AppTokens.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentBookingsSection extends StatelessWidget {
  const _RecentBookingsSection({
    required this.l10n,
    required this.loading,
    required this.bookings,
    required this.errorMessage,
    required this.onRetry,
    required this.onTapBooking,
  });

  final AppLocalizations l10n;
  final bool loading;
  final List<GuestBookingLookupResult> bookings;
  final String? errorMessage;
  final VoidCallback onRetry;
  final ValueChanged<GuestBookingLookupResult> onTapBooking;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        key: Key('account_recent_bookings_loading'),
        child: Padding(
          padding: EdgeInsets.all(AppTokens.spaceMd),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (errorMessage != null) {
      return AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(errorMessage!, style: const TextStyle(color: AppTokens.error)),
            TextButton(onPressed: onRetry, child: Text(l10n.t('account_mileage_retry'))),
          ],
        ),
      );
    }

    if (bookings.isEmpty) {
      return AppUi.surfaceCard(
        child: Text(l10n.t('account_recent_bookings_empty')),
      );
    }

    return Column(
      children: bookings
          .map(
            (booking) => Padding(
              padding: const EdgeInsets.only(bottom: AppTokens.spaceSm),
              child: AppUi.surfaceCard(
                padding: EdgeInsets.zero,
                child: ListTile(
                  key: Key('account_recent_booking_${booking.bookingNumber}'),
                  title: Text(booking.bookingNumber),
                  subtitle: Text(
                    '${BookingStatusDisplay.label(l10n, booking.status)} · '
                    '${CustomerBookingFormat.pickupDateTime(l10n, booking.scheduledPickupAt)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onTapBooking(booking),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}
