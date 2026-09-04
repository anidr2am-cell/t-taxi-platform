import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../auth/controllers/auth_controller.dart';
import '../../auth/widgets/booking_social_login_section.dart';
import '../../booking/models/guest_booking_lookup_result.dart';
import '../../booking/services/customer_bookings_api_service.dart';
import '../../booking/utils/customer_booking_format.dart';

class MyReviewsPage extends StatefulWidget {
  const MyReviewsPage({super.key, this.apiService});

  final CustomerBookingsApiService? apiService;

  @override
  State<MyReviewsPage> createState() => _MyReviewsPageState();
}

class _MyReviewsPageState extends State<MyReviewsPage> {
  List<GuestBookingLookupResult> _reviews = const [];
  bool _loading = true;
  String? _errorMessage;

  CustomerBookingsApiService _resolveApiService() {
    return widget.apiService ??
        CustomerBookingsApiService(
          session: AuthScope.of(context).customerSession,
        );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReviews();
    });
  }

  Future<void> _loadReviews() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final result = await _resolveApiService().listMyBookings(
        page: 1,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _reviews = result.bookings
            .where(
              (booking) =>
                  booking.review != null &&
                  (booking.review!.submitted || booking.review!.rating != null),
            )
            .toList(growable: false);
        _loading = false;
      });
    } on CustomerBookingsApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = context.l10n.t('account_my_reviews_load_failed');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      key: const Key('my_reviews_page'),
      appBar: AppBar(title: Text(l10n.t('account_my_reviews_title'))),
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
                label: l10n.t('account_mileage_retry'),
                onPressed: _loadReviews,
              ),
            ],
          ),
        ),
      );
    }

    if (_reviews.isEmpty) {
      return Center(
        child: Padding(
          padding: AppUi.pagePadding(context),
          child: Text(
            l10n.t('account_my_reviews_empty'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReviews,
      child: ListView.separated(
        padding: AppUi.pagePadding(context),
        itemCount: _reviews.length,
        separatorBuilder: (_, __) => const SizedBox(height: AppTokens.spaceSm),
        itemBuilder: (context, index) {
          final booking = _reviews[index];
          final review = booking.review!;
          return AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  booking.bookingNumber,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    ...List.generate(5, (starIndex) {
                      final filled = (review.rating ?? 0) > starIndex;
                      return Icon(
                        filled ? Icons.star : Icons.star_border,
                        size: 18,
                        color: filled ? Colors.amber : AppTokens.textSecondary,
                      );
                    }),
                    const SizedBox(width: AppTokens.spaceSm),
                    Text(
                      CustomerBookingFormat.pickupDateTime(
                        l10n,
                        review.createdAt ?? booking.scheduledPickupAt,
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTokens.textSecondary,
                      ),
                    ),
                  ],
                ),
                if (review.comment != null && review.comment!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: AppTokens.spaceSm),
                    child: Text(review.comment!.trim()),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
