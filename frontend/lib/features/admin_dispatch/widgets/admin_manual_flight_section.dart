import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../../booking/models/flight_lookup_models.dart';
import '../../booking/services/flight_lookup_api_service.dart';
import '../../booking/utils/flight_pickup_time_conflict.dart';
import '../../booking/utils/flight_time_format.dart';
import '../../booking/utils/pickup_time_format.dart';

enum _PickupTimeSource { manual, flight }

/// Flight lookup + pickup vs arrival conflict resolution (admin manual calls).
class AdminManualFlightSection extends StatefulWidget {
  const AdminManualFlightSection({
    super.key,
    required this.flightNumber,
    required this.pickupDateIsoOrBangkokDate,
    required this.pickupAtBangkok,
    required this.onFlightNumberChanged,
    this.onConfirmedLookup,
    this.onPickupAtApply,
    this.flightLookupApi,
    this.enabled = true,
  });

  final String flightNumber;
  final String? pickupDateIsoOrBangkokDate;
  final DateTime? pickupAtBangkok;
  final ValueChanged<String> onFlightNumberChanged;
  final ValueChanged<FlightSearchResult?>? onConfirmedLookup;
  final ValueChanged<DateTime>? onPickupAtApply;
  final FlightLookupApiService? flightLookupApi;
  final bool enabled;

  @override
  State<AdminManualFlightSection> createState() =>
      _AdminManualFlightSectionState();
}

class _AdminManualFlightSectionState extends State<AdminManualFlightSection> {
  late final TextEditingController _controller;
  bool _lookingUp = false;
  FlightSearchResult? _lookupResult;
  String? _lookupErrorCode;
  bool _lookupConfirmed = false;
  int _searchGeneration = 0;

  int? _pickupTimeConflictMinutes;
  DateTime? _flightArrivalBangkok;
  DateTime? _manualPickupAtConfirm;
  _PickupTimeSource? _selectedPickupSource;

  FlightLookupApiService get _flightLookupApi =>
      widget.flightLookupApi ?? FlightLookupApiService();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.flightNumber);
  }

  @override
  void didUpdateWidget(covariant AdminManualFlightSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.flightNumber != widget.flightNumber &&
        _controller.text != widget.flightNumber) {
      _controller.text = widget.flightNumber;
      _clearLookupState();
    }
    if (oldWidget.pickupDateIsoOrBangkokDate !=
            widget.pickupDateIsoOrBangkokDate ||
        oldWidget.pickupAtBangkok != widget.pickupAtBangkok) {
      if (_lookupConfirmed) {
        setState(() {
          _evaluatePickupTimeConflict(clearSelection: true);
        });
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? get _pickupDateYmd {
    final raw = widget.pickupDateIsoOrBangkokDate?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.length >= 10 && raw[4] == '-' && raw[7] == '-') {
      return raw.substring(0, 10);
    }
    return null;
  }

  void _clearLookupState() {
    _searchGeneration++;
    setState(() {
      _lookupResult = null;
      _lookupErrorCode = null;
      _lookupConfirmed = false;
      _lookingUp = false;
      _resetPickupTimeConflict();
    });
    widget.onConfirmedLookup?.call(null);
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

    final flightArrival = bangkokWallClockFromFlightIso(
      result.arrival.scheduledAt,
    );
    final manualPickup = widget.pickupAtBangkok;
    if (flightArrival == null || manualPickup == null) {
      _resetPickupTimeConflict();
      return;
    }

    final diff = absoluteMinuteDifference(manualPickup, flightArrival);
    if (diff == null || diff < flightPickupConflictThresholdMinutes) {
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

  void _confirmFlightLookup() {
    setState(() {
      _lookupConfirmed = true;
      _evaluatePickupTimeConflict(clearSelection: true);
    });
    widget.onConfirmedLookup?.call(_lookupResult);
  }

  Future<void> _searchFlight() async {
    final flightNumber = _controller.text.trim();
    final flightDate = _pickupDateYmd;
    if (flightNumber.isEmpty || flightDate == null || _lookingUp) return;

    final generation = ++_searchGeneration;
    setState(() {
      _lookingUp = true;
      _lookupResult = null;
      _lookupErrorCode = null;
      _lookupConfirmed = false;
      _resetPickupTimeConflict();
    });
    widget.onConfirmedLookup?.call(null);

    try {
      final result = await _flightLookupApi.searchFlight(
        flightNumber,
        flightDate,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _lookingUp = false;
        _lookupResult = result;
      });
    } on FlightLookupException catch (err) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _lookingUp = false;
        _lookupErrorCode = err.errorCode;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _lookingUp = false;
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
      default:
        return l10n.t('flight_lookup_provider_unavailable');
    }
  }

  String _formatPickupSummary(AppLocalizations l10n, DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${value.year}-${two(value.month)}-${two(value.day)}';
    final time = PickupTimeFormat.formatDisplay(
      hour24: value.hour,
      minute: value.minute,
      amLabel: l10n.t('pickup_time_am'),
      pmLabel: l10n.t('pickup_time_pm'),
    );
    return '$date · $time';
  }

  void _selectManualPickupTime() {
    setState(() => _selectedPickupSource = _PickupTimeSource.manual);
  }

  void _selectFlightPickupTime() {
    final flightArrival = _flightArrivalBangkok;
    if (flightArrival == null) return;
    setState(() => _selectedPickupSource = _PickupTimeSource.flight);
    widget.onPickupAtApply?.call(flightArrival);
    setState(() {
      _evaluatePickupTimeConflict(clearSelection: false);
    });
  }

  Widget _buildConflictSection(AppLocalizations l10n) {
    final minutes = _pickupTimeConflictMinutes!;
    final manualPickup = _manualPickupAtConfirm;
    final flightArrival = _flightArrivalBangkok;
    if (manualPickup == null || flightArrival == null) {
      return const SizedBox.shrink();
    }

    final warning = l10n
        .t('admin_manual_booking_flight_pickup_conflict_warning')
        .replaceAll('{minutes}', '$minutes');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          key: const Key('adminFlightPickupConflictWarning'),
          warning,
          style: const TextStyle(
            color: AppTokens.error,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _ConflictTile(
          key: const Key('adminFlightPickupUseManual'),
          title: l10n.t('admin_manual_booking_flight_pickup_keep_manual'),
          subtitle: _formatPickupSummary(l10n, manualPickup),
          icon: Icons.edit_calendar_outlined,
          selected: _selectedPickupSource == _PickupTimeSource.manual,
          onTap: _selectManualPickupTime,
        ),
        const SizedBox(height: AppTokens.spaceSm),
        _ConflictTile(
          key: const Key('adminFlightPickupUseFlight'),
          title: l10n.t('admin_manual_booking_flight_pickup_use_flight'),
          subtitle: _formatPickupSummary(l10n, flightArrival),
          icon: Icons.flight_land_outlined,
          selected: _selectedPickupSource == _PickupTimeSource.flight,
          onTap: _selectFlightPickupTime,
        ),
        if (_selectedPickupSource != null && widget.pickupAtBangkok != null) ...[
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            key: const Key('adminFlightPickupFinalSummary'),
            '${l10n.t('admin_manual_booking_flight_pickup_final_label')}: '
            '${_formatPickupSummary(l10n, widget.pickupAtBangkok!)}',
            style: const TextStyle(fontWeight: FontWeight.w700, height: 1.45),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canSearch = _controller.text.trim().isNotEmpty &&
        _pickupDateYmd != null &&
        !_lookingUp &&
        widget.enabled;

    return AppUi.surfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.t('flight_number'),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          TextField(
            key: const Key('adminManualFlightNumber'),
            controller: _controller,
            enabled: widget.enabled,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              hintText: l10n.t('flight_number_hint'),
              prefixIcon: const Icon(Icons.flight_outlined),
              suffixIcon: IconButton(
                key: const Key('adminFlightSearchButton'),
                onPressed: canSearch ? _searchFlight : null,
                icon: _lookingUp
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
              ),
            ),
            onChanged: (value) {
              widget.onFlightNumberChanged(value);
              if (_lookupResult != null ||
                  _lookupErrorCode != null ||
                  _lookupConfirmed ||
                  _lookingUp) {
                _clearLookupState();
              }
            },
          ),
          if (_pickupDateYmd == null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSm),
              child: Text(
                l10n.t('admin_manual_booking_flight_pickup_date_required'),
                style: const TextStyle(color: AppTokens.textSecondary),
              ),
            ),
          if (_lookupErrorMessage(l10n) != null)
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceSm),
              child: Text(
                key: const Key('adminFlightLookupError'),
                _lookupErrorMessage(l10n)!,
                style: const TextStyle(color: AppTokens.warning),
              ),
            ),
          if (_lookupResult != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            Text(
              FlightTimeFormat.formatBangkokDisplay(
                _lookupResult!.arrival.scheduledAt,
                amLabel: l10n.t('pickup_time_am'),
                pmLabel: l10n.t('pickup_time_pm'),
              ),
              style: const TextStyle(color: AppTokens.textSecondary),
            ),
            const SizedBox(height: AppTokens.spaceSm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('adminFlightLookupConfirm'),
                onPressed: widget.enabled && !_lookupConfirmed
                    ? _confirmFlightLookup
                    : null,
                icon: Icon(
                  _lookupConfirmed ? Icons.check_circle : Icons.check_circle_outline,
                  size: 18,
                  color: _lookupConfirmed ? AppTokens.success : AppTokens.primary,
                ),
                label: Text(l10n.t('flight_lookup_confirm')),
              ),
            ),
          ],
          if (_lookupConfirmed && _pickupTimeConflictMinutes != null) ...[
            const SizedBox(height: AppTokens.spaceSm),
            _buildConflictSection(l10n),
          ],
          Padding(
            padding: const EdgeInsets.only(top: AppTokens.spaceSm),
            child: Text(
              l10n.t('admin_manual_booking_flight_manual_fallback_hint'),
              style: const TextStyle(
                color: AppTokens.textSecondary,
                height: 1.4,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictTile extends StatelessWidget {
  const _ConflictTile({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppTokens.primaryLight : AppTokens.surface,
      borderRadius: BorderRadius.circular(AppTokens.radiusMd),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppTokens.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppTokens.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? AppTokens.primary : AppTokens.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
