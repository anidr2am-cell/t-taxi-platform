import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/guest_booking_lookup_result.dart';
import '../models/guest_contact_lookup_item.dart';
import '../services/booking_api_service.dart';
import '../services/customer_bookings_api_service.dart';
import '../services/guest_booking_lookup_service.dart';
import '../../auth/services/auth_token_storage.dart';
import '../utils/booking_status_display.dart';
import '../utils/customer_booking_format.dart';
import '../utils/location_display.dart';
import '../widgets/guest_booking_lookup_inquiry_banner.dart';
import '../widgets/booking_notification_section.dart';
import '../widgets/booking_review_form.dart';
import '../widgets/assigned_driver_status_card.dart';
import '../widgets/airport_meeting_guide_card.dart';
import '../widgets/guest_booking_cancel_section.dart';
import '../../driver_location/widgets/guest_driver_tracking_section.dart';

enum _GuestLookupMode { bookingNumber, contactName }

class GuestBookingLookupPage extends StatefulWidget {
  const GuestBookingLookupPage({
    super.key,
    this.lookupService,
    this.enableCustomerTools = false,
    this.fromMyBookings = false,
    this.reviewApi,
    this.trackingBuilder,
    this.initialResult,
    this.customerBookingsApiService,
    this.tokenStorage,
  });

  final GuestBookingLookupService? lookupService;
  final bool enableCustomerTools;
  final bool fromMyBookings;
  final BookingReviewApi? reviewApi;
  final Widget Function(GuestBookingLookupResult result)? trackingBuilder;
  final GuestBookingLookupResult? initialResult;
  final CustomerBookingsApiService? customerBookingsApiService;
  final AuthTokenStorage? tokenStorage;

  @override
  State<GuestBookingLookupPage> createState() => _GuestBookingLookupPageState();
}

class _GuestBookingLookupPageState extends State<GuestBookingLookupPage> {
  final _formKey = GlobalKey<FormState>();
  final _bookingNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  final _nameController = TextEditingController();
  late final GuestBookingLookupService _lookupService =
      widget.lookupService ?? GuestBookingLookupService();
  late final CustomerBookingsApiService _customerBookingsApiService =
      widget.customerBookingsApiService ?? CustomerBookingsApiService();
  late final AuthTokenStorage _tokenStorage =
      widget.tokenStorage ?? AuthTokenStorage();

  _GuestLookupMode _lookupMode = _GuestLookupMode.bookingNumber;
  GuestBookingLookupResult? _result;
  List<GuestContactLookupItem>? _contactResults;
  GuestContactLookupItem? _selectedContact;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  String? _customerAccessToken;

  @override
  void initState() {
    super.initState();
    final initialResult = widget.initialResult;
    if (initialResult != null) {
      _applyInitialResult(initialResult);
    } else {
      _loadCached();
    }
    if (widget.fromMyBookings) {
      _loadCustomerAccessToken();
    }
  }

  Future<void> _loadCustomerAccessToken() async {
    final session = await _tokenStorage.loadSession();
    if (!mounted) return;
    setState(() => _customerAccessToken = session?.accessToken);
  }

  void _applyInitialResult(GuestBookingLookupResult result) {
    _bookingNumberController.text = result.bookingNumber;
    if (result.customerPhone != null && result.customerPhone!.isNotEmpty) {
      _phoneController.text = result.customerPhone!;
    }
    setState(() {
      _result = result;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _bookingNumberController.dispose();
    _phoneController.dispose();
    _nameController.dispose();
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

    if (widget.fromMyBookings) {
      await _refreshFromMyBookings(result);
      return;
    }

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

  Future<void> _refreshFromMyBookings(GuestBookingLookupResult result) async {
    setState(() {
      _refreshing = true;
      _error = null;
    });

    try {
      final refreshed = await _customerBookingsApiService.findMyBookingByNumber(
        result.bookingNumber,
      );
      if (!mounted) return;
      setState(() {
        _result = refreshed;
        _refreshing = false;
      });
    } on CustomerBookingsApiException catch (err) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = userFacingError(
          err,
          fallback: context.l10n.t('guest_lookup_load_error'),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _refreshing = false;
        _error = context.l10n.t('guest_lookup_load_error');
      });
    }
  }

  bool _hasGuestToken(GuestBookingLookupResult result) =>
      result.guestAccessToken.trim().isNotEmpty;

  bool _hasCustomerTokenLoaded() =>
      widget.fromMyBookings && _customerAccessToken?.trim().isNotEmpty == true;

  bool _hasBookingCustomerAuth(GuestBookingLookupResult result) =>
      _hasGuestToken(result) || _hasCustomerTokenLoaded();

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
        _hasBookingCustomerAuth(result);
  }

  bool _canShowNotifications(GuestBookingLookupResult result) {
    return widget.enableCustomerTools &&
        result.capabilities.notificationsAvailable &&
        _hasBookingCustomerAuth(result);
  }

  bool _canShowDriverPhone(GuestBookingLookupResult result) {
    const activeStatuses = {
      'DRIVER_ASSIGNED',
      'ON_ROUTE',
      'DRIVER_ARRIVED',
      'PICKED_UP',
    };
    return activeStatuses.contains(result.status) &&
        result.driverPhone?.trim().isNotEmpty == true &&
        _hasBookingCustomerAuth(result);
  }

  Widget _trackingSection(GuestBookingLookupResult result) {
    return widget.trackingBuilder?.call(result) ??
        GuestDriverTrackingSection(
          bookingId: result.bookingId!,
          guestAccessToken: result.guestAccessToken,
          bookingStatus: result.status,
          useCustomerAuth: widget.fromMyBookings,
          customerAccessToken:
              widget.fromMyBookings ? _customerAccessToken : null,
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

  Future<void> _lookupByContact() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
      _contactResults = null;
      _selectedContact = null;
    });

    try {
      final response = await _lookupService.lookupByContact(
        name: _nameController.text,
        phone: _phoneController.text,
      );
      if (!mounted) return;
      setState(() {
        _contactResults = response.bookings;
        _loading = false;
        if (response.bookings.length == 1) {
          _selectedContact = response.bookings.first;
          _contactResults = null;
        }
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
      _contactResults = null;
      _selectedContact = null;
      _error = null;
      _bookingNumberController.clear();
      _phoneController.clear();
      _nameController.clear();
    });
  }

  void _switchLookupMode(_GuestLookupMode mode) {
    if (_lookupMode == mode) return;
    setState(() {
      _lookupMode = mode;
      _error = null;
      _contactResults = null;
      _selectedContact = null;
    });
  }

  String _pickupPeriodLabel(AppLocalizations l10n, String? period) {
    switch (period) {
      case 'MORNING':
        return l10n.t('guest_lookup_pickup_period_morning');
      case 'AFTERNOON':
        return l10n.t('guest_lookup_pickup_period_afternoon');
      case 'EVENING':
        return l10n.t('guest_lookup_pickup_period_evening');
      default:
        return '';
    }
  }

  String _maskedPickupLabel(AppLocalizations l10n, GuestContactLookupItem item) {
    final date = item.scheduledPickupDate?.trim();
    final period = _pickupPeriodLabel(l10n, item.pickupTimePeriod);
    if (date == null || date.isEmpty) return period;
    if (period.isEmpty) return date;
    return '$date · $period';
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
          child: _result != null
              ? _bookingDetail(_result!)
              : _selectedContact != null
              ? _contactLookupDetail(_selectedContact!)
              : _contactResults != null
              ? _contactLookupList(_contactResults!)
              : _lookupForm(),
        ),
      ),
    );
  }

  Widget _lookupForm() {
    final l10n = context.l10n;
    final isContactMode = _lookupMode == _GuestLookupMode.contactName;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(
            context,
            title: l10n.t('guest_lookup_title'),
            subtitle: isContactMode
                ? l10n.t('guest_lookup_contact_subtitle')
                : l10n.t('guest_lookup_subtitle'),
          ),
          SegmentedButton<_GuestLookupMode>(
            key: const ValueKey('guest_lookup_mode_switch'),
            segments: [
              ButtonSegment(
                value: _GuestLookupMode.bookingNumber,
                label: Text(l10n.t('guest_lookup_mode_booking_number')),
                icon: const Icon(Icons.confirmation_number_outlined),
              ),
              ButtonSegment(
                value: _GuestLookupMode.contactName,
                label: Text(l10n.t('guest_lookup_mode_contact_name')),
                icon: const Icon(Icons.person_outline),
              ),
            ],
            selected: {_lookupMode},
            onSelectionChanged: (selection) =>
                _switchLookupMode(selection.first),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.surfaceCard(
            child: Column(
              children: [
                if (!isContactMode)
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
                      if (isContactMode) return null;
                      final normalized = (value ?? '').trim().toUpperCase();
                      return RegExp(r'^TX\d{12}$').hasMatch(normalized)
                          ? null
                          : l10n.t('guest_lookup_invalid_number');
                    },
                  )
                else
                  TextFormField(
                    key: const ValueKey('guest_lookup_name'),
                    controller: _nameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: l10n.t('guest_lookup_name'),
                      prefixIcon: const Icon(Icons.person_outline),
                    ),
                    validator: (value) {
                      if (!isContactMode) return null;
                      return (value ?? '').trim().isNotEmpty
                          ? null
                          : l10n.t('guest_lookup_invalid_name');
                    },
                  ),
                if (!isContactMode) const SizedBox(height: AppTokens.spaceMd),
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
            onPressed: _loading
                ? null
                : (isContactMode ? _lookupByContact : _lookup),
          ),
        ],
      ),
    );
  }

  Widget _contactLookupList(List<GuestContactLookupItem> items) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(
          context,
          title: l10n.t('guest_lookup_contact_results_title'),
          subtitle: l10n.t('guest_lookup_contact_detail_guidance'),
        ),
        for (final item in items) ...[
          AppUi.surfaceCard(
            child: InkWell(
              key: Key('guest_lookup_contact_card_${item.bookingNumber}'),
              onTap: () => setState(() => _selectedContact = item),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.bookingNumber,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppUi.statusBadge(
                      BookingStatusDisplay.label(
                        l10n,
                        item.status,
                        reassignmentInProgress: item.reassignmentInProgress,
                      ),
                      tone: item.reassignmentInProgress
                          ? AppStatusTone.warning
                          : AppUi.toneForBookingStatus(item.status),
                    ),
                    const SizedBox(height: 8),
                    Text(item.serviceTypeName),
                    if (_maskedPickupLabel(l10n, item).isNotEmpty)
                      Text(
                        _maskedPickupLabel(l10n, item),
                        style: const TextStyle(color: AppTokens.textSecondary),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
        ],
        AppUi.secondaryButton(
          label: l10n.t('guest_lookup_another'),
          icon: Icons.search,
          onPressed: _clear,
          fullWidth: true,
        ),
      ],
    );
  }

  Widget _contactLookupDetail(GuestContactLookupItem item) {
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
                item.bookingNumber,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                  color: AppTokens.primaryDark,
                ),
              ),
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.statusBadge(
                BookingStatusDisplay.label(
                  l10n,
                  item.status,
                  reassignmentInProgress: item.reassignmentInProgress,
                ),
                tone: item.reassignmentInProgress
                    ? AppStatusTone.warning
                    : AppUi.toneForBookingStatus(item.status),
              ),
            ],
          ),
        ),
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
                  l10n.t('guest_lookup_contact_detail_guidance'),
                  style: const TextStyle(
                    color: AppTokens.textSecondary,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        AppUi.sectionHeader(
          context,
          title: l10n.t('guest_lookup_trip_details'),
        ),
        AppUi.surfaceCard(
          child: Column(
            children: [
              if (_maskedPickupLabel(l10n, item).isNotEmpty)
                AppUi.summaryRow(
                  label: l10n.t('guest_lookup_pickup'),
                  value: _maskedPickupLabel(l10n, item),
                ),
              AppUi.summaryRow(
                label: l10n.t('guest_lookup_service'),
                value: item.serviceTypeName,
              ),
              if (item.originName != null || item.originCode != null)
                AppUi.summaryRow(
                  label: l10n.t('guest_lookup_from'),
                  value: item.originName ?? item.originCode ?? '',
                ),
              if (item.destinationName != null || item.destinationCode != null)
                AppUi.summaryRow(
                  label: l10n.t('guest_lookup_to'),
                  value: item.destinationName ?? item.destinationCode ?? '',
                ),
              if (item.passengerTotal != null)
                AppUi.summaryRow(
                  label: l10n.t('guest_lookup_passengers'),
                  value: '${item.passengerTotal}',
                ),
              if (item.luggageTotalPieces != null && item.luggageTotalPieces! > 0)
                AppUi.summaryRow(
                  label: l10n.t('guest_lookup_luggage'),
                  value: '${item.luggageTotalPieces}',
                ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceLg),
        if (_contactResults != null && _contactResults!.length > 1)
          AppUi.secondaryButton(
            label: l10n.t('guest_lookup_contact_back_to_list'),
            icon: Icons.list,
            onPressed: () => setState(() {
              _selectedContact = null;
            }),
            fullWidth: true,
          ),
        AppUi.secondaryButton(
          label: l10n.t('guest_lookup_another'),
          icon: Icons.search,
          onPressed: _clear,
          fullWidth: true,
        ),
      ],
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
        const GuestBookingLookupInquiryBanner(),
        const SizedBox(height: AppTokens.spaceMd),
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
                BookingStatusDisplay.label(
                  l10n,
                  result.status,
                  reassignmentInProgress: result.reassignmentInProgress,
                ),
                tone: result.reassignmentInProgress
                    ? AppStatusTone.warning
                    : AppUi.toneForBookingStatus(result.status),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppTokens.spaceMd),
        _actionSummary(result),
        if (result.driverName?.trim().isNotEmpty == true) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AssignedDriverStatusCard(
            result: result,
            allowDriverPhoneWithoutGuestToken: widget.fromMyBookings &&
                _customerAccessToken?.trim().isNotEmpty == true,
            useCustomerAuth: widget.fromMyBookings,
            customerAccessToken:
                widget.fromMyBookings ? _customerAccessToken : null,
          ),
        ],
        if (BookingStatusDisplay.customerGuidance(
              l10n,
              result.status,
              reassignmentInProgress: result.reassignmentInProgress,
            ) !=
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
                    BookingStatusDisplay.customerGuidance(
                      l10n,
                      result.status,
                      reassignmentInProgress: result.reassignmentInProgress,
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
        const SizedBox(height: AppTokens.spaceMd),
        GuestBookingCancelSection(
          booking: result,
          lookupService: _lookupService,
          customerAccessToken: widget.fromMyBookings ? _customerAccessToken : null,
          tokenStorage: widget.fromMyBookings ? _tokenStorage : null,
          onCancelled: (updated) {
            setState(() {
              _result = updated;
              _error = null;
            });
          },
        ),
        if (reviewSubmitted) ...[
          const SizedBox(height: AppTokens.spaceMd),
          BookingReviewForm(
            key: ValueKey(
              'guest_review_${result.bookingNumber}_${result.status}_submitted',
            ),
            bookingNumber: result.bookingNumber,
            guestAccessToken: result.guestAccessToken,
            customerAccessToken:
                widget.fromMyBookings ? _customerAccessToken : null,
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
            customerAccessToken:
                widget.fromMyBookings ? _customerAccessToken : null,
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
              bookingLocationSummaryRow(
                label: l10n.t('origin'),
                name: result.originName,
                address: result.originAddress,
              ),
              bookingLocationSummaryRow(
                label: l10n.t('destination'),
                name: result.destinationName,
                address: result.destinationAddress,
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
            vehicleInfo: AirportMeetingVehicleInfo(
              driverName: result.driverName,
              driverPhone: _canShowDriverPhone(result)
                  ? result.driverPhone
                  : null,
              vehicleType: result.vehicleType,
              vehicleColor: result.vehicleColor,
              vehiclePlateNumber: result.vehiclePlateNumber,
            ),
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
              customerAccessToken:
                  widget.fromMyBookings ? _customerAccessToken : null,
              useCustomerPushRegistration: widget.fromMyBookings,
            ),
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
            value: BookingStatusDisplay.label(
              l10n,
              result.status,
              reassignmentInProgress: result.reassignmentInProgress,
            ),
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
            BookingStatusDisplay.customerGuidance(
                  l10n,
                  result.status,
                  reassignmentInProgress: result.reassignmentInProgress,
                ) ??
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
