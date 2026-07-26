import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_exception.dart';
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

  String? _validate() {
    final name = _name.text.trim();
    final phone = _phone.text.trim();
    if (name.isEmpty || name.length > 100) return '이름은 1~100자로 입력해 주세요.';
    if (phone.length < 8 || phone.length > 20) {
      return '전화번호는 8~20자로 입력해 주세요.';
    }
    if (_model.text.trim().length > 100) return '차량 모델은 100자 이내로 입력해 주세요.';
    if (_color.text.trim().length > 30) return '차량 색상은 30자 이내로 입력해 주세요.';
    final originalPlate = widget.initialProfile.vehicle?.plateNumber ?? '';
    if ((_plate.text != originalPlate || _vehicleType != null) &&
        _plate.text.trim().isEmpty) {
      return '차량 번호를 입력해 주세요.';
    }
    if (_plate.text.trim().length > 20) return '차량 번호는 20자 이내로 입력해 주세요.';
    if (_year.text.trim().isNotEmpty) {
      final value = int.tryParse(_year.text.trim());
      if (value == null || value < 1990 || value > DateTime.now().year + 1) {
        return '연식은 1990년부터 ${DateTime.now().year + 1}년 사이로 입력해 주세요.';
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
    final error = _validate();
    if (error != null) {
      _message(error);
      return;
    }
    final changes = _changes();
    if (changes.isEmpty) {
      _message('변경된 내용이 없습니다.');
      return;
    }
    setState(() => _saving = true);
    try {
      _profile = await widget.api.updateProfile(changes);
      if (!mounted) return;
      _message('프로필이 저장되었습니다.');
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) _message(error.userMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upload({required bool avatar}) async {
    if (_uploading) return;
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
      setState(() {});
      _message(avatar ? '프로필 사진이 변경되었습니다.' : '차량 사진이 변경되었습니다.');
    } on ApiException catch (error) {
      if (!mounted) return;
      final message =
          !avatar &&
              error.statusCode == 409 &&
              error.errorCode == 'VALIDATION_ERROR'
          ? '승인된 기사 지원서가 없어 차량 사진을 변경할 수 없습니다.'
          : error.userMessage;
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
        ? Image.network(
            widget.api.resolveAssetUrl(path),
            key: Key(avatar ? 'avatarImage' : 'vehiclePhotoImage'),
            height: avatar ? 100 : 150,
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
          )
        : Icon(avatar ? Icons.person : Icons.directions_car_outlined, size: 54);
    return SizedBox(
      height: avatar ? 100 : 150,
      child: Center(child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = _profile.vehicle;
    return Scaffold(
      appBar: AppBar(title: const Text('프로필 수정')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _networkImage(_profile.avatarUrl, avatar: true),
          OutlinedButton(
            key: const Key('replaceAvatar'),
            onPressed: _uploading ? null : () => _upload(avatar: true),
            child: const Text('프로필 사진 교체'),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('profileName'),
            controller: _name,
            decoration: const InputDecoration(labelText: '이름'),
          ),
          TextField(
            key: const Key('profilePhone'),
            controller: _phone,
            decoration: const InputDecoration(labelText: '전화번호'),
            keyboardType: TextInputType.phone,
          ),
          TextFormField(
            initialValue: _profile.email,
            enabled: false,
            decoration: const InputDecoration(labelText: '이메일 (읽기 전용)'),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            key: const Key('profileVehicleType'),
            initialValue: _vehicleTypes.contains(_vehicleType)
                ? _vehicleType
                : null,
            decoration: const InputDecoration(labelText: '차종'),
            items: _vehicleTypes
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() => _vehicleType = value),
          ),
          TextField(
            controller: _model,
            decoration: const InputDecoration(labelText: '모델'),
          ),
          TextField(
            controller: _plate,
            decoration: const InputDecoration(labelText: '차량 번호'),
          ),
          TextField(
            controller: _color,
            decoration: const InputDecoration(labelText: '색상'),
          ),
          TextField(
            controller: _year,
            decoration: const InputDecoration(labelText: '연식'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 16),
          _networkImage(vehicle?.photoUrl, avatar: false),
          if (vehicle?.photoUrl == null)
            const Text(
              '등록된 차량 사진이 없거나 아직 승인되지 않았습니다.',
              key: Key('vehiclePhotoUnavailableNotice'),
              textAlign: TextAlign.center,
            ),
          OutlinedButton(
            key: const Key('replaceVehiclePhoto'),
            onPressed: _uploading ? null : () => _upload(avatar: false),
            child: const Text('차량 사진 교체'),
          ),
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('saveProfile'),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CircularProgressIndicator()
                : const Text('저장'),
          ),
        ],
      ),
    );
  }
}
