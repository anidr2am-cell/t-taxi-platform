import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../widgets/app_ui.dart';
import '../services/admin_dispatch_api_service.dart';
import '../utils/admin_customer_brief.dart';

class AdminDriverDetailDialog extends StatefulWidget {
  const AdminDriverDetailDialog({
    super.key,
    required this.driverId,
    required this.api,
  });
  final int driverId;
  final AdminDispatchApiService api;
  @override
  State<AdminDriverDetailDialog> createState() =>
      _AdminDriverDetailDialogState();
}

class _AdminDriverDetailDialogState extends State<AdminDriverDetailDialog> {
  late Future<Map<String, dynamic>> _detail;
  @override
  void initState() {
    super.initState();
    _detail = widget.api.getDriverDetail(widget.driverId);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    String t(String k) => l.t('admin_customer_brief_$k');
    Widget row(String key, dynamic value) => AppUi.summaryRow(
      label: t(key),
      value: briefText(value).isEmpty ? '-' : briefText(value),
    );
    return AlertDialog(
      title: Text(t('driver_title')),
      content: SizedBox(
        width: 600,
        child: FutureBuilder<Map<String, dynamic>>(
          future: _detail,
          builder: (context, snapshot) {
            if (snapshot.hasError)
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(t('error')),
                  TextButton(
                    onPressed: () => setState(
                      () =>
                          _detail = widget.api.getDriverDetail(widget.driverId),
                    ),
                    child: Text(l.t('admin_dispatch_retry')),
                  ),
                ],
              );
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final d = snapshot.data!;
            final vehicles = (d['vehicles'] as List? ?? [])
                .map(briefMap)
                .toList();
            return SingleChildScrollView(
              child: SelectionArea(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      briefText(d['displayName']),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('ID: ${widget.driverId}'),
                    row('phone', d['phone']),
                    row('status', d['driverStatus']),
                    row('online', d['onlineState']),
                    row('jobs', d['activeAssignmentCount']),
                    row('rating', d['averageRating']),
                    if (briefMap(d['suspension'])['reason'] != null)
                      Text(
                        '${l.t('admin_driver_suspend_reason_label')}: ${briefMap(d['suspension'])['reason']}',
                      ),
                    const SizedBox(height: AppTokens.spaceMd),
                    if (vehicles.isEmpty) Text(t('no_vehicle')),
                    for (final v in vehicles) ...[
                      Text(
                        '${briefText(v['modelName'])} · ${briefText(v['plateNumber'])}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      if (v['isPrimary'] == true) Text(t('primary')),
                      row('vehicle', v['typeCode']),
                      row('color', v['color']),
                      row('vehicle_status', v['approvalStatus']),
                      const SizedBox(height: AppTokens.spaceSm),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(MaterialLocalizations.of(context).closeButtonLabel),
        ),
      ],
    );
  }
}
