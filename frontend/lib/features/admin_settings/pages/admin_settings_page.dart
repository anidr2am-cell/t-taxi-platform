import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../widgets/app_ui.dart';
import '../../platform_settings/services/platform_settings_api_service.dart';

class AdminSettingsPage extends StatefulWidget {
  const AdminSettingsPage({
    super.key,
    this.api = const PlatformSettingsApiService(),
    this.pickImageFile,
  });
  final PlatformSettingsApiService api;
  final Future<PlatformFile?> Function()? pickImageFile;

  @override
  State<AdminSettingsPage> createState() => _AdminSettingsPageState();
}

class _AdminSettingsPageState extends State<AdminSettingsPage> {
  final _controllers = <String, TextEditingController>{
    for (final key in [
      'lineQrDescription',
      'bankName',
      'accountName',
      'accountNumber',
      'promptPayNumber',
    ])
      key: TextEditingController(),
  };
  final _guestLookupBannerMessageController = TextEditingController();
  final _contactKakaoUrlController = TextEditingController();
  final _contactLineUrlController = TextEditingController();

  Map<String, dynamic>? _settings;
  Map<String, dynamic>? _contactChannels;
  bool _guestLookupBannerEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _savingContactChannels = false;
  String? _error;
  final _localImagePreviews = <String, Uint8List>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final value in _controllers.values) {
      value.dispose();
    }
    _guestLookupBannerMessageController.dispose();
    _contactKakaoUrlController.dispose();
    _contactLineUrlController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.api.getAdmin(),
        widget.api.getContactChannelsAdmin(),
      ]);
      final data = results[0];
      final contactChannels = results[1];
      for (final entry in _controllers.entries) {
        entry.value.text = data[entry.key] as String? ?? '';
      }
      if (mounted) {
        setState(() {
          _settings = data;
          _applyContactChannels(contactChannels);
          _loading = false;
          _error = null;
          _localImagePreviews.clear();
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$err';
        });
      }
    }
  }

  void _applyContactChannels(Map<String, dynamic> contactChannels) {
    _contactChannels = Map<String, dynamic>.from(contactChannels);
    _guestLookupBannerEnabled =
        contactChannels['guestLookupInquiryBannerEnabled'] == true;
    _guestLookupBannerMessageController.text =
        contactChannels['guestLookupInquiryBannerMessage'] as String? ?? '';
    _contactKakaoUrlController.text =
        contactChannels['contactKakaoAddUrl'] as String? ?? '';
    _contactLineUrlController.text =
        contactChannels['contactLineAddUrl'] as String? ?? '';
  }

  Map<String, dynamic> _contactChannelsPayload() {
    final current = Map<String, dynamic>.from(_contactChannels ?? {});
    return {
      ...current,
      'guestLookupInquiryBannerEnabled': _guestLookupBannerEnabled,
      'guestLookupInquiryBannerMessage': _guestLookupBannerMessageController
          .text
          .trim(),
      'contactKakaoAddUrl': _contactKakaoUrlController.text.trim(),
      'contactLineAddUrl': _contactLineUrlController.text.trim(),
    };
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final data = await widget.api.update({
        for (final entry in _controllers.entries) entry.key: entry.value.text,
      });
      if (mounted) {
        setState(() => _settings = data);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('admin_settings_saved'))),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$err')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveContactChannels() async {
    setState(() => _savingContactChannels = true);
    try {
      final data = await widget.api.updateContactChannels(
        _contactChannelsPayload(),
      );
      if (mounted) {
        setState(() => _applyContactChannels(data));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('admin_settings_saved'))),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$err')));
      }
    } finally {
      if (mounted) setState(() => _savingContactChannels = false);
    }
  }

  Future<void> _upload(String kind) async {
    final file = await _pickImageFile();
    final Uint8List? bytes = file?.bytes;
    if (file == null || bytes == null) return;
    final imageKey = _imageKeyForKind(kind);
    setState(() {
      _saving = true;
      if (imageKey != null) {
        _localImagePreviews[imageKey] = bytes;
      }
    });
    try {
      final data = await widget.api.uploadImage(kind, bytes, file.name);
      if (mounted) {
        setState(() {
          _settings = data;
          if (imageKey != null) _localImagePreviews.remove(imageKey);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.t('admin_settings_saved'))),
        );
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          if (imageKey != null) _localImagePreviews.remove(imageKey);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_uploadErrorMessage(err))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _uploadErrorMessage(Object error) {
    final l10n = context.l10n;
    if (error is PlatformSettingsApiException) {
      if (error.errorCode == 'FILE_TOO_LARGE') {
        return l10n.t('admin_settings_image_too_large');
      }
      if (error.errorCode == 'INVALID_SETTINGS_IMAGE' ||
          error.errorCode == 'INVALID_FILE_TYPE') {
        return l10n.t('admin_settings_image_invalid');
      }
    }
    return l10n.t('admin_settings_image_upload_failed');
  }

  Future<PlatformFile?> _pickImageFile() async {
    if (widget.pickImageFile != null) return widget.pickImageFile!();
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    return picked?.files.single;
  }

  String? _imageKeyForKind(String kind) => switch (kind) {
    'lineQr' => 'lineQrImageUrl',
    'promptPayQr' => 'promptPayQrImageUrl',
    _ => null,
  };

  @override
  Widget build(BuildContext context) {
    if (_loading) return AppUi.loadingState();
    if (_error != null) {
      return AppUi.errorState(message: _error!, onRetry: _load);
    }
    final l10n = context.l10n;
    return ListView(
      padding: AppUi.pagePadding(context),
      children: [
        AppUi.adminDetailSection(
          context: context,
          title: l10n.t('admin_settings_line_qr'),
          child: Column(
            children: [
              _field('lineQrDescription', l10n.t('admin_settings_description')),
              _image('lineQrImageUrl'),
              KeyedSubtree(
                key: const ValueKey('admin_settings_upload_line_qr'),
                child: AppUi.secondaryButton(
                  label: l10n.t('admin_settings_upload_line_qr'),
                  icon: Icons.qr_code,
                  onPressed: _saving ? null : () => _upload('lineQr'),
                  fullWidth: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppUi.adminDetailSection(
          context: context,
          title: l10n.t('admin_settings_bank'),
          child: Column(
            children: [
              _field('bankName', l10n.t('admin_settings_bank_name')),
              _field('accountName', l10n.t('admin_settings_account_name')),
              _field('accountNumber', l10n.t('admin_settings_account_number')),
              _field('promptPayNumber', 'PromptPay'),
              _image('promptPayQrImageUrl'),
              KeyedSubtree(
                key: const ValueKey('admin_settings_upload_promptpay_qr'),
                child: AppUi.secondaryButton(
                  label: l10n.t('admin_settings_upload_promptpay'),
                  icon: Icons.qr_code_2,
                  onPressed: _saving ? null : () => _upload('promptPayQr'),
                  fullWidth: true,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppUi.adminDetailSection(
          context: context,
          title: l10n.t('admin_settings_guest_lookup_inquiry'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              KeyedSubtree(
                key: const ValueKey('admin_settings_guest_lookup_banner_toggle'),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    l10n.t('admin_settings_guest_lookup_banner_enabled'),
                  ),
                  value: _guestLookupBannerEnabled,
                  onChanged: _savingContactChannels
                      ? null
                      : (value) =>
                            setState(() => _guestLookupBannerEnabled = value),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey(
                  'admin_settings_guest_lookup_banner_message',
                ),
                controller: _guestLookupBannerMessageController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.t(
                    'admin_settings_guest_lookup_banner_message',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('admin_settings_guest_lookup_kakao_url'),
                controller: _contactKakaoUrlController,
                decoration: InputDecoration(
                  labelText: l10n.t('admin_settings_guest_lookup_kakao_url'),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('admin_settings_guest_lookup_line_url'),
                controller: _contactLineUrlController,
                decoration: InputDecoration(
                  labelText: l10n.t('admin_settings_guest_lookup_line_url'),
                ),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: const ValueKey('admin_settings_guest_lookup_save'),
                child: AppUi.primaryButton(
                  label: l10n.t('admin_settings_guest_lookup_save'),
                  loading: _savingContactChannels,
                  onPressed: _savingContactChannels ? null : _saveContactChannels,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppUi.primaryButton(
          label: l10n.t('admin_settings_save'),
          loading: _saving,
          onPressed: _saving ? null : _save,
        ),
      ],
    );
  }

  Widget _field(String key, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: _controllers[key],
      decoration: InputDecoration(labelText: label),
    ),
  );

  Widget _image(String key) {
    final previewBytes = _localImagePreviews[key];
    if (previewBytes != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Image.memory(
          previewBytes,
          key: Key('admin_settings_memory_preview_$key'),
          height: 180,
          fit: BoxFit.contain,
        ),
      );
    }
    final path = _settings?[key] as String?;
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Image.network(
        key: Key('admin_settings_network_preview_$key'),
        widget.api.assetUri(path).toString(),
        height: 180,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Container(
          key: Key('admin_settings_image_fallback_$key'),
          height: 180,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.broken_image_outlined),
        ),
      ),
    );
  }
}
