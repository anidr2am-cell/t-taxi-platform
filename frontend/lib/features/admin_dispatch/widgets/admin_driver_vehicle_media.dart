import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/browser_download.dart';
import '../../booking/utils/thailand_pickup_datetime.dart';
import '../services/admin_dispatch_api_service.dart';

class AdminDriverVehicleMedia extends StatefulWidget {
  const AdminDriverVehicleMedia({
    super.key,
    required this.driverId,
    required this.vehicle,
    required this.api,
    this.onChanged,
  });
  final int driverId;
  final Map<String, dynamic> vehicle;
  final AdminDispatchApiService api;
  final VoidCallback? onChanged;
  @override
  State<AdminDriverVehicleMedia> createState() =>
      _AdminDriverVehicleMediaState();
}

class _AdminDriverVehicleMediaState extends State<AdminDriverVehicleMedia> {
  late Future<List<dynamic>> _media;
  final _bytes = <int, Future<Uint8List>>{};
  late Map<String, dynamic> _insurance;
  bool _saving = false;
  String? _error;
  int get _vehicleId => (widget.vehicle['vehicleId'] as num).toInt();
  @override
  void initState() {
    super.initState();
    _insurance = Map<String, dynamic>.from(
      widget.vehicle['insurance'] as Map? ?? {},
    );
    _media = widget.api.getDriverVehicleMedia(widget.driverId, _vehicleId);
  }

  Future<void> _setDate() async {
    final today = ThailandPickupDateTime.thailandNow();
    final initial =
        DateTime.tryParse(_insurance['expiresOn']?.toString() ?? '') ?? today;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null || !mounted) return;
    final date =
        '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final insurance = await widget.api.updateDriverInsurance(
        widget.driverId,
        _vehicleId,
        date,
      );
      if (!mounted) return;
      setState(() => _insurance = insurance);
      widget.onChanged?.call();
    } catch (_) {
      if (mounted) {
        setState(() => _error = context.l10n.t('admin_vehicle_load_error'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final status = _insurance['status'] as String? ?? 'MISSING';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${l.t('admin_vehicle_insurance_date')}: ${_insurance['expiresOn'] ?? l.t('admin_vehicle_insurance_MISSING')}',
        ),
        Text(
          l.t('admin_vehicle_insurance_$status'),
          style: TextStyle(
            color: status == 'EXPIRED'
                ? AppTokens.error
                : status == 'EXPIRING'
                ? AppTokens.warning
                : AppTokens.textMuted,
          ),
        ),
        Text(l.t('admin_vehicle_insurance_help')),
        OutlinedButton.icon(
          onPressed: _saving ? null : _setDate,
          icon: const Icon(Icons.event),
          label: Text(l.t('admin_vehicle_insurance_edit')),
        ),
        if (_saving) const LinearProgressIndicator(),
        if (_error != null) Text(_error!),
        FutureBuilder<List<dynamic>>(
          future: _media,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return TextButton(
                onPressed: () => setState(() {
                  _bytes.clear();
                  _media = widget.api.getDriverVehicleMedia(
                    widget.driverId,
                    _vehicleId,
                  );
                }),
                child: Text(l.t('admin_vehicle_load_error')),
              );
            }
            if (!snapshot.hasData) return const LinearProgressIndicator();
            if (snapshot.data!.isEmpty) {
              return Text(l.t('admin_vehicle_no_files'));
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final raw in snapshot.data!)
                  _file(Map<String, dynamic>.from(raw as Map)),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _file(Map<String, dynamic> file) {
    final l = context.l10n;
    final photo = file['category'] == 'DRIVER_VEHICLE_PHOTO';
    final id = (file['fileId'] as num).toInt();
    final mime = file['mimeType'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTokens.spaceSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l.t(
              photo
                  ? 'admin_vehicle_photo'
                  : 'admin_vehicle_insurance_certificate',
            ),
          ),
          if (file['available'] != true)
            Text(l.t('admin_vehicle_missing_file'))
          else
            FutureBuilder<Uint8List>(
              future: _bytes.putIfAbsent(
                id,
                () => widget.api.getDriverVehicleMediaBytes(
                  widget.driverId,
                  _vehicleId,
                  id,
                ),
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Text(l.t('admin_vehicle_missing_file'));
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (mime.startsWith('image/'))
                      Image.memory(
                        snapshot.data!,
                        height: 160,
                        fit: BoxFit.contain,
                        errorBuilder: (_, error, stack) =>
                            Text(l.t('admin_vehicle_missing_file')),
                      ),
                    OutlinedButton.icon(
                      onPressed: () => downloadBytes(
                        snapshot.data!,
                        'driver-${widget.driverId}-vehicle-$_vehicleId-file-$id.${mime == 'application/pdf'
                            ? 'pdf'
                            : mime == 'image/png'
                            ? 'png'
                            : mime == 'image/webp'
                            ? 'webp'
                            : 'jpg'}',
                        mime,
                      ),
                      icon: const Icon(Icons.download),
                      label: Text(l.t('admin_vehicle_download')),
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
