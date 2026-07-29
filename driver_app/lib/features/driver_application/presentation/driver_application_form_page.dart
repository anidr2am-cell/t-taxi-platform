import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../../l10n/app_localizations_extensions.dart';
import '../data/driver_application_api.dart';
import '../data/driver_application_models.dart';

typedef DriverApplicationSubmitted =
    void Function(DriverApplicationReceipt receipt);
typedef DriverApplicationPhotoPicker =
    Future<List<DriverApplicationUploadFile>> Function(int remaining);
typedef DriverApplicationDocumentPicker =
    Future<DriverApplicationUploadFile?> Function({required bool imageOnly});

class DriverApplicationFormPage extends StatefulWidget {
  const DriverApplicationFormPage({
    super.key,
    required this.api,
    this.onSubmitted,
    this.pickPhotos,
    this.pickDocument,
  });

  final DriverApplicationDataSource api;
  final DriverApplicationSubmitted? onSubmitted;
  final DriverApplicationPhotoPicker? pickPhotos;
  final DriverApplicationDocumentPicker? pickDocument;

  @override
  State<DriverApplicationFormPage> createState() =>
      _DriverApplicationFormPageState();
}

class _DriverApplicationFormPageState extends State<DriverApplicationFormPage> {
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _licenseNumber = TextEditingController();
  final _licenseCountry = TextEditingController(text: 'TH');
  final _licenseExpiry = TextEditingController();
  final _bankName = TextEditingController();
  final _bankAccountNumber = TextEditingController();
  final _bankAccountHolder = TextEditingController();
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  final _vehicleYear = TextEditingController();
  final _vehicleColor = TextEditingController();
  final _vehiclePlate = TextEditingController();
  final _serviceAreas = TextEditingController();
  final _lineId = TextEditingController();

  List<DriverApplicationVehicleType>? _vehicleTypes;
  String? _vehicleTypeCode;
  DriverApplicationApiException? _loadError;
  bool _submitting = false;
  bool _personalConsent = false;
  bool _termsConsent = false;

  DriverApplicationUploadFile? _lineQr;
  final List<DriverApplicationUploadFile> _vehiclePhotos = [];
  DriverApplicationUploadFile? _insuranceCertificate;
  DriverApplicationUploadFile? _vehicleRegistration;
  DriverApplicationUploadFile? _taxCertificate;

  @override
  void initState() {
    super.initState();
    _loadVehicleTypes();
  }

  @override
  void dispose() {
    for (final controller in [
      _fullName,
      _phone,
      _password,
      _passwordConfirm,
      _licenseNumber,
      _licenseCountry,
      _licenseExpiry,
      _bankName,
      _bankAccountNumber,
      _bankAccountHolder,
      _vehicleMake,
      _vehicleModel,
      _vehicleYear,
      _vehicleColor,
      _vehiclePlate,
      _serviceAreas,
      _lineId,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _appLocaleCode(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return code == 'th' ? 'th' : 'ko';
  }

  Future<void> _loadVehicleTypes() async {
    try {
      final types = await widget.api.listVehicleTypes();
      if (!mounted) return;
      setState(() {
        _vehicleTypes = types;
        _vehicleTypeCode = types.isEmpty ? null : types.first.code;
      });
    } on DriverApplicationApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _vehicleTypes = const [];
        _loadError = error;
      });
    }
  }

  Future<List<DriverApplicationUploadFile>> _pickPhotos(int remaining) async {
    if (widget.pickPhotos != null) return widget.pickPhotos!(remaining);
    final files = await ImagePicker().pickMultiImage();
    final selected = <DriverApplicationUploadFile>[];
    for (final file in files.take(remaining)) {
      selected.add(
        DriverApplicationUploadFile(
          filename: file.name,
          bytes: await file.readAsBytes(),
        ),
      );
    }
    return selected;
  }

  Future<DriverApplicationUploadFile?> _pickDocument({
    required bool imageOnly,
  }) async {
    if (widget.pickDocument != null) {
      return widget.pickDocument!(imageOnly: imageOnly);
    }
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: imageOnly
          ? const ['jpg', 'jpeg', 'png']
          : const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final file = result?.files.singleOrNull;
    if (file?.bytes == null || file!.bytes!.isEmpty) return null;
    return DriverApplicationUploadFile(
      filename: file.name,
      bytes: file.bytes!,
    );
  }

  List<String> _parseServiceAreas() {
    return _serviceAreas.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  DriverApplicationDraft _buildDraft(BuildContext context) {
    final locale = _appLocaleCode(context);
    final yearText = _vehicleYear.text.trim();
    final expiryText = _licenseExpiry.text.trim();
    return DriverApplicationDraft(
      fullName: _fullName.text,
      password: _password.text,
      passwordConfirm: _passwordConfirm.text,
      phone: _phone.text,
      phoneCountryCode: '+66',
      countryCode: 'TH',
      locale: locale,
      drivingLicenseNumber: _licenseNumber.text,
      drivingLicenseCountry: _licenseCountry.text,
      drivingLicenseExpiryDate: expiryText.isEmpty ? null : expiryText,
      yearsOfDrivingExperience: 1,
      vehicleOwnershipType: 'OWNED',
      vehicleTypeCode: _vehicleTypeCode ?? '',
      vehicleMake: _vehicleMake.text.trim().isEmpty ? null : _vehicleMake.text,
      vehicleModel:
          _vehicleModel.text.trim().isEmpty ? null : _vehicleModel.text,
      vehicleYear: yearText.isEmpty ? null : int.tryParse(yearText),
      vehicleColor:
          _vehicleColor.text.trim().isEmpty ? null : _vehicleColor.text,
      vehiclePlateNumber: _vehiclePlate.text,
      serviceAreas: _parseServiceAreas(),
      languages: [locale],
      bankName: _bankName.text.trim().isEmpty ? null : _bankName.text,
      bankAccountNumber: _bankAccountNumber.text.trim().isEmpty
          ? null
          : _bankAccountNumber.text,
      bankAccountHolder: _bankAccountHolder.text.trim().isEmpty
          ? null
          : _bankAccountHolder.text,
      lineId: _lineId.text.trim().isEmpty ? null : _lineId.text,
      files: DriverApplicationFileBundle(
        lineQr: _lineQr,
        vehiclePhotos: List.unmodifiable(_vehiclePhotos),
        insuranceCertificate: _insuranceCertificate,
        vehicleRegistration: _vehicleRegistration,
        taxCertificate: _taxCertificate,
      ),
      personalDataConsent: _personalConsent,
      driverTermsConsent: _termsConsent,
    );
  }

  void _showValidationError(
    AppLocalizations l10n,
    List<DriverApplicationValidationIssue> issues,
  ) {
    final message = issues.first.localizedMessage(l10n);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _pickLicenseExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 365)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 20)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _licenseExpiry.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    });
  }

  Future<void> _addPhotos() async {
    final remaining = 6 - _vehiclePhotos.length;
    if (remaining <= 0) return;
    final selected = await _pickPhotos(remaining);
    if (!mounted) return;
    setState(() => _vehiclePhotos.addAll(selected.take(remaining)));
  }

  Future<void> _submit() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context);
    final draft = _buildDraft(context);
    final issues = DriverApplicationFormValidator.validate(draft);
    if (issues.isNotEmpty) {
      _showValidationError(l10n, issues);
      return;
    }

    setState(() => _submitting = true);
    try {
      final receipt = await widget.api.submitApplication(draft);
      if (!mounted) return;
      widget.onSubmitted?.call(receipt);
    } on DriverApplicationApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.localizedMessage(l10n))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.driverApplicationTitle)),
      body: _vehicleTypes == null
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(l10n.driverApplicationVehicleTypesLoadError),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadVehicleTypes,
                      child: Text(l10n.retry),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionTitle(l10n.driverApplicationSectionAccount),
                  TextField(
                    key: const Key('driverApplyFullName'),
                    controller: _fullName,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationFullName,
                    ),
                  ),
                  TextField(
                    key: const Key('driverApplyPhone'),
                    controller: _phone,
                    enabled: !_submitting,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationPhone,
                    ),
                  ),
                  TextField(
                    key: const Key('driverApplyPassword'),
                    controller: _password,
                    enabled: !_submitting,
                    obscureText: true,
                    decoration: InputDecoration(labelText: l10n.password),
                  ),
                  TextField(
                    key: const Key('driverApplyPasswordConfirm'),
                    controller: _passwordConfirm,
                    enabled: !_submitting,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationPasswordConfirm,
                    ),
                  ),
                  _sectionTitle(l10n.driverApplicationSectionDriverInfo),
                  TextField(
                    key: const Key('driverApplyLicenseNumber'),
                    controller: _licenseNumber,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationLicenseNumber,
                    ),
                  ),
                  TextField(
                    controller: _licenseCountry,
                    enabled: !_submitting,
                    maxLength: 2,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationLicenseCountry,
                    ),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(l10n.driverApplicationLicenseExpiry),
                    subtitle: Text(
                      _licenseExpiry.text.isEmpty
                          ? l10n.driverApplicationLicenseExpiryPicker
                          : _licenseExpiry.text,
                    ),
                    trailing: OutlinedButton(
                      key: const Key('driverApplyLicenseExpiry'),
                      onPressed: _submitting ? null : _pickLicenseExpiry,
                      child: Text(l10n.select),
                    ),
                  ),
                  TextField(
                    controller: _bankName,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationBankName,
                    ),
                  ),
                  TextField(
                    controller: _bankAccountNumber,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationBankAccountNumber,
                    ),
                  ),
                  TextField(
                    controller: _bankAccountHolder,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationBankAccountHolder,
                    ),
                  ),
                  DropdownButtonFormField<String>(
                    key: const Key('driverApplyVehicleType'),
                    initialValue: _vehicleTypeCode,
                    decoration: InputDecoration(labelText: l10n.vehicleType),
                    items: _vehicleTypes!
                        .map(
                          (type) => DropdownMenuItem(
                            value: type.code,
                            child: Text(
                              type.name.isEmpty ? type.code : type.name,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _vehicleTypeCode = value),
                  ),
                  TextField(
                    controller: _vehicleMake,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationVehicleMake,
                    ),
                  ),
                  TextField(
                    controller: _vehicleModel,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationVehicleModel,
                    ),
                  ),
                  TextField(
                    key: const Key('driverApplyVehicleYear'),
                    controller: _vehicleYear,
                    enabled: !_submitting,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationVehicleYear,
                    ),
                  ),
                  TextField(
                    controller: _vehicleColor,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationVehicleColor,
                    ),
                  ),
                  TextField(
                    key: const Key('driverApplyVehiclePlate'),
                    controller: _vehiclePlate,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.vehiclePlateNumber,
                    ),
                  ),
                  TextField(
                    key: const Key('driverApplyServiceAreas'),
                    controller: _serviceAreas,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationServiceAreas,
                      hintText: l10n.driverApplicationServiceAreasHint,
                    ),
                  ),
                  TextField(
                    controller: _lineId,
                    enabled: !_submitting,
                    decoration: InputDecoration(
                      labelText: l10n.driverApplicationLineId,
                    ),
                  ),
                  _sectionTitle(l10n.driverApplicationSectionDocuments),
                  _DocumentSelector(
                    key: const Key('driverApplyLineQr'),
                    label: l10n.driverApplicationLineQr,
                    file: _lineQr,
                    requiredHint: l10n.requiredFileNotSelected,
                    selectLabel: l10n.select,
                    onPick: _submitting
                        ? null
                        : () async {
                            final file = await _pickDocument(imageOnly: true);
                            if (file != null && mounted) {
                              setState(() => _lineQr = file);
                            }
                          },
                  ),
                  Text(l10n.vehiclePhotosProgress(_vehiclePhotos.length)),
                  OutlinedButton(
                    key: const Key('driverApplyVehiclePhotos'),
                    onPressed: _submitting || _vehiclePhotos.length >= 6
                        ? null
                        : _addPhotos,
                    child: Text(l10n.selectVehiclePhotos),
                  ),
                  if (_vehiclePhotos.isNotEmpty)
                    TextButton(
                      onPressed: _submitting
                          ? null
                          : () => setState(() => _vehiclePhotos.clear()),
                      child: Text(l10n.clearAllVehiclePhotos),
                    ),
                  _DocumentSelector(
                    key: const Key('driverApplyInsurance'),
                    label: l10n.insuranceCertificate,
                    file: _insuranceCertificate,
                    requiredHint: l10n.requiredFileNotSelected,
                    selectLabel: l10n.select,
                    onPick: _submitting
                        ? null
                        : () async {
                            final file = await _pickDocument(imageOnly: false);
                            if (file != null && mounted) {
                              setState(() => _insuranceCertificate = file);
                            }
                          },
                  ),
                  _DocumentSelector(
                    key: const Key('driverApplyRegistration'),
                    label: l10n.vehicleRegistrationDoc,
                    file: _vehicleRegistration,
                    requiredHint: l10n.requiredFileNotSelected,
                    selectLabel: l10n.select,
                    onPick: _submitting
                        ? null
                        : () async {
                            final file = await _pickDocument(imageOnly: false);
                            if (file != null && mounted) {
                              setState(() => _vehicleRegistration = file);
                            }
                          },
                  ),
                  _DocumentSelector(
                    key: const Key('driverApplyTaxCertificate'),
                    label: l10n.driverApplicationTaxCertificate,
                    file: _taxCertificate,
                    requiredHint: l10n.requiredFileNotSelected,
                    selectLabel: l10n.select,
                    onPick: _submitting
                        ? null
                        : () async {
                            final file = await _pickDocument(imageOnly: false);
                            if (file != null && mounted) {
                              setState(() => _taxCertificate = file);
                            }
                          },
                  ),
                  CheckboxListTile(
                    key: const Key('driverApplyPersonalConsent'),
                    contentPadding: EdgeInsets.zero,
                    value: _personalConsent,
                    onChanged: _submitting
                        ? null
                        : (value) =>
                              setState(() => _personalConsent = value ?? false),
                    title: Text(l10n.driverApplicationPersonalConsent),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    key: const Key('driverApplyTermsConsent'),
                    contentPadding: EdgeInsets.zero,
                    value: _termsConsent,
                    onChanged: _submitting
                        ? null
                        : (value) =>
                              setState(() => _termsConsent = value ?? false),
                    title: Text(l10n.driverApplicationTermsConsent),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  Text(
                    l10n.driverApplicationFalseInfoNotice,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    key: const Key('driverApplySubmit'),
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.driverApplicationSubmit),
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
  final DriverApplicationUploadFile? file;
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
