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
    required this.drivingLicenseExpiryDate,
    required this.yearsOfDrivingExperience,
    required this.vehicleOwnershipType,
    required this.vehicleTypeCode,
    required this.vehicleTypeId,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleYear,
    required this.vehicleColor,
    required this.vehiclePlateNumber,
    required this.serviceAreas,
    required this.languages,
    required this.notes,
    required this.bankName,
    required this.bankAccountNumber,
    required this.bankAccountHolder,
    required this.lineId,
    required this.primaryServiceArea,
    required this.files,
    required this.personalDataConsent,
    required this.driverTermsConsent,
  });

  final String fullName;
  final String password;
  final String passwordConfirm;
  final String phone;
  final String? phoneCountryCode;
  final String countryCode;
  final String locale;
  final String drivingLicenseNumber;
  final String drivingLicenseCountry;
  final String drivingLicenseExpiryDate;
  final int yearsOfDrivingExperience;
  final String vehicleOwnershipType;
  final String vehicleTypeCode;
  final int? vehicleTypeId;
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

  Map<String, dynamic> toJson() {
    return {
      'fullName': fullName.trim(),
      'applicantName': fullName.trim(),
      'email': '${phone.replaceAll(RegExp(r'[^0-9+]'), '')}@driver.local',
      'password': password,
      'passwordConfirm': passwordConfirm,
      'passwordConfirmation': passwordConfirm,
      'phone': phone.trim(),
      'phoneCountryCode': phoneCountryCode?.trim(),
      'countryCode': countryCode.trim().toUpperCase(),
      'locale': locale,
      'drivingLicenseNumber': drivingLicenseNumber.trim(),
      'drivingLicenseCountry': drivingLicenseCountry.trim().toUpperCase(),
      'drivingLicenseExpiryDate': drivingLicenseExpiryDate.trim(),
      'yearsOfDrivingExperience': yearsOfDrivingExperience,
      'vehicleOwnershipType': vehicleOwnershipType,
      'vehicleTypeCode': vehicleTypeCode.trim().toUpperCase(),
      if (vehicleTypeId != null) 'vehicleTypeId': vehicleTypeId,
      'vehicleMake': vehicleMake?.trim(),
      'vehicleModel': vehicleModel?.trim(),
      'vehicleYear': vehicleYear,
      'vehicleColor': vehicleColor?.trim(),
      'vehiclePlateNumber': vehiclePlateNumber.trim().toUpperCase(),
      'serviceAreas': serviceAreas,
      'languages': languages,
      'notes': notes?.trim(),
      'bankName': bankName?.trim(),
      'bankAccountNumber': bankAccountNumber?.trim(),
      'bankAccountHolder': bankAccountHolder?.trim(),
      'lineId': lineId?.trim(),
      'primaryServiceArea': primaryServiceArea?.trim(),
      'personalDataConsent': personalDataConsent,
      'driverTermsConsent': driverTermsConsent,
    };
  }
}

class DriverApplicationUploadFile {
  const DriverApplicationUploadFile({required this.name, required this.bytes});

  final String name;
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

class DriverApplicationStatusResult {
  const DriverApplicationStatusResult({
    required this.applicationNumber,
    required this.status,
    required this.submittedAt,
    required this.reviewedAt,
    required this.rejectionReason,
  });

  final String applicationNumber;
  final String status;
  final String submittedAt;
  final String? reviewedAt;
  final String? rejectionReason;

  factory DriverApplicationStatusResult.fromJson(Map<String, dynamic> json) {
    return DriverApplicationStatusResult(
      applicationNumber: json['applicationNumber'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      submittedAt: json['submittedAt']?.toString() ?? '',
      reviewedAt: json['reviewedAt']?.toString(),
      rejectionReason: json['rejectionReason']?.toString(),
    );
  }
}

class DriverApplicationAdminListResult {
  const DriverApplicationAdminListResult({
    required this.page,
    required this.pageSize,
    required this.total,
    required this.items,
  });

  final int page;
  final int pageSize;
  final int total;
  final List<DriverApplicationAdminListItem> items;

  factory DriverApplicationAdminListResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return DriverApplicationAdminListResult(
      page: json['page'] as int? ?? 1,
      pageSize: json['page_size'] as int? ?? json['pageSize'] as int? ?? 20,
      total: json['total'] as int? ?? rawItems.length,
      items: rawItems
          .map(
            (item) => DriverApplicationAdminListItem.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false),
    );
  }
}

class DriverApplicationAdminListItem {
  const DriverApplicationAdminListItem({
    required this.id,
    required this.applicationNumber,
    required this.status,
    required this.email,
    required this.fullName,
    required this.phone,
    required this.countryCode,
    required this.locale,
    required this.vehicleTypeCode,
    required this.vehiclePlateNumber,
    required this.primaryServiceArea,
    required this.submittedAt,
    required this.reviewedAt,
  });

  final int id;
  final String applicationNumber;
  final String status;
  final String email;
  final String fullName;
  final String phone;
  final String? countryCode;
  final String locale;
  final String vehicleTypeCode;
  final String vehiclePlateNumber;
  final String? primaryServiceArea;
  final String submittedAt;
  final String? reviewedAt;

  factory DriverApplicationAdminListItem.fromJson(Map<String, dynamic> json) {
    return DriverApplicationAdminListItem(
      id: json['id'] as int? ?? 0,
      applicationNumber: json['applicationNumber'] as String? ?? '',
      status: json['status'] as String? ?? 'PENDING',
      email: json['email'] as String? ?? '',
      fullName: json['fullName'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      countryCode: json['countryCode'] as String?,
      locale: json['locale'] as String? ?? 'ko',
      vehicleTypeCode: json['vehicleTypeCode'] as String? ?? '',
      vehiclePlateNumber: json['vehiclePlateNumber'] as String? ?? '',
      primaryServiceArea: json['primaryServiceArea'] as String?,
      submittedAt: json['submittedAt']?.toString() ?? '',
      reviewedAt: json['reviewedAt']?.toString(),
    );
  }
}

class DriverApplicationAdminDetail extends DriverApplicationAdminListItem {
  const DriverApplicationAdminDetail({
    required super.id,
    required super.applicationNumber,
    required super.status,
    required super.email,
    required super.fullName,
    required super.phone,
    required super.countryCode,
    required super.locale,
    required super.vehicleTypeCode,
    required super.vehiclePlateNumber,
    required super.primaryServiceArea,
    required super.submittedAt,
    required super.reviewedAt,
    required this.phoneCountryCode,
    required this.drivingLicenseNumber,
    required this.drivingLicenseCountry,
    required this.drivingLicenseExpiryDate,
    required this.yearsOfDrivingExperience,
    required this.vehicleOwnershipType,
    required this.vehicleMake,
    required this.vehicleModel,
    required this.vehicleYear,
    required this.vehicleColor,
    required this.serviceAreas,
    required this.languages,
    required this.notes,
    required this.bankName,
    required this.bankAccountNumber,
    required this.bankAccountHolder,
    required this.lineId,
    required this.files,
    required this.personalDataConsentAt,
    required this.driverTermsConsentAt,
    required this.rejectionReason,
    required this.adminNote,
    required this.approvedUserId,
    required this.approvedDriverId,
    required this.resubmittedFromApplicationId,
  });

  final String? phoneCountryCode;
  final String drivingLicenseNumber;
  final String? drivingLicenseCountry;
  final String? drivingLicenseExpiryDate;
  final int yearsOfDrivingExperience;
  final String vehicleOwnershipType;
  final String? vehicleMake;
  final String? vehicleModel;
  final int? vehicleYear;
  final String? vehicleColor;
  final List<String> serviceAreas;
  final List<String> languages;
  final String? notes;
  final String? bankName;
  final String? bankAccountNumber;
  final String? bankAccountHolder;
  final String? lineId;
  final List<DriverApplicationAdminFile> files;
  final String? personalDataConsentAt;
  final String? driverTermsConsentAt;
  final String? rejectionReason;
  final String? adminNote;
  final int? approvedUserId;
  final int? approvedDriverId;
  final int? resubmittedFromApplicationId;

  factory DriverApplicationAdminDetail.fromJson(Map<String, dynamic> json) {
    final base = DriverApplicationAdminListItem.fromJson(json);
    List<String> strings(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false);

    return DriverApplicationAdminDetail(
      id: base.id,
      applicationNumber: base.applicationNumber,
      status: base.status,
      email: base.email,
      fullName: base.fullName,
      phone: base.phone,
      countryCode: base.countryCode,
      locale: base.locale,
      vehicleTypeCode: base.vehicleTypeCode,
      vehiclePlateNumber: base.vehiclePlateNumber,
      primaryServiceArea: base.primaryServiceArea,
      submittedAt: base.submittedAt,
      reviewedAt: base.reviewedAt,
      phoneCountryCode: json['phoneCountryCode'] as String?,
      drivingLicenseNumber: json['drivingLicenseNumber'] as String? ?? '',
      drivingLicenseCountry: json['drivingLicenseCountry'] as String?,
      drivingLicenseExpiryDate: json['drivingLicenseExpiryDate']?.toString(),
      yearsOfDrivingExperience: json['yearsOfDrivingExperience'] as int? ?? 0,
      vehicleOwnershipType: json['vehicleOwnershipType'] as String? ?? '',
      vehicleMake: json['vehicleMake'] as String?,
      vehicleModel: json['vehicleModel'] as String?,
      vehicleYear: json['vehicleYear'] as int?,
      vehicleColor: json['vehicleColor'] as String?,
      serviceAreas: strings('serviceAreas'),
      languages: strings('languages'),
      notes: json['notes'] as String?,
      bankName: json['bankName'] as String?,
      bankAccountNumber: json['bankAccountNumber'] as String?,
      bankAccountHolder: json['bankAccountHolder'] as String?,
      lineId: json['lineId'] as String?,
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => DriverApplicationAdminFile.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      personalDataConsentAt: json['personalDataConsentAt']?.toString(),
      driverTermsConsentAt: json['driverTermsConsentAt']?.toString(),
      rejectionReason: json['rejectionReason'] as String?,
      adminNote: json['adminNote'] as String?,
      approvedUserId: json['approvedUserId'] as int?,
      approvedDriverId: json['approvedDriverId'] as int?,
      resubmittedFromApplicationId:
          json['resubmittedFromApplicationId'] as int?,
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
      id: json['id'] as int? ?? 0,
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? json['code'] as String? ?? '',
    );
  }
}

class DriverApplicationAdminFile {
  const DriverApplicationAdminFile({
    required this.id,
    required this.category,
    required this.originalFilename,
    required this.mimeType,
    required this.url,
  });

  final int id;
  final String category;
  final String originalFilename;
  final String mimeType;
  final String url;

  factory DriverApplicationAdminFile.fromJson(Map<String, dynamic> json) {
    return DriverApplicationAdminFile(
      id: json['id'] as int? ?? 0,
      category: json['category'] as String? ?? '',
      originalFilename: json['originalFilename'] as String? ?? '',
      mimeType: json['mimeType'] as String? ?? '',
      url: json['url'] as String? ?? '',
    );
  }
}
