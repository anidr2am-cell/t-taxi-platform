import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/account_api.dart';
import '../data/account_models.dart';

typedef AccountImagePicker = Future<AccountUploadFile?> Function();

class ProfileEditPage extends StatefulWidget {
  const ProfileEditPage({
    super.key,
    required this.api,
    required this.initialProfile,
    this.pickImage,
  });

  final AccountDataSource api;
  final DriverProfile initialProfile;
  final AccountImagePicker? pickImage;

  @override
  State<ProfileEditPage> createState() => _ProfileEditPageState();
}

class _ProfileEditPageState extends State<ProfileEditPage> {
  static const _vehicleTypes = [
    'SEDAN',
    'SUV',
    'VIP_SUV',
    'VAN',
    'VIP_VAN',
    'LUXURY',
  ];

  late final _name = TextEditingController(text: widget.initialProfile.name);
  late final _phone = TextEditingController(text: widget.initialProfile.phone);
  late final _model = TextEditingController(
    text: widget.initialProfile.vehicle?.modelName ?? '',
  );
  late final _plate = TextEditingController(
    text: widget.initialProfile.vehicle?.plateNumber ?? '',
  );
  late final _color = TextEditingController(
    text: widget.initialProfile.vehicle?.color ?? '',
  );
  late final _year = TextEditingController(
    text: widget.initialProfile.vehicle?.year?.toString() ?? '',
  );
  late String? _vehicleType = widget.initialProfile.vehicle?.typeCode;
  late DriverProfile _profile = widget.initialProfile;
  bool _saving = false;
  bool _uploading = false;
  final Map<String, Future<List<int>>> _imageLoads = {};

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _model.dispose();
    _plate.dispose();
    _color.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<AccountUploadFile?> _pick() async {
    if (widget.pickImage != null) return widget.pickImage!();
    final file = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (file == null) return null;
    return AccountUploadFile(
      filename: file.name,
      bytes: await file.readAsBytes(),
    );
  }

  String? _validate(AppLocalizations l10n) {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || name.length > 100) return l10n.nameLengthValidation;
    if (phone.length < 8 || phone.length > 20) {
      return l10n.phoneLengthValidation;
    }
    if (_model.text.trim().length > 100) return l10n.modelLengthValidation;
    if (_color.text.trim().length > 30) return l10n.colorLengthValidation;
    final originalPlate = widget.initialProfile.vehicle?.plateNumber ?? '';
    if ((_plate.text != originalPlate || _vehicleType != null) &&
        _plate.text.trim().isEmpty) {
      return l10n.plateRequiredValidation;
    }
    if (_plate.text.trim().length > 20) return l10n.plateLengthValidation;
    if (_year.text.trim().isNotEmpty) {
      final value = int.tryParse(_year.text.trim());
      final maxYear = DateTime.now().year + 1;
      if (value == null || value < 1990 || value > maxYear) {
        return l10n.yearRangeValidation(1990, maxYear);
      }
    }
    return null;
  }

  Map<String, dynamic> _changes() {
    final original = widget.initialProfile;
    final vehicle = original.vehicle;
    final changes = <String, dynamic>{};
    void changed(String key, Object? value, Object? previous) {
      if (value != previous) changes[key] = value;
    }

    changed('name', _name.text.trim(), original.name);
    changed('phone', _phone.text.trim(), original.phone);
    changed('vehicleTypeCode', _vehicleType, vehicle?.typeCode);
    changed('vehicleModelName', _model.text.trim(), vehicle?.modelName ?? '');
    changed(
      'vehiclePlateNumber',
      _plate.text.trim(),
      vehicle?.plateNumber ?? '',
    );
    changed('vehicleColor', _color.text.trim(), vehicle?.color ?? '');
    final year = _year.text.trim().isEmpty
        ? null
        : int.parse(_year.text.trim());
    changed('vehicleYear', year, vehicle?.year);
    changes.removeWhere((_, value) => value == null);
    return changes;
  }

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context);
    final error = _validate(l10n);
    if (error != null) {
      _message(error);
      return;
    }
    final changes = _changes();
    if (changes.isEmpty) {
      _message(l10n.noChangesToSave);
      return;
    }
    setState(() => _saving = true);
    try {
      _profile = await widget.api.updateProfile(changes);
      if (!mounted) return;
      _message(l10n.profileSaved);
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _message(error.localizedMessage(l10n));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upload({required bool avatar}) async {
    if (_uploading) return;
    final l10n = AppLocalizations.of(context);
    final file = await _pick();
    if (file == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      if (avatar) {
        await widget.api.uploadAvatar(file);
      } else {
        await widget.api.uploadVehiclePhoto(file);
      }
      _profile = await widget.api.getProfile();
      if (!mounted) return;
      setState(_imageLoads.clear);
      _message(
        avatar ? l10n.profilePhotoChanged : l10n.vehiclePhotoChanged,
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      final message =
          !avatar &&
              error.statusCode == 409 &&
              error.errorCode == 'VALIDATION_ERROR'
          ? l10n.noApprovedApplicationForVehiclePhoto
          : error.localizedMessage(l10n);
      _message(message);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _networkImage(String? path, {required bool avatar}) {
    final hasImage = path != null && path.isNotEmpty;
    final child = hasImage
        ? FutureBuilder<List<int>>(
            key: Key(avatar ? 'avatarImage' : 'vehiclePhotoImage'),
            future: _imageLoads.putIfAbsent(
              path,
              () => widget.api.loadAsset(path),
            ),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Icon(Icons.broken_image_outlined);
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return const CircularProgressIndicator();
              }
              return Image.memory(
                Uint8List.fromList(bytes),
                height: avatar ? 100 : 150,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              );
            },
          )
        : Icon(avatar ? Icons.person : Icons.directions_car_outlined, size: 54);
    return SizedBox(
      height: avatar ? 100 : 150,
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final vehicle = _profile.vehicle;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.profileEditTitle)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _networkImage(_profile.avatarUrl, avatar: true),
            OutlinedButton(
              key: const Key('replaceAvatar'),
              onPressed: _uploading ? null : () => _upload(avatar: true),
              child: Text(l10n.replaceProfilePhoto),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('profileName'),
              controller: _name,
              decoration: InputDecoration(labelText: l10n.name),
            ),
            TextField(
              key: const Key('profilePhone'),
              controller: _phone,
              decoration: InputDecoration(labelText: l10n.phone),
              keyboardType: TextInputType.phone,
            ),
            TextFormField(
              initialValue: _profile.email,
              enabled: false,
              decoration: InputDecoration(labelText: l10n.emailReadOnly),
            ),
            const SizedBox(height: 20),
            DropdownButtonFormField<String>(
              key: const Key('profileVehicleType'),
              initialValue: _vehicleTypes.contains(_vehicleType)
                  ? _vehicleType
                  : null,
              decoration: InputDecoration(labelText: l10n.vehicleType),
              items: _vehicleTypes
                  .map(
                    (value) =>
                        DropdownMenuItem(value: value, child: Text(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _vehicleType = value),
            ),
            TextField(
              controller: _model,
              decoration: InputDecoration(labelText: l10n.model),
            ),
            TextField(
              controller: _plate,
              decoration: InputDecoration(labelText: l10n.vehiclePlateNumber),
            ),
            TextField(
              controller: _color,
              decoration: InputDecoration(labelText: l10n.color),
            ),
            TextField(
              controller: _year,
              decoration: InputDecoration(labelText: l10n.year),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            _networkImage(vehicle?.photoUrl, avatar: false),
            if (vehicle?.photoUrl == null)
              Text(
                l10n.vehiclePhotoUnavailable,
                key: const Key('vehiclePhotoUnavailableNotice'),
                textAlign: TextAlign.center,
              ),
            OutlinedButton(
              key: const Key('replaceVehiclePhoto'),
              onPressed: _uploading ? null : () => _upload(avatar: false),
              child: Text(l10n.replaceVehiclePhoto),
            ),
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('saveProfile'),
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const CircularProgressIndicator()
                  : Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }
}
