import 'package:flutter/material.dart';

import '../../../features/driver_application/models/driver_application_models.dart';
import '../../../features/driver_application/services/driver_application_api_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';

class AdminDriverApplicationDetailPage extends StatefulWidget {
  const AdminDriverApplicationDetailPage({
    super.key,
    required this.id,
    this.api,
    this.onChanged,
  });

  final int id;
  final DriverApplicationApiService? api;
  final VoidCallback? onChanged;

  @override
  State<AdminDriverApplicationDetailPage> createState() =>
      _AdminDriverApplicationDetailPageState();
}

class _AdminDriverApplicationDetailPageState
    extends State<AdminDriverApplicationDetailPage> {
  late final DriverApplicationApiService _api =
      widget.api ?? DriverApplicationApiService();
  bool _loading = true;
  bool _acting = false;
  String? _error;
  DriverApplicationAdminDetail? _detail;

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
      final detail = await _api.getAdminApplicationDetail(widget.id);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('ui_load_failed'),
        );
        _loading = false;
      });
    }
  }

  AppStatusTone _tone(String status) {
    switch (status) {
      case 'APPROVED':
        return AppStatusTone.success;
      case 'REJECTED':
        return AppStatusTone.error;
      default:
        return AppStatusTone.warning;
    }
  }

  String _label(String status) {
    switch (status) {
      case 'APPROVED':
        return context.l10n.t('driver_application_status_approved');
      case 'REJECTED':
        return context.l10n.t('driver_application_status_rejected');
      default:
        return context.l10n.t('driver_application_status_pending');
    }
  }

  Future<void> _approve() async {
    final detail = _detail;
    if (detail == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('admin_driver_application_approve_title')),
        content: Text(
          '${detail.fullName}\n${detail.email}\n${detail.vehiclePlateNumber}\n\n'
          '${context.l10n.t('admin_driver_application_approve_help')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.t('ui_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.t('admin_driver_application_approve')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _act(
      () => _api.approveApplication(detail.id),
      'admin_driver_application_approved',
    );
  }

  Future<void> _reject() async {
    final detail = _detail;
    if (detail == null) return;
    final reason = TextEditingController();
    final note = TextEditingController();
    final result = await showDialog<Map<String, String>?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('admin_driver_application_reject_title')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.t('admin_driver_application_reject_help')),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: reason,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: context.l10n.t(
                    'admin_driver_application_rejection_reason',
                  ),
                ),
              ),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: note,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: context.l10n.t(
                    'admin_driver_application_admin_note',
                  ),
                  helperText: context.l10n.t(
                    'admin_driver_application_admin_note_private',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.t('ui_cancel')),
          ),
          FilledButton.tonal(
            onPressed: () {
              if (reason.text.trim().isEmpty) return;
              Navigator.pop(context, {
                'reason': reason.text.trim(),
                'note': note.text.trim(),
              });
            },
            child: Text(context.l10n.t('admin_driver_application_reject')),
          ),
        ],
      ),
    );
    reason.dispose();
    note.dispose();
    if (result == null) return;
    await _act(
      () => _api.rejectApplication(
        detail.id,
        rejectionReason: result['reason']!,
        adminNote: result['note'],
      ),
      'admin_driver_application_rejected',
    );
  }

  Future<void> _act(
    Future<Object?> Function() action,
    String successKey,
  ) async {
    setState(() => _acting = true);
    try {
      await action();
      widget.onChanged?.call();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.t(successKey))));
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(err, fallback: context.l10n.t('ui_action_failed')),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.t('admin_driver_application_detail')),
      ),
      bottomNavigationBar: detail?.status == 'PENDING'
          ? AppUi.adminStickyActions(
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _acting ? null : _reject,
                        icon: const Icon(Icons.block_outlined),
                        label: Text(
                          context.l10n.t('admin_driver_application_reject'),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _acting ? null : _approve,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(
                          context.l10n.t('admin_driver_application_approve'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null,
      body: _loading
          ? AppUi.loadingState()
          : _error != null
          ? AppUi.errorState(
              message: _error!,
              retryLabel: context.l10n.t('ui_retry'),
              onRetry: _load,
            )
          : detail == null
          ? AppUi.emptyState(
              title: context.l10n.t('admin_driver_application_empty'),
            )
          : _content(detail),
    );
  }

  Widget _content(DriverApplicationAdminDetail detail) {
    final l10n = context.l10n;
    return AppUi.centeredContent(
      maxWidth: 960,
      child: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          AppUi.surfaceCard(
            backgroundColor: detail.status == 'PENDING'
                ? AppTokens.warningLight
                : detail.status == 'APPROVED'
                ? AppTokens.successLight
                : AppTokens.errorLight,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    detail.applicationNumber,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                AppUi.statusBadge(
                  _label(detail.status),
                  tone: _tone(detail.status),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTokens.spaceMd),
          _section(l10n.t('driver_application_section_basic'), [
            ['driver_application_full_name', detail.fullName],
            ['email', detail.email],
            [
              'phone',
              '${detail.phoneCountryCode ?? ''} ${detail.phone}'.trim(),
            ],
            ['country', detail.countryCode ?? '-'],
            ['landing_language_label', detail.locale],
          ]),
          _section(l10n.t('driver_application_section_license'), [
            ['driver_application_license_number', detail.drivingLicenseNumber],
            [
              'driver_application_license_country',
              detail.drivingLicenseCountry ?? '-',
            ],
            [
              'driver_application_license_expiry',
              detail.drivingLicenseExpiryDate ?? '-',
            ],
            [
              'driver_application_experience',
              '${detail.yearsOfDrivingExperience}',
            ],
          ]),
          _section(l10n.t('driver_application_section_vehicle'), [
            [
              'driver_application_vehicle_ownership',
              detail.vehicleOwnershipType,
            ],
            ['driver_application_vehicle_type', detail.vehicleTypeCode],
            ['driver_application_vehicle_make', detail.vehicleMake ?? '-'],
            ['driver_application_vehicle_model', detail.vehicleModel ?? '-'],
            [
              'driver_application_vehicle_year',
              detail.vehicleYear?.toString() ?? '-',
            ],
            ['driver_application_vehicle_color', detail.vehicleColor ?? '-'],
            ['driver_application_vehicle_plate', detail.vehiclePlateNumber],
          ]),
          _section(l10n.t('driver_application_section_service'), [
            [
              'driver_application_service_areas',
              detail.serviceAreas.join(', '),
            ],
            ['driver_application_languages', detail.languages.join(', ')],
            ['driver_application_notes', detail.notes ?? '-'],
          ]),
          _section(l10n.t('driver_application_section_consent'), [
            [
              'driver_application_personal_consent',
              detail.personalDataConsentAt ?? '-',
            ],
            [
              'driver_application_terms_consent',
              detail.driverTermsConsentAt ?? '-',
            ],
            ['driver_application_submitted_at', detail.submittedAt],
            ['driver_application_reviewed_at', detail.reviewedAt ?? '-'],
          ]),
          if (detail.rejectionReason != null || detail.adminNote != null)
            _section(l10n.t('admin_driver_application_review_info'), [
              [
                'admin_driver_application_rejection_reason',
                detail.rejectionReason ?? '-',
              ],
              ['admin_driver_application_admin_note', detail.adminNote ?? '-'],
              [
                'admin_driver_application_admin_note_private',
                l10n.t('admin_driver_application_admin_note_private'),
              ],
            ]),
          if (detail.status != 'PENDING')
            Padding(
              padding: const EdgeInsets.only(top: AppTokens.spaceMd),
              child: AppUi.surfaceCard(
                backgroundColor: AppTokens.surfaceMuted,
                child: Text(l10n.t('admin_driver_application_processed')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, List<List<String>> rows) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: AppUi.adminDetailSection(
        context: context,
        title: title,
        child: Column(
          children: rows
              .map(
                (row) => AppUi.summaryRow(
                  label: context.l10n.t(row[0]),
                  value: row[1],
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}
