import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/browser_download.dart';
import '../../../utils/voucher_print.dart';
import '../../platform_settings/services/platform_settings_api_service.dart';
import '../models/guest_booking_lookup_result.dart';
import '../utils/customer_booking_format.dart';
import '../utils/booking_status_display.dart';
import 'assigned_driver_status_card.dart';
import 'guest_driver_vehicle_photo.dart';
import 'preferred_support_button.dart';

/// Receives only an already-authorized lookup result. No public booking lookup.
class BookingVoucher extends StatefulWidget {
  const BookingVoucher({
    super.key,
    required this.result,
    this.customerAccessToken,
    this.useCustomerAuth = false,
  });
  final GuestBookingLookupResult result;
  final String? customerAccessToken;
  final bool useCustomerAuth;
  @override
  State<BookingVoucher> createState() => _BookingVoucherState();
}

class _BookingVoucherState extends State<BookingVoucher> {
  final _capture = GlobalKey();
  Map<String, dynamic> _settings = {};
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    const PlatformSettingsApiService()
        .getPublic()
        .then((data) {
          if (mounted) setState(() => _settings = data);
        })
        .catchError((_) {});
  }

  Future<void> _export(bool print) async {
    setState(() => _saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary =
          _capture.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      final bytes = data!.buffer.asUint8List();
      if (print) {
        printVoucher(bytes);
      } else {
        downloadBytes(bytes, '${widget.result.bookingNumber}.png', 'image/png');
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('cx_export_error'))),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n, r = widget.result;
    final meeting =
        _settings['meeting${r.originAirportCode}_${l.languageCode}']
            as String? ??
        '';
    Widget row(String label, String value) => Padding(
      padding: const EdgeInsets.only(top: AppTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTokens.textSecondary)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepaintBoundary(
          key: _capture,
          child: Container(
            padding: const EdgeInsets.all(AppTokens.spaceMd),
            decoration: BoxDecoration(
              color: AppTokens.surface,
              borderRadius: AppTokens.borderRadiusLg,
              border: Border.all(color: AppTokens.primary),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'T-Rider · ${l.t('cx_voucher')}',
                  style: const TextStyle(
                    color: AppTokens.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                row(l.t('guest_lookup_booking_number'), r.bookingNumber),
                row(
                  l.t('status'),
                  BookingStatusDisplay.label(
                    l,
                    r.status,
                    reassignmentInProgress: r.reassignmentInProgress,
                  ),
                ),
                row(
                  l.t('guest_lookup_pickup'),
                  CustomerBookingFormat.pickupDateTime(l, r.scheduledPickupAt),
                ),
                row(l.t('origin'), r.originName ?? r.originAddress),
                if (r.originName != null && r.originAddress != r.originName)
                  Text(r.originAddress),
                row(
                  l.t('destination'),
                  r.destinationName ?? r.destinationAddress,
                ),
                if (r.destinationName != null &&
                    r.destinationAddress != r.destinationName)
                  Text(r.destinationAddress),
                if (r.flightNumber?.isNotEmpty == true)
                  row(l.t('cx_flight'), r.flightNumber!),
                row(
                  l.t('guest_lookup_vehicle'),
                  l.t('cx_vehicle_${r.vehicleType?.toUpperCase()}') ==
                          'cx_vehicle_${r.vehicleType?.toUpperCase()}'
                      ? (r.vehicleType ?? '—')
                      : l.t('cx_vehicle_${r.vehicleType?.toUpperCase()}'),
                ),
                row(l.t('total'), '${r.totalAmount} ${r.currency}'),
                row(
                  l.t('payment_method'),
                  CustomerBookingFormat.paymentMethod(l, r.paymentMethod),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Text(l.t('customer_price_conditions')),
                const SizedBox(height: AppTokens.spaceSm),
                Text(l.t('booking_cancel_policy_hint')),
                if (meeting.trim().isNotEmpty &&
                    r.serviceTypeCode == 'AIRPORT_PICKUP')
                  row(l.t('cx_meeting'), meeting),
                if (r.driverName?.isNotEmpty == true) ...[
                  if (r.driverPhotoUrl?.isNotEmpty == true)
                    GuestDriverVehiclePhoto(
                      photoPath: r.driverPhotoUrl!,
                      guestAccessToken: r.guestAccessToken,
                      useCustomerAuth: widget.useCustomerAuth,
                      customerAccessToken: widget.customerAccessToken,
                      height: 96,
                    ),
                  if (r.vehicleModel?.isNotEmpty == true)
                    row(l.t('guest_lookup_vehicle'), r.vehicleModel!),
                  AssignedDriverStatusCard(
                    result: r,
                    useCustomerAuth: widget.useCustomerAuth,
                    customerAccessToken: widget.customerAccessToken,
                    allowDriverPhoneWithoutGuestToken:
                        widget.useCustomerAuth &&
                        widget.customerAccessToken?.trim().isNotEmpty == true,
                  ),
                ],
              ],
            ),
          ),
        ),
        const PreferredSupportButton(),
        Wrap(
          spacing: AppTokens.spaceSm,
          children: [
            TextButton.icon(
              onPressed: _saving ? null : () => _export(false),
              icon: const Icon(Icons.image_outlined),
              label: Text(l.t('cx_save_image')),
            ),
            TextButton.icon(
              onPressed: _saving ? null : () => _export(true),
              icon: const Icon(Icons.print_outlined),
              label: Text(l.t('cx_print')),
            ),
            TextButton.icon(
              onPressed: () => Navigator.pushNamed(context, '/support'),
              icon: const Icon(Icons.support_agent),
              label: Text(l.t('landing_support_cta')),
            ),
          ],
        ),
      ],
    );
  }
}
