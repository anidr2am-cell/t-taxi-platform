import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../services/admin_dispatch_api_service.dart';

class AssignDriverDialogResult {
  final int driverId;
  final String? reason;

  AssignDriverDialogResult({required this.driverId, this.reason});
}

Future<AssignDriverDialogResult?> showAssignDriverDialog({
  required BuildContext context,
  required AdminDispatchApiService api,
  required bool isReassign,
}) {
  return showDialog<AssignDriverDialogResult>(
    context: context,
    builder: (_) => AssignDriverDialog(api: api, isReassign: isReassign),
  );
}

class AssignDriverDialog extends StatefulWidget {
  final AdminDispatchApiService api;
  final bool isReassign;

  const AssignDriverDialog({
    super.key,
    required this.api,
    required this.isReassign,
  });

  @override
  State<AssignDriverDialog> createState() => _AssignDriverDialogState();
}

class _AssignDriverDialogState extends State<AssignDriverDialog> {
  bool _loading = true;
  String? _error;
  List<dynamic> _drivers = [];
  int? _selectedDriverId;
  final _reasonController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadDrivers();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadDrivers() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drivers = await widget.api.listDrivers();
      setState(() {
        _drivers = drivers;
        _loading = false;
      });
    } catch (err) {
      setState(() {
        _error = err.toString();
        _loading = false;
      });
    }
  }

  Future<void> _confirm() async {
    if (_selectedDriverId == null) return;
    if (widget.isReassign && _reasonController.text.trim().isEmpty) return;
    setState(() => _submitting = true);
    Navigator.pop(
      context,
      AssignDriverDialogResult(
        driverId: _selectedDriverId!,
        reason: widget.isReassign ? _reasonController.text.trim() : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = widget.isReassign
        ? l10n.t('admin_dispatch_reassign_driver')
        : l10n.t('admin_dispatch_assign_driver');

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!),
                      ElevatedButton(onPressed: _loadDrivers, child: Text(l10n.t('admin_dispatch_retry'))),
                    ],
                  )
                : _drivers.isEmpty
                    ? Text(l10n.t('admin_dispatch_no_drivers'))
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ..._drivers.map((raw) {
                            final driver = Map<String, dynamic>.from(raw as Map);
                            final eligible = driver['assignmentEligible'] == true;
                            final id = driver['driverId'] as int;
                            final selected = _selectedDriverId == id;
                            return ListTile(
                              enabled: eligible,
                              selected: selected,
                              onTap: eligible
                                  ? () => setState(() => _selectedDriverId = id)
                                  : null,
                              leading: Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                color: eligible ? null : Colors.grey,
                              ),
                              title: Text(driver['displayName'] as String? ?? ''),
                              subtitle: Text(
                                '${driver['phone']} · ${driver['eligibilityState']} · active ${driver['activeAssignmentCount']}',
                              ),
                            );
                          }),
                          if (widget.isReassign) ...[
                            const SizedBox(height: 8),
                            TextField(
                              controller: _reasonController,
                              decoration: InputDecoration(
                                labelText: l10n.t('admin_dispatch_reassign_reason'),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ],
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.t('back'))),
        ElevatedButton(
          onPressed: _submitting ? null : _confirm,
          child: Text(l10n.t('confirm')),
        ),
      ],
    );
  }
}
