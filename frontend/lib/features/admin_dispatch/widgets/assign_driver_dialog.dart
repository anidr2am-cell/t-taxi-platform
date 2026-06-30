import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
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
      shape: RoundedRectangleBorder(borderRadius: AppTokens.borderRadiusLg),
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: _loading
            ? AppUi.loadingState(message: 'Loading drivers...')
            : _error != null
                ? AppUi.errorState(message: _error!, onRetry: _loadDrivers, retryLabel: l10n.t('admin_dispatch_retry'))
                : _drivers.isEmpty
                    ? AppUi.emptyState(title: l10n.t('admin_dispatch_no_drivers'))
                    : SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ..._drivers.map((raw) {
                              final driver = Map<String, dynamic>.from(raw as Map);
                              final eligible = driver['assignmentEligible'] == true;
                              final id = driver['driverId'] as int;
                              final selected = _selectedDriverId == id;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: AppUi.surfaceCard(
                                  onTap: eligible ? () => setState(() => _selectedDriverId = id) : null,
                                  backgroundColor: selected ? AppTokens.primaryLight : AppTokens.surface,
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                        color: eligible
                                            ? (selected ? AppTokens.primary : AppTokens.textSecondary)
                                            : AppTokens.textMuted,
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              driver['displayName'] as String? ?? '',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w700,
                                                color: eligible ? AppTokens.textPrimary : AppTokens.textMuted,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              '${driver['phone']} · ${driver['eligibilityState']} · active ${driver['activeAssignmentCount']}',
                                              style: const TextStyle(
                                                color: AppTokens.textSecondary,
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                            if (widget.isReassign) ...[
                              const SizedBox(height: AppTokens.spaceSm),
                              TextField(
                                controller: _reasonController,
                                decoration: InputDecoration(
                                  labelText: l10n.t('admin_dispatch_reassign_reason'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.t('back'))),
        AppUi.primaryButton(
          label: l10n.t('confirm'),
          icon: Icons.check,
          onPressed: _submitting ? null : _confirm,
        ),
      ],
    );
  }
}
