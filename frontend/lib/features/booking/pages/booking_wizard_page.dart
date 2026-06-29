import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../providers/booking_provider.dart';
import '../../../widgets/language_selector.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/service_type_option.dart';
import '../pages/booking_complete_page.dart';
import '../widgets/step_confirmation.dart';
import '../widgets/step_customer_info.dart';
import '../widgets/step_destination_select.dart';
import '../widgets/step_origin_select.dart';
import '../widgets/step_passengers_luggage.dart';
import '../widgets/step_pickup_datetime.dart';
import '../widgets/step_service_select.dart';
import '../widgets/step_vehicle_select.dart';
import '../widgets/wizard_status_views.dart';
import '../widgets/wizard_step_indicator.dart';

class BookingWizardPage extends StatefulWidget {
  const BookingWizardPage({super.key});

  @override
  State<BookingWizardPage> createState() => _BookingWizardPageState();
}

class _BookingWizardPageState extends State<BookingWizardPage> {
  late final BookingWizardController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BookingWizardController();
    _controller.initialize();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
        return l10n.t('booking_summary');
      case 7:
        return l10n.t('customer_info');
      default:
        return l10n.t('app_title');
    }
  }

  Future<void> _handleNext() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _controller.goNext();
    if (!ok && _controller.state.errorMessage != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(_controller.state.errorMessage!)),
      );
    }
  }

  Future<void> _handleSubmit() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final snapshot = _controller.state;
    final serviceLabel = l10n.t(snapshot.serviceType?.labelKey ?? '');
    final originLabel = _controller.formatLocationLabel(snapshot.origin);
    final destinationLabel = _controller.formatLocationLabel(
      snapshot.destination,
    );

    final result = await _controller.submitBooking();
    if (result == null) {
      if (_controller.state.errorMessage != null) {
        messenger.showSnackBar(
          SnackBar(content: Text(_controller.state.errorMessage!)),
        );
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
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final locale = context.watch<LocaleState>().languageCode;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        if (!_controller.isInitialized) {
          return const Scaffold(body: WizardLoadingView());
        }

        final state = _controller.state;
        if (state.step == 4 &&
            state.recommendation == null &&
            !_controller.isLoading &&
            state.errorMessage == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _controller.loadRecommendation();
          });
        }
        final maxWidth = MediaQuery.sizeOf(context).width > 720
            ? 720.0
            : double.infinity;

        return Scaffold(
          appBar: AppBar(
            title: Text(_stepTitle(l10n, state.step)),
            actions: const [LanguageSelector()],
          ),
          body: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Column(
                children: [
                  WizardStepIndicator(
                    currentStep: state.step,
                    totalSteps: BookingWizardState.stepCount,
                  ),
                  Expanded(child: _buildStep(state, locale)),
                  _buildFooter(l10n, state),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStep(BookingWizardState state, String locale) {
    switch (state.step) {
      case 0:
        return StepServiceSelect(
          selected: state.serviceType,
          onSelected: _controller.selectService,
        );
      case 1:
        return StepOriginSelect(
          serviceType: state.serviceType,
          selected: state.origin,
          languageCode: locale,
          onSelected: _controller.setOrigin,
        );
      case 2:
        return StepDestinationSelect(
          serviceType: state.serviceType,
          selected: state.destination,
          languageCode: locale,
          onSelected: _controller.setDestination,
        );
      case 3:
        return StepPickupDateTime(state: state, controller: _controller);
      case 4:
        return StepPassengersLuggage(
          state: state,
          controller: _controller,
          onRetryRecommendation: _controller.loadRecommendation,
        );
      case 5:
        return StepVehicleSelect(state: state, controller: _controller);
      case 6:
        return StepConfirmation(state: state);
      case 7:
        return StepCustomerInfo(
          state: state,
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
          onFlightNumberChanged: (v) =>
              _controller.updateCustomerInfo(flightNumber: v),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFooter(AppLocalizations l10n, BookingWizardState state) {
    final isLast = state.step == BookingWizardState.stepCount - 1;
    final canProceed =
        _controller.canProceedFromCurrentStep() && !_controller.isLoading;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            if (state.step > 0)
              OutlinedButton(
                onPressed: _controller.isLoading ? null : _controller.goBack,
                child: Text(l10n.t('back')),
              ),
            const Spacer(),
            if (isLast)
              ElevatedButton(
                onPressed: canProceed ? _handleSubmit : null,
                child: _controller.isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.t('confirm')),
              )
            else
              ElevatedButton(
                onPressed: canProceed ? _handleNext : null,
                child: Text(l10n.t('next')),
              ),
          ],
        ),
      ),
    );
  }
}
