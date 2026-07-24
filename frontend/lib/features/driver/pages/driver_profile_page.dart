import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../../notification/services/notification_device_registration_service.dart';
import '../driver_auth.dart';
import '../services/driver_api_service.dart';
import '../widgets/driver_status_control.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({
    super.key,
    this.api,
    this.deviceRegistrationService,
    this.onStatusChanged,
  });

  final DriverApiService? api;
  final NotificationDeviceRegistrationService? deviceRegistrationService;
  final VoidCallback? onStatusChanged;

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  late final DriverApiService _api = widget.api ?? DriverApiService();
  late final NotificationDeviceRegistrationService _deviceRegistration =
      widget.deviceRegistrationService ??
      NotificationDeviceRegistrationService();
  Future<Map<String, dynamic>>? _ratingFuture;
  Future<Map<String, dynamic>>? _profileFuture;
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _modelController = TextEditingController();
  final _plateController = TextEditingController();
  final _colorController = TextEditingController();
  final _yearController = TextEditingController();
  String? _vehicleTypeCode;
  String? _email;
  String? _avatarUrl;
  String? _vehiclePhotoUrl;
  bool _saving = false;
  bool _uploadingAvatar = false;
  bool _uploadingVehiclePhoto = false;

  static const _vehicleTypeOptions = [
    'SEDAN',
    'SUV',
    'VIP_SUV',
    'VAN',
    'VIP_VAN',
    'LUXURY',
  ];

  @override
  void initState() {
    super.initState();
    _ratingFuture = _api.getRatingSummary();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _modelController.dispose();
    _plateController.dispose();
    _colorController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  void _loadProfile() {
    setState(() {
      _profileFuture = _api.getProfile().then((profile) {
        _applyProfile(profile);
        return profile;
      });
    });
  }

  void _applyProfile(Map<String, dynamic> profile) {
    _nameController.text = profile['name'] as String? ?? '';
    _phoneController.text = profile['phone'] as String? ?? '';
    _email = profile['email'] as String?;
    _avatarUrl = _api.resolveProfileAssetUrl(profile['avatarUrl'] as String?);
    final vehicle = profile['vehicle'] is Map
        ? Map<String, dynamic>.from(profile['vehicle'] as Map)
        : null;
    _vehicleTypeCode = vehicle?['typeCode'] as String?;
    _modelController.text = vehicle?['modelName'] as String? ?? '';
    _plateController.text = vehicle?['plateNumber'] as String? ?? '';
    _colorController.text = vehicle?['color'] as String? ?? '';
    final year = vehicle?['year'];
    _yearController.text = year == null ? '' : '$year';
    _vehiclePhotoUrl = _api.resolveProfileAssetUrl(
      vehicle?['photoUrl'] as String?,
    );
  }

  Future<void> _saveProfile() async {
    if (_saving) return;
    setState(() => _saving = true);
    final l10n = context.l10n;
    try {
      final body = <String, dynamic>{
        'name': _nameController.text.trim(),
        'phone': _phoneController.text.trim(),
      };
      if (_vehicleTypeCode != null && _vehicleTypeCode!.isNotEmpty) {
        body['vehicleTypeCode'] = _vehicleTypeCode;
      }
      if (_modelController.text.trim().isNotEmpty) {
        body['vehicleModelName'] = _modelController.text.trim();
      }
      if (_plateController.text.trim().isNotEmpty) {
        body['vehiclePlateNumber'] = _plateController.text.trim();
      }
      if (_colorController.text.trim().isNotEmpty) {
        body['vehicleColor'] = _colorController.text.trim();
      }
      if (_yearController.text.trim().isNotEmpty) {
        body['vehicleYear'] = int.tryParse(_yearController.text.trim());
      }
      final profile = await _api.updateProfile(body);
      if (!mounted) return;
      _applyProfile(profile);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.t('driver_profile_save_success'))),
      );
      widget.onStatusChanged?.call();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            err is DriverApiException
                ? driverApiErrorMessage(
                    message: err.message,
                    errorCode: err.errorCode,
                    languageCode: Localizations.localeOf(context).languageCode,
                  )
                : l10n.t('driver_profile_save_failed'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingAvatar = true);
    try {
      await _api.uploadProfileAvatar(
        file.bytes!,
        file.name.isNotEmpty ? file.name : 'avatar.jpg',
      );
      if (!mounted) return;
      _loadProfile();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(
              err,
              fallback: context.l10n.t('driver_profile_save_failed'),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _pickAndUploadVehiclePhoto() async {
    if (_uploadingVehiclePhoto) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    setState(() => _uploadingVehiclePhoto = true);
    try {
      await _api.uploadVehiclePhoto(
        file.bytes!,
        file.name.isNotEmpty ? file.name : 'vehicle.jpg',
      );
      if (!mounted) return;
      _loadProfile();
    } catch (err) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingError(
              err,
              fallback: context.l10n.t('driver_profile_save_failed'),
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploadingVehiclePhoto = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _deviceRegistration.deactivateAuthenticated(
        accessTokenLoader: _api.getSavedToken,
      );
    } catch (_) {}
    await _api.logout();
    if (!mounted) return;
    driverRedirectToLogin(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_profile_edit_title'))),
      body: ListView(
        padding: AppUi.pagePadding(context),
        children: [
          FutureBuilder<Map<String, dynamic>>(
            future: _ratingFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return AppUi.loadingState();
              }
              if (snapshot.hasError) {
                return AppUi.surfaceCard(
                  child: Text(l10n.t('driver_rating_error')),
                );
              }
              final rating = snapshot.data ?? {};
              final avg = rating['averageRating'];
              final count = rating['reviewCount'] ?? 0;
              return AppUi.surfaceCard(
                child: Row(
                  children: [
                    const Icon(Icons.star, color: AppTokens.warning),
                    const SizedBox(width: AppTokens.spaceSm),
                    Expanded(
                      child: Text(
                        avg == null
                            ? l10n.t('driver_no_ratings')
                            : '$avg · $count ${l10n.t('driver_rating_count')}',
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: AppTokens.spaceMd),
          FutureBuilder<Map<String, dynamic>>(
            future: _profileFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return AppUi.loadingState();
              }
              if (snapshot.hasError) {
                return AppUi.errorState(
                  message: userFacingError(
                    snapshot.error!,
                    fallback: l10n.t('driver_load_failed'),
                  ),
                  onRetry: _loadProfile,
                  retryLabel: l10n.t('driver_retry'),
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppUi.surfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: CircleAvatar(
                            radius: 44,
                            backgroundColor: AppTokens.primaryLight,
                            backgroundImage:
                                _avatarUrl != null && _avatarUrl!.isNotEmpty
                                ? NetworkImage(_avatarUrl!)
                                : null,
                            child: _avatarUrl == null || _avatarUrl!.isEmpty
                                ? const Icon(Icons.person, size: 40)
                                : null,
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _uploadingAvatar
                                ? null
                                : _pickAndUploadAvatar,
                            icon: _uploadingAvatar
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.photo_camera_outlined),
                            label: Text(l10n.t('driver_profile_upload_avatar')),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceMd),
                        TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: l10n.t('name'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        TextField(
                          controller: _phoneController,
                          decoration: InputDecoration(
                            labelText: l10n.t('phone'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        TextField(
                          enabled: false,
                          controller: TextEditingController(text: _email ?? ''),
                          decoration: InputDecoration(
                            labelText: l10n.t('driver_profile_readonly_email'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  AppUi.surfaceCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.t('driver_account_vehicle_title'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        DropdownButtonFormField<String>(
                          value:
                              _vehicleTypeCode != null &&
                                  _vehicleTypeOptions.contains(_vehicleTypeCode)
                              ? _vehicleTypeCode
                              : null,
                          decoration: InputDecoration(
                            labelText: l10n.t('airport_meeting_vehicle_type'),
                            border: const OutlineInputBorder(),
                          ),
                          items: _vehicleTypeOptions
                              .map(
                                (code) => DropdownMenuItem(
                                  value: code,
                                  child: Text(code),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setState(() => _vehicleTypeCode = value),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        TextField(
                          controller: _modelController,
                          decoration: InputDecoration(
                            labelText: l10n.t('driver_account_vehicle_model'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        TextField(
                          controller: _plateController,
                          decoration: InputDecoration(
                            labelText: l10n.t('airport_meeting_vehicle_plate'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        TextField(
                          controller: _colorController,
                          decoration: InputDecoration(
                            labelText: l10n.t('driver_account_vehicle_color'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        TextField(
                          controller: _yearController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: l10n.t('driver_account_vehicle_year'),
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: AppTokens.spaceSm),
                        if (_vehiclePhotoUrl != null &&
                            _vehiclePhotoUrl!.isNotEmpty)
                          ClipRRect(
                            borderRadius: AppTokens.borderRadiusSm,
                            child: Image.network(
                              _vehiclePhotoUrl!,
                              height: 160,
                              width: double.infinity,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                height: 120,
                                color: AppTokens.surfaceMuted,
                                alignment: Alignment.center,
                                child: const Icon(
                                  Icons.directions_car_outlined,
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: AppTokens.spaceSm),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _uploadingVehiclePhoto
                                ? null
                                : _pickAndUploadVehiclePhoto,
                            icon: _uploadingVehiclePhoto
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.directions_car_outlined),
                            label: Text(
                              l10n.t('driver_profile_upload_vehicle_photo'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  SizedBox(
                    height: 52,
                    child: FilledButton(
                      onPressed: _saving ? null : _saveProfile,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(l10n.t('driver_profile_save')),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: AppTokens.spaceMd),
          DriverStatusControl(
            api: _api,
            onStatusChanged: widget.onStatusChanged,
            padding: EdgeInsets.zero,
          ),
          const SizedBox(height: AppTokens.spaceLg),
          SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout),
              label: Text(l10n.t('driver_logout')),
            ),
          ),
        ],
      ),
    );
  }
}
