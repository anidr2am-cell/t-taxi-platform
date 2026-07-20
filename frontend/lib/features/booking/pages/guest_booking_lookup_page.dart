import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/guest_booking_lookup_result.dart';
import '../services/booking_api_service.dart';
import '../services/booking_chat_api.dart';
import '../services/guest_booking_lookup_service.dart';
import '../utils/booking_status_display.dart';
import '../utils/customer_booking_format.dart';
import '../widgets/booking_chat_section.dart';
import '../widgets/booking_notification_section.dart';
import '../widgets/booking_review_form.dart';
import '../widgets/assigned_driver_status_card.dart';
import '../widgets/airport_meeting_guide_card.dart';
import '../../driver_location/widgets/guest_driver_tracking_section.dart';
import '../../chat/services/chat_socket_service.dart';
import 'customer_booking_chat_page.dart';

class GuestBookingLookupPage extends StatefulWidget {
  const GuestBookingLookupPage({
    super.key,
    this.lookupService,
    this.bookingChatApi,
    this.bookingChatSocketService,
    this.enableCustomerTools = false,
    this.reviewApi,
    this.trackingBuilder,
  });

  final GuestBookingLookupService? lookupService;
  final BookingChatApi? bookingChatApi;
  final ChatSocketService? bookingChatSocketService;
  final bool enableCustomerTools;
  final BookingReviewApi? reviewApi;
  final Widget Function(GuestBookingLookupResult result)? trackingBuilder;

  @override
  State<GuestBookingLookupPage> createState() => _GuestBookingLookupPageState();
}

class _GuestBookingLookupPageState extends State<GuestBookingLookupPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookingNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  late final GuestBookingLookupService _lookupService =
      widget.lookupService ?? GuestBookingLookupService();

  GuestBookingLookupResult? _result;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  final Set<String> _pickupAlertSentBookingNumbers = <String>{};

  @override
  void initState() {
    super.initState();
    _loadCached();
  }

  @override
  void dispose() {
    _bookingNumberController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _loadCached() async {
    final cached = await _lookupService.loadCached();
    if (!mounted) return;
    if (cached != null) {
      _bookingNumberController.text = cached.bookingNumber;
      if (cached.customerPhone != null && cached.customerPhone!.isNotEmpty) {
        _phoneController.text = cached.customerPhone!;
      }
    }
    setState(() {
      _result = cached;
      _loading = false;
    });
  }

  Future<void> _refresh() async {
    final result = _result;
    if (result == null) return;
    final phone = result.customerPhone?.trim();
    if (phone == null || phone.isEmpty) {
      setState(() {
        _error = context.l10n.t('guest_lookup_refresh_needs_phone');
      });
      return;
    }

    setState(() {
      _refreshing = true;
      _error = null;
    });

    try {
      final refreshed = await _lookupService.lookup(
        bookingNumber: result.bookingNumber,
        phone: phone,
      );
      if (!mounted) return;
      setState(() {
        _result = refreshed;
        _refreshing = false;
      });
    } on BookingApiException catch (err) {
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _refreshing = false;
        _error = err.errorCode == 'BOOKING_NOT_FOUND'
            ? l10n.t('guest_lookup_not_found')
            : userFacingError(err, fallback: l10n.t('guest_lookup_load_error'));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = context.l10n.t('guest_lookup_load_error');
      });
    }
  }

  Future<void> _notifyPickupReady(GuestBookingLookupResult result) async {
    if (_pickupAlertSentBookingNumbers.contains(result.bookingNumber)) {
      _openCustomerChat(result);
      return;
    }
    await (widget.bookingChatApi ?? const BookingChatApi()).sendPickupAlert(
      bookingNumber: result.bookingNumber,
      guestAccessToken: result.guestAccessToken,
    );
    if (!mounted) return;
    setState(() {
      _pickupAlertSentBookingNumbers.add(result.bookingNumber);
    });
    _openCustomerChat(result);
  }

  void _openCustomerChat(GuestBookingLookupResult result) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerBookingChatPage(
          bookingNumber: result.bookingNumber,
          guestAccessToken: result.guestAccessToken,
          api: widget.bookingChatApi,
          socketService: widget.bookingChatSocketService,
        ),
      ),
    );
  }

  bool _canSendPickupAlert(GuestBookingLookupResult result) => false;

  bool _canShowTracking(GuestBookingLookupResult result) {
    const trackingStatuses = {
      'DRIVER_ASSIGNED',
      'ON_ROUTE',
      'DRIVER_ARRIVED',
      'PICKED_UP',
    };
    return widget.enableCustomerTools &&
        result.bookingId != null &&
        result.capabilities.trackingAvailable &&
        trackingStatuses.contains(result.status) &&
        result.guestAccessToken.trim().isNotEmpty;
  }

  bool _canShowNotifications(GuestBookingLookupResult result) {
    return widget.enableCustomerTools &&
        result.capabilities.notificationsAvailable &&
        result.guestAccessToken.trim().isNotEmpty;
  }

  bool _canShowChat(GuestBookingLookupResult result) => false;

  bool _canShowDriverPhone(GuestBookingLookupResult result) {
    const activeStatuses = {
      'DRIVER_ASSIGNED',
      'ON_ROUTE',
      'DRIVER_ARRIVED',
      'PICKED_UP',
    };
    return activeStatuses.contains(result.status) &&
        result.driverPhone?.trim().isNotEmpty == true &&
        result.guestAccessToken.trim().isNotEmpty;
  }

  Widget _trackingSection(GuestBookingLookupResult result) {
    return widget.trackingBuilder?.call(result) ??
        GuestDriverTrackingSection(
          bookingId: result.bookingId!,
          guestAccessToken: result.guestAccessToken,
          bookingStatus: result.status,
        );
  }

  Future<void> _lookup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _lookupService.lookup(
        bookingNumber: _bookingNumberController.text,
        phone: _phoneController.text,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on BookingApiException catch (err) {
      if (!mounted) return;
      final l10n = context.l10n;
      setState(() {
        _loading = false;
        _error = err.errorCode == 'BOOKING_NOT_FOUND'
            ? l10n.t('guest_lookup_not_found')
            : userFacingError(err, fallback: l10n.t('guest_lookup_load_error'));
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.t('guest_lookup_load_error');
      });
    }
  }

  Future<void> _clear() async {
    await _lookupService.clearCached();
    if (!mounted) return;
    setState(() {
      _result = null;
      _error = null;
      _bookingNumberController.clear();
      _phoneController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_loading && _result == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.t('guest_lookup_title'))),
        body: AppUi.loadingState(message: l10n.t('guest_lookup_loading')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('guest_lookup_title')),
        actions: [
          if (_result != null)
            IconButton(
              key: const ValueKey('guest_lookup_refresh'),
              onPressed: _loading || _refreshing ? null : _refresh,
              tooltip: l10n.t('guest_lookup_refresh'),
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
      body: AppUi.centeredContent(
        child: SingleChildScrollView(
          padding: AppUi.pagePadding(context),
          child: _result == null ? _lookupForm() : _bookingDetail(_result!),
        ),
      ),
    );
  }

  Widget _lookupForm() {
    final l10n = context.l10n;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('guest_lookup_title'),
            subtitle: l10n.t('guest_lookup_subtitle'),
          ),
          AppUi.surfaceCard(
            child: Column(
              children: [
                TextFormField(
                  key: const ValueKey('guest_lookup_booking_number'),
                  controller: _bookingNumberController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.t('guest_lookup_booking_number'),
                    hintText: l10n.t('guest_lookup_booking_number_hint'),
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  ),
                  validator: (value) {
                    final normalized = (value ?? '').trim().toUpperCase();
                    return RegExp(r'^TX\d{12}$').hasMatch(normalized)
                        ? null
                        : l10n.t('guest_lookup_invalid_number');
                  },
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextFormField(
                  key: const ValueKey('guest_lookup_phone'),
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: l10n.t('guest_lookup_phone'),
                    prefixIcon: const Icon(Icons.phone_outlined),
                  ),
                  validator: (value) {
                    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                    return digits.length >= 4
                        ? null
                        : l10n.t('guest_lookup_invalid_phone');
                  },
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AppTokens.spaceMd),
            AppUi.errorState(message: _error!),
          ],
          const SizedBox(height: AppTokens.spaceLg),
          AppUi.primaryButton(
            label: l10n.t('guest_lookup_find'),
            icon: Icons.search,
            loading: _loading,
            onPressed: _loading ? null : _lookup,
          ),
        ],
      ),
    );
  }

  Widget _bookingDetail(GuestBookingLookupResult result) {
    final l10n = context.l10n;
    final reviewSubmitted = result.review?.submitted == true;
    final canShowReviewForm = result.canReview && !reviewSubmitted;
    final reviewFormState =
        result.review?.toFormState() ??
        const {'eligible': true, 'submitted': false};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.surfaceCard(
          backgroundColor: AppTokens.primaryLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.t('guest_lookup_booking_number'),
                style: const TextStyle(
                  color: AppTokens.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(
                result.bookingNumber,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: AppTokens.primaryDark,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.statusBadge(
                BookingStatusDisplay.label(l10n, result.status),
                tone: AppUi.toneForBookingStatus(result.status),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _actionSummary(result),
        if (result.driverName?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AssignedDriverStatusCard(result: result),
        ],
        if (BookingStatusDisplay.customerGuidance(l10n, result.status) !=
            null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.infoLight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline, color: AppTokens.info, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    BookingStatusDisplay.customerGuidance(l10n, result.status)!,
                    style: const TextStyle(
                      color: AppTokens.textSecondary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (reviewSubmitted) ...[
          const SizedBox(height: AppTokens.spaceMd),
          BookingReviewForm(
            key: ValueKey(
              'guest_review_${result.bookingNumber}_${result.status}_submitted',
            ),
            bookingNumber: result.bookingNumber,
            guestAccessToken: result.guestAccessToken,
            api: widget.reviewApi,
            initialState: result.review!.toFormState(),
          ),
        ] else if (canShowReviewForm) ...[
          const SizedBox(height: AppTokens.spaceMd),
          BookingReviewForm(
            key: ValueKey(
              'guest_review_${result.bookingNumber}_${result.status}_pending',
            ),
            bookingNumber: result.bookingNumber,
            guestAccessToken: result.guestAccessToken,
            api: widget.reviewApi,
            initialState: reviewFormState,
            onSubmitted: _refresh,
          ),
        ],
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.sectionHeader(
          context,
          title: l10n.t('guest_lookup_trip_details'),
        ),
        AppUi.surfaceCard(
          child: Column(
            children: [
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_pickup'),
                value: CustomerBookingFormat.pickupDateTime(
                  l10n,
                  result.scheduledPickupAt,
                ),
              ),
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_service'),
                value: result.serviceTypeName,
              ),
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_from'),
                value: result.originAddress,
              ),
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_to'),
                value: result.destinationAddress,
              ),
              if (result.driverName != null) ...[
                const Divider(height: 24),
                AppUi.summaryRow(
                  label: l10n.t('guest_lookup_driver'),
                  value: result.driverName!,
                ),
                if (_canShowDriverPhone(result))
                  AppUi.summaryRow(
                    label: l10n.t('guest_lookup_driver_phone'),
                    value: result.driverPhone!.trim(),
                  ),
              ],
            ],
          ),
        ),
        if (AirportMeetingGuideCard.shouldShow(
          serviceTypeCode: result.serviceTypeCode,
          originAirportCode: result.originAirportCode,
        )) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AirportMeetingGuideCard(
            serviceTypeCode: result.serviceTypeCode,
            originAirportCode: result.originAirportCode,
            nameSignRequested: result.nameSignRequested,
            pickupAlertSent: _pickupAlertSentBookingNumbers.contains(
              result.bookingNumber,
            ),
            vehicleInfo: AirportMeetingVehicleInfo(
              driverName: result.driverName,
              driverPhone: _canShowDriverPhone(result)
                  ? result.driverPhone
                  : null,
              vehicleType: result.vehicleType,
              vehicleColor: result.vehicleColor,
              vehiclePlateNumber: result.vehiclePlateNumber,
            ),
            onNotifyPickup: _canSendPickupAlert(result)
                ? () => _notifyPickupReady(result)
                : null,
          ),
        ],
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.sectionHeader(context, title: l10n.t('guest_lookup_payment')),
        AppUi.surfaceCard(
          backgroundColor: AppTokens.accentLight,
          child: Column(
            children: [
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_total'),
                value: CustomerBookingFormat.money(
                  result.totalAmount,
                  result.currency,
                ),
                emphasize: true,
              ),
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_payment'),
                value: CustomerBookingFormat.paymentMethod(
                  l10n,
                  result.paymentMethod,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        if (_error != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.errorState(message: _error!),
        ],
        if (widget.enableCustomerTools) ...[
          const SizedBox(height: AppTokens.spaceMd),
          if (_canShowTracking(result)) _trackingSection(result),
          if (_canShowTracking(result))
            const SizedBox(height: AppTokens.spaceMd),
          if (_canShowNotifications(result))
            BookingNotificationSection(
              bookingNumber: result.bookingNumber,
              bookingId: result.bookingId,
              guestAccessToken: result.guestAccessToken,
            ),
          if (_canShowChat(result)) ...[
            const SizedBox(height: AppTokens.spaceMd),
            BookingChatSection(
              bookingNumber: result.bookingNumber,
              guestAccessToken: result.guestAccessToken,
              api: widget.bookingChatApi ?? const BookingChatApi(),
              socketService: widget.bookingChatSocketService,
            ),
          ],
        ],
        const SizedBox(height: AppTokens.spaceLg),
        AppUi.secondaryButton(
          label: l10n.t('guest_lookup_another'),
          icon: Icons.search,
          onPressed: _clear,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _actionSummary(GuestBookingLookupResult result) {
    final l10n = context.l10n;
    final driverSummary = _driverSummary(result, l10n);
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.infoLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('customer_next_action'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTokens.info,
            ),
          ),
          const SizedBox(height: 8),
          AppUi.summaryRow(
            label: l10n.t('status'),
            value: BookingStatusDisplay.label(l10n, result.status),
          ),
          AppUi.summaryRow(
            label: l10n.t('pickup_datetime'),
            value: CustomerBookingFormat.pickupDateTime(
              l10n,
              result.scheduledPickupAt,
            ),
          ),
          AppUi.summaryRow(
            label: l10n.t('customer_driver_assignment'),
            value: driverSummary,
          ),
          AppUi.summaryRow(
            label: l10n.t('customer_payment_method'),
            value: CustomerBookingFormat.paymentMethod(
              l10n,
              result.paymentMethod,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            BookingStatusDisplay.customerGuidance(l10n, result.status) ??
                l10n.t('customer_status_unknown_guidance'),
            style: const TextStyle(
              color: AppTokens.textSecondary,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  String _driverSummary(
    GuestBookingLookupResult result,
    AppLocalizations l10n,
  ) {
    final driverName = result.driverName?.trim();
    if (driverName == null || driverName.isEmpty) {
      return l10n.t('customer_driver_pending');
    }
    final vehicle =
        [result.vehicleType, result.vehicleColor, result.vehiclePlateNumber]
            .whereType<String>()
            .map((item) => item.trim())
            .where((item) => item.isNotEmpty)
            .join(' · ');
    return vehicle.isEmpty ? driverName : '$driverName · $vehicle';
  }
}
