import '../../../core/network/api_client.dart';

class DriverApplicationUploadFile {
  const DriverApplicationUploadFile({
    required this.filename,
    required this.bytes,
  });

  final String filename;
  final List<int> bytes;
}

class DriverApplicationFileBundle {
  const DriverApplicationFileBundle({
    this.lineQr,
    this.vehiclePhotos = const [],
    this.insuranceCertificate,
    this.vehicleRegistration,
    this.taxCertificate,
  });

  final DriverApplicationUploadFile? lineQr;
  final List<DriverApplicationUploadFile> vehiclePhotos;
  final DriverApplicationUploadFile? insuranceCertificate;
  final DriverApplicationUploadFile? vehicleRegistration;
  final DriverApplicationUploadFile? taxCertificate;
}

class DriverApplicationDraft {
  const DriverApplicationDraft({
    required this.fullName,
    required this.password,
    required this.passwordConfirm,
    required this.phone,
    required this.phoneCountryCode,
    required this.countryCode,
    required this.locale,
    required this.drivingLicenseNumber,
    required this.drivingLicenseCountry,
    this.drivingLicenseExpiryDate,
    required this.yearsOfDrivingExperience,
    required this.vehicleOwnershipType,
    required this.vehicleTypeCode,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleYear,
    this.vehicleColor,
    required this.vehiclePlateNumber,
    required this.serviceAreas,
    required this.languages,
    this.notes,
    this.bankName,
    this.bankAccountNumber,
    this.bankAccountHolder,
    this.lineId,
    this.primaryServiceArea,
    required this.files,
    required this.personalDataConsent,
    required this.driverTermsConsent,
    this.email,
  });

  final String fullName;
  final String password;
  final String passwordConfirm;
  final String phone;
  final String phoneCountryCode;
  final String countryCode;
  final String locale;
  final String drivingLicenseNumber;
  final String drivingLicenseCountry;
  final String? drivingLicenseExpiryDate;
  final int yearsOfDrivingExperience;
  final String vehicleOwnershipType;
  final String vehicleTypeCode;
  final String? vehicleMake;
  final String? vehicleModel;
  final int? vehicleYear;
  final String? vehicleColor;
  final String vehiclePlateNumber;
  final List<String> serviceAreas;
  final List<String> languages;
  final String? notes;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountHolder;
  final String? lineId;
  final String? primaryServiceArea;
  final DriverApplicationFileBundle files;
  final bool personalDataConsent;
  final bool driverTermsConsent;
  final String? email;

  Map<String, String> toMultipartFields() {
    String? trimmed(String? value) {
      final text = value?.trim();
      return text == null || text.isEmpty ? null : text;
    }

    return {
      'fullName': fullName.trim(),
      'password': password,
      'passwordConfirm': passwordConfirm,
      'phone': phone.trim(),
      'phoneCountryCode': phoneCountryCode.trim(),
      'countryCode': countryCode.trim().toUpperCase(),
      'locale': locale,
      'drivingLicenseNumber': drivingLicenseNumber.trim(),
      'drivingLicenseCountry': drivingLicenseCountry.trim().toUpperCase(),
      if (trimmed(drivingLicenseExpiryDate) != null)
        'drivingLicenseExpiryDate': trimmed(drivingLicenseExpiryDate)!,
      'yearsOfDrivingExperience': '$yearsOfDrivingExperience',
      'vehicleOwnershipType': vehicleOwnershipType,
      'vehicleTypeCode': vehicleTypeCode.trim().toUpperCase(),
      if (trimmed(vehicleMake) != null) 'vehicleMake': trimmed(vehicleMake)!,
      if (trimmed(vehicleModel) != null) 'vehicleModel': trimmed(vehicleModel)!,
      if (vehicleYear != null) 'vehicleYear': '$vehicleYear',
      if (trimmed(vehicleColor) != null) 'vehicleColor': trimmed(vehicleColor)!,
      'vehiclePlateNumber': vehiclePlateNumber.trim().replaceAll(
        RegExp(r'\s+'),
        ' ',
      ),
      'serviceAreas': serviceAreas.join(','),
      'languages': languages.join(','),
      if (trimmed(notes) != null) 'notes': trimmed(notes)!,
      if (trimmed(bankName) != null) 'bankName': trimmed(bankName)!,
      if (trimmed(bankAccountNumber) != null)
        'bankAccountNumber': trimmed(bankAccountNumber)!,
      if (trimmed(bankAccountHolder) != null)
        'bankAccountHolder': trimmed(bankAccountHolder)!,
      if (trimmed(lineId) != null) 'lineId': trimmed(lineId)!,
      if (trimmed(primaryServiceArea) != null)
        'primaryServiceArea': trimmed(primaryServiceArea)!,
      if (trimmed(email) != null) 'email': trimmed(email)!,
      'personalDataConsent': personalDataConsent.toString(),
      'driverTermsConsent': driverTermsConsent.toString(),
    };
  }

  List<ApiMultipartFile> toMultipartFiles() {
    final multipartFiles = <ApiMultipartFile>[];
    void addOne(String field, DriverApplicationUploadFile? file, {required bool imageOnly}) {
      if (file == null) return;
      multipartFiles.add(
        ApiMultipartFile(
          field: field,
          filename: file.filename,
          bytes: file.bytes,
          contentType: _contentTypeFor(file.filename, imageOnly: imageOnly),
        ),
      );
    }

    addOne('lineQr', files.lineQr, imageOnly: true);
    for (final photo in files.vehiclePhotos) {
      addOne('vehiclePhotos', photo, imageOnly: true);
    }
    addOne(
      'insuranceCertificate',
      files.insuranceCertificate,
      imageOnly: false,
    );
    addOne(
      'vehicleRegistration',
      files.vehicleRegistration,
      imageOnly: false,
    );
    addOne('taxCertificate', files.taxCertificate, imageOnly: false);
    return multipartFiles;
  }
}

class DriverApplicationReceipt {
  const DriverApplicationReceipt({
    required this.applicationNumber,
    required this.status,
    required this.statusToken,
    required this.submittedAt,
  });

  final String applicationNumber;
  final String status;
  final String statusToken;
  final String submittedAt;

  factory DriverApplicationReceipt.fromJson(Map<String, dynamic> json) {
    return DriverApplicationReceipt(
      applicationNumber: json['applicationNumber'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      statusToken: json['statusToken'] as String? ?? '',
      submittedAt: json['submittedAt']?.toString() ?? '',
    );
  }
}

class DriverApplicationVehicleType {
  const DriverApplicationVehicleType({
    required this.id,
    required this.code,
    required this.name,
  });

  final int id;
  final String code;
  final String name;

  factory DriverApplicationVehicleType.fromJson(Map<String, dynamic> json) {
    return DriverApplicationVehicleType(
      id: (json['id'] as num?)?.toInt() ?? 0,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? json['code'] as String? ?? '',
    );
  }
}

enum DriverApplicationFailureKind {
  validation,
  invalidFileType,
  fileTooLarge,
  phoneConflict,
  plateConflict,
  duplicateApplication,
  unavailable,
  timeout,
  server,
  invalidResponse,
  unknown,
}

class DriverApplicationApiException implements Exception {
  const DriverApplicationApiException(
    this.kind, {
    this.fieldErrors = const {},
    this.statusCode,
  });

  final DriverApplicationFailureKind kind;
  final Map<String, String> fieldErrors;
  final int? statusCode;
}

enum DriverApplicationValidationIssue {
  requiredField,
  passwordTooShort,
  passwordMismatch,
  vehicleTypeMissing,
  serviceAreaMissing,
  consentMissing,
  vehiclePhotoCount,
  missingFile,
  licenseExpiryInvalid,
  licenseExpiryPast,
  vehicleYearInvalid,
}

class DriverApplicationFormValidator {
  static const imageExtensions = {'jpg', 'jpeg', 'png'};
  static const documentExtensions = {'jpg', 'jpeg', 'png', 'pdf'};

  static List<DriverApplicationValidationIssue> validate(
    DriverApplicationDraft draft,
  ) {
    final issues = <DriverApplicationValidationIssue>[];

    if (draft.fullName.trim().isEmpty ||
        draft.phone.trim().isEmpty ||
        draft.drivingLicenseNumber.trim().isEmpty ||
        draft.vehiclePlateNumber.trim().isEmpty) {
      issues.add(DriverApplicationValidationIssue.requiredField);
    }
    if (draft.password.length < 6) {
      issues.add(DriverApplicationValidationIssue.passwordTooShort);
    }
    if (draft.password != draft.passwordConfirm) {
      issues.add(DriverApplicationValidationIssue.passwordMismatch);
    }
    if (draft.vehicleTypeCode.trim().isEmpty) {
      issues.add(DriverApplicationValidationIssue.vehicleTypeMissing);
    }
    if (draft.serviceAreas.isEmpty) {
      issues.add(DriverApplicationValidationIssue.serviceAreaMissing);
    }
    if (!draft.personalDataConsent || !draft.driverTermsConsent) {
      issues.add(DriverApplicationValidationIssue.consentMissing);
    }
    final photoCount = draft.files.vehiclePhotos.length;
    if (photoCount < 3 || photoCount > 6) {
      issues.add(DriverApplicationValidationIssue.vehiclePhotoCount);
    }
    if (draft.files.lineQr == null ||
        draft.files.insuranceCertificate == null ||
        draft.files.vehicleRegistration == null ||
        draft.files.taxCertificate == null) {
      issues.add(DriverApplicationValidationIssue.missingFile);
    }

    final expiry = draft.drivingLicenseExpiryDate?.trim();
    if (expiry != null && expiry.isNotEmpty) {
      final parsed = _parseYmd(expiry);
      if (parsed == null) {
        issues.add(DriverApplicationValidationIssue.licenseExpiryInvalid);
      } else if (!parsed.isAfter(_dateOnly(DateTime.now().subtract(
        const Duration(days: 1),
      )))) {
        issues.add(DriverApplicationValidationIssue.licenseExpiryPast);
      }
    }

    final yearText = draft.vehicleYear;
    if (yearText != null) {
      final currentYear = DateTime.now().year;
      if (yearText < 1980 || yearText > currentYear) {
        issues.add(DriverApplicationValidationIssue.vehicleYearInvalid);
      }
    }

    return issues;
  }

  static bool isAllowedFilename(String filename, {required bool imageOnly}) {
    final ext = fileExtension(filename);
    return imageOnly
        ? imageExtensions.contains(ext)
        : documentExtensions.contains(ext);
  }

  static String fileExtension(String filename) => _extension(filename);

  static String _extension(String filename) {
    final safeName = filename
        .split(RegExp(r'[?#]'))
        .first
        .split(RegExp(r'[\\/]'))
        .last;
    final dot = safeName.lastIndexOf('.');
    if (dot < 0 || dot == safeName.length - 1) return '';
    return safeName.substring(dot + 1).toLowerCase();
  }

  static DateTime? _parseYmd(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _formatYmd(parsed) != value) return null;
    return _dateOnly(parsed);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _formatYmd(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')}';
  }
}

String? _contentTypeFor(String filename, {required bool imageOnly}) {
  if (!DriverApplicationFormValidator.isAllowedFilename(
    filename,
    imageOnly: imageOnly,
  )) {
    return null;
  }
  return switch (DriverApplicationFormValidator.fileExtension(filename)) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'pdf' => 'application/pdf',
    _ => null,
  };
}
