import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/clipboard_writer.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_complete_review.dart';
import '../models/booking_create_result.dart';
import '../models/guest_booking_lookup_result.dart';
import '../services/booking_chat_api.dart';
import '../services/guest_booking_lookup_service.dart';
import '../utils/booking_status_display.dart';
import '../utils/customer_booking_format.dart';
import '../widgets/booking_complete_review_section.dart';
import '../widgets/booking_review_form.dart';
import '../widgets/booking_notification_section.dart';
import '../../chat/services/chat_socket_service.dart';
import '../../driver_location/widgets/guest_driver_tracking_section.dart';
import '../widgets/airport_meeting_guide_card.dart';
import '../widgets/booking_chat_section.dart';
import '../widgets/guest_booking_cancel_section.dart';
import 'customer_booking_chat_page.dart';
import 'guest_booking_lookup_page.dart';

class BookingCompletePage extends StatefulWidget {
  final BookingCreateResult result;
  final String serviceLabel;
  final String originLabel;
  final String destinationLabel;
  final BookingCompleteReview? review;
  final Future<DropoffQrIssueResult> Function()? issueDropoffQr;
  final BookingChatApi? chatApi;
  final ChatSocketService? chatSocketService;
  final String? serviceTypeCode;
  final String? originAirportCode;
  final bool nameSignRequested;
  final AirportMeetingVehicleInfo? meetingVehicleInfo;
  final String? customerPhone;
  final String? scheduledPickupAt;
  final String? selectedVehicle;
  final bool enableCustomerTools;
  final GuestBookingLookupService? lookupService;

  const BookingCompletePage({
    super.key,
    required this.result,
    required this.serviceLabel,
    required this.originLabel,
    required this.destinationLabel,
    this.review,
    this.issueDropoffQr,
    this.chatApi,
    this.chatSocketService,
    this.serviceTypeCode,
    this.originAirportCode,
    this.nameSignRequested = false,
    this.meetingVehicleInfo,
    this.customerPhone,
    this.scheduledPickupAt,
    this.selectedVehicle,
    this.enableCustomerTools = false,
    this.lookupService,
  });

  @override
  State<BookingCompletePage> createState() => _BookingCompletePageState();
}

class _BookingCompletePageState extends State<BookingCompletePage> {
  static const _pickupAlertStatuses = {
    'DRIVER_ASSIGNED',
    'ON_ROUTE',
    'DRIVER_ARRIVED',
  };
  bool _pickupAlertSent = false;
  late String _status;
  late bool _canCancel;
  String? _cancellationDeadline;
  String? _cancellationBlockedReason;

  @override
  void initState() {
    super.initState();
    _status = widget.result.status;
    _canCancel = widget.result.canCancel;
    _cancellationDeadline = widget.result.cancellationDeadline;
    _cancellationBlockedReason = widget.result.cancellationBlockedReason;
    BookingReviewApi().persistGuestToken(
      widget.result.bookingNumber,
      widget.result.guestAccessToken,
    );
    _persistGuestLookup();
  }

  Future<void> _persistGuestLookup() async {
    final phone = widget.customerPhone?.trim();
    final token = widget.result.guestAccessToken;
    if (phone == null || phone.isEmpty || token == null || token.isEmpty) {
      return;
    }
    final summary = GuestBookingLookupResult.fromCreateSummary(
      bookingId: widget.result.bookingId,
      bookingNumber: widget.result.bookingNumber,
      status: _status,
      totalAmount: widget.result.totalAmount,
      currency: widget.result.currency,
      paymentMethod: widget.result.paymentMethod,
      guestAccessToken: token,
      customerPhone: phone,
      serviceTypeName: widget.serviceLabel,
      originAddress: widget.originLabel,
      destinationAddress: widget.destinationLabel,
      serviceTypeCode: widget.serviceTypeCode,
      originAirportCode: widget.originAirportCode,
      nameSignRequested: widget.nameSignRequested,
      canCancel: _canCancel,
      cancellationDeadline: _cancellationDeadline,
      cancellationBlockedReason: _cancellationBlockedReason,
      scheduledPickupAt: widget.scheduledPickupAt,
    );
    await (widget.lookupService ?? GuestBookingLookupService())
        .persistFromCreateSummary(summary);
  }

  GuestBookingLookupResult get _cancelBookingView {
    return GuestBookingLookupResult.fromCreateSummary(
      bookingId: widget.result.bookingId,
      bookingNumber: widget.result.bookingNumber,
      status: _status,
      totalAmount: widget.result.totalAmount,
      currency: widget.result.currency,
      paymentMethod: widget.result.paymentMethod,
      guestAccessToken: widget.result.guestAccessToken ?? '',
      customerPhone: widget.customerPhone ?? '',
      serviceTypeName: widget.serviceLabel,
      originAddress: widget.originLabel,
      destinationAddress: widget.destinationLabel,
      serviceTypeCode: widget.serviceTypeCode,
      originAirportCode: widget.originAirportCode,
      nameSignRequested: widget.nameSignRequested,
      canCancel: _canCancel,
      cancellationDeadline: _cancellationDeadline,
      cancellationBlockedReason: _cancellationBlockedReason,
      scheduledPickupAt: widget.scheduledPickupAt,
    );
  }

  void _openBookingLookup() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuestBookingLookupPage(
          lookupService: widget.lookupService,
          enableCustomerTools: widget.enableCustomerTools,
        ),
      ),
    );
  }

  bool get _isCompleted => _status == 'COMPLETED';

  bool get _canShowChat => false;

  bool get _canShowNotifications =>
      widget.enableCustomerTools &&
      widget.result.bookingId != null &&
      widget.result.guestAccessToken?.isNotEmpty == true;

  bool get _canShowTracking {
    const statuses = {
      'DRIVER_ASSIGNED',
      'ON_ROUTE',
      'DRIVER_ARRIVED',
      'PICKED_UP',
    };
    return widget.enableCustomerTools &&
        widget.result.bookingId != null &&
        widget.result.guestAccessToken?.isNotEmpty == true &&
        widget.result.trackingAvailable &&
        statuses.contains(_status);
  }

  bool get _canShowReviewForm =>
      widget.enableCustomerTools &&
      _status == 'COMPLETED' &&
      widget.result.guestAccessToken?.isNotEmpty == true &&
      widget.review == null;

  bool get _canShowCancel =>
      widget.result.guestAccessToken?.isNotEmpty == true;

  Future<void> _copyBookingNumber() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    try {
      await writeClipboardText(widget.result.bookingNumber);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.t('booking_number_copied'))),
      );
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.t('booking_number_copy_failed'))),
      );
    }
  }

  Future<void> _notifyPickupReady() async {
    if (_pickupAlertSent) {
      _openCustomerChat();
      return;
    }
    await (widget.chatApi ?? const BookingChatApi()).sendPickupAlert(
      bookingNumber: widget.result.bookingNumber,
      guestAccessToken: widget.result.guestAccessToken ?? '',
    );
    if (!mounted) return;
    setState(() {
      _pickupAlertSent = true;
    });
    _openCustomerChat();
  }

  void _openCustomerChat() {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerBookingChatPage(
          bookingNumber: widget.result.bookingNumber,
          guestAccessToken: widget.result.guestAccessToken,
          api: widget.chatApi,
          socketService: widget.chatSocketService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = widget.result;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('booking_complete'))),
      body: AppUi.centeredContent(
        child: SingleChildScrollView(
          padding: AppUi.pagePadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SuccessHero(l10n: l10n),
              const SizedBox(height: AppTokens.spaceLg),
              _BookingNumberCard(
                bookingNumber: result.bookingNumber,
                statusLabel: BookingStatusDisplay.label(l10n, _status),
                pickupDateTime: CustomerBookingFormat.pickupDateTime(
                  l10n,
                  widget.scheduledPickupAt,
                ),
                origin: widget.originLabel,
                destination: widget.destinationLabel,
                vehicle: widget.selectedVehicle,
                total: CustomerBookingFormat.money(
                  result.totalAmount,
                  result.currency,
                ),
                paymentLabel: CustomerBookingFormat.paymentMethod(
                  l10n,
                  result.paymentMethod,
                ),
                nextAction: BookingStatusDisplay.customerGuidance(
                  l10n,
                  _status,
                ),
                l10n: l10n,
                onCopy: _copyBookingNumber,
                statusTone: AppUi.toneForBookingStatus(_status),
              ),
              if (BookingStatusDisplay.customerGuidance(l10n, _status) !=
                  null) ...[
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.surfaceCard(
                  backgroundColor: AppTokens.infoLight,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: AppTokens.info,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          BookingStatusDisplay.customerGuidance(
                            l10n,
                            _status,
                          )!,
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
              if (_canShowCancel) ...[
                const SizedBox(height: AppTokens.spaceMd),
                GuestBookingCancelSection(
                  booking: _cancelBookingView,
                  lookupService: widget.lookupService,
                  onCancelled: (updated) {
                    setState(() {
                      _status = updated.status;
                      _canCancel = updated.canCancel;
                      _cancellationDeadline = updated.cancellationDeadline;
                      _cancellationBlockedReason =
                          updated.cancellationBlockedReason;
                    });
                  },
                ),
              ],
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.primaryButton(
                label: l10n.t('booking_complete_track_cta'),
                icon: Icons.search,
                onPressed: _openBookingLookup,
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.sectionHeader(context, title: l10n.t('booking_summary')),
              AppUi.surfaceCard(
                child: Column(
                  children: [
                    AppUi.summaryRow(
                      label: l10n.t('service_type'),
                      value: widget.serviceLabel,
                    ),
                    AppUi.summaryRow(
                      label: l10n.t('origin'),
                      value: widget.originLabel,
                    ),
                    AppUi.summaryRow(
                      label: l10n.t('destination'),
                      value: widget.destinationLabel,
                    ),
                    AppUi.summaryRow(
                      label: l10n.t('pickup_datetime'),
                      value: CustomerBookingFormat.pickupDateTime(
                        l10n,
                        widget.scheduledPickupAt,
                      ),
                    ),
                    if (widget.selectedVehicle?.trim().isNotEmpty == true)
                      AppUi.summaryRow(
                        label: l10n.t('vehicle'),
                        value: widget.selectedVehicle!.trim(),
                      ),
                  ],
                ),
              ),
              if (AirportMeetingGuideCard.shouldShow(
                serviceTypeCode: widget.serviceTypeCode,
                originAirportCode: widget.originAirportCode,
              )) ...[
                const SizedBox(height: AppTokens.spaceMd),
                AirportMeetingGuideCard(
                  serviceTypeCode: widget.serviceTypeCode,
                  originAirportCode: widget.originAirportCode,
                  nameSignRequested: widget.nameSignRequested,
                  vehicleInfo: widget.meetingVehicleInfo,
                  pickupAlertSent: _pickupAlertSent,
                  onNotifyPickup:
                      _pickupAlertStatuses.contains(_status) &&
                          widget.meetingVehicleInfo?.hasAssignedDetails ==
                              true &&
                          widget.result.guestAccessToken?.isNotEmpty == true
                      ? _notifyPickupReady
                      : null,
                ),
              ],
              if (widget.review != null) ...[
                const SizedBox(height: AppTokens.spaceMd),
                BookingCompleteReviewSection(review: widget.review!),
              ],
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.surfaceCard(
                backgroundColor: AppTokens.accentLight,
                child: Text(
                  l10n.t('customer_price_conditions'),
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceLg),
              if (widget.enableCustomerTools) ...[
                if (_canShowTracking) ...[
                  GuestDriverTrackingSection(
                    bookingId: result.bookingId!,
                    guestAccessToken: result.guestAccessToken!,
                    bookingStatus: _status,
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                ],
                if (_isCompleted) ...[
                  AppUi.surfaceCard(
                    backgroundColor: AppTokens.successLight,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          color: AppTokens.success,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.t('booking_trip_completed'),
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: AppTokens.success,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  if (_canShowNotifications) ...[
                    BookingNotificationSection(
                      bookingNumber: result.bookingNumber,
                      bookingId: result.bookingId,
                      guestAccessToken: result.guestAccessToken,
                    ),
                    const SizedBox(height: AppTokens.spaceMd),
                  ],
                  if (_canShowReviewForm)
                    BookingReviewForm(
                      bookingNumber: result.bookingNumber,
                      guestAccessToken: result.guestAccessToken,
                      initialState: const {
                        'eligible': true,
                        'submitted': false,
                      },
                    ),
                ] else if (_canShowChat) ...[
                  const SizedBox(height: AppTokens.spaceMd),
                  BookingChatSection(
                    bookingNumber: result.bookingNumber,
                    guestAccessToken: result.guestAccessToken,
                    api: widget.chatApi,
                    socketService: widget.chatSocketService,
                  ),
                ],
              ],
              const SizedBox(height: AppTokens.spaceLg),
              SizedBox(
                width: double.infinity,
                child: AppUi.primaryButton(
                  label: l10n.t('app_title'),
                  icon: Icons.home_outlined,
                  onPressed: () =>
                      Navigator.of(context).popUntil((route) => route.isFirst),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  const _SuccessHero({required this.l10n});

  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.successLight,
      padding: const EdgeInsets.all(AppTokens.spaceLg),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTokens.success.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle,
              color: AppTokens.success,
              size: 48,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Text(
            l10n.t('booking_complete'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: AppTokens.success,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            l10n.t('booking_trust_message'),
            style: const TextStyle(color: AppTokens.textSecondary, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _BookingNumberCard extends StatelessWidget {
  const _BookingNumberCard({
    required this.bookingNumber,
    required this.statusLabel,
    required this.pickupDateTime,
    required this.origin,
    required this.destination,
    required this.vehicle,
    required this.total,
    required this.paymentLabel,
    required this.nextAction,
    required this.l10n,
    required this.onCopy,
    required this.statusTone,
  });

  final String bookingNumber;
  final String statusLabel;
  final String pickupDateTime;
  final String origin;
  final String destination;
  final String? vehicle;
  final String total;
  final String paymentLabel;
  final String? nextAction;
  final AppLocalizations l10n;
  final Future<void> Function() onCopy;
  final AppStatusTone statusTone;

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.t('reservation_number'),
            style: const TextStyle(
              color: AppTokens.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: SelectableText(
                  bookingNumber,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: AppTokens.primaryDark,
                  ),
                ),
              ),
              IconButton(
                onPressed: onCopy,
                tooltip: l10n.t('booking_number_copy'),
                icon: const Icon(Icons.copy_outlined),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l10n.t('booking_number_save_notice'),
            style: TextStyle(
              color: AppTokens.primaryDark.withValues(alpha: 0.85),
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.45,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [AppUi.statusBadge(statusLabel, tone: statusTone)],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          const Divider(height: 1),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.summaryRow(
            label: l10n.t('pickup_datetime'),
            value: pickupDateTime,
          ),
          AppUi.summaryRow(label: l10n.t('origin'), value: origin),
          AppUi.summaryRow(label: l10n.t('destination'), value: destination),
          if (vehicle?.trim().isNotEmpty == true)
            AppUi.summaryRow(label: l10n.t('vehicle'), value: vehicle!.trim()),
          AppUi.summaryRow(
            label: l10n.t('total'),
            value: total,
            emphasize: true,
          ),
          AppUi.summaryRow(
            label: l10n.t('payment_method'),
            value: paymentLabel,
          ),
          if (nextAction != null && nextAction!.trim().isNotEmpty) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              nextAction!,
              style: const TextStyle(
                color: AppTokens.textSecondary,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
