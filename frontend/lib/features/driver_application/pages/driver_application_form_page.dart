import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../models/driver_application_models.dart';
import '../services/driver_application_api_service.dart';

class DriverApplicationFormPage extends StatefulWidget {
  const DriverApplicationFormPage({
    super.key,
    this.api,
    this.resubmitApplicationNumber,
    this.resubmitToken,
    @visibleForTesting this.debugSubmitDraft,
  });

  final DriverApplicationApiService? api;
  final String? resubmitApplicationNumber;
  final String? resubmitToken;
  final DriverApplicationDraft? debugSubmitDraft;

  @override
  State<DriverApplicationFormPage> createState() =>
      _DriverApplicationFormPageState();
}

class _DriverApplicationFormPageState extends State<DriverApplicationFormPage> {
  static const _imageExtensions = {'jpg', 'jpeg', 'png', 'webp'};
  static const _documentExtensions = {'jpg', 'jpeg', 'png', 'webp', 'pdf'};

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
  final _fieldKeys = <String, GlobalKey>{
    'vehicleYear': GlobalKey(),
    'serviceAreas': GlobalKey(),
    'personalDataConsent': GlobalKey(),
    'driverTermsConsent': GlobalKey(),
  };

  bool _loadingVehicles = true;
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  List<DriverApplicationVehicleType> _vehicleTypes = [];
  String? _vehicleTypeCode;
  String _locale = 'ko';
  final String _ownership = 'OWNED';
  final Set<String> _languages = {'ko'};
  bool _personalConsent = false;
  bool _termsConsent = false;
  bool _showDocumentErrors = false;
  bool _submitted = false;
  DriverApplicationUploadFile? _lineQr;
  final List<DriverApplicationUploadFile> _vehiclePhotos = [];
  DriverApplicationUploadFile? _insuranceCertificate;
  DriverApplicationUploadFile? _vehicleRegistration;
  DriverApplicationUploadFile? _taxCertificate;

  bool get _isResubmit =>
      widget.resubmitApplicationNumber != null && widget.resubmitToken != null;

  static const _lineGroupQrAsset = 'assets/images/driver_line_group_qr.png';
  static const _lineGroupUrl = String.fromEnvironment(
    'DRIVER_LINE_GROUP_URL',
    defaultValue: '',
  );

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
    if (!_isAllowedFileName(file.name, imageOnly: imageOnly)) {
      setState(() => _error = context.l10n.t('driver_apply_invalid_file_type'));
      return null;
    }
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
    final invalid = result.files.any(
      (file) => !_isAllowedFileName(file.name, imageOnly: true),
    );
    if (invalid) {
      setState(() => _error = context.l10n.t('driver_apply_invalid_file_type'));
      return;
    }
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

  String _extension(String filename) {
    final safeName = filename
        .split(RegExp(r'[?#]'))
        .first
        .split(RegExp(r'[\\/]'))
        .last;
    final dot = safeName.lastIndexOf('.');
    if (dot < 0 || dot == safeName.length - 1) return '';
    return safeName.substring(dot + 1).toLowerCase();
  }

  bool _isAllowedFileName(String filename, {required bool imageOnly}) {
    final ext = _extension(filename);
    return imageOnly
        ? _imageExtensions.contains(ext)
        : _documentExtensions.contains(ext);
  }

  DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  String _formatYmd(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }

  DateTime? _parseYmd(String value) {
    final trimmed = value.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return null;
    final parsed = DateTime.tryParse(trimmed);
    if (parsed == null || _formatYmd(parsed) != trimmed) return null;
    return _dateOnly(parsed);
  }

  String? _validateLicenseExpiry(String? value) {
    final required = _required(value);
    if (required != null) return required;
    final parsed = _parseYmd(value ?? '');
    if (parsed == null) {
      return context.l10n.t('driver_apply_license_expiry_invalid');
    }
    if (parsed.isBefore(_dateOnly(DateTime.now()))) {
      return context.l10n.t('driver_apply_license_expiry_past');
    }
    return null;
  }

  Future<void> _showLicenseExpiryPicker() async {
    final today = _dateOnly(DateTime.now());
    final typed = _parseYmd(_licenseExpiry.text);
    final selected = await showDatePicker(
      context: context,
      initialDate: typed != null && !typed.isBefore(today) ? typed : today,
      firstDate: today,
      lastDate: DateTime(today.year + 30, today.month, today.day),
    );
    if (selected == null) return;
    setState(() => _licenseExpiry.text = _formatYmd(selected));
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
          fallback: context.l10n.t('driver_apply_vehicle_load_error'),
        );
      });
    }
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return context.l10n.t('driver_apply_validation_required');
    }
    return null;
  }

  String? _serverFieldError(String field) => _fieldErrors[field];

  String? _validateVehicleYear(String? value) {
    final serverError = _serverFieldError('vehicleYear');
    if (serverError != null) return serverError;
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) return null;
    if (!RegExp(r'^\d{4}$').hasMatch(trimmed)) {
      return context.l10n.t('driver_apply_vehicle_year_invalid');
    }
    final year = int.tryParse(trimmed);
    final currentYear = DateTime.now().year;
    if (year == null || year < 1980 || year > currentYear) {
      return context.l10n.t('driver_apply_vehicle_year_invalid');
    }
    return null;
  }

  Future<void> _scrollToFirstFieldError() async {
    if (_fieldErrors.isEmpty) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final key = _fieldKeys[_fieldErrors.keys.first];
    final fieldContext = key?.currentContext;
    if (fieldContext == null || !fieldContext.mounted) return;
    await Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  DriverApplicationDraft? _buildDraft() {
    if (widget.debugSubmitDraft != null) return widget.debugSubmitDraft;
    setState(() => _showDocumentErrors = true);
    if (!_formKey.currentState!.validate()) return null;
    if (_vehicleTypeCode == null || _vehicleTypeCode!.isEmpty) {
      setState(() => _error = context.l10n.t('driver_apply_vehicle_required'));
      return null;
    }
    if (!_personalConsent || !_termsConsent) {
      setState(() => _error = context.l10n.t('driver_apply_consent_required'));
      return null;
    }
    if (_password.text.length < 6) {
      setState(() => _error = context.l10n.t('driver_apply_password_min'));
      return null;
    }
    if (_vehiclePhotos.length < 3 || _vehiclePhotos.length > 6) {
      setState(
        () => _error = context.l10n.t('driver_apply_vehicle_photo_count_error'),
      );
      return null;
    }
    if (_lineQr == null ||
        _insuranceCertificate == null ||
        _vehicleRegistration == null ||
        _taxCertificate == null) {
      setState(() => _error = context.l10n.t('driver_apply_file_required'));
      return null;
    }
    final areas = _serviceAreas.text
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (areas.isEmpty) {
      setState(
        () => _error = context.l10n.t('driver_apply_service_area_required'),
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
    setState(() {
      _error = null;
      _fieldErrors = const {};
    });
    final draft = _buildDraft();
    if (draft == null) return;
    setState(() => _submitting = true);
    try {
      if (_isResubmit) {
        await _api.resubmitApplication(
          applicationNumber: widget.resubmitApplicationNumber!,
          token: widget.resubmitToken!,
          draft: draft,
        );
      } else {
        await _api.submitApplication(draft);
      }
      if (!mounted) return;
      setState(() => _submitted = true);
    } catch (err) {
      if (!mounted) return;
      final fieldErrors = err is DriverApplicationApiException
          ? err.fieldErrors
          : const <String, String>{};
      setState(() {
        _fieldErrors = fieldErrors;
        _error = userFacingError(
          err,
          fallback: context.l10n.t('driver_apply_submit_failed'),
        );
      });
      _formKey.currentState?.validate();
      await _scrollToFirstFieldError();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openLineGroup() async {
    final uri = Uri.tryParse(_lineGroupUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_submitted) {
      return _submittedScaffold(l10n);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.t(
            _isResubmit ? 'driver_apply_resubmit_title' : 'driver_apply_title',
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
                title: l10n.t('driver_apply_section_account'),
                children: [
                  _text(_fullName, 'driver_apply_full_name'),
                  _text(
                    _phone,
                    'driver_apply_phone',
                    keyboardType: TextInputType.phone,
                  ),
                  _text(
                    _password,
                    'driver_apply_password',
                    obscure: true,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      if ((value ?? '').length < 6) {
                        return l10n.t('driver_apply_password_min');
                      }
                      return null;
                    },
                  ),
                  _text(
                    _passwordConfirm,
                    'driver_apply_password_confirm',
                    obscure: true,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    validator: (value) {
                      if (value != _password.text) {
                        return l10n.t('driver_apply_password_mismatch');
                      }
                      return null;
                    },
                  ),
                  _text(
                    _phoneCountryCode,
                    'driver_apply_phone_country_code',
                    requiredField: false,
                  ),
                  _text(_countryCode, 'driver_apply_country'),
                  DropdownButtonFormField<String>(
                    initialValue: _locale,
                    decoration: InputDecoration(
                      labelText: l10n.t('driver_apply_language'),
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
                title: l10n.t('driver_apply_section_driver_info'),
                children: [
                  _text(_licenseNumber, 'driver_apply_license_number'),
                  _text(_licenseCountry, 'driver_apply_license_country'),
                  _text(
                    _licenseExpiry,
                    'driver_apply_license_expiry',
                    hint: '2030-01-01',
                    validator: _validateLicenseExpiry,
                    suffixIcon: IconButton(
                      tooltip: l10n.t('driver_apply_license_expiry_picker'),
                      icon: const Icon(Icons.calendar_today_outlined),
                      onPressed: _showLicenseExpiryPicker,
                    ),
                  ),
                  _text(_bankName, 'driver_apply_bank_name'),
                  _text(_bankAccountNumber, 'driver_apply_bank_account_number'),
                  _text(_bankAccountHolder, 'driver_apply_bank_account_holder'),
                  if (_loadingVehicles)
                    const LinearProgressIndicator()
                  else
                    DropdownButtonFormField<String>(
                      initialValue: _vehicleTypeCode,
                      decoration: InputDecoration(
                        labelText: l10n.t('driver_apply_vehicle_type'),
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
                          ? l10n.t('driver_apply_vehicle_required')
                          : null,
                      onChanged: (value) =>
                          setState(() => _vehicleTypeCode = value),
                    ),
                  _text(
                    _make,
                    'driver_apply_vehicle_make',
                    requiredField: false,
                  ),
                  _text(
                    _model,
                    'driver_apply_vehicle_model',
                    requiredField: false,
                  ),
                  _text(
                    _year,
                    'driver_apply_vehicle_year',
                    fieldName: 'vehicleYear',
                    requiredField: false,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    validator: _validateVehicleYear,
                  ),
                  _text(
                    _color,
                    'driver_apply_vehicle_color',
                    requiredField: false,
                  ),
                  _text(_plate, 'driver_apply_vehicle_plate'),
                  _text(
                    _serviceAreas,
                    'driver_apply_service_areas',
                    fieldName: 'serviceAreas',
                    hint: l10n.t('driver_apply_service_areas_hint'),
                    validator: (value) =>
                        _serverFieldError('serviceAreas') ?? _required(value),
                  ),
                  _text(_lineId, 'driver_apply_line_id'),
                ],
              ),
              _section(
                title: l10n.t('driver_apply_section_documents'),
                children: [
                  _fileButton('driver_apply_line_qr', _lineQr?.name, () async {
                    final file = await _pickOne(imageOnly: true);
                    if (file != null) {
                      setState(() => _lineQr = file);
                    }
                  }, missing: _lineQr == null),
                  _fileButton(
                    'driver_apply_vehicle_photos',
                    '${_vehiclePhotos.length}/6',
                    _pickVehiclePhotos,
                    missing:
                        _vehiclePhotos.length < 3 || _vehiclePhotos.length > 6,
                    errorKey: 'driver_apply_vehicle_photo_count_error',
                  ),
                  _fileButton(
                    'driver_apply_insurance_certificate',
                    _insuranceCertificate?.name,
                    () async {
                      final file = await _pickOne(imageOnly: false);
                      if (file != null) {
                        setState(() => _insuranceCertificate = file);
                      }
                    },
                    missing: _insuranceCertificate == null,
                  ),
                  _fileButton(
                    'driver_apply_vehicle_registration',
                    _vehicleRegistration?.name,
                    () async {
                      final file = await _pickOne(imageOnly: false);
                      if (file != null) {
                        setState(() => _vehicleRegistration = file);
                      }
                    },
                    missing: _vehicleRegistration == null,
                  ),
                  _fileButton(
                    'driver_apply_tax_certificate',
                    _taxCertificate?.name,
                    () async {
                      final file = await _pickOne(imageOnly: false);
                      if (file != null) {
                        setState(() => _taxCertificate = file);
                      }
                    },
                    missing: _taxCertificate == null,
                  ),
                  CheckboxListTile(
                    key: _fieldKeys['personalDataConsent'],
                    value: _personalConsent,
                    onChanged: (value) =>
                        setState(() => _personalConsent = value ?? false),
                    title: Text(l10n.t('driver_apply_personal_consent')),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_fieldErrors['personalDataConsent'] != null)
                    Text(
                      _fieldErrors['personalDataConsent']!,
                      style: const TextStyle(color: AppTokens.error),
                    ),
                  CheckboxListTile(
                    key: _fieldKeys['driverTermsConsent'],
                    value: _termsConsent,
                    onChanged: (value) =>
                        setState(() => _termsConsent = value ?? false),
                    title: Text(l10n.t('driver_apply_terms_consent')),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  if (_fieldErrors['driverTermsConsent'] != null)
                    Text(
                      _fieldErrors['driverTermsConsent']!,
                      style: const TextStyle(color: AppTokens.error),
                    ),
                  Text(
                    l10n.t('driver_apply_false_info_notice'),
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
                      ? 'driver_apply_resubmit'
                      : 'driver_apply_signup_submit',
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

  Widget _submittedScaffold(AppLocalizations l10n) {
    return Scaffold(
      appBar: AppBar(title: Text(l10n.t('driver_apply_title'))),
      body: AppUi.centeredContent(
        maxWidth: 680,
        child: ListView(
          padding: AppUi.pagePadding(context),
          children: [
            AppUi.surfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 48,
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Text(
                    l10n.t('driver_apply_simple_submitted_message'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppTokens.spaceSm),
                  Text(
                    l10n.t('driver_apply_line_group_instruction'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTokens.textSecondary,
                    ),
                  ),
                  const SizedBox(height: AppTokens.spaceMd),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 240,
                        maxHeight: 240,
                      ),
                      child: Image.asset(
                        _lineGroupQrAsset,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 180,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              border: Border.all(color: AppTokens.border),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(AppTokens.spaceMd),
                              child: Text(
                                l10n.t('driver_apply_line_qr_unavailable'),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppTokens.textSecondary,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  if (_lineGroupUrl.isNotEmpty) ...[
                    const SizedBox(height: AppTokens.spaceMd),
                    AppUi.secondaryButton(
                      label: l10n.t('driver_apply_open_line_group'),
                      icon: Icons.open_in_new,
                      onPressed: _openLineGroup,
                    ),
                  ],
                ],
              ),
            ),
          ],
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
    String? fieldName,
    String? hint,
    TextInputType? keyboardType,
    int? maxLength,
    List<TextInputFormatter>? inputFormatters,
    String? Function(String?)? validator,
    AutovalidateMode? autovalidateMode,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      key: fieldName == null ? null : _fieldKeys[fieldName],
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      maxLength: maxLength,
      inputFormatters: inputFormatters,
      autovalidateMode: autovalidateMode,
      decoration: InputDecoration(
        labelText: requiredField
            ? '${context.l10n.t(labelKey)} *'
            : context.l10n.t(labelKey),
        hintText: hint,
        suffixIcon: suffixIcon,
      ),
      validator: validator ?? (requiredField ? _required : null),
    );
  }

  Widget _fileButton(
    String labelKey,
    String? value,
    Future<void> Function() onPressed, {
    required bool missing,
    String errorKey = 'driver_apply_file_required',
  }) {
    final showError = _showDocumentErrors && missing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.attach_file),
          label: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${context.l10n.t(labelKey)} *: ${value == null || value.isEmpty ? context.l10n.t('driver_apply_no_file') : value}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: AppTokens.spaceXs),
          Text(
            context.l10n.t(errorKey),
            style: const TextStyle(color: AppTokens.error),
          ),
        ],
      ],
    );
  }
}
