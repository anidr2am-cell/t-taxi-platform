import 'package:flutter/material.dart';

import '../../booking/utils/booking_status_display.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_dispatch_api_service.dart';
import '../widgets/admin_qr_reissue_dialog.dart';
import '../widgets/assign_driver_dialog.dart';
import '../widgets/recommend_drivers_dialog.dart';

class AdminBookingDetailPage extends StatefulWidget {
  final String bookingNumber;
  final AdminDispatchApiService api;
  final VoidCallback onChanged;

  const AdminBookingDetailPage({
    super.key,
    required this.bookingNumber,
    required this.api,
    required this.onChanged,
  });

  @override
  State<AdminBookingDetailPage> createState() => _AdminBookingDetailPageState();
}

class _AdminBookingDetailPageState extends State<AdminBookingDetailPage> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _detail;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await widget.api.getBookingDetail(widget.bookingNumber);
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(err, fallback: context.l10n.t('ui_load_failed'));
        _loading = false;
      });
    }
  }

  List<String> _allowedActions() {
    final actions = _detail?['allowedActions'] as List<dynamic>? ?? [];
    return actions.map((e) => e as String).toList();
  }

  Map<String, dynamic>? _devQrTools() {
    final tools = _detail?['devQrTools'];
    if (tools is Map) return Map<String, dynamic>.from(tools);
    return null;
  }

  Future<void> _reissueQr(String qrType) async {
    setState(() => _submitting = true);
    try {
      await handleAdminQrReissue(
        context: context,
        api: widget.api,
        bookingNumber: widget.bookingNumber,
        qrType: qrType,
      );
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(err, fallback: context.l10n.t('ui_action_failed')))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _assign() async {
    final result = await showAssignDriverDialog(
      context: context,
      api: widget.api,
      isReassign: false,
    );
    if (result == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.assignDriver(widget.bookingNumber, result.driverId);
      widget.onChanged();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver assigned successfully')),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(err, fallback: context.l10n.t('ui_action_failed')))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _recommendDrivers() async {
    final result = await showRecommendDriversDialog(
      context: context,
      api: widget.api,
      bookingNumber: widget.bookingNumber,
    );
    if (result == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.autoAssignDriver(
        widget.bookingNumber,
        driverId: result.useTopCandidate ? null : result.driverId,
        useTopCandidate: result.useTopCandidate,
        expectedAssignmentVersion: result.assignmentVersion,
      );
      widget.onChanged();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Driver assigned successfully')),
        );
      }
    } catch (err) {
      if (mounted) {
        final message = userFacingError(err, fallback: context.l10n.t('ui_action_failed'));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
        if (message.toLowerCase().contains('conflict') ||
            message.toLowerCase().contains('already')) {
          await _load();
        }
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _reassign() async {
    final result = await showAssignDriverDialog(
      context: context,
      api: widget.api,
      isReassign: true,
    );
    if (result == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.reassignDriver(
        widget.bookingNumber,
        result.driverId,
        result.reason!,
      );
      widget.onChanged();
      await _load();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userFacingError(err, fallback: context.l10n.t('ui_action_failed')))),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = _allowedActions();
    final detail = _detail;

    return Scaffold(
      appBar: AppBar(title: Text(widget.bookingNumber)),
      bottomNavigationBar: detail == null || _loading || _error != null
          ? null
          : _actionBar(l10n, actions),
      body: _loading
          ? AppUi.loadingState()
          : _error != null
          ? AppUi.errorState(message: _error!, onRetry: _load, retryLabel: l10n.t('admin_dispatch_retry'))
          : AppUi.centeredContent(
              maxWidth: 900,
              child: SingleChildScrollView(
                padding: AppUi.pagePadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _summaryHeader(l10n, detail!),
                    const SizedBox(height: AppTokens.spaceMd),
                    _basicInfoSection(l10n, detail),
                    const SizedBox(height: AppTokens.spaceMd),
                    _tripSection(l10n, detail),
                    const SizedBox(height: AppTokens.spaceMd),
                    _customerSection(l10n, detail),
                    const SizedBox(height: AppTokens.spaceMd),
                    _assignmentSection(l10n, detail),
                    if (_hasFlight(detail)) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      _flightSection(detail),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    _pricingSection(l10n, detail),
                    if (_statusHistory(detail).isNotEmpty) ...[
                      const SizedBox(height: AppTokens.spaceMd),
                      _activitySection(l10n, detail),
                    ],
                    const SizedBox(height: AppTokens.spaceMd),
                    _qrManagementSection(l10n),
                    const SizedBox(height: 96),
                  ],
                ),
              ),
            ),
    );
  }

  Widget? _actionBar(AppLocalizations l10n, List<String> actions) {
    if (actions.isEmpty) return null;
    final buttons = <Widget>[];
    if (actions.contains('RECOMMEND_DRIVERS')) {
      buttons.add(
        AppUi.secondaryButton(
          label: 'Recommend drivers',
          icon: Icons.recommend_outlined,
          onPressed: _submitting ? null : _recommendDrivers,
          fullWidth: true,
        ),
      );
      buttons.add(const SizedBox(height: 8));
    }
    if (actions.contains('ASSIGN_DRIVER')) {
      buttons.add(
        SizedBox(
          width: double.infinity,
          child: AppUi.primaryButton(
            label: l10n.t('admin_dispatch_assign_driver'),
            icon: Icons.person_add_alt,
            loading: _submitting,
            onPressed: _submitting ? null : _assign,
          ),
        ),
      );
    }
    if (actions.contains('REASSIGN_DRIVER')) {
      buttons.add(
        AppUi.secondaryButton(
          label: l10n.t('admin_dispatch_reassign_driver'),
          icon: Icons.swap_horiz,
          onPressed: _submitting ? null : _reassign,
          fullWidth: true,
        ),
      );
    }
    if (buttons.isEmpty) return null;
    return AppUi.adminStickyActions(actions: buttons);
  }

  Widget _summaryHeader(AppLocalizations l10n, Map<String, dynamic> detail) {
    final assignment = detail['activeAssignment'] is Map
        ? Map<String, dynamic>.from(detail['activeAssignment'] as Map)
        : null;
    final status = detail['status'] as String? ?? '';
    final actions = _allowedActions();

    return AppUi.surfaceCard(
      backgroundColor: AppTokens.primaryLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.bookingNumber,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTokens.primaryDark),
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppUi.statusBadge(
                BookingStatusDisplay.label(l10n, status),
                tone: AppUi.toneForBookingStatus(status),
              ),
            ],
          ),
          const SizedBox(height: AppTokens.spaceSm),
          Text(
            _nextActionHint(l10n, actions),
            style: const TextStyle(color: AppTokens.textSecondary, height: 1.4),
          ),
        ],
      ),
    );
  }

  String _nextActionHint(AppLocalizations l10n, List<String> actions) {
    if (actions.contains('RECOMMEND_DRIVERS')) {
      return l10n.t('admin_dispatch_next_action_recommend');
    }
    if (actions.contains('ASSIGN_DRIVER')) {
      return l10n.t('admin_dispatch_next_action_assign');
    }
    if (actions.contains('REASSIGN_DRIVER')) {
      return l10n.t('admin_dispatch_next_action_reassign');
    }
    return l10n.t('admin_dispatch_next_action_none');
  }

  Widget _basicInfoSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final serviceType = Map<String, dynamic>.from(detail['serviceType'] as Map? ?? {});
    return AppUi.adminDetailSection(
      context: context,
      title: 'Basic information',
      child: Column(
        children: [
          AppUi.summaryRow(
            label: l10n.t('status'),
            value: BookingStatusDisplay.label(
              l10n,
              detail['status'] as String? ?? '',
            ),
          ),
          AppUi.summaryRow(label: l10n.t('service_type'), value: serviceType['name'] as String? ?? '-'),
          AppUi.summaryRow(label: l10n.t('pickup_datetime'), value: detail['scheduledPickupAt'] as String? ?? ''),
          if (detail['createdAt'] != null)
            AppUi.summaryRow(label: 'Created', value: detail['createdAt'] as String),
          if (detail['commissionStatus'] != null)
            AppUi.summaryRow(label: 'Commission', value: detail['commissionStatus'] as String),
        ],
      ),
    );
  }

  Widget _tripSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final route = Map<String, dynamic>.from(detail['route'] as Map);
    final origin = Map<String, dynamic>.from(route['origin'] as Map);
    final destination = Map<String, dynamic>.from(route['destination'] as Map);
    final vehicle = Map<String, dynamic>.from(detail['vehicle'] as Map? ?? {});
    final passengers = Map<String, dynamic>.from(detail['passengers'] as Map? ?? {});
    final luggage = Map<String, dynamic>.from(detail['luggage'] as Map? ?? {});

    return AppUi.adminDetailSection(
      context: context,
      title: 'Trip details',
      child: Column(
        children: [
          AppUi.summaryRow(label: l10n.t('origin'), value: origin['address'] as String? ?? ''),
          AppUi.summaryRow(label: l10n.t('destination'), value: destination['address'] as String? ?? ''),
          AppUi.summaryRow(label: 'Vehicle', value: vehicle['typeName'] as String? ?? '-'),
          AppUi.summaryRow(
            label: 'Passengers',
            value: '${passengers['adults'] ?? 0}A / ${passengers['children'] ?? 0}C / ${passengers['infants'] ?? 0}I',
          ),
          AppUi.summaryRow(
            label: 'Luggage',
            value: '20" ${luggage['carriers20Inch'] ?? 0} · 24"+ ${luggage['carriers24InchPlus'] ?? 0} · Golf ${luggage['golfBags'] ?? 0}',
          ),
          if (detail['specialRequests'] != null && '${detail['specialRequests']}'.isNotEmpty)
            AppUi.summaryRow(label: 'Notes', value: '${detail['specialRequests']}'),
        ],
      ),
    );
  }

  Widget _customerSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final customer = Map<String, dynamic>.from(detail['customer'] as Map);
    return AppUi.adminDetailSection(
      context: context,
      title: 'Customer',
      child: Column(
        children: [
          AppUi.summaryRow(label: l10n.t('name'), value: customer['name'] as String? ?? ''),
          AppUi.summaryRow(label: l10n.t('phone'), value: customer['phone'] as String? ?? ''),
          if (customer['email'] != null)
            AppUi.summaryRow(label: l10n.t('email'), value: customer['email'] as String),
          if (customer['messengerType'] != null)
            AppUi.summaryRow(label: 'Messenger', value: '${customer['messengerType']} ${customer['messengerId'] ?? ''}'.trim()),
        ],
      ),
    );
  }

  Widget _assignmentSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final assignment = detail['activeAssignment'] is Map
        ? Map<String, dynamic>.from(detail['activeAssignment'] as Map)
        : null;
    final vehicle = assignment?['vehicle'] is Map
        ? Map<String, dynamic>.from(assignment!['vehicle'] as Map)
        : null;

    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_dispatch_assigned_driver'),
      backgroundColor: assignment == null ? AppTokens.warningLight : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (assignment == null)
            AppUi.summaryRow(
              label: l10n.t('admin_dispatch_assignment'),
              value: l10n.t('admin_dispatch_unassigned'),
            )
          else ...[
            AppUi.summaryRow(label: l10n.t('name'), value: assignment['driverDisplayName'] as String? ?? ''),
            if (assignment['driverStatus'] != null)
              AppUi.summaryRow(label: l10n.t('status'), value: assignment['driverStatus'] as String),
            if (vehicle != null) AppUi.summaryRow(label: 'Vehicle', value: _vehicleSummary(vehicle)),
            if (assignment['assignedAt'] != null)
              AppUi.summaryRow(label: 'Assigned at', value: assignment['assignedAt'] as String),
            AppUi.summaryRow(
              label: l10n.t('admin_dispatch_assignment'),
              value: assignment['status'] as String? ?? '',
            ),
          ],
        ],
      ),
    );
  }

  bool _hasFlight(Map<String, dynamic> detail) {
    final flight = detail['flight'];
    if (flight is! Map) return false;
    return (flight['flightNumber'] as String?)?.isNotEmpty == true;
  }

  Widget _flightSection(Map<String, dynamic> detail) {
    final flight = Map<String, dynamic>.from(detail['flight'] as Map);
    return AppUi.adminDetailSection(
      context: context,
      title: 'Flight',
      child: Column(
        children: [
          AppUi.summaryRow(label: 'Flight', value: flight['flightNumber'] as String? ?? '-'),
          if (flight['airportIata'] != null)
            AppUi.summaryRow(label: 'Airport', value: flight['airportIata'] as String),
          if (flight['scheduledArrivalAt'] != null)
            AppUi.summaryRow(label: 'Scheduled arrival', value: flight['scheduledArrivalAt'] as String),
          if (flight['estimatedArrivalAt'] != null)
            AppUi.summaryRow(label: 'Estimated arrival', value: flight['estimatedArrivalAt'] as String),
          if (flight['delayStatus'] != null)
            AppUi.summaryRow(label: 'Delay status', value: flight['delayStatus'] as String),
          if (flight['delayMinutes'] != null)
            AppUi.summaryRow(label: 'Delay minutes', value: '${flight['delayMinutes']}'),
        ],
      ),
    );
  }

  Widget _pricingSection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final pricing = Map<String, dynamic>.from(detail['pricing'] as Map);
    final chargeItems = pricing['chargeItems'] as List<dynamic>? ?? [];

    return AppUi.adminDetailSection(
      context: context,
      title: 'Pricing',
      backgroundColor: AppTokens.accentLight,
      child: Column(
        children: [
          for (final raw in chargeItems)
            AppUi.summaryRow(
              label: _chargeLabel(raw),
              value: '${_chargeAmount(raw)} ${pricing['currency']}',
            ),
          if (chargeItems.isNotEmpty) const Divider(height: 20),
          AppUi.summaryRow(
            label: l10n.t('total'),
            value: '${pricing['totalAmount']} ${pricing['currency']}',
            emphasize: true,
          ),
          AppUi.summaryRow(
            label: l10n.t('payment_method'),
            value: pricing['paymentMethod'] as String? ?? '',
          ),
          if (pricing['paymentStatus'] != null)
            AppUi.summaryRow(label: 'Payment status', value: pricing['paymentStatus'] as String),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _statusHistory(Map<String, dynamic> detail) {
    return (detail['statusHistory'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  Widget _activitySection(AppLocalizations l10n, Map<String, dynamic> detail) {
    final history = _statusHistory(detail);
    return AppUi.adminDetailSection(
      context: context,
      title: 'Activity log',
      child: Column(
        children: history.map((entry) {
          final from = entry['fromStatus'] as String? ?? '-';
          final to = entry['toStatus'] as String? ?? '-';
          final when = entry['createdAt'] as String? ?? '';
          final role = entry['changedByRole'] as String? ?? '';
          final fromLabel = from == '-'
              ? from
              : BookingStatusDisplay.label(l10n, from);
          final toLabel = to == '-'
              ? to
              : BookingStatusDisplay.label(l10n, to);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.history, size: 18, color: AppTokens.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$fromLabel → $toLabel',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      if (when.isNotEmpty)
                        Text(when, style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12)),
                      if (role.isNotEmpty)
                        Text(role, style: const TextStyle(color: AppTokens.textMuted, fontSize: 12)),
                      if (entry['reason'] != null)
                        Text('${entry['reason']}', style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                AppUi.statusBadge(
                  toLabel,
                  tone: AppUi.toneForBookingStatus(to),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _qrManagementSection(AppLocalizations l10n) {
    final tools = _devQrTools();
    if (tools == null) return const SizedBox.shrink();

    final enabled = tools['qrReissueEnabled'] == true;
    final disabledReason = tools['disabledReason'] as String?;
    final boarding = Map<String, dynamic>.from(tools['boarding'] as Map? ?? {});
    final dropoff = Map<String, dynamic>.from(tools['dropoff'] as Map? ?? {});

    return AppUi.adminDetailSection(
      context: context,
      title: l10n.t('admin_qr_management_title'),
      subtitle: enabled
          ? l10n.t('admin_qr_management_help')
          : (disabledReason ?? l10n.t('admin_qr_management_disabled_help')),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (enabled) ...[
            if (boarding['reissueAvailable'] == true)
              AppUi.secondaryButton(
                label: l10n.t('admin_dev_qr_reissue_boarding'),
                icon: Icons.qr_code,
                onPressed: _submitting ? null : () => _reissueQr('BOARDING'),
                fullWidth: true,
              )
            else if (boarding['unavailableReason'] != null)
              Text(
                boarding['unavailableReason'] as String,
                style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
              ),
            if (dropoff['reissueAvailable'] == true) ...[
              const SizedBox(height: 8),
              AppUi.secondaryButton(
                label: l10n.t('admin_dev_qr_reissue_dropoff'),
                icon: Icons.qr_code_2,
                onPressed: _submitting ? null : () => _reissueQr('DROPOFF'),
                fullWidth: true,
              ),
            ] else if (dropoff['unavailableReason'] != null) ...[
              const SizedBox(height: 8),
              Text(
                dropoff['unavailableReason'] as String,
                style: const TextStyle(color: AppTokens.textSecondary, fontSize: 12),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _vehicleSummary(Map<String, dynamic> vehicle) {
    return [
      vehicle['typeCode'],
      vehicle['plateNumber'],
      vehicle['modelName'],
    ].whereType<String>().where((value) => value.isNotEmpty).join(' · ');
  }

  String _chargeLabel(dynamic raw) {
    return Map<String, dynamic>.from(raw as Map)['description'] as String? ?? 'Charge';
  }

  num? _chargeAmount(dynamic raw) {
    return Map<String, dynamic>.from(raw as Map)['amount'] as num?;
  }
}
