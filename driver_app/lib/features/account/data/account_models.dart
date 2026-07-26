class DriverProfile {
  const DriverProfile({
    required this.name,
    required this.phone,
    required this.email,
    this.avatarUrl,
    this.vehicle,
  });

  final String name;
  final String phone;
  final String email;
  final String? avatarUrl;
  final DriverProfileVehicle? vehicle;

  factory DriverProfile.fromJson(Map<String, dynamic> json) {
    final vehicle = json['vehicle'];
    return DriverProfile(
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String?,
      vehicle: vehicle is Map
          ? DriverProfileVehicle.fromJson(Map<String, dynamic>.from(vehicle))
          : null,
    );
  }
}

class DriverProfileVehicle {
  const DriverProfileVehicle({
    this.typeCode,
    this.typeName,
    this.modelName,
    this.plateNumber,
    this.color,
    this.year,
    this.photoUrl,
  });

  final String? typeCode;
  final String? typeName;
  final String? modelName;
  final String? plateNumber;
  final String? color;
  final int? year;
  final String? photoUrl;

  factory DriverProfileVehicle.fromJson(Map<String, dynamic> json) =>
      DriverProfileVehicle(
        typeCode: json['typeCode'] as String?,
        typeName: json['typeName'] as String?,
        modelName: json['modelName'] as String?,
        plateNumber: json['plateNumber'] as String?,
        color: json['color'] as String?,
        year: (json['year'] as num?)?.toInt(),
        photoUrl: json['photoUrl'] as String?,
      );
}

class RatingSummary {
  const RatingSummary({required this.averageRating, required this.reviewCount});

  final double? averageRating;
  final int reviewCount;

  factory RatingSummary.fromJson(Map<String, dynamic> json) => RatingSummary(
    averageRating: (json['averageRating'] as num?)?.toDouble(),
    reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
  );
}

class DriverVehicle {
  const DriverVehicle({
    required this.id,
    required this.vehicleTypeId,
    required this.vehicleTypeCode,
    required this.vehicleTypeName,
    required this.plateNumber,
    required this.isPrimary,
    required this.isActive,
    required this.approvalStatus,
    required this.documentCounts,
    this.modelName,
    this.color,
    this.rejectionReason,
  });

  final int id;
  final int vehicleTypeId;
  final String vehicleTypeCode;
  final String vehicleTypeName;
  final String plateNumber;
  final String? modelName;
  final String? color;
  final bool isPrimary;
  final bool isActive;
  final String approvalStatus;
  final String? rejectionReason;
  final VehicleDocumentCounts documentCounts;

  factory DriverVehicle.fromJson(Map<String, dynamic> json) => DriverVehicle(
    id: (json['id'] as num?)?.toInt() ?? 0,
    vehicleTypeId: (json['vehicleTypeId'] as num?)?.toInt() ?? 0,
    vehicleTypeCode: json['vehicleTypeCode'] as String? ?? '',
    vehicleTypeName: json['vehicleTypeName'] as String? ?? '',
    plateNumber: json['plateNumber'] as String? ?? '',
    modelName: json['modelName'] as String?,
    color: json['color'] as String?,
    isPrimary: json['isPrimary'] == true,
    isActive: json['isActive'] == true,
    approvalStatus: json['approvalStatus'] as String? ?? 'APPROVED',
    rejectionReason: json['rejectionReason'] as String?,
    documentCounts: VehicleDocumentCounts.fromJson(
      Map<String, dynamic>.from(json['documentCounts'] as Map? ?? const {}),
    ),
  );
}

class VehicleDocumentCounts {
  const VehicleDocumentCounts({
    required this.vehiclePhotos,
    required this.insuranceCertificate,
    required this.vehicleRegistration,
    required this.taxCertificate,
  });

  final int vehiclePhotos;
  final int insuranceCertificate;
  final int vehicleRegistration;
  final int taxCertificate;

  factory VehicleDocumentCounts.fromJson(
    Map<String, dynamic> json,
  ) => VehicleDocumentCounts(
    vehiclePhotos: (json['vehiclePhotos'] as num?)?.toInt() ?? 0,
    insuranceCertificate: (json['insuranceCertificate'] as num?)?.toInt() ?? 0,
    vehicleRegistration: (json['vehicleRegistration'] as num?)?.toInt() ?? 0,
    taxCertificate: (json['taxCertificate'] as num?)?.toInt() ?? 0,
  );
}

class AccountUploadFile {
  const AccountUploadFile({required this.filename, required this.bytes});

  final String filename;
  final List<int> bytes;
}

class VehicleCreateRequest {
  const VehicleCreateRequest({
    required this.vehicleTypeId,
    required this.plateNumber,
    required this.vehiclePhotos,
    required this.insuranceCertificate,
    required this.vehicleRegistration,
    this.modelName,
    this.color,
  });

  final int vehicleTypeId;
  final String plateNumber;
  final String? modelName;
  final String? color;
  final List<AccountUploadFile> vehiclePhotos;
  final AccountUploadFile insuranceCertificate;
  final AccountUploadFile vehicleRegistration;
}

class VehicleTypeOption {
  const VehicleTypeOption({
    required this.id,
    required this.code,
    required this.name,
  });

  final int id;
  final String code;
  final String name;

  factory VehicleTypeOption.fromJson(Map<String, dynamic> json) =>
      VehicleTypeOption(
        id: (json['id'] as num?)?.toInt() ?? 0,
        code: json['code'] as String? ?? '',
        name: json['name'] as String? ?? '',
      );
}
