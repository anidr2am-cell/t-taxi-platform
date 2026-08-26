import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/guest_booking_lookup_result.dart';
import '../pages/guest_booking_lookup_page.dart';
import '../services/customer_bookings_api_service.dart';
import '../utils/booking_status_display.dart';
import '../utils/customer_booking_format.dart';

class MyBookingsPage extends StatefulWidget {
  const MyBookingsPage({super.key, this.apiService});

  final CustomerBookingsApiService? apiService;

  @override
  State<MyBookingsPage> createState() => _MyBookingsPageState();
}

class _MyBookingsPageState extends State<MyBookingsPage> {
  late final CustomerBookingsApiService _apiService =
      widget.apiService ?? CustomerBookingsApiService();

  List<GuestBookingLookupResult> _bookings = const [];
  bool _loading = true;
  bool _refreshing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings({bool refreshing = false}) async {
    if (!refreshing) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _refreshing = true;
        _errorMessage = null;
      });
    }

    try {
      final result = await _apiService.listMyBookings();
      if (!mounted) return;
      setState(() {
        _bookings = result.bookings;
        _loading = false;
        _refreshing = false;
      });
    } on CustomerBookingsApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = userFacingError(
          error,
          fallback: context.l10n.t('my_bookings_load_error'),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _errorMessage = context.l10n.t('my_bookings_load_error');
      });
    }
  }

  Future<void> _handleRefresh() {
    return _loadBookings(refreshing: true);
  }

  void _openBookingDetail(GuestBookingLookupResult booking) {
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
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('my_bookings_title')),
        actions: [
          IconButton(
            tooltip: l10n.t('guest_lookup_refresh'),
            onPressed: _loading || _refreshing ? null : _handleRefresh,
            icon: _refreshing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(l10n),
    );
  }

  Widget _buildBody(AppLocalizations l10n) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: AppUi.pagePadding(context),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTokens.error),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.primaryButton(
                label: l10n.t('guest_lookup_refresh'),
                icon: Icons.refresh,
                onPressed: _handleRefresh,
              ),
            ],
          ),
        ),
      );
    }

    if (_bookings.isEmpty) {
      return Center(
        child: Padding(
          padding: AppUi.pagePadding(context),
          child: Text(
            l10n.t('my_bookings_empty'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTokens.textSecondary,
              height: 1.5,
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      child: ListView.separated(
        padding: AppUi.pagePadding(context),
        itemCount: _bookings.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppTokens.spaceSm),
        itemBuilder: (context, index) {
          final booking = _bookings[index];
          return _BookingListTile(
            booking: booking,
            l10n: l10n,
            onTap: () => _openBookingDetail(booking),
          );
        },
      ),
    );
  }
}

class _BookingListTile extends StatelessWidget {
  const _BookingListTile({
    required this.booking,
    required this.l10n,
    required this.onTap,
  });

  final GuestBookingLookupResult booking;
  final AppLocalizations l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusLabel = BookingStatusDisplay.label(
      l10n,
      booking.status,
      reassignmentInProgress: booking.reassignmentInProgress,
    );
    final pickupLabel = CustomerBookingFormat.pickupDateTime(
      l10n,
      booking.scheduledPickupAt,
    );
    final driverSummary = booking.driverName?.trim();

    return AppUi.surfaceCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            booking.bookingNumber,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTokens.textPrimary,
            ),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            booking.serviceTypeName,
            style: const TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            pickupLabel,
            style: const TextStyle(color: AppTokens.textSecondary),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Row(
            children: [
              AppUi.statusBadge(
                statusLabel,
                tone: AppUi.toneForBookingStatus(booking.status),
              ),
              if (driverSummary != null && driverSummary.isNotEmpty) ...[
                const SizedBox(width: AppTokens.spaceSm),
                Expanded(
                  child: Text(
                    l10n
                        .t('my_bookings_driver_summary')
                        .replaceAll('{name}', driverSummary),
                    style: const TextStyle(color: AppTokens.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
