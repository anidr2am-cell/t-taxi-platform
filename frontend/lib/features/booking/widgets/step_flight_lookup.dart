import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/flight_lookup_models.dart';
import '../services/flight_lookup_api_service.dart';
import '../utils/flight_time_format.dart';
import 'wizard_compact.dart';

class StepFlightLookup extends StatefulWidget {
  const StepFlightLookup({
    super.key,
    required this.state,
    required this.controller,
    this.flightLookupApi,
    this.onFlightConfirmed,
  });

  final BookingWizardState state;
  final BookingWizardController controller;
  final FlightLookupApiService? flightLookupApi;
  final VoidCallback? onFlightConfirmed;

  @override
  State<StepFlightLookup> createState() => _StepFlightLookupState();
}

class _StepFlightLookupState extends State<StepFlightLookup> {
  late final TextEditingController _flightController;
  final GlobalKey _resultsAnchorKey = GlobalKey();
  bool _loading = false;
  int? _confirmedIndex;
  List<FlightSearchResult> _results = const [];
  String? _errorKey;

  FlightLookupApiService get _api =>
      widget.flightLookupApi ?? FlightLookupApiService();

  @override
  void initState() {
    super.initState();
    _flightController = TextEditingController(text: widget.state.flightNumber);
  }

  @override
  void didUpdateWidget(covariant StepFlightLookup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.flightNumber != widget.state.flightNumber &&
        _flightController.text != widget.state.flightNumber) {
      _flightController.text = widget.state.flightNumber;
    }
  }

  @override
  void dispose() {
    _flightController.dispose();
    super.dispose();
  }

  Future<void> _pickFlightDate() async {
    final today = widget.controller.thailandNow();
    final parsed = DateTime.tryParse(widget.state.flightDate);
    final date = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime(today.year, today.month, today.day),
      firstDate: DateTime(today.year, today.month, today.day),
      lastDate: DateTime(today.year + 2),
    );
    if (date == null) return;
    await widget.controller.updateCustomerInfo(
      flightDate: widget.controller.formatDate(date),
    );
    if (!mounted) return;
    setState(_clearResult);
    FocusScope.of(context).unfocus();
    if (_flightController.text.trim().isNotEmpty) {
      await _search(dateOverride: widget.controller.formatDate(date));
    }
  }

  void _clearResult() {
    _results = const [];
    _errorKey = null;
    _confirmedIndex = null;
  }

  Future<void> _search({String? dateOverride}) async {
    final number = _flightController.text.trim();
    final date = dateOverride ?? widget.state.flightDate;
    if (number.isEmpty || date.isEmpty || _loading) return;
    setState(() {
      _loading = true;
      _clearResult();
    });
    try {
      final results = await _api.searchFlights(number, date);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = results;
      });
      if (results.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final resultContext = _resultsAnchorKey.currentContext;
          if (resultContext == null) return;
          Scrollable.ensureVisible(
            resultContext,
            alignment: 0.2,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
          );
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorKey = 'flight_lookup_manual_fallback';
      });
    }
  }

  Future<void> _confirm(FlightSearchResult result, int index) async {
    final applied = await widget.controller.applyConfirmedFlight(
      flightNumber: result.flightNumber.isEmpty
          ? _flightController.text
          : result.flightNumber,
      flightDate: widget.state.flightDate,
      arrivalAirportCode: result.arrival.airportCode,
      arrivalTimestamp:
          result.arrival.estimatedAt ?? result.arrival.scheduledAt,
    );
    if (!mounted) return;
    setState(() {
      _confirmedIndex = applied ? index : null;
      _errorKey = applied ? null : 'flight_lookup_airport_unsupported';
    });
    if (applied) widget.onFlightConfirmed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canSearch =
        _flightController.text.trim().isNotEmpty &&
        widget.state.flightDate.isNotEmpty &&
        !_loading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppUi.sectionHeader(
          context,
          title: l10n.t('flight_lookup_route_title'),
          subtitle: l10n.t('flight_departure_date_help'),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('route_flight_number_field'),
                controller: _flightController,
                textCapitalization: TextCapitalization.characters,
                decoration: WizardCompact.inputDecoration(
                  label: l10n.t('flight_number'),
                  hint: l10n.t('flight_number_hint'),
                  prefixIcon: const Icon(Icons.flight_outlined, size: 20),
                ),
                onChanged: (value) {
                  widget.controller.updateCustomerInfo(flightNumber: value);
                  setState(_clearResult);
                },
              ),
            ),
            const SizedBox(width: AppTokens.spaceSm),
            Expanded(
              child: OutlinedButton.icon(
                key: const Key('route_flight_date_button'),
                onPressed: _pickFlightDate,
                icon: const Icon(Icons.calendar_today_outlined, size: 18),
                label: Text(
                  widget.state.flightDate.isEmpty
                      ? l10n.t('flight_departure_date')
                      : widget.state.flightDate,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppTokens.spaceSm),
        SizedBox(
          height: WizardCompact.minTouchHeight,
          child: FilledButton.tonal(
            key: const Key('route_flight_lookup_button'),
            onPressed: canSearch ? () => _search() : null,
            child: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.t('flight_lookup_search')),
          ),
        ),
        if (_errorKey != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.warningLight,
            child: Text(
              l10n.t(_errorKey!),
              style: const TextStyle(height: 1.45),
            ),
          ),
        ],
        if (_results.isNotEmpty) ...[
          const SizedBox(height: AppTokens.spaceSm),
          KeyedSubtree(
            key: _resultsAnchorKey,
            child: Column(
              children: [
                for (var index = 0; index < _results.length; index++) ...[
                  _resultCard(l10n, _results[index], index),
                  if (index != _results.length - 1)
                    const SizedBox(height: AppTokens.spaceSm),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: WizardCompact.sectionGap),
      ],
    );
  }

  Widget _resultCard(
    AppLocalizations l10n,
    FlightSearchResult result,
    int index,
  ) {
    final departureLocal = FlightTimeFormat.localWallClock(
      result.departure.estimatedLocal ??
          result.departure.scheduledLocal ??
          result.departure.estimatedAt ??
          result.departure.scheduledAt,
    );
    final arrival = result.arrival.estimatedAt ?? result.arrival.scheduledAt;
    final arrivalBangkok = FlightTimeFormat.bangkokWallClock(arrival);
    final departureCode =
        result.departure.airportCode ?? result.departure.airportName ?? '—';
    final arrivalCode =
        result.arrival.airportCode ?? result.arrival.airportName ?? '—';
    final departureDate = FlightTimeFormat.formatDate(departureLocal);
    final arrivalDate = FlightTimeFormat.formatDate(arrivalBangkok);
    final datesDiffer = departureDate != arrivalDate;
    return KeyedSubtree(
      key: Key('route_flight_result_$index'),
      child: AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if ((result.airlineName ?? '').isNotEmpty)
              Text(
                result.airlineName!,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              '$departureCode ${FlightTimeFormat.format24Hour(departureLocal)} '
              '→ $arrivalCode ${FlightTimeFormat.format24Hour(arrivalBangkok)}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              datesDiffer
                  ? '${l10n.t('flight_lookup_departure_date_short')}: $departureDate · '
                        '${l10n.t('flight_lookup_arrival_date_short')}: $arrivalDate'
                  : departureDate,
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            TextButton.icon(
              key: Key('route_flight_confirm_button_$index'),
              onPressed: () => _confirm(result, index),
              icon: Icon(
                _confirmedIndex == index
                    ? Icons.check_circle
                    : Icons.check_circle_outline,
                color: _confirmedIndex == index
                    ? AppTokens.success
                    : AppTokens.primary,
              ),
              label: Text(l10n.t('flight_lookup_confirm')),
            ),
            if (_confirmedIndex == index)
              Text(
                l10n.t('flight_lookup_applied_50_minutes'),
                style: const TextStyle(color: AppTokens.success),
              ),
          ],
        ),
      ),
    );
  }
}
