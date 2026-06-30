import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_create_result.dart';
import '../services/booking_api_service.dart';
import '../services/booking_chat_api.dart';
import '../widgets/booking_review_form.dart';
import '../widgets/booking_notification_section.dart';
import '../../chat/services/chat_socket_service.dart';
import '../widgets/booking_chat_section.dart';

class BookingCompletePage extends StatefulWidget {
  final BookingCreateResult result;
  final String serviceLabel;
  final String originLabel;
  final String destinationLabel;
  final Future<DropoffQrIssueResult> Function()? issueDropoffQr;
  final BookingChatApi? chatApi;
  final ChatSocketService? chatSocketService;

  const BookingCompletePage({
    super.key,
    required this.result,
    required this.serviceLabel,
    required this.originLabel,
    required this.destinationLabel,
    this.issueDropoffQr,
    this.chatApi,
    this.chatSocketService,
  });

  @override
  State<BookingCompletePage> createState() => _BookingCompletePageState();
}

class _BookingCompletePageState extends State<BookingCompletePage> {
  bool _loadingDropoffQr = false;
  String? _dropoffQrToken;
  String? _dropoffQrError;
  String? _status;

  @override
  void initState() {
    super.initState();
    _status = widget.result.status;
    BookingReviewApi().persistGuestToken(
      widget.result.bookingNumber,
      widget.result.guestAccessToken,
    );
  }

  bool get _isCompleted => _status == 'COMPLETED';

  Future<void> _loadDropoffQr() async {
    setState(() {
      _loadingDropoffQr = true;
      _dropoffQrError = null;
    });

    try {
      final issue =
          widget.issueDropoffQr ??
          () => BookingApiService().issueDropoffQr(
            bookingNumber: widget.result.bookingNumber,
            guestAccessToken: widget.result.guestAccessToken,
          );
      final result = await issue();
      if (!mounted) return;
      setState(() {
        _status = result.status;
        _dropoffQrToken = result.dropoffQrToken;
        _loadingDropoffQr = false;
      });
    } on BookingApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingDropoffQr = false;
        _dropoffQrToken = null;
        _dropoffQrError = err.errorCode == 'INVALID_STATUS_TRANSITION'
            ? context.l10n.t('booking_dropoff_qr_unavailable')
            : userFacingError(err, fallback: context.l10n.t('ui_action_failed'));
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingDropoffQr = false;
        _dropoffQrError = userFacingError(err, fallback: context.l10n.t('ui_action_failed'));
      });
    }
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
              _SuccessHero(l10n: l10n, trustMessage: result.trustMessage),
              const SizedBox(height: AppTokens.spaceLg),
              _BookingNumberCard(
                bookingNumber: result.bookingNumber,
                statusLabel: l10n.t('status_pending'),
                total: '${result.totalAmount} ${result.currency}',
                paymentLabel: l10n.t('pay_driver_at_destination'),
                l10n: l10n,
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.sectionHeader(context, title: l10n.t('booking_summary')),
              AppUi.surfaceCard(
                child: Column(
                  children: [
                    AppUi.summaryRow(label: l10n.t('service_type'), value: widget.serviceLabel),
                    AppUi.summaryRow(label: l10n.t('origin'), value: widget.originLabel),
                    AppUi.summaryRow(label: l10n.t('destination'), value: widget.destinationLabel),
                  ],
                ),
              ),
              const SizedBox(height: AppTokens.spaceLg),
              if (_isCompleted) ...[
                AppUi.surfaceCard(
                  backgroundColor: AppTokens.successLight,
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline, color: AppTokens.success),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          l10n.t('booking_trip_completed'),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: AppTokens.success,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                BookingNotificationSection(
                  bookingNumber: result.bookingNumber,
                  bookingId: result.bookingId,
                  guestAccessToken: result.guestAccessToken,
                ),
                const SizedBox(height: AppTokens.spaceMd),
                BookingReviewForm(
                  bookingNumber: result.bookingNumber,
                  guestAccessToken: result.guestAccessToken,
                ),
              ] else if (_dropoffQrToken != null)
                _QrDisplay(
                  title: l10n.t('booking_dropoff_qr_title'),
                  hint: l10n.t('booking_dropoff_qr_hint'),
                  token: _dropoffQrToken!,
                )
              else
                _QrDisplay(
                  title: l10n.t('boarding_qr_title'),
                  hint: l10n.t('boarding_qr_hint'),
                  token: result.boardingQrToken,
                ),
              const SizedBox(height: AppTokens.spaceMd),
              BookingChatSection(
                bookingNumber: result.bookingNumber,
                guestAccessToken: result.guestAccessToken,
                api: widget.chatApi,
                socketService: widget.chatSocketService,
              ),
              if (!_isCompleted) ...[
                const SizedBox(height: AppTokens.spaceMd),
                if (_dropoffQrError != null)
                  AppUi.errorState(message: _dropoffQrError!),
                AppUi.secondaryButton(
                  label: _dropoffQrToken == null
                      ? l10n.t('booking_refresh_dropoff_qr')
                      : l10n.t('booking_issue_new_dropoff_qr'),
                  icon: Icons.refresh,
                  onPressed: _loadingDropoffQr ? null : _loadDropoffQr,
                  fullWidth: true,
                ),
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
              const SizedBox(height: AppTokens.spaceSm),
              AppUi.secondaryButton(
                label: l10n.t('chat_after_driver_assignment'),
                icon: Icons.chat_bubble_outline,
                onPressed: null,
                fullWidth: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuccessHero extends StatelessWidget {
  const _SuccessHero({required this.l10n, required this.trustMessage});

  final AppLocalizations l10n;
  final String trustMessage;

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
            child: const Icon(Icons.check_circle, color: AppTokens.success, size: 48),
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
            trustMessage.isNotEmpty ? trustMessage : l10n.t('booking_trust_message'),
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
    required this.total,
    required this.paymentLabel,
    required this.l10n,
  });

  final String bookingNumber;
  final String statusLabel;
  final String total;
  final String paymentLabel;
  final AppLocalizations l10n;

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
          SelectableText(
            bookingNumber,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: AppTokens.primaryDark,
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppUi.statusBadge(statusLabel, tone: AppStatusTone.warning),
            ],
          ),
          const SizedBox(height: AppTokens.spaceMd),
          const Divider(height: 1),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.summaryRow(
            label: l10n.t('total'),
            value: total,
            emphasize: true,
          ),
          AppUi.summaryRow(
            label: l10n.t('payment_method'),
            value: paymentLabel,
          ),
        ],
      ),
    );
  }
}

class _QrDisplay extends StatelessWidget {
  const _QrDisplay({
    required this.title,
    required this.hint,
    required this.token,
  });

  final String title;
  final String hint;
  final String token;

  @override
  Widget build(BuildContext context) {
    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            style: const TextStyle(color: AppTokens.textSecondary, fontSize: 13, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.spaceMd),
          Center(
            child: Container(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              decoration: BoxDecoration(
                color: AppTokens.surface,
                borderRadius: AppTokens.borderRadiusLg,
                border: Border.all(color: AppTokens.border),
                boxShadow: AppTokens.cardShadow(),
              ),
              child: QrImageView(
                data: token,
                size: 200,
                backgroundColor: AppTokens.surface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
