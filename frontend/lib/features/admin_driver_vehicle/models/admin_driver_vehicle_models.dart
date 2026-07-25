class AdminDriverVehicleFile {
  const AdminDriverVehicleFile({
    required this.id,
    required this.category,
    required this.url,
    this.originalFilename,
    this.mimeType,
  });

  final int id;
  final String category;
  final String url;
  final String? originalFilename;
  final String? mimeType;

  bool get isImage {
    final mime = (mimeType ?? '').toLowerCase();
    if (mime.startsWith('image/')) return true;
    final name = (originalFilename ?? '').toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
  }

  factory AdminDriverVehicleFile.fromJson(Map<String, dynamic> json) {
    return AdminDriverVehicleFile(
      id: (json['id'] as num?)?.toInt() ?? 0,
      category: json['category'] as String? ?? '',
      url: json['url'] as String? ?? '',
      originalFilename: json['originalFilename'] as String?,
      mimeType: json['mimeType'] as String?,
    );
  }
}

class AdminDriverVehicleListItem {
  const AdminDriverVehicleListItem({
    required this.id,
    required this.driverId,
    required this.driverName,
    required this.vehicleTypeCode,
    required this.vehicleTypeName,
    required this.plateNumber,
    required this.isActive,
    required this.approvalStatus,
    required this.submittedAt,
    required this.files,
    this.driverPhone,
    this.modelName,
    this.color,
    this.rejectionReason,
  });

  final int id;
  final int driverId;
  final String driverName;
  final String? driverPhone;
  final String vehicleTypeCode;
  final String vehicleTypeName;
  final String plateNumber;
  final String? modelName;
  final String? color;
  final bool isActive;
  final String approvalStatus;
  final String? rejectionReason;
  final String submittedAt;
  final List<AdminDriverVehicleFile> files;

  factory AdminDriverVehicleListItem.fromJson(Map<String, dynamic> json) {
    return AdminDriverVehicleListItem(
      id: (json['id'] as num?)?.toInt() ?? 0,
      driverId: (json['driverId'] as num?)?.toInt() ?? 0,
      driverName: json['driverName'] as String? ?? '',
      driverPhone: json['driverPhone'] as String?,
      vehicleTypeCode: json['vehicleTypeCode'] as String? ?? '',
      vehicleTypeName: json['vehicleTypeName'] as String? ?? '',
      plateNumber: json['plateNumber'] as String? ?? '',
      modelName: json['modelName'] as String?,
      color: json['color'] as String?,
      isActive: json['isActive'] == true,
      approvalStatus: (json['approvalStatus'] as String? ?? 'PENDING')
          .toUpperCase(),
      rejectionReason: json['rejectionReason'] as String?,
      submittedAt: json['submittedAt']?.toString() ?? '',
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AdminDriverVehicleFile.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
    );
  }
}

class AdminDriverVehicleListResult {
  const AdminDriverVehicleListResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });

  final List<AdminDriverVehicleListItem> items;
  final int total;
  final int page;
  final int pageSize;

  factory AdminDriverVehicleListResult.fromJson(Map<String, dynamic> json) {
    return AdminDriverVehicleListResult(
      items: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) => AdminDriverVehicleListItem.fromJson(
              Map<String, dynamic>.from(item),
            ),
          )
          .toList(growable: false),
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      pageSize: (json['page_size'] as num?)?.toInt() ??
          (json['pageSize'] as num?)?.toInt() ??
          20,
    );
  }
}
