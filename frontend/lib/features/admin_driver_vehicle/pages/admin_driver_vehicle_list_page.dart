import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/admin_driver_vehicle_models.dart';
import '../services/admin_driver_vehicle_api_service.dart';

class AdminDriverVehicleListPage extends StatefulWidget {
  const AdminDriverVehicleListPage({super.key, this.api});

  final AdminDriverVehicleApiService? api;

  @override
  State<AdminDriverVehicleListPage> createState() =>
      _AdminDriverVehicleListPageState();
}

class _AdminDriverVehicleListPageState
    extends State<AdminDriverVehicleListPage> {
  late final AdminDriverVehicleApiService _api =
      widget.api ?? AdminDriverVehicleApiService();
  final _search = TextEditingController();

  bool _loading = true;
  bool _acting = false;
  String? _error;
  String _status = 'PENDING';
  int _page = 1;
  int _total = 0;
  final int _limit = 20;
  List<AdminDriverVehicleListItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load(page: 1);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({required int page}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.listVehicles(
        page: page,
        limit: _limit,
        status: _status,
        search: _search.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _page = page;
        _total = data.total;
        _items = data.items;
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

  String _statusLabel(String status) {
    switch (status) {
      case 'APPROVED':
        return context.l10n.t('driver_application_status_approved');
      case 'REJECTED':
        return context.l10n.t('driver_application_status_rejected');
      default:
        return context.l10n.t('driver_application_status_pending');
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

  String _categoryLabel(String category) {
    switch (category) {
      case 'DRIVER_VEHICLE_PHOTO':
        return context.l10n.t('driver_vehicle_photos_title');
      case 'DRIVER_INSURANCE_CERTIFICATE':
        return context.l10n.t('driver_vehicle_insurance_title');
      case 'DRIVER_VEHICLE_REGISTRATION':
        return context.l10n.t('driver_vehicle_registration_title');
      case 'DRIVER_TAX_CERTIFICATE':
        return context.l10n.t('driver_application_tax_certificate');
      default:
        return category;
    }
  }

  Future<void> _approve(AdminDriverVehicleListItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('admin_driver_vehicle_approve_title')),
        content: Text(
          '${item.driverName}\n${item.vehicleTypeName}\n${item.plateNumber}\n\n'
          '${context.l10n.t('admin_driver_vehicle_approve_help')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.l10n.t('ui_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.t('admin_driver_vehicle_approve')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _act(() => _api.approve(item.id), 'admin_driver_vehicle_approved');
  }

  Future<void> _reject(AdminDriverVehicleListItem item) async {
    final reason = TextEditingController();
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.t('admin_driver_vehicle_reject_title')),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.l10n.t('admin_driver_vehicle_reject_help')),
              const SizedBox(height: AppTokens.spaceSm),
              TextField(
                controller: reason,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: context.l10n.t(
                    'admin_driver_vehicle_rejection_reason',
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
              Navigator.pop(context, reason.text.trim());
            },
            child: Text(context.l10n.t('admin_driver_vehicle_reject')),
          ),
        ],
      ),
    );
    reason.dispose();
    if (result == null || result.isEmpty) return;
    await _act(
      () => _api.reject(item.id, rejectionReason: result),
      'admin_driver_vehicle_rejected',
    );
  }

  Future<void> _act(Future<void> Function() action, String successKey) async {
    setState(() => _acting = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.t(successKey))),
      );
      await _load(page: 1);
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

  Future<void> _previewFile(AdminDriverVehicleFile file) async {
    if (!file.isImage) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(file.originalFilename ?? file.category)),
      );
      return;
    }
    try {
      final bytes = await _api.fetchFileBytes(file.url);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          child: InteractiveViewer(
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(err, fallback: context.l10n.t('ui_load_failed')),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        Padding(
          padding: AppUi.pagePadding(
            context,
          ).copyWith(bottom: AppTokens.spaceSm),
          child: AppUi.surfaceCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppUi.sectionHeader(
                  context,
                  title: l10n.t('admin_driver_vehicle_title'),
                  subtitle: l10n.t('admin_driver_vehicle_subtitle'),
                  trailing: IconButton(
                    tooltip: l10n.t('admin_dispatch_refresh'),
                    onPressed: _acting ? null : () => _load(page: 1),
                    icon: const Icon(Icons.refresh),
                  ),
                ),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: l10n.t('admin_driver_vehicle_search'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search),
                      onPressed: () => _load(page: 1),
                    ),
                  ),
                  onSubmitted: (_) => _load(page: 1),
                ),
                const SizedBox(height: AppTokens.spaceSm),
                Wrap(
                  spacing: AppTokens.spaceSm,
                  children: [
                    for (final status in const [
                      'PENDING',
                      'APPROVED',
                      'REJECTED',
                      '',
                    ])
                      ChoiceChip(
                        label: Text(
                          status.isEmpty
                              ? l10n.t('admin_driver_application_all_statuses')
                              : _statusLabel(status),
                        ),
                        selected: _status == status,
                        onSelected: (_) {
                          setState(() => _status = status);
                          _load(page: 1);
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: AppTokens.error)))
              : _items.isEmpty
              ? AppUi.emptyState(
                  title: l10n.t('admin_driver_vehicle_empty'),
                  message: l10n.t('admin_driver_vehicle_subtitle'),
                  icon: Icons.directions_car_outlined,
                )
              : ListView.separated(
                  padding: AppUi.pagePadding(context),
                  itemCount: _items.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppTokens.spaceSm),
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    return AppUi.surfaceCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.driverName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                              AppUi.statusBadge(
                                _statusLabel(item.approvalStatus),
                                tone: _tone(item.approvalStatus),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${item.vehicleTypeName.isNotEmpty ? item.vehicleTypeName : item.vehicleTypeCode} · ${item.plateNumber}',
                          ),
                          if (item.submittedAt.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.submittedAt,
                              style: const TextStyle(
                                color: AppTokens.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                          if (item.files.isNotEmpty) ...[
                            const SizedBox(height: AppTokens.spaceSm),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final file in item.files.take(8))
                                  InkWell(
                                    onTap: () => _previewFile(file),
                                    child: Chip(
                                      avatar: Icon(
                                        file.isImage
                                            ? Icons.image_outlined
                                            : Icons.description_outlined,
                                        size: 16,
                                      ),
                                      label: Text(_categoryLabel(file.category)),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                          if (item.approvalStatus == 'PENDING') ...[
                            const SizedBox(height: AppTokens.spaceSm),
                            Row(
                              children: [
                                FilledButton(
                                  onPressed: _acting
                                      ? null
                                      : () => _approve(item),
                                  child: Text(
                                    l10n.t('admin_driver_vehicle_approve'),
                                  ),
                                ),
                                const SizedBox(width: AppTokens.spaceSm),
                                FilledButton.tonal(
                                  onPressed: _acting
                                      ? null
                                      : () => _reject(item),
                                  child: Text(
                                    l10n.t('admin_driver_vehicle_reject'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                ),
        ),
        if (!_loading && _total > _limit)
          Padding(
            padding: const EdgeInsets.all(AppTokens.spaceSm),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: _page <= 1 || _acting
                      ? null
                      : () => _load(page: _page - 1),
                  child: const Text('‹'),
                ),
                Text('$_page / ${((_total + _limit - 1) / _limit).floor()}'),
                TextButton(
                  onPressed:
                      _page * _limit >= _total || _acting
                      ? null
                      : () => _load(page: _page + 1),
                  child: const Text('›'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
