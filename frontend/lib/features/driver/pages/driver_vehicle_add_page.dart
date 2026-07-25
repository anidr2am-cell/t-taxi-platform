import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../config/app_config.dart';
import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../driver_application/models/driver_application_models.dart';
import '../../driver_application/widgets/driver_registration_photo_upload_card.dart';
import '../services/driver_api_service.dart';

class DriverVehicleAddPage extends StatefulWidget {
  const DriverVehicleAddPage({super.key, this.api});

  final DriverApiService? api;

  @override
  State<DriverVehicleAddPage> createState() => _DriverVehicleAddPageState();
}

class _DriverVehicleAddPageState extends State<DriverVehicleAddPage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  final _plateController = TextEditingController();
  final _modelController = TextEditingController();
  final _colorController = TextEditingController();

  List<DriverApplicationVehicleType> _types = const [];
  int? _vehicleTypeId;
  final List<DriverApplicationUploadFile> _vehiclePhotos = [];
  DriverApplicationUploadFile? _insurance;
  DriverApplicationUploadFile? _registration;
  bool _loadingTypes = true;
  bool _submitting = false;
  String? _error;
  bool _showMissing = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _plateController.dispose();
    _modelController.dispose();
    _colorController.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.apiBaseUrl}/api/v1/vehicles/types'),
        headers: const {'Accept': 'application/json'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load vehicle types');
      }
      final decoded = jsonDecode(response.body);
      final map = Map<String, dynamic>.from(decoded as Map);
      final data = map['data'];
      final list = data is List
          ? data
          : (data is Map ? (data['items'] as List? ?? const []) : const []);
      final types = list
          .map(
            (item) => DriverApplicationVehicleType.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .where((item) => item.id > 0)
          .toList();
      if (!mounted) return;
      setState(() {
        _types = types;
        _vehicleTypeId = types.isNotEmpty ? types.first.id : null;
        _loadingTypes = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingTypes = false;
        _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_load_failed'),
        );
      });
    }
  }

  Future<DriverApplicationUploadFile?> _pickOne() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    return DriverApplicationUploadFile(name: file.name, bytes: bytes);
  }

  Future<void> _pickVehiclePhotos() async {
    final remaining = 6 - _vehiclePhotos.length;
    if (remaining <= 0) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final added = <DriverApplicationUploadFile>[];
    for (final file in result.files.take(remaining)) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      added.add(DriverApplicationUploadFile(name: file.name, bytes: bytes));
    }
    if (added.isEmpty) return;
    setState(() => _vehiclePhotos.addAll(added));
  }

  bool get _formReady =>
      _vehicleTypeId != null &&
      _plateController.text.trim().isNotEmpty &&
      _vehiclePhotos.length >= 3 &&
      _insurance != null &&
      _registration != null;

  Future<void> _submit() async {
    final l10n = context.l10n;
    setState(() {
      _showMissing = true;
      _error = null;
    });
    if (!_formReady || _submitting) return;
    setState(() => _submitting = true);
    try {
      final files = <({String field, String filename, List<int> bytes})>[
        for (final photo in _vehiclePhotos)
          (field: 'vehiclePhotos', filename: photo.name, bytes: photo.bytes),
        (
          field: 'insuranceCertificate',
          filename: _insurance!.name,
          bytes: _insurance!.bytes,
        ),
        (
          field: 'vehicleRegistration',
          filename: _registration!.name,
          bytes: _registration!.bytes,
        ),
      ];
      await _api.createVehicle(
        vehicleTypeId: _vehicleTypeId!,
        plateNumber: _plateController.text.trim(),
        modelName: _modelController.text.trim(),
        color: _colorController.text.trim(),
        files: files,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('driver_vehicle_add_success'))),
      );
      Navigator.of(context).pop(true);
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = userFacingError(
          err,
          fallback: l10n.t('driver_vehicle_add_failed'),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_vehicle_add_title'))),
      body: _loadingTypes
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(AppTokens.spaceMd),
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: const TextStyle(color: AppTokens.error),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                ],
                DropdownButtonFormField<int>(
                  value: _vehicleTypeId,
                  decoration: InputDecoration(
                    labelText: l10n.t('driver_vehicle_type_label'),
                  ),
                  items: _types
                      .map(
                        (type) => DropdownMenuItem(
                          value: type.id,
                          child: Text(type.name),
                        ),
                      )
                      .toList(),
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _vehicleTypeId = value),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _plateController,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: l10n.t('driver_vehicle_plate_label'),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _modelController,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: l10n.t('driver_account_vehicle_model'),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                TextField(
                  controller: _colorController,
                  enabled: !_submitting,
                  decoration: InputDecoration(
                    labelText: l10n.t('driver_account_vehicle_color'),
                  ),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                DriverRegistrationPhotoUploadCard(
                  fieldKey: 'vehiclePhotos',
                  title: l10n.t('driver_vehicle_photos_title'),
                  description: l10n.t('driver_vehicle_photos_hint'),
                  files: _vehiclePhotos,
                  isRequired: true,
                  showMissing: _showMissing &&
                      (_vehiclePhotos.length < 3 || _vehiclePhotos.length > 6),
                  processing: _submitting,
                  selectLabel: l10n.t('driver_apply_upload_add_photo'),
                  showSelectButton: _vehiclePhotos.length < 6,
                  onSelect: _submitting ? null : _pickVehiclePhotos,
                  onRemoveAll: _submitting
                      ? null
                      : () => setState(() => _vehiclePhotos.clear()),
                  onRemoveFile: _submitting
                      ? null
                      : (index) =>
                          setState(() => _vehiclePhotos.removeAt(index)),
                  missingText: l10n.t('driver_vehicle_photos_required'),
                  countText: l10n
                      .t('driver_apply_vehicle_photo_count')
                      .replaceAll('{count}', '${_vehiclePhotos.length}'),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                DriverRegistrationPhotoUploadCard(
                  fieldKey: 'insuranceCertificate',
                  title: l10n.t('driver_vehicle_insurance_title'),
                  description: l10n.t('driver_vehicle_doc_hint'),
                  files: _insurance == null ? const [] : [_insurance!],
                  isRequired: true,
                  showMissing: _showMissing && _insurance == null,
                  processing: _submitting,
                  selectLabel: l10n.t('driver_apply_upload_select'),
                  showSelectButton: true,
                  onSelect: _submitting
                      ? null
                      : () async {
                          final file = await _pickOne();
                          if (file != null) {
                            setState(() => _insurance = file);
                          }
                        },
                  onRemoveAll: _submitting
                      ? null
                      : () => setState(() => _insurance = null),
                  missingText: l10n.t('driver_vehicle_doc_required'),
                ),
                const SizedBox(height: AppTokens.spaceMd),
                DriverRegistrationPhotoUploadCard(
                  fieldKey: 'vehicleRegistration',
                  title: l10n.t('driver_vehicle_registration_title'),
                  description: l10n.t('driver_vehicle_doc_hint'),
                  files: _registration == null ? const [] : [_registration!],
                  isRequired: true,
                  showMissing: _showMissing && _registration == null,
                  processing: _submitting,
                  selectLabel: l10n.t('driver_apply_upload_select'),
                  showSelectButton: true,
                  onSelect: _submitting
                      ? null
                      : () async {
                          final file = await _pickOne();
                          if (file != null) {
                            setState(() => _registration = file);
                          }
                        },
                  onRemoveAll: _submitting
                      ? null
                      : () => setState(() => _registration = null),
                  missingText: l10n.t('driver_vehicle_doc_required'),
                ),
                const SizedBox(height: AppTokens.spaceLg),
                SizedBox(
                  height: 52,
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: (!_submitting && _formReady) ? _submit : null,
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.t('driver_vehicle_submit')),
                  ),
                ),
              ],
            ),
    );
  }
}
