import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/guest_booking_lookup_result.dart';
import '../services/booking_api_service.dart';
import '../services/booking_chat_api.dart';
import '../services/guest_booking_lookup_service.dart';
import '../widgets/booking_chat_section.dart';
import '../widgets/booking_notification_section.dart';
import '../widgets/booking_review_form.dart';
import '../../driver_location/widgets/guest_driver_tracking_section.dart';

class GuestBookingLookupPage extends StatefulWidget {
  const GuestBookingLookupPage({
    super.key,
    this.lookupService,
    this.bookingApiService,
    this.enableCustomerTools = true,
  });

  final GuestBookingLookupService? lookupService;
  final BookingApiService? bookingApiService;
  final bool enableCustomerTools;

  @override
  State<GuestBookingLookupPage> createState() => _GuestBookingLookupPageState();
}

class _GuestBookingLookupPageState extends State<GuestBookingLookupPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookingNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  late final GuestBookingLookupService _lookupService =
      widget.lookupService ?? GuestBookingLookupService();
  late final BookingApiService _bookingApiService =
      widget.bookingApiService ?? BookingApiService();

  GuestBookingLookupResult? _result;
  bool _loading = true;
  String? _error;
  bool _loadingDropoffQr = false;
  String? _dropoffQrToken;

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
    setState(() {
      _result = cached;
      _loading = false;
    });
  }

  Future<void> _lookup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _dropoffQrToken = null;
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
      _dropoffQrToken = null;
      _bookingNumberController.clear();
      _phoneController.clear();
    });
  }

  Future<void> _issueDropoffQr() async {
    final result = _result;
    if (result == null) return;
    setState(() {
      _loadingDropoffQr = true;
      _error = null;
    });
    try {
      final qr = await _bookingApiService.issueDropoffQr(
        bookingNumber: result.bookingNumber,
        guestAccessToken: result.guestAccessToken,
      );
      if (!mounted) return;
      setState(() {
        _dropoffQrToken = qr.dropoffQrToken;
        _loadingDropoffQr = false;
      });
    } on BookingApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingDropoffQr = false;
        _error = err.message;
      });
    }
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
      appBar: AppBar(title: Text(l10n.t('guest_lookup_title'))),
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
                    hintText: 'TX202607010001',
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
                    return digits.length >= 4 ? null : l10n.t('guest_lookup_invalid_phone');
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
                result.status,
                tone: AppUi.toneForBookingStatus(result.status),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.sectionHeader(context, title: l10n.t('guest_lookup_trip_details')),
        AppUi.surfaceCard(
          child: Column(
            children: [
              AppUi.summaryRow(label: l10n.t('guest_lookup_pickup'), value: result.scheduledPickupAt ?? '-'),
              AppUi.summaryRow(label: l10n.t('guest_lookup_service'), value: result.serviceTypeName),
              AppUi.summaryRow(label: l10n.t('guest_lookup_from'), value: result.originAddress),
              AppUi.summaryRow(label: l10n.t('guest_lookup_to'), value: result.destinationAddress),
              if (result.driverName != null) ...[
                const Divider(height: 24),
                AppUi.summaryRow(label: l10n.t('guest_lookup_driver'), value: result.driverName!),
                if (result.driverPhone != null)
                  AppUi.summaryRow(label: l10n.t('guest_lookup_driver_phone'), value: result.driverPhone!),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.sectionHeader(context, title: l10n.t('guest_lookup_payment')),
        AppUi.surfaceCard(
          backgroundColor: AppTokens.accentLight,
          child: Column(
            children: [
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_total'),
                value: '${result.totalAmount} ${result.currency}',
                emphasize: true,
              ),
              AppUi.summaryRow(label: l10n.t('guest_lookup_payment'), value: result.paymentMethod),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _qrSection(result),
        if (_error != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.errorState(message: _error!),
        ],
        if (widget.enableCustomerTools) ...[
          const SizedBox(height: AppTokens.spaceMd),
          if (result.bookingId != null)
            GuestDriverTrackingSection(
              bookingId: result.bookingId!,
              guestAccessToken: result.guestAccessToken,
              bookingStatus: result.status,
            ),
          if (result.bookingId != null) const SizedBox(height: AppTokens.spaceMd),
          if (result.capabilities.notificationsAvailable)
            BookingNotificationSection(
              bookingNumber: result.bookingNumber,
              bookingId: result.bookingId,
              guestAccessToken: result.guestAccessToken,
            ),
          if (result.capabilities.chatAvailable) ...[
            const SizedBox(height: AppTokens.spaceMd),
            BookingChatSection(
              bookingNumber: result.bookingNumber,
              guestAccessToken: result.guestAccessToken,
              api: const BookingChatApi(),
            ),
          ],
          if (result.capabilities.reviewAvailable) ...[
            const SizedBox(height: AppTokens.spaceMd),
            BookingReviewForm(
              bookingNumber: result.bookingNumber,
              guestAccessToken: result.guestAccessToken,
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

  Widget _qrSection(GuestBookingLookupResult result) {
    if (result.status == 'COMPLETED') {
      return AppUi.surfaceCard(
        backgroundColor: AppTokens.surfaceMuted,
        child: Text(
          context.l10n.t('guest_lookup_trip_completed_qr_hidden'),
          style: const TextStyle(color: AppTokens.textSecondary),
        ),
      );
    }

    if (_dropoffQrToken != null) {
      return AppUi.surfaceCard(
        child: SelectableText(
          context.l10n.t('guest_lookup_dropoff_qr_token').replaceAll('{token}', _dropoffQrToken!),
        ),
      );
    }

    if (result.capabilities.dropoffQrIssueAvailable) {
      return AppUi.primaryButton(
        label: context.l10n.t('guest_lookup_issue_dropoff_qr'),
        icon: Icons.qr_code,
        loading: _loadingDropoffQr,
        onPressed: _loadingDropoffQr ? null : _issueDropoffQr,
      );
    }

    if (result.capabilities.boardingQrPreviouslyIssued) {
      return AppUi.surfaceCard(
        backgroundColor: AppTokens.infoLight,
        child: Text(
          context.l10n.t('guest_lookup_boarding_qr_security'),
          style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
