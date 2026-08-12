import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../controllers/booking_wizard_controller.dart';
import '../models/booking_wizard_state.dart';
import '../models/flight_lookup_models.dart';
import '../models/service_type_option.dart';
import '../services/flight_lookup_api_service.dart';
import '../utils/flight_time_format.dart';
import '../utils/pickup_time_format.dart';
import 'pickup_time_picker_sheet.dart';
import 'wizard_compact.dart';
import 'wizard_ui.dart';

enum _PickupTimeSource { manual, flight }

const _pickupFlightConflictThresholdMinutes = 30;

class StepPickupDateTime extends StatefulWidget {
  const StepPickupDateTime({
    super.key,
    required this.state,
    required this.controller,
    this.onFlightNumberChanged,
    this.flightLookupApi,
    this.embedded = false,
    this.focusNode,
  });

  final BookingWizardState state;
  final BookingWizardController controller;
  final ValueChanged<String>? onFlightNumberChanged;
  final FlightLookupApiService? flightLookupApi;
  final bool embedded;
  final FocusNode? focusNode;

  @override
  State<StepPickupDateTime> createState() => _StepPickupDateTimeState();
}

class _StepPickupDateTimeState extends State<StepPickupDateTime> {
  late final TextEditingController _flightController;
  late final TextEditingController _manualTimeController;
  String? _manualTimeErrorKey;
  bool _isLookingUp = false;
  FlightSearchResult? _lookupResult;
  String? _lookupErrorCode;
  bool _lookupConfirmed = false;
  int? _pickupTimeConflictMinutes;
  DateTime? _flightArrivalBangkok;
  DateTime? _manualPickupAtConfirm;
  _PickupTimeSource? _selectedPickupSource;
  bool _applyingFlightPickupTime = false;

  FlightLookupApiService get _flightLookupApi =>
      widget.flightLookupApi ?? FlightLookupApiService();

  @override
  void initState() {
    super.initState();
    _flightController = TextEditingController(text: widget.state.flightNumber);
    _manualTimeController = TextEditingController();
    _flightController.addListener(_onFlightControllerChanged);
  }

  void _onFlightControllerChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncManualTimeField();
  }

  @override
  void didUpdateWidget(covariant StepPickupDateTime oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.flightNumber != widget.state.flightNumber &&
        _flightController.text != widget.state.flightNumber) {
      _flightController.text = widget.state.flightNumber;
    }
    if (oldWidget.state.pickupTime != widget.state.pickupTime ||
        oldWidget.state.pickupDate != widget.state.pickupDate) {
      _syncManualTimeField();
      if (oldWidget.state.pickupDate != widget.state.pickupDate) {
        _clearLookup();
      } else if (!_applyingFlightPickupTime) {
        _onPickupDateTimeChangedExternally();
      }
    }
  }

  DateTime? _bangkokWallClockFromIsoUtc(String? isoUtc) {
    if (isoUtc == null || isoUtc.isEmpty) return null;
    final utc = DateTime.parse(isoUtc).toUtc();
    final bangkok = utc.add(const Duration(hours: 7));
    return DateTime(
      bangkok.year,
      bangkok.month,
      bangkok.day,
      bangkok.hour,
      bangkok.minute,
    );
  }

  int? _absoluteMinuteDifference(DateTime? left, DateTime? right) {
    if (left == null || right == null) return null;
    return left.difference(right).inMinutes.abs();
  }

  void _resetPickupTimeConflict() {
    _pickupTimeConflictMinutes = null;
    _flightArrivalBangkok = null;
    _manualPickupAtConfirm = null;
    _selectedPickupSource = null;
  }

  void _evaluatePickupTimeConflict({required bool clearSelection}) {
    final result = _lookupResult;
    if (!_lookupConfirmed || result == null) {
      _resetPickupTimeConflict();
      return;
    }

    final flightArrival = _bangkokWallClockFromIsoUtc(result.arrival.scheduledAt);
    final manualPickup = widget.controller.selectedPickupDateTime();
    if (flightArrival == null || manualPickup == null) {
      _resetPickupTimeConflict();
      return;
    }

    final diff = _absoluteMinuteDifference(manualPickup, flightArrival);
    if (diff == null || diff < _pickupFlightConflictThresholdMinutes) {
      _resetPickupTimeConflict();
      return;
    }

    _flightArrivalBangkok = flightArrival;
    _manualPickupAtConfirm = manualPickup;
    _pickupTimeConflictMinutes = diff;
    if (clearSelection) {
      _selectedPickupSource = null;
    }
  }

  void _onPickupDateTimeChangedExternally() {
    if (_lookupConfirmed && _lookupResult != null) {
      setState(() {
        _evaluatePickupTimeConflict(clearSelection: true);
      });
      return;
    }
    if (_pickupTimeConflictMinutes != null || _selectedPickupSource != null) {
      setState(_resetPickupTimeConflict);
    }
  }

  void _clearLookup() {
    if (_lookupResult == null &&
        _lookupErrorCode == null &&
        !_isLookingUp &&
        !_lookupConfirmed &&
        _pickupTimeConflictMinutes == null) {
      return;
    }
    setState(() {
      _lookupResult = null;
      _lookupErrorCode = null;
      _lookupConfirmed = false;
      _isLookingUp = false;
      _resetPickupTimeConflict();
    });
  }

  void _confirmFlightLookup() {
    setState(() {
      _lookupConfirmed = true;
      _evaluatePickupTimeConflict(clearSelection: true);
    });
  }

  String _formatPickupSummary(AppLocalizations l10n, DateTime value) {
    final amLabel = l10n.t('pickup_time_am');
    final pmLabel = l10n.t('pickup_time_pm');
    final date = widget.controller.formatDate(value);
    final time = PickupTimeFormat.formatDisplay(
      hour24: value.hour,
      minute: value.minute,
      amLabel: amLabel,
      pmLabel: pmLabel,
    );
    return '$date $time';
  }

  Future<void> _selectManualPickupTime() async {
    final manualPickup = _manualPickupAtConfirm;
    setState(() => _selectedPickupSource = _PickupTimeSource.manual);
    if (manualPickup == null) return;

    final current = widget.controller.selectedPickupDateTime();
    if (current != null &&
        current.year == manualPickup.year &&
        current.month == manualPickup.month &&
        current.day == manualPickup.day &&
        current.hour == manualPickup.hour &&
        current.minute == manualPickup.minute) {
      return;
    }

    await widget.controller.setPickupDateTime(manualPickup);
  }

  Future<void> _selectFlightPickupTime() async {
    final flightArrival = _flightArrivalBangkok;
    if (flightArrival == null) return;

    setState(() => _selectedPickupSource = _PickupTimeSource.flight);
    _applyingFlightPickupTime = true;
    await widget.controller.setPickupDateTime(flightArrival);
    if (!mounted) return;
    setState(() {
      _applyingFlightPickupTime = false;
      _evaluatePickupTimeConflict(clearSelection: false);
    });
  }

  void _onFlightNumberChanged(String value) {
    _clearLookup();
    widget.onFlightNumberChanged?.call(value);
  }

  Future<void> _searchFlight() async {
    final flightNumber = _flightController.text.trim();
    final flightDate = widget.state.pickupDate;
    if (flightNumber.isEmpty || flightDate == null || _isLookingUp) return;

    setState(() {
      _isLookingUp = true;
      _lookupResult = null;
      _lookupErrorCode = null;
      _lookupConfirmed = false;
      _resetPickupTimeConflict();
    });

    try {
      final result = await _flightLookupApi.searchFlight(
        flightNumber,
        flightDate,
      );
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _lookupResult = result;
      });
    } on FlightLookupException catch (err) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _lookupErrorCode = err.errorCode;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLookingUp = false;
        _lookupErrorCode = 'FLIGHT_PROVIDER_ERROR';
      });
    }
  }

  String? _lookupErrorMessage(AppLocalizations l10n) {
    final code = _lookupErrorCode;
    if (code == null) return null;
    switch (code) {
      case 'FLIGHT_NOT_FOUND':
        return l10n.t('flight_lookup_not_found');
      case 'INVALID_FLIGHT_NUMBER':
        return l10n.t('flight_number_invalid');
      case 'INVALID_FLIGHT_DATE':
        return l10n.t('flight_lookup_invalid_date');
      case 'FLIGHT_PROVIDER_NOT_CONFIGURED':
      case 'FLIGHT_PROVIDER_TIMEOUT':
      case 'FLIGHT_PROVIDER_RATE_LIMITED':
      case 'FLIGHT_PROVIDER_ERROR':
        return l10n.t('flight_lookup_provider_unavailable');
      default:
        return l10n.t('flight_lookup_provider_unavailable');
    }
  }

  Widget _buildFlightLookupSection(AppLocalizations l10n) {
    final canSearch =
        _flightController.text.trim().isNotEmpty &&
        widget.state.pickupDate != null &&
        !_isLookingUp;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                key: const Key('flight_number_field'),
                controller: _flightController,
                focusNode: widget.focusNode,
                scrollPadding: WizardCompact.fieldScrollPadding,
                decoration: WizardCompact.inputDecoration(
                  label: l10n.t('flight_number'),
                  hint: l10n.t('flight_number_hint'),
                  prefixIcon: const Icon(Icons.flight_outlined, size: 20),
                ).copyWith(
                  errorText: widget.state.errorMessage == 'flight_number_invalid'
                      ? l10n.t('flight_number_invalid')
                      : null,
                ),
                textCapitalization: TextCapitalization.characters,
                onChanged: _onFlightNumberChanged,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: WizardCompact.minTouchHeight,
              child: FilledButton.tonal(
                key: const Key('flight_lookup_search_button'),
                onPressed: canSearch ? _searchFlight : null,
                child: _isLookingUp
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onSecondaryContainer,
                        ),
                      )
                    : Text(l10n.t('flight_lookup_search')),
              ),
            ),
          ],
        ),
        if (_lookupErrorCode != null) ...[
          const SizedBox(height: WizardCompact.fieldGap),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.warningLight,
            padding: widget.embedded
                ? const EdgeInsets.all(WizardCompact.cardPadding)
                : const EdgeInsets.all(AppTokens.spaceMd),
            child: Text(
              _lookupErrorMessage(l10n) ?? '',
              style: const TextStyle(height: 1.45),
            ),
          ),
        ],
        if (_lookupResult != null) ...[
          const SizedBox(height: WizardCompact.fieldGap),
          _buildLookupResultCard(l10n, _lookupResult!),
        ],
      ],
    );
  }

  Widget _buildLookupResultCard(
    AppLocalizations l10n,
    FlightSearchResult result,
  ) {
    final amLabel = l10n.t('pickup_time_am');
    final pmLabel = l10n.t('pickup_time_pm');

    return AppUi.surfaceCard(
      padding: widget.embedded
          ? const EdgeInsets.all(WizardCompact.cardPadding)
          : const EdgeInsets.all(AppTokens.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if ((result.airlineName ?? '').isNotEmpty)
            Text(
              result.airlineName!,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          if ((result.airlineName ?? '').isNotEmpty)
            const SizedBox(height: 6),
          Text(
            result.routeLabel(),
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 8),
          Text(
            '${l10n.t('flight_lookup_departure')}: '
            '${FlightTimeFormat.formatBangkokDisplay(result.departure.scheduledAt, amLabel: amLabel, pmLabel: pmLabel)}',
            style: TextStyle(color: AppTokens.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            '${l10n.t('flight_lookup_arrival')}: '
            '${FlightTimeFormat.formatBangkokDisplay(result.arrival.scheduledAt, amLabel: amLabel, pmLabel: pmLabel)}',
            style: TextStyle(color: AppTokens.textSecondary, height: 1.4),
          ),
          if (result.arrival.estimatedAt != null &&
              result.arrival.estimatedAt != result.arrival.scheduledAt) ...[
            const SizedBox(height: 4),
            Text(
              '${l10n.t('flight_lookup_estimated_arrival')}: '
              '${FlightTimeFormat.formatBangkokDisplay(result.arrival.estimatedAt, amLabel: amLabel, pmLabel: pmLabel)}',
              style: TextStyle(color: AppTokens.textSecondary, height: 1.4),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const Key('flight_lookup_confirm_button'),
              onPressed: _confirmFlightLookup,
              icon: Icon(
                _lookupConfirmed ? Icons.check_circle : Icons.check_circle_outline,
                size: 18,
                color: _lookupConfirmed ? AppTokens.success : AppTokens.primary,
              ),
              label: Text(l10n.t('flight_lookup_confirm')),
            ),
          ),
          if (_lookupConfirmed && _pickupTimeConflictMinutes != null) ...[
            const SizedBox(height: WizardCompact.fieldGap),
            _buildPickupTimeConflictSection(l10n),
          ],
        ],
      ),
    );
  }

  Widget _buildPickupTimeConflictSection(AppLocalizations l10n) {
    final minutes = _pickupTimeConflictMinutes!;
    final manualPickup = _manualPickupAtConfirm;
    final flightArrival = _flightArrivalBangkok;
    if (manualPickup == null || flightArrival == null) {
      return const SizedBox.shrink();
    }

    final copy = _FlightPickupConflictCopy(l10n.languageCode);
    final manualSubtitle = _formatPickupSummary(l10n, manualPickup);
    final flightSubtitle = _formatPickupSummary(l10n, flightArrival);
    final selectedPickup = widget.controller.selectedPickupDateTime();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: const Key('flight_pickup_conflict_warning'),
          copy.warning(minutes),
          style: const TextStyle(
            color: AppTokens.error,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: WizardCompact.fieldGap),
        Material(
          key: const Key('flight_pickup_use_manual_tile'),
          color: Colors.transparent,
          child: WizardUi.selectionTile(
            title: copy.useManualTime,
            subtitle: manualSubtitle,
            icon: Icons.edit_calendar_outlined,
            selected: _selectedPickupSource == _PickupTimeSource.manual,
            onTap: _selectManualPickupTime,
          ),
        ),
        const SizedBox(height: WizardCompact.fieldGap),
        Material(
          key: const Key('flight_pickup_use_flight_tile'),
          color: Colors.transparent,
          child: WizardUi.selectionTile(
            title: copy.useFlightTime,
            subtitle: flightSubtitle,
            icon: Icons.flight_land_outlined,
            selected: _selectedPickupSource == _PickupTimeSource.flight,
            onTap: _selectFlightPickupTime,
          ),
        ),
        if (_selectedPickupSource != null && selectedPickup != null) ...[
          const SizedBox(height: WizardCompact.fieldGap),
          Text(
            key: const Key('flight_pickup_final_summary'),
            '${copy.finalPickupLabel}: ${_formatPickupSummary(l10n, selectedPickup)}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }

  void _syncManualTimeField() {
    final selected = widget.controller.selectedPickupDateTime();
    if (selected == null) return;
    final l10n = context.l10n;
    final display = PickupTimeFormat.formatDisplay(
      hour24: selected.hour,
      minute: selected.minute,
      amLabel: l10n.t('pickup_time_am'),
      pmLabel: l10n.t('pickup_time_pm'),
    );
    if (_manualTimeController.text != display) {
      _manualTimeController.text = display;
    }
  }

  @override
  void dispose() {
    _flightController.removeListener(_onFlightControllerChanged);
    _flightController.dispose();
    _manualTimeController.dispose();
    super.dispose();
  }

  bool get _showFlightField =>
      widget.state.serviceType == BookingServiceType.airportPickup &&
      widget.onFlightNumberChanged != null;

  String _timeDisplayValue(AppLocalizations l10n, DateTime selected) {
    if (widget.state.pickupTime != null) {
      final parts = widget.state.pickupTime!.split(':');
      if (parts.length == 2) {
        final hour = int.tryParse(parts[0]);
        final minute = int.tryParse(parts[1]);
        if (hour != null && minute != null) {
          return PickupTimeFormat.formatDisplay(
            hour24: hour,
            minute: minute,
            amLabel: l10n.t('pickup_time_am'),
            pmLabel: l10n.t('pickup_time_pm'),
          );
        }
      }
    }
    return PickupTimeFormat.formatDisplay(
      hour24: selected.hour,
      minute: selected.minute,
      amLabel: l10n.t('pickup_time_am'),
      pmLabel: l10n.t('pickup_time_pm'),
    );
  }

  Future<void> _pickTime(BuildContext context, DateTime selected) async {
    final result = await PickupTimePickerSheet.show(
      context,
      initialHour24: selected.hour,
      initialMinute: selected.minute,
    );
    if (result == null) return;
    await widget.controller.setPickupDateTime(
      DateTime(
        selected.year,
        selected.month,
        selected.day,
        result.hour24,
        result.minute,
      ),
    );
  }

  Future<void> _applyManualTime(DateTime selected) async {
    final l10n = context.l10n;
    final parsed = PickupTimeFormat.parseManualInput(
      _manualTimeController.text,
      amLabel: l10n.t('pickup_time_am'),
      pmLabel: l10n.t('pickup_time_pm'),
    );
    if (parsed == null) {
      setState(() => _manualTimeErrorKey = 'pickup_time_invalid');
      return;
    }
    setState(() => _manualTimeErrorKey = null);
    await widget.controller.setPickupDateTime(
      DateTime(
        selected.year,
        selected.month,
        selected.day,
        parsed.hour24,
        parsed.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected =
        widget.controller.selectedPickupDateTime() ??
        widget.controller.defaultPickupDateTime();
    final min = widget.controller.earliestSelectablePickupDateTime();
    final showUrgentHint = widget.controller.isUrgentPickupWindowSelected();

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.embedded)
          AppUi.sectionHeader(
            context,
            title: l10n.t('pickup_datetime'),
            subtitle: l10n.t('pickup_minimum_notice'),
          ),
        if (widget.embedded)
          Text(
            l10n.t('pickup_minimum_notice'),
            style: WizardCompact.hintTextStyle,
          ),
        if (showUrgentHint) ...[
          if (widget.embedded) const SizedBox(height: WizardCompact.fieldGap),
          AppUi.surfaceCard(
            backgroundColor: AppTokens.warningLight,
            padding: widget.embedded
                ? const EdgeInsets.all(WizardCompact.cardPadding)
                : const EdgeInsets.all(AppTokens.spaceMd),
            child: Text(
              l10n.t('customer_urgent_pickup_hint'),
              style: const TextStyle(height: 1.45),
            ),
          ),
        ],
        if (widget.embedded) const SizedBox(height: WizardCompact.fieldGap),
        LayoutBuilder(
          builder: (context, constraints) {
            final dateTimeCard = AppUi.surfaceCard(
              padding: widget.embedded
                  ? const EdgeInsets.symmetric(
                      horizontal: WizardCompact.cardPadding,
                      vertical: 2,
                    )
                  : const EdgeInsets.all(AppTokens.spaceMd),
              child: Column(
                children: [
                  _PickerRow(
                    compact: widget.embedded,
                    icon: Icons.calendar_today_outlined,
                    title: l10n.t('pickup_date'),
                    value:
                        widget.state.pickupDate ??
                        widget.controller.formatDate(selected),
                    onTap: () => _pickDate(context, selected, min),
                  ),
                  const Divider(height: 1),
                  _PickerRow(
                    compact: widget.embedded,
                    icon: Icons.schedule_outlined,
                    title: l10n.t('pickup_time'),
                    value: _timeDisplayValue(l10n, selected),
                    onTap: () => _pickTime(context, selected),
                  ),
                ],
              ),
            );

            final manualTimeField = TextField(
              controller: _manualTimeController,
              decoration:
                  WizardCompact.inputDecoration(
                    label: l10n.t('pickup_time_enter_manually'),
                    hint: PickupTimeFormat.formatDisplay(
                      hour24: 9,
                      minute: 30,
                      amLabel: l10n.t('pickup_time_am'),
                      pmLabel: l10n.t('pickup_time_pm'),
                    ),
                  ).copyWith(
                    errorText: _manualTimeErrorKey != null
                        ? l10n.t(_manualTimeErrorKey!)
                        : null,
                  ),
              onSubmitted: (_) => _applyManualTime(selected),
              onChanged: (_) {
                if (_manualTimeErrorKey != null) {
                  setState(() => _manualTimeErrorKey = null);
                }
              },
            );

            if (!_showFlightField) {
              return Focus(
                focusNode: widget.focusNode,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    dateTimeCard,
                    const SizedBox(height: WizardCompact.fieldGap),
                    manualTimeField,
                  ],
                ),
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                dateTimeCard,
                const SizedBox(height: WizardCompact.fieldGap),
                manualTimeField,
                const SizedBox(height: WizardCompact.fieldGap),
                _buildFlightLookupSection(l10n),
              ],
            );
          },
        ),
        if (!widget.embedded && widget.state.errorMessage != null) ...[
          const SizedBox(height: AppTokens.spaceMd),
          AppUi.errorState(message: l10n.t(widget.state.errorMessage!)),
        ],
      ],
    );

    if (widget.embedded) return content;

    return ListView(padding: AppUi.pagePadding(context), children: [content]);
  }

  Future<void> _pickDate(
    BuildContext context,
    DateTime selected,
    DateTime min,
  ) async {
    final date = await showDatePicker(
      context: context,
      initialDate:
          DateTime(
            selected.year,
            selected.month,
            selected.day,
          ).isBefore(DateTime(min.year, min.month, min.day))
          ? DateTime(min.year, min.month, min.day)
          : DateTime(selected.year, selected.month, selected.day),
      firstDate: DateTime(min.year, min.month, min.day),
      lastDate: DateTime(min.year + 2),
    );
    if (date == null) return;
    await widget.controller.setPickupDateTime(
      DateTime(date.year, date.month, date.day, selected.hour, selected.minute),
    );
  }
}

class _FlightPickupConflictCopy {
  _FlightPickupConflictCopy(this.languageCode);

  final String languageCode;

  String warning(int minutes) {
    switch (languageCode) {
      case 'ko':
        return '입력하신 픽업 시간과 항공편 도착 예정 시간이 $minutes분 차이납니다.';
      case 'zh':
        return '您输入的接送时间与航班预计到达时间相差 $minutes 分钟。';
      case 'ja':
        return '入力したピックアップ時間とフライト到着予定時間が $minutes 分異なります。';
      case 'th':
        return 'เวลารับที่คุณกรอกกับเวลาถึงตามกำหนดของเที่ยวบินต่างกัน $minutes นาที';
      default:
        return 'Your pickup time and the flight scheduled arrival differ by $minutes minutes.';
    }
  }

  String get useManualTime {
    switch (languageCode) {
      case 'ko':
        return '직접 입력한 시간 사용';
      case 'zh':
        return '使用我输入的时间';
      case 'ja':
        return '入力した時間を使用';
      case 'th':
        return 'ใช้เวลาที่กรอกเอง';
      default:
        return 'Keep my entered time';
    }
  }

  String get useFlightTime {
    switch (languageCode) {
      case 'ko':
        return '항공편 시간 기준으로 변경';
      case 'zh':
        return '按航班到达时间更改';
      case 'ja':
        return 'フライト到着時間に変更';
      case 'th':
        return 'เปลี่ยนตามเวลาเที่ยวบิน';
      default:
        return 'Use flight arrival time';
    }
  }

  String get finalPickupLabel {
    switch (languageCode) {
      case 'ko':
        return '최종 픽업 요청시간';
      case 'zh':
        return '最终接送请求时间';
      case 'ja':
        return '最終ピックアップ希望時間';
      case 'th':
        return 'เวลารับสุดท้ายที่ขอ';
      default:
        return 'Final pickup request time';
    }
  }
}

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final verticalPadding = compact ? 10.0 : 14.0;
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppTokens.borderRadiusMd,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: WizardCompact.minTouchHeight,
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              vertical: verticalPadding,
              horizontal: 4,
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.all(compact ? 8 : 10),
                  decoration: BoxDecoration(
                    color: AppTokens.primary.withValues(alpha: 0.1),
                    borderRadius: AppTokens.borderRadiusSm,
                  ),
                  child: Icon(
                    icon,
                    color: AppTokens.primary,
                    size: compact ? 20 : 22,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppTokens.textSecondary,
                          fontSize: compact ? 12 : 13,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        value,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: compact ? 15 : 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: AppTokens.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
