import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
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
  String? _loadError;

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
          _loadError = error.userMessage;
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('차량이 등록되었습니다. 승인 대기 중입니다.')));
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      final message = error.kind == ApiFailureKind.vehiclePlateAlreadyRegistered
          ? '이미 등록된 차량 번호입니다.'
          : error.kind == ApiFailureKind.server
          ? '일시적인 오류가 발생했습니다. 다시 시도해 주세요.'
          : error.userMessage;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('차량 추가')),
      body: _types == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(child: Text(_loadError!))
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  DropdownButtonFormField<int>(
                    key: const Key('vehicleType'),
                    initialValue: _typeId,
                    decoration: const InputDecoration(labelText: '차종'),
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
                    decoration: const InputDecoration(labelText: '차량 번호'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _model,
                    enabled: !_submitting,
                    maxLength: 100,
                    decoration: const InputDecoration(labelText: '모델명 (선택)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  TextField(
                    controller: _color,
                    enabled: !_submitting,
                    maxLength: 30,
                    decoration: const InputDecoration(labelText: '색상 (선택)'),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  Text('차량 사진 (${_photos.length}/3~6)'),
                  OutlinedButton(
                    key: const Key('pickVehiclePhotos'),
                    onPressed: _submitting || _photos.length >= 6
                        ? null
                        : _addPhotos,
                    child: const Text('차량 사진 선택'),
                  ),
                  if (_photos.isNotEmpty)
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _photos.clear()),
                      child: const Text('차량 사진 전체 삭제'),
                    ),
                  const SizedBox(height: 12),
                  _DocumentSelector(
                    key: const Key('insuranceSelector'),
                    label: '보험증서',
                    file: _insurance,
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
                    label: '차량등록증',
                    file: _registration,
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
                        : const Text('등록 신청'),
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
    required this.onPick,
  });

  final String label;
  final AccountUploadFile? file;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: Text(file?.filename ?? '필수 파일을 선택해 주세요.'),
      trailing: OutlinedButton(onPressed: onPick, child: const Text('선택')),
    );
  }
}
