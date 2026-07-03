import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/driver_application_models.dart';
import '../services/driver_application_api_service.dart';
import '../services/driver_application_storage.dart';
import 'driver_application_status_page.dart';

class DriverApplicationFormPage extends StatefulWidget {
  const DriverApplicationFormPage({
    super.key,
    this.api,
    this.storage = const DriverApplicationStorage(),
    this.resubmitApplicationNumber,
    this.resubmitToken,
  });

  final DriverApplicationApiService? api;
  final DriverApplicationStorage storage;
  final String? resubmitApplicationNumber;
  final String? resubmitToken;

  @override
  State<DriverApplicationFormPage> createState() =>
      _DriverApplicationFormPageState();
}

class _DriverApplicationFormPageState extends State<DriverApplicationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final DriverApplicationApiService _api =
      widget.api ?? DriverApplicationApiService();

  final _fullName = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _phone = TextEditingController();
  final _phoneCountryCode = TextEditingController(text: '+66');
  final _countryCode = TextEditingController(text: 'TH');
  final _licenseNumber = TextEditingController();
  final _licenseCountry = TextEditingController(text: 'TH');
  final _licenseExpiry = TextEditingController();
  final _experience = TextEditingController(text: '1');
  final _make = TextEditingController();
  final _model = TextEditingController();
  final _year = TextEditingController();
  final _color = TextEditingController();
  final _plate = TextEditingController();
  final _serviceAreas = TextEditingController();
  final _notes = TextEditingController();
  final _bankName = TextEditingController();
  final _bankAccountNumber = TextEditingController();
  final _bankAccountHolder = TextEditingController();
  final _lineId = TextEditingController();

  bool _loadingVehicles = true;
  bool _submitting = false;
  String? _error;
  List<DriverApplicationVehicleType> _vehicleTypes = [];
  String? _vehicleTypeCode;
  String _locale = 'ko';
  final String _ownership = 'OWNED';
  final Set<String> _languages = {'ko'};
  bool _personalConsent = false;
  bool _termsConsent = false;
  DriverApplicationUploadFile? _lineQr;
  final List<DriverApplicationUploadFile> _vehiclePhotos = [];
  DriverApplicationUploadFile? _insuranceCertificate;
  DriverApplicationUploadFile? _vehicleRegistration;
  DriverApplicationUploadFile? _taxCertificate;

  bool get _isResubmit =>
      widget.resubmitApplicationNumber != null && widget.resubmitToken != null;

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  @override
  void dispose() {
    for (final controller in [
      _fullName,
      _password,
      _passwordConfirm,
      _phone,
      _phoneCountryCode,
      _countryCode,
      _licenseNumber,
      _licenseCountry,
      _licenseExpiry,
      _experience,
      _make,
      _model,
      _year,
      _color,
      _plate,
      _serviceAreas,
      _notes,
      _bankName,
      _bankAccountNumber,
      _bankAccountHolder,
      _lineId,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<DriverApplicationUploadFile?> _pickOne({
    required bool imageOnly,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: imageOnly
          ? const ['jpg', 'jpeg', 'png', 'webp']
          : const ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return null;
    return DriverApplicationUploadFile(name: file.name, bytes: file.bytes!);
  }

  Future<void> _pickVehiclePhotos() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    final selected = result.files
        .where((file) => file.bytes != null)
        .map(
          (file) =>
              DriverApplicationUploadFile(name: file.name, bytes: file.bytes!),
        )
        .toList();
    setState(() {
      _vehiclePhotos
        ..clear()
        ..addAll(selected.take(6));
    });
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final types = await _api.listVehicleTypes();
      if (!mounted) return;
      setState(() {
        _vehicleTypes = types;
        _vehicleTypeCode = types.isEmpty ? null : types.first.code;
        _loadingVehicles = false;
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _loadingVehicles = false;
        _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_application_vehicle_load_error'),
        );
      });
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.l10n.t('driver_application_validation_required');
    }
    return null;
  }

  DriverApplicationDraft? _buildDraft() {
    if (!_formKey.currentState!.validate()) return null;
    if (_vehicleTypeCode == null || _vehicleTypeCode!.isEmpty) {
      setState(
        () => _error = context.l10n.t('driver_application_vehicle_required'),
      );
      return null;
    }
    if (!_personalConsent || !_termsConsent) {
      setState(
        () => _error = context.l10n.t('driver_application_consent_required'),
      );
      return null;
    }
    if (_password.text.length < 6) {
      setState(
        () => _error = context.l10n.t('driver_application_password_min'),
      );
      return null;
    }
    if (_vehiclePhotos.length < 3 || _vehiclePhotos.length > 6) {
      setState(
        () => _error = context.l10n.t(
          'driver_application_vehicle_photo_count_error',
        ),
      );
      return null;
    }
    if (_lineQr == null ||
        _insuranceCertificate == null ||
        _vehicleRegistration == null ||
        _taxCertificate == null) {
      setState(
        () => _error = context.l10n.t('driver_application_file_required'),
      );
      return null;
    }
    final areas = _serviceAreas.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (areas.isEmpty) {
      setState(
        () =>
            _error = context.l10n.t('driver_application_service_area_required'),
      );
      return null;
    }
    return DriverApplicationDraft(
      fullName: _fullName.text,
      password: _password.text,
      passwordConfirm: _passwordConfirm.text,
      phone: _phone.text,
      phoneCountryCode: _phoneCountryCode.text,
      countryCode: _countryCode.text,
      locale: _locale,
      drivingLicenseNumber: _licenseNumber.text,
      drivingLicenseCountry: _licenseCountry.text,
      drivingLicenseExpiryDate: _licenseExpiry.text,
      yearsOfDrivingExperience: int.tryParse(_experience.text.trim()) ?? 0,
      vehicleOwnershipType: _ownership,
      vehicleTypeCode: _vehicleTypeCode!,
      vehicleTypeId: _selectedVehicleTypeId(),
      vehicleMake: _make.text,
      vehicleModel: _model.text,
      vehicleYear: int.tryParse(_year.text.trim()),
      vehicleColor: _color.text,
      vehiclePlateNumber: _plate.text,
      serviceAreas: areas,
      languages: _languages.toList(growable: false),
      notes: _notes.text,
      bankName: _bankName.text,
      bankAccountNumber: _bankAccountNumber.text,
      bankAccountHolder: _bankAccountHolder.text,
      lineId: _lineId.text,
      primaryServiceArea: areas.first,
      files: DriverApplicationFileBundle(
        lineQr: _lineQr,
        vehiclePhotos: _vehiclePhotos,
        insuranceCertificate: _insuranceCertificate,
        vehicleRegistration: _vehicleRegistration,
        taxCertificate: _taxCertificate,
      ),
      personalDataConsent: _personalConsent,
      driverTermsConsent: _termsConsent,
    );
  }

  int? _selectedVehicleTypeId() {
    for (final type in _vehicleTypes) {
      if (type.code == _vehicleTypeCode) return type.id == 0 ? null : type.id;
    }
    return null;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() => _error = null);
    final draft = _buildDraft();
    if (draft == null) return;
    setState(() => _submitting = true);
    try {
      final receipt = _isResubmit
          ? await _api.resubmitApplication(
              applicationNumber: widget.resubmitApplicationNumber!,
              token: widget.resubmitToken!,
              draft: draft,
            )
          : await _api.submitApplication(draft);
      await widget.storage.save(receipt);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DriverApplicationStatusPage(
            api: _api,
            storage: widget.storage,
            initialReceipt: receipt,
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_application_submit_failed'),
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.t(
            _isResubmit
                ? 'driver_application_resubmit_title'
                : 'driver_application_title',
          ),
        ),
      ),
      body: AppUi.centeredContent(
        maxWidth: 860,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: AppUi.pagePadding(context),
            children: [
              _section(
                title: l10n.t('driver_application_section_account'),
                children: [
                  _text(_fullName, 'driver_application_full_name'),
                  _text(_phone, 'phone', keyboardType: TextInputType.phone),
                  _text(
                    _password,
                    'password',
                    obscure: true,
                    validator: (value) {
                      if ((value ?? '').length < 6) {
                        return l10n.t('driver_application_password_min');
                      }
                      return null;
                    },
                  ),
                  _text(
                    _passwordConfirm,
                    'driver_application_password_confirm',
                    obscure: true,
                    validator: (value) {
                      if (value != _password.text) {
                        return l10n.t('driver_application_password_mismatch');
                      }
                      return null;
                    },
                  ),
                  _text(
                    _phoneCountryCode,
                    'driver_application_phone_country_code',
                    requiredField: false,
                  ),
                  _text(_countryCode, 'country'),
                  DropdownButtonFormField<String>(
                    initialValue: _locale,
                    decoration: InputDecoration(
                      labelText: l10n.t('landing_language_label'),
                    ),
                    items: AppLocalizations.supportedLanguages
                        .map(
                          (code) => DropdownMenuItem(
                            value: code,
                            child: Text(
                              AppLocalizations.languageNames[code] ?? code,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _locale = value ?? 'ko'),
                  ),
                ],
              ),
              _section(
                title: l10n.t('driver_application_section_driver_info'),
                children: [
                  _text(_licenseNumber, 'driver_application_license_number'),
                  _text(_licenseCountry, 'driver_application_license_country'),
                  _text(
                    _licenseExpiry,
                    'driver_application_license_expiry',
                    hint: '2030-01-01',
                  ),
                  _text(_bankName, 'driver_application_bank_name'),
                  _text(
                    _bankAccountNumber,
                    'driver_application_bank_account_number',
                  ),
                  _text(
                    _bankAccountHolder,
                    'driver_application_bank_account_holder',
                  ),
                  if (_loadingVehicles)
                    const LinearProgressIndicator()
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _vehicleTypeCode,
                      decoration: InputDecoration(
                        labelText: l10n.t('driver_application_vehicle_type'),
                      ),
                      items: _vehicleTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type.code,
                              child: Text('${type.name} (${type.code})'),
                            ),
                          )
                          .toList(),
                      validator: (_) => _vehicleTypeCode == null
                          ? l10n.t('driver_application_vehicle_required')
                          : null,
                      onChanged: (value) =>
                          setState(() => _vehicleTypeCode = value),
                    ),
                  _text(
                    _make,
                    'driver_application_vehicle_make',
                    requiredField: false,
                  ),
                  _text(
                    _model,
                    'driver_application_vehicle_model',
                    requiredField: false,
                  ),
                  _text(
                    _year,
                    'driver_application_vehicle_year',
                    requiredField: false,
                    keyboardType: TextInputType.number,
                  ),
                  _text(
                    _color,
                    'driver_application_vehicle_color',
                    requiredField: false,
                  ),
                  _text(_plate, 'driver_application_vehicle_plate'),
                  _text(
                    _serviceAreas,
                    'driver_application_service_areas',
                    hint: l10n.t('driver_application_service_areas_hint'),
                  ),
                  _text(_lineId, 'driver_application_line_id'),
                ],
              ),
              _section(
                title: l10n.t('driver_application_section_documents'),
                children: [
                  _fileButton(
                    'driver_application_line_qr',
                    _lineQr?.name,
                    () async {
                      final file = await _pickOne(imageOnly: true);
                      if (file != null) {
                        setState(() => _lineQr = file);
                      }
                    },
                  ),
                  _fileButton(
                    'driver_application_vehicle_photos',
                    '${_vehiclePhotos.length}/6',
                    _pickVehiclePhotos,
                  ),
                  _fileButton(
                    'driver_application_insurance_certificate',
                    _insuranceCertificate?.name,
                    () async {
                      final file = await _pickOne(imageOnly: false);
                      if (file != null) {
                        setState(() => _insuranceCertificate = file);
                      }
                    },
                  ),
                  _fileButton(
                    'driver_application_vehicle_registration',
                    _vehicleRegistration?.name,
                    () async {
                      final file = await _pickOne(imageOnly: false);
                      if (file != null) {
                        setState(() => _vehicleRegistration = file);
                      }
                    },
                  ),
                  _fileButton(
                    'driver_application_tax_certificate',
                    _taxCertificate?.name,
                    () async {
                      final file = await _pickOne(imageOnly: false);
                      if (file != null) {
                        setState(() => _taxCertificate = file);
                      }
                    },
                  ),
                  CheckboxListTile(
                    value: _personalConsent,
                    onChanged: (value) =>
                        setState(() => _personalConsent = value ?? false),
                    title: Text(l10n.t('driver_application_personal_consent')),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    value: _termsConsent,
                    onChanged: (value) =>
                        setState(() => _termsConsent = value ?? false),
                    title: Text(l10n.t('driver_application_terms_consent')),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Text(
                    l10n.t('driver_application_false_info_notice'),
                    style: const TextStyle(color: AppTokens.textSecondary),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: AppTokens.spaceSm),
                AppUi.surfaceCard(
                  backgroundColor: AppTokens.errorLight,
                  child: Text(
                    _error!,
                    style: const TextStyle(color: AppTokens.error),
                  ),
                ),
              ],
              const SizedBox(height: AppTokens.spaceMd),
              AppUi.primaryButton(
                label: l10n.t(
                  _isResubmit
                      ? 'driver_application_resubmit'
                      : 'driver_application_signup_submit',
                ),
                icon: Icons.send_outlined,
                loading: _submitting,
                onPressed: _submitting || _loadingVehicles ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section({required String title, required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTokens.spaceMd),
      child: AppUi.surfaceCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppTokens.spaceMd),
            ...children.expand((child) => [child, const SizedBox(height: 12)]),
          ],
        ),
      ),
    );
  }

  Widget _text(
    TextEditingController controller,
    String labelKey, {
    bool obscure = false,
    bool requiredField = true,
    String? hint,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: requiredField
            ? '${context.l10n.t(labelKey)} ${context.l10n.t('field_required')}'
            : context.l10n.t(labelKey),
        hintText: hint,
      ),
      validator: validator ?? (requiredField ? _required : null),
    );
  }

  Widget _fileButton(
    String labelKey,
    String? value,
    Future<void> Function() onPressed,
  ) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.attach_file),
      label: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${context.l10n.t(labelKey)}: ${value == null || value.isEmpty ? context.l10n.t('ui_select') : value}',
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
