import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_theme.dart';
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
            ? 'Dropoff QR is available after pickup and before trip completion.'
            : err.message;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingDropoffQr = false;
        _dropoffQrError = err.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = widget.result;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('booking_complete'))),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.check_circle, color: AppTheme.success, size: 64),
            const SizedBox(height: 16),
            Text(
              result.trustMessage.isNotEmpty
                  ? result.trustMessage
                  : l10n.t('booking_trust_message'),
              style: TextStyle(color: Colors.grey.shade800, fontSize: 15),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _row(l10n.t('reservation_number'), result.bookingNumber),
                    _row(l10n.t('status'), l10n.t('status_pending')),
                    _row(
                      l10n.t('total'),
                      '${result.totalAmount} ${result.currency}',
                      bold: true,
                    ),
                    _row(
                      l10n.t('payment_method'),
                      l10n.t('pay_driver_at_destination'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.t('booking_summary'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _row(l10n.t('service_type'), widget.serviceLabel),
                    _row(l10n.t('origin'), widget.originLabel),
                    _row(l10n.t('destination'), widget.destinationLabel),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            if (_isCompleted) ...[
              const _QrStatusMessage(message: 'Trip completed'),
              const SizedBox(height: 16),
              BookingNotificationSection(
                bookingNumber: result.bookingNumber,
                bookingId: result.bookingId,
                guestAccessToken: result.guestAccessToken,
              ),
              const SizedBox(height: 16),
              BookingReviewForm(
                bookingNumber: result.bookingNumber,
                guestAccessToken: result.guestAccessToken,
              ),
            ] else if (_dropoffQrToken != null)
              _QrDisplay(
                title: 'Dropoff QR',
                hint: 'Show this QR to your driver at destination.',
                token: _dropoffQrToken!,
              )
            else
              _QrDisplay(
                title: l10n.t('boarding_qr_title'),
                hint: l10n.t('boarding_qr_hint'),
                token: result.boardingQrToken,
              ),
            const SizedBox(height: 16),
            BookingChatSection(
              bookingNumber: result.bookingNumber,
              guestAccessToken: result.guestAccessToken,
              api: widget.chatApi,
              socketService: widget.chatSocketService,
            ),
            const SizedBox(height: 16),
            if (!_isCompleted) ...[
              if (_dropoffQrError != null) ...[
                Text(
                  _dropoffQrError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
              OutlinedButton.icon(
                onPressed: _loadingDropoffQr ? null : _loadDropoffQr,
                icon: _loadingDropoffQr
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  _dropoffQrToken == null
                      ? 'Refresh dropoff QR'
                      : 'Issue new dropoff QR',
                ),
              ),
            ],
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: null,
              icon: const Icon(Icons.chat_bubble_outline),
              label: Text(l10n.t('chat_after_driver_assignment')),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).popUntil((route) => route.isFirst),
              child: Text(l10n.t('app_title')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: bold ? FontWeight.bold : FontWeight.w600,
              ),
            ),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          hint,
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: QrImageView(
              data: token,
              size: 200,
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

class _QrStatusMessage extends StatelessWidget {
  const _QrStatusMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      textAlign: TextAlign.center,
    );
  }
}
