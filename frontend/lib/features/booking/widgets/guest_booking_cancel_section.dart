import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/guest_booking_lookup_result.dart';
import '../services/booking_api_service.dart';
import '../services/guest_booking_lookup_service.dart';
import '../utils/booking_cancel_display.dart';
import '../utils/booking_status_display.dart';
import '../utils/customer_booking_format.dart';

class GuestBookingCancelSection extends StatefulWidget {
  const GuestBookingCancelSection({
    super.key,
    required this.booking,
    required this.onCancelled,
    this.lookupService,
  });

  final GuestBookingLookupResult booking;
  final ValueChanged<GuestBookingLookupResult> onCancelled;
  final GuestBookingLookupService? lookupService;

  @override
  State<GuestBookingCancelSection> createState() =>
      _GuestBookingCancelSectionState();
}

class _GuestBookingCancelSectionState extends State<GuestBookingCancelSection> {
  bool _cancelling = false;
  String? _error;

  GuestBookingLookupService get _lookupService =>
      widget.lookupService ?? GuestBookingLookupService();

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    if (BookingCancelDisplay.isTerminalStatus(booking.status)) {
      return const SizedBox.shrink();
    }

    final l10n = context.l10n;
    final canCancel = booking.canCancel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(context, title: l10n.t('booking_cancel_section')),
        AppUi.surfaceCard(
          backgroundColor: canCancel
              ? AppTokens.warningLight
              : AppTokens.errorLight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                canCancel
                    ? l10n.t('booking_cancel_policy_hint')
                    : BookingCancelDisplay.blockedReasonMessage(
                        l10n,
                        booking.cancellationBlockedReason,
                      ),
                style: TextStyle(
                  color: canCancel ? AppTokens.warning : AppTokens.error,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppTokens.error,
                    height: 1.4,
                  ),
                ),
              ],
              if (canCancel) ...[
                const SizedBox(height: AppTokens.spaceMd),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    key: const ValueKey('guest_booking_cancel_button'),
                    onPressed: _cancelling ? null : _confirmAndCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTokens.error,
                      side: const BorderSide(color: AppTokens.error),
                    ),
                    icon: _cancelling
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cancel_outlined),
                    label: Text(l10n.t('booking_cancel_action')),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _confirmAndCancel() async {
    final l10n = context.l10n;
    final booking = widget.booking;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.t('booking_cancel_confirm_title')),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(l10n.t('booking_cancel_confirm_irreversible')),
                const SizedBox(height: AppTokens.spaceMd),
                AppUi.summaryRow(
                  label: l10n.t('reservation_number'),
                  value: booking.bookingNumber,
                ),
                AppUi.summaryRow(
                  label: l10n.t('pickup_datetime'),
                  value: CustomerBookingFormat.pickupDateTime(
                    l10n,
                    booking.scheduledPickupAt,
                  ),
                ),
                AppUi.summaryRow(
                  label: l10n.t('customer_driver_assignment'),
                  value: BookingCancelDisplay.driverAssignmentLabel(
                    l10n: l10n,
                    status: booking.status,
                    driverName: booking.driverName,
                  ),
                ),
                AppUi.summaryRow(
                  label: l10n.t('status'),
                  value: BookingStatusDisplay.label(l10n, booking.status),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.t('ui_cancel')),
            ),
            TextButton(
              key: const ValueKey('guest_booking_cancel_confirm'),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: AppTokens.error),
              child: Text(l10n.t('booking_cancel_confirm_action')),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _cancelling = true;
      _error = null;
    });

    try {
      final updated = await _lookupService.cancelBooking(booking: booking);
      if (!mounted) return;
      setState(() {
        _cancelling = false;
      });
      widget.onCancelled(updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('booking_cancel_success'))),
      );
    } on BookingApiException catch (err) {
      if (!mounted) return;
      final reason = err.errors.isNotEmpty ? err.errors.first.field : null;
      setState(() {
        _cancelling = false;
        _error = BookingCancelDisplay.blockedReasonMessage(
          l10n,
          reason,
          serverMessage: userFacingError(
            err,
            fallback: l10n.t('booking_cancel_failed'),
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _cancelling = false;
        _error = l10n.t('booking_cancel_failed');
      });
    }
  }
}
