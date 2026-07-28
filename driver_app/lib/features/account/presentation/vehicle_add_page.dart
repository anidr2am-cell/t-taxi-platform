import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/account_api.dart';
import '../data/account_models.dart';

typedef VehiclePhotoPicker =
    Future<List<AccountUploadFile>> Function(int remaining);
typedef VehicleDocumentPicker = Future<AccountUploadFile?> Function();

class VehicleAddPage extends StatefulWidget {
  const VehicleAddPage({
    super.key,
    required this.api,
    this.pickPhotos,
    this.pickDocument,
  });

  final AccountDataSource api;
  final VehiclePhotoPicker? pickPhotos;
  final VehicleDocumentPicker? pickDocument;

  @override
  State<VehicleAddPage> createState() => _VehicleAddPageState();
}

class _VehicleAddPageState extends State<VehicleAddPage> {
  final _plate = TextEditingController();
  final _model = TextEditingController();
  final _color = TextEditingController();
  List<VehicleTypeOption>? _types;
  int? _typeId;
  final List<AccountUploadFile> _photos = [];
  AccountUploadFile? _insurance;
  AccountUploadFile? _registration;
  bool _submitting = false;
  ApiException? _loadError;

  bool get _ready =>
      _typeId != null &&
      _plate.text.trim().length >= 2 &&
      _plate.text.trim().length <= 20 &&
      _model.text.trim().length <= 100 &&
      _color.text.trim().length <= 30 &&
      _photos.length >= 3 &&
      _photos.length <= 6 &&
      _insurance != null &&
      _registration != null;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _plate.dispose();
    _model.dispose();
    _color.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final values = await widget.api.getVehicleTypes();
      if (!mounted) return;
      setState(() {
        _types = values;
        _typeId = values.isEmpty ? null : values.first.id;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _types = const [];
          _loadError = error;
        });
      }
    }
  }

  Future<List<AccountUploadFile>> _pickPhotos(int remaining) async {
    if (widget.pickPhotos != null) return widget.pickPhotos!(remaining);
    final files = await ImagePicker().pickMultiImage();
    final selected = <AccountUploadFile>[];
    for (final file in files.take(remaining)) {
      selected.add(
        AccountUploadFile(filename: file.name, bytes: await file.readAsBytes()),
      );
    }
    return selected;
  }

  Future<AccountUploadFile?> _pickDocument() async {
    if (widget.pickDocument != null) return widget.pickDocument!();
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file?.bytes == null || file!.bytes!.isEmpty) return null;
    return AccountUploadFile(filename: file.name, bytes: file.bytes!);
  }

  Future<void> _addPhotos() async {
    final remaining = 6 - _photos.length;
    if (remaining <= 0) return;
    final selected = await _pickPhotos(remaining);
    if (!mounted) return;
    setState(() => _photos.addAll(selected.take(remaining)));
  }

  Future<void> _submit() async {
    if (!_ready || _submitting) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _submitting = true);
    try {
      await widget.api.createVehicle(
        VehicleCreateRequest(
          vehicleTypeId: _typeId!,
          plateNumber: _plate.text.trim(),
          modelName: _model.text.trim(),
          color: _color.text.trim(),
          vehiclePhotos: List.unmodifiable(_photos),
          insuranceCertificate: _insurance!,
          vehicleRegistration: _registration!,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.vehicleRegisteredPendingApproval)),
      );
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      final message = error.kind == ApiFailureKind.vehiclePlateAlreadyRegistered
          ? l10n.plateAlreadyRegistered
          : error.localizedMessage(l10n);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.addVehicleTitle)),
      body: _types == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text(_loadError!.localizedMessage(l10n)))
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<int>(
                    key: const Key('vehicleType'),
                    initialValue: _typeId,
                    decoration: InputDecoration(labelText: l10n.vehicleType),
                    items: _types!
                        .map(
                          (type) => DropdownMenuItem(
                            value: type.id,
                            child: Text(
                              type.name.isEmpty ? type.code : type.name,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _typeId = value),
                  ),
                  TextField(
                    key: const Key('vehiclePlate'),
                    controller: _plate,
                    enabled: !_submitting,
                    maxLength: 20,
                    decoration: InputDecoration(
                      labelText: l10n.vehiclePlateNumber,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _model,
                    enabled: !_submitting,
                    maxLength: 100,
                    decoration: InputDecoration(labelText: l10n.modelNameOptional),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _color,
                    enabled: !_submitting,
                    maxLength: 30,
                    decoration: InputDecoration(labelText: l10n.colorOptional),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.vehiclePhotosProgress(_photos.length)),
                  OutlinedButton(
                    key: const Key('pickVehiclePhotos'),
                    onPressed: _submitting || _photos.length >= 6
                        ? null
                        : _addPhotos,
                    child: Text(l10n.selectVehiclePhotos),
                  ),
                  if (_photos.isNotEmpty)
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _photos.clear()),
                      child: Text(l10n.clearAllVehiclePhotos),
                    ),
                  const SizedBox(height: 12),
                  _DocumentSelector(
                    key: const Key('insuranceSelector'),
                    label: l10n.insuranceCertificate,
                    file: _insurance,
                    requiredHint: l10n.requiredFileNotSelected,
                    selectLabel: l10n.select,
                    onPick: _submitting
                        ? null
                        : () async {
                            final file = await _pickDocument();
                            if (file != null && mounted) {
                              setState(() => _insurance = file);
                            }
                          },
                  ),
                  _DocumentSelector(
                    key: const Key('registrationSelector'),
                    label: l10n.vehicleRegistrationDoc,
                    file: _registration,
                    requiredHint: l10n.requiredFileNotSelected,
                    selectLabel: l10n.select,
                    onPick: _submitting
                        ? null
                        : () async {
                            final file = await _pickDocument();
                            if (file != null && mounted) {
                              setState(() => _registration = file);
                            }
                          },
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('submitVehicle'),
                    onPressed: !_submitting && _ready ? _submit : null,
                    child: _submitting
                        ? const CircularProgressIndicator()
                        : Text(l10n.submitRegistration),
                  ),
                ],
              ),
            ),
    );
  }
}

class _DocumentSelector extends StatelessWidget {
  const _DocumentSelector({
    super.key,
    required this.label,
    required this.file,
    required this.requiredHint,
    required this.selectLabel,
    required this.onPick,
  });

  final String label;
  final AccountUploadFile? file;
  final String requiredHint;
  final String selectLabel;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(file?.filename ?? requiredHint),
      trailing: OutlinedButton(onPressed: onPick, child: Text(selectLabel)),
    );
  }
}
