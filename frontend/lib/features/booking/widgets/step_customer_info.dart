import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../models/booking_wizard_state.dart';
import '../models/service_type_option.dart';

class StepCustomerInfo extends StatefulWidget {
  final BookingWizardState state;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onEmailChanged;
  final ValueChanged<String> onPhoneChanged;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String> onMessengerTypeChanged;
  final ValueChanged<String> onMessengerIdChanged;
  final ValueChanged<String> onAdditionalRequestsChanged;
  final ValueChanged<String>? onFlightNumberChanged;

  const StepCustomerInfo({
    super.key,
    required this.state,
    required this.onNameChanged,
    required this.onEmailChanged,
    required this.onPhoneChanged,
    required this.onCountryChanged,
    required this.onMessengerTypeChanged,
    required this.onMessengerIdChanged,
    required this.onAdditionalRequestsChanged,
    this.onFlightNumberChanged,
  });

  @override
  State<StepCustomerInfo> createState() => _StepCustomerInfoState();
}

class _StepCustomerInfoState extends State<StepCustomerInfo> {
  late final TextEditingController _nameController;
  late final TextEditingController _emailController;
  late final TextEditingController _phoneController;
  late final TextEditingController _countryController;
  late final TextEditingController _messengerTypeController;
  late final TextEditingController _messengerIdController;
  late final TextEditingController _requestsController;
  late final TextEditingController _flightController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.state.customerName);
    _emailController = TextEditingController(text: widget.state.customerEmail);
    _phoneController = TextEditingController(text: widget.state.customerPhone);
    _countryController = TextEditingController(text: widget.state.customerCountryCode);
    _messengerTypeController = TextEditingController(text: widget.state.messengerType);
    _messengerIdController = TextEditingController(text: widget.state.messengerId);
    _requestsController = TextEditingController(text: widget.state.additionalRequests);
    _flightController = TextEditingController(text: widget.state.flightNumber);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _countryController.dispose();
    _messengerTypeController.dispose();
    _messengerIdController.dispose();
    _requestsController.dispose();
    _flightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return SingleChildScrollView(
      padding: AppUi.pagePadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppUi.sectionHeader(context, title: l10n.t('customer_info')),
          const SizedBox(height: 8),
          if (widget.state.serviceType == BookingServiceType.airportPickup &&
              widget.onFlightNumberChanged != null) ...[
            TextField(
              controller: _flightController,
              decoration: InputDecoration(
                labelText: l10n.t('flight_number'),
                hintText: 'TG401',
                border: const OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.characters,
              onChanged: widget.onFlightNumberChanged,
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _nameController,
            decoration: InputDecoration(
              labelText: l10n.t('name'),
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onNameChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _emailController,
            decoration: InputDecoration(
              labelText: l10n.t('email'),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            onChanged: widget.onEmailChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            decoration: InputDecoration(
              labelText: l10n.t('phone'),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
            onChanged: widget.onPhoneChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _countryController,
            decoration: InputDecoration(
              labelText: l10n.t('country'),
              border: const OutlineInputBorder(),
              hintText: l10n.t('country_code_hint'),
            ),
            onChanged: widget.onCountryChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messengerTypeController,
            decoration: InputDecoration(
              labelText: l10n.t('messenger_type'),
              border: const OutlineInputBorder(),
              hintText: l10n.t('messenger_type_hint'),
            ),
            onChanged: widget.onMessengerTypeChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messengerIdController,
            decoration: InputDecoration(
              labelText: l10n.t('messenger_id'),
              border: const OutlineInputBorder(),
            ),
            onChanged: widget.onMessengerIdChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _requestsController,
            decoration: InputDecoration(
              labelText: l10n.t('additional_requests'),
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
            onChanged: widget.onAdditionalRequestsChanged,
          ),
        ],
      ),
    );
  }
}
