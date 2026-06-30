import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
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
      setState(() {
        _error = err.toString();
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err.toString())));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err.toString())));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err.toString())));
        if (err.toString().toLowerCase().contains('conflict') ||
            err.toString().toLowerCase().contains('already')) {
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(err.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _qrManagementSection(AppLocalizations l10n) {
    final tools = _devQrTools();
    if (tools == null) return const SizedBox.shrink();

    final enabled = tools['qrReissueEnabled'] == true;
    final disabledReason = tools['disabledReason'] as String?;
    final boarding = Map<String, dynamic>.from(tools['boarding'] as Map? ?? {});
    final dropoff = Map<String, dynamic>.from(tools['dropoff'] as Map? ?? {});

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.t('admin_qr_management_title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              enabled
                  ? l10n.t('admin_qr_management_help')
                  : (disabledReason ??
                        l10n.t('admin_qr_management_disabled_help')),
              style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
            ),
            if (enabled) ...[
              const SizedBox(height: 12),
              if (boarding['reissueAvailable'] == true)
                OutlinedButton(
                  onPressed: _submitting ? null : () => _reissueQr('BOARDING'),
                  child: Text(l10n.t('admin_dev_qr_reissue_boarding')),
                )
              else if (boarding['unavailableReason'] != null)
                Text(
                  boarding['unavailableReason'] as String,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              if (dropoff['reissueAvailable'] == true) ...[
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: _submitting ? null : () => _reissueQr('DROPOFF'),
                  child: Text(l10n.t('admin_dev_qr_reissue_dropoff')),
                ),
              ] else if (dropoff['unavailableReason'] != null) ...[
                const SizedBox(height: 8),
                Text(
                  dropoff['unavailableReason'] as String,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final actions = _allowedActions();

    return Scaffold(
      appBar: AppBar(title: Text(widget.bookingNumber)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  ElevatedButton(
                    onPressed: _load,
                    child: Text(l10n.t('admin_dispatch_retry')),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _infoCard(l10n, _detail!),
                  const SizedBox(height: 16),
                  _assignmentCard(l10n, _detail!),
                  const SizedBox(height: 16),
                  _qrManagementSection(l10n),
                  const SizedBox(height: 16),
                  if (actions.contains('RECOMMEND_DRIVERS'))
                    OutlinedButton(
                      onPressed: _submitting ? null : _recommendDrivers,
                      child: const Text('Recommend drivers'),
                    ),
                  if (actions.contains('ASSIGN_DRIVER'))
                    ElevatedButton(
                      onPressed: _submitting ? null : _assign,
                      child: Text(l10n.t('admin_dispatch_assign_driver')),
                    ),
                  if (actions.contains('REASSIGN_DRIVER'))
                    OutlinedButton(
                      onPressed: _submitting ? null : _reassign,
                      child: Text(l10n.t('admin_dispatch_reassign_driver')),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _infoCard(AppLocalizations l10n, Map<String, dynamic> detail) {
    final route = Map<String, dynamic>.from(detail['route'] as Map);
    final origin = Map<String, dynamic>.from(route['origin'] as Map);
    final destination = Map<String, dynamic>.from(route['destination'] as Map);
    final customer = Map<String, dynamic>.from(detail['customer'] as Map);
    final pricing = Map<String, dynamic>.from(detail['pricing'] as Map);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('booking_summary'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _row(l10n.t('status'), detail['status'] as String? ?? ''),
            _row(
              l10n.t('pickup_datetime'),
              detail['scheduledPickupAt'] as String? ?? '',
            ),
            _row(l10n.t('origin'), origin['address'] as String? ?? ''),
            _row(
              l10n.t('destination'),
              destination['address'] as String? ?? '',
            ),
            _row(l10n.t('name'), customer['name'] as String? ?? ''),
            _row(l10n.t('phone'), customer['phone'] as String? ?? ''),
            _row(
              l10n.t('total'),
              '${pricing['totalAmount']} ${pricing['currency']}',
            ),
            _row(
              l10n.t('payment_method'),
              pricing['paymentMethod'] as String? ?? '',
            ),
          ],
        ),
      ),
    );
  }

  Widget _assignmentCard(AppLocalizations l10n, Map<String, dynamic> detail) {
    final assignment = detail['activeAssignment'] is Map
        ? Map<String, dynamic>.from(detail['activeAssignment'] as Map)
        : null;
    final vehicle = assignment?['vehicle'] is Map
        ? Map<String, dynamic>.from(assignment!['vehicle'] as Map)
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.t('admin_dispatch_assigned_driver'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (assignment == null)
              _row(
                l10n.t('admin_dispatch_assignment'),
                l10n.t('admin_dispatch_unassigned'),
              )
            else ...[
              _row(
                l10n.t('name'),
                assignment['driverDisplayName'] as String? ?? '',
              ),
              if (assignment['driverStatus'] != null)
                _row(l10n.t('status'), assignment['driverStatus'] as String),
              if (vehicle != null) _row('Vehicle', _vehicleSummary(vehicle)),
              if (assignment['assignedAt'] != null)
                _row('Assigned at', assignment['assignedAt'] as String),
              _row(
                l10n.t('admin_dispatch_assignment'),
                assignment['status'] as String? ?? '',
              ),
            ],
          ],
        ),
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

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
