import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../widgets/language_selector.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_route_args.dart';
import '../models/booking_wizard_state.dart';
import '../models/booking_wizard_steps.dart';
import '../models/location_option.dart';
import '../models/service_type_option.dart';
import '../pages/booking_complete_page.dart';
import '../pages/booking_contact_connect_page.dart';
import '../pages/urgent_booking_flow_page.dart';
import '../models/booking_contact_connect_args.dart';
import '../utils/customer_booking_format.dart';
import '../services/booking_analytics.dart';
import '../widgets/airport_meeting_guide_card.dart';
import '../widgets/booking_progress_header.dart';
import '../widgets/booking_review_form.dart';
import '../widgets/booking_summary_bar.dart';
import '../widgets/step_confirmation.dart';
import '../widgets/step_customer_info.dart';
import '../widgets/step_passengers_luggage.dart';
import '../widgets/step_pickup_datetime.dart';
import '../widgets/step_route_select.dart';
import '../widgets/step_vehicle_select.dart';
import '../widgets/wizard_compact.dart';
import '../widgets/wizard_status_views.dart';
import '../../auth/widgets/booking_social_login_section.dart';

class BookingWizardPage extends StatefulWidget {
  const BookingWizardPage({
    super.key,
    this.now,
    this.controller,
    this.routeArgs,
  });

  /// Fixed clock for tests. Ignored when [controller] is provided.
  final DateTime Function()? now;

  /// Preconfigured controller for tests. Skips [BookingWizardController.initialize].
  final BookingWizardController? controller;

  /// Route-level prefill from the landing page booking widget.
  final BookingWizardRouteArgs? routeArgs;

  @override
  State<BookingWizardPage> createState() => _BookingWizardPageState();
}

class _BookingWizardPageState extends State<BookingWizardPage> {
  late final BookingWizardController _controller;
  final FocusNode _originFocusNode = FocusNode();
  final FocusNode _destinationFocusNode = FocusNode();
  final FocusNode _customerNameFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  int? _lastTrackedStep;
  bool _sessionStartedTracked = false;

  void _syncAnalytics(BuildContext context) {
    if (!_controller.isInitialized) return;
    final width = MediaQuery.sizeOf(context).width;
    final locale = context.read<LocaleState>().languageCode;
    _controller.syncAnalyticsContext(
      locale: locale,
      deviceType: BookingAnalytics.deviceTypeForWidth(width),
    );
    if (!_sessionStartedTracked) {
      _sessionStartedTracked = true;
      _controller.analytics.trackBookingStarted(
        locale: locale,
        deviceType: BookingAnalytics.deviceTypeForWidth(width),
      );
    }
    final step = _controller.state.step;
    if (_lastTrackedStep == step) return;
    _lastTrackedStep = step;
    _resetScrollToTop();
    _controller.analytics.trackStepViewed(
      stepNumber: step + 1,
      stepName: BookingAnalytics.stepNameFor(step),
    );
    if (step == BookingWizardSteps.review) {
      final state = _controller.state;
      _controller.analytics.trackBookingReviewViewed(
        vehicleType: state.selectedVehicle,
        routeType: BookingAnalytics.routeTypeFor(state.serviceType),
      );
      _customerAccessTokenForSubmit().then((accessToken) {
        if (!mounted) return;
        _controller.loadAvailableCoupons(accessToken: accessToken);
      });
    }
  }

  void _resetScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_scrollController.offset != 0) {
        _scrollController.jumpTo(0);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? BookingWizardController(now: widget.now);
    if (widget.controller != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.syncDerivedData();
      });
    } else {
      final args = widget.routeArgs;
      if (args != null) {
        _controller
            .applyRoutePrefill(
              serviceType: args.serviceType,
              origin: args.origin,
              destination: args.destination,
              initialStep: args.initialStep,
            )
            .then((_) {
          if (mounted) _controller.syncDerivedData();
        });
      } else {
        _controller.initialize().then((_) {
          if (mounted) _controller.syncDerivedData();
        });
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _originFocusNode.dispose();
    _destinationFocusNode.dispose();
    _customerNameFocusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String _wizardErrorText(AppLocalizations l10n, String? message) {
    if (message == null || message.isEmpty) return '';
    return l10n.t(message);
  }

  String? _formattedPrice(BookingWizardState state) {
    final pricing = state.pricing;
    if (pricing == null) return null;
    return CustomerBookingFormat.money(pricing.totalAmount, pricing.currency);
  }

  String _ctaLabel(AppLocalizations l10n, BookingWizardState state) {
    final price = _formattedPrice(state);
    switch (state.step) {
      case BookingWizardSteps.route:
        return l10n.t('wizard_cta_route');
      case BookingWizardSteps.schedule:
        return l10n.t('wizard_cta_schedule');
      case BookingWizardSteps.vehicle:
        if (state.selectedVehicle == null || price == null) {
          return l10n.t('wizard_cta_vehicle_unselected');
        }
        return l10n
            .t('wizard_cta_vehicle_selected')
            .replaceAll('{price}', price);
      case BookingWizardSteps.customer:
        return price == null
            ? l10n.t('customer_review_booking')
            : l10n.t('wizard_cta_customer').replaceAll('{price}', price);
      case BookingWizardSteps.review:
        return price == null
            ? l10n.t('customer_confirm_booking')
            : l10n.t('wizard_cta_confirm').replaceAll('{price}', price);
      default:
        return l10n.t('ui_next');
    }
  }

  Future<void> _handleAdvance() async {
    if (_controller.isSubmitting || _controller.isLoading) return;
    final state = _controller.state;
    if (state.step == BookingWizardSteps.review) return;

    final advanced = await _controller.goNext();
    if (!advanced && mounted && _controller.state.errorMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _wizardErrorText(context.l10n, _controller.state.errorMessage),
          ),
        ),
      );
    }
  }

  Future<void> _handleSubmit() async {
    if (_controller.isSubmitting || _controller.isLoading) return;
    if (_controller.state.step != BookingWizardSteps.review) return;

    await _submitBooking(bookingMode: 'STANDARD');
  }

  Future<void> _handleUrgentSubmit() async {
    if (_controller.isSubmitting || _controller.isLoading) return;
    if (_controller.state.step != BookingWizardSteps.review) return;
    if (!_controller.isUrgentPickupWindowSelected()) return;

    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('customer_urgent_confirm_title')),
        content: Text(l10n.t('customer_urgent_confirm_body')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.t('ui_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.t('customer_urgent_confirm_submit')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _submitBooking(bookingMode: 'URGENT');
  }

  Future<String?> _customerAccessTokenForSubmit() async {
    final authController = AuthScope.maybeOf(context);
    if (authController == null || !authController.isLoggedIn) {
      return null;
    }
    return authController.customerSession.tokenStorage.readAccessToken();
  }

  Future<void> _submitBooking({required String bookingMode}) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    await _controller.prepareForSubmit();

    final canSubmit = bookingMode == 'URGENT'
        ? _controller.canSubmitUrgent()
        : _controller.canSubmitStandard();
    if (!canSubmit) {
      final firstIncomplete = _controller.firstIncompleteStep();
      if (firstIncomplete != null) {
        await _controller.goToStep(firstIncomplete);
      }
      return;
    }

    final snapshot = _controller.state;
    final review = _controller.buildCompleteReview();
    final serviceLabel = l10n.t(snapshot.serviceType?.labelKey ?? '');
    final scheduledPickupAt = _controller.scheduledPickupAtIsoFor(snapshot);
    final accessToken = await _customerAccessTokenForSubmit();

    final result = bookingMode == 'URGENT'
        ? await _controller.submitUrgentBooking(accessToken: accessToken)
        : await _controller.submitBooking(accessToken: accessToken);
    if (result == null) {
      if (_controller.state.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _wizardErrorText(l10n, _controller.state.errorMessage),
            ),
          ),
        );
        final errorStep =
            _controller.firstIncompleteStep() ?? _controller.state.step;
        await _controller.goToStep(errorStep);
      }
      return;
    }

    if (!mounted) return;

    final guestToken = result.guestAccessToken;
    if (guestToken != null && guestToken.isNotEmpty) {
      await const BookingReviewApi().persistGuestToken(
        result.bookingNumber,
        guestToken,
      );
    }

    final needsContactConnect = result.contactConnectionRequired ||
        result.contactStatus == 'PENDING';

    if (needsContactConnect) {
      final connectArgs = BookingContactConnectArgs(
        result: result,
        serviceLabel: serviceLabel,
        origin: snapshot.origin,
        destination: snapshot.destination,
        review: review,
        serviceTypeCode: snapshot.serviceType?.apiCode,
        originAirportCode: snapshot.origin?.kind == LocationKind.airport
            ? snapshot.origin?.code
            : null,
        nameSignRequested: snapshot.nameSign,
        customerPhone: snapshot.customerPhone,
        scheduledPickupAt: scheduledPickupAt,
        selectedVehicle: snapshot.selectedVehicle,
        isUrgent: bookingMode == 'URGENT' || result.isUrgentRequest,
        meetingVehicleInfo: AirportMeetingVehicleInfo(
          vehicleType: snapshot.selectedVehicle,
        ),
      );
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => BookingContactConnectPage(
            bookingNumber: result.bookingNumber,
            args: connectArgs,
          ),
        ),
      );
      return;
    }

    if (bookingMode == 'URGENT' || result.isUrgentRequest) {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => UrgentBookingFlowPage(
            result: result,
            customerPhone: snapshot.customerPhone,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BookingCompletePage(
          result: result,
          serviceLabel: serviceLabel,
          origin: snapshot.origin,
          destination: snapshot.destination,
          review: review,
          serviceTypeCode: snapshot.serviceType?.apiCode,
          originAirportCode: snapshot.origin?.kind == LocationKind.airport
              ? snapshot.origin?.code
              : null,
          nameSignRequested: snapshot.nameSign,
          customerPhone: snapshot.customerPhone,
          scheduledPickupAt: scheduledPickupAt,
          selectedVehicle: snapshot.selectedVehicle,
          enableCustomerTools: true,
          meetingVehicleInfo: AirportMeetingVehicleInfo(
            vehicleType: snapshot.selectedVehicle,
          ),
        ),
      ),
    );
  }

  Widget _buildTrustNotes(AppLocalizations l10n, {bool includeFlight = false}) {
    final keys = [
      'wizard_trust_toll_included',
      'wizard_trust_no_airport_parking',
      'wizard_trust_no_night_surcharge',
      if (includeFlight) 'wizard_trust_flight_delay_wait',
    ];
    return AppUi.surfaceCard(
      backgroundColor: AppTokens.accentLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < keys.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.check_circle_outline, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.t(keys[i]),
                    style: const TextStyle(height: 1.4),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepContent(
    int step,
    BookingWizardState state,
    String locale,
    AppLocalizations l10n,
  ) {
    switch (step) {
      case BookingWizardSteps.route:
        return StepRouteSelect(
          state: state,
          controller: _controller,
          languageCode: locale,
          originFocusNode: _originFocusNode,
          destinationFocusNode: _destinationFocusNode,
        );
      case BookingWizardSteps.schedule:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepPickupDateTime(
              embedded: true,
              state: state,
              controller: _controller,
              onFlightNumberChanged: (value) =>
                  _controller.updateCustomerInfo(flightNumber: value),
            ),
            const SizedBox(height: WizardCompact.sectionGap),
            _buildTrustNotes(
              l10n,
              includeFlight:
                  state.serviceType == BookingServiceType.airportPickup,
            ),
          ],
        );
      case BookingWizardSteps.vehicle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StepPassengersLuggage(
              embedded: true,
              state: state,
              controller: _controller,
              onRetryRecommendation: _controller.loadRecommendation,
            ),
            const SizedBox(height: WizardCompact.sectionGap),
            StepVehicleSelect(
              embedded: true,
              state: state,
              controller: _controller,
            ),
            const SizedBox(height: WizardCompact.sectionGap),
            _buildTrustNotes(
              l10n,
              includeFlight:
                  state.serviceType == BookingServiceType.airportPickup,
            ),
          ],
        );
      case BookingWizardSteps.customer:
        return StepCustomerInfo(
          embedded: true,
          state: state,
          nameFocusNode: _customerNameFocusNode,
          onNameChanged: (v) => _controller.updateCustomerInfo(name: v),
          onEmailChanged: (v) => _controller.updateCustomerInfo(email: v),
          onPhoneChanged: (v) => _controller.updateCustomerInfo(phone: v),
          onCountryChanged: (v) =>
              _controller.updateCustomerInfo(countryCode: v),
          onAdditionalRequestsChanged: (v) =>
              _controller.updateCustomerInfo(additionalRequests: v),
        );
      case BookingWizardSteps.review:
        return StepConfirmation(
          embedded: true,
          state: state,
          onEditStep: (editStep) => _controller.goToStepForEdit(editStep),
          availableCoupons: _controller.availableCoupons,
          loadingCoupons: _controller.loadingCoupons,
          onCouponSelected: _controller.selectCoupon,
          estimatedTotal: _controller.estimatedTotalAfterCoupon(),
          couponDiscount: _controller.appliedCouponDiscount(),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.watch<LocaleState>().languageCode;
    final maxWidth = MediaQuery.sizeOf(context).width > 720
        ? 720.0
        : double.infinity;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (!_controller.isInitialized) {
          return const Scaffold(body: WizardLoadingView());
        }

        _syncAnalytics(context);

        final state = _controller.state;
        final isReviewStep = state.step == BookingWizardSteps.review;
        final isUrgentWindow = _controller.isUrgentPickupWindowSelected();
        final isBusy = _controller.isLoading || _controller.isSubmitting;
        final canAdvance =
            !isReviewStep && _controller.canProceedFromCurrentStep() && !isBusy;
        final canSubmitStandard =
            isReviewStep &&
            !isUrgentWindow &&
            _controller.canSubmitStandard() &&
            !isBusy;
        final canSubmitUrgent =
            isReviewStep &&
            isUrgentWindow &&
            _controller.canSubmitUrgent() &&
            !isBusy;
        final showAdvanceCta = !isReviewStep;
        final validationKey = _controller.stepValidationMessageKey(state.step);
        final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
        const ctaBarReserveHeight = 88.0;
        final scrollBottomPadding = keyboardVisible
            ? AppTokens.spaceMd
            : AppTokens.spaceMd + ctaBarReserveHeight;

        return PopScope(
          canPop: state.step == BookingWizardSteps.route,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop && state.step > BookingWizardSteps.route) {
              _controller.goBack();
            }
          },
          child: Scaffold(
            resizeToAvoidBottomInset: true,
            appBar: AppBar(
              title: Text(l10n.t(BookingWizardSteps.titleKey(state.step))),
              leading: state.step > BookingWizardSteps.route
                  ? Semantics(
                      label: l10n.t('back'),
                      button: true,
                      child: BackButton(onPressed: _controller.goBack),
                    )
                  : null,
              actions: const [LanguageSelector()],
            ),
            body: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Column(
                  children: [
                    BookingProgressHeader(currentStep: state.step),
                    if (state.step >= BookingWizardSteps.schedule)
                      BookingSummaryBar(
                        state: state,
                        controller: _controller,
                      ),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: EdgeInsets.fromLTRB(
                          AppTokens.spaceMd,
                          AppTokens.spaceMd,
                          AppTokens.spaceMd,
                          scrollBottomPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (validationKey != null &&
                                !isReviewStep &&
                                !_controller.canProceedFromCurrentStep())
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: AppUi.surfaceCard(
                                  backgroundColor: AppTokens.warningLight,
                                  child: Text(
                                    l10n.t(validationKey),
                                    style: const TextStyle(height: 1.45),
                                  ),
                                ),
                              ),
                            _buildStepContent(state.step, state, locale, l10n),
                          ],
                        ),
                      ),
                    ),
                    if (!keyboardVisible)
                      Container(
                        key: const Key('booking_wizard_cta_bar'),
                        decoration: const BoxDecoration(
                          color: AppTokens.surface,
                          border: Border(top: BorderSide(color: AppTokens.border)),
                          boxShadow: [
                            BoxShadow(
                              color: Color(0x0F000000),
                              blurRadius: 12,
                              offset: Offset(0, -2),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.all(AppTokens.spaceMd),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (isReviewStep && isUrgentWindow) ...[
                                  AppUi.surfaceCard(
                                    backgroundColor: AppTokens.warningLight,
                                    child: Text(
                                      l10n.t('customer_urgent_pickup_hint'),
                                      style: const TextStyle(height: 1.45),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                if (showAdvanceCta)
                                  Semantics(
                                    button: true,
                                    label: _ctaLabel(l10n, state),
                                    child: SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: ElevatedButton(
                                        onPressed:
                                            canAdvance ? _handleAdvance : null,
                                        child: Text(
                                          _ctaLabel(l10n, state),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                  ),
                                if (canSubmitUrgent)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: FilledButton(
                                      onPressed: _handleUrgentSubmit,
                                      child: _controller.isSubmitting
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : Text(l10n.t('customer_urgent_request')),
                                    ),
                                  ),
                                if (canSubmitStandard)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 48,
                                    child: ElevatedButton(
                                      onPressed: _handleSubmit,
                                      child: _controller.isSubmitting
                                          ? Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                    strokeWidth: 2,
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Flexible(
                                                  child: Text(
                                                    l10n.t(
                                                      'customer_booking_processing',
                                                    ),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            )
                                          : Text(_ctaLabel(l10n, state)),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
