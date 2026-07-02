import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../../widgets/language_selector.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/location_option.dart';
import '../models/service_type_option.dart';
import '../pages/booking_complete_page.dart';
import '../widgets/airport_meeting_guide_card.dart';
import '../widgets/step_customer_info.dart';
import '../widgets/step_destination_select.dart';
import '../widgets/step_origin_select.dart';
import '../widgets/step_passengers_luggage.dart';
import '../widgets/step_pickup_datetime.dart';
import '../widgets/step_service_select.dart';
import '../widgets/step_vehicle_select.dart';
import '../widgets/wizard_compact.dart';
import '../widgets/wizard_section_card.dart';
import '../widgets/wizard_status_views.dart';
import '../widgets/wizard_step_indicator.dart';

class BookingWizardPage extends StatefulWidget {
  const BookingWizardPage({super.key});

  @override
  State<BookingWizardPage> createState() => _BookingWizardPageState();
}

class _BookingWizardPageState extends State<BookingWizardPage> {
  late final BookingWizardController _controller;
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    BookingWizardState.stepCount,
    (_) => GlobalKey(),
  );
  late final List<FocusNode> _sectionFocusNodes = List.generate(
    BookingWizardState.stepCount,
    (_) => FocusNode(),
  );

  @override
  void initState() {
    super.initState();
    _controller = BookingWizardController();
    _controller.initialize().then((_) {
      if (mounted) _controller.syncDerivedData();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final node in _sectionFocusNodes) {
      node.dispose();
    }
    _controller.dispose();
    super.dispose();
  }

  String _wizardErrorText(AppLocalizations l10n, String? message) {
    if (message == null || message.isEmpty) return '';
    return l10n.t(message);
  }

  void _scrollToSection(int step) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _sectionKeys[step].currentContext;
      if (target == null) return;
      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: 0.06,
      );
      if (_sectionFocusNodes[step].canRequestFocus) {
        _sectionFocusNodes[step].requestFocus();
      }
    });
  }

  String _stepTitle(AppLocalizations l10n, int step) {
    switch (step) {
      case 0:
        return l10n.t('select_service');
      case 1:
        return l10n.t('origin');
      case 2:
        return l10n.t('destination');
      case 3:
        return l10n.t('pickup_datetime');
      case 4:
        return l10n.t('passengers');
      case 5:
        return l10n.t('select_vehicle');
      case 6:
        return l10n.t('customer_info');
      default:
        return l10n.t('book_your_ride');
    }
  }

  Future<void> _handleSubmit() async {
    if (_controller.isSubmitting || _controller.isLoading) return;

    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);

    await _controller.prepareForSubmit();

    final firstIncomplete = _controller.firstIncompleteStep();
    if (firstIncomplete != null) {
      _scrollToSection(firstIncomplete);
      return;
    }

    if (!_controller.canSubmitAll()) return;

    final snapshot = _controller.state;
    final review = _controller.buildCompleteReview();
    final serviceLabel = l10n.t(snapshot.serviceType?.labelKey ?? '');
    final originLabel = _controller.formatLocationLabel(snapshot.origin);
    final destinationLabel = _controller.formatLocationLabel(
      snapshot.destination,
    );

    final result = await _controller.submitBooking();
    if (result == null) {
      if (_controller.state.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              _wizardErrorText(l10n, _controller.state.errorMessage),
            ),
          ),
        );
        final errorStep = _controller.firstIncompleteStep() ?? 6;
        _scrollToSection(errorStep);
      }
      return;
    }

    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => BookingCompletePage(
          result: result,
          serviceLabel: serviceLabel,
          originLabel: originLabel,
          destinationLabel: destinationLabel,
          review: review,
          serviceTypeCode: snapshot.serviceType?.apiCode,
          originAirportCode: snapshot.origin?.kind == LocationKind.airport
              ? snapshot.origin?.code
              : null,
          nameSignRequested: snapshot.nameSign,
          meetingVehicleInfo: AirportMeetingVehicleInfo(
            vehicleType: snapshot.selectedVehicle,
          ),
        ),
      ),
    );
  }

  Widget _buildStepContent(int step, BookingWizardState state, String locale) {
    switch (step) {
      case 0:
        return StepServiceSelect(
          embedded: true,
          selected: state.serviceType,
          onSelected: _controller.selectService,
        );
      case 1:
        return StepOriginSelect(
          embedded: true,
          serviceType: state.serviceType,
          selected: state.origin,
          languageCode: locale,
          focusNode: _sectionFocusNodes[1],
          onSelected: _controller.setOrigin,
        );
      case 2:
        return StepDestinationSelect(
          embedded: true,
          serviceType: state.serviceType,
          selected: state.destination,
          languageCode: locale,
          focusNode: _sectionFocusNodes[2],
          onSelected: _controller.setDestination,
        );
      case 3:
        return StepPickupDateTime(
          embedded: true,
          state: state,
          controller: _controller,
          focusNode: _sectionFocusNodes[3],
          onFlightNumberChanged: (value) =>
              _controller.updateCustomerInfo(flightNumber: value),
        );
      case 4:
        return StepPassengersLuggage(
          embedded: true,
          state: state,
          controller: _controller,
          onRetryRecommendation: _controller.loadRecommendation,
        );
      case 5:
        return StepVehicleSelect(
          embedded: true,
          state: state,
          controller: _controller,
        );
      case 6:
        return StepCustomerInfo(
          embedded: true,
          state: state,
          nameFocusNode: _sectionFocusNodes[6],
          onNameChanged: (v) => _controller.updateCustomerInfo(name: v),
          onEmailChanged: (v) => _controller.updateCustomerInfo(email: v),
          onPhoneChanged: (v) => _controller.updateCustomerInfo(phone: v),
          onCountryChanged: (v) =>
              _controller.updateCustomerInfo(countryCode: v),
          onMessengerTypeChanged: (v) =>
              _controller.updateCustomerInfo(messengerType: v),
          onMessengerIdChanged: (v) =>
              _controller.updateCustomerInfo(messengerId: v),
          onAdditionalRequestsChanged: (v) =>
              _controller.updateCustomerInfo(additionalRequests: v),
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

        final state = _controller.state;
        final canSubmit =
            _controller.canSubmitAll() &&
            !_controller.isLoading &&
            !_controller.isSubmitting;

        return Scaffold(
          appBar: AppBar(
            title: Text(l10n.t('book_your_ride')),
            actions: const [LanguageSelector()],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  WizardStepIndicator(
                    completedRequired: _controller.completedRequiredCount,
                    totalRequired: _controller.totalRequiredCount,
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      padding: AppUi.pagePadding(context),
                      child: Column(
                        children: [
                          for (
                            var i = 0;
                            i < BookingWizardState.stepCount;
                            i++
                          ) ...[
                            KeyedSubtree(
                              key: _sectionKeys[i],
                              child: WizardSectionCard(
                                stepNumber: i + 1,
                                title: _stepTitle(l10n, i),
                                validationHint:
                                    !_controller.canProceedFromStep(i)
                                    ? () {
                                        final key = _controller
                                            .stepValidationMessageKey(i);
                                        return key != null ? l10n.t(key) : null;
                                      }()
                                    : null,
                                child: _buildStepContent(i, state, locale),
                              ),
                            ),
                            if (i < BookingWizardState.stepCount - 1)
                              const SizedBox(height: WizardCompact.sectionGap),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Container(
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
                      child: Padding(
                        padding: const EdgeInsets.all(AppTokens.spaceMd),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed: canSubmit ? _handleSubmit : null,
                            child: _controller.isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l10n.t('confirm')),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
