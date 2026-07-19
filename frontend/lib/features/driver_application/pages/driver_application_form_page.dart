import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../l10n/app_localizations.dart';
import '../../../theme/app_tokens.dart';
import '../../../utils/user_facing_error.dart';
import '../../../widgets/app_ui.dart';
import '../config/driver_application_upload_limits.dart';
import '../models/driver_application_models.dart';
import '../services/driver_application_api_service.dart';
import '../services/driver_application_image_compression_service.dart';
import '../widgets/driver_registration_photo_upload_card.dart';

typedef DriverApplicationSingleFilePicker =
    Future<DriverApplicationUploadFile?> Function(bool imageOnly);
typedef DriverApplicationVehiclePhotosPicker =
    Future<List<DriverApplicationUploadFile>?> Function();

class DriverApplicationFormPage extends StatefulWidget {
  const DriverApplicationFormPage({
    super.key,
    this.api,
    this.resubmitApplicationNumber,
    this.resubmitToken,
    @visibleForTesting this.debugSubmitDraft,
    @visibleForTesting this.debugPickOne,
    @visibleForTesting this.debugPickVehiclePhotos,
    @visibleForTesting this.debugCompressionService,
  });

  final DriverApplicationApiService? api;
  final String? resubmitApplicationNumber;
  final String? resubmitToken;
  final DriverApplicationDraft? debugSubmitDraft;
  final DriverApplicationSingleFilePicker? debugPickOne;
  final DriverApplicationVehiclePhotosPicker? debugPickVehiclePhotos;
  final DriverApplicationImageCompressionService? debugCompressionService;

  @override
  State<DriverApplicationFormPage> createState() =>
      _DriverApplicationFormPageState();
}

class _DriverApplicationFormPageState extends State<DriverApplicationFormPage> {
  static const _imageExtensions = {'jpg', 'jpeg', 'png'};
  static const _documentExtensions = {'jpg', 'jpeg', 'png', 'pdf'};

  final _formKey = GlobalKey<FormState>();
  late final DriverApplicationApiService _api =
      widget.api ?? DriverApplicationApiService();
  late final DriverApplicationImageCompressionService _compressionService =
      widget.debugCompressionService ??
      const DriverApplicationImageCompressionService();

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
    'lineQr': GlobalKey(),
    'vehiclePhotos': GlobalKey(),
    'insuranceCertificate': GlobalKey(),
    'vehicleRegistration': GlobalKey(),
    'taxCertificate': GlobalKey(),
  };

  bool _loadingVehicles = true;
  bool _submitting = false;
  String? _error;
  Map<String, String> _fieldErrors = const {};
  Map<String, String> _fileErrors = const {};
  List<DriverApplicationVehicleType> _vehicleTypes = [];
  String? _vehicleTypeCode;
  String _locale = 'ko';
  final String _ownership = 'OWNED';
  final Set<String> _languages = {'ko'};
  bool _personalConsent = false;
  bool _termsConsent = false;
  bool _showDocumentErrors = false;
  bool _lastDraftFailureWasDocument = false;
  bool _submitted = false;
  DriverApplicationUploadFile? _lineQr;
  final List<DriverApplicationUploadFile> _vehiclePhotos = [];
  DriverApplicationUploadFile? _insuranceCertificate;
  DriverApplicationUploadFile? _vehicleRegistration;
  DriverApplicationUploadFile? _taxCertificate;
  String? _pickingFileKey;

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
    final debugPicker = widget.debugPickOne;
    if (debugPicker != null) return debugPicker(imageOnly);
    final invalidTypeMessage = context.l10n.t('driver_apply_invalid_file_type');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: imageOnly
          ? const ['jpg', 'jpeg', 'png']
          : const ['jpg', 'jpeg', 'png', 'pdf'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null || file.bytes == null) return null;
    if (!_isAllowedFileName(file.name, imageOnly: imageOnly)) {
      throw _DriverApplicationFilePickException(invalidTypeMessage);
    }
    return DriverApplicationUploadFile(name: file.name, bytes: file.bytes!);
  }

  Future<void> _selectSingleFile({
    required String fieldKey,
    required bool imageOnly,
    required void Function(DriverApplicationUploadFile file) onSelected,
  }) async {
    if (_pickingFileKey != null) return;
    setState(() {
      _pickingFileKey = fieldKey;
      _error = null;
      _fileErrors = {..._fileErrors}..remove(fieldKey);
    });
    try {
      final file = await _pickOne(imageOnly: imageOnly);
      if (!mounted || file == null) return;
      final prepared = widget.debugPickOne == null
          ? await _prepareSelectedFile(
              file,
              category: fieldKey == 'lineQr'
                  ? DriverApplicationImageCategory.lineQr
                  : DriverApplicationImageCategory.document,
            )
          : file;
      if (!mounted) return;
      setState(() => onSelected(prepared));
    } on _DriverApplicationFilePickException catch (err) {
      if (!mounted) return;
      setState(() {
        _fileErrors = {..._fileErrors, fieldKey: err.message};
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _fileErrors = {
          ..._fileErrors,
          fieldKey: context.l10n.t('driver_apply_file_pick_failed'),
        };
      });
    } finally {
      if (mounted) setState(() => _pickingFileKey = null);
    }
  }

  Future<void> _selectVehiclePhotos() async {
    if (_pickingFileKey != null) return;
    if (_vehiclePhotos.length >= 6) {
      setState(() {
        _fileErrors = {
          ..._fileErrors,
          'vehiclePhotos': context.l10n.t(
            'driver_apply_vehicle_photo_limit_reached',
          ),
        };
      });
      return;
    }
    setState(() {
      _pickingFileKey = 'vehiclePhotos';
      _error = null;
      _fileErrors = {..._fileErrors}..remove('vehiclePhotos');
    });
    try {
      final selected = await _pickVehiclePhotos();
      if (!mounted || selected == null) return;
      final preparedSelected = widget.debugPickVehiclePhotos == null
          ? await _prepareVehiclePhotos(selected)
          : selected;
      if (!mounted) return;
      final remainingSlots = 6 - _vehiclePhotos.length;
      var duplicateSkipped = false;
      var limitSkipped = false;
      final filesToAdd = <DriverApplicationUploadFile>[];
      for (final file in preparedSelected) {
        final duplicate =
            _vehiclePhotos.any(
              (existing) => _sameFileIdentity(existing, file),
            ) ||
            filesToAdd.any((existing) => _sameFileIdentity(existing, file));
        if (duplicate) {
          duplicateSkipped = true;
          continue;
        }
        if (filesToAdd.length >= remainingSlots) {
          limitSkipped = true;
          continue;
        }
        filesToAdd.add(file);
      }
      setState(() {
        if (filesToAdd.isNotEmpty) {
          _vehiclePhotos.addAll(filesToAdd);
        }
        final nextErrors = {..._fileErrors}..remove('vehiclePhotos');
        if (duplicateSkipped || limitSkipped) {
          nextErrors['vehiclePhotos'] = duplicateSkipped
              ? context.l10n.t('driver_apply_duplicate_file')
              : context.l10n.t('driver_apply_vehicle_photo_limit_reached');
        }
        _fileErrors = nextErrors;
      });
    } on _DriverApplicationFilePickException catch (err) {
      if (!mounted) return;
      setState(() {
        _fileErrors = {..._fileErrors, 'vehiclePhotos': err.message};
      });
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _fileErrors = {
          ..._fileErrors,
          'vehiclePhotos': context.l10n.t('driver_apply_file_pick_failed'),
        };
      });
    } finally {
      if (mounted) setState(() => _pickingFileKey = null);
    }
  }

  Future<List<DriverApplicationUploadFile>?> _pickVehiclePhotos() async {
    final debugPicker = widget.debugPickVehiclePhotos;
    if (debugPicker != null) return debugPicker();
    final invalidTypeMessage = context.l10n.t('driver_apply_invalid_file_type');
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['jpg', 'jpeg', 'png'],
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return null;
    final invalid = result.files.any(
      (file) => !_isAllowedFileName(file.name, imageOnly: true),
    );
    if (invalid) {
      throw _DriverApplicationFilePickException(invalidTypeMessage);
    }
    return result.files
        .where((file) => file.bytes != null)
        .map(
          (file) =>
              DriverApplicationUploadFile(name: file.name, bytes: file.bytes!),
        )
        .toList();
  }

  void _removeFile(String fieldKey) {
    setState(() {
      _fileErrors = {..._fileErrors}..remove(fieldKey);
      switch (fieldKey) {
        case 'lineQr':
          _lineQr = null;
          break;
        case 'vehiclePhotos':
          _vehiclePhotos.clear();
          break;
        case 'insuranceCertificate':
          _insuranceCertificate = null;
          break;
        case 'vehicleRegistration':
          _vehicleRegistration = null;
          break;
        case 'taxCertificate':
          _taxCertificate = null;
          break;
      }
    });
  }

  void _removeVehiclePhotoAt(int index) {
    if (index < 0 || index >= _vehiclePhotos.length) return;
    setState(() {
      _vehiclePhotos.removeAt(index);
      _fileErrors = {..._fileErrors}..remove('vehiclePhotos');
    });
  }

  bool _sameFileIdentity(
    DriverApplicationUploadFile left,
    DriverApplicationUploadFile right,
  ) {
    return left.name == right.name && left.bytes.length == right.bytes.length;
  }

  Future<DriverApplicationUploadFile> _prepareSelectedFile(
    DriverApplicationUploadFile file, {
    required DriverApplicationImageCategory category,
  }) async {
    final processingFailedMessage = context.l10n.t(
      'driver_apply_image_processing_failed',
    );
    final tooLargeMessage = context.l10n.t(
      'driver_apply_file_too_large_after_compression',
    );
    try {
      final prepared = await _compressionService.prepare(
        file,
        category: category,
      );
      _validatePreparedFile(prepared, tooLargeMessage);
      return prepared;
    } on _DriverApplicationFilePickException {
      rethrow;
    } catch (_) {
      throw _DriverApplicationFilePickException(processingFailedMessage);
    }
  }

  Future<List<DriverApplicationUploadFile>> _prepareVehiclePhotos(
    List<DriverApplicationUploadFile> files,
  ) async {
    final prepared = <DriverApplicationUploadFile>[];
    for (final file in files) {
      prepared.add(
        await _prepareSelectedFile(
          file,
          category: DriverApplicationImageCategory.vehicle,
        ),
      );
      if (!mounted) break;
      await Future<void>.delayed(Duration.zero);
    }
    return prepared;
  }

  void _validatePreparedFile(
    DriverApplicationUploadFile file,
    String tooLargeMessage,
  ) {
    if (file.bytes.length >
        DriverApplicationUploadLimits.perFileHardLimitBytes) {
      throw _DriverApplicationFilePickException(tooLargeMessage);
    }
  }

  List<DriverApplicationUploadFile> _allSelectedFiles() {
    return _allFilesInBundle(
      DriverApplicationFileBundle(
        lineQr: _lineQr,
        vehiclePhotos: _vehiclePhotos,
        insuranceCertificate: _insuranceCertificate,
        vehicleRegistration: _vehicleRegistration,
        taxCertificate: _taxCertificate,
      ),
    );
  }

  List<DriverApplicationUploadFile> _allFilesInBundle(
    DriverApplicationFileBundle bundle,
  ) {
    return [
      if (bundle.lineQr != null) bundle.lineQr!,
      ...bundle.vehiclePhotos,
      if (bundle.insuranceCertificate != null) bundle.insuranceCertificate!,
      if (bundle.vehicleRegistration != null) bundle.vehicleRegistration!,
      if (bundle.taxCertificate != null) bundle.taxCertificate!,
    ];
  }

  int _totalUploadBytesFor(List<DriverApplicationUploadFile> files) =>
      files.fold(0, (sum, file) => sum + file.bytes.length);

  int _totalUploadBytes() => _totalUploadBytesFor(_allSelectedFiles());

  bool _hasBlockingFileError() {
    return _fileErrors.isNotEmpty || _hasBlockingFileSize(_allSelectedFiles());
  }

  bool _hasBlockingFileSize(List<DriverApplicationUploadFile> files) {
    return files.any(
          (file) =>
              file.bytes.length >
              DriverApplicationUploadLimits.perFileHardLimitBytes,
        ) ||
        _totalUploadBytesFor(files) >
            DriverApplicationUploadLimits.totalHardLimitBytes;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    final mb = bytes / DriverApplicationUploadLimits.bytesPerMb;
    if (mb >= 0.1) return '${mb.toStringAsFixed(1)}MB';
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(0)}KB';
  }

  String _totalUploadSizeText() {
    return context.l10n
        .t('driver_apply_total_upload_size')
        .replaceAll('{size}', _formatBytes(_totalUploadBytes()))
        .replaceAll(
          '{limit}',
          _formatBytes(DriverApplicationUploadLimits.totalHardLimitBytes),
        );
  }

  String? _totalUploadWarningText() {
    return _totalUploadWarningTextFor(_allSelectedFiles());
  }

  String? _totalUploadWarningTextFor(List<DriverApplicationUploadFile> files) {
    final total = _totalUploadBytesFor(files);
    if (total > DriverApplicationUploadLimits.totalHardLimitBytes) {
      return context.l10n.t('driver_apply_total_upload_too_large');
    }
    if (total > DriverApplicationUploadLimits.totalWarningBytes) {
      return context.l10n.t('driver_apply_total_upload_warning');
    }
    return null;
  }

  Future<void> _scrollToFirstDocumentError() async {
    final firstKey = _firstDocumentErrorKey();
    if (firstKey == null) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final fieldContext = _fieldKeys[firstKey]?.currentContext;
    if (fieldContext == null || !fieldContext.mounted) return;
    await Scrollable.ensureVisible(
      fieldContext,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      alignment: 0.15,
    );
  }

  String? _firstDocumentErrorKey() {
    if (_lineQr == null) return 'lineQr';
    if (_vehiclePhotos.length < 3 || _vehiclePhotos.length > 6) {
      return 'vehiclePhotos';
    }
    if (_insuranceCertificate == null) return 'insuranceCertificate';
    if (_vehicleRegistration == null) return 'vehicleRegistration';
    if (_taxCertificate == null) return 'taxCertificate';
    return null;
  }

  List<DriverApplicationUploadFile> _singleFileList(
    DriverApplicationUploadFile? file,
  ) {
    return file == null ? const [] : [file];
  }

  Widget _uploadCard({
    required String fieldKey,
    required String titleKey,
    required String descriptionKey,
    required List<DriverApplicationUploadFile> files,
    required bool missing,
    required VoidCallback onSelect,
    VoidCallback? onRemoveAll,
    void Function(int index)? onRemoveFile,
    String missingKey = 'driver_apply_file_required',
    String? selectLabelKey,
    bool? showSelectButton,
    String? disabledSelectLabelKey,
    String? countText,
    int maxPreviewFiles = 3,
  }) {
    final hasFiles = files.isNotEmpty;
    final canSelect = showSelectButton ?? !hasFiles;
    return KeyedSubtree(
      key: _fieldKeys[fieldKey],
      child: DriverRegistrationPhotoUploadCard(
        fieldKey: fieldKey,
        title: context.l10n.t(titleKey),
        description: context.l10n.t(descriptionKey),
        files: files,
        isRequired: true,
        showMissing: _showDocumentErrors && missing,
        processing: _pickingFileKey == fieldKey,
        selectLabel: context.l10n.t(
          selectLabelKey ?? 'driver_apply_upload_select',
        ),
        showSelectButton: canSelect,
        disabledSelectLabel: disabledSelectLabelKey == null
            ? null
            : context.l10n.t(disabledSelectLabelKey),
        errorText: _fileErrors[fieldKey],
        missingText: context.l10n.t(missingKey),
        countText: countText,
        maxPreviewFiles: maxPreviewFiles,
        onSelect: onSelect,
        onRemoveAll: onRemoveAll,
        onRemoveFile: onRemoveFile,
      ),
    );
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
    if (widget.debugSubmitDraft != null) {
      final draft = widget.debugSubmitDraft!;
      final files = _allFilesInBundle(draft.files);
      if (_hasBlockingFileSize(files)) {
        setState(() {
          _lastDraftFailureWasDocument = true;
          _error =
              _totalUploadWarningTextFor(files) ??
              context.l10n.t('driver_apply_file_too_large_after_compression');
        });
        return null;
      }
      return draft;
    }
    setState(() {
      _showDocumentErrors = true;
      _lastDraftFailureWasDocument = false;
    });
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
      setState(() {
        _lastDraftFailureWasDocument = true;
        _error = context.l10n.t('driver_apply_vehicle_photo_count_error');
      });
      return null;
    }
    if (_lineQr == null ||
        _insuranceCertificate == null ||
        _vehicleRegistration == null ||
        _taxCertificate == null) {
      setState(() {
        _lastDraftFailureWasDocument = true;
        _error = context.l10n.t('driver_apply_file_required');
      });
      return null;
    }
    if (_hasBlockingFileError()) {
      setState(() {
        _lastDraftFailureWasDocument = true;
        _error =
            _totalUploadWarningText() ??
            context.l10n.t('driver_apply_file_too_large_after_compression');
      });
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
    if (draft == null) {
      if (_lastDraftFailureWasDocument) {
        await _scrollToFirstDocumentError();
      }
      return;
    }
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
        _error = _submitErrorMessage(err);
      });
      _formKey.currentState?.validate();
      await _scrollToFirstFieldError();
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _submitErrorMessage(Object err) {
    final l10n = context.l10n;
    if (err is DriverApplicationApiException) {
      if (err.statusCode == 413 || err.errorCode == 'FILE_TOO_LARGE') {
        return l10n.t('driver_apply_upload_too_large');
      }
      if (err.statusCode == 502 ||
          err.statusCode == 503 ||
          err.statusCode == 504 ||
          err.errorCode == 'SERVER_UNAVAILABLE') {
        return l10n.t('driver_apply_server_unavailable');
      }
      if (err.errorCode == 'REQUEST_FAILED') {
        return l10n.t('driver_apply_request_failed');
      }
    }
    if (_looksLikeJsonParseFailure(err)) {
      return l10n.t('driver_apply_request_failed');
    }
    return userFacingError(err, fallback: l10n.t('driver_apply_submit_failed'));
  }

  bool _looksLikeJsonParseFailure(Object err) {
    final text = err.toString().toLowerCase();
    return text.contains('syntaxerror') ||
        text.contains('json parse error') ||
        text.contains('unexpected token') ||
        text.contains('formatException'.toLowerCase()) ||
        text.contains('unexpected character') ||
        text.contains('unexpected end of input') ||
        text.contains('invalid json');
  }

  Future<void> _openLineGroup() async {
    final uri = Uri.tryParse(_lineGroupUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _uploadSizeSummary() {
    final warning = _totalUploadWarningText();
    final color = warning == null
        ? AppTokens.textSecondary
        : _totalUploadBytes() >
              DriverApplicationUploadLimits.totalHardLimitBytes
        ? AppTokens.error
        : AppTokens.warning;
    return Container(
      key: const ValueKey('driver_application_upload_size_summary'),
      padding: const EdgeInsets.all(AppTokens.spaceMd),
      decoration: BoxDecoration(
        color: warning == null
            ? AppTokens.surfaceMuted
            : AppTokens.warningLight,
        borderRadius: BorderRadius.circular(AppTokens.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _totalUploadSizeText(),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: color),
          ),
          if (warning != null) ...[
            const SizedBox(height: AppTokens.spaceXs),
            Text(
              warning,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
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
                  _uploadCard(
                    fieldKey: 'lineQr',
                    titleKey: 'driver_apply_line_qr',
                    descriptionKey: 'driver_apply_upload_image_help',
                    files: _singleFileList(_lineQr),
                    missing: _lineQr == null,
                    onSelect: () => _selectSingleFile(
                      fieldKey: 'lineQr',
                      imageOnly: true,
                      onSelected: (file) => _lineQr = file,
                    ),
                    onRemoveAll: () => _removeFile('lineQr'),
                  ),
                  _uploadCard(
                    fieldKey: 'vehiclePhotos',
                    titleKey: 'driver_apply_vehicle_photos',
                    descriptionKey: 'driver_apply_vehicle_photo_help',
                    files: _vehiclePhotos,
                    missing:
                        _vehiclePhotos.length < 3 || _vehiclePhotos.length > 6,
                    onSelect: _selectVehiclePhotos,
                    onRemoveFile: _removeVehiclePhotoAt,
                    missingKey: 'driver_apply_vehicle_photo_count_error',
                    selectLabelKey: 'driver_apply_upload_add_photo',
                    showSelectButton: _vehiclePhotos.length < 6,
                    disabledSelectLabelKey:
                        'driver_apply_vehicle_photo_limit_reached',
                    countText: context.l10n
                        .t('driver_apply_vehicle_photo_count')
                        .replaceAll('{count}', '${_vehiclePhotos.length}'),
                    maxPreviewFiles: 6,
                  ),
                  _uploadCard(
                    fieldKey: 'insuranceCertificate',
                    titleKey: 'driver_apply_insurance_certificate',
                    descriptionKey: 'driver_apply_upload_document_help',
                    files: _singleFileList(_insuranceCertificate),
                    missing: _insuranceCertificate == null,
                    onSelect: () => _selectSingleFile(
                      fieldKey: 'insuranceCertificate',
                      imageOnly: false,
                      onSelected: (file) => _insuranceCertificate = file,
                    ),
                    onRemoveAll: () => _removeFile('insuranceCertificate'),
                  ),
                  _uploadCard(
                    fieldKey: 'vehicleRegistration',
                    titleKey: 'driver_apply_vehicle_registration',
                    descriptionKey: 'driver_apply_upload_document_help',
                    files: _singleFileList(_vehicleRegistration),
                    missing: _vehicleRegistration == null,
                    onSelect: () => _selectSingleFile(
                      fieldKey: 'vehicleRegistration',
                      imageOnly: false,
                      onSelected: (file) => _vehicleRegistration = file,
                    ),
                    onRemoveAll: () => _removeFile('vehicleRegistration'),
                  ),
                  _uploadCard(
                    fieldKey: 'taxCertificate',
                    titleKey: 'driver_apply_tax_certificate',
                    descriptionKey: 'driver_apply_upload_document_help',
                    files: _singleFileList(_taxCertificate),
                    missing: _taxCertificate == null,
                    onSelect: () => _selectSingleFile(
                      fieldKey: 'taxCertificate',
                      imageOnly: false,
                      onSelected: (file) => _taxCertificate = file,
                    ),
                    onRemoveAll: () => _removeFile('taxCertificate'),
                  ),
                  _uploadSizeSummary(),
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
                onPressed:
                    _submitting || _loadingVehicles || _pickingFileKey != null
                    ? null
                    : _submit,
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
}

class _DriverApplicationFilePickException implements Exception {
  const _DriverApplicationFilePickException(this.message);

  final String message;
}
